<?php

declare(strict_types=1);

/*
| Rejoue, sur la VRAIE règle du serveur, l'e-mail facultatif d'un employé ou d'un
| compte (28/10/2026) : `AdresseEmailFacultative::normaliser` et le validateur de
| Laravel avec `AdresseEmailFacultative::REGLES` (`nullable|email:filter|max:255`),
| plus les deux phrases de `rh_pwa`.
|
| Entrée (stdin, JSON)  : { "adresses": ["...", ...] }
| Sortie (stdout, JSON) : { "resultats": [ {"saisie","normalisee","valide"} ... ],
|                           "phrases": {"invalide","enregistree"} }
|
| Aucune base n'est lue ni écrite.
| Usage : php tool/rh/rejouer_email_facultatif.php < scenario.json
*/

$api = realpath(__DIR__ . '/../../../tatacora-api');

if ($api === false || ! is_file($api . '/vendor/autoload.php')) {
    fwrite(STDERR, "tatacora-api/vendor/autoload.php introuvable.\n");
    exit(2);
}

$scenario = json_decode((string) stream_get_contents(STDIN), true);

if (! is_array($scenario) || ! isset($scenario['adresses'])) {
    fwrite(STDERR, "Entree JSON invalide.\n");
    exit(3);
}

chdir($api);
require $api . '/vendor/autoload.php';

$app = require $api . '/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
$app->setLocale('fr');

use App\Shared\Mail\Support\AdresseEmailFacultative;
use Illuminate\Support\Facades\Validator;

$resultats = [];

foreach ($scenario['adresses'] as $saisie) {
    // Comme l'écran : normalisée AVANT la validation.
    $normalisee = AdresseEmailFacultative::normaliser($saisie);
    $valide = Validator::make(
        ['email' => $normalisee],
        ['email' => AdresseEmailFacultative::REGLES],
    )->passes();

    $resultats[] = ['saisie' => $saisie, 'normalisee' => $normalisee, 'valide' => $valide];
}

echo json_encode([
    'resultats' => $resultats,
    'phrases' => [
        'invalide' => __('rh_pwa.email_invalide'),
        'enregistree' => __('rh_pwa.email_enregistre'),
    ],
], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
