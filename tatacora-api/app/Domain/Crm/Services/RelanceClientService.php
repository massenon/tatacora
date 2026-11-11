<?php

declare(strict_types=1);

namespace App\Domain\Crm\Services;

use App\Domain\Crm\Models\Client;
use App\Domain\Crm\Models\RelanceClient;
use RuntimeException;

/**
 * Relances des clients débiteurs (M3) — PA-165, unique point d'écriture de
 * `relances_clients`.
 *
 * Une relance n'est pas un mouvement d'argent : aucune écriture comptable.
 * Le montant réclamé est FIGÉ au jour de l'appel — c'est ce qui a été dit au
 * client — pendant que le solde vivant, lui, se recalcule (PA-126). Les deux
 * peuvent diverger ensuite, et c'est normal : l'historique garde la parole
 * donnée, pas l'état courant.
 *
 * @see EF-M3-03 Relances clients
 */
class RelanceClientService
{
    private const PRECISION = 2;

    /**
     * `id` (facultatif) : l'identifiant né sur un poste hors connexion
     * (`GestionnaireRelancesClients`) — la relance le garde, ce qui rend son
     * rejeu idempotent.
     *
     * @param  array{id?: string, client_id: string, canal: string, montant_reclame: string, promesse?: string|null, commentaire?: string|null, date_relance?: string}  $donnees
     *
     * @throws RuntimeException canal hors registre, client inconnu ou montant invalide
     */
    public function enregistrer(array $donnees): RelanceClient
    {
        if (! in_array((string) $donnees['canal'], RelanceClient::CANAUX, true)) {
            throw new RuntimeException(__('crm.relance_canal_inconnu', ['canal' => (string) $donnees['canal']]));
        }

        if (! Client::query()->whereKey((string) $donnees['client_id'])->exists()) {
            throw new RuntimeException(__('crm.relance_client_inconnu'));
        }

        $montant = (string) $donnees['montant_reclame'];

        if (! is_numeric($montant) || bccomp($montant, '0', self::PRECISION) < 0) {
            throw new RuntimeException(__('crm.relance_montant_invalide'));
        }

        return RelanceClient::create([
            ...(isset($donnees['id']) && $donnees['id'] !== '' ? ['id' => (string) $donnees['id']] : []),
            'client_id' => (string) $donnees['client_id'],
            'date_relance' => (string) ($donnees['date_relance'] ?? now()->toDateString()),
            'canal' => (string) $donnees['canal'],
            'montant_reclame' => bcadd($montant, '0', self::PRECISION),
            'promesse' => ($donnees['promesse'] ?? '') === '' ? null : (string) $donnees['promesse'],
            'commentaire' => ($donnees['commentaire'] ?? '') === '' ? null : (string) $donnees['commentaire'],
        ]);
    }
}
