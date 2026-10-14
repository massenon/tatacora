<?php

declare(strict_types=1);

namespace App\Domain\Notifications\Contracts;

/**
 * Un détecteur sait trouver les occurrences RÉELLES d'un déclencheur —
 * maître : `notifications-engine.js` l.76-232, méthode `detecter()` de
 * chaque entrée de `DECLENCHEURS`.
 *
 * Une classe par déclencheur COUVERT, jamais une seule classe qui lirait
 * tous les domaines : c'est le même principe que `Domain/Stocks/Etats/
 * EtatStocks` pour M14 — le code qui interroge un domaine VIT dans ce
 * domaine, et `RegistreDeclencheurs::detecteur()` ne fait que le nommer.
 *
 * Aucune écriture, aucun effet de bord : un détecteur lit, il ne compose ni
 * ne persiste — c'est `DetectionNotificationsService` qui fait les deux.
 */
interface DetecteurDeclencheurInterface
{
    /**
     * Les occurrences du jour. `reference` doit être STABLE pour la même
     * occurrence d'un appel à l'autre — c'est la moitié de la clé
     * d'idempotence (`unique(modele_id, reference)`), l'autre moitié étant
     * le modèle qui compose.
     *
     * `email` (01/09/2026) — l'adresse RÉELLE du destinataire, quand ce
     * détecteur sait la résoudre (`Client::email`...), `null` sinon. C'est
     * distinct de `destinataire`, qui reste un nom d'affichage : un
     * détecteur qui ne connaît aucune adresse doit rendre `null`, jamais le
     * nom en guise d'adresse.
     *
     * @return list<array{reference: string, destinataire: string, email?: string|null, variables: array<string, string>}>
     */
    public function detecter(): array;
}
