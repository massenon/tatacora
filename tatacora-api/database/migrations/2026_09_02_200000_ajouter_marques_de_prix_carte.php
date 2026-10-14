<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Les deux marques de prix de la carte — PA-161, arbitrage (b) du 31/08/2026.
 *
 * ## Le defaut, et pourquoi il compte plus que les autres
 *
 * Le maitre marque six boissons `prix_provisoire` et six lignes de
 * sandwicherie `prix_corrige_main` (`prototype_v2/assets/js/referentiel-carte.js`
 * l.22-31 et l.169-179). Ce ne sont pas des ornements : l'ardoise du bar ne
 * donnait AUCUN prix pour EKU 66 cl, Guinness 66 cl, Vody / Loco, le vin
 * blanc, le vin rouge et le rhum. Un tarif a ete pose pour chacun sur decision
 * du Product Owner (17/08/2026, « mets des prix, on le modifiera apres »)
 * afin de debloquer le point de vente. Le maitre le dit sans detour : « ce
 * sont des prix de vente INVENTES : ils sont appliques a de vrais clients a
 * chaque service ».
 *
 * La PWA derivait la marque de `prix_vente <= 0` sur une colonne NOT NULL :
 * le compteur affichait donc « aucun prix provisoire » en permanence, sans
 * l'avoir verifie une seule fois — un indicateur qui affirme un etat qu'il
 * n'a pas mesure (PA-59/60/61). Le refus qui en decoulait est retire par le
 * meme lot : son motif cesse d'etre vrai avec cette migration, et un motif
 * perime transforme une decision en oubli (PA-144).
 *
 * ## Pourquoi ces marques doivent exister EN BASE, et non dans un fichier
 *
 * La fiche des prix est un papier REMIS AU CLIENT. Un prix provisoire imprime
 * sans sa marque devient un tarif ferme — c'est la version papier de PA-61 :
 * un document qui affirme une certitude que personne n'a etablie. Tant que la
 * marque vit dans le jeu de donnees du prototype et pas dans la table, le
 * document servi par le serveur ne peut pas la porter.
 *
 * ## Deux colonnes et non une, parce que ce sont deux faits distincts
 *
 * - `prix_provisoire` : le tarif a ete POSE faute de releve. Il reste a
 *   confronter a l'ardoise physique.
 * - `prix_corrige_main` : le tarif imprime a ete REMPLACE a la main. Une carte
 *   qui se corrige au stylo signale un tarif instable.
 *
 * Les six sandwiches du maitre portent la seconde SANS la premiere : les
 * fusionner en une colonne « tarif a revalider » perdrait la raison, et c'est
 * la raison qui dit quoi faire — aller lire l'ardoise, ou faire retirer
 * l'etiquette collee.
 *
 * ## NOT NULL DEFAULT false, jamais nullable
 *
 * Un troisieme etat « on ne sait pas » n'existe pas ici : un prix est
 * provisoire ou il ne l'est pas, et l'ignorance se lirait comme une absence de
 * marque de toute facon. `false` par defaut decrit exactement l'etat des
 * lignes existantes — aucune n'a jamais ete marquee — au lieu de le laisser
 * implicite. Les six boissons du maitre sont posees par le referentiel de
 * demonstration, pas ici : une migration qui semerait des donnees metier
 * ferait entrer un prix invente dans une base de production.
 *
 * @see EF-M4-01 Gestion des menus et cartes
 * @see EF-M5-02 Carte des boissons
 * @see PA-161 (b) Marques de prix — arbitrage du Product Owner du 31/08/2026
 */
return new class () extends Migration {
    /**
     * Les deux tables portent la MEME paire, et pour la meme raison : un plat
     * et une boisson sont deux lignes de la meme carte, rendues par le meme
     * ecran (`carte-module.js`) et imprimees sur la meme fiche des prix.
     *
     * @var list<string>
     */
    private const TABLES = ['cartes_boisson', 'plats'];

    /** @var list<string> */
    private const COLONNES = ['prix_provisoire', 'prix_corrige_main'];

    public function up(): void
    {
        foreach (self::TABLES as $table) {
            if (! Schema::hasTable($table)) {
                continue;
            }

            Schema::table($table, function (Blueprint $structure) use ($table): void {
                foreach (self::COLONNES as $colonne) {
                    if (Schema::hasColumn($table, $colonne)) {
                        continue;
                    }

                    // Juste apres le prix : les trois se lisent ensemble, et
                    // un `SHOW COLUMNS` doit montrer la marque a cote de ce
                    // qu'elle qualifie.
                    $structure->boolean($colonne)->default(false)->after('prix_vente');
                }
            });
        }
    }

    public function down(): void
    {
        foreach (self::TABLES as $table) {
            if (! Schema::hasTable($table)) {
                continue;
            }

            Schema::table($table, function (Blueprint $structure) use ($table): void {
                foreach (self::COLONNES as $colonne) {
                    if (Schema::hasColumn($table, $colonne)) {
                        $structure->dropColumn($colonne);
                    }
                }
            });
        }
    }
};
