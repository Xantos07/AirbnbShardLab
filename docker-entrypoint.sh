#!/usr/bin/env bash
set -e

#  Lancer mongod en mode insecure (sans --auth), en arrière-plan
echo "→ Démarrage de mongod en mode insecure (sans auth) pour création de root..."
mongod --bind_ip_all --fork --logpath /var/log/mongod-insecure.log

#  Boucle « ping » jusqu’à ce que le mongod insecure réponde
RET=1
while [ $RET -ne 0 ]; do
  echo "⏳ Attente du mongod insecure…"
  mongosh --quiet --eval "db.adminCommand('ping')" > /dev/null 2>&1 && RET=0 || RET=1
  sleep 1
done
echo "✅ mongod insecure est prêt."

# Créer l’utilisateur root (admin) si nécessaire
echo "→ Vérification / création de l’utilisateur root…"
mongosh admin --eval "
  if (!db.getUser('${MONGO_INITDB_ROOT_USERNAME}')) {
    db.createUser({
      user: '${MONGO_INITDB_ROOT_USERNAME}',
      pwd: '${MONGO_INITDB_ROOT_PASSWORD}',
      roles: [ { role: 'root', db: 'admin' } ]
    });
    print('→ Utilisateur root créé.');
  } else {
    print('→ Utilisateur root déjà existant.');
  }
" > /dev/null

# Arrêter proprement le mongod insecure
echo "→ Arrêt du mongod insecure via mongod --shutdown..."
mongod --dbpath /data/db --shutdown

#  relancer mongod en mode authentifié
echo "→ Relancement de mongod avec --auth..."
mongod --bind_ip_all --auth --fork --logpath /var/log/mongod.log

#  loop jusqu’à ce que le mongod authentifié réponde
RET=1
while [ $RET -ne 0 ]; do
  echo "⏳ Attente du mongod …"
  mongosh --quiet --eval "db.adminCommand('ping')" -u "${MONGO_INITDB_ROOT_USERNAME}" -p "${MONGO_INITDB_ROOT_PASSWORD}" --authenticationDatabase admin > /dev/null 2>&1 && RET=0 || RET=1
  sleep 1
done
echo "✅ mongod est prêt."


#Créer un certificat SSL auto-signé et l'utiliser
echo "→ Création du certificat SSL auto-signé..."
mkdir -p /tmp/ssl
openssl req -newkey rsa:2048 -new -x509 -days 3652 -nodes \
  -out /tmp/ssl/server.crt \
  -keyout /tmp/ssl/server.key \
  -subj "/C=FR/ST=State/L=City/O=Test/CN=localhost"

#combiner clé et certificat
cat /tmp/ssl/server.key /tmp/ssl/server.crt > /tmp/ssl/server.pem

echo "→ Démarrage de mongosqld (BI Connector) avec SSL..."
cat > /tmp/mongosqld.yaml << EOF
net:
  bindIp: "0.0.0.0"
  port: 3307
  ssl:
    mode: "allowSSL"
    PEMKeyFile: "/tmp/ssl/server.pem"
security:
  enabled: true
mongodb:
  net:
    uri: "mongodb://localhost:27017/?authSource=admin"
    auth:
      username: "${MONGO_INITDB_ROOT_USERNAME}"
      password: "${MONGO_INITDB_ROOT_PASSWORD}"
      source: "admin"
EOF

exec mongosqld --config /tmp/mongosqld.yaml