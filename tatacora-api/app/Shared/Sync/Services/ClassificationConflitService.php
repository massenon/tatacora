<?php

declare(strict_types=1);

namespace App\Shared\Sync\Services;

/**
 * Classification d'un conflit de synchronisation — RG-17.
 *
 * Squelette de `Shared/Sync` (Sprint 1) : le moteur de synchronisation complet
 * relève de LARAVEL_SYNC_FLUTTER.md et de son propre sprint. Ce qui est livré
 * ici est la seule partie qu'on ne peut pas se permettre de découvrir plus
 * tard — **la règle qui décide si un conflit a le droit d'être résolu
 * automatiquement**.
 *
 * Pourquoi maintenant plutôt qu'au sprint Sync : la liste des tables
 * financières est une donnée de sécurité. Si elle est écrite en même temps que
 * le moteur, elle sera écrite par quelqu'un qui pense « résolution de conflit »
 * et non « argent réel ». Une seule table oubliée dans cette liste, et un
 * paiement disparaît silencieusement à la synchronisation, sans erreur ni
 * trace — le scénario que RG-17 existe pour rendre impossible.
 */
class ClassificationConflitService
{
    /**
     * Tables sur lesquelles AUCUNE résolution automatique n'est permise —
     * 00_MASTER_INSTRUCTIONS.md §3 principe 4, RG-17.
     *
     * Liste FERMÉE : toute addition relève de l'Architecte, et tout retrait
     * est un incident de sécurité, pas une optimisation.
     *
     * @var list<string>
     */
    public const TABLES_FINANCIERES = [
        'factures',
        'lignes_facture',
        'avoirs',
        'paiements',
        'sessions_caisse',
        'mouvements_stock',
        'ecritures_comptables',
        'bulletins_paie',
    ];

    /**
     * Tables de plage de dates : un conflit n'y est pas une divergence de
     * versions d'un même enregistrement, mais deux enregistrements distincts
     * qui ne peuvent pas coexister (RG-01/RG-08/RG-13). Le second à
     * synchroniser est REJETÉ par VerificationChevauchementService, il n'entre
     * jamais dans la file d'arbitrage.
     *
     * @var list<string>
     */
    public const TABLES_STRUCTURELLES = [
        'reservations',
        'contrats_location',
        'plannings',
    ];

    /**
     * Décide du traitement d'un conflit sur une table donnée.
     *
     * @return 'arbitrage_manuel'|'rejet_structurel'|'resolution_automatique'
     */
    public function traitementPour(string $table): string
    {
        if (in_array($table, self::TABLES_FINANCIERES, true)) {
            return 'arbitrage_manuel';
        }

        if (in_array($table, self::TABLES_STRUCTURELLES, true)) {
            return 'rejet_structurel';
        }

        return 'resolution_automatique';
    }

    /**
     * Une table financière ne peut JAMAIS être résolue automatiquement,
     * quel que soit l'horodatage, quelle que soit l'urgence.
     */
    public function autoriseResolutionAutomatique(string $table): bool
    {
        return $this->traitementPour($table) === 'resolution_automatique';
    }
}
