<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Taux de conversion « carte -> stock » — PA-159 lot 0b, T2.
 *
 * ## Le defaut
 *
 * La modale « Lier au stock » de M4 et M5 demande, en champ OBLIGATOIRE,
 * « Combien de X dans une unite de stock ? », et affiche en direct « Soit, en
 * unites vendables » puis « Chaque vente decrementera ». La reponse etait
 * jetee : le composant n'ecrivait que `article_id`. Un casier de 24 et une
 * bouteille vendue a l'unite produisaient le meme enregistrement, donc la meme
 * decrementation — fausse d'un facteur 24 pour l'un des deux, et l'ecart
 * n'apparait qu'a l'inventaire, impute a une perte physique.
 *
 * Le maitre le porte : `prototype_v2/assets/js/carte-engine.js` l.119-126
 * stocke `lien = { article_id, quantite }` et avertit lui-meme que « se tromper
 * de sens vide le stock 24 fois trop vite, ou 24 fois trop lentement ».
 *
 * ## Le SENS de la colonne est dans son nom, et c'est deliberé
 *
 * Deux conventions inverses coexistent dans les sources :
 *
 *  - le maitre stocke le nombre d'UNITES DE STOCK consommees par vente (1/24) ;
 *  - la modale demande le nombre d'UNITES VENDABLES contenues dans une unite
 *    de stock (24).
 *
 * La colonne retient la question posee a l'operateur — c'est la seule des deux
 * valeurs qu'un barman peut compter sans calcul —, et son nom l'ecrit en toutes
 * lettres : `unites_vendables_par_unite_stock`. La deduction vaut donc
 * `quantite_vendue / unites_vendables_par_unite_stock`. Nommer la colonne
 * `quantite` ou `ratio` aurait laisse le sens a la lecture du code, c'est-a-dire
 * a l'oubli.
 *
 * ## `plats.article_id` N'EXISTAIT PAS — defaut trouve en mesurant
 *
 * Le modele `Plat` declare `article_id` fillable, expose une relation
 * `article()` vers `App\Domain\Stocks\Models\Article`, et la vue Carte du
 * restaurant charge cette relation. La colonne, elle, n'est creee par AUCUNE
 * migration (releve `SHOW COLUMNS FROM plats` du 31/08/2026 : huit colonnes,
 * pas d'`article_id`). La relation ne levait pourtant aucune erreur : Eloquent
 * lit un attribut absent comme `null`, donc la jointure ne ramenait jamais
 * rien — un lien de stock qui parait exister et n'existe pas. C'est le meme
 * defaut que PA-126, une colonne rendue comme un fait alors que rien ne
 * l'alimente, a ceci pres que celle-ci n'existait meme pas. Elle est creee
 * ici, avant la colonne de conversion qui en depend.
 *
 * ## Nullable a un endroit, pas a l'autre — ecart assume a la consigne
 *
 * La consigne demandait la meme colonne nullable sur les deux tables. Elle
 * l'est sur `plats` et ne l'est PAS sur `cartes_boisson`, parce que les deux
 * liens n'ont pas la meme nature au schema :
 *
 *  - `cartes_boisson.article_id` est NOT NULL : une boisson a TOUJOURS un lien
 *    de stock. Une valeur nulle y signifierait « liee mais taux inconnu », un
 *    etat que le schema ne peut pas produire et qui arreterait silencieusement
 *    toute deduction RG-05 au bar. La colonne est donc NOT NULL DEFAULT 1.
 *  - `plats.article_id` est nullable : un plat se decremente normalement par sa
 *    fiche technique (EF-M4-02), pas par un article unique. NULL y veut dire
 *    « aucun lien direct », ce qui est un etat legitime et frequent.
 *
 * ## La valeur de reprise 1 n'est pas une hypothese
 *
 * C'est la description exacte de ce que le code faisait jusqu'ici :
 * `VenteBarService` sortait une unite de stock par unite vendue, en 1 pour 1,
 * et le docblock de la classe le dit. La reprise ecrit ce comportement au lieu
 * de le laisser implicite. Elle ne le corrige pas — corriger demande de
 * connaitre le conditionnement reel de chaque article, que seul le Gite peut
 * renseigner depuis la modale.
 *
 * @see RG-05 Sortie de stock automatique
 * @see EF-M4-02 Fiches techniques (recettes)
 * @see EF-M5-02 Carte des boissons
 */
return new class () extends Migration {
    private const COLONNE = 'unites_vendables_par_unite_stock';

    public function up(): void
    {
        if (Schema::hasTable('cartes_boisson') && ! Schema::hasColumn('cartes_boisson', self::COLONNE)) {
            Schema::table('cartes_boisson', function (Blueprint $table): void {
                $table->decimal(self::COLONNE, 15, 4)->default('1.0000')->after('article_id');
            });

            // Explicite meme si la valeur par defaut la couvre : une colonne
            // ajoutee sur des lignes existantes recoit le defaut, mais le dire
            // rend la reprise verifiable au lieu d'etre supposee.
            DB::table('cartes_boisson')->whereNull(self::COLONNE)->update([self::COLONNE => '1.0000']);
        }

        if (Schema::hasTable('plats') && ! Schema::hasColumn('plats', 'article_id')) {
            Schema::table('plats', function (Blueprint $table): void {
                // Vraie cle etrangere, jamais un identifiant libre — un plat
                // rattache a un article supprime rendrait sa deduction
                // inverifiable. `restrictOnDelete` comme partout ailleurs.
                $table->foreignUuid('article_id')->nullable()->after('recette_id')
                    ->constrained('articles')->restrictOnDelete();
            });
        }

        if (Schema::hasTable('plats') && ! Schema::hasColumn('plats', self::COLONNE)) {
            Schema::table('plats', function (Blueprint $table): void {
                $table->decimal(self::COLONNE, 15, 4)->nullable()->after('article_id');
            });

            // Seuls les plats DEJA rattaches a un article recoivent 1 : pour
            // les autres, la colonne doit rester nulle, sans quoi un taux
            // apparaitrait sur un plat qui ne decremente rien.
            DB::table('plats')->whereNotNull('article_id')->update([self::COLONNE => '1.0000']);
        }
    }

    public function down(): void
    {
        if (Schema::hasTable('cartes_boisson') && Schema::hasColumn('cartes_boisson', self::COLONNE)) {
            Schema::table('cartes_boisson', function (Blueprint $table): void {
                $table->dropColumn(self::COLONNE);
            });
        }

        if (Schema::hasTable('plats') && Schema::hasColumn('plats', self::COLONNE)) {
            Schema::table('plats', function (Blueprint $table): void {
                $table->dropColumn(self::COLONNE);
            });
        }

        if (Schema::hasTable('plats') && Schema::hasColumn('plats', 'article_id')) {
            Schema::table('plats', function (Blueprint $table): void {
                $table->dropForeign(['article_id']);
                $table->dropColumn('article_id');
            });
        }
    }
};
