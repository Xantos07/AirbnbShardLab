###############################################################################
# Dockerfile → MongoDB 6.0 + BI Connector v2.14.22 (mongosqld) sur Ubuntu 22.04
###############################################################################

# 1) Base image officielle Mongo 6.0 (Ubuntu 22.04 « jammy »)
FROM mongo:6.0

# 2) Désactiver les invites apt
ENV DEBIAN_FRONTEND=noninteractive

# 3) Installer les dépendances pour BI Connector (jammy)
RUN apt-get update && \
    apt-get install -y \
      wget \
      ca-certificates \
      libssl3 \
      libssl-dev \
      libgssapi-krb5-2 \
      mongodb-org-shell && \
    rm -rf /var/lib/apt/lists/*

# 4) Créer un dossier de travail pour télécharger le BI Connector
WORKDIR /home/mongobi

# 5) Télécharger et extraire le BI Connector v2.14.22 pour Ubuntu 22.04
ARG BI_CONNECTOR_VERSION=2.14.22
RUN wget https://info-mongodb-com.s3.amazonaws.com/mongodb-bi/v2/mongodb-bi-linux-x86_64-ubuntu2204-v${BI_CONNECTOR_VERSION}.tgz && \
    tar -xzf mongodb-bi-linux-x86_64-ubuntu2204-v${BI_CONNECTOR_VERSION}.tgz && \
    mv mongodb-bi-linux-x86_64-ubuntu2204-v${BI_CONNECTOR_VERSION} /opt/mongodb-bi && \
    rm mongodb-bi-linux-x86_64-ubuntu2204-v${BI_CONNECTOR_VERSION}.tgz

# 6) Copier le script d’entrée et, si besoin, le fichier de config mongosqld.conf
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

#    Si vous n’utilisez pas de fichier YAML, vous pouvez supprimer la ligne suivante.
#  COPY mongosqld.conf /home/mongobi/mongosqld.conf

# 7) Installer le binaire mongosqld dans /usr/local/bin
RUN install -m755 /opt/mongodb-bi/bin/mongosqld /usr/local/bin/mongosqld

# 8) Volume pour les données MongoDB + exposition des ports
VOLUME /data/db
EXPOSE 27017
EXPOSE 3307

# 9) Entrypoint & CMD
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["mongod"]
