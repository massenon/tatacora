<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Les trois colonnes manquantes du tableau M6 — PA-161, arbitrage (a).
 *
 * ## Mesure AVANT creation, pas apres
 *
 * Releve `SHOW COLUMNS FROM articles` du 02/09/2026, base `tatacora_test_ab`
 * migree de zero : treize colonnes — `id`, `libelle`, `categorie`,
 * `unite_mesure`, `seuil_alerte`, `seuil_reappro`, `cout_moyen_pondere`, les
 * deux `timestamps` et les quatre colonnes d'audit. AUCUN rattachement a un
 * point de stockage, AUCUN mode de suivi, AUCUN prix d'achat. Aucune table
 * pivot non plus : `SHOW TABLES` ne rend que `articles`, `mouvements_stock` et
 * `points_stockage` sur ce perimetre. Les trois colonnes sont donc creees, pas
 * doublees.
 *
 * ## 1. `point_stockage_id` — un RATTACHEMENT, jamais une portee de stock
 *
 * ⚠ Cette colonne ne dit PAS ou se trouve le stock. Le stock reste calcule par
 * couple (article, point) depuis `mouvements_stock` : un meme article existe
 * simultanement au magasin et au bar, et `ConsultationStockService` continue
 * de l'agreger ainsi. La colonne porte le point PRINCIPAL de l'article — celui
 * que le maitre affiche en colonne « Point » (`m6-stocks.html` l.227) et
 * repropose par defaut a la saisie d'un mouvement (l.396). La lire pour
 * repondre a « combien en ai-je ? » serait le meme contresens que lire
 * `unites_hebergement.statut` pour repondre a « cette chambre est-elle
 * libre ? » (PA-118).
 *
 * Nullable, et c'est le point qui compte : les articles deja au referentiel
 * n'ont jamais ete receptionnes par cet ecran. Leur poser un point par defaut
 * — « Magasin general », par exemple — affirmerait un rattachement que
 * personne n'a decide. L'ecran rend « — » AVEC sa raison plutot qu'un lieu
 * plausible.
 *
 * `restrictOnDelete` comme partout : un article rattache a un point efface
 * deviendrait un rattachement muet.
 *
 * ## 2. `suivi` — la notion etait DEJA UTILISEE, sans colonne pour la porter
 *
 * Trois endroits du maitre s'en servent deja : la modale « Lier au stock »
 * (« Seuls les articles en suivi permanent apparaissent », `carte-module.js`
 * l.240), l'ouverture d'inventaire (`m6-inventaires.html` l.418) et le refus
 * de mouvement (`m6-stocks.html` l.380-383). Cote PWA, chacun de ces trois
 * points portait un motif de refus disant « le schema ne distingue pas encore
 * le suivi permanent de l'achat journalier ». C'est cette phrase qui cesse
 * d'etre vraie ici.
 *
 * `enum` et non `varchar` : le registre est FERME. Un « journaliere » saisi au
 * pluriel ferait disparaitre l'article de tous les filtres sans qu'aucun
 * message ne l'annonce.
 *
 * DEFAULT `permanent`, et ce n'est pas une hypothese : c'est la description
 * exacte du comportement en vigueur jusqu'ici. Tout article existant est suivi
 * en stock — il entre dans les mouvements, dans l'inventaire et dans la
 * valorisation. Ecrire `journalier` par defaut retirerait silencieusement du
 * bilan des marchandises reellement detenues.
 *
 * ## 3. `prix_achat` — le DERNIER prix connu, distinct du cout moyen pondere
 *
 * ⚠ Ne jamais y recopier le CMP. L'ecart entre les deux est precisement ce que
 * la colonne « Valeur d'achat » du maitre sert a montrer : il affiche a cote du
 * CMP la derive en pourcentage (`m6-stocks.html` l.219-220), un signal
 * d'inflation fournisseur. Recopier le CMP rendrait cette derive nulle par
 * construction — un indicateur qui annonce « aucune hausse » sans jamais avoir
 * rien mesure.
 *
 * Nullable : un article jamais receptionne n'a pas de prix d'achat, et zero se
 * lirait « gratuit ». Il est ecrit par `MouvementStockService::entree()`, qui
 * recoit deja le cout unitaire, et par la reception M7 qui passe par ce meme
 * service — un seul point d'ecriture, comme le CMP.
 *
 * `DECIMAL(15,2)` et cast `decimal:2` : la regle des montants du depot, jamais
 * un flottant.
 *
 * @see EF-M6-01 Referentiel articles multi-categories
 * @see EF-M6-03 Valorisation au cout moyen pondere
 * @see PA-161 (a) Les trois colonnes M6 — arbitrage du Product Owner du 31/08/2026
 */
return new class () extends Migration {
    /** Le registre FERME des modes de suivi — celui du maitre, l.312-314. */
    private const MODES_DE_SUIVI = ['permanent', 'journalier'];

    public function up(): void
    {
        if (! Schema::hasTable('articles')) {
            return;
        }

        if (! Schema::hasColumn('articles', 'point_stockage_id')) {
            Schema::table('articles', function (Blueprint $table): void {
                $table->foreignUuid('point_stockage_id')->nullable()->after('unite_mesure')
                    ->constrained('points_stockage')->restrictOnDelete();
            });
        }

        if (! Schema::hasColumn('articles', 'suivi')) {
            Schema::table('articles', function (Blueprint $table): void {
                $table->enum('suivi', self::MODES_DE_SUIVI)->default('permanent')->after('point_stockage_id');
            });
        }

        if (! Schema::hasColumn('articles', 'prix_achat')) {
            Schema::table('articles', function (Blueprint $table): void {
                // Juste AVANT `cout_moyen_pondere` : les deux se lisent l'un
                // contre l'autre, et leur ecart est l'information utile.
                $table->decimal('prix_achat', 15, 2)->nullable()->after('seuil_reappro');
            });
        }
    }

    public function down(): void
    {
        if (! Schema::hasTable('articles')) {
            return;
        }

        if (Schema::hasColumn('articles', 'point_stockage_id')) {
            Schema::table('articles', function (Blueprint $table): void {
                // La contrainte AVANT la colonne : MySQL refuse de retirer une
                // colonne encore portee par une cle etrangere.
                $table->dropForeign(['point_stockage_id']);
                $table->dropColumn('point_stockage_id');
            });
        }

        foreach (['suivi', 'prix_achat'] as $colonne) {
            if (Schema::hasColumn('articles', $colonne)) {
                Schema::table('articles', function (Blueprint $table) use ($colonne): void {
                    $table->dropColumn($colonne);
                });
            }
        }
    }
};
