<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Rattachement comptable des ventes encaissees — la regle du 31/08/2026.
 *
 * ## Ce que cette colonne rend possible
 *
 * « Tout mouvement d'argent produit son ecriture comptable reelle, cote
 * domaine, dans la meme transaction. » `DepenseService` tenait deja la moitie
 * sortante depuis PA-159 lot 0b ; la moitie entrante — les ventes du point de
 * vente — n'ecrivait rien du tout. Cinq ventes en base, zero ecriture, un
 * journal des ventes vide, et un compte de resultat qui ne voyait que des
 * charges.
 *
 * ## Ce que `ecriture_id` designe exactement
 *
 * La LIGNE DE CONTREPARTIE de la piece — l'unique DEBIT, qui porte le montant
 * total encaisse (tresorerie) ou porte en compte client (note de chambre). Ce
 * n'est pas « la piece » : PA-52 constate que `ecritures_comptables` n'a
 * aucune colonne groupant les lignes d'une meme piece, et rien ici ne repare
 * cela. La ligne de contrepartie est retenue parce qu'elle est la seule dont
 * il existe exactement une par vente, quel que soit le nombre de comptes de
 * produits ventiles — symetrique exact de `depenses.ecriture_id`, ou c'est la
 * ligne de tresorerie (l'unique credit) qui joue ce role.
 *
 * ## `restrictOnDelete`, et ce n'est pas une precaution de style
 *
 * Une ecriture validee est immuable (RG-11) et ne se supprime jamais :
 * `EcritureComptableObserver` leve a `deleting()`. La contrainte dit la meme
 * chose au moteur, pour le jour ou quelqu'un passera par SQL direct.
 * `cascadeOnDelete()` est de toute facon interdit sur une table
 * transactionnelle (03_DATABASE_ENGINEERING.md §15).
 *
 * Nullable : les ventes ecrites AVANT ce lot n'ont pas de piece, et le dire
 * par un NULL vaut mieux que de leur en fabriquer une retroactivement.
 * `VenteService::comptabiliser()` est le rattrapage, geste explicite.
 *
 * @see RG-11 Immutabilite — la correction passe par contre-passation
 */
return new class () extends Migration {
    public function up(): void
    {
        if (! Schema::hasTable('ventes') || ! Schema::hasTable('ecritures_comptables')) {
            return;
        }

        if (Schema::hasColumn('ventes', 'ecriture_id')) {
            return;
        }

        Schema::table('ventes', function (Blueprint $table): void {
            $table->foreignUuid('ecriture_id')->nullable()->after('utilisateur_id')
                ->constrained('ecritures_comptables')->restrictOnDelete();
        });
    }

    public function down(): void
    {
        if (! Schema::hasTable('ventes') || ! Schema::hasColumn('ventes', 'ecriture_id')) {
            return;
        }

        Schema::table('ventes', function (Blueprint $table): void {
            // La contrainte se retire AVANT la colonne : MySQL refuse de
            // supprimer une colonne encore referencee par une cle etrangere,
            // et un `down()` qui echoue a mi-parcours laisse un schema que
            // personne ne sait plus decrire.
            $table->dropForeign(['ecriture_id']);
            $table->dropColumn('ecriture_id');
        });
    }
};
