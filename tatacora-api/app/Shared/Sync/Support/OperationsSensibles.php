<?php

declare(strict_types=1);

namespace App\Shared\Sync\Support;

/**
 * La LISTE FERMÉE des opérations d'un poste que le serveur juge encore sur le compte
 * du JETON D'APPAIRAGE — décision du Product Owner du 09/11/2026.
 *
 * ## La règle générale
 *
 * « Le jeton du poste porte un seul compte. Tout ce qui sort d'un poste appairé par le
 * barman est jugé sur les droits du barman : NON, ÇA NE DOIT PAS JUGER. » Le contrôle
 * des droits se fait AU POSTE, sur l'utilisateur connecté (RBAC local) ; le serveur
 * accepte les opérations d'un poste de confiance — appairé par un administrateur,
 * jeton révocable, génération des données concordante, compte actif — et garde ce qui
 * est de la COHÉRENCE métier (référence inconnue, chevauchement, montant, statut,
 * idempotence, ordre). Le WEB, lui, garde le RBAC par module et par action.
 *
 * ## Ce qui reste jugé (décisions explicites du PO, et elles seules)
 *
 * Chacune est rejetée SEULE (`droit_manquant`, phrase lisible, « À traiter », relançable)
 * et ne bloque ni les opérations suivantes de la file ni les tables suivantes du lot.
 *
 *  - suppression d'un COMPTE : `super_admin` (03/11/2026, `User::peutSupprimerDesComptes`) ;
 *  - réglages de la facturation normalisée (mode, API, opérateur) et FORME JURIDIQUE :
 *    administrateur (09/11/2026, `GestionnaireParametres::refusDeDroit`) ;
 *  - clôture d'exercice (démarrer, reprendre, clôturer) : écriture sur M10, et
 *    réouverture / affectation du résultat / contre-passation : rôle `comptable`
 *    (20/10/2026 et 09/11/2026, dans `ClotureExerciceService` et
 *    `AffectationResultatService`) ;
 *  - purge définitive (unités d'hébergement, véhicules) : `super_admin` + écriture `PARAM`.
 *
 * ## Ce qui reste hors de cette liste, volontairement
 *
 * Le jeton, le poste concordant, la génération des données, le compte ACTIF (un compte
 * désactivé reste refusé : `compte_inactif`) et le journal (`journal_securite`,
 * `journal_reception`, poste d'origine) ne sont pas des droits : ils restent.
 */
final class OperationsSensibles
{
    /**
     * Table → ce qui en fait une opération sensible. Le test d'architecture
     * (`JugementDuCompteDAppairageTest`) échoue si un gestionnaire exige un module
     * sans figurer ici, ou si une entrée d'ici n'exige plus rien.
     *
     * @var array<string, string>
     */
    public const PAR_TABLE = [
        'demandes_cloture_exercice' => 'clôture, réouverture, affectation du résultat et contre-passation (droit comptable)',
        'pieces_saisie' => 'affectation du résultat de l\'exercice (rôle comptable ; une pièce ordinaire est une saisie courante)',
        'parametres_systeme' => 'clés réservées à l\'administrateur (mode MECeF, API, opérateur, forme juridique)',
        'utilisateurs' => 'suppression d\'un compte (super administrateur)',
    ];

    /** La purge définitive (type `suppression`) : super_admin + écriture PARAM, jugée par le moteur. */
    public const PURGE = 'suppression';
}
