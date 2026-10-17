<?php

declare(strict_types=1);

namespace App\Domain\Facturation\Services;

use App\Domain\Comptabilite\Services\CalculTvaService;
use App\Domain\Facturation\Models\Avoir;
use App\Domain\Facturation\Models\Facture;
use App\Domain\Facturation\Models\LigneFacture;
use App\Domain\Hebergement\Models\Reservation;
use Illuminate\Support\Facades\DB;

/**
 * Émission et certification des factures (M2).
 *
 * @see EF-M2-01 Émission de facture
 * @see RG-03 Immutabilité — garantie par FactureObserver, pas ici
 * @see RG-04 Consolidation multi-activités
 */
class EmissionFactureService
{
    /** Taux de TVA applicable — voir la note de `tauxTva()`. */
    private const PRECISION = 2;

    public function __construct(
        private readonly MecefClientInterface $mecef,
        private readonly CalculTvaService $tva,
    ) {
    }

    /**
     * Facture un séjour (M1). À ce sprint, seule source de lignes disponible ;
     * RG-04 sera complétée au fil des modules (M4, M5, M8, M9) sans changer la
     * structure : chaque module ajoutera ses lignes au même document.
     */
    public function emettrePourReservation(Reservation $reservation, string $prixUnitaire): Facture
    {
        return DB::transaction(function () use ($reservation, $prixUnitaire) {
            $nuitees = (string) $reservation->nombreNuitees();
            $montantCatalogue = bcmul($nuitees, $prixUnitaire, self::PRECISION);

            // Ventilation par le service de TVA — l'émission ne décide jamais
            // elle-même si le tarif est HT ou TTC, ni si la TVA s'applique.
            $ventilation = $this->tva->ventiler($montantCatalogue);
            $montantHt = $ventilation['ht'];

            $facture = Facture::create([
                'client_id' => $reservation->client_id,
                'date_emission' => now()->toDateString(),
                'montant_ht' => $montantHt,
                'montant_tva' => $ventilation['tva'],
                'montant_ttc' => $ventilation['ttc'],
                // La facture existe AVANT la certification : la DGI peut être
                // indisponible, le client ne doit pas attendre pour être servi
                // (MECEF_INTEGRATION_SPEC.md §2).
                'statut' => 'en_attente_certification',
            ]);

            LigneFacture::create([
                'facture_id' => $facture->id,
                'source_module' => 'M1',
                'source_id' => $reservation->id,
                'libelle' => sprintf(
                    'Hébergement — unité %s, du %s au %s',
                    // `unite_id` est NOT NULL avec FK RESTRICT : la relation
                    // ne peut pas être absente sur une réservation persistée.
                    $reservation->unite->numero,
                    $reservation->date_arrivee->toDateString(),
                    $reservation->date_depart->toDateString(),
                ),
                'quantite' => $nuitees,
                'prix_catalogue' => $prixUnitaire,
                // Les lignes sont TOUJOURS stockées hors taxe, quelle que soit
                // la convention du catalogue : c'est la présentation comptable
                // normale d'une facture (lignes HT, TVA en pied de document).
                // Si le tarif est saisi TTC, il est converti ici, une seule fois.
                'prix_unitaire' => bcdiv($montantHt, $nuitees, self::PRECISION),
                'montant' => $montantHt,
            ]);

            return $facture->refresh();
        });
    }

    /**
     * Facture les SEULES consommations d'un séjour — sans ligne d'hébergement.
     *
     * ⚠ AMENDEMENT DE RG-04 (« un seul document ») — directive du Product
     * Owner du 02/09/2026 : à la clôture du panier d'un client hébergé, le
     * toggle « Payer séparément » permet d'émettre une facture qui ne porte
     * QUE les consommations. L'hébergement n'est PAS abandonné : il reste dû
     * sur la fiche du client (`Reservation::resteAPayer()` continue de le
     * porter — la facture partielle, sans ligne M1, ne consomme pas l'acompte
     * de la réservation : voir `Facture::SQL_ACOMPTES_LIES`) et sera facturé
     * plus tard par son propre chemin.
     *
     * La facture naît VIDE (totaux à zéro) : chaque consommation y entre par
     * {@see ajouterLigne()}, qui recalcule les totaux — jamais une seconde
     * arithmétique ici.
     */
    public function emettrePourConsommations(Reservation $reservation): Facture
    {
        return $this->emettreVide((string) $reservation->client_id);
    }

    /**
     * Une facture VIDE d'un client — les lignes y entrent par
     * {@see ajouterLigne()}. Lot F5c (17/10/2026) : `$id` et `$dateEmission`
     * pour la seule synchronisation (l'UUID du poste, la date d'émission du
     * poste) ; en ligne : un nouvel identifiant, aujourd'hui. Dans une
     * transaction : le numéro `F-` y est alloué sous verrou.
     */
    public function emettreVide(string $clientId, ?string $id = null, ?string $dateEmission = null): Facture
    {
        return DB::transaction(fn (): Facture => Facture::create([
            ...($id !== null ? ['id' => $id] : []),
            'client_id' => $clientId,
            'date_emission' => $dateEmission ?? now()->toDateString(),
            'montant_ht' => '0.00',
            'montant_tva' => '0.00',
            'montant_ttc' => '0.00',
            // Même cycle que l'émission de séjour : la facture existe AVANT
            // la certification (MECEF_INTEGRATION_SPEC.md §2).
            'statut' => 'en_attente_certification',
        ])->refresh());
    }

    /**
     * Ajout d'une ligne issue d'un autre module — RG-04.
     *
     * Refusé sur une facture certifiée : ajouter une prestation à un document
     * déjà transmis à la DGI en changerait le total sans que la DGI le sache.
     *
     * `$sourceId` est obligatoire — le schéma le déclare NOT NULL, et c'est
     * volontaire : une ligne sans enregistrement d'origine serait invérifiable
     * en cas de litige sur une facture consolidée.
     */
    public function ajouterLigne(
        Facture $facture,
        string $moduleSource,
        string $sourceId,
        string $libelle,
        string $quantite,
        string $prixUnitaire,
    ): LigneFacture {
        // `estFigee()` et non `estCertifiee()` : une facture certifiee en mode
        // demonstration doit etre figee elle aussi, sans quoi le chemin
        // d'immuabilite ne serait jamais emprunte hors Production.
        if ($facture->estFigee()) {
            throw new \App\Domain\Facturation\Exceptions\FactureImmuableException($facture->id, ['lignes']);
        }

        return DB::transaction(function () use ($facture, $moduleSource, $sourceId, $libelle, $quantite, $prixUnitaire) {
            $montantCatalogue = bcmul($quantite, $prixUnitaire, self::PRECISION);
            $montantHt = $this->tva->ventiler($montantCatalogue)['ht'];

            $ligne = LigneFacture::create([
                'facture_id' => $facture->id,
                'source_module' => $moduleSource,
                'source_id' => $sourceId,
                'libelle' => $libelle,
                'quantite' => $quantite,
                'prix_unitaire' => bcdiv($montantHt, $quantite, self::PRECISION),
                // Lot F5c : le prix VENDU, avant ventilation.
                'prix_catalogue' => $prixUnitaire,
                'montant' => $montantHt,
            ]);

            $this->recalculerTotaux($facture);

            return $ligne;
        });
    }

    /**
     * Totaux CALCULÉS depuis les lignes, jamais saisis — une facture dont le
     * total ne correspond pas à ses lignes est indéfendable en contrôle.
     */
    public function recalculerTotaux(Facture $facture): Facture
    {
        $totalHt = '0.00';

        foreach ($facture->lignes()->get() as $ligne) {
            $totalHt = bcadd($totalHt, (string) $ligne->montant, self::PRECISION);
        }

        // Les lignes étant hors taxe, la TVA se calcule toujours dans le sens
        // HT → TVA, y compris quand le catalogue est saisi en TTC : la
        // conversion a déjà eu lieu à la création de chaque ligne.
        $tva = $this->tva->estActive() ? $this->tva->depuisHt($totalHt) : '0.00';

        $facture->update([
            'montant_ht' => $totalHt,
            'montant_tva' => $tva,
            'montant_ttc' => bcadd($totalHt, $tva, self::PRECISION),
        ]);

        return $facture->refresh();
    }

    /**
     * Certification MECeF. En mode démonstration (PA-17 non résolue), produit
     * un NIM explicitement marqué DEMO, sans valeur fiscale.
     */
    public function certifier(Facture $facture): Facture
    {
        // Idempotence : une facture deja passee par la certification ne la
        // rejoue pas, y compris en demonstration — sinon chaque passage
        // consommerait un nouveau numero pour la meme piece.
        if ($facture->estFigee()) {
            return $facture;
        }

        $resultat = $this->mecef->certifier($facture);

        $facture->update([
            'numero_mecef' => $resultat->nim,
            'qr_code_fiscal' => $resultat->cachetFiscal,
            'statut' => 'certifiee',
        ]);

        return $facture->refresh();
    }

    /**
     * Émission d'un avoir — RG-03, unique chemin de correction.
     *
     * La facture d'origine reste rigoureusement inchangée : c'est le point de
     * la règle. Un test le vérifie explicitement.
     */
    public function emettreAvoir(Facture $facture, string $montant, string $motif): Avoir
    {
        if (bccomp($montant, (string) $facture->montant_ttc, self::PRECISION) > 0) {
            throw new \InvalidArgumentException(__('facturation.avoir_montant_excessif'));
        }

        // Dans une transaction : le numéro `AV-` y est alloué sous verrou.
        return DB::transaction(fn (): Avoir => Avoir::create([
            'facture_id' => $facture->id,
            'motif' => $motif,
            'montant' => $montant,
            'date_emission' => now()->toDateString(),
            'utilisateur_validation_id' => auth()->id(),
        ])->refresh());
    }

    public function modeDemonstration(): bool
    {
        return ! $this->mecef->estModeReel();
    }
}
