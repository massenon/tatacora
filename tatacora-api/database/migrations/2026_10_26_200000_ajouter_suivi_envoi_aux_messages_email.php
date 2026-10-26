<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * L'envoi réel d'e-mails, avec SUIVI (décision du PO du 26/10/2026 : « l'envoi
 * réel d'e-mails DOIT ÊTRE IMPLÉMENTÉ EN POSTE ET WEB »).
 *
 * Quatre colonnes ADDITIVES sur les deux tables dont un message part par
 * SMTP — `notifications_composees` (M12) et `messages_editeur` (Contact
 * éditeur) : le nombre de tentatives RÉELLES (une connexion au serveur SMTP a
 * été essayée), la cause lisible du dernier échec (jamais un secret), le
 * moment de la dernière tentative (l'ancre du délai de relance) et le moment
 * où le serveur SMTP a ACCEPTÉ le message. `statut` ne change pas : un message
 * « en échec » est un message en attente dont les relances automatiques sont
 * épuisées (`tentatives >= TENTATIVES_MAX`), jamais un statut de plus à
 * synchroniser avec l'enum.
 */
return new class () extends Migration {
    public function up(): void
    {
        foreach (['notifications_composees', 'messages_editeur'] as $nom) {
            Schema::table($nom, function (Blueprint $table): void {
                $table->unsignedSmallInteger('tentatives')->default(0);
                $table->text('derniere_erreur')->nullable();
                $table->timestamp('derniere_tentative_le')->nullable();
                $table->timestamp('envoye_le')->nullable();
            });
        }
    }

    public function down(): void
    {
        foreach (['notifications_composees', 'messages_editeur'] as $nom) {
            Schema::table($nom, function (Blueprint $table): void {
                $table->dropColumn(['tentatives', 'derniere_erreur', 'derniere_tentative_le', 'envoye_le']);
            });
        }
    }
};
