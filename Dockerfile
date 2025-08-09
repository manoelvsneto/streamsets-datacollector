FROM ubuntu:22.04

# Instalação de bibliotecas
RUN apt-get update -y && apt-get install -y ssh rsync net-tools vim openjdk-11-jdk wget

# Variável de ambiente do Java 11 (compatível com StreamSets 6.x)
ENV JAVA_HOME=/usr/lib/jvm/java-11-openjdk-arm64

# Inclusão das informações no path
ENV PATH="/usr/lib/jvm/java-11-openjdk-arm64/bin:/opt/hadoop/bin:${PATH}"

# Diretório de trabalho
WORKDIR /opt

# Baixa a aplicação StreamSets 6.1.1
RUN wget --tries=5 --retry-connrefused --waitretry=10 --timeout=30 https://archives.streamsets.com/datacollector/6.1.1/tarball/activation/streamsets-datacollector-core-6.1.1.tgz

# Descompacta
RUN tar -xvzf streamsets-datacollector-core-6.1.1.tgz

# Verifica o nome da pasta extraída e renomeia
RUN ls -la && \
    if [ -d "streamsets-datacollector-core-6.1.1" ]; then \
        mv streamsets-datacollector-core-6.1.1 streamsets; \
    elif [ -d "streamsets-datacollector-6.1.1" ]; then \
        mv streamsets-datacollector-6.1.1 streamsets; \
    else \
        echo "Erro: Pasta extraída não encontrada!" && ls -la && exit 1; \
    fi

# Deleta arquivo
RUN rm streamsets-datacollector-core-6.1.1.tgz

# Executa a aplicação, "dc" significa "Data Collector"
ENTRYPOINT [ "/opt/streamsets/bin/streamsets","dc"]