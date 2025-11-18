FROM eclipse-temurin:11-jre-jammy

RUN apt-get update && apt-get install -y curl ca-certificates bash && rm -rf /var/lib/apt/lists/*
WORKDIR /opt
ENV SDC_VERSION=6.1.1
ENV SDC_CONF=/opt/streamsets/etc \
    SDC_DATA=/opt/streamsets/data \
    SDC_LOG=/opt/streamsets/log \
    SDC_RESOURCES=/opt/streamsets/resources


# baixa, extrai, normaliza scripts e dá permissão de execução
RUN curl -fsSL -o sdc.tgz https://archives.streamsets.com/datacollector/${SDC_VERSION}/tarball/activation/streamsets-datacollector-core-${SDC_VERSION}.tgz \
 && tar -xzf sdc.tgz \
 && (mv streamsets-datacollector-core-${SDC_VERSION} streamsets || mv streamsets-datacollector-${SDC_VERSION} streamsets) \
 && rm sdc.tgz \
 && sed -i '1s/^\xEF\xBB\xBF//' /opt/streamsets/bin/streamsets && sed -i 's/\r$//' /opt/streamsets/bin/streamsets \
 && chmod +x /opt/streamsets/bin/streamsets


# Create necessary directories and set permissions
RUN mkdir -p ${SDC_DATA} ${SDC_LOG} ${SDC_RESOURCES} \
 && chmod -R 755 /opt/streamsets

# Configure StreamSets to bind to all interfaces
RUN echo "http.port=18630" >> /opt/streamsets/etc/sdc.properties \
 && echo "https.port=18631" >> /opt/streamsets/etc/sdc.properties

EXPOSE 18630 18631

WORKDIR /opt/streamsets
ENTRYPOINT ["/opt/streamsets/bin/streamsets","dc","-verbose"]

