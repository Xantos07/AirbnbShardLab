// requetes.js - Attendre que le replica set soit prêt

print("🔍 Vérification du statut du replica set...");

// Attendre que le replica set soit prêt
var maxRetries = 10;
var ready = false;

for (var attempt = 1; attempt <= maxRetries; attempt++) {
    try {
        var status = rs.status();
        var currentMember = status.members.find(m => m.self === true);
        
        if (currentMember && currentMember.stateStr === 'PRIMARY') {
            print("✅ Connecté au PRIMARY - Replica set prêt!");
            ready = true;
            break;
        } else {
            print("⏳ Tentative " + attempt + "/" + maxRetries + " - Statut: " + (currentMember ? currentMember.stateStr : 'UNKNOWN'));
            if (attempt < maxRetries) {
                sleep(50000); // Attendre 2 secondes
            }
        }
    } catch (e) {
        print("⏳ Tentative " + attempt + "/" + maxRetries + " - Attente du replica set...");
        if (attempt < maxRetries) {
            sleep(50000);
        }
    }
}

if (!ready) {
    print("❌ Impossible de se connecter au primary après " + maxRetries + " tentatives");
    quit(1);
}

// Maintenant que le primary est prêt, exécuter les requêtes
print("\n🚀 Démarrage des requêtes MongoDB...");
print("================================================");

db = db.getSiblingDB('projetdb');

// Vérifier que la base contient des données
var docCount = db.utilisateurs.countDocuments({});
print("📊 Nombre total de documents:", docCount);

if (docCount === 0) {
    print("⚠️ Aucun document trouvé dans la collection utilisateurs");
    quit(1);
}

print("\n ---- Afficher un user ---- ");
printjson(db.utilisateurs.findOne());

print("\n ---- Nombre d'annonces par type de location ---- ");
db.utilisateurs.aggregate([
    {$group: {_id:"$room_type", count:{$sum: 1}}},
    {$sort: {count: -1}}
]).forEach(doc => printjson(doc));

print("\n ---- Top 5 annonces avec le plus d'évaluations ---- ");
db.utilisateurs.find(
    { number_of_reviews: { $exists: true } },
    { name: 1, number_of_reviews: 1, _id: 0 }
).sort({ number_of_reviews: -1 }).limit(5).forEach(doc => printjson(doc));

print("\n ---- Nombre total d'hôtes différents ---- ");
const nombre_total_hote_diff = db.utilisateurs.distinct("host_id").length;
print("Total d'hôtes différents:", nombre_total_hote_diff);

print("\n ---- Nombre de locations réservables instantanément et sa proportion ---- ");
const instant_bookable = db.utilisateurs.countDocuments({instant_bookable : "t"});
const total_count = db.utilisateurs.countDocuments();

print("Réservables instantanément:", instant_bookable);
print("Proportion:", ((instant_bookable/total_count) * 100).toFixed(2) + "%");

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

print("🏆 Gros hôtes (+100 annonces):");
bigHosts.forEach(doc => {
    print("  " + doc.host_name + " (" + doc._id + ") → " + doc.total_listings + " annonces");
});

const allHosts = db.utilisateurs.distinct("host_id");
print("Hôtes avec +100 annonces:", bigHosts.length);
print("Pourcentage:", (bigHosts.length / allHosts.length * 100).toFixed(2) + "%");

print("\n ---- SuperHost différent et sa proportion ---- ");
const superhosts = db.utilisateurs.distinct("host_id", { host_is_superhost: "t" });

print("⭐ Nombre de super hôtes:", superhosts.length);
print("📊 Nombre total d'hôtes:", allHosts.length);
print("🎯 Proportion:", ((superhosts.length/allHosts.length) * 100).toFixed(2) + "%");

print("\n✅ Toutes les requêtes terminées avec succès!");

