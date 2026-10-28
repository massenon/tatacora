<?php

declare(strict_types=1);

/*
| Juge des fichiers par le VRAI `RecuDepenseService::controler()` du serveur,
| pour que le test Flutter compare, fichier par fichier, ce que le poste en
| pense (type reconnu, refus, phrase) a ce que le serveur en dira au depot
| (lot L4, 27/10/2026 : le recu en image d'une depense).
|
| Depuis le 28/10/2026 (PO : une image trop lourde est REDUITE, pas refusee), chaque
| fichier est aussi passe par `preparer()` — la regle de SAISIE du web — et
| rend sous `preparer` : ok/type/reduit/taille/largeur/hauteur, ou le refus.
|
| Aucune base n'est ouverte : le controle du contenu (regles `image` et `max:400`
| de Laravel, empreinte) ne lit que les octets. Rien n'est ecrit.
|
| Entree (stdin, JSON) :
|   { "fichiers": [ {"nom": "a", "base64": "..."}, ... ] }
| Sortie (stdout, JSON) :
|   { "constantes": { "taille_max_ko": 400, "dossier": "recus_depenses",
|                     "phrases": { "recu_vide": "...", ... } },
|     "resultats": [ {"nom": "a", "ok": true, "type": "image/png", "extension": "png",
|                      "sha256": "..."}  |  {"nom": "a", "refus": "recu_invalide",
|                      "statut": 422, "message": "..."} ] }
|
| Usage : php tool/depenses/rejouer_recus.php < fichiers.json
*/

$api = realpath(__DIR__ . '/../../../tatacora-api');

if ($api === false || ! is_file($api . '/vendor/autoload.php')) {
    fwrite(STDERR, "tatacora-api/vendor/autoload.php introuvable.\n");
    exit(2);
}

$entree = json_decode((string) stream_get_contents(STDIN), true);

if (! is_array($entree) || ! isset($entree['fichiers']) || ! is_array($entree['fichiers'])) {
    fwrite(STDERR, "Entree JSON invalide.\n");
    exit(3);
}

chdir($api);
require $api . '/vendor/autoload.php';

$app = require $api . '/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
$app->setLocale('fr');

use App\Domain\Depenses\Exceptions\RefusRecuDepense;
use App\Domain\Depenses\Services\RecuDepenseService;

$service = $app->make(RecuDepenseService::class);
$resultats = [];

foreach ($entree['fichiers'] as $fichier) {
    $octets = base64_decode((string) $fichier['base64'], true);

    if ($octets === false) {
        fwrite(STDERR, "base64 invalide pour " . $fichier['nom'] . "\n");
        exit(4);
    }

    try {
        $resultat = ['nom' => $fichier['nom'], 'ok' => true, ...$service->controler($octets)];
    } catch (RefusRecuDepense $refus) {
        $resultat = [
            'nom' => $fichier['nom'],
            'refus' => $refus->codeMotif,
            'statut' => $refus->statutHttp,
            'message' => $refus->getMessage(),
        ];
    }

    // La regle de SAISIE : reduire au lieu de refuser le poids.
    try {
        $prepare = $service->preparer($octets);
        $dimensions = @getimagesizefromstring($prepare['octets']) ?: [0, 0];
        $resultat['preparer'] = [
            'ok' => true,
            'type' => $prepare['type'],
            'extension' => $prepare['extension'],
            'reduit' => $prepare['reduit'],
            'taille' => strlen($prepare['octets']),
            'largeur' => $dimensions[0],
            'hauteur' => $dimensions[1],
            'sha256' => $prepare['sha256'],
        ];
    } catch (RefusRecuDepense $refus) {
        $resultat['preparer'] = [
            'ok' => false,
            'refus' => $refus->codeMotif,
            'message' => $refus->getMessage(),
        ];
    }

    $resultats[] = $resultat;
}

echo json_encode([
    'constantes' => [
        'taille_max_ko' => RecuDepenseService::TAILLE_MAX_KO,
        'dossier' => RecuDepenseService::DOSSIER,
        'reduction' => [
            'cote_max_px' => RecuDepenseService::COTE_MAX_PX,
            'qualites' => RecuDepenseService::QUALITES,
            'facteur' => RecuDepenseService::FACTEUR_REDUCTION,
            'cote_min_px' => RecuDepenseService::COTE_MIN_PX,
        ],
        'phrases' => [
            'recu_vide' => __('depenses.recu_vide'),
            'recu_illisible' => __('depenses.recu_illisible'),
            'recu_deja_rattache' => __('depenses.recu_deja_rattache'),
            'recu_empreinte' => __('depenses.recu_empreinte'),
            'recu_depense_inconnue' => __('depenses.recu_depense_inconnue'),
            'recu_autre_poste' => __('depenses.recu_autre_poste'),
            'recu_introuvable' => __('depenses.recu_introuvable'),
            'champ_recu' => __('depenses_pwa.champ_recu'),
            'champ_recu_aide' => __('depenses_pwa.champ_recu_aide'),
            'recu' => __('depenses_pwa.recu'),
            'sans_recu' => __('depenses_pwa.sans_recu'),
        ],
    ],
    'resultats' => $resultats,
], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);
