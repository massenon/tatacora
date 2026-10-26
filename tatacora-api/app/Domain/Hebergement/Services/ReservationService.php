<?php

declare(strict_types=1);

namespace App\Domain\Hebergement\Services;

use App\Domain\Comptabilite\Services\CorrespondanceComptesService;
use App\Domain\Comptabilite\Services\PasserEcritureService;
use App\Domain\Depenses\Services\DepenseService;
use App\Domain\Hebergement\Events\ReservationAnnulee;
use App\Domain\Hebergement\Models\Reservation;
use App\Shared\Integrite\Services\VerificationChevauchementService;

/**
 * Création, modification et annulation de réservation (M1).
 *
 * **Unique point d'entrée d'écriture sur `reservations`.** Appeler
 * `Reservation::create()` ailleurs contournerait le verrou de RG-01 sans
 * aucune erreur visible — c'est le mode de défaillance principal depuis que la
 * garantie est applicative et non plus déclarative (bascule MySQL du
 * 15/08/2026).
 *
 * @see EF-M1-02 Création, modification et annulation de réservation
 * @see EF-M1-03 Prévention des doubles réservations (RG-01)
 */
class ReservationService
{
    public function __construct(
        private readonly VerificationChevauchementService $verification,
        private readonly PasserEcritureService $ecritures,
        private readonly CorrespondanceComptesService $comptes,
    ) {
    }

    /**
     * Mode de paiement de la fiche → trésorerie qui ENCAISSE l'acompte —
     * comptes et journaux de {@see DepenseService::TRESORERIES}, seuls à
     * faire foi. « credit » n'y figure pas : à crédit, aucun argent n'entre.
     *
     * @var array<string, string>
     */
    public const TRESORERIE_ACOMPTE_PAR_MODE = [
        'especes' => 'caisse',
        'mobile_money' => 'momo',
        'virement' => 'banque',
        'cheque' => 'banque',
    ];

    /**
     * @param  array<string, mixed>  $donnees
     * @param  string|null  $dateComptable date MÉTIER de la pièce d'acompte
     *                                     (`Y-m-d`). `null` : aujourd'hui — la saisie au comptoir. La
     *                                     synchronisation hors connexion passe la date du DOCUMENT
     *                                     (décision PO du 15/10/2026, D246) : un acompte encaissé
     *                                     lundi et synchronisé jeudi appartient au tiroir de lundi.
     *
     * @throws \App\Shared\Integrite\Exceptions\ChevauchementDetecteException
     */
    public function creer(array $donnees, ?string $dateComptable = null): Reservation
    {
        return $this->verification->executerSousVerrou(
            tablePlages: 'reservations',
            tableRessource: 'unites_hebergement',
            colonneRessource: 'unite_id',
            ressourceId: (string) $donnees['unite_id'],
            colonneDebut: 'date_arrivee',
            colonneFin: 'date_depart',
            debut: (string) $donnees['date_arrivee'],
            fin: (string) $donnees['date_depart'],
            // refresh() n'est pas cosmétique : les valeurs par défaut du schéma
            // (`statut` = en_attente, `acompte` = 0) sont appliquées par MySQL à
            // l'insertion et restent absentes de l'instance en mémoire. Sans ce
            // rechargement, l'API renvoie `statut: null` sur une réservation
            // pourtant correctement enregistrée.
            ecriture: function () use ($donnees, $dateComptable): Reservation {
                // Le tarif est FIGÉ ICI, dans le SEUL chemin d'écriture
                // (PA-55 côté serveur, PA-163) — pas dans chaque appelant.
                // Trouvé le 02/09/2026 (passage navigateur) : la fiche PWA le
                // figeait, mais la réservation rapide, l'amorçage et la
                // synchronisation passaient sans lui — TOUTES les
                // réservations du poste avaient `tarif_nuit` NULL, et les
                // cartes ne pouvaient jamais afficher « Séjour » ni « Reste
                // à payer ». Un appelant qui envoie déjà son tarif (la fiche,
                // un lot Flutter futur) garde le sien : figé une fois, jamais
                // réécrit.
                if (! array_key_exists('tarif_nuit', $donnees) || $donnees['tarif_nuit'] === null || $donnees['tarif_nuit'] === '') {
                    $donnees['tarif_nuit'] = \App\Domain\Hebergement\Models\UniteHebergement::with('categorie')
                        ->findOrFail((string) $donnees['unite_id'])
                        ->categorie?->tarif_base;
                }

                $reservation = Reservation::create($donnees)->refresh();

                $this->comptabiliserAcompte($reservation, $dateComptable ?? now()->toDateString());

                return $reservation;
            },
            messageConflit: __('hebergement.chevauchement'),
        );
    }

    /**
     * L'acompte reçu produit sa pièce comptable — la moitié RÉCEPTION que
     * PA-166 nommait ouverte (01/09/2026, arbitrage du Product Owner sur les
     * annulations : le remboursement débite `4191`, ce compte doit donc
     * être crédité quand l'argent ENTRE). DÉBIT trésorerie du mode de
     * paiement, CRÉDIT 4191 « Clients — avances et acomptes reçus », même
     * transaction que la réservation (règle stricte, PA-162) : une pièce
     * refusée refuse la réservation entière.
     *
     * ## Trois cas SANS pièce, et chacun est un fait, pas un oubli
     *
     * - Acompte nul : aucun argent, aucune pièce.
     * - Mode « credit » : l'acompte est PROMIS, pas reçu — aucune trésorerie
     *   ne bouge ; la créance vit sur `resteAPayer()`.
     * - Mode absent (lot Flutter PA-57, réservation rapide sans acompte) :
     *   la trésorerie d'entrée est INCONNAISSABLE ici — imputer la caisse
     *   par défaut fausserait le tiroir du montant d'un Mobile Money. Le
     *   flux reste celui inventorié en PA-162/PA-166, nommé, jamais deviné.
     */
    private function comptabiliserAcompte(Reservation $reservation, string $date): void
    {
        $acompte = (string) $reservation->acompte;

        if (bccomp($acompte, '0', 2) <= 0) {
            return;
        }

        $mode = (string) ($reservation->mode_paiement ?? '');

        if (! array_key_exists($mode, self::TRESORERIE_ACOMPTE_PAR_MODE)) {
            return;
        }

        $tresorerie = DepenseService::TRESORERIES[self::TRESORERIE_ACOMPTE_PAR_MODE[$mode]];

        $this->ecritures->passerEtValider([
            'journal' => $tresorerie['journal'],
            'date' => $date,
            'libelle' => sprintf('Acompte réservation — %s', $reservation->id),
            'lignes' => [
                ['compte' => $this->comptes->compteDeTresorerie(self::TRESORERIE_ACOMPTE_PAR_MODE[$mode]), 'role' => CorrespondanceComptesService::roleDeTresorerie(self::TRESORERIE_ACOMPTE_PAR_MODE[$mode]), 'debit' => $acompte, 'credit' => '0'],
                ['compte' => $this->comptes->compte('AVANCES_CLIENTS'), 'role' => 'AVANCES_CLIENTS', 'debit' => '0', 'credit' => $acompte],
            ],
        ]);
    }

    /**
     * Déplacement d'une réservation : la réservation modifiée est exclue de sa
     * propre vérification, sans quoi elle se déclarerait en conflit avec
     * elle-même.
     *
     * @param  array<string, mixed>  $donnees
     *
     * @throws \App\Shared\Integrite\Exceptions\ChevauchementDetecteException
     */
    public function modifier(Reservation $reservation, array $donnees): Reservation
    {
        $uniteId = (string) ($donnees['unite_id'] ?? $reservation->unite_id);
        $arrivee = (string) ($donnees['date_arrivee'] ?? $reservation->date_arrivee->toDateString());
        $depart = (string) ($donnees['date_depart'] ?? $reservation->date_depart->toDateString());

        return $this->verification->executerSousVerrou(
            tablePlages: 'reservations',
            tableRessource: 'unites_hebergement',
            colonneRessource: 'unite_id',
            ressourceId: $uniteId,
            colonneDebut: 'date_arrivee',
            colonneFin: 'date_depart',
            debut: $arrivee,
            fin: $depart,
            ecriture: function () use ($reservation, $donnees): Reservation {
                $reservation->update($donnees);

                return $reservation->refresh();
            },
            exclureId: $reservation->id,
            messageConflit: __('hebergement.chevauchement'),
        );
    }

    /**
     * Annulation — RG-02.
     *
     * Aucune propagation n'est nécessaire : la disponibilité étant calculée à
     * la demande, passer le statut à `annulee` suffit à libérer l'unité dans le
     * calendrier, immédiatement et partout.
     */
    public function annuler(Reservation $reservation): Reservation
    {
        $reservation->update(['statut' => 'annulee']);

        // L'événement existe pour les domaines qui devront réagir plus tard
        // (M12 notification d'annulation, M2 avoir sur acompte). Aucun Listener
        // n'est câblé à ce stade : ces domaines ne sont pas implémentés, et un
        // Listener prématuré serait un couplage sans objet.
        ReservationAnnulee::dispatch($reservation->id, $reservation->unite_id);

        return $reservation->refresh();
    }

    // =====================================================================
    // Lignes de services — PA-163
    // =====================================================================

    /**
     * Les quatre catalogues, et où lire libellé et prix dans chacun —
     * l'UNIQUE endroit du serveur qui associe un service à sa table.
     *
     * `vehicule` compose son libellé de deux colonnes : la table ne porte
     * aucune colonne libellé, et « Berline · BJ-1234-RB » est ce que le
     * maître affiche.
     *
     * @var array<string, array{table: string, libelle: list<string>, prix: string}>
     */
    public const CATALOGUES = [
        'restauration' => ['table' => 'plats', 'libelle' => ['libelle'], 'prix' => 'prix_vente'],
        'bar' => ['table' => 'cartes_boisson', 'libelle' => ['libelle'], 'prix' => 'prix_vente'],
        'tourisme' => ['table' => 'circuits', 'libelle' => ['nom'], 'prix' => 'prix'],
        'vehicule' => ['table' => 'vehicules', 'libelle' => ['categorie', 'immatriculation'], 'prix' => 'tarif_jour'],
    ];

    /**
     * Remplace les lignes de services d'une fiche par celles saisies.
     *
     * ## Prix ET libellé figés ICI, jamais à l'affichage
     *
     * Le catalogue est lu au moment de l'écriture (PA-55/PA-98) : un
     * changement de carte ne réécrit jamais une fiche convenue. Une source
     * inexistante REFUSE toute la fiche — une ligne sans origine réelle est
     * invérifiable, et un repli silencieux transformerait une faute de saisie
     * en donnée fausse (le piège `?? first()` de PA-161).
     *
     * ## Remplacer, pas éditer ligne à ligne
     *
     * Les lignes sont la composition COURANTE de la fiche, comme au maître :
     * l'historique auditable vit sur la réservation (RG-15), et le document
     * immuable est la facture (RG-03), jamais la fiche. Une réservation
     * annulée ne se retouche pas.
     *
     * @param  list<array{service: string, source_id: string, quantite: string}>  $lignes
     *
     * @throws \InvalidArgumentException service inconnu, source inexistante ou fiche annulée
     */
    public function remplacerLignes(Reservation $reservation, array $lignes): Reservation
    {
        if (! $reservation->estActive()) {
            throw new \InvalidArgumentException(__('hebergement.annulee_non_modifiable'));
        }

        return \Illuminate\Support\Facades\DB::transaction(function () use ($reservation, $lignes): Reservation {
            $reservation->lignes()->delete();

            foreach ($lignes as $ligne) {
                $service = (string) $ligne['service'];
                $catalogue = self::CATALOGUES[$service] ?? null;

                if ($catalogue === null) {
                    throw new \InvalidArgumentException(__('hebergement.ligne_service_inconnu', ['service' => $service]));
                }

                $source = \Illuminate\Support\Facades\DB::table($catalogue['table'])
                    ->where('id', (string) $ligne['source_id'])
                    ->first();

                if ($source === null) {
                    throw new \InvalidArgumentException(__('hebergement.ligne_source_inconnue', ['service' => $service]));
                }

                $quantite = (string) $ligne['quantite'];

                if (bccomp($quantite, '0', 2) <= 0) {
                    throw new \InvalidArgumentException(__('hebergement.ligne_quantite_invalide'));
                }

                $prix = (string) $source->{$catalogue['prix']};
                $libelle = implode(' · ', array_map(
                    static fn (string $colonne): string => (string) $source->{$colonne},
                    $catalogue['libelle'],
                ));

                $reservation->lignes()->create([
                    'service' => $service,
                    'source_id' => (string) $ligne['source_id'],
                    'libelle' => $libelle,
                    'quantite' => $quantite,
                    'prix_unitaire' => $prix,
                    'montant' => bcmul($quantite, $prix, 2),
                ]);
            }

            return $reservation->refresh()->load('lignes');
        });
    }
}
