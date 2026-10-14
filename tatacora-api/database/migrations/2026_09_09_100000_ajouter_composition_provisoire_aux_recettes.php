<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * La marque « composition provisoire » des fiches techniques — 04/09/2026,
 * arbitrage du Product Owner.
 *
 * ## Le defaut qu'elle accompagne
 *
 * Releve du 04/09/2026 en base de developpement : 83 plats, 83 recettes,
 * **3 lignes d'`ingredients_recette` en tout**. Chaque plat avait donc bien sa
 * fiche technique, et 82 sur 83 etaient VIDES — or une fiche vide n'est pas
 * une fiche qui ne consomme rien, c'est une vente REFUSEE
 * (`DeductionStockCuisineService` leve `RecetteManquanteException`). Le point
 * de vente restaurant etait bloque en entier.
 *
 * Le Product Owner a tranche : semer des compositions PLAUSIBLES pour
 * debloquer le service tout de suite, « on pourra modifier ». C'est exactement
 * la decision de PA-161 (b) sur les prix — « mets des prix, on le modifiera
 * apres » — et elle appelle exactement la meme protection.
 *
 * ## Pourquoi la marque doit exister EN BASE
 *
 * Un grammage seme decremente un stock REEL. Sans marque, une fiche devinee
 * et une fiche pesee par le cuisinier sont indiscernables une fois en base :
 * l'ecart ne se verrait qu'a l'inventaire, ou il serait impute a une perte
 * physique — une casse, un vol — qui n'a jamais eu lieu. C'est la forme exacte
 * de PA-59/60/61 appliquee au stock : un chiffre qui affirme une consommation
 * que personne n'a mesuree.
 *
 * ## `composition_provisoire` est un FAIT, et il TOMBE tout seul
 *
 * La marque se leve des que quelqu'un enregistre la composition — c'est le
 * raisonnement de `MarquesDePrix` sur `prix_corrige_main` : demander en plus
 * de cocher « ce n'est plus provisoire » reviendrait a faire declarer ce
 * qu'on vient de faire, et on l'oublierait. `CompositionRecetteService`
 * (unique auteur des lignes) la remet a `false` a chaque remplacement, sauf
 * decision explicite de l'appelant — c'est le seeder, et lui seul, qui la pose
 * a `true`.
 *
 * ## NOT NULL DEFAULT false, jamais nullable
 *
 * `false` decrit exactement l'etat des lignes existantes : aucune n'a jamais
 * ete marquee. Un troisieme etat « on ne sait pas » se lirait de toute facon
 * comme une absence de marque, et cette table n'a pas besoin d'un doute qui ne
 * change aucune decision.
 *
 * ⚠ Cette migration ne seme AUCUNE donnee metier. Les compositions
 * provisoires sont posees par `RestaurantSeeder` (Dev/Recette uniquement) :
 * une migration qui semerait des grammages les ferait entrer en Production.
 *
 * @see EF-M4-02 Gestion des fiches techniques de recette
 * @see RG-05 Sortie de stock automatique
 * @see PA-161 (b) Marques de prix — le precedent dont ceci reprend la forme
 */
return new class () extends Migration {
    private const TABLE = 'recettes';

    private const COLONNE = 'composition_provisoire';

    public function up(): void
    {
        if (! Schema::hasTable(self::TABLE) || Schema::hasColumn(self::TABLE, self::COLONNE)) {
            return;
        }

        Schema::table(self::TABLE, function (Blueprint $structure): void {
            // Juste apres le cout matiere : les deux se lisent ensemble — un
            // cout calcule sur des quantites devinees est un cout devine, et
            // un `SHOW COLUMNS` doit montrer la marque a cote de ce qu'elle
            // qualifie.
            $structure->boolean(self::COLONNE)->default(false)->after('cout_matiere_calcule');
        });
    }

    public function down(): void
    {
        if (! Schema::hasTable(self::TABLE) || ! Schema::hasColumn(self::TABLE, self::COLONNE)) {
            return;
        }

        Schema::table(self::TABLE, function (Blueprint $structure): void {
            $structure->dropColumn(self::COLONNE);
        });
    }
};
