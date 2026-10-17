<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Le POSTE D'ORIGINE de chaque document — lot F4, décision du Product Owner
 * du 17/10/2026 (« NE PLUS LIMITER » : tous les documents de tous les postes
 * descendent sur tous les postes).
 *
 * ## Deux usages
 *
 * 1. **Dire d'où vient un document** : le flux de descente le rend avec son
 *    poste (`poste_origine`) ; un document sans ligne ici a été saisi au
 *    serveur (PWA).
 * 2. **Ne pas renvoyer à un poste ce qu'il a DÉJÀ** (`exclu_pour_poste`) : un
 *    bon de réception poussé par le poste A fait écrire au serveur ses
 *    propres mouvements de stock (identifiants du serveur) ; le poste A, lui,
 *    a déjà écrit les siens localement. Les redescendre à A compterait la
 *    réception deux fois. Ces lignes DÉRIVÉES, que le poste d'origine tient en
 *    miroir, sont marquées et retirées du flux de CE poste seulement — les
 *    autres postes les reçoivent.
 *
 * Le document lui-même (même identifiant que chez le poste) n'est jamais
 * exclu : il redescend pour porter ses changements d'état (une vente annulée
 * sur la PWA).
 *
 * ## Reprise de l'existant
 *
 * Les documents poussés avant cette table ont leur poste dans
 * `deduplication_synchronisation` (rétention 30 jours) : la première ligne de
 * chaque (table, entité) y est reprise. Au-delà, le poste reste inconnu
 * (affiché « serveur »), jamais deviné.
 */
return new class () extends Migration {
    public function up(): void
    {
        Schema::create('origines_synchronisation', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('table_concernee');
            $table->uuid('entite_id');
            $table->string('poste_id');
            $table->boolean('exclu_pour_poste')->default(false);
            $table->timestamp('created_at')->useCurrent();

            $table->unique(['table_concernee', 'entite_id']);
            $table->index(['poste_id', 'exclu_pour_poste']);
        });

        $reprises = DB::table('deduplication_synchronisation')
            ->select('table_concernee', 'entite_id', DB::raw('MIN(poste_id) as poste_id'))
            ->whereNotNull('entite_id')
            ->groupBy('table_concernee', 'entite_id')
            ->get();

        foreach ($reprises as $r) {
            DB::table('origines_synchronisation')->insertOrIgnore([
                'id' => (string) \Illuminate\Support\Str::uuid(),
                'table_concernee' => $r->table_concernee,
                'entite_id' => $r->entite_id,
                'poste_id' => $r->poste_id,
                'exclu_pour_poste' => false,
            ]);
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('origines_synchronisation');
    }
};
