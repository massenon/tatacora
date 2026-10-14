<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Écran « Contactez l'éditeur » — maître : `prototype_v2/pages/contact-editeur.html`.
 *
 * Jusqu'au 01/09/2026, `envoyerMessage()`/`signalerBug()` écrivaient dans
 * cette table SANS qu'elle existe : `Schema::hasTable()` rendait toujours
 * `false`, l'écriture n'avait jamais lieu, et pourtant l'écran annonçait
 * « Votre message a été transmis à l'éditeur » — PA-59/60/61. Cette
 * migration crée réellement la table que le code présumait.
 *
 * Un seul enregistrement par envoi, message OU signalement de bug — `type`
 * distingue les deux, `module_concerne` et `etapes` ne s'appliquant qu'au
 * second. `objet` porte le sujet libre (message) ou le libellé
 * « Bug — <module> » (bug), jamais une clé étrangère : aucune table ne
 * référence un « objet de contact ».
 *
 * `module_concerne` est une CHAÎNE issue d'un registre fermé côté PHP
 * (`RegistreModulesContact`), pas une clé étrangère : les seize entrées du
 * maître (M1 à M14, Rôles & Permissions, Paramètres...) ne correspondent pas
 * toutes à une ligne de `roles_permissions`, et « Connexion / navigation
 * générale » ou « Autre / je ne sais pas » n'en sont pas.
 *
 * `capture_nom`/`capture_chemin` restent NULLABLES : la capture d'écran est
 * facultative au maître (l.115, « optionnel »).
 *
 * `statut` distingue `a_transmettre` de `transmis` — `transmis` uniquement
 * quand l'envoi SMTP a réellement réussi (voir `MessageEditeurService`).
 * Aucun état intermédiaire « en cours » : soit la tentative a eu lieu et a
 * réussi, soit elle n'a pas eu lieu ou a échoué, et l'enregistrement reste
 * honnêtement `a_transmettre` — jamais un état qui affirmerait un envoi que
 * personne n'a vérifié (PA-59/60/61).
 *
 * Colonnes d'audit du dépôt (`Auditable`) : `utilisateur_creation_id` porte
 * l'AUTEUR réel de l'envoi, jamais un « Inconnu » de session côté client.
 */
return new class () extends Migration {
    public function up(): void
    {
        Schema::create('messages_editeur', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->enum('type', ['message', 'bug']);
            $table->string('objet');
            $table->string('module_concerne')->nullable();
            $table->text('corps');
            $table->text('etapes')->nullable();
            $table->string('capture_nom')->nullable();
            $table->string('capture_chemin')->nullable();
            $table->enum('statut', ['a_transmettre', 'transmis'])->default('a_transmettre');

            $table->foreignUuid('utilisateur_creation_id')->nullable()
                ->constrained('utilisateurs')->nullOnDelete();
            $table->timestamp('date_creation')->nullable();
            $table->foreignUuid('utilisateur_modification_id')->nullable()
                ->constrained('utilisateurs')->nullOnDelete();
            $table->timestamp('date_modification')->nullable();

            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('messages_editeur');
    }
};
