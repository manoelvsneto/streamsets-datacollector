FROM eclipse-temurin:11-jre-jammy

# utilitários mínimos
RUN apt-get update && apt-get install -y curl ca-certificates bash && rm -rf /var/lib/apt/lists/*

WORKDIR /opt
ENV SDC_VERSION=6.1.1

# baixa e instala o SDC
RUN curl -fsSL -o sdc.tgz https://archives.streamsets.com/datacollector/${SDC_VERSION}/tarball/activation/streamsets-datacollector-core-${SDC_VERSION}.tgz \
 && tar -xzf sdc.tgz \
 && (mv streamsets-datacollector-core-${SDC_VERSION} streamsets || mv streamsets-datacollector-${SDC_VERSION} streamsets) \
 && rm sdc.tgz \
 && chmod +x /opt/streamsets/bin/streamsets

EXPOSE 18630 18631
ENTRYPOINT ["/opt/streamsets/bin/streamsets","dc"]
