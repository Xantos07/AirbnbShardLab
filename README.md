# 🏠 Airbnb Data Analysis Lab

Projet d'analyse de données Airbnb Paris avec MongoDB, BI Connector, et outils d'analyse Python.

## 📁 Structure du projet

```
AirbnbShardLab/
├── data/
│   ├── Listings_Paris.csv          # Données source
│   └── Data+Dictionary+(1).xlsx    
├── data_import/
│   ├── Dockerfile                  # Import automatique
│   └── import.sh                   # Script d'import
├── analysis/
│   ├── analyse.py                  # Analyses Python/Polars
│   ├── requirements.txt            # Dépendances Python
│   └── Dockerfile                  # Container d'analyse
├── requetes/
│   └── requetes.js                 # Requêtes MongoDB
├── compose.yaml                    # Orchestration Docker
├── Dockerfile                      # MongoDB + BI Connector
├── docker-entrypoint.sh           # Script de démarrage
└── .env                           # Variables d'environnement
```
## 🚀 Installation et Exécution
### 1️⃣ Prérequis
- **Docker & Docker Compose** installés
- **Power BI Desktop** (optionnel, pour visualisation)
- **MySQL ODBC Driver 8.0** (pour connexion Power BI)


### 2️⃣ Installation

Construire le projet:
```bash
docker-compose build --no-cache
```

Démarrer les services:
```bash
docker-compose up -d mongodb mongo-express
```

Importer les données (automatique):
```bash
docker-compose run --rm data-import
```

## 📊 Analyses disponibles

### Requêtes simples (MongoDB/JavaScript)
```bash
# Via exec
docker exec -it mongodb mongosh --host localhost -u root -p secret --authenticationDatabase admin /scripts/requetes.js

# Via compose
docker-compose up mongo-queries
```

### Analyses complexes (Python/Polars)
```bash
# Via run
docker-compose run --rm analysis python /app/analyse.py

# Via compose
docker-compose up analysis
```
## 🛠️ Technologies & Justification

| Technologie          | Raison du choix                                                                                           |
|----------------------|-----------------------------------------------------------------------------------------------------------|
| **Docker / Compose** | Isolation des services et portabilité ; déploiement rapide.                                               |
| **MongoDB**          | Base de données NoSQL flexible, idéale pour les données semi-structurées                                  |
| **MongoDB BI Connector** | Pont SQL vers MongoDB permettant l'utilisation d'outils comme Power BI                                    |
| **Python / Polars**          | Polars pour ses performances sur de gros volumes, idéal pour les analyses plus complexes.                 |
| **Mongo Express**              | Interface web pour l'exploration des données MongoDB, facilitant la visibilité.                           |
| **Power BI**              | Outil de visualisation, permettant la création de tableaux de bord interactifs |

---

## 🌐 Interfaces disponibles

| Service | URL | Credentials |
|---------|-----|-------------|
| **Mongo Express** | http://localhost:8081 | admin/admin |
| **MongoDB Direct** | localhost:27017 | root/secret |
| **Power BI (MySQL)** | localhost:3307 | root/secret |

## 📈 Connexion Power BI

### Via ODBC 
1. Installer MySQL ODBC Driver 8.0
2. Créer source ODBC :
   - **Server** : localhost
   - **Port** : 3307
   - **Database** : projetdb
   - **User** : root / **Password** : secret
   - **SSL** : Activé


## 🔍 Requêtes disponibles

### JavaScript 
- Nombre d'annonces par type de location
- Top 5 annonces avec le plus d'évaluations
- Analyse des hôtes 
- Taux de réservation instantanée

### Python
- Taux de réservation par type de logement
- Médiane des avis 
- Densité de logements par quartier
- Quartiers avec fort taux de réservation

## 🛠 Commandes utiles

```bash
# Voir les logs
docker logs mongodb --follow

# État des services
docker-compose ps

# Arrêter tout
docker-compose down

# Nettoyer complètement
docker-compose down -v
docker system prune -f

# Rebuild sans cache
docker-compose build --no-cache
```

## 📝 Variables d'environnement de test

```env
MONGO_INITDB_ROOT_USERNAME=root
MONGO_INITDB_ROOT_PASSWORD=secret
ME_CONFIG_BASICAUTH_USERNAME=admin
ME_CONFIG_BASICAUTH_PASSWORD=admin
```

## 🔧 Dépannage

### MongoDB ne démarre pas
```bash
docker logs mongodb
docker-compose restart mongodb
```

### BI Connector (mongosqld) ne répond pas
- Attendre 1-2 minutes après le démarrage
- Vérifier que les données sont importées
- Utiliser `--ssl --ssl-verify-server-cert=false` pour MySQL

### Power BI : Erreur d'authentification
- Utiliser ODBC au lieu du connecteur MySQL direct
- Vérifier que le port 3307 est ouvert : `docker port mongodb`

## 📊 Données

**Source** : Listings Airbnb Paris (CSV)  
**Collection MongoDB** : `projetdb.utilisateurs`  
**Documents** : ~95000 annonces Airbnb

