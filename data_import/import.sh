#!/bin/bash

echo "Attente du démarrage de MongoDB..."
sleep 15

if [ -f "/app/.env" ]; then
  export $(cat /app/.env | xargs)
fi

echo "Vérification de la connexion MongoDB..."

# tester sans authentification
echo "Test de connexion basique..."
while ! mongosh --host mongodb --quiet --eval "db.adminCommand('ping')" > /dev/null 2>&1; do
  echo "Attente de MongoDB..."
  sleep 3
done

echo "✅ MongoDB accessible"

# Tenter de créer l'utilisateur admin si il n'existe pas
echo "Vérification/création de l'utilisateur admin..."
mongosh --host mongodb --quiet --eval "
try {
  // Tenter de créer l'utilisateur s'il n'existe pas
  db.getSiblingDB('admin').createUser({
    user: '$MONGO_INITDB_ROOT_USERNAME',
    pwd: '$MONGO_INITDB_ROOT_PASSWORD',
    roles: [
      { role: 'root', db: 'admin' },
      { role: 'userAdminAnyDatabase', db: 'admin' },
      { role: 'readWriteAnyDatabase', db: 'admin' }
    ]
  });
  print('✅ Utilisateur admin créé');
} catch(e) {
  if (e.code === 51003) {
    print('✅ Utilisateur admin existe déjà');
  } else {
    print('ℹ️ Info utilisateur:', e.message);
  }
}
" 2>/dev/null

echo "Vérification de la base existante..."

# Vérifier le nombre total de documents
EXISTING_COUNT=$(mongosh --host mongodb \
  --username "$MONGO_INITDB_ROOT_USERNAME" \
  --password "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --quiet \
  --eval "
    try {
      var count = db.getSiblingDB('projetdb').utilisateurs.estimatedDocumentCount();
      print(count);
    } catch(e) {
      print('0');
    }
  " 2>/dev/null | tail -1)

# Vérifier si le résultat est un nombre
if ! [[ "$EXISTING_COUNT" =~ ^[0-9]+$ ]]; then
  echo "⚠️ Impossible de compter les documents, on assume 0"
  EXISTING_COUNT=0
fi

echo "📊 Documents total déjà présents : $EXISTING_COUNT"

# === ÉTAPE 1: IMPORT PARIS ===
echo ""
echo "🏙️ === GESTION DES DONNÉES PARIS ==="

# Vérifier si Paris existe déjà (avec champ ville)
PARIS_COUNT=$(mongosh --host mongodb \
  --username "$MONGO_INITDB_ROOT_USERNAME" \
  --password "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --quiet \
  --eval "
    try {
      var count = db.getSiblingDB('projetdb').utilisateurs.countDocuments({ville: 'Paris'});
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
    # Cas 1: Aucune donnée → Import Paris normal
    echo "📥 Import initial des données Paris..."
    
    if [ ! -f "/app/data/Listings_Paris.csv" ]; then
      echo "❌ Fichier Paris non trouvé : /app/data/Listings_Paris.csv"
      exit 1
    fi
    
    mongoimport --host mongodb \
      --username "$MONGO_INITDB_ROOT_USERNAME" \
      --password "$MONGO_INITDB_ROOT_PASSWORD" \
      --authenticationDatabase admin \
      --db projetdb \
      --collection utilisateurs \
      --type csv \
      --headerline \
      --file /app/data/Listings_Paris.csv
    
    if [ $? -eq 0 ]; then
      echo "✅ Import Paris réussi !"
    else
      echo "❌ Erreur lors de l'import Paris"
      exit 1
    fi
  fi
  
  # Cas 2: Données existent mais pas de champ ville -> Ajouter ville="Paris"
  echo "🏷️ Ajout du champ ville='Paris' aux données existantes..."
  mongosh --host mongodb \
    --username "$MONGO_INITDB_ROOT_USERNAME" \
    --password "$MONGO_INITDB_ROOT_PASSWORD" \
    --authenticationDatabase admin \
    --quiet \
    --eval "
      db = db.getSiblingDB('projetdb');
      var result = db.utilisateurs.updateMany(
        {ville: {\$exists: false}}, 
        {\$set: {ville: 'Paris'}}
      );
      print('✅ ' + result.modifiedCount + ' documents mis à jour avec ville=Paris');
    "
else
  echo "✅ Données Paris déjà présentes avec champ ville ($PARIS_COUNT documents)"
fi

# === ÉTAPE 2: IMPORT LYON ===
echo ""
echo "🏙️ === GESTION DES DONNÉES LYON ==="

# Vérifier si Lyon existe déjà
LYON_COUNT=$(mongosh --host mongodb \
  --username "$MONGO_INITDB_ROOT_USERNAME" \
  --password "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --quiet \
  --eval "
    try {
      var count = db.getSiblingDB('projetdb').utilisateurs.countDocuments({ville: 'Lyon'});
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
    
    # Import temporaire dans une collection séparée
    mongoimport --host mongodb \
      --username "$MONGO_INITDB_ROOT_USERNAME" \
      --password "$MONGO_INITDB_ROOT_PASSWORD" \
      --authenticationDatabase admin \
      --db projetdb \
      --collection temp_lyon \
      --type csv \
      --headerline \
      --file /app/data/Listings_Lyon.csv
    
    if [ $? -eq 0 ]; then
      echo "✅ Import temporaire Lyon réussi !"
      
      # Ajouter le champ ville="Lyon" et transférer
      echo "🏷️ Ajout du champ ville='Lyon' et fusion..."
      mongosh --host mongodb \
        --username "$MONGO_INITDB_ROOT_USERNAME" \
        --password "$MONGO_INITDB_ROOT_PASSWORD" \
        --authenticationDatabase admin \
        --quiet \
        --eval "
          db = db.getSiblingDB('projetdb');
          
          // Ajouter le champ ville à tous les documents Lyon
          var updateResult = db.temp_lyon.updateMany({}, {\$set: {ville: 'Lyon'}});
          print('✅ Champ ville ajouté à ' + updateResult.modifiedCount + ' documents Lyon');
          
          // Transférer vers la collection principale
          var docs = db.temp_lyon.find().toArray();
          if (docs.length > 0) {
            db.utilisateurs.insertMany(docs);
            print('✅ ' + docs.length + ' documents Lyon ajoutés à la collection principale');
          }
          
          // Nettoyer la collection temporaire
          db.temp_lyon.drop();
          print('✅ Collection temporaire supprimée');
        "
      echo "✅ Import Lyon terminé !"
    else
      echo "❌ Erreur lors de l'import Lyon"
    fi
  else
    echo "Fichier Lyon non trouvé (/app/data/Listings_Lyon.csv), import ignoré."
  fi
else
  echo "✅ Données Lyon déjà présentes ($LYON_COUNT documents)"
fi

# === STATISTIQUES FINALES ===
echo ""
echo "=== STATISTIQUES FINALES ==="
mongosh --host mongodb \
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
    } catch(e) {
      print('❌ Erreur lors du calcul des statistiques: ' + e);
    }
  "

echo "🎉 Import terminé !"