#!/usr/bin/env bash
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
set -e
set -x

echo "🚀 Iniciando configuração do StreamSets Data Collector..."
echo "📂 SDC_DIST: ${SDC_DIST}"
echo "📂 SDC_CONF: ${SDC_CONF}"
echo "🌐 SDC_URL: ${SDC_URL}"

# Check if SDC dist already exists, if not create its artifact of things.
if [ ! -d "${SDC_DIST}" ]; then
    echo "📦 Diretório SDC não existe, criando..."

    # Try to find existing tgz file first
    TGZ_FOUND=false
    for f in /tmp/*.tgz; do
        if [ -e "$f" ]; then
            echo "✅ Arquivo .tgz encontrado: $f"
            mv "$f" /tmp/sdc.tgz
            TGZ_FOUND=true
            break
        fi
    done

    # If no tgz file found, download it
    if [ "$TGZ_FOUND" = false ]; then
        echo "📥 Nenhum arquivo .tgz encontrado, fazendo download..."
        echo "🌐 URL: ${SDC_URL}"
        
        # Test network connectivity
        if command -v curl >/dev/null 2>&1; then
            echo "✅ curl está disponível"
        else
            echo "❌ curl não está disponível"
            exit 1
        fi
        
        # Try to download with retries
        RETRY_COUNT=3
        for i in $(seq 1 $RETRY_COUNT); do
            echo "🔄 Tentativa $i de $RETRY_COUNT..."
            if curl -f -L --connect-timeout 30 --max-time 300 -o /tmp/sdc.tgz "${SDC_URL}"; then
                echo "✅ Download concluído com sucesso"
                break
            else
                echo "❌ Falha no download (tentativa $i)"
                if [ $i -eq $RETRY_COUNT ]; then
                    echo "💥 Todas as tentativas de download falharam"
                    exit 1
                fi
                sleep 5
            fi
        done
    fi

    # Verify the downloaded file
    if [ ! -f "/tmp/sdc.tgz" ]; then
        echo "❌ Arquivo /tmp/sdc.tgz não encontrado"
        exit 1
    fi

    # Check file size
    FILE_SIZE=$(stat -c%s "/tmp/sdc.tgz" 2>/dev/null || stat -f%z "/tmp/sdc.tgz" 2>/dev/null || echo "0")
    echo "📏 Tamanho do arquivo: $FILE_SIZE bytes"
    
    if [ "$FILE_SIZE" -lt 10000 ]; then
        echo "❌ Arquivo muito pequeno, provavelmente corrompido"
        echo "📝 Conteúdo do arquivo:"
        head -20 /tmp/sdc.tgz || true
        exit 1
    fi

    # Test if file is a valid gzip
    echo "🔍 Verificando se é um arquivo gzip válido..."
    if file /tmp/sdc.tgz | grep -q "gzip"; then
        echo "✅ Arquivo gzip válido"
    else
        echo "❌ Arquivo não é um gzip válido"
        echo "📝 Tipo do arquivo:"
        file /tmp/sdc.tgz || true
        echo "📝 Primeiros bytes do arquivo:"
        head -c 100 /tmp/sdc.tgz | xxd || hexdump -C /tmp/sdc.tgz | head -5 || true
        exit 1
    fi

    # Create destination directory
    echo "📁 Criando diretório ${SDC_DIST}..."
    mkdir -p "${SDC_DIST}"
    
    # Extract the archive
    echo "📦 Extraindo arquivo..."
    if tar xzf /tmp/sdc.tgz --strip-components 1 -C "${SDC_DIST}"; then
        echo "✅ Extração concluída com sucesso"
    else
        echo "❌ Falha na extração"
        echo "📝 Listando conteúdo do arquivo:"
        tar tzf /tmp/sdc.tgz | head -10 || true
        exit 1
    fi
    
    # Clean up
    rm -rf /tmp/sdc.tgz
    echo "🧹 Arquivo temporário removido"

    # Move configuration to /etc/sdc
    echo "⚙️ Movendo configuração para ${SDC_CONF}..."
    if [ -d "${SDC_DIST}/etc" ]; then
        mv "${SDC_DIST}/etc" "${SDC_CONF}"
        echo "✅ Configuração movida com sucesso"
    else
        echo "⚠️ Diretório etc não encontrado em ${SDC_DIST}"
        echo "📂 Conteúdo de ${SDC_DIST}:"
        ls -la "${SDC_DIST}" || true
    fi
else
    echo "✅ Diretório SDC já existe: ${SDC_DIST}"
fi

echo "👤 Configurando usuário ${SDC_USER}..."

# SDC-11575 -- support for arbitrary userIds as per OpenShift
# We use Apache Hadoop code in file system related stagelibs to lookup the
# current user name, which fails when run in OpenShift.
# It fails because containers in OpenShift run as an ephemeral uid for
# security purposes, and that uid does not show up in /etc/passwd.

# Check if group already exists
if ! getent group ${SDC_USER} >/dev/null 2>&1; then
    echo "👥 Criando grupo ${SDC_USER} com GID ${SDC_GID}..."
    groupadd --system --gid ${SDC_GID} ${SDC_USER}
else
    echo "✅ Grupo ${SDC_USER} já existe"
fi

# Check if user already exists
if ! id ${SDC_USER} >/dev/null 2>&1; then
    echo "👤 Criando usuário ${SDC_USER} com UID ${SDC_UID}..."
    adduser --system --uid ${SDC_UID} --gid ${SDC_GID} ${SDC_USER}
else
    echo "✅ Usuário ${SDC_USER} já existe"
fi

echo "🔐 Configurando permissões..."
usermod -aG root ${SDC_USER} && \
    chgrp -R 0 "${SDC_DIST}" "${SDC_CONF}"  && \
    chmod -R g=u "${SDC_DIST}" "${SDC_CONF}" && \
    # setgid bit on conf dir to preserve group on sed -i
    chmod g+s "${SDC_CONF}" && \
    chmod g+s "${SDC_DIST}/libexec" && \
    chmod g+s "${SDC_CONF}/dpm.properties" && \
    chmod g+s "${SDC_CONF}/ldap-login.conf" && \
    # The following are created at runtime
    mkdir -p /data /logs /resources && \
    chmod 777 /data /logs && \
    chmod 755 /resources

echo "✅ Configuração do StreamSets Data Collector concluída com sucesso!"
echo "📂 SDC_DIST: ${SDC_DIST}"
echo "📂 SDC_CONF: ${SDC_CONF}"
echo "👤 Usuário: ${SDC_USER} (UID: ${SDC_UID}, GID: ${SDC_GID})"
