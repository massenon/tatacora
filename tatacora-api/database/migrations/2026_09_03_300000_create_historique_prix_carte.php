<?php

declare(strict_types=1);

use Database\Migrations\Concerns\HasAuditColumns;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Historique des prix de la carte — demande du Product Owner du 01/09/2026.
 *
 * ## La demande, telle qu'elle a été formulée
 *
 * « on peut modifier le prix d'un article de la restauration ou boisson — il
 * ne faut pas que le changement de ce prix impute les ventes précédentes ou
 * la comptabilité ; on doit retracer les changements de prix » (M4/M5).
 *
 * Le premier volet — l'IMMUNITÉ des ventes déjà encaissées — n'appelait aucun
 * code nouveau : `VenteService::resoudreLignes()` fige `prix_unitaire` sur
 * `lignes_vente` AVANT la transaction, et la pièce comptable est construite
 * sur ce montant figé. Une ligne de vente, son montant et la pièce ne relisent
 * plus jamais `cartes_boisson.prix_vente` ni `plats.prix_vente` après coup —
 * voir la mutation de `VenteServiceTest::le_prix_est_fige_a_l_encaissement…`
 * (PA-98) et son extension du 01/09/2026, qui ajoute le contrôle de la pièce.
 *
 * Cette table couvre le SECOND volet, qui n'existait nulle part : la TRACE.
 *
 * ## Pourquoi un OBSERVER et pas un service d'écriture
 *
 * Le prix se modifie par plusieurs chemins — `CarteBoissonService::modifier()`,
 * `CartePlatMenuService::modifier()`, un futur import, un seeder. Un service
 * de traçabilité que chacun devrait appeler explicitement serait oublié par
 * l'un d'eux tôt ou tard (même défaut que `EcritureComptableObserver`
 * documente pour RG-11). `CarteBoissonObserver` et `PlatObserver` couvrent
 * TOUS les chemins d'écriture Eloquent à la fois — c'est pourquoi ce modèle
 * n'a AUCUN service d'écriture : l'Observer est l'UNIQUE auteur de cette
 * table (même règle que « un référentiel a un seul auteur », PA-160/161).
 *
 * ## `source` + `source_id` plutôt que deux clés étrangères nullables
 *
 * `IndisponibiliteCarte` porte `boisson_id`/`plat_id`, deux vraies clés
 * étrangères sous contrainte CHECK. Ce choix n'est PAS repris ici :
 * `lignes_vente.code` (PA-98) pose déjà le précédent d'une référence en
 * CHAÎNE plutôt qu'une clé par table, pour la même raison — Q1 de
 * `PROPOSITION_MODELE_PANIER_POS.md` reste ouverte, et deux tables sources
 * pour un même historique auraient demandé la même contrainte CHECK
 * `(boisson_id IS NULL) <> (plat_id IS NULL)`. `source_id` n'est PAS une clé
 * étrangère : l'article peut être un `plat` retiré depuis (RG-02 ne s'applique
 * pas à la carte — aucune suppression n'existe dans ce dépôt, mais rien
 * n'interdit qu'un enregistrement de démonstration soit reseedé sous un autre
 * identifiant), et l'historique doit rester lisible même si son article n'est
 * plus retrouvable.
 *
 * ## `champ` couvre `prix_vente` ET `prix_corrige_main`, pas `prix_provisoire`
 *
 * `prix_vente` est LE prix. `prix_corrige_main` (`MarquesDePrix::CORRIGE_MAIN`)
 * est un FAIT directement lié au prix — « le tarif imprimé a été remplacé à la
 * main » — et sa bascule fait partie de ce qu'un changement de tarif doit
 * pouvoir retracer. `prix_provisoire` est une DÉCISION de gestion sur le
 * statut du tarif, pas un changement de son montant : elle reste hors de ce
 * registre, qui répond à une question précise — « qu'est-ce qui a changé sur
 * le PRIX ». Pour uniformiser la comparaison (`bccomp`, jamais `==` —
 * `MarquesDePrix` l.44-46), la bascule booléenne de `prix_corrige_main` est
 * portée dans les MÊMES colonnes `DECIMAL(15,2)` que `prix_vente`, sous la
 * forme `0.00`/`1.00` : un registre à deux colonnes selon le champ aurait
 * dédoublé la lecture de l'écran pour un gain nul.
 *
 * ## `ancien_prix`/`nouveau_prix` NULLABLES
 *
 * Les deux colonnes suivies (`prix_vente`, `prix_corrige_main`) sont
 * `NOT NULL` au schéma aujourd'hui : aucune ligne de ce dépôt ne devrait donc
 * porter `ancien_prix` ou `nouveau_prix` à `NULL` en pratique. La nullabilité
 * est posée par défense, pas pour couvrir un cas déjà vu : un champ de prix
 * qui deviendrait nullable demain (ex. un prix promotionnel) ne devra pas
 * exiger une seconde migration sur CETTE table pour representer un passage à
 * `NULL`.
 *
 * @see EF-M4-01 Gestion des menus et cartes
 * @see EF-M5-02 Carte des boissons
 * @see PA-98 Prix et libellé figés à l'encaissement
 * @see PA-161 (b) Les deux marques de prix de la carte
 */
return new class () extends Migration {
    use HasAuditColumns;

    public function up(): void
    {
        if (Schema::hasTable('historique_prix_carte')) {
            return;
        }

        Schema::create('historique_prix_carte', function (Blueprint $table): void {
            $table->uuid('id')->primary();
            $table->enum('source', ['carte_boisson', 'plat']);
            // Pas de clé étrangère : voir la note de l'entête sur `source_id`.
            $table->uuid('source_id');
            $table->enum('champ', ['prix_vente', 'prix_corrige_main']);
            $table->decimal('ancien_prix', 15, 2)->nullable();
            $table->decimal('nouveau_prix', 15, 2)->nullable();
            $this->auditColumns($table);
            $table->timestamps();

            // La seule question que l'écran pose : « l'historique de CET
            // article, du plus récent au plus ancien ». Nom explicite : le nom
            // déduit dépasserait les 64 caractères admis par MySQL.
            $table->index(['source', 'source_id', 'created_at'], 'idx_historique_prix_carte_article');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('historique_prix_carte');
    }
};
