<?php

declare(strict_types=1);

/*
| Rejoue, sur la VRAIE règle du serveur, la description FACULTATIVE d'un plat
| (30/10/2026, poste v47) : `DescriptionPlat::normaliser` (espaces de bord
| retirés, vide = null) puis le validateur de Laravel avec
| `DescriptionPlat::REGLES` (`nullable|string|max:500`) et la phrase de
| `restaurant.validation.description_trop_longue`, comme `Restauration::
| enregistrerPlat`, `EnregistrerPlatRequest` et `GestionnairePlats`.
|
| Entrée (stdin, JSON)  : { "descriptions": ["...", null, ...] }
| Sortie (stdout, JSON) : { "resultats": [ {"saisie","normalisee","valide","message"} ... ],
|                           "maximum": 500, "phrase": "..." }
|
| Aucune base n'est lue ni écrite.
| Usage : php tool/restaurant/rejouer_description_plat.php < scenario.json
*/

$api = realpath(__DIR__ . '/../../../tatacora-api');

if ($api === false || ! is_file($api . '/vendor/autoload.php')) {
    fwrite(STDERR, "tatacora-api/vendor/autoload.php introuvable.\n");
    exit(2);
}

$scenario = json_decode((string) stream_get_contents(STDIN), true);

if (! is_array($scenario) || ! isset($scenario['descriptions'])) {
    fwrite(STDERR, "Entree JSON invalide.\n");
    exit(3);
}

chdir($api);
require $api . '/vendor/autoload.php';

$app = require $api . '/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
$app->setLocale('fr');

use App\Domain\Restaurant\Support\DescriptionPlat;
use Illuminate\Support\Facades\Validator;

$phrase = __('restaurant.validation.description_trop_longue', ['max' => DescriptionPlat::MAX]);
$resultats = [];

foreach ($scenario['descriptions'] as $saisie) {
    // Comme l'ecran, l'API et la synchronisation : normalisee AVANT la validation.
    $normalisee = DescriptionPlat::normaliser($saisie);
    $validateur = Validator::make(
        ['description' => $normalisee],
        ['description' => DescriptionPlat::REGLES],
        ['description.max' => $phrase],
    );

    $resultats[] = [
        'saisie' => $saisie,
        'normalisee' => $normalisee,
        'valide' => $validateur->passes(),
        'message' => $validateur->passes() ? null : $validateur->errors()->first('description'),
    ];
}

echo json_encode([
    'resultats' => $resultats,
    'maximum' => DescriptionPlat::MAX,
    'phrase' => $phrase,
], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
