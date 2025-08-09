#
# Copyright contributors to the StreamSets project
# StreamSets Inc., an IBM Company 2024
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

ARG BASE_IMAGE=ubuntu:22.04
FROM $BASE_IMAGE

USER 0

# Set environment variables to avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=GMT

RUN apt-get update && \
    apt-get install -y \
        apache2-utils \
        hostname \
        krb5-user \
        iputils-ping \
        psmisc \
        sudo \
        wget \
        unzip \
        curl \
        ca-certificates \
        gnupg \
        lsb-release \
        file \
        openjdk-17-jre-headless \
        && \
    # Ensure Java cert directory exists and has correct permissions
    mkdir -p /etc/ssl/certs/java && \
    chmod 755 /etc/ssl/certs/java && \
    # Install Java certificates package
    apt-get install -y ca-certificates-java && \
    # Force reconfigure Java certificates to fix any issues
    dpkg-reconfigure -f noninteractive ca-certificates-java && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ARG JDK_VERSION=17
RUN set -e; \
    if [ $JDK_VERSION = 8 ]; then \
        apt-get update && \
        apt-get install -y openjdk-8-jdk-headless && \
        update-alternatives --set java /usr/lib/jvm/java-8-openjdk-$(dpkg --print-architecture)/jre/bin/java && \
        apt-get clean && \
        rm -rf /var/lib/apt/lists/*; \
    fi

# Set Java environment with architecture detection
RUN ARCH=$(dpkg --print-architecture) && \
    echo "JAVA_HOME=/usr/lib/jvm/java-17-openjdk-${ARCH}" >> /etc/environment
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
ENV PATH="${JAVA_HOME}/bin:${PATH}"

# Update JAVA_HOME for the correct architecture at runtime
RUN ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "arm64" ]; then \
        sed -i 's/java-17-openjdk-amd64/java-17-openjdk-arm64/g' /etc/environment; \
    fi

# Marker for transition between base image and application image for CVE scanning
ARG LAYER_NAME=application-image

# Configure DNS resolution priority
RUN echo 'hosts: files mdns4_minimal [NOTFOUND=return] dns mdns4' >> /etc/nsswitch.conf

# Set up GMT as the default timezone to maintain compatibility
RUN ln -sf /usr/share/zoneinfo/GMT /etc/localtime && \
    echo "GMT" > /etc/timezone

# Install protobuf-compiler - Multi-architecture support
RUN ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "amd64" ]; then \
        PROTOC_ARCH="x86_64"; \
    elif [ "$ARCH" = "arm64" ]; then \
        PROTOC_ARCH="aarch_64"; \
    else \
        echo "Architecture $ARCH is not supported for protoc" && exit 1; \
    fi && \
    curl -LO "https://github.com/protocolbuffers/protobuf/releases/download/v25.1/protoc-25.1-linux-${PROTOC_ARCH}.zip" && \
    unzip "protoc-25.1-linux-${PROTOC_ARCH}.zip" -d /usr/local && \
    rm "protoc-25.1-linux-${PROTOC_ARCH}.zip" && \
    chmod +x /usr/local/bin/protoc

# We set a UID/GID for the SDC user because certain test environments require these to be consistent throughout
# the cluster. We use 20159 because it's above the default value of YARN's min.user.id property.
ARG SDC_UID=20159
ARG SDC_GID=20159

# Begin Data Collector installation
ARG SDC_VERSION=4.4.0
ARG SDC_URL=https://archives.streamsets.com/datacollector/${SDC_VERSION}/tarball/streamsets-datacollector-core-${SDC_VERSION}.tgz
ARG SDC_USER=sdc
# SDC_HOME is where executables and related files are installed. Used in setup_mapr script.
ARG SDC_HOME="/opt/streamsets-datacollector-${SDC_VERSION}"

# The paths below should generally be attached to a VOLUME for persistence.
# SDC_CONF is where configuration files are stored. This can be shared.
# SDC_DATA is a volume for storing collector state. Do not share this between containers.
# SDC_LOG is an optional volume for file based logs.
# SDC_RESOURCES is where resource files such as runtime:conf resources and Hadoop configuration can be placed.
# STREAMSETS_LIBRARIES_EXTRA_DIR is where extra libraries such as JDBC drivers should go.
# USER_LIBRARIES_DIR is where custom stage libraries are installed.
ENV SDC_CONF=/etc/sdc \
    SDC_DATA=/data \
    SDC_DIST=${SDC_HOME} \
    SDC_HOME=${SDC_HOME} \
    SDC_LOG=/logs \
    SDC_RESOURCES=/resources \
    USER_LIBRARIES_DIR=/opt/streamsets-datacollector-user-libs
ENV STREAMSETS_LIBRARIES_EXTRA_DIR="${SDC_DIST}/streamsets-libs-extras"

ENV SDC_JAVA_OPTS="-Dfile.encoding=UTF-8 -Dsun.jnu.encoding=UTF-8 -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0"

# Download and install StreamSets Data Collector with robust error handling
RUN set -e && \
    echo "=== StreamSets Data Collector Installation ===" && \
    \
    # Check if SDC dist already exists, if not create its artifact of things.
    if [ ! -d "${SDC_DIST}" ]; then \
        echo "Checking network connectivity..." && \
        curl -s --max-time 10 --head https://www.google.com > /dev/null && \
        echo "Network connectivity verified" && \
        \
        # Try multiple download URLs sequentially
        DOWNLOAD_SUCCESS=false && \
        \
        # Try URL 1: Primary archive URL
        echo "Trying primary URL: ${SDC_URL}" && \
        if curl -s --max-time 30 --head "${SDC_URL}" > /dev/null; then \
            echo "Primary URL is accessible" && \
            for attempt in 1 2 3; do \
                echo "Download attempt $attempt/3 from primary URL..." && \
                rm -f /tmp/sdc.tgz && \
                if curl -L --retry 3 --retry-delay 5 --max-time 600 --connect-timeout 30 --fail --show-error --progress-bar -o /tmp/sdc.tgz "${SDC_URL}"; then \
                    if [ -f /tmp/sdc.tgz ]; then \
                        file_size=$(stat -c%s /tmp/sdc.tgz 2>/dev/null || echo "0") && \
                        echo "File size: $file_size bytes" && \
                        if [ "$file_size" -gt 52428800 ]; then \
                            if file /tmp/sdc.tgz | grep -q "gzip compressed"; then \
                                if tar -tzf /tmp/sdc.tgz > /dev/null 2>&1; then \
                                    echo "Primary URL download validation successful" && \
                                    DOWNLOAD_SUCCESS=true && \
                                    break; \
                                fi; \
                            fi; \
                        fi; \
                    fi; \
                    rm -f /tmp/sdc.tgz; \
                fi && \
                if [ $attempt -lt 3 ]; then sleep 5; fi; \
            done; \
        else \
            echo "Primary URL not accessible"; \
        fi && \
        \
        # Try URL 2: Maven Central mirror if first failed
        if [ "$DOWNLOAD_SUCCESS" = false ]; then \
            ALT_URL="https://repo1.maven.org/maven2/com/streamsets/streamsets-datacollector-core/${SDC_VERSION}/streamsets-datacollector-core-${SDC_VERSION}.tgz" && \
            echo "Trying Maven Central URL: $ALT_URL" && \
            if curl -s --max-time 30 --head "$ALT_URL" > /dev/null; then \
                echo "Maven Central URL is accessible" && \
                for attempt in 1 2 3; do \
                    echo "Download attempt $attempt/3 from Maven Central..." && \
                    rm -f /tmp/sdc.tgz && \
                    if curl -L --retry 3 --retry-delay 5 --max-time 600 --connect-timeout 30 --fail --show-error --progress-bar -o /tmp/sdc.tgz "$ALT_URL"; then \
                        if [ -f /tmp/sdc.tgz ]; then \
                            file_size=$(stat -c%s /tmp/sdc.tgz 2>/dev/null || echo "0") && \
                            echo "File size: $file_size bytes" && \
                            if [ "$file_size" -gt 52428800 ]; then \
                                if file /tmp/sdc.tgz | grep -q "gzip compressed"; then \
                                    if tar -tzf /tmp/sdc.tgz > /dev/null 2>&1; then \
                                        echo "Maven Central download validation successful" && \
                                        DOWNLOAD_SUCCESS=true && \
                                        break; \
                                    fi; \
                                fi; \
                            fi; \
                        fi; \
                        rm -f /tmp/sdc.tgz; \
                    fi && \
                    if [ $attempt -lt 3 ]; then sleep 5; fi; \
                done; \
            else \
                echo "Maven Central URL not accessible"; \
            fi; \
        fi && \
        \
        # Try URL 3: GitHub releases as last resort
        if [ "$DOWNLOAD_SUCCESS" = false ]; then \
            GITHUB_URL="https://github.com/streamsets/datacollector/releases/download/streamsets-datacollector-core-${SDC_VERSION}/streamsets-datacollector-core-${SDC_VERSION}.tgz" && \
            echo "Trying GitHub releases URL: $GITHUB_URL" && \
            if curl -s --max-time 30 --head "$GITHUB_URL" > /dev/null; then \
                echo "GitHub URL is accessible" && \
                for attempt in 1 2 3; do \
                    echo "Download attempt $attempt/3 from GitHub..." && \
                    rm -f /tmp/sdc.tgz && \
                    if curl -L --retry 3 --retry-delay 5 --max-time 600 --connect-timeout 30 --fail --show-error --progress-bar -o /tmp/sdc.tgz "$GITHUB_URL"; then \
                        if [ -f /tmp/sdc.tgz ]; then \
                            file_size=$(stat -c%s /tmp/sdc.tgz 2>/dev/null || echo "0") && \
                            echo "File size: $file_size bytes" && \
                            if [ "$file_size" -gt 52428800 ]; then \
                                if file /tmp/sdc.tgz | grep -q "gzip compressed"; then \
                                    if tar -tzf /tmp/sdc.tgz > /dev/null 2>&1; then \
                                        echo "GitHub download validation successful" && \
                                        DOWNLOAD_SUCCESS=true && \
                                        break; \
                                    fi; \
                                fi; \
                            fi; \
                        fi; \
                        rm -f /tmp/sdc.tgz; \
                    fi && \
                    if [ $attempt -lt 3 ]; then sleep 5; fi; \
                done; \
            else \
                echo "GitHub URL not accessible"; \
            fi; \
        fi && \
        \
        # Check if we have a valid file
        if [ "$DOWNLOAD_SUCCESS" = false ]; then \
            echo "FATAL: Failed to download valid StreamSets Data Collector from any URL" && \
            exit 1; \
        fi && \
        \
        # Extract the archive
        echo "Creating SDC directory: ${SDC_DIST}" && \
        mkdir -p "${SDC_DIST}" && \
        echo "Extracting StreamSets Data Collector..." && \
        tar xzf /tmp/sdc.tgz --strip-components 1 -C "${SDC_DIST}" && \
        rm -f /tmp/sdc.tgz && \
        echo "Extraction completed successfully" && \
        \
        # Move configuration to /etc/sdc
        mv "${SDC_DIST}/etc" "${SDC_CONF}" && \
        echo "Configuration moved to ${SDC_CONF}"; \
    else \
        echo "SDC_DIST already exists: ${SDC_DIST}"; \
    fi && \
    \
    # Configure users and permissions
    echo "Configuring users and permissions..." && \
    \
    # SDC-11575 -- support for arbitrary userIds as per OpenShift
    if ! getent group ${SDC_GID} > /dev/null 2>&1; then \
        groupadd --system --gid ${SDC_GID} ${SDC_USER}; \
    fi && \
    \
    if ! getent passwd ${SDC_UID} > /dev/null 2>&1; then \
        adduser --system --uid ${SDC_UID} --gid ${SDC_GID} ${SDC_USER}; \
    fi && \
    \
    usermod -aG root ${SDC_USER} && \
    chgrp -R 0 "${SDC_DIST}" "${SDC_CONF}" && \
    chmod -R g=u "${SDC_DIST}" "${SDC_CONF}" && \
    # setgid bit on conf dir to preserve group on sed -i
    chmod g+s "${SDC_CONF}" && \
    chmod g=u /etc/passwd && \
    \
    # Update /etc/sudoers to include SDC user.
    echo "${SDC_USER} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers && \
    \
    # Add logging to stdout to make logs visible through `docker logs`.
    if [ -f "${SDC_CONF}/sdc-log4j.properties" ]; then \
        sed -i 's|INFO, streamsets|INFO, streamsets,stdout|' "${SDC_CONF}/sdc-log4j.properties"; \
    elif [ -f "${SDC_CONF}/sdc-log4j2.properties" ]; then \
        sed -i 's|rootLogger.appenderRef.streamsets.ref = streamsets|rootLogger.appenderRef.streamsets.ref = streamsets\nrootLogger.appenderRef.stdout.ref = stdout|' "${SDC_CONF}/sdc-log4j2.properties"; \
    fi && \
    \
    # Workaround to address SDC-8005.
    if [ -d "${SDC_DIST}/user-libs" ]; then \
        cp -R "${SDC_DIST}/user-libs" "${USER_LIBRARIES_DIR}"; \
    fi && \
    \
    # Create necessary directories.
    mkdir -p /mnt \
        "${SDC_DATA}" \
        "${SDC_LOG}" \
        "${SDC_RESOURCES}" \
        "${USER_LIBRARIES_DIR}" && \
    \
    chgrp -R 0 "${SDC_RESOURCES}" "${USER_LIBRARIES_DIR}" "${SDC_LOG}" "${SDC_DATA}" && \
    chmod -R g=u "${SDC_RESOURCES}" "${USER_LIBRARIES_DIR}" "${SDC_LOG}" "${SDC_DATA}" && \
    \
    # Update sdc-security.policy to include the custom stage library directory.
    echo "" >> "${SDC_CONF}/sdc-security.policy" && \
    echo "// custom stage library directory" >> "${SDC_CONF}/sdc-security.policy" && \
    echo "grant codebase \"file:///opt/streamsets-datacollector-user-libs/-\" {" >> "${SDC_CONF}/sdc-security.policy" && \
    echo "  permission java.security.AllPermission;" >> "${SDC_CONF}/sdc-security.policy" && \
    echo "};" >> "${SDC_CONF}/sdc-security.policy" && \
    \
    # Use short option -s as long option --status is not supported on alpine linux.
    sed -i 's|--status|-s|' "${SDC_DIST}/libexec/_stagelibs" && \
    \
    # Set distribution channel variable
    sed -i '/^export SDC_DISTRIBUTION_CHANNEL=*/d' "${SDC_DIST}/libexec/sdcd-env.sh" && \
    sed -i '/^export SDC_DISTRIBUTION_CHANNEL=*/d' "${SDC_DIST}/libexec/sdc-env.sh" && \
    echo -e "\nexport SDC_DISTRIBUTION_CHANNEL=docker" >> ${SDC_DIST}/libexec/sdc-env.sh && \
    echo -e "\nexport SDC_DISTRIBUTION_CHANNEL=docker" >> ${SDC_DIST}/libexec/sdcd-env.sh && \
    \
    # Needed for OpenShift deployment
    sed -i 's/http.realm.file.permission.check=true/http.realm.file.permission.check=false/' ${SDC_CONF}/sdc.properties && \
    \
    # Create VERSION file
    echo "${SDC_VERSION}" > "${SDC_DIST}/VERSION" && \
    \
    echo "StreamSets Data Collector installation completed successfully"

# Install any additional stage libraries if requested
ARG SDC_LIBS
RUN if [ -n "${SDC_LIBS}" ]; then "${SDC_DIST}/bin/streamsets" stagelibs -install="${SDC_LIBS}"; fi

# Copy files in $PROJECT_ROOT/resources dir to the SDC_RESOURCES dir.
COPY resources/ ${SDC_RESOURCES}/
RUN chown -R sdc:sdc ${SDC_RESOURCES}/

# Copy local "sdc-extras" libs to STREAMSETS_LIBRARIES_EXTRA_DIR.
# Local files should be placed in appropriate stage lib subdirectories.  For example
# to add a JDBC driver like my-jdbc.jar to the JDBC stage lib, the local file my-jdbc.jar
# should be at the location $PROJECT_ROOT/sdc-extras/streamsets-datacollector-jdbc-lib/lib/my-jdbc.jar
COPY sdc-extras/ ${STREAMSETS_LIBRARIES_EXTRA_DIR}/
RUN chown -R sdc:sdc ${STREAMSETS_LIBRARIES_EXTRA_DIR}/

# Create symlink of custom certs for compatibility between jre and jdk file paths
RUN /bin/bash -c 'if [[ ${JDK_VERSION} =~ ^8 ]]; then ln -snf ${JAVA_HOME}/jre/lib/security ${JAVA_HOME}/lib/security; fi'

# Create Flight libs symlink
RUN sudo ln -s ${SDC_DIST}/flightservice/opt/ibm /opt/ibm

USER ${SDC_USER}
EXPOSE 18630
COPY docker-entrypoint.sh /
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["dc"]
