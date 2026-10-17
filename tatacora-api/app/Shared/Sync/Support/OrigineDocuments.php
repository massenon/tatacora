<?php

declare(strict_types=1);

namespace App\Shared\Sync\Support;

use Closure;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Retient le POSTE D'ORIGINE des documents (table `origines_synchronisation`,
 * lot F4). Liée en SINGLETON : pendant qu'une opération d'un poste est
 * appliquée, [pendant()] ouvre une portée — tout document créé dedans (le
 * document lui-même, et ce que son service écrit en conséquence : les
 * mouvements de stock d'une réception, d'une vente) est attribué à ce poste.
 *
 * Hors portée (PWA, commandes artisan), rien n'est retenu : un document sans
 * origine est un document du serveur.
 */
final class OrigineDocuments
{
    private ?string $posteId = null;

    /** @var list<string> */
    private array $tablesMiroirs = [];

    /**
     * Applique `$travail` dans la portée du poste `$posteId`.
     *
     * @template T
     *
     * @param  list<string>  $tablesMiroirs  les tables DÉRIVÉES que le poste
     *                                       d'origine écrit déjà localement
     *                                       (exclues de SON flux)
     * @param  Closure(): T  $travail
     * @return T
     */
    public function pendant(string $posteId, array $tablesMiroirs, Closure $travail): mixed
    {
        [$avantPoste, $avantMiroirs] = [$this->posteId, $this->tablesMiroirs];
        $this->posteId = $posteId;
        $this->tablesMiroirs = $tablesMiroirs;

        try {
            return $travail();
        } finally {
            $this->posteId = $avantPoste;
            $this->tablesMiroirs = $avantMiroirs;
        }
    }

    public function actif(): bool
    {
        return $this->posteId !== null;
    }

    /**
     * Retient l'origine d'un document créé dans la portée. Sans portée : rien.
     * Une origine déjà retenue n'est jamais réécrite (le premier poste reste
     * l'auteur).
     */
    public function retenir(string $table, string $entiteId, bool $derive = true): void
    {
        if ($this->posteId === null) {
            return;
        }

        DB::table('origines_synchronisation')->insertOrIgnore([
            'id' => (string) Str::uuid(),
            'table_concernee' => $table,
            'entite_id' => $entiteId,
            'poste_id' => $this->posteId,
            'exclu_pour_poste' => $derive && in_array($table, $this->tablesMiroirs, true),
        ]);
    }
}
