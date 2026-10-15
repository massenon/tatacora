<?php

declare(strict_types=1);

namespace App\Shared\Sync\Contracts;

use App\Shared\Sync\Support\ContexteSynchronisation;
use App\Shared\Sync\Support\EcritureSynchronisee;

/**
 * Le gestionnaire d'UNE table synchronisable — seul chemin d'écriture de la
 * synchronisation sur cette table.
 *
 * ## Pourquoi un gestionnaire par table plutôt qu'un `if` dans le moteur
 *
 * Jusqu'au 15/10/2026, le moteur distinguait les tables par un test sur le
 * nom du service, et tout ce qui n'était pas une réservation tombait dans un
 * `DB::table($table)->insert/update($payload)` BRUT. Ce chemin écrivait sur
 * `clients` sans validation, sans RG-18, et pouvait même basculer l'archive
 * (`actif`) en contournant le verrou d'engagement que seul le service porte ;
 * sur `reservations`, une `modification` déplaçait un séjour SANS repasser
 * par RG-01. Chaque table nouvelle (fournisseurs, commandes d'achat, ventes —
 * décision PO du 15/10/2026) aurait élargi cette porte.
 *
 * Le contrat ferme la porte par construction : le moteur ne sait plus écrire,
 * il délègue. Un gestionnaire écrit par son service de domaine, ou refuse.
 *
 * ## Ce que chaque gestionnaire DÉCLARE
 *
 * - `module()` / `niveauRequis()` — le RBAC par opération (PA-65) : on ne peut
 *   pas rendre une table synchronisable sans dire qui a le droit d'y écrire.
 * - `serviceDomaine()` — le service par lequel passent ses écritures. Rendu
 *   visible pour que les tests vérifient qu'aucune table ne s'en passe.
 * - `accepteModification()` — `false` est un REFUS EXPLICITE : le moteur
 *   rejette la modification (« modification non synchronisable ») sans
 *   appeler `modifier()`. Il n'existe plus de repli générique.
 * - `estFinanciere()` — RG-17 : aucune résolution automatique de conflit.
 * - `champDateDocument()` — le champ du document qui porte sa date métier,
 *   à défaut de `date_metier` explicite (voir `ContexteSynchronisation`).
 *
 * D246 (décision PO du 15/10/2026) : un gestionnaire reçoit des documents
 * SOURCES, jamais des écritures comptables. Les écritures sont produites par
 * les services métier du serveur, à la date métier du contexte.
 */
interface GestionnaireSynchronisation
{
    /** La table du registre `TABLES_SYNCHRONISABLES` que ce gestionnaire sert. */
    public function table(): string;

    /** Module RBAC (`M1`…`M14`) dont le droit est exigé pour écrire. */
    public function module(): string;

    /** Niveau exigé sur ce module — `C` : toute opération synchronisée écrit. */
    public function niveauRequis(): string;

    /**
     * Service de domaine par lequel passent les écritures.
     *
     * @return class-string
     */
    public function serviceDomaine(): string;

    /** Table financière au sens de RG-17 (`ClassificationConflitService`). */
    public function estFinanciere(): bool;

    /** `false` : toute `modification` est rejetée, `modifier()` n'est jamais appelé. */
    public function accepteModification(): bool;

    /** Champ du payload portant la date métier du document, ou `null`. */
    public function champDateDocument(): ?string;

    /**
     * Crée l'élément sous l'UUID du poste — ou le FUSIONNE sur un élément
     * serveur équivalent, auquel cas `EcritureSynchronisee::$fusionneAvec`
     * porte l'identifiant serveur.
     *
     * @param  array<string, mixed>  $payload
     *
     * @throws \RuntimeException refus métier — rejet définitif, motif transmis au poste
     */
    public function creer(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee;

    /**
     * Applique une modification sur un élément EXISTANT (identifiant serveur,
     * déjà résolu par le moteur).
     *
     * @param  array<string, mixed>  $payload
     *
     * @throws \RuntimeException refus métier
     * @throws \LogicException si `accepteModification()` est faux
     */
    public function modifier(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee;
}
