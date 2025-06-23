#!/bin/bash

echo "Attente du démarrage du replica set MongoDB..."
sleep 30

if [ -f "/app/.env" ]; then
  export $(cat /app/.env | xargs)
fi

echo "Vérification de la connexion au replica set..."

# Tester la connexion au primary avec authentification
echo "Test de connexion au primary..."
while ! mongosh --host mongodb-primary \
  --username "$MONGO_INITDB_ROOT_USERNAME" \
  --password "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --quiet --eval "db.adminCommand('ping')" > /dev/null 2>&1; do
  echo "Attente du primary..."
  sleep 3
done

echo "✅ Primary MongoDB accessible"

# Attendre que le replica set soit complètement configuré et que le primary soit prêt
echo "Attente de la configuration complète du replica set..."
while true; do
  RS_STATUS=$(mongosh --host mongodb-primary \
    --username "$MONGO_INITDB_ROOT_USERNAME" \
    --password "$MONGO_INITDB_ROOT_PASSWORD" \
    --authenticationDatabase admin \
    --quiet \
    --eval "
      try {
        var status = rs.status();
        if (status.ok === 1) {
          var primary = status.members.find(m => m.stateStr === 'PRIMARY');
          if (primary && primary.health === 1) {
            print('ready');
          } else {
            print('waiting');
          }
        } else {
          print('waiting');
        }
      } catch(e) {
        print('waiting');
      }
    " 2>/dev/null | tail -1)
  
  if [ "$RS_STATUS" = "ready" ]; then
    echo "✅ Replica set prêt avec primary actif"
    break
  else
    echo "⏳ Attente du replica set..."
    sleep 5
  fi
done

# Vérifier le statut du replica set
echo "Vérification du statut du replica set..."
mongosh --host mongodb-primary \
  --username "$MONGO_INITDB_ROOT_USERNAME" \
  --password "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --quiet \
  --eval "
    try {
      var status = rs.status();
      print('🔗 Replica set actif: ' + status.set);
      print('🎯 Primary: ' + status.members.find(m => m.stateStr === 'PRIMARY').name);
    } catch(e) {
      print('⚠️ Replica set non configuré: ' + e.message);
    }
  "

echo "Vérification de la base existante..."

# Vérifier le nombre total de documents
EXISTING_COUNT=$(mongosh --host mongodb-primary \
  --username "$MONGO_INITDB_ROOT_USERNAME" \
  --password "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --quiet \
  --eval "
    try {
      db = db.getSiblingDB('projetdb');
      var count = db.utilisateurs.countDocuments({});
      print(count);
    } catch(e) {
      print('0');
    }
  " 2>/dev/null | tail -1)

# Vérifier si le résultat est un nombre
if ! [[ "$EXISTING_COUNT" =~ ^[0-9]+$ ]]; then
  EXISTING_COUNT=0
fi

echo "📊 Documents total déjà présents : $EXISTING_COUNT"

# === ÉTAPE 1: IMPORT PARIS ===
echo ""
echo "🗼 === GESTION DES DONNÉES PARIS ==="

# Vérifier si Paris existe déjà avec le champ ville
PARIS_COUNT=$(mongosh --host mongodb-primary \
  --username "$MONGO_INITDB_ROOT_USERNAME" \
  --password "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --quiet \
  --eval "
    try {
      db = db.getSiblingDB('projetdb');
      var count = db.utilisateurs.countDocuments({ville: 'Paris'});
      print(count);
    } catch(e) {
      print('0');
    }
  " 2>/dev/null | tail -1)

if ! [[ "$PARIS_COUNT" =~ ^[0-9]+$ ]]; then
  PARIS_COUNT=0
fi

echo "📊 Documents Paris existants : $PARIS_COUNT"

if [ "$PARIS_COUNT" -eq 0 ]; then
  if [ "$EXISTING_COUNT" -eq 0 ]; then
    # Cas 1: Aucune donnée -> Import complet
    if [ -f "/app/data/Listings_Paris.csv" ]; then
      echo "📥 Import initial des données Paris..."
      
      # Utiliser une URI de connexion pour le replica set
      mongoimport --uri "mongodb://root:secret@mongodb-primary:27017/projetdb?authSource=admin&replicaSet=rs0" \
        --collection utilisateurs \
        --type csv \
        --headerline \
        --file /app/data/Listings_Paris.csv
      
      if [ $? -eq 0 ]; then
        echo "✅ Import Paris réussi !"
        
        # Ajouter le champ ville="Paris"
        echo "🏷️ Ajout du champ ville='Paris'..."
        mongosh --host mongodb-primary \
          --username "$MONGO_INITDB_ROOT_USERNAME" \
          --password "$MONGO_INITDB_ROOT_PASSWORD" \
          --authenticationDatabase admin \
          --quiet \
          --eval "
            db = db.getSiblingDB('projetdb');
            var result = db.utilisateurs.updateMany({ville: {\$exists: false}}, {\$set: {ville: 'Paris'}});
            print('✅ Champ ville ajouté à ' + result.modifiedCount + ' documents');
          "
      else
        echo "❌ Erreur lors de l'import Paris"
        exit 1
      fi
    else
      echo "⚠️ Fichier Paris non trouvé (/app/data/Listings_Paris.csv), import ignoré."
    fi
  else
    # Cas 2: Données existent mais pas de champ ville -> Ajouter ville="Paris"
    echo "🏷️ Ajout du champ ville='Paris' aux données existantes..."
    mongosh --host mongodb-primary \
      --username "$MONGO_INITDB_ROOT_USERNAME" \
      --password "$MONGO_INITDB_ROOT_PASSWORD" \
      --authenticationDatabase admin \
      --quiet \
      --eval "
        db = db.getSiblingDB('projetdb');
        var result = db.utilisateurs.updateMany({ville: {\$exists: false}}, {\$set: {ville: 'Paris'}});
        print('✅ Champ ville ajouté à ' + result.modifiedCount + ' documents');
      "
  fi
else
  echo "✅ Données Paris déjà présentes avec champ ville ($PARIS_COUNT documents)"
fi

# === ÉTAPE 2: IMPORT LYON ===
echo ""
echo "🏙️ === GESTION DES DONNÉES LYON ==="

# Vérifier si Lyon existe déjà
LYON_COUNT=$(mongosh --host mongodb-primary \
  --username "$MONGO_INITDB_ROOT_USERNAME" \
  --password "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --quiet \
  --eval "
    try {
      db = db.getSiblingDB('projetdb');
      var count = db.utilisateurs.countDocuments({ville: 'Lyon'});
      print(count);
    } catch(e) {
      print('0');
    }
  " 2>/dev/null | tail -1)

if ! [[ "$LYON_COUNT" =~ ^[0-9]+$ ]]; then
  LYON_COUNT=0
fi

echo "📊 Documents Lyon existants : $LYON_COUNT"

if [ "$LYON_COUNT" -eq 0 ]; then
  if [ -f "/app/data/Listings_Lyon.csv" ]; then
    echo "📥 Import des données Lyon..."
    
    # Import temporaire dans une collection séparée avec URI de replica set
    mongoimport --uri "mongodb://root:secret@mongodb-primary:27017/projetdb?authSource=admin&replicaSet=rs0" \
      --collection temp_lyon \
      --type csv \
      --headerline \
      --file /app/data/Listings_Lyon.csv
    
    if [ $? -eq 0 ]; then
      echo "✅ Import temporaire Lyon réussi !"
      
      # Ajouter le champ ville="Lyon" et transférer
      echo "🏷️ Ajout du champ ville='Lyon' et fusion..."
      mongosh --host mongodb-primary \
        --username "$MONGO_INITDB_ROOT_USERNAME" \
        --password "$MONGO_INITDB_ROOT_PASSWORD" \
        --authenticationDatabase admin \
        --quiet \
        --eval "
          db = db.getSiblingDB('projetdb');
          
          // Ajouter le champ ville à tous les documents de temp_lyon
          db.temp_lyon.updateMany({}, {\$set: {ville: 'Lyon'}});
          
          // Transférer vers la collection principale
          var docs = db.temp_lyon.find({}).toArray();
          if (docs.length > 0) {
            db.utilisateurs.insertMany(docs);
            print('✅ ' + docs.length + ' documents Lyon transférés');
          }
          
          // Supprimer la collection temporaire
          db.temp_lyon.drop();
          print('✅ Collection temporaire supprimée');
        "
      echo "✅ Import Lyon terminé !"
    else
      echo "❌ Erreur lors de l'import Lyon"
    fi
  else
    echo "⚠️ Fichier Lyon non trouvé (/app/data/Listings_Lyon.csv), import ignoré."
  fi
else
  echo "✅ Données Lyon déjà présentes ($LYON_COUNT documents)"
fi

# === STATISTIQUES FINALES ===
echo ""
echo "=== STATISTIQUES FINALES ==="
mongosh --host mongodb-primary \
  --username "$MONGO_INITDB_ROOT_USERNAME" \
  --password "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --quiet \
  --eval "
    db = db.getSiblingDB('projetdb');
    try {
      var total = db.utilisateurs.countDocuments({});
      var paris = db.utilisateurs.countDocuments({ville: 'Paris'});
      var lyon = db.utilisateurs.countDocuments({ville: 'Lyon'});
      var autres = total - paris - lyon;
      
      print('📈 Résultats finaux:');
      print('   🌍 Total: ' + total + ' documents');
      print('   🗼 Paris: ' + paris + ' documents');
      print('   🦁 Lyon: ' + lyon + ' documents');
      if (autres > 0) {
        print('   ❓ Autres: ' + autres + ' documents');
      }
      
      // Afficher le statut du replica set
      print('');
      print('🔗 Statut du replica set:');
      var status = rs.status();
      status.members.forEach(function(member) {
        print('   ' + member.name + ': ' + member.stateStr);
      });
    } catch(e) {
      print('❌ Erreur lors du calcul des statistiques: ' + e);
    }
  "

echo "🎉 Import terminé !"