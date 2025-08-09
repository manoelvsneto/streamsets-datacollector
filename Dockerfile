FROM ubuntu:22.04

# Variável da versão do StreamSets
ARG SDC_VERSION=6.1.1

# Instalação de bibliotecas
RUN apt-get update -y && apt-get install -y ssh rsync net-tools vim openjdk-11-jdk wget

# Variável de ambiente do Java 11 (compatível com StreamSets 3.22.2)
ENV JAVA_HOME=/usr/lib/jvm/java-11-openjdk-arm64

# Inclusão das informações no path
ENV PATH="/usr/lib/jvm/java-11-openjdk-arm64/bin:/opt/hadoop/bin:${PATH}"

# Diretório de trabalho
WORKDIR /opt

# Baixa a aplicação
RUN wget https://archives.streamsets.com/datacollector/${SDC_VERSION}/tarball/activation/streamsets-datacollector-core-${SDC_VERSION}.tgz

# Descompacta
RUN tar -xvzf streamsets-datacollector-core-${SDC_VERSION}.tgz

# Renomeia a pasta
RUN mv streamsets-datacollector-${SDC_VERSION} streamsets

# Deleta arquivo
RUN rm streamsets-datacollector-core-${SDC_VERSION}.tgz

# Executa a aplicação, "dc" significa "Data Collector"
ENTRYPOINT [ "/opt/streamsets/bin/streamsets","dc"]