#
# StreamSets Data Collector - Dockerfile Completo e Robusto
# Versão única que incorpora toda a lógica de download e configuração
#

ARG BASE_IMAGE=ubuntu:22.04
FROM $BASE_IMAGE

# Set environment variables to avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=GMT

# Install system dependencies in correct order
USER 0
RUN apt-get update && \
    # Install basic utilities first
    apt-get install -y \
        curl \
        wget \
        unzip \
        sudo \
        hostname \
        iputils-ping \
        traceroute \
        psmisc \
        gnupg \
        lsb-release \
        ca-certificates \
        file \
        xxd \
        && \
    # Install Java JRE
    apt-get install -y openjdk-17-jre-headless && \
    # Ensure Java cert directory exists and has correct permissions
    mkdir -p /etc/ssl/certs/java && \
    chmod 755 /etc/ssl/certs/java && \
    # Install Java certificates package
    apt-get install -y ca-certificates-java && \
    # Force reconfigure Java certificates to fix any issues
    dpkg-reconfigure -f noninteractive ca-certificates-java && \
    # Install additional packages
    apt-get install -y \
        krb5-user \
        apache2-utils \
        && \
    # Clean up
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Verify Java installation and certificates
RUN java -version && \
    ls -la /etc/ssl/certs/java/ && \
    keytool -list -keystore /etc/ssl/certs/java/cacerts -storepass changeit | head -10

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

ARG JDK_VERSION=17
RUN set -e; \
    if [ $JDK_VERSION = 8 ]; then \
        apt-get update && \
        apt-get install -y openjdk-8-jdk-headless && \
        update-alternatives --set java /usr/lib/jvm/java-8-openjdk-$(dpkg --print-architecture)/jre/bin/java && \
        apt-get clean && \
        rm -rf /var/lib/apt/lists/*; \
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
ARG SDC_VERSION=6.0.0-SNAPSHOT
ARG SDC_URL=http://nightly.streamsets.com.s3-us-west-2.amazonaws.com/datacollector/latest/tarball/streamsets-datacollector-core-${SDC_VERSION}.tgz
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

# Java options optimized for containers
ENV SDC_JAVA_OPTS="-Dfile.encoding=UTF-8 -Dsun.jnu.encoding=UTF-8 -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0"

# Download and install StreamSets Data Collector with robust error handling
RUN set -e && \
    echo "=== StreamSets Data Collector Installation ===" && \
    \
    # Check if SDC dist already exists, if not create its artifact of things.
    if [ ! -d "${SDC_DIST}" ]; then \
        echo "Checking network connectivity..." && \
        curl -s --max-time 10 --head https://www.google.com > /dev/null && \
        curl -s --max-time 30 --head "${SDC_URL}" > /dev/null && \
        echo "Network connectivity verified" && \
        \
        # Download with retry logic
        for attempt in 1 2 3; do \
            echo "Download attempt $attempt/3..." && \
            rm -f /tmp/sdc.tgz && \
            if curl -L \
                --retry 3 \
                --retry-delay 5 \
                --max-time 600 \
                --connect-timeout 30 \
                --fail \
                --show-error \
                --progress-bar \
                -o /tmp/sdc.tgz \
                "${SDC_URL}"; then \
                \
                echo "Download completed, validating file..." && \
                \
                # Validate downloaded file
                if [ -f /tmp/sdc.tgz ]; then \
                    file_size=$(stat -c%s /tmp/sdc.tgz 2>/dev/null || stat -f%z /tmp/sdc.tgz 2>/dev/null || echo "0") && \
                    echo "File size: $file_size bytes" && \
                    \
                    if [ "$file_size" -gt 104857600 ]; then \
                        if file /tmp/sdc.tgz | grep -q "gzip compressed"; then \
                            if tar -tzf /tmp/sdc.tgz > /dev/null 2>&1; then \
                                echo "File validation successful" && \
                                break; \
                            else \
                                echo "File validation failed: corrupted tar archive"; \
                            fi; \
                        else \
                            echo "File validation failed: not a gzip file" && \
                            file /tmp/sdc.tgz; \
                        fi; \
                    else \
                        echo "File validation failed: file too small (< 100MB)"; \
                    fi; \
                else \
                    echo "File validation failed: file does not exist"; \
                fi && \
                rm -f /tmp/sdc.tgz; \
            else \
                echo "Download failed (attempt $attempt)"; \
            fi && \
            \
            if [ $attempt -lt 3 ]; then \
                echo "Waiting 10 seconds before retry..." && \
                sleep 10; \
            fi; \
        done && \
        \
        # Check if we have a valid file
        if [ ! -f /tmp/sdc.tgz ]; then \
            echo "FATAL: Failed to download valid StreamSets Data Collector after 3 attempts" && \
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
RUN if [ -n "${SDC_LIBS}" ]; then \
        echo "Installing stage libraries: ${SDC_LIBS}" && \
        "${SDC_DIST}/bin/streamsets" stagelibs -install="${SDC_LIBS}" && \
        echo "Stage libraries installed successfully"; \
    else \
        echo "No additional stage libraries specified"; \
    fi

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
RUN if [ -d "${SDC_DIST}/flightservice/opt/ibm" ]; then \
        sudo ln -s ${SDC_DIST}/flightservice/opt/ibm /opt/ibm; \
    fi

# Final verification
RUN echo "=== Final Installation Verification ===" && \
    ls -la "${SDC_DIST}" && \
    ls -la "${SDC_CONF}" && \
    test -f "${SDC_DIST}/bin/streamsets" && \
    echo "Version: $(cat ${SDC_DIST}/VERSION)" && \
    echo "Installation verified successfully"

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD curl -f http://localhost:18630/ || exit 1

USER ${SDC_USER}
EXPOSE 18630

# Create inline entrypoint script
RUN echo '#!/bin/bash' > /entrypoint.sh && \
    echo 'set -e' >> /entrypoint.sh && \
    echo 'if [ "$1" = "dc" ]; then' >> /entrypoint.sh && \
    echo '    exec "${SDC_DIST}/bin/streamsets" dc' >> /entrypoint.sh && \
    echo 'else' >> /entrypoint.sh && \
    echo '    exec "$@"' >> /entrypoint.sh && \
    echo 'fi' >> /entrypoint.sh && \
    chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["dc"]

# Add labels
LABEL org.label-schema.name="StreamSets Data Collector" \
      org.label-schema.description="StreamSets Data Collector on Ubuntu 22.04 with robust download handling" \
      org.label-schema.version="${SDC_VERSION}" \
      org.label-schema.vendor="StreamSets Inc." \
      build.arch="amd64,arm64" \
      build.validated="true" \
      build.type="production"
