import os
import polars as pl
from pymongo import MongoClient
import sys
import time

def main():
    try:
        # Configuration MongoDB depuis les variables d'environnement
        username = os.getenv('MONGO_INITDB_ROOT_USERNAME', 'root')
        password = os.getenv('MONGO_INITDB_ROOT_PASSWORD', 'secret')
        host = os.getenv('MONGODB_HOST', 'mongodb-primary')
        
        print(f"🔗 Connexion à MongoDB Primary : {host}")
        
        # Attendre que le replica set soit prêt et que le primary soit disponible
        max_retries = 15
        for attempt in range(max_retries):
            try:
                # URI de connexion directe au primary (sans replica set discovery)
                uri = f"mongodb://{username}:{password}@{host}:27017/projetdb?authSource=admin&directConnection=true"
                client = MongoClient(uri, serverSelectionTimeoutMS=5000)
                
                # Vérifier que c'est bien le primary
                admin_db = client.admin
                rs_status = admin_db.command('replSetGetStatus')
                
                # Trouver le membre actuel
                current_member = None
                for member in rs_status['members']:
                    if member.get('self', False):
                        current_member = member
                        break
                
                if current_member and current_member['stateStr'] == 'PRIMARY':
                    print("✅ Connexion au PRIMARY réussie")
                    break
                else:
                    state = current_member['stateStr'] if current_member else 'UNKNOWN'
                    print(f"⏳ Nœud actuel: {state}, attente du PRIMARY...")
                    client.close()
                    time.sleep(3)
                    continue
                    
            except Exception as e:
                if attempt < max_retries - 1:
                    print(f"⏳ Tentative {attempt + 1}/{max_retries} - Attente du primary...")
                    time.sleep(3)
                    continue
                else:
                    print(f"❌ Impossible de se connecter au primary après {max_retries} tentatives")
                    raise e
        
        # Accès à la base et collection
        db = client.projetdb
        collection = db.utilisateurs
        
        # Vérifier le nombre de documents
        count = collection.count_documents({})
        print(f"📊 Nombre total de documents: {count}")
        
        if count == 0:
            print("⚠️ Aucun document trouvé. Assurez-vous que l'import a été effectué.")
            return
        
        print("\n🚀 === ANALYSES SPÉCIALISÉES AIRBNB ===\n")
        
        # Requête 1: Taux de réservation moyen par mois par type de logement
        print("1️⃣ Taux de réservation moyen par mois, par type de logement")
        print("=" * 60)
        
        docs = list(collection.find(
            {
                "availability_365": { "$nin": [None, ""] }
            },
            {
                "room_type": 1,
                "availability_365": 1,
                "_id": 0
            }
        ))
        
        for doc in docs:
            try:
                doc["availability_365"] = int(doc["availability_365"])
            except (ValueError, TypeError):
                doc["availability_365"] = None
        
        if docs:
            df = pl.DataFrame(docs)
            
            df = df.with_columns([
                (1 - (pl.col("availability_365") / 365)).alias("booking_rate_annual")
            ])
            
            result = df.group_by("room_type").agg(
                pl.col("booking_rate_annual").mean().alias("avg_booking_rate_per_month")
            )
            
            print(result)
        else:
            print("⚠️ Aucune donnée d'availability_365 trouvée")
        
        print("\n" + "="*60 + "\n")
        
        # Requête 2: Médiane du nombre d'avis pour TOUS les logements
        print("2️⃣ Médiane du nombre d'avis (tous logements confondus)")
        print("=" * 60)
        
        docs_all = list(collection.find(
            {},
            {"number_of_reviews": 1, "_id": 0}
        ))
        
        for doc in docs_all:
            try:
                doc["number_of_reviews"] = int(doc.get("number_of_reviews", 0))
            except (ValueError, TypeError):
                doc["number_of_reviews"] = 0
        
        df_all = pl.DataFrame(docs_all)
        
        median_all = df_all.select(
            pl.col("number_of_reviews")
              .median()
              .alias("median_number_of_reviews")
        )
        
        print(median_all)
        
        print("\n" + "="*60 + "\n")
        
        # Requête 3: Médiane du nombre d'avis PAR catégorie (room_type)
        print("3️⃣ Médiane du nombre d'avis par type de logement")
        print("=" * 60)
        
        docs_by_type = list(collection.find(
            {},
            {"room_type": 1, "number_of_reviews": 1, "_id": 0}
        ))
        
        for doc in docs_by_type:
            try:
                doc["number_of_reviews"] = int(doc.get("number_of_reviews", 0))
            except (ValueError, TypeError):
                doc["number_of_reviews"] = 0
        
        df_by_type = pl.DataFrame(docs_by_type)
        
        median_by_type = (
            df_by_type
            .group_by("room_type")
            .agg(
                pl.col("number_of_reviews")
                  .median()
                  .alias("median_number_of_reviews")
            )
        )
        
        print(median_by_type)
        
        print("\n" + "="*60 + "\n")
        
        # Requête 4: Densité de logements par quartier de Paris
        print("4️⃣ Densité de logements par quartier de Paris")
        print("=" * 60)
        
        docs = list(collection.find(
            {},
            {
                "neighbourhood_cleansed": 1,
                "availability_365": 1,
                "_id": 0
            }
        ))
        
        for doc in docs:
            try:
                doc["availability_365"] = float(doc.get("availability_365", 0))
            except:
                doc["availability_365"] = 0
        
        df = pl.DataFrame(docs)
        
        df = df.filter(pl.col("neighbourhood_cleansed").is_not_null())
        
        densite_par_quartier = df.group_by("neighbourhood_cleansed").agg(
            pl.len().alias("nb_logements")
        ).sort("nb_logements", descending=True)
        
        print(densite_par_quartier.head(10))  # Top 10
        
        print("\n" + "="*60 + "\n")
        
        # Requête 5: Quartiers avec le plus fort taux de réservation par mois
        print("5️⃣ Quartiers avec le plus fort taux de réservation par mois")
        print("=" * 60)
        
        docs = list(collection.find(
            {},
            {
                "neighbourhood_cleansed": 1,
                "availability_365": 1,
                "_id": 0
            }
        ))
        
        for doc in docs:
            try:
                doc["availability_365"] = float(doc.get("availability_365", 0))
            except:
                doc["availability_365"] = 0
        
        df = pl.DataFrame(docs)
        
        df = df.filter(
            (pl.col("neighbourhood_cleansed").is_not_null()) &
            (pl.col("availability_365").is_not_null())
        )
        
        df = df.with_columns([
            ((1 - (pl.col("availability_365") / 365)) * 30).alias("reserved_days_per_month")
        ])
        
        result = df.group_by("neighbourhood_cleansed").agg(
            pl.col("reserved_days_per_month").mean().alias("avg_reserved_days_per_month")
        ).sort("avg_reserved_days_per_month", descending=True)
        
        print(result.head(10))  # Top 10
        
        print("\n🎉 === TOUTES LES ANALYSES TERMINÉES AVEC SUCCÈS! ===")
        
    except Exception as e:
        print(f"❌ Erreur lors de l'analyse : {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
    finally:
        try:
            client.close()
        except:
            pass

if __name__ == "__main__":
    main()