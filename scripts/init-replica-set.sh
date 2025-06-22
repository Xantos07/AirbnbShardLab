#!/bin/bash
set -e

echo 'Attente du démarrage des instances MongoDB...'
sleep 30

echo 'Test de connexion au primary avec authentification...'
while ! mongosh --host mongodb-primary:27017 --quiet \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval 'db.adminCommand("ping")' > /dev/null 2>&1; do
  echo 'Attente du primary...'
  sleep 3
done
echo '✅ Primary accessible avec authentification'

echo 'Vérification si le replica set existe déjà...'
RS_STATUS=$(mongosh --host mongodb-primary:27017 --quiet \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval 'try { rs.status().ok } catch(e) { 0 }' 2>/dev/null | tail -1)

if [ "$RS_STATUS" != "1" ]; then
  echo 'Initialisation du replica set...'
  mongosh --host mongodb-primary:27017 \
    -u "$MONGO_INITDB_ROOT_USERNAME" \
    -p "$MONGO_INITDB_ROOT_PASSWORD" \
    --authenticationDatabase admin \
    --eval "
      rs.initiate({
        _id: 'rs0',
        members: [
          { _id: 0, host: 'mongodb-primary:27017', priority: 2 },
          { _id: 1, host: 'mongodb-secondary1:27017', priority: 1 },
          { _id: 2, host: 'mongodb-secondary2:27017', priority: 1 },
          { _id: 3, host: 'mongodb-arbiter:27017', arbiterOnly: true }
        ]
      })
    "
  
  echo 'Attente de la stabilisation du replica set...'
  sleep 20
  
  echo 'Vérification du statut final...'
  mongosh --host mongodb-primary:27017 \
    -u "$MONGO_INITDB_ROOT_USERNAME" \
    -p "$MONGO_INITDB_ROOT_PASSWORD" \
    --authenticationDatabase admin \
    --eval "
      var status = rs.status();
      print('Replica set: ' + status.set);
      status.members.forEach(function(member) {
        print('  - ' + member.name + ': ' + member.stateStr);
      });
    "
  
else
  echo 'Replica set déjà configuré!'
fi

echo 'Configuration du replica set terminée!'