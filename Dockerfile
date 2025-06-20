# Base image officielle Mongo 6.0
FROM mongo:6.0

# Désactiver les invites apt
ENV DEBIAN_FRONTEND=noninteractive

# Installation des dépendances pour BI Connector
RUN apt-get update && \
    apt-get install -y \
      wget \
      ca-certificates \
      libssl3 \
      libssl-dev \
      libgssapi-krb5-2 \
      mongodb-org-shell && \
    rm -rf /var/lib/apt/lists/*

# Création d'un dossier de travail pour télécharger le BI Connector
WORKDIR /home/mongobi

# Télécharge et extraie le BI Connector v2.14.22 pour Ubuntu 22.04
ARG BI_CONNECTOR_VERSION=2.14.22
RUN wget https://info-mongodb-com.s3.amazonaws.com/mongodb-bi/v2/mongodb-bi-linux-x86_64-ubuntu2204-v${BI_CONNECTOR_VERSION}.tgz && \
    tar -xzf mongodb-bi-linux-x86_64-ubuntu2204-v${BI_CONNECTOR_VERSION}.tgz && \
    mv mongodb-bi-linux-x86_64-ubuntu2204-v${BI_CONNECTOR_VERSION} /opt/mongodb-bi && \
    rm mongodb-bi-linux-x86_64-ubuntu2204-v${BI_CONNECTOR_VERSION}.tgz

# Copie le script d’entrée et config mongosqld.conf
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Installer le binaire mongosqld dans /usr/local/bin
RUN install -m755 /opt/mongodb-bi/bin/mongosqld /usr/local/bin/mongosqld

# Volume pour les données MongoDB + exposition des ports
VOLUME /data/db
EXPOSE 27017
EXPOSE 3307

# Entrypoint & CMD
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["mongod"]
