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
 *   appeler `modifier()`. Il n'existe plus de repli générique. Depuis la
 *   décision PO du 15/10/2026 (« offline-first total »), TOUT le catalogue
 *   l'accepte — articles, boissons, plats, menus, fiches, points de stockage,
 *   catégories et unités d'hébergement, fournisseurs — en dernier écrit
 *   gagnant sur l'horodatage de saisie (`SynchronisationService`).
 * - `modificationSurInconnu()` — que faire d'une modification dont la cible
 *   est inconnue du serveur (création jamais reçue, ouverture refusée).
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

    /**
     * Tous les modules dont l'écriture est exigée pour CE payload — au moins
     * `module()`. Une vente portant des plats exige aussi M4 (lot S3,
     * 15/10/2026), comme l'écran en ligne.
     *
     * @param  array<string, mixed>  $payload
     * @return list<string>
     */
    public function modulesRequis(array $payload): array;

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
     * Une `creation` arrive sur un identifiant qui EXISTE déjà, sous l'UUID
     * même du poste (lot S3, 15/10/2026).
     *
     * Pour un DOCUMENT (vente, dépense, commande, bon de réception, session de
     * caisse), c'est le même document rejoué : le gestionnaire rend le
     * résultat d'origine — rien n'est réécrit. `null` (référentiels, fiches)
     * garde le rejet « création sur identifiant existant » : une fiche ne se
     * réécrit pas en se déclarant nouvelle.
     */
    public function reprendreExistant(string $entiteId, ContexteSynchronisation $contexte): ?EcritureSynchronisee;

    /**
     * Une `modification` vise un identifiant que le serveur ne connaît pas —
     * ni tel quel, ni par correspondance (décision PO du 15/10/2026).
     *
     * `null` garde le rejet `sync.modification_entite_inconnue`. Le catalogue
     * y voit une création perdue en route : si le payload est assez complet
     * pour les règles de CRÉATION, l'élément est créé (ou fusionné) ; sinon
     * rejet motivé. La caisse y voit la clôture d'une session dont
     * l'ouverture a été refusée ou jamais reçue : acceptée sans rien écrire
     * qu'une anomalie (`cloture_sans_session_serveur`) — une clôture n'est
     * jamais bloquée.
     *
     * @param  array<string, mixed>  $payload
     *
     * @throws \RuntimeException refus métier
     */
    public function modificationSurInconnu(string $entiteId, array $payload, ContexteSynchronisation $contexte): ?EcritureSynchronisee;

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
