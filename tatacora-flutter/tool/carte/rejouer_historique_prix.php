<?php

declare(strict_types=1);

/*
| Rejoue, sur le VRAI serveur, ce que `TraceurHistoriquePrix` TRACE quand le prix
| d'un article de la carte change (26/10/2026) : le serveur est l'ancrage de la
| règle que le poste réplique (`changementsDePrix`), jamais une liste recopiée.
|
| Entrée (stdin, JSON) : { "scenarios": [ { "nom": "...", "source": "carte_boisson"|"plat",
|     "prix_avant": 1000, "prix_apres": 1200, "corrige_avant": false, "corrige_apres": false }, ... ] }
|
| Sortie (stdout, JSON) : { "<nom>": [ { "champ": "...", "ancien": "...", "nouveau": "..." }, ... ], ... }
| — les traces écrites par les VRAIS observateurs (`CarteBoissonObserver`,
| `PlatObserver`), dans l'ordre où le serveur les écrit.
|
| La base N'EST PAS un double : le script travaille sur `tatacora_test` (il REFUSE
| toute autre base, sauf une base d'essai PRIVÉE `tatacora_<nom>_test` donnée par
| `TATACORA_BASE_ESSAI`), puis ANNULE tout (rollback).
| Usage : php tool/carte/rejouer_historique_prix.php < scenarios.json
*/

const BASE_AUTORISEE = 'tatacora_test';

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

use App\Domain\Bar\Models\CarteBoisson;
use App\Domain\Carte\Models\HistoriquePrixCarte;
use App\Domain\Restaurant\Models\Menu;
use App\Domain\Restaurant\Models\Plat;
use App\Domain\Restaurant\Models\Recette;
use App\Domain\Stocks\Models\Article;
use Illuminate\Support\Facades\DB;

$base = (string) config('database.connections.' . config('database.default') . '.database');

if ($base !== $baseEssai) {
    fwrite(STDERR, "Refus : la base active est \u{ab} {$base} \u{bb}, pas \u{ab} {$baseEssai} \u{bb}.\n");
    exit(1);
}

$entree = json_decode((string) stream_get_contents(STDIN), true);
$scenarios = is_array($entree) ? ($entree['scenarios'] ?? null) : null;

if (! is_array($scenarios) || $scenarios === []) {
    fwrite(STDERR, "Entrée illisible : { \"scenarios\": [...] } attendu.\n");
    exit(2);
}

DB::beginTransaction();

try {
    $article = Article::create(['libelle' => 'Bière', 'categorie' => 'Boissons', 'unite_mesure' => 'bouteille', 'seuil_alerte' => '0.00', 'cout_moyen_pondere' => '0.0000']);
    $menu = Menu::create(['libelle' => 'Carte du jour', 'type' => 'local']);
    $recette = Recette::create(['libelle' => 'Riz', 'cout_matiere_calcule' => '0.00']);

    $sortie = [];

    foreach ($scenarios as $i => $s) {
        $nom = (string) $s['nom'];
        $prixAvant = number_format((float) $s['prix_avant'], 2, '.', '');
        $prixApres = number_format((float) $s['prix_apres'], 2, '.', '');

        if ($s['source'] === HistoriquePrixCarte::SOURCE_BOISSON) {
            $article_ = CarteBoisson::create([
                'article_id' => $article->id, 'libelle' => 'Boisson ' . $i, 'categorie' => 'locale',
                'prix_vente' => $prixAvant, 'prix_corrige_main' => (bool) $s['corrige_avant'],
                'unites_vendables_par_unite_stock' => '1.0000',
            ]);
        } else {
            $article_ = Plat::create([
                'menu_id' => $menu->id, 'recette_id' => $recette->id, 'categorie' => 'plats',
                'libelle' => 'Plat ' . $i, 'prix_vente' => $prixAvant, 'prix_corrige_main' => (bool) $s['corrige_avant'],
            ]);
        }

        // Aucune trace à la création : l'observateur ne naît qu'à `updated`.
        $apresCreation = HistoriquePrixCarte::query()->where('source_id', $article_->id)->count();

        $article_->update(['prix_vente' => $prixApres, 'prix_corrige_main' => (bool) $s['corrige_apres']]);

        $sortie[$nom] = [
            'a_la_creation' => $apresCreation,
            'traces' => HistoriquePrixCarte::query()
                ->where('source_id', $article_->id)
                ->orderBy('created_at')
                ->orderByRaw("FIELD(champ, 'prix_vente', 'prix_corrige_main')")
                ->get(['champ', 'ancien_prix', 'nouveau_prix'])
                ->map(static fn (HistoriquePrixCarte $t): array => [
                    'champ' => $t->champ,
                    'ancien' => $t->getRawOriginal('ancien_prix'),
                    'nouveau' => $t->getRawOriginal('nouveau_prix'),
                ])
                ->all(),
        ];
    }

    echo json_encode($sortie, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
} finally {
    while (DB::transactionLevel() > 0) {
        DB::rollBack();
    }
}
