<?php

declare(strict_types=1);

/*
| La MENTION client du comptoir (« Client (facultatif) : Nom a imprimer sur le
| ticket »), confrontee au VRAI code du serveur : `VenteService::
| normaliserMentionClient`, celui que `VenteService::enregistrer` applique a
| `ventes.client_mention` (au web comme a la synchronisation d'un poste).
|
| Le poste en porte la replique (`MentionClient.normaliser`) ; le test
| `mention_client_contre_serveur_test.dart` envoie ici les memes saisies et
| compare, caractere pour caractere. Un script PHP recopie a la main des deux
| cotes ne prouverait rien : la saisie est UN seul JSON, lu par les deux moteurs.
|
| La base N'EST PAS un double : le script travaille sur une base d'ESSAI
| (`TATACORA_BASE_ESSAI=tatacora_<nom>_test`, a defaut `tatacora_test`) et REFUSE
| toute autre ; il n'ecrit rien. Le chemin COMPLET (charge d'une vente de poste,
| `GestionnaireVentes`, `VenteService::enregistrer`, colonne `client_mention`) est
| prouve par `charges_contre_serveur_test.dart` (`tool/sync/valider_charge.php`).
|
| Entree (stdin, JSON) : { "saisies": [ "<texte>", null, ... ] }
| Sortie (stdout, JSON) : { "normalisees": [ "<texte>"|null, ... ],
|                           "colonne_max": <longueur reelle de la colonne> }
|
| Usage : php tool/ventes/rejouer_mention_client.php < saisies.json
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

if (! is_array($entree) || ! isset($entree['saisies']) || ! is_array($entree['saisies'])) {
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

use App\Domain\Ventes\Services\VenteService;
use Illuminate\Support\Facades\DB;

$base = (string) config('database.connections.' . config('database.default') . '.database');

if ($base !== $baseEssai) {
    fwrite(STDERR, "Refus : la base active est \u{ab} {$base} \u{bb}, pas \u{ab} {$baseEssai} \u{bb}.\n");
    exit(1);
}

$sortie = ['normalisees' => [], 'colonne_max' => null];

foreach ($entree['saisies'] as $saisie) {
    $sortie['normalisees'][] = VenteService::normaliserMentionClient($saisie);
}

// La colonne : sa longueur reelle (le poste borne a la meme valeur).
$colonne = DB::selectOne(
    'SELECT CHARACTER_MAXIMUM_LENGTH AS longueur FROM information_schema.COLUMNS '
    . 'WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ? AND COLUMN_NAME = ?',
    [$baseEssai, 'ventes', 'client_mention'],
);
$sortie['colonne_max'] = $colonne === null ? null : (int) $colonne->longueur;

echo json_encode($sortie, JSON_UNESCAPED_UNICODE | JSON_INVALID_UTF8_SUBSTITUTE);
