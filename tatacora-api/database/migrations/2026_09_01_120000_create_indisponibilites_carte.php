<?php

declare(strict_types=1);

use Database\Migrations\Concerns\HasAuditColumns;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Indisponibilite d'un article de carte — PA-159 lot 0b, T3.
 *
 * ## Le defaut
 *
 * `CarteBar::enregistrerDispo()` et `CarteRestaurant::enregistrerDispo()`
 * ecrivaient dans `Session::put(...)`. Trois consequences :
 *
 *  1. un plat retire revient tout seul a la carte a l'expiration de la
 *     session, sans que personne ne l'ait remis ;
 *  2. aucun autre poste ne le voit retire — le barman du comptoir continue de
 *     le vendre pendant que la cuisine le sait en rupture ;
 *  3. la decision n'est imputable a personne.
 *
 * ## Les codes sont ceux du MAITRE, pas ceux de la PWA
 *
 * `prototype_v2/assets/js/carte-engine.js` l.51-55 pose `rupture` / `saison` /
 * `retire` ; la PWA ecrivait `rupture` / `hors_saison` / `retrait`. Les
 * libelles affiches etant identiques, la divergence etait invisible a l'ecran
 * et se serait vue le jour d'un export ou d'un rapprochement avec le maitre.
 * Le maitre fait foi (`DIRECTIVE_CONFORMITE_100.md`) : l'`enum` porte ses trois
 * codes, et rien d'autre — un registre ferme, pas une chaine libre.
 *
 * `temporaire` (vrai pour `rupture` et `saison`, faux pour `retire`) n'est PAS
 * une colonne : c'est une propriete du code, portee par
 * `IndisponibiliteCarte::MOTIFS`. Stockee, elle pourrait diverger de son motif
 * a la premiere saisie incoherente.
 *
 * ## Deux cles etrangeres plutot qu'une reference polymorphe
 *
 * `boisson_id` et `plat_id` sont deux VRAIES cles etrangeres, dont une seule
 * est renseignee — contrainte CHECK a l'appui. Un couple
 * `(type_article, article_id)` aurait ete une reference non contrainte : rien
 * n'aurait empeche d'y ecrire l'identifiant d'un plat supprime, ou d'une table
 * qui n'existe pas. La regle du depot est explicite : tout champ relationnel
 * est une vraie cle etrangere.
 *
 * ## Lever une indisponibilite est une ECRITURE, jamais une suppression
 *
 * `date_retour_disponibilite` cloture la ligne au lieu de l'effacer. Le « D »
 * de CRUD n'existe nulle part dans ce depot, et l'historique des ruptures est
 * precisement ce qui permet de decider d'un reapprovisionnement : effacer la
 * ligne effacerait la question.
 *
 * @see EF-M4-01 Gestion des menus et cartes
 * @see EF-M5-02 Carte des boissons
 */
return new class () extends Migration {
    use HasAuditColumns;

    public function up(): void
    {
        if (Schema::hasTable('indisponibilites_carte')) {
            return;
        }

        Schema::create('indisponibilites_carte', function (Blueprint $table): void {
            $table->uuid('id')->primary();
            $table->foreignUuid('boisson_id')->nullable()
                ->constrained('cartes_boisson')->restrictOnDelete();
            $table->foreignUuid('plat_id')->nullable()
                ->constrained('plats')->restrictOnDelete();
            $table->enum('motif', ['rupture', 'saison', 'retire']);
            $table->text('commentaire')->nullable();
            $table->timestamp('date_indisponibilite');
            // NOT NULL : retirer un article de la carte du jour est une
            // decision de gestion. Une decision anonyme n'est pas opposable.
            $table->foreignUuid('utilisateur_id')->constrained('utilisateurs')->restrictOnDelete();
            $table->timestamp('date_retour_disponibilite')->nullable();
            $table->foreignUuid('utilisateur_retour_id')->nullable()
                ->constrained('utilisateurs')->restrictOnDelete();
            $this->auditColumns($table);
            $table->timestamps();

            // Les deux index servent la meme question, la seule que l'ecran
            // pose : « cet article est-il indisponible en ce moment ? ».
            // Noms explicites : les noms deduits depassaient les 64 caracteres
            // admis par MySQL pour un identifiant.
            $table->index(['boisson_id', 'date_retour_disponibilite'], 'idx_indispo_carte_boisson_retour');
            $table->index(['plat_id', 'date_retour_disponibilite'], 'idx_indispo_carte_plat_retour');
        });

        // Exactement une des deux cles — MySQL 8.0.16+/MariaDB 10.2.1+.
        // `Blueprint::check()` n'existe pas nativement en Laravel (piege
        // recense dans CLAUDE.md), d'ou le passage par une instruction brute.
        DB::statement(
            'ALTER TABLE indisponibilites_carte ADD CONSTRAINT chk_indisponibilites_carte_cible '
            .'CHECK ((boisson_id IS NULL) <> (plat_id IS NULL))',
        );
    }

    public function down(): void
    {
        Schema::dropIfExists('indisponibilites_carte');
    }
};
