<?php

declare(strict_types=1);

namespace App\Domain\Etats\Services;

use App\Domain\Achats\Etats\EtatAchatsFournisseurs;
use App\Domain\Comptabilite\Etats\EtatBalance;
use App\Domain\Crm\Etats\EtatCreancesClients;
use App\Domain\Depenses\Etats\EtatDepenses;
use App\Domain\Hebergement\Etats\EtatReservations;
use App\Domain\Rh\Etats\EtatPaieEffectif;
use App\Domain\Stocks\Etats\EtatStocks;
use App\Domain\TableauxDeBord\Etats\EtatTableauDeBord;
use App\Domain\Tourisme\Etats\EtatTourisme;
use App\Domain\Vehicules\Etats\EtatLocations;
use App\Domain\Vehicules\Etats\EtatParcVehicules;
use App\Domain\Ventes\Etats\EtatVentes;
use App\Models\User;
use App\Shared\ReportEngine\Contracts\EtatInterface;
use RuntimeException;

/**
 * Bibliothèque d'états standards par module — EF-M14-02.
 *
 * @see EF-M14-02 Bibliothèque d'états standards par module
 * @see EF-M14-03 Génération à la demande avec filtres dynamiques
 * @see RG-16 RBAC à 3 niveaux
 *
 * ## Registre fermé, pas un scan de répertoire
 *
 * Les états sont énumérés explicitement plutôt que découverts par
 * introspection. Un scan ferait apparaître dans le Hub tout fichier
 * implémentant `EtatInterface` — y compris un état de test, un brouillon, ou
 * un état à demi porté. La liste des documents éditables par le gîte est une
 * décision produit, pas une conséquence de l'arborescence.
 *
 * ## Le filtrage RBAC est ici, sur le catalogue lui-même
 *
 * `RESPECT_TABLEAU_RAPPORT.md` §4 : « État consolidé (M11/M14) affichant une
 * donnée d'un module non autorisé pour le rôle ». Lister un état qu'on ne peut
 * pas éditer renseigne déjà sur la structure interne du système sans aucun
 * bénéfice — même raisonnement que le masquage de menu de la PWA. Le contrôle
 * de `GenerateurEtatService` reste en place derrière : celui-ci n'est que le
 * 1ᵉʳ des 3 niveaux.
 *
 * ## Ce catalogue contient DOUZE états (01/09/2026)
 *
 * `05_MODULE_SPECIFICATIONS.md` §M14 décrit un Hub à 13 onglets. Neuf de plus
 * ont été ajoutés le 01/09/2026 — réservations (M1), créances clients (M3),
 * ventes (M5), dépenses (M10), achats/dettes fournisseurs (M7), locations
 * (M8), tourisme (M9), paie/effectif (M13), balance (M10) —, chacun réutilisant
 * un Service de LECTURE déjà existant dans son domaine (jamais une seconde
 * requête parallèle). Ce qui reste absent dépend de domaines non implémentés
 * ou d'une décision non arbitrée (M12 Notifications — RG-20 ; balance âgée
 * des créances — PA-20) — les déclarer ici renverrait une liste que le
 * moteur ne saurait pas honorer.
 */
class CatalogueEtatsService
{
    /**
     * Registre : code d'état => classe.
     *
     * Le code est stable et fait partie du contrat d'API : le client Flutter
     * l'enregistre dans ses préférences d'écran. Ne jamais le renommer sans
     * versionner l'API.
     *
     * @var array<string, class-string<EtatInterface>>
     */
    private const REGISTRE = [
        'stocks' => EtatStocks::class,
        'tableau-de-bord' => EtatTableauDeBord::class,
        'parc-vehicules' => EtatParcVehicules::class,
        'reservations' => EtatReservations::class,
        'creances-clients' => EtatCreancesClients::class,
        'ventes' => EtatVentes::class,
        'depenses' => EtatDepenses::class,
        'achats-fournisseurs' => EtatAchatsFournisseurs::class,
        'locations-vehicules' => EtatLocations::class,
        'tourisme' => EtatTourisme::class,
        'paie-effectif' => EtatPaieEffectif::class,
        'balance' => EtatBalance::class,
    ];

    /**
     * États réellement éditables par cet utilisateur — 1ᵉʳ niveau RBAC.
     *
     * @return list<array{code: string, module: string, libelle: string, niveau: string}>
     */
    public function pourUtilisateur(?User $utilisateur): array
    {
        if ($utilisateur === null || ! $utilisateur->estActif()) {
            return [];
        }

        $disponibles = [];

        foreach (self::REGISTRE as $code => $classe) {
            /** @var EtatInterface $etat */
            $etat = app($classe);
            $niveau = $utilisateur->niveauSurModule($etat->module());

            // '-' : l'entrée est absente, pas grisée.
            if ($niveau === '-') {
                continue;
            }

            $disponibles[] = [
                'code' => $code,
                'module' => $etat->module(),
                // Libellé sans filtre : c'est l'intitulé générique du catalogue,
                // pas celui du document, qui dépend des filtres appliqués.
                'libelle' => $etat->libelle([]),
                'niveau' => $niveau,
            ];
        }

        return $disponibles;
    }

    /**
     * @throws RuntimeException si le code ne correspond à aucun état du registre
     */
    public function resoudre(string $code): EtatInterface
    {
        $classe = self::REGISTRE[$code] ?? null;

        if ($classe === null) {
            // Refus explicite : un repli sur un état par défaut ferait éditer
            // et archiver un document que personne n'a demandé.
            throw new RuntimeException(__('rapports.etat_inconnu', ['code' => $code]));
        }

        return app($classe);
    }

    /**
     * @return list<string>
     */
    public function codesDisponibles(): array
    {
        return array_keys(self::REGISTRE);
    }
}
