<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * L'ANNULATION avec commission et remboursement — séance client du 18 et
 * 20/08/2026 (`Rapport_Presentation_Echange_TATACORA_AFRIQUE.pdf` §4.3/4.4/6.1/6.3),
 * précisée par instruction directe du Product Owner le 01/09/2026.
 *
 * ## Ce que le client a validé par écrit
 *
 * « La gestion de la commission doit être effectuée sur la base du montant
 * GLOBAL de la réservation, et non uniquement sur le montant de l'avance ou
 * de l'acompte versé » (§4.3). Un cas de référence est retenu : annulation à
 * MOINS DE 24 HEURES avant la prestation → taux de 50 %, PARAMÉTRABLE (§4.4,
 * §6.3) — voir `AnnulationReservationService` et `RegistreParametres`.
 *
 * ## Colonnes FIGÉES au moment de l'annulation, jamais recalculées après
 *
 * Même raisonnement que `tarif_nuit` (PA-55) et les lignes de service
 * (PA-163) : si la grille tarifaire ou la remise changeaient après coup, un
 * recalcul à la lecture rendrait un montant que personne n'a réellement
 * appliqué. `montant_total_annulation` est donc une COPIE figée de
 * `Reservation::montantTotal()` à l'instant T, pas une valeur dérivée à
 * l'affichage.
 *
 * ## Toutes NULLABLES — une réservation non annulée n'en porte aucune
 *
 * Une réservation active a huit colonnes NULL. Ce n'est pas une donnée
 * absente par erreur (PA-59/60/61) : c'est l'état normal d'une fiche qui n'a
 * jamais été annulée. `AnnulationReservationService` est l'unique écrivain.
 *
 * ## `utilisateur_annulation_id` et `date_annulation` sont DÉDIÉS
 *
 * `Auditable` (trait déjà posé sur `Reservation`) réécrit
 * `utilisateur_modification_id`/`date_modification` à CHAQUE mise à jour du
 * modèle — un geste ultérieur sans rapport avec l'annulation écraserait donc
 * cette trace si elle vivait sur ces colonnes génériques. Le Product Owner
 * l'exige nommément : « l'identité de la personne qui a effectué
 * l'annulation doit être conservée en audit ».
 *
 * ## `ecriture_remboursement_id` : NULL signifie « rien n'est sorti de caisse »
 *
 * Renseigné UNIQUEMENT quand `montant_rembourse_annulation` > 0 — c'est la
 * règle des sept qui ne souffrent aucune exception : « si RIEN n'est
 * remboursé (l'intégralité est retenue), aucun mouvement de caisse n'a lieu
 * — ne pas en fabriquer un ». Même sémantique que `ventes.ecriture_id`
 * (2026_09_02_600000) : la ligne DÉBIT de la pièce (4191 « Clients,
 * avances et acomptes reçus » ; 419100 avant le plan du PO du 10/10/2026), reconnue par son sens, jamais sa position.
 *
 * @see docs/PLAN_ACTION_SEQUENCE_POST_AUDIT.md EF-M1-06
 * @see App\Domain\Hebergement\Services\AnnulationReservationService
 */
return new class () extends Migration {
    private const CONTRAINTES = [
        'chk_reservations_taux_annulation' =>
            'taux_annulation IS NULL OR (taux_annulation >= 0 AND taux_annulation <= 100)',
        'chk_reservations_mode_remboursement' =>
            "mode_saisie_remboursement IN ('pourcentage', 'montant')",
        'chk_reservations_montant_commission_annulation' =>
            'montant_commission_annulation IS NULL OR montant_commission_annulation >= 0',
        'chk_reservations_montant_rembourse_annulation' =>
            'montant_rembourse_annulation IS NULL OR montant_rembourse_annulation >= 0',
    ];

    public function up(): void
    {
        Schema::table('reservations', function (Blueprint $table): void {
            // Le taux RÉELLEMENT appliqué à CETTE annulation — le paramètre
            // système ne fait que PRÉ-REMPLIR le formulaire, il n'est jamais
            // relu après coup (un taux modifié en Paramètres ne doit jamais
            // réécrire une annulation déjà décidée).
            $table->decimal('taux_annulation', 5, 2)->nullable()->after('mode_paiement');

            // Montant global de la réservation, figé à l'instant de
            // l'annulation — jamais recalculé (§ ci-dessus).
            $table->decimal('montant_total_annulation', 15, 2)->nullable()->after('taux_annulation');

            // Commission = montant_total_annulation × taux_annulation / 100,
            // sur le MONTANT GLOBAL — jamais sur le seul acompte (§4.3 du
            // compte rendu client).
            $table->decimal('montant_commission_annulation', 15, 2)->nullable()
                ->after('montant_total_annulation');

            $table->decimal('montant_rembourse_annulation', 15, 2)->nullable()
                ->after('montant_commission_annulation');

            // Comment l'opérateur a SAISI le remboursement — l'autre
            // représentation (montant ⇄ %) est dérivée, jamais stockée deux
            // fois : deux colonnes finiraient par diverger (PA-121).
            $table->string('mode_saisie_remboursement', 20)->nullable()
                ->after('montant_rembourse_annulation');

            // Date ET heure, pas seulement la date — exigé nommément par le
            // Product Owner.
            $table->dateTime('date_annulation')->nullable()->after('mode_saisie_remboursement');

            $table->foreignUuid('utilisateur_annulation_id')->nullable()->after('date_annulation')
                ->constrained('utilisateurs')->nullOnDelete();

            $table->foreignUuid('ecriture_remboursement_id')->nullable()->after('utilisateur_annulation_id')
                ->constrained('ecritures_comptables')->restrictOnDelete();
        });

        foreach (self::CONTRAINTES as $nom => $expression) {
            DB::statement("ALTER TABLE reservations ADD CONSTRAINT {$nom} CHECK ({$expression})");
        }
    }

    public function down(): void
    {
        foreach (array_keys(self::CONTRAINTES) as $nom) {
            DB::statement("ALTER TABLE reservations DROP CONSTRAINT {$nom}");
        }

        Schema::table('reservations', function (Blueprint $table): void {
            $table->dropConstrainedForeignId('ecriture_remboursement_id');
            $table->dropConstrainedForeignId('utilisateur_annulation_id');
            $table->dropColumn([
                'taux_annulation',
                'montant_total_annulation',
                'montant_commission_annulation',
                'montant_rembourse_annulation',
                'mode_saisie_remboursement',
                'date_annulation',
            ]);
        });
    }
};
