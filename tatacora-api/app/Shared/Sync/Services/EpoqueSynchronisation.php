<?php

declare(strict_types=1);

namespace App\Shared\Sync\Services;

use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Str;

/**
 * L'ÉPOQUE de synchronisation — la façon, SANS WebSocket, de dire à un poste
 * « quelque chose a changé au serveur, descends » (décision du PO du 03/11/2026 :
 * « les données envoyées par un poste reviennent aux autres postes »).
 *
 * C'est un compteur de changements, incrémenté quand une opération d'un poste
 * est ACCEPTÉE (`SynchronisationService`) ou qu'un compte est supprimé au web.
 * Il est rendu dans la réponse du battement léger de 30 s
 * (`GET /api/v1/sync/demande`, champ `epoque`) ; le poste le compare à la
 * dernière époque qu'il a vue et, si elle a changé, lance UNE descente.
 *
 * ## Ce que l'époque n'est pas
 *
 * - Pas une donnée : aucun curseur n'en dépend, la descente reste incrémentale
 *   par table. Une époque perdue ou fausse coûte une descente de plus ou le
 *   cycle de 5 minutes, jamais une donnée.
 * - Pas bloquante : le poste fonctionne sans la lire.
 * - Pas un ordre : seule l'ÉGALITÉ compte. La valeur est « <nonce>.<n> » ; le
 *   nonce, tiré au premier usage, change si le cache est vidé — un compteur
 *   reparti de 1 ne retombe donc jamais sur une valeur déjà vue.
 */
class EpoqueSynchronisation
{
    private const CLE_COMPTEUR = 'sync.epoque.n';

    private const CLE_NONCE = 'sync.epoque.nonce';

    /** L'époque courante (« 0 » avant tout changement). */
    public function courante(): string
    {
        $n = (int) Cache::get(self::CLE_COMPTEUR, 0);

        return $this->nonce() . '.' . $n;
    }

    /** Un changement vient d'être accepté : rend la nouvelle époque. */
    public function incrementer(): string
    {
        // Le nonce AVANT le compteur : une époque ne se lit jamais sans nonce.
        $nonce = $this->nonce();
        Cache::add(self::CLE_COMPTEUR, 0);
        $n = (int) Cache::increment(self::CLE_COMPTEUR);

        return $nonce . '.' . $n;
    }

    private function nonce(): string
    {
        $nonce = Cache::get(self::CLE_NONCE);

        if (! is_string($nonce) || $nonce === '') {
            $nonce = Str::lower(Str::random(6));
            Cache::add(self::CLE_NONCE, $nonce);
            $nonce = (string) Cache::get(self::CLE_NONCE, $nonce);
        }

        return $nonce;
    }
}
