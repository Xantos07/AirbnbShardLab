#!/usr/bin/env bash
set -e

echo "→ Démarrage de mongod en mode standalone pour création de root..."
mongod --bind_ip_all --fork --logpath /var/log/mongod-insecure.log

# Boucle « ping » jusqu'à ce que le mongod insecure réponde
RET=1
while [ $RET -ne 0 ]; do
  echo "⏳ Attente du mongod insecure…"
  mongosh --quiet --eval "db.adminCommand('ping')" > /dev/null 2>&1 && RET=0 || RET=1
  sleep 1
done
echo "✅ mongod insecure est prêt."

# Créer l'utilisateur root (admin) 
echo "→ Vérification / création de l'utilisateur root…"
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

# Arrêter mongod insecure
echo "→ Arrêt du mongod insecure via mongod --shutdown..."
mongod --dbpath /data/db --shutdown

# Créer un keyfile pour le replica set si nécessaire
if [ -n "$MONGO_REPLICA_SET_NAME" ]; then
    echo "→ Création du keyfile pour le replica set..."
    mkdir -p /data/keyfile
    echo "myReplicaSetKey123456789012345678901234567890" > /data/keyfile/mongodb-keyfile
    chmod 600 /data/keyfile/mongodb-keyfile
    chown mongodb:mongodb /data/keyfile/mongodb-keyfile
    
    REPLICA_SET_ARGS="--replSet $MONGO_REPLICA_SET_NAME --keyFile /data/keyfile/mongodb-keyfile"
    echo "→ Relancement de mongod en mode replica set: $MONGO_REPLICA_SET_NAME"
else
    REPLICA_SET_ARGS=""
    echo "→ Relancement de mongod en mode standalone"
fi

# Relancer mongod en mode authentifié avec replica set
echo "→ Relancement de mongod avec --auth et replica set..."
mongod --bind_ip_all --auth $REPLICA_SET_ARGS --fork --logpath /var/log/mongod.log

# Loop jusqu'à ce que le mongod authentifié réponde
RET=1
while [ $RET -ne 0 ]; do
  echo "⏳ Attente du mongod …"
  # Pour un replica set non-initialisé, on teste sans auth d'abord
  if [ -n "$MONGO_REPLICA_SET_NAME" ]; then
    mongosh --quiet --eval "db.adminCommand('ping')" > /dev/null 2>&1 && RET=0 || RET=1
  else
    mongosh --quiet --eval "db.adminCommand('ping')" -u "${MONGO_INITDB_ROOT_USERNAME}" -p "${MONGO_INITDB_ROOT_PASSWORD}" --authenticationDatabase admin > /dev/null 2>&1 && RET=0 || RET=1
  fi
  sleep 1
done
echo "✅ mongod est prêt."

# Si c'est le primary, attendre l'initialisation du replica set avec timeout
if [ "$MONGO_REPLICA_HOST" = "mongodb-primary" ] && [ -n "$MONGO_REPLICA_SET_NAME" ]; then
    echo "→ En attente de l'initialisation du replica set par mongodb-setup..."
    
    # Attendre que le replica set soit initialisé (max 120 secondes)
    TIMEOUT=120
    ELAPSED=0
    while [ $ELAPSED -lt $TIMEOUT ]; do
        sleep 5
        ELAPSED=$((ELAPSED + 5))
        
        RS_STATUS=$(mongosh --quiet \
          -u "${MONGO_INITDB_ROOT_USERNAME}" \
          -p "${MONGO_INITDB_ROOT_PASSWORD}" \
          --authenticationDatabase admin \
          --eval "
            try { 
                var status = rs.status(); 
                if (status.ok === 1) {
                  var primary = status.members.find(m => m.stateStr === 'PRIMARY');
                  print(primary ? '1' : '0');
                } else {
                  print('0');
                }
            } catch(e) { 
                print('0'); 
            }
        " 2>/dev/null | tail -1)
        
        if [ "$RS_STATUS" = "1" ]; then
            echo "✅ Replica set initialisé avec succès!"
            break
        else
            echo "⏳ Replica set pas encore initialisé, attente... ($ELAPSED/$TIMEOUT sec)"
        fi
    done
    
    if [ $ELAPSED -ge $TIMEOUT ]; then
        echo "⚠️ Timeout atteint, démarrage de mongosqld sans attendre le replica set"
    fi
fi

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