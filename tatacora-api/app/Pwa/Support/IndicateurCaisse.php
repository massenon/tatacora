<?php

declare(strict_types=1);

namespace App\Pwa\Support;

use App\Domain\Caisse\Models\SessionCaisse;
use App\Models\User;

/**
 * L'indicateur de caisse de la barre supérieure — `#indicateur-caisse`.
 *
 * ## Le trou qu'il ferme (relevé du 31/08/2026)
 *
 * Le maître réserve cet emplacement dans sa barre (`shell.js` l.22) et
 * `caisse-ui.js` y rend un état réel : « Caisse fermée », ou « Clôturer la
 * caisse · bar » avec un point rouge passé 24 h d'ouverture. La barre servie
 * ne rendait RIEN — l'emplacement n'existait pas, et le Product Owner l'a vu
 * en confrontant les deux barres.
 *
 * ## Un écart de comportement, déclaré : LIEN, pas bouton d'action
 *
 * Chez le maître, cliquer ouvre/clôture la caisse sur place. Ici l'indicateur
 * NAVIGUE vers le POS comptant, qui possède le geste (modale de fond de
 * caisse, comptage du tiroir). La barre est rendue par chaque composant : y
 * câbler une écriture de caisse dupliquerait sur 40 écrans un geste qui a un
 * propriétaire. L'ÉTAT affiché, lui, est réel — dérivé de `sessions_caisse`,
 * jamais d'un libellé figé (PA-59/60/61).
 *
 * L'accès suit la règle unique du masquage : sans droit sur M5, pas
 * d'indicateur — le POS lui-même est masqué à ce rôle.
 *
 * @see prototype_v2/assets/js/caisse-ui.js l.168-193
 */
final class IndicateurCaisse
{
    /**
     * Libellés du maître pour `sessions_caisse.point_vente` — trois valeurs
     * fermées (`bar`, `restaurant`, `reception`), jamais un `ucfirst()`
     * générique : le maître écrit « Réception » avec son accent
     * (`prototype_v2/pages/pos.html` l.364), qu'un `ucfirst()` ne produirait
     * pas. Un point technique renvoyé tel quel (`· restaurant`) élargit le
     * bouton de quelques caractères de plus que le maître (`· Bar` /
     * `· Restaurant` / `· Réception`) et déplace la cloche d'autant — l'écart
     * mesuré lors de l'audit du 01/09/2026 vient d'ici, pas d'une classe
     * Tailwind différente.
     *
     * @see prototype_v2/assets/js/ventes-engine.js l.214 (« 'Bar' | 'Restaurant' »)
     * @see prototype_v2/pages/pos.html l.364 (repli « Réception »)
     */
    private const LIBELLES_POINT_VENTE = [
        'bar' => 'Bar',
        'restaurant' => 'Restaurant',
        'reception' => 'Réception',
    ];

    /**
     * @return array{etat: 'fermee'|'ouverte'|'tardive', point: string|null}|null
     *         `null` : rôle sans M5, aucun indicateur (masquage niveau 1).
     */
    public static function pour(?User $utilisateur): ?array
    {
        if ($utilisateur === null || $utilisateur->niveauSurModule('M5') === '-') {
            return null;
        }

        $session = SessionCaisse::query()
            ->whereNull('date_cloture')
            ->orderByDesc('date_ouverture')
            ->first();

        if ($session === null) {
            return ['etat' => 'fermee', 'point' => null];
        }

        // Le seuil des 24 h est celui du maître : une caisse ouverte depuis
        // plus d'une journée est une clôture oubliée, pas une session.
        // `date_ouverture` est non nulle par contrat de modèle (ouvrir une
        // caisse, c'est l'horodater) — le PHPDoc du modèle le garantit.
        $tardive = $session->date_ouverture->diffInHours(now()) >= 24;

        return [
            'etat' => $tardive ? 'tardive' : 'ouverte',
            'point' => self::LIBELLES_POINT_VENTE[$session->point_vente] ?? (string) $session->point_vente,
        ];
    }
}
