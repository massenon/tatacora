<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Shared\Auth\Services\SuppressionCompteService;
use App\Shared\Sync\Support\ContexteSynchronisation;
use App\Shared\Sync\Support\EcritureSynchronisee;
use RuntimeException;

/**
 * Les COMPTES UTILISATEURS dans la synchronisation — décision du PO du
 * 03/11/2026, et pour la SEULE suppression.
 *
 * Jusque-là les comptes ne se synchronisaient pas du tout (PA-103 : aucun
 * mot de passe ni hash ne quitte une machine). Cela reste vrai : ce
 * gestionnaire n'accepte NI création NI modification — une création de compte
 * sur un poste ne crée rien au serveur, un mot de passe ne voyage jamais. Il
 * n'accepte que la `suppression` : le poste annonce qu'un compte (désigné par
 * son LOGIN, les identifiants numériques différant entre web et postes) a été
 * supprimé chez lui.
 *
 * ## L'autorité est vérifiée AVANT tout, par le moteur
 *
 * `SynchronisationService::traiterSuppressionDeCompte` exige que le compte du
 * jeton d'appairage du poste soit un super administrateur
 * ({@see \App\Models\User::peutSupprimerDesComptes()}), puis passe par
 * {@see SuppressionCompteService} : cible non administratrice, jamais soi-même,
 * idempotence (compte inconnu ou déjà supprimé : rien, journalisé).
 *
 * La suppression ainsi acceptée est ensuite publiée vers les AUTRES postes par
 * le catalogue descendant (`CatalogueDescendantService::COLONNES['utilisateurs']`,
 * `login` et `supprime_le` seulement).
 */
final class GestionnaireUtilisateurs extends GestionnaireAbstrait
{
    public function table(): string
    {
        return 'utilisateurs';
    }

    public function module(): string
    {
        return 'ROLES';
    }

    public function serviceDomaine(): string
    {
        return SuppressionCompteService::class;
    }

    /** La suppression d'un compte (logique) se synchronise ; rien d'autre. */
    public function accepteSuppression(): bool
    {
        return true;
    }

    public function creer(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        // Un compte ne se crée jamais par la synchronisation (aucun mot de passe
        // ne voyage) : refus lisible, définitif.
        throw new RuntimeException(__('sync.comptes.creation_non_synchronisable'));
    }

    public function supprimer(string $entiteId, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        // Le chemin des comptes est celui du moteur (par LOGIN, pas par
        // identifiant) : arriver ici est un bogue de programmation.
        throw new \LogicException(__('sync.interne.modification_non_declaree', ['table' => $this->table()]));
    }
}
