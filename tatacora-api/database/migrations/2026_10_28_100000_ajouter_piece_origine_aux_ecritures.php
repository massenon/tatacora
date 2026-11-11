<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * L'IDENTIFIANT D'ORIGINE d'une pièce saisie sur un poste (D246 rouvert par
 * décision du PO du 28/10/2026 : les écritures saisies à la main sur un poste
 * sont partagées).
 *
 * Le poste envoie la pièce SOURCE de sa saisie sous un identifiant ; le serveur
 * la rejoue et passe SA pièce (ses lignes, son numéro). Cette colonne garde
 * l'identifiant du poste sur CHAQUE ligne de la pièce du serveur :
 *
 *  * elle rend la création IDEMPOTENTE (un rejeu retrouve la pièce déjà passée,
 *    sans second numéro) ;
 *  * elle descend avec l'écriture, et le poste reconnaît ainsi, dans son miroir
 *    de lecture, la pièce qu'il a lui-même saisie — pour ne jamais la compter
 *    deux fois.
 *
 * NULLABLE : une pièce du serveur (vente, dépense, clôture, saisie web) n'a pas
 * d'origine de poste. Index simple, jamais unique (N lignes par pièce).
 */
return new class () extends Migration {
    public function up(): void
    {
        // Le DOCUMENT SOURCE reçu du poste (en-tête de la saisie) : le moteur de
        // synchronisation lit chaque table du registre sous son nom et son `id`.
        if (! Schema::hasTable('pieces_saisie')) {
            Schema::create('pieces_saisie', function (Blueprint $table): void {
                $table->uuid('id')->primary();
                $table->string('journal', 10);
                $table->date('date_piece');
                $table->string('libelle');
                // brouillon | validee : le statut que le POSTE a donné à sa saisie.
                $table->string('statut', 10);
                $table->string('numero_piece', 20)->nullable();
                $table->unsignedSmallInteger('nombre_lignes');
                $table->string('poste_id');
                $table->foreignUuid('auteur_id')->nullable()->constrained('utilisateurs')->nullOnDelete();
                $table->timestamps();
            });
        }

        if (! Schema::hasColumn('ecritures_comptables', 'piece_origine_id')) {
            Schema::table('ecritures_comptables', function (Blueprint $table): void {
                $table->string('piece_origine_id', 36)->nullable()->after('numero_piece');
                $table->index('piece_origine_id');
            });
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('pieces_saisie');

        if (Schema::hasColumn('ecritures_comptables', 'piece_origine_id')) {
            Schema::table('ecritures_comptables', function (Blueprint $table): void {
                $table->dropIndex(['piece_origine_id']);
                $table->dropColumn('piece_origine_id');
            });
        }
    }
};
