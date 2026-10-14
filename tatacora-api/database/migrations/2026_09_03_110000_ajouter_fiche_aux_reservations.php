<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * La FICHE du maître arrive au schéma serveur — PA-163 (01/09/2026).
 *
 * Décision du Product Owner : le formulaire complet de `reservations.html`
 * (canal, remise, mode de paiement) et la réservation rapide du tableau de
 * bord (canal obligatoire) doivent être saisissables dans la PWA. Jusqu'ici
 * PA-29 tenait ces champs HORS du serveur — la fiche restait locale au client
 * Flutter. La décision est LEVÉE pour ces colonnes, explicitement, pas
 * contournée : ce fichier est la levée.
 *
 * ## Toutes NULLABLES (ou avec défaut) — et c'est ce qui protège Flutter
 *
 * `POST /api/v1/sync` crée des réservations avec le jeu de champs de PA-57,
 * qui ne connaît aucune de ces colonnes. Une colonne NOT NULL sans défaut
 * ferait rejeter chaque lot hors ligne — le défaut exact que PA-29 redoutait.
 * Un client Flutter qui ne les envoie pas produit une réservation valide.
 *
 * ## `tarif_nuit` : le prix FIGÉ à la réservation
 *
 * PA-55 l'impose au client local depuis le schéma v2 : sans lui, un
 * changement de grille tarifaire réécrit le montant d'une réservation déjà
 * prise. Le serveur ne le portait pas (PA-57 : « le serveur ne connaît pas
 * `tarif_nuit` ») — le récapitulatif de la fiche PWA (sous-total, reste à
 * payer) le rend nécessaire ici aussi. NULLABLE : les réservations
 * antérieures n'en ont pas, et un récapitulatif sans tarif se REFUSE, il
 * n'invente pas le tarif courant à la place du tarif convenu.
 *
 * ## `remise_type` + `remise_valeur` : les deux champs du maître, pas un montant
 *
 * Le maître saisit un TYPE (aucune / % / FCFA) et une VALEUR. Stocker un
 * montant pré-calculé perdrait l'intention (« 10 % ») et rendrait la remise
 * fausse au premier ajout de ligne. Le montant se CALCULE, comme tout ce qui
 * se calcule (règle n° 3 du dépôt).
 *
 * @see prototype_v2/pages/reservations.html le formulaire complet
 * @see docs/PLAN_ACTION_SEQUENCE_POST_AUDIT.md PA-163
 */
return new class () extends Migration {
    private const CONTRAINTES = [
        'chk_reservations_remise_type' => "remise_type IN ('aucune', 'pourcentage', 'montant')",
        // Une remise « aucune » avec une valeur non nulle serait lisible et
        // fausse : l'écran l'ignorerait, un export la compterait.
        'chk_reservations_remise_coherente' => "remise_type <> 'aucune' OR remise_valeur = 0",
    ];

    public function up(): void
    {
        Schema::table('reservations', function (Blueprint $table): void {
            $table->foreignUuid('canal_id')->nullable()
                ->constrained('canaux_reservation')->restrictOnDelete();

            $table->decimal('tarif_nuit', 15, 2)->nullable();

            $table->string('remise_type', 20)->default('aucune');
            $table->decimal('remise_valeur', 15, 2)->default(0);

            // Chaîne libre bornée par validation applicative, PAS un
            // référentiel : le maître porte quatre modes en dur et aucun
            // écran d'administration — une table d'un seul lecteur serait un
            // second auteur en attente.
            $table->string('mode_paiement', 30)->nullable();
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
            $table->dropConstrainedForeignId('canal_id');
            $table->dropColumn(['tarif_nuit', 'remise_type', 'remise_valeur', 'mode_paiement']);
        });
    }
};
