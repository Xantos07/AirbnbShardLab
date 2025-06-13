#!/usr/bin/env bash
set -e

################################################################################
# Script d’entrée pour MongoDB + BI Connector (mongosqld)
#
# 1) Démarrer 'mongod' sans auth (fork)
# 2) Attendre que MongoDB insecure soit prêt (ping)
# 3) Créer l’utilisateur root (admin) si nécessaire
# 4) Arrêter MongoDB insecure via 'mongod --shutdown'
# 5) Relancer 'mongod' avec --auth (fork)
# 6) Attendre que mongod authentifié soit prêt (ping)
# 7) Lancer 'mongosqld' (BI Connector) au premier plan avec --auth
################################################################################

# 1) Lancer mongod en mode insecure (sans --auth), en arrière-plan
echo "→ Démarrage de mongod en mode insecure (sans auth) pour création de root..."
mongod --bind_ip_all --fork --logpath /var/log/mongod-insecure.log

# 2) Boucle « ping » jusqu’à ce que le mongod insecure réponde
RET=1
while [ $RET -ne 0 ]; do
  echo "⏳ Attente du mongod insecure…"
  mongosh --quiet --eval "db.adminCommand('ping')" > /dev/null 2>&1 && RET=0 || RET=1
  sleep 1
done
echo "✅ mongod insecure est prêt."

# 3) Créer l’utilisateur root (admin) si nécessaire
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

# 4) Arrêter proprement le mongod insecure
echo "→ Arrêt du mongod insecure via mongod --shutdown..."
mongod --dbpath /data/db --shutdown

# 5) Relancer mongod en mode authentifié (fork)
echo "→ Relancement de mongod avec --auth..."
mongod --bind_ip_all --auth --fork --logpath /var/log/mongod.log

# 6) Boucle « ping » jusqu’à ce que le mongod authentifié réponde
RET=1
while [ $RET -ne 0 ]; do
  echo "⏳ Attente du mongod authenticated…"
  mongosh --quiet --eval "db.adminCommand('ping')" -u "${MONGO_INITDB_ROOT_USERNAME}" -p "${MONGO_INITDB_ROOT_PASSWORD}" --authenticationDatabase admin > /dev/null 2>&1 && RET=0 || RET=1
  sleep 1
done
echo "✅ mongod authenticated est prêt."


# ... tout votre code existant reste identique jusqu'à la ligne 7 ...

# 7) Créer un certificat SSL auto-signé et l'utiliser
echo "→ Création du certificat SSL auto-signé..."
mkdir -p /tmp/ssl
openssl req -newkey rsa:2048 -new -x509 -days 3652 -nodes \
  -out /tmp/ssl/server.crt \
  -keyout /tmp/ssl/server.key \
  -subj "/C=FR/ST=State/L=City/O=Test/CN=localhost"

# Combiner clé et certificat
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