<?php

declare(strict_types=1);

use Database\Migrations\Concerns\HasAuditColumns;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Le PANIER des deux points de vente — PA-161, arbitrage (f) du 31/08/2026.
 *
 * ## Ce qui est tranche, et ce qui ne l'est pas
 *
 * Q2 de `PROPOSITION_MODELE_PANIER_POS.md` demandait comment garantir
 * « un seul panier ouvert par sejour » sur MySQL. Deux options y etaient
 * posees : A, un service avec verrou pessimiste, sur le patron de
 * `VerificationChevauchementService` ; B, une colonne generee portant un index
 * unique. **L'arbitrage retient A**, et ce fichier en tire la consequence :
 *
 * ⚠ **L'index `(reservation_id, statut)` est SIMPLE, jamais unique.** Un index
 * unique sur ce couple n'exprimerait pas la regle : il interdirait un second
 * panier CLOTURE sur le meme sejour — c'est-a-dire le cas normal d'un client
 * qui consomme, se fait facturer, puis reconsomme. MySQL ne connait pas les
 * index partiels : « unique la ou `statut = ouvert` » ne s'ecrit pas. La
 * garantie vit donc dans `PanierService`, sous `lockForUpdate()`, exactement
 * comme RG-01 vit dans `VerificationChevauchementService` faute d'`EXCLUDE
 * USING gist`.
 *
 * ## Une seule table pour DEUX points de vente
 *
 * `reservation_id` est NULLABLE : le panier du comptoir n'a pas de sejour.
 * C'est ce qui fait partager la table aux deux ecrans — « le POS n'est pas une
 * structure, c'est un ecran » (PA-98) : la difference tient dans `type_vente`
 * et `reservation_id`, et nulle part ailleurs.
 *
 * ## `table_id` n'est PAS une cle etrangere deguisee
 *
 * ⚠ Le premier paragraphe de cette section a VIEILLI le 02/09/2026 : la table
 * `tables_salle` existe (migration `2026_09_06_200000_create_tables_salle`),
 * le plan de salle du POS la lit (`TableSalleService::planDeSalle()`), et le
 * registre d'ecran `PosComptant::PLAN_DE_SALLE` est retire. La colonne reste
 * pourtant une CHAINE, et la raison est datee dans l'entete de cette nouvelle
 * migration : les bases deja semees portent des paniers au `table_id` de
 * l'ancien registre (`tab-r1`…) — poser la FK ferait echouer la migration ou
 * reecrirait des lignes de vente. La conversion est un arbitrage ouvert a
 * l'Architecte, pas un oubli.
 *
 * ## `session_id` est la caisse d'OUVERTURE, pas celle d'encaissement
 *
 * `ventes.session_id` porte le tiroir qui a ENCAISSE. Celle-ci porte le tiroir
 * ouvert quand le panier a ete OUVERT. Les deux peuvent differer, et c'est
 * precisement le defaut que ce lot corrige : un panier qui survit a un
 * changement d'equipe est encaisse par une autre session que celle qui l'a vu
 * naitre. Ce ne sont donc pas deux copies d'un meme fait, mais deux faits.
 * Nullable : le POS des clients heberges n'a pas de caisse, et un panier peut
 * s'ouvrir avant l'ouverture du tiroir.
 *
 * ## Les CHECK disent ce que le code promet
 *
 * Quatre contraintes, chacune fermant un etat que rien d'autre n'interdirait :
 * les deux registres fermes (`type_vente`, `statut`), l'equivalence entre
 * « vente sur sejour » et « sejour renseigne », et l'interdiction pour un
 * panier OUVERT de porter une vente ou une date de cloture. Sans la derniere,
 * un panier pourrait etre a la fois ouvert et facture, et l'ecran afficherait
 * un encours deja encaisse.
 *
 * @see docs/PROPOSITION_MODELE_PANIER_POS.md §3, §5 (R-a a R-e) et §8 (Q2)
 * @see RG-02 Aucune suppression — un panier se cloture, il ne disparait pas
 */
return new class () extends Migration {
    use HasAuditColumns;

    /**
     * @var list<string>
     */
    private const CONTRAINTES_PANIERS = [
        'chk_paniers_type_vente' => "type_vente IN ('comptant', 'sejour')",
        'chk_paniers_statut' => "statut IN ('ouvert', 'cloture')",
        // Un panier de sejour SANS sejour, ou un panier comptant AVEC sejour,
        // seraient tous deux lisibles et faux. L'equivalence les ferme.
        'chk_paniers_sejour_coherent' => "(type_vente = 'sejour') = (reservation_id IS NOT NULL)",
        // Un panier ouvert ne peut ni porter une vente ni une date de cloture :
        // il serait encaisse ET encore encaissable.
        'chk_paniers_cloture_coherente' => "statut = 'cloture' OR (vente_id IS NULL AND cloture_at IS NULL)",
    ];

    public function up(): void
    {
        Schema::create('paniers', function (Blueprint $table): void {
            $table->uuid('id')->primary();

            // NULL au comptoir : c'est ce qui fait partager la table aux deux
            // points de vente. `restrictOnDelete` — une reservation ne se
            // supprime pas (RG-02), la contrainte ne bloque donc aucun geste
            // legitime et interdit le seul qui orphelinerait un panier.
            $table->foreignUuid('reservation_id')->nullable()
                ->constrained('reservations')->restrictOnDelete();

            $table->string('type_vente', 20);
            $table->string('point_vente', 50);
            // Chaine libre, PAS une cle etrangere : aucun referentiel de tables
            // de salle n'existe au schema (voir l'entete).
            $table->string('table_id')->nullable();

            $table->foreignUuid('session_id')->nullable()
                ->constrained('sessions_caisse')->restrictOnDelete();

            $table->string('statut', 20)->default('ouvert');

            // Posee A LA CLOTURE, quand une vente en est issue. Un panier
            // cloture sans `vente_id` a ete abandonne : la trace reste, le
            // montant n'a jamais existe.
            $table->foreignUuid('vente_id')->nullable()
                ->constrained('ventes')->restrictOnDelete();
            $table->timestamp('cloture_at')->nullable();

            $this->auditColumns($table);
            $table->timestamps();

            // ⚠ SIMPLE, jamais unique — voir l'entete. Il sert la lecture
            // « le panier ouvert de ce sejour » ET le verrou de portee de
            // `PanierService::ouvrirPourSejour()`.
            $table->index(['reservation_id', 'statut']);

            // AJOUT au schema arbitre, avec sa raison : le panier du comptoir
            // n'a pas de ligne parente a verrouiller (une reservation, elle,
            // existe deja). Le verrou de son ouverture porte donc sur la plage
            // d'index elle-meme, et sans cet index il n'y aurait aucune plage
            // a verrouiller — le controle d'unicite du poste serait une lecture
            // sans garantie.
            $table->index(['point_vente', 'table_id', 'statut']);
        });

        Schema::create('lignes_panier', function (Blueprint $table): void {
            $table->uuid('id')->primary();

            // `restrictOnDelete` et non `cascadeOnDelete` : une ligne de panier
            // ne doit pas disparaitre parce que son panier aurait ete supprime
            // — et un panier ne se supprime pas.
            $table->foreignUuid('panier_id')->constrained('paniers')->restrictOnDelete();

            // Le module est estampille sur la LIGNE, jamais deduit apres coup
            // de la categorie de l'article : c'est ce qui permet a un bar et a
            // un restaurant de partager un panier (regle du maitre, portee en
            // PA-98) sans qu'aucun rattachement ne se devine.
            $table->string('module', 10);
            // Chaine et non cle etrangere : une meme ligne peut viser
            // `cartes_boisson` ou `plats`, deux tables differentes. C'est la
            // question Q1, ouverte aupres de l'Architecte — la trancher ici en
            // inventant une colonne par table ferait diverger le serveur du
            // client Flutter, qui a retenu le registre ferme plus une
            // verification reelle d'existence.
            $table->uuid('reference_id');

            // FIGES a l'ajout, comme `tarifNuit` (PA-55) et les lignes de vente
            // (PA-98) : un panier de sejour vit plusieurs jours, la carte peut
            // changer entre-temps, et le montant deja annonce au client ne doit
            // pas bouger sous lui.
            $table->string('libelle');
            $table->decimal('prix_unitaire', 15, 2);
            $table->integer('quantite')->default(1);

            $this->auditColumns($table);
            $table->timestamps();

            $table->index('module');
            $table->index(['panier_id', 'module', 'reference_id']);
        });

        foreach (self::CONTRAINTES_PANIERS as $nom => $predicat) {
            DB::statement('ALTER TABLE paniers ADD CONSTRAINT '.$nom.' CHECK ('.$predicat.')');
        }

        // Une quantite saisie a ZERO ne devient jamais une unite facturee
        // (PA-98, `QuantiteSaisie`) : elle ne cree pas une ligne a zero franc,
        // elle ne cree rien. La contrainte le tient meme si un jour un import
        // ou un job contournait le service.
        DB::statement(
            'ALTER TABLE lignes_panier ADD CONSTRAINT chk_lignes_panier_quantite CHECK (quantite >= 1)',
        );
    }

    public function down(): void
    {
        // L'ordre est la substance : `lignes_panier` porte la cle etrangere
        // vers `paniers`, la detruire d'abord evite d'avoir a la defaire.
        Schema::dropIfExists('lignes_panier');
        Schema::dropIfExists('paniers');
    }
};
