<?php

declare(strict_types=1);

/*
| Exporte, depuis le SERVEUR, le referentiel comptable que le poste replique :
| plan comptable (lu par la VRAIE fonction `ComptabiliteReferentielSeeder::
| lireFichier()`), table de correspondance `ComptesSyscohada`, centres, journaux,
| centres par defaut, et les gabarits de messages de refus (`lang/fr`). Le test
| Flutter confronte chacun de ces blocs a son equivalent Dart : jamais deux
| listes qui divergent (10/10/2026, lot 1 de M10).
|
| Aucune base n'est interrogee : l'application est amorcee pour que les aides
| `database_path()` et le traducteur existent, rien de plus.
|
| Sortie (stdout, JSON) :
|   { "plan": [["1","COMPTES ..."], ...], "comptes": {"CLIENTS":"4111", ...},
|     "centres": {"Hébergement":"exploitation", ...}, "journaux": {"VTE":"..."},
|     "centre_par_defaut": {"131":"Structure", ...},
|     "natures": ["actif", ...], "messages": {"comptabilite.piece_vide":"...", ...} }
|
| Usage : php tool/comptabilite/exporter_referentiel.php
*/

$api = realpath(__DIR__ . '/../../../tatacora-api');

if ($api === false || ! is_file($api . '/vendor/autoload.php')) {
    fwrite(STDERR, "tatacora-api/vendor/autoload.php introuvable.\n");
    exit(2);
}

chdir($api);
require $api . '/vendor/autoload.php';

$app = require $api . '/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
$app->setLocale('fr');

use App\Domain\Comptabilite\Services\PlanComptableService;
use App\Domain\Comptabilite\Support\ComptesSyscohada;
use Database\Seeders\ComptabiliteReferentielSeeder;

$cles = [
    'comptabilite.piece_vide',
    'comptabilite.piece_sans_montant',
    'comptabilite.piece_desequilibree',
    'comptabilite.ecriture_immuable',
    'comptabilite.ecriture_suppression_interdite',
    'comptabilite.exercice_clos',
    'comptabilite.ecriture_deja_validee',
    'comptabilite.contrepassation_sur_brouillon',
    'comptabilite.deja_contrepassee',
    'comptabilite.libelle_contrepassation',
    'comptabilite.compte_division',
    'comptabilite.compte_numero_invalide',
    'comptabilite.compte_libelle_requis',
    'comptabilite.compte_nature_invalide',
    'comptabilite.compte_deja_existant',
    'comptabilite.exercice_annee_invalide',
    'comptabilite.exercice_deja_existant',
    'comptabilite.exercice_deja_cloture',
    'comptabilite.cloture_brouillons_restants',
    'comptabilite.plan_fichier_illisible',
    'comptabilite.plan_fichier_ligne_invalide',
    'depenses.journal_inconnu',
    'depenses.compte_inconnu',
    'depenses.exercice_absent',
    'depenses.exercice_clos',
    'depenses.centre_absent',
];

$messages = [];
foreach ($cles as $cle) {
    $texte = (string) __($cle);
    if ($texte === $cle) {
        fwrite(STDERR, "Cle de langue introuvable : {$cle}\n");
        exit(4);
    }
    $messages[$cle] = $texte;
}

echo json_encode([
    'plan' => ComptabiliteReferentielSeeder::lireFichier(),
    'comptes' => (new ReflectionClass(ComptesSyscohada::class))->getConstants(),
    'centres' => (new ReflectionClassConstant(ComptabiliteReferentielSeeder::class, 'CENTRES'))->getValue(),
    'journaux' => (new ReflectionClassConstant(ComptabiliteReferentielSeeder::class, 'JOURNAUX'))->getValue(),
    'centre_par_defaut' => (new ReflectionClassConstant(ComptabiliteReferentielSeeder::class, 'CENTRE_PAR_DEFAUT'))->getValue(),
    'fichier_plan' => ComptabiliteReferentielSeeder::FICHIER_PLAN,
    'natures' => PlanComptableService::NATURES,
    'messages' => $messages,
], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
