<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Correspondances d'identifiants poste → serveur — décision du Product Owner
 * du 15/10/2026 (référentiels du catalogue).
 *
 * ## Pourquoi une table, et pas une réécriture des identifiants
 *
 * Le serveur est MAÎTRE du référentiel : les postes le téléchargent. Mais un
 * poste coupé du serveur peut créer un élément hors connexion (un fournisseur
 * livrant ce matin, absent du catalogue). À la synchronisation, si un élément
 * équivalent existe déjà côté serveur (clé naturelle), le serveur FUSIONNE —
 * aucun doublon — et retient ici que l'UUID du poste désigne désormais
 * l'élément serveur.
 *
 * Réécrire l'identifiant chez le poste ne suffirait pas : entre la création
 * hors connexion et la synchronisation, d'autres documents du même poste
 * (commandes d'achat, S2) citent déjà l'UUID local, et certains sont peut-être
 * encore dans la file. Le serveur les traduit par cette table, au moment où
 * il les reçoit — le poste, lui, remappe à réception de `fusionne_avec`.
 *
 * ## Unicité (table_concernee, id_poste)
 *
 * Un UUID de poste ne désigne qu'UN élément serveur. Deux postes créant le
 * même fournisseur produisent deux lignes (deux UUID de poste) vers le MÊME
 * `id_serveur` : c'est le cas nominal de la fusion, pas une anomalie.
 *
 * Aucune clé étrangère sur `id_serveur` : la table est générique (toutes les
 * tables du registre `TABLES_SYNCHRONISABLES`), et une contrainte par table
 * cible n'est pas exprimable sur une colonne polymorphe.
 */
return new class () extends Migration {
    public function up(): void
    {
        Schema::create('correspondances_synchronisation', function (Blueprint $table) {
            $table->uuid('id')->primary();

            // Provenance — le poste qui a créé l'élément hors connexion.
            $table->string('poste_id');
            $table->string('table_concernee');
            $table->uuid('id_poste');
            $table->uuid('id_serveur');
            $table->timestamp('created_at')->useCurrent();

            $table->unique(['table_concernee', 'id_poste']);
            // « Quels UUID de postes désignent cet élément ? » — diagnostic.
            $table->index(['table_concernee', 'id_serveur']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('correspondances_synchronisation');
    }
};
