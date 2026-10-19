<?php

declare(strict_types=1);

/**
 * Prépare la base de CAPTURE (Phase 1D) : les rôles et un compte
 * administrateur de test.
 *
 * ⚠ Ce compte n'existe QUE dans la base `tatacora_capture`, jetable, servie
 * sur 127.0.0.1 pour mesurer la vue Blade dans un navigateur. Son mot de passe
 * est écrit ICI parce que c'est un identifiant d'essai : aucun poste réel, aucun
 * serveur de recette ni de production ne le connaît, et le dépôt n'a aucun mot
 * de passe par défaut ailleurs (CLAUDE.md : « aucun mot de passe par défaut
 * n'existe nulle part dans ce dépôt »). Le script REFUSE de tourner sur une
 * autre base que `tatacora_capture`.
 *
 *   cd tatacora-api
 *   DB_DATABASE=tatacora_capture php ../tatacora-flutter/tool/conformite_blade/preparer_base_capture.php
 */

const BASE_AUTORISEE = 'tatacora_capture';
const LOGIN = 'capture.admin';
const MOT_DE_PASSE = 'Capture-1D-locale';

$racine = getcwd();
require $racine.'/vendor/autoload.php';

$app = require $racine.'/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

$base = (string) config('database.connections.'.config('database.default').'.database');

if ($base !== BASE_AUTORISEE) {
    fwrite(STDERR, "Refus : la base active est « {$base} », pas « ".BASE_AUTORISEE." ».\n");
    exit(1);
}

(new Database\Seeders\RolePermissionSeeder())->run();

$role = App\Shared\Rbac\Models\Role::where('libelle', 'administrateur')->firstOrFail();

App\Models\User::updateOrCreate(
    ['login' => LOGIN],
    [
        'mot_de_passe_hash' => Illuminate\Support\Facades\Hash::make(MOT_DE_PASSE),
        'role_id' => $role->id,
        'statut' => 'actif',
    ],
);

// Le jeu de démonstration PARTAGÉ avec les tests de widget (cas_ecrans.dart :
// `semerClients`, `semerParc`) : deux clients, un bungalow, deux unités. La
// vue Blade et l'écran Flutter doivent montrer les MÊMES données, sinon on
// mesure des états vides différents.
App\Domain\Crm\Models\Client::firstOrCreate(
    ['nom' => 'KORA', 'telephone' => '97111111'],
    ['type_client' => 'particulier'],
);
App\Domain\Crm\Models\Client::firstOrCreate(
    ['nom' => 'KORA', 'prenom' => 'Jean', 'telephone' => '+229 01 00 00 00 01'],
    ['type_client' => 'particulier'],
);
$categorie = App\Domain\Hebergement\Models\CategorieHebergement::firstOrCreate(
    ['libelle' => 'Bungalow'],
    ['capacite_max' => 2, 'tarif_base' => '28000.00'],
);
foreach (['BNG-01', 'BNG-02'] as $numero) {
    App\Domain\Hebergement\Models\UniteHebergement::firstOrCreate(
        ['numero' => $numero],
        ['categorie_id' => $categorie->id, 'statut' => 'libre'],
    );
}

echo "Base « {$base} » prête : compte ".LOGIN." (administrateur).\n";
