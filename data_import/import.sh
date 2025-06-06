#!/bin/bash

echo "Attente du démarrage de MongoDB..."
sleep 10

if [ -f "/app/.env" ]; then
  export $(cat /app/.env | xargs)
fi

echo "Vérification de la base existante..."

EXISTING_COUNT=$(mongosh --quiet --host mongodb \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "db.getSiblingDB('projetdb').utilisateurs.estimatedDocumentCount()")

echo "Documents déjà présents : $EXISTING_COUNT"

if [ "$EXISTING_COUNT" -eq 0 ]; then
  echo "Importation des données..."
  mongoimport --host mongodb \
    --username "$MONGO_INITDB_ROOT_USERNAME" \
    --password "$MONGO_INITDB_ROOT_PASSWORD" \
    --authenticationDatabase admin \
    --db projetdb \
    --collection utilisateurs \
    --type csv \
    --headerline \
    --file /app/data/Listings_Paris.csv
  echo "Importation terminée !"
else
  echo "Importation ignorée : la collection contient déjà des données."
fi
