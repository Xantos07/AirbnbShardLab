import os
from dotenv import load_dotenv
from pymongo import MongoClient
import polars as pl


load_dotenv()
MONGO_USERNAME = os.getenv("MONGO_INITDB_ROOT_USERNAME")
MONGO_PASSWORD = os.getenv("MONGO_INITDB_ROOT_PASSWORD")

connection_string = f"mongodb://{MONGO_USERNAME}:{MONGO_PASSWORD}@mongodb:27017/?authSource=admin"
client = MongoClient(connection_string)
db = client["projetdb"]
collection = db["utilisateurs"]


try:
    print("✅ Connexion MongoDB OK. Documents dans la collection :", collection.estimated_document_count())
except Exception as e:
    print("❌ Échec de la connexion :", e)


# Requete 1
 # Calculer le taux de réservation moyen par mois par type de logement
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

df = pl.DataFrame(docs)

df = df.with_columns([
    (1 - (pl.col("availability_365") / 365)).alias("booking_rate_annual")
])

result = df.group_by("room_type").agg(
    pl.col("booking_rate_annual").mean().alias("avg_booking_rate_per_month")
)


print("Taux de réservation moyen par mois, par type de logement :\n")
print(result)



# Requête 2 : Médiane du nombre d’avis pour TOUS les logements

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

print("Médiane du nombre d’avis (tous logements confondus) :")
print(median_all)


#  Requête 3 : Médiane du nombre d’avis PAR catégorie (room_type)

docs_by_type = list(collection.find(
    {},
    {"room_type": 1, "number_of_reviews": 1, "_id": 0}
))

for doc in docs_by_type:
    try:
        doc["number_of_reviews"] = int(doc.get("number_of_reviews"))
    except (ValueError, TypeError):
        doc["number_of_reviews"] = None

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

print("\nMédiane du nombre d’avis par type de logement :")
print(median_by_type)

# requete 4 Calculer la densité de logements par quartier de Paris

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
print("Calculer la densité de logements par quartier de Paris :")
print(densite_par_quartier)

# Requête 5  Quartiers avec le plus fort taux de réservation par mois

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

print("Quartiers avec le plus fort taux de réservation estimé par mois :")
print(result)
