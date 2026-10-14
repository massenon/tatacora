<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * La FILE D'ATTENTE de M12 — onglet par défaut du maître
 * (`prototype_v2/pages/m12-notifications-hub.html` l.73, moteur
 * `notifications-engine.js` l.402-461, clés `tatacora_m12_file`/
 * `tatacora_m12_journal`).
 *
 * ## Une seule table pour la file ET le journal, comme le maître
 *
 * Le maître tient deux listes (`file`, `journal`) qui portent en réalité le
 * MÊME objet à des états différents — un message quitte `file` quand il est
 * traité et rejoint `journal`, jamais copié. `statut` fait ici ce que
 * l'appartenance à l'une ou l'autre liste faisait côté client :
 * `en_attente` = file, `traite_manuellement`/`abandonne` = journal. Une seule
 * table évite la question qui se poserait avec deux : où vit la ligne
 * pendant la transition ?
 *
 * ## `unique(modele_id, reference)` EST le mécanisme d'idempotence
 *
 * Le maître le fait en mémoire, par `Set` (`dejaEnFile`/`dejaTraite`,
 * l.412-413) : composer deux fois pour le même couple ne doit jamais
 * dupliquer un message — c'est exactement le défaut qui ferait recevoir
 * trois fois la même relance à un client. Une contrainte au SCHÉMA le
 * garantit même si deux détections tournent en même temps (deux clics sur
 * « Détecter maintenant », deux onglets), ce qu'un `Set` en mémoire de
 * navigateur ne pouvait pas offrir.
 *
 * ## `canal` est un INSTANTANÉ, pas une référence vivante au modèle
 *
 * `ModeleNotificationService::modifierModele()` autorise à changer le canal
 * d'un modèle après coup. Un message déjà composé doit garder le canal (donc
 * la limite de caractères, donc la mise en forme) qui était en vigueur au
 * moment de sa composition — le relire plus tard sous un autre canal
 * romprait le lien entre le texte et sa validation.
 *
 * ## Ni `traite_par`, ni `date_traitement` : les colonnes d'audit du dépôt
 *
 * `utilisateur_modification_id`/`date_modification` (trait `Auditable`)
 * portent déjà CETTE information dès que « Transmis à la main » ou
 * « Abandonner » modifie la ligne : les dupliquer serait une seconde source
 * de vérité sur la même question — exactement ce que ce dépôt refuse
 * ailleurs (RolesPermissions, Etats...).
 */
return new class () extends Migration {
    public function up(): void
    {
        Schema::create('notifications_composees', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('modele_id')->constrained('modeles_notification')->restrictOnDelete();
            $table->string('canal');
            $table->string('reference');
            $table->string('destinataire');
            $table->string('objet')->nullable();
            $table->text('contenu');
            $table->unsignedInteger('longueur');
            $table->enum('statut', ['en_attente', 'traite_manuellement', 'abandonne'])
                ->default('en_attente');
            $table->text('commentaire')->nullable();
            $table->text('motif_abandon')->nullable();

            $table->foreignUuid('utilisateur_creation_id')->nullable()
                ->constrained('utilisateurs')->nullOnDelete();
            $table->timestamp('date_creation')->nullable();
            $table->foreignUuid('utilisateur_modification_id')->nullable()
                ->constrained('utilisateurs')->nullOnDelete();
            $table->timestamp('date_modification')->nullable();

            $table->timestamps();

            $table->unique(['modele_id', 'reference']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('notifications_composees');
    }
};
