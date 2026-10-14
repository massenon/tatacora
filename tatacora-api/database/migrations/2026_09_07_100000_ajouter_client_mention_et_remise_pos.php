<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Directive Product Owner du 02/09/2026 — couloir POS/documents.
 *
 * ## `ventes.client_mention` — une MENTION imprimée, pas une clé étrangère
 *
 * Le POS comptant perd son sélecteur de clients : la vente au comptoir est
 * anonyme par nature, et proposer le référentiel M3 au comptoir poussait à
 * rattacher n'importe quel passant à une fiche client. Le champ devient un
 * texte libre FACULTATIF, imprimé sur le ticket et la facture de la vente.
 *
 * ⚠ ÉCART ASSUMÉ à la règle « tout champ relationnel est une vraie clé
 * étrangère, jamais du texte libre » (CLAUDE.md, 7 règles) — décision PO du
 * 02/09/2026 : cette colonne n'est PAS relationnelle. Elle n'alimente aucun
 * registre client, ne porte aucun solde, ne rejoint jamais `clients` — c'est
 * le nom que le client au comptoir demande à voir sur son papier, rien
 * d'autre. `ventes.client_id` (la vraie FK) reste en place : le POS des
 * clients hébergés continue de la renseigner, et les ventes comptant déjà
 * liées à un client conservent leur donnée.
 *
 * ## `paniers.remise_type` + `paniers.remise_valeur` — le motif de `reservations`
 *
 * Les deux champs du maître de la fiche de réservation, jamais un montant
 * pré-calculé : stocker le montant perdrait l'intention (« 10 % ») et rendrait
 * la remise fausse au premier article ajouté. Le montant est DÉRIVÉ par
 * l'auteur unique `Panier::remiseSur()` (net = total − remise, bcmath,
 * jamais négatif). La remise se FIGE à la clôture comme les prix : un panier
 * clôturé est immuable (`PanierService::exigerOuvert()`), ses colonnes de
 * remise avec lui.
 *
 * Les CHECK reprennent mot pour mot ceux de
 * `2026_09_03_110000_ajouter_fiche_aux_reservations.php` : même registre
 * fermé, même interdiction d'une remise « aucune » à valeur non nulle.
 */
return new class () extends Migration {
    /**
     * @var array<string, string>
     */
    private const CONTRAINTES_PANIERS = [
        'chk_paniers_remise_type' => "remise_type IN ('aucune', 'pourcentage', 'montant')",
        'chk_paniers_remise_coherente' => "remise_type <> 'aucune' OR remise_valeur = 0",
    ];

    public function up(): void
    {
        Schema::table('ventes', function (Blueprint $table): void {
            // Nullable : « aucune mention » et « mention vide » ne doivent pas
            // se distinguer — le ticket omet la ligne dans les deux cas.
            $table->string('client_mention')->nullable()->after('client_id');
        });

        Schema::table('paniers', function (Blueprint $table): void {
            $table->string('remise_type', 20)->default('aucune')->after('statut');
            $table->decimal('remise_valeur', 15, 2)->default(0)->after('remise_type');
        });

        foreach (self::CONTRAINTES_PANIERS as $nom => $condition) {
            // `Blueprint::check()` n'existe pas en Laravel (piège documenté au
            // CLAUDE.md §Équivalences MySQL) : SQL brut, comme les migrations
            // sœurs.
            DB::statement("ALTER TABLE paniers ADD CONSTRAINT {$nom} CHECK ({$condition})");
        }
    }

    public function down(): void
    {
        foreach (array_keys(self::CONTRAINTES_PANIERS) as $nom) {
            DB::statement("ALTER TABLE paniers DROP CONSTRAINT {$nom}");
        }

        Schema::table('paniers', function (Blueprint $table): void {
            $table->dropColumn(['remise_type', 'remise_valeur']);
        });

        Schema::table('ventes', function (Blueprint $table): void {
            $table->dropColumn('client_mention');
        });
    }
};
