<?php

declare(strict_types=1);

/*
| Rejoue, sur le VRAI `AideEchecEmail` du serveur, l'AIDE posée sous l'échec de « Envoyer un
| email de test » (09/11/2026) : pour chaque message de transport, le cas reconnu et la phrase.
| Le poste (`AideEchecEmail` de Dart) dit la même chose ; le test `aide_email_contre_serveur_test`
| compare, message par message — jamais une liste recopiée.
|
| Entrée (stdin, JSON) : { "messages": [ "...", ... ] }
| Sortie (stdout, JSON) : { "cas": {message: "hote|connexion|authentification"|null},
|                           "aide": {message: phrase|null},
|                           "phrases": {"hote": ..., "connexion": ..., "authentification": ...},
|                           "fragments": {cas: [...]} }
|
| Aucune base : le script ne lit que le service et le fichier de langue.
| Usage : php tool/parametres/rejouer_aide_email.php < messages.json
*/

$api = realpath(__DIR__ . '/../../../tatacora-api');

if ($api === false || ! is_file($api . '/vendor/autoload.php')) {
    fwrite(STDERR, "tatacora-api/vendor/autoload.php introuvable.\n");
    exit(2);
}

$entree = json_decode((string) stream_get_contents(STDIN), true);

if (! is_array($entree) || ! isset($entree['messages'])) {
    fwrite(STDERR, "Entree JSON invalide.\n");
    exit(3);
}

chdir($api);
require $api . '/vendor/autoload.php';

$app = require $api . '/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
$app->setLocale('fr');

use App\Shared\Parametres\Services\AideEchecEmail;

$cas = [];
$aide = [];

foreach ($entree['messages'] as $message) {
    $cas[$message] = AideEchecEmail::cas((string) $message);
    $aide[$message] = AideEchecEmail::pour((string) $message);
}

echo json_encode([
    'cas' => $cas,
    'aide' => $aide,
    'phrases' => [
        AideEchecEmail::HOTE => (string) __('pwa.parametres.email_test_aide_hote'),
        AideEchecEmail::CONNEXION => (string) __('pwa.parametres.email_test_aide_connexion'),
        AideEchecEmail::AUTHENTIFICATION => (string) __('pwa.parametres.email_test_aide_authentification'),
    ],
    'fragments' => AideEchecEmail::FRAGMENTS,
], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
