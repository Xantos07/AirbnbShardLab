// requetes.js

db = db.getSiblingDB('projetdb');

print(" ---- Afficher un user ---- ");
printjson(db.utilisateurs.findOne());


print("\n ---- Nombre d’annonces par type de location ---- ");

db.utilisateurs.aggregate([
    {$group: {_id:"$room_type", count:{$sum: 1}}}
]).forEach(doc => printjson(doc));

print("\n ---- Top 5 annonces avec le plus d’évaluations ---- ");

db.utilisateurs.find(
    { number_of_reviews: { $exists: true } },
    { name: 1, number_of_reviews: 1, _id: 0 }
).sort({ number_of_reviews: -1 }).limit(5).forEach(doc => printjson(doc));

print("\n ---- Nombre total d’hôtes différents ---- ");

// sert a prendre toutes les variables UNIQUE
const nombre_total_hote_diff = db.utilisateurs.distinct("host_id").length;
print(nombre_total_hote_diff);

print("\n ---- Nombre de locations réservables instantanément et sa proportion ---- ");

//instant_bookable
const instant_bookable = db.utilisateurs.countDocuments({instant_bookable : "t"})
const total_count = db.utilisateurs.countDocuments();

print("réservables instantanement :", instant_bookable);
print("proportion : ", ((instant_bookable/total_count) * 100).toFixed(2) + "%")

print("\n ---- Hôtes ayant plus de 100 annonces et sa proportion ---- ");

const bigHosts = db.utilisateurs.aggregate([
    {
        $group: {
            _id: "$host_id",
            total_listings: { $sum: 1 },
            host_name: { $first: "$host_name" }
        }
    },
    {$match: {total_listings: { $gt: 100 }}},
    {$sort: { total_listings: -1 }}
]).toArray();

bigHosts.forEach(doc => {
    print(doc.host_name + " (" + doc._id + ") → " + doc.total_listings + " annonces");
});

const allHosts = db.utilisateurs.distinct("host_id");
print("Hôtes avec +100 annonces :", bigHosts.length);
print("Pourcentage :", (bigHosts.length / allHosts.length * 100).toFixed(2) + "%");

print("\n ---- SuperHost différent et sa proportion ---- ");
const superhosts = db.utilisateurs.distinct("host_id", { host_is_superhost: "t" });

print("Nombre de super hôtes :", superhosts.length);
print("Nombre total d'hôtes :", allHosts.length);
print("proportion :", ((superhosts.length/allHosts.length)* 100).toFixed(2) + "%");

