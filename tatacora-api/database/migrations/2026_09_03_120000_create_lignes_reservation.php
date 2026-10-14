<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Les LIGNES DE SERVICES d'une réservation — PA-163 (01/09/2026).
 *
 * « Une réservation peut combiner Hébergement, Restauration, Bar, Tourisme
 * et/ou Location de véhicule sur une même fiche client » — le sous-titre de
 * `reservations.html` (l.30), porté au client Flutter par PA-110 (schéma v8)
 * et jusqu'ici ABSENT du serveur. Le formulaire complet de la PWA le rend
 * nécessaire ici.
 *
 * ## QUATRE services, jamais cinq — l'hébergement n'est PAS une ligne
 *
 * `reservations.unite_id` porte déjà la chambre : NOT NULL, une seule, et
 * c'est sur elle que RG-01 verrouille. Dupliquer l'hébergement en ligne
 * créerait deux vérités (l'unité de la fiche et celle de la ligne) qui
 * divergeraient au premier déplacement de chambre. Le récapitulatif recompose
 * la part hébergement depuis `unite_id` × `tarif_nuit` × nuitées — une seule
 * source. Les arbitrages « plusieurs chambres » et « fiche sans hébergement »
 * restent ouverts (PA-110) et ne sont pas tranchés ici.
 *
 * ## `source_id` NOT NULL : une ligne sans origine est invérifiable
 *
 * Même règle que `lignes_facture` : chaque ligne pointe l'enregistrement réel
 * de son catalogue (plat, boisson à la carte, circuit, véhicule). Pas de FK
 * SQL — quatre tables cibles selon `service`, MySQL ne sait pas l'exprimer —
 * mais `ReservationService` refuse une source inexistante à l'écriture.
 *
 * ## Prix ET libellé FIGÉS à l'ajout
 *
 * Même raisonnement que `tarif_nuit` (PA-55) et que le panier (PA-98) : un
 * changement de carte ne doit jamais réécrire une fiche déjà convenue. Le
 * catalogue est LU au moment de l'ajout, jamais au moment de l'affichage.
 *
 * @see prototype_v2/pages/reservations-services.js le modèle du maître
 * @see docs/PLAN_ACTION_SEQUENCE_POST_AUDIT.md PA-163
 */
return new class () extends Migration {
    private const CONTRAINTES = [
        'chk_lignes_resa_service' => "service IN ('restauration', 'bar', 'tourisme', 'vehicule')",
        // Une quantité nulle ou négative n'est pas une ligne, c'est une
        // absence — le piège « zéro devient une unité » de PA-98, fermé au
        // schéma cette fois.
        'chk_lignes_resa_quantite' => 'quantite > 0',
        'chk_lignes_resa_prix' => 'prix_unitaire >= 0',
    ];

    public function up(): void
    {
        Schema::create('lignes_reservation', function (Blueprint $table): void {
            $table->uuid('id')->primary();

            $table->foreignUuid('reservation_id')
                ->constrained('reservations')->restrictOnDelete();

            $table->string('service', 20);
            $table->uuid('source_id');

            $table->string('libelle');
            $table->decimal('quantite', 10, 2);
            $table->decimal('prix_unitaire', 15, 2);
            $table->decimal('montant', 15, 2);

            $table->timestamps();

            $table->index(['reservation_id', 'service']);
        });

        foreach (self::CONTRAINTES as $nom => $expression) {
            DB::statement("ALTER TABLE lignes_reservation ADD CONSTRAINT {$nom} CHECK ({$expression})");
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('lignes_reservation');
    }
};
