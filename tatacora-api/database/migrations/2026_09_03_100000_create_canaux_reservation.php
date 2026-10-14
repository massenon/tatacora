<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Canaux de réservation — référentiel administrable (PA-163, 01/09/2026).
 *
 * ## Pourquoi une TABLE, pas une liste dans un `<select>`
 *
 * Le maître l'écrit lui-même (`canaux-engine.js`, 24/08/2026) : ses sept
 * canaux étaient codés en dur dans `reservations.html`, la réservation rapide
 * n'en proposait aucun et écrivait « Physique » d'office — les statistiques
 * par canal comptaient au comptoir tout ce qui venait de Booking. Deux listes
 * écrites à deux endroits finissent par diverger ; une seule source, lue par
 * les deux formulaires.
 *
 * ## `actif` : un canal se DÉSACTIVE, il ne s'efface jamais
 *
 * Règle du maître, reprise telle quelle : un canal employé par au moins une
 * réservation doit rester lisible — l'effacer laisserait des réservations
 * pointant un canal inexistant, et l'analyse par canal perdrait son
 * historique. C'est la politique générale du dépôt (supprimer = archiver),
 * et la FK `restrictOnDelete` posée sur `reservations.canal_id` la rend
 * mécanique.
 *
 * @see prototype_v2/assets/js/canaux-engine.js le référentiel du maître
 * @see docs/PLAN_ACTION_SEQUENCE_POST_AUDIT.md PA-163
 */
return new class () extends Migration {
    public function up(): void
    {
        Schema::create('canaux_reservation', function (Blueprint $table): void {
            $table->uuid('id')->primary();

            // Unique : deux canaux du même nom rendraient toute statistique
            // par canal ambiguë — le défaut « deux auteurs » de PA-160/161,
            // fermé au schéma plutôt que par une convention.
            $table->string('nom', 100)->unique();

            $table->boolean('actif')->default(true);

            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('canaux_reservation');
    }
};
