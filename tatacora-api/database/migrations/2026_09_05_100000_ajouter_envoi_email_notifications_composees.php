<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * M12 — l'e-mail RÉEL de la file d'attente (directive du Product Owner,
 * 01/09/2026 : « pour le moment utilise le SMTP »).
 *
 * ## Ce que ce lot ajoute, et pourquoi
 *
 * 1. `email_destinataire` — `notifications_composees.destinataire` est un
 *    NOM d'affichage (`Client::nomComplet()`, `Employe`...), jamais une
 *    adresse : composer un message ne suffit pas à savoir où l'envoyer. Les
 *    détecteurs qui savent résoudre une adresse réelle (`SejourDemainDetecteur`,
 *    `SejourDepartDetecteur`, `RestitutionVehiculeDetecteur`) la posent ici au
 *    moment de la composition ; les autres laissent la colonne `null`, et
 *    l'écran l'affiche comme un refus NOMMÉ (« aucune adresse connue »),
 *    jamais un champ vide qu'on croirait oublié.
 *
 * 2. `envoye` au sein de l'enum `statut` — un message parti réellement par
 *    e-mail quitte la file sans être ni « transmis à la main » (ce serait
 *    mentir sur qui l'a fait partir) ni « abandonné ». C'est un TROISIÈME
 *    sort, distinct des deux gestes manuels existants.
 *
 * ## Ce que ce lot n'ajoute PAS
 *
 * Aucune colonne de trace d'envoi ici : le fait qu'un message soit
 * réellement parti est écrit dans `notifications_envoyees` (table réelle
 * existante, jusqu'ici jamais alimentée), pas dupliqué sur cette ligne. Une
 * seconde source de vérité sur « quand » et « comment » a été envoyé
 * finirait par diverger de la première — même refus que partout ailleurs
 * dans ce dépôt (Rôles & Permissions, Etats...).
 */
return new class () extends Migration {
    public function up(): void
    {
        Schema::table('notifications_composees', function (Blueprint $table): void {
            $table->string('email_destinataire')->nullable()->after('destinataire');
        });

        DB::statement(
            "ALTER TABLE notifications_composees MODIFY statut "
            ."ENUM('en_attente','traite_manuellement','abandonne','envoye') NOT NULL DEFAULT 'en_attente'",
        );
    }

    public function down(): void
    {
        // Un message réellement `envoye` ne se représente pas dans l'enum
        // d'origine : il rejoint honnêtement `traite_manuellement`, plutôt
        // que de faire échouer le rollback sur une troncature MySQL — le
        // même choix d'ordre que `2026_09_02_400000_completer_modeles_notification`.
        DB::table('notifications_composees')
            ->where('statut', 'envoye')
            ->update(['statut' => 'traite_manuellement']);

        DB::statement(
            "ALTER TABLE notifications_composees MODIFY statut "
            ."ENUM('en_attente','traite_manuellement','abandonne') NOT NULL DEFAULT 'en_attente'",
        );

        Schema::table('notifications_composees', function (Blueprint $table): void {
            $table->dropColumn('email_destinataire');
        });
    }
};
