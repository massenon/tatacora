<?php

declare(strict_types=1);

/*
| Rejoue, sur le VRAI serveur, une suite de mouvements de stock valorises et rend
| (1) ce que le serveur AFFICHE pour chaque article (Valeur d'achat, CMP, Valeur
| stock : `ConsultationStockService::etatConsolide`, la meme source que l'ecran web)
| et (2) ce que la DESCENTE livre a un second poste, tel quel
| (`CatalogueDescendantService::page`, lue par un gerant). Le test Flutter
| (`valeurs_stock_contre_serveur_test.dart`) rejoue la meme suite sur le poste A,
| nourrit le poste B avec la descente et exige trois valeurs egales (09/11/2026).
|
| Entree (stdin, JSON) :
|   { "articles": ["cafe", ...],
|     "etapes": [{"article":"cafe","type":"entree","centiemes":1500,"cout":5000000}, ...] }
|   `cout` en dix-milliemes de franc (null/absent : entree non valorisee) ; `type` :
|   entree | sortie | perte.
| Sortie (stdout, JSON) :
|   { "serveur": {"cafe": {"prix_achat":"500.00","cmp":"500.0000","stock":"15.00","valeur":"7500.00"}},
|     "descente": [ <elements points_stockage, articles, mouvements_stock> ],
|     "ids": {"cafe":"<uuid>", "point":"<uuid>"} }
|
| La base N'EST PAS un double : le script travaille sur `tatacora_test` (il REFUSE
| toute autre base) ou sur la base privee `TATACORA_BASE_ESSAI=tatacora_<nom>_test`,
| seme les roles par le VRAI seeder, puis ANNULE tout (rollback).
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

$entree = json_decode((string) stream_get_contents(STDIN), true);

if (! is_array($entree) || ! isset($entree['articles'], $entree['etapes'])) {
    fwrite(STDERR, "Entree JSON invalide.\n");
    exit(3);
}

putenv('DB_DATABASE=' . $baseEssai);
$_ENV['DB_DATABASE'] = $baseEssai;
$_SERVER['DB_DATABASE'] = $baseEssai;

chdir($api);
require $api . '/vendor/autoload.php';

$app = require $api . '/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
$app->setLocale('fr');

use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\ConsultationStockService;
use App\Domain\Stocks\Services\MouvementStockService;
use App\Domain\Stocks\Services\ReferentielArticleService;
use App\Models\User;
use App\Shared\Rbac\Models\Role;
use App\Shared\Sync\Services\CatalogueDescendantService;
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

Carbon::setTestNow('2026-11-09 09:00:00');

DB::beginTransaction();

try {
    (new RolePermissionSeeder())->run();

    $utilisateur = static fn (string $role): User => User::create([
        'login' => $role . '.' . Str::random(6),
        'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
        'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
        'statut' => 'actif',
    ]);

    $barman = $utilisateur('barman');
    $gerant = $utilisateur('gerant');
    Auth::login($barman);

    $point = PointStockage::create(['libelle' => 'Bar', 'type' => 'bar']);
    $service = app(ReferentielArticleService::class);
    $mouvements = app(MouvementStockService::class);
    $ids = ['point' => (string) $point->id];

    // Des articles IMPORTES sans prix ni quantite (modeles Excel).
    foreach ($entree['articles'] as $cle) {
        $article = $service->creer([
            'libelle' => (string) $cle, 'categorie' => 'boisson', 'unite_mesure' => 'unite',
            'seuil_alerte' => '5.00', 'point_stockage_id' => $point->id,
        ]);
        $ids[(string) $cle] = (string) $article->id;
    }

    foreach ($entree['etapes'] as $etape) {
        Carbon::setTestNow(Carbon::now()->addSeconds(2));
        $quantite = bcdiv((string) $etape['centiemes'], '100', 2);
        $article = $ids[(string) $etape['article']];

        match ($etape['type']) {
            'entree' => $mouvements->entree(
                $article,
                $point->id,
                $quantite,
                'Essai',
                isset($etape['cout']) ? bcdiv((string) $etape['cout'], '10000', 4) : null,
            ),
            'sortie' => $mouvements->sortie($article, $point->id, $quantite, 'Essai', validationRupture: true),
            'perte' => $mouvements->perte($article, $point->id, $quantite, 'Essai', validationRupture: true),
        };
    }

    // Ce que le serveur (donc le web) affiche, pour tous les points.
    $serveur = [];
    $etat = app(ConsultationStockService::class)->etatConsolide();

    foreach ($etat->lignes as $ligne) {
        $serveur[$ligne->article->libelle] = [
            'prix_achat' => $ligne->article->prix_achat === null ? null : (string) $ligne->article->prix_achat,
            'cmp' => (string) $ligne->article->cout_moyen_pondere,
            'stock' => $ligne->stock,
            'valeur' => $ligne->valeur,
        ];
    }

    // Ce que la descente livre a un second poste, lue par un GERANT.
    Carbon::setTestNow(Carbon::now()->addSeconds(CatalogueDescendantService::HORIZON_SECONDES + 1));
    $descente = [];
    $curseur = null;

    do {
        $page = app(CatalogueDescendantService::class)->page($gerant, 'poste-b', $curseur, 500);
        foreach ($page['elements'] as $element) {
            if (in_array($element['table'], ['points_stockage', 'articles', 'mouvements_stock'], true)) {
                $descente[] = $element;
            }
        }
        $curseur = $page['curseur'];
    } while (! $page['complet']);

    echo json_encode(
        ['serveur' => $serveur, 'descente' => $descente, 'ids' => $ids],
        JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES,
    );
} finally {
    while (DB::transactionLevel() > 0) {
        DB::rollBack();
    }
}
