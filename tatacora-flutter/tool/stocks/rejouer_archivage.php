<?php

declare(strict_types=1);

/*
| Rejoue, sur le VRAI serveur, les VERROUS D'ARCHIVAGE d'un article
| (`ReferentielArticleService::verrous`) sur des scenarios dont le poste monte
| les memes (21/10/2026) : le serveur est l'ancrage, jamais une liste recopiee.
|
| Six scenarios, rendus par nom :
|   libre      aucun engagement                                      -> []
|   stock       entree de 10, sortie de 3                             -> stock
|   commandes  2 commandes envoyees + 1 receptionnee + 1 cloturee    -> 2 en cours
|   carte      1 boisson a la carte                                  -> carte
|   recettes   2 compositions de recette                             -> recette
|   tout       2 en stock, 1 commande, 1 boisson, 1 recette          -> quatre motifs
|
| Sortie (stdout, JSON) : { "<scenario>": ["<motif>", ...], ... }
|
| La base N'EST PAS un double : le script travaille sur `tatacora_test` (il
| REFUSE toute autre base), seme les roles par le VRAI seeder, puis ANNULE tout
| (rollback). Usage : php tool/stocks/rejouer_archivage.php
*/

const BASE_AUTORISEE = 'tatacora_test';

// Une base d'ESSAI privee (`TATACORA_BASE_ESSAI=tatacora_<nom>_test`) peut
// remplacer `tatacora_test` quand plusieurs essais tournent en meme temps : la
// base partagee est alors migree sous les pieds de l'un ou de l'autre. Le nom
// doit finir par `test` — la base de developpement reste refusee.
$baseEssai = (static function (): string {
    $voulue = getenv('TATACORA_BASE_ESSAI');

    return is_string($voulue) && preg_match('/^tatacora_[a-z0-9_]*test$/', $voulue) === 1
        ? $voulue
        : BASE_AUTORISEE;
})();

$api = realpath(__DIR__ . '/../../../tatacora-api');

if ($api === false || ! is_file($api . '/vendor/autoload.php')) {
    fwrite(STDERR, "tatacora-api/vendor/autoload.php introuvable.\n");
    exit(2);
}

putenv('DB_DATABASE=' . $baseEssai);
$_ENV['DB_DATABASE'] = $baseEssai;
$_SERVER['DB_DATABASE'] = $baseEssai;

chdir($api);
require $api . '/vendor/autoload.php';

$app = require $api . '/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
$app->setLocale('fr');

use App\Domain\Achats\Models\CommandeAchat;
use App\Domain\Achats\Models\Fournisseur;
use App\Domain\Achats\Models\LigneCommandeAchat;
use App\Domain\Bar\Models\CarteBoisson;
use App\Domain\Restaurant\Models\Recette;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\MouvementStockService;
use App\Domain\Stocks\Services\ReferentielArticleService;
use App\Models\User;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;

$base = (string) config('database.connections.' . config('database.default') . '.database');

if ($base !== $baseEssai) {
    fwrite(STDERR, "Refus : la base active est \u{ab} {$base} \u{bb}, pas \u{ab} {$baseEssai} \u{bb}.\n");
    exit(1);
}

Carbon::setTestNow('2026-10-21 10:00:00');

DB::beginTransaction();

try {
    (new RolePermissionSeeder())->run();

    $admin = User::create([
        'login' => 'archivage.' . Str::random(6),
        'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
        'role_id' => Role::where('libelle', 'administrateur')->firstOrFail()->id,
        'statut' => 'actif',
    ]);
    Auth::login($admin);

    $magasin = PointStockage::create(['libelle' => 'Magasin', 'type' => 'magasin']);
    $fournisseur = Fournisseur::create(['raison_sociale' => 'Grossiste']);
    $mouvements = app(MouvementStockService::class);
    $service = app(ReferentielArticleService::class);

    $article = static fn (string $libelle): Article => Article::create([
        'libelle' => $libelle, 'categorie' => 'denree', 'unite_mesure' => 'sac',
        'seuil_alerte' => '5.00', 'seuil_reappro' => '12.00', 'cout_moyen_pondere' => '0.0000',
    ]);

    $commande = static function (Article $a, string $statut) use ($fournisseur, $admin): void {
        $c = CommandeAchat::create([
            'fournisseur_id' => $fournisseur->id, 'date_commande' => '2026-10-20',
            'statut' => $statut, 'utilisateur_id' => $admin->id,
        ]);
        LigneCommandeAchat::create([
            'commande_id' => $c->id, 'article_id' => $a->id,
            'quantite_commandee' => '5.00', 'prix_unitaire' => '1000.00',
        ]);
    };

    $boisson = static fn (Article $a, string $libelle): CarteBoisson => CarteBoisson::create([
        'article_id' => $a->id, 'libelle' => $libelle, 'categorie' => 'locale',
        'prix_vente' => '1000.00', 'unites_vendables_par_unite_stock' => '1.0000',
    ]);

    $recette = static function (Article $a, string $libelle): void {
        $r = Recette::create(['libelle' => $libelle]);
        DB::table('ingredients_recette')->insert([
            'recette_id' => $r->id, 'article_id' => $a->id, 'quantite_unitaire' => '0.250',
        ]);
    };

    $sortie = [];

    $sortie['libre'] = $service->verrous($article('Libre'));

    $a = $article('Stock');
    $mouvements->entree($a->id, $magasin->id, '10.00', 'Ouverture');
    $mouvements->sortie($a->id, $magasin->id, '3.00', 'Vente');
    $sortie['stock'] = $service->verrous($a);

    $a = $article('Commandes');
    $commande($a, 'envoyee');
    $commande($a, 'brouillon');
    $commande($a, 'receptionnee');
    $commande($a, 'cloturee');
    $sortie['commandes'] = $service->verrous($a);

    $a = $article('Carte');
    $boisson($a, 'Boisson A');
    $sortie['carte'] = $service->verrous($a);

    $a = $article('Recettes');
    $recette($a, 'Sauce');
    $recette($a, 'Soupe');
    $sortie['recettes'] = $service->verrous($a);

    $a = $article('Tout');
    $mouvements->entree($a->id, $magasin->id, '2.00', 'Ouverture');
    $commande($a, 'envoyee');
    $boisson($a, 'Boisson B');
    $recette($a, 'Ragout');
    $sortie['tout'] = $service->verrous($a);

    echo json_encode($sortie, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
} finally {
    while (DB::transactionLevel() > 0) {
        DB::rollBack();
    }
}
