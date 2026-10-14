<?php

declare(strict_types=1);

use Database\Migrations\Concerns\HasAuditColumns;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;

/**
 * Reprise du schema de `ventes` / `lignes_vente` — PA-159 lot 0b, T1.
 *
 * `2026_08_29_000003_create_ventes_table.php` a cree ces deux tables avec des
 * cles auto-incrementees et des colonnes de rattachement en `bigint unsigned`.
 * Trois consequences MESUREES contre `tatacora_dev` le 31/08/2026 :
 *
 *  1. `ventes.client_id` est un `bigint` alors que `clients.id` est un
 *     `char(36)`. La colonne ne PEUT PAS porter de cle etrangere : elle est
 *     restee un entier libre, jamais contrainte, toujours nulle. La regle du
 *     depot est explicite — « tout champ relationnel est une vraie cle
 *     etrangere, jamais du texte libre » (CLAUDE.md §6 regles).
 *  2. `ventes.utilisateur_id` a le meme defaut, et il porte RG-15 : une vente
 *     doit continuer de nommer qui l'a encaissee. Un entier non contraint ne
 *     nomme personne.
 *  3. `lignes_vente.vente_id` etait en `cascadeOnDelete()`, interdit sur une
 *     table transactionnelle (03_DATABASE_ENGINEERING.md §15) : la suppression
 *     d'une vente aurait emporte ses lignes sans laisser de trace.
 *
 * S'y ajoute la convention de cle : `$table->uuid('id')` fourni par le client,
 * jamais un auto-increment serveur — c'est aussi la cle de deduplication qui
 * rend la synchronisation idempotente (02_SOFTWARE_ARCHITECTURE.md, offline).
 *
 * ## Pourquoi une reprise par tables temporaires plutot qu'une suite d'ALTER
 *
 * Changer le type d'une cle primaire auto-incrementee referencee par une cle
 * etrangere demande, en MySQL, de defaire l'auto-increment, la contrainte, la
 * cle primaire, puis de les refaire — six ALTER dont l'ordre est le seul
 * garant. Renommer, recreer proprement et recopier donne un `up()` lisible,
 * un `down()` reellement symetrique, et surtout une table finale identique a
 * ce qu'une creation neuve produirait : aucun ecart possible entre une base
 * migree et une base fraiche.
 *
 * ## La reprise des donnees est faite, pas annoncee
 *
 * Trois ventes et cinq lignes existaient au moment de l'ecriture, toutes avec
 * `client_id`, `utilisateur_id` et `session_id` a NULL (releve du 31/08/2026).
 * Elles sont recopiees avec un UUID neuf et la correspondance ancien id -> UUID
 * est appliquee aux lignes. La reprise est triviale aujourd'hui et deviendra
 * impossible des que le journal de caisse sera reellement alimente.
 *
 * @see RG-15 Journalisation — `utilisateur_id` devient une vraie FK
 */
return new class () extends Migration {
    use HasAuditColumns;

    private const VENTES_REPRISE = 'ventes_reprise_uuid';

    private const LIGNES_REPRISE = 'lignes_vente_reprise_uuid';

    public function up(): void
    {
        if (! Schema::hasTable('ventes') || ! Schema::hasTable('lignes_vente')) {
            return;
        }

        if (Schema::getColumnType('ventes', 'id') === 'char') {
            // Deja reprise : `migrate` rejoue sur une base a jour ne doit pas
            // detruire les ventes qu'elle contient.
            return;
        }

        Schema::rename('ventes', self::VENTES_REPRISE);
        Schema::rename('lignes_vente', self::LIGNES_REPRISE);

        // Les noms de cle etrangere sont uniques a l'echelle du SCHEMA en
        // MySQL, pas de la table : sans cette suppression, la creation de la
        // nouvelle `lignes_vente` echouerait sur un nom deja pris par la table
        // renommee. Les noms d'INDEX, eux, sont propres a leur table et ne
        // posent pas ce probleme.
        Schema::table(self::LIGNES_REPRISE, function (Blueprint $table): void {
            $table->dropForeign('lignes_vente_vente_id_foreign');
        });

        $this->creerVentes();
        $this->creerLignesVente();
        $this->recopierVersUuid();

        Schema::drop(self::LIGNES_REPRISE);
        Schema::drop(self::VENTES_REPRISE);
    }

    public function down(): void
    {
        if (! Schema::hasTable('ventes') || ! Schema::hasTable('lignes_vente')) {
            return;
        }

        if (Schema::getColumnType('ventes', 'id') !== 'char') {
            return;
        }

        Schema::rename('ventes', self::VENTES_REPRISE);
        Schema::rename('lignes_vente', self::LIGNES_REPRISE);

        Schema::table(self::LIGNES_REPRISE, function (Blueprint $table): void {
            $table->dropForeign('lignes_vente_vente_id_foreign');
        });

        $this->creerVentesEntier();
        $this->creerLignesVenteEntier();
        $this->recopierVersEntier();

        Schema::drop(self::LIGNES_REPRISE);
        Schema::drop(self::VENTES_REPRISE);
    }

    private function creerVentes(): void
    {
        Schema::create('ventes', function (Blueprint $table): void {
            $table->uuid('id')->primary();
            $table->string('numero')->unique();
            // Une vente au comptoir appartient a une session de caisse : c'est
            // ce qui rend le rapprochement de fin de service possible
            // (EF-M2-07). Nullable parce que le registre porte aussi des
            // ventes reprises ou importees, qui n'en ont pas.
            $table->foreignUuid('session_id')->nullable()
                ->constrained('sessions_caisse')->restrictOnDelete();
            $table->string('point_vente', 50)->default('Bar');
            $table->foreignUuid('client_id')->nullable()
                ->constrained('clients')->restrictOnDelete();
            // Le LIBELLE de la table et sa CLE, les deux — `ventes-engine.js`
            // l.293-299 : le libelle seul ne permet aucune analyse par table,
            // la cle seule rend illisible une vente dont la table a ete
            // renommee depuis.
            // ⚠ « Aucun referentiel de tables de salle n'existe au schema »
            // a VIEILLI le 02/09/2026 : `tables_salle` existe (migration
            // 2026_09_06_200000). `table_id` reste une chaine libre malgre
            // tout — les ventes deja enregistrees portent les identifiants de
            // l'ancien registre d'ecran, et une FK les rendrait immigrables ;
            // motif date dans l'entete de la nouvelle migration.
            $table->string('table')->nullable();
            $table->string('table_id')->nullable();
            $table->decimal('montant_total', 15, 2)->default(0);
            $table->string('mode_paiement', 50)->default('especes');
            $table->boolean('encaisse')->default(true);
            $table->string('statut', 20)->default('validee');
            $table->string('motif_annulation')->nullable();
            $table->timestamp('annulee_at')->nullable();
            // RG-15 : une vente doit continuer de porter le nom de qui l'a
            // encaissee. `restrictOnDelete` et non `nullOnDelete` — un compte
            // desactive n'est jamais supprime, donc la contrainte ne bloque
            // aucun geste legitime, et elle interdit le seul geste qui
            // effacerait cette imputation.
            $table->foreignUuid('utilisateur_id')->nullable()
                ->constrained('utilisateurs')->restrictOnDelete();
            $table->json('stock_non_impacte')->nullable();
            $this->auditColumns($table);
            $table->timestamps();

            $table->index('point_vente');
            $table->index('mode_paiement');
            $table->index('statut');
            $table->index('created_at');
        });
    }

    private function creerLignesVente(): void
    {
        Schema::create('lignes_vente', function (Blueprint $table): void {
            $table->uuid('id')->primary();
            // `restrictOnDelete` remplace le `cascadeOnDelete` d'origine :
            // aucune ligne de vente ne doit disparaitre parce que sa vente a
            // ete supprimee — une vente ne se supprime pas, elle s'annule.
            $table->foreignUuid('vente_id')->constrained('ventes')->restrictOnDelete();
            $table->string('code')->nullable();
            $table->string('nom');
            $table->string('categorie')->nullable();
            $table->string('module', 10)->default('M5');
            $table->decimal('prix_unitaire', 15, 2);
            $table->integer('quantite')->default(1);
            $table->decimal('montant', 15, 2);
            $this->auditColumns($table);
            $table->timestamps();

            $table->index('module');
        });
    }

    private function recopierVersUuid(): void
    {
        $correspondance = [];

        foreach (DB::table(self::VENTES_REPRISE)->orderBy('id')->get() as $ancienne) {
            $uuid = (string) Str::uuid();
            $correspondance[(int) $ancienne->id] = $uuid;

            $ligne = (array) $ancienne;
            $ligne['id'] = $uuid;
            // Les trois colonnes de rattachement etaient des entiers non
            // contraints : aucune valeur n'y est interpretable comme un UUID.
            // Elles repartent a NULL plutot que de porter une correspondance
            // inventee.
            $ligne['client_id'] = null;
            $ligne['utilisateur_id'] = null;
            $ligne['session_id'] = null;
            $ligne['date_creation'] = $ancienne->created_at ?? now();

            DB::table('ventes')->insert($ligne);
        }

        foreach (DB::table(self::LIGNES_REPRISE)->orderBy('id')->get() as $ancienneLigne) {
            $venteUuid = $correspondance[(int) $ancienneLigne->vente_id] ?? null;

            if ($venteUuid === null) {
                // Une ligne orpheline ne peut pas etre rattachee : la taire
                // ferait disparaitre un montant du journal de caisse sans que
                // personne ne le sache.
                throw new RuntimeException(
                    'Ligne de vente '.$ancienneLigne->id.' rattachee a une vente absente ('
                    .$ancienneLigne->vente_id.') : reprise interrompue.',
                );
            }

            $ligne = (array) $ancienneLigne;
            $ligne['id'] = (string) Str::uuid();
            $ligne['vente_id'] = $venteUuid;
            $ligne['date_creation'] = $ancienneLigne->created_at ?? now();

            DB::table('lignes_vente')->insert($ligne);
        }
    }

    private function creerVentesEntier(): void
    {
        Schema::create('ventes', function (Blueprint $table): void {
            $table->id();
            $table->string('numero')->unique();
            $table->string('session_id')->nullable();
            $table->string('point_vente', 50)->default('Bar');
            $table->unsignedBigInteger('client_id')->nullable();
            $table->string('table')->nullable();
            $table->string('table_id')->nullable();
            $table->decimal('montant_total', 15, 2)->default(0);
            $table->string('mode_paiement', 50)->default('especes');
            $table->boolean('encaisse')->default(true);
            $table->string('statut', 20)->default('validee');
            $table->string('motif_annulation')->nullable();
            $table->timestamp('annulee_at')->nullable();
            $table->unsignedBigInteger('utilisateur_id')->nullable();
            $table->json('stock_non_impacte')->nullable();
            $table->timestamps();

            $table->index('point_vente');
            $table->index('mode_paiement');
            $table->index('statut');
            $table->index('created_at');
        });
    }

    private function creerLignesVenteEntier(): void
    {
        Schema::create('lignes_vente', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('vente_id')->constrained('ventes')->cascadeOnDelete();
            $table->string('code')->nullable();
            $table->string('nom');
            $table->string('categorie')->nullable();
            $table->string('module', 10)->default('M5');
            $table->decimal('prix_unitaire', 15, 2);
            $table->integer('quantite')->default(1);
            $table->decimal('montant', 15, 2);
            $table->timestamps();

            $table->index('module');
        });
    }

    private function recopierVersEntier(): void
    {
        $correspondance = [];

        foreach (DB::table(self::VENTES_REPRISE)->orderBy('created_at')->get() as $vente) {
            $ligne = (array) $vente;
            unset($ligne['id'], $ligne['utilisateur_creation_id'], $ligne['date_creation']);
            unset($ligne['utilisateur_modification_id'], $ligne['date_modification']);
            // Les colonnes de rattachement redeviennent des entiers : aucun
            // UUID n'y tient. La perte est REELLE et c'est le prix du retour
            // arriere — elle est ecrite ici plutot que decouverte apres coup.
            $ligne['client_id'] = null;
            $ligne['utilisateur_id'] = null;
            $ligne['session_id'] = null;

            $correspondance[(string) $vente->id] = (int) DB::table('ventes')->insertGetId($ligne);
        }

        foreach (DB::table(self::LIGNES_REPRISE)->orderBy('created_at')->get() as $ligneVente) {
            $venteId = $correspondance[(string) $ligneVente->vente_id] ?? null;

            if ($venteId === null) {
                throw new RuntimeException(
                    'Ligne de vente '.$ligneVente->id.' orpheline au retour arriere : interrompu.',
                );
            }

            $ligne = (array) $ligneVente;
            unset($ligne['id'], $ligne['utilisateur_creation_id'], $ligne['date_creation']);
            unset($ligne['utilisateur_modification_id'], $ligne['date_modification']);
            $ligne['vente_id'] = $venteId;

            DB::table('lignes_vente')->insert($ligne);
        }
    }
};
