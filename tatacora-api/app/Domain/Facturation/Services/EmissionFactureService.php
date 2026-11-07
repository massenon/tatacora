<?php

declare(strict_types=1);

namespace App\Domain\Facturation\Services;

use App\Domain\Comptabilite\Services\CalculTvaService;
use App\Domain\Facturation\Exceptions\EmecefErreur;
use App\Domain\Facturation\Exceptions\FactureImmuableException;
use App\Domain\Facturation\Models\Avoir;
use App\Domain\Facturation\Models\Facture;
use App\Domain\Facturation\Models\LigneFacture;
use App\Domain\Facturation\Support\IfuClient;
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
    public function emettrePourReservation(Reservation $reservation, string $prixUnitaire, ?string $acheteurIfu = null, ?string $acheteurNom = null): Facture
    {
        $this->exigerIfuValide($acheteurIfu);

        return DB::transaction(function () use ($reservation, $prixUnitaire, $acheteurIfu, $acheteurNom) {
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
                'acheteur_ifu' => IfuClient::nettoyer($acheteurIfu),
                'acheteur_nom' => $this->nomAcheteur($acheteurNom),
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
    public function emettrePourConsommations(Reservation $reservation, ?string $acheteurIfu = null, ?string $acheteurNom = null): Facture
    {
        return $this->emettreVide((string) $reservation->client_id, null, null, $acheteurIfu, $acheteurNom);
    }

    /**
     * Une facture VIDE d'un client — les lignes y entrent par
     * {@see ajouterLigne()}. Lot F5c (17/10/2026) : `$id` et `$dateEmission`
     * pour la seule synchronisation (l'UUID du poste, la date d'émission du
     * poste) ; en ligne : un nouvel identifiant, aujourd'hui. Dans une
     * transaction : le numéro `F-` y est alloué sous verrou.
     */
    public function emettreVide(string $clientId, ?string $id = null, ?string $dateEmission = null, ?string $acheteurIfu = null, ?string $acheteurNom = null): Facture
    {
        $this->exigerIfuValide($acheteurIfu);

        return DB::transaction(fn (): Facture => Facture::create([
            'acheteur_ifu' => IfuClient::nettoyer($acheteurIfu),
            'acheteur_nom' => $this->nomAcheteur($acheteurNom),
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

    /** L'IFU du client : facultatif, 13 chiffres s'il est renseigné (une règle, web et poste). */
    private function exigerIfuValide(?string $ifu): void
    {
        if (! IfuClient::valide($ifu)) {
            throw new \InvalidArgumentException(__('facturation.ifu_client.invalide'));
        }
    }

    private function nomAcheteur(?string $nom): ?string
    {
        $net = trim((string) $nom);

        return $net === '' ? null : mb_substr($net, 0, 100);
    }

    /**
     * Range l'ACHETEUR de la facture (IFU facultatif, nom) ; « Retenir pour ce client »
     * le range aussi sur la fiche du client (jamais pour la fiche « Client de passage »,
     * partagée par tous les clients sans fiche). Refusé sur une facture NORMALISÉE.
     */
    public function definirAcheteur(Facture $facture, ?string $ifu, ?string $nom, bool $retenir = false): Facture
    {
        $this->exigerIfuValide($ifu);

        if ($facture->normalisation_statut === StatutNormalisation::Normalisee->value) {
            throw new FactureImmuableException($facture->id, ['acheteur']);
        }

        $facture->update([
            'acheteur_ifu' => IfuClient::nettoyer($ifu),
            'acheteur_nom' => $this->nomAcheteur($nom),
        ]);

        $this->retenirSurLaFiche($facture, $ifu, $retenir);

        return $facture->refresh();
    }

    /** « Retenir pour ce client » : l'IFU saisi va sur la fiche (si le client en a une, et que ce n'est pas le client de passage). */
    public function retenirSurLaFiche(Facture $facture, ?string $ifu, bool $retenir): void
    {
        $propre = IfuClient::nettoyer($ifu);

        if (! $retenir || $propre === null) {
            return;
        }

        $client = $facture->client()->first();

        if ($client === null || $client->nom === \App\Shared\Sync\Gestionnaires\GestionnaireFactures::CLIENT_DE_PASSAGE['nom']) {
            return;
        }

        $client->update(['ifu' => $propre]);
    }

    /**
     * L'acheteur tel qu'il part à la normalisation : (IFU ou null, nom). Sans nom saisi,
     * le nom de la fiche ; sans fiche, « Client divers ». Un client sans IFU part sans IFU.
     *
     * @return array{0: ?string, 1: string}
     */
    public static function acheteurPourNormalisation(Facture $facture): array
    {
        $facture->loadMissing('client');

        return [
            IfuClient::nettoyer($facture->acheteur_ifu),
            IfuClient::nomPourNormalisation($facture->acheteur_nom, $facture->client?->nomComplet()),
        ];
    }

    /**
     * ÉMISSION d'une facture SIMPLE (07/11/2026) : la facture est ÉMISE et figée (`statut`
     * `certifiee` = émise, nom hérité), sans numéro MECeF ni QR ni mention : une facture
     * ordinaire. La normalisation, elle, ne vient que par le bouton « Normaliser ».
     */
    public function figerEmission(Facture $facture): Facture
    {
        if ($facture->statut === 'en_attente_certification' || $facture->statut === 'brouillon') {
            $facture->update(['statut' => 'certifiee']);
        }

        return $facture->refresh();
    }

    /**
     * Le BOUTON « Normaliser » du web : e-MECeF seulement. Désactivé : facture simple, rien à
     * normaliser. Boîtier : le web n'appelle jamais le boîtier (le poste le fait). Une erreur
     * classée de la DGI se range sur la facture (en attente / refusée / à vérifier) sans lever :
     * la facture reste émise, rejouable.
     */
    public function normaliserLaFacture(Facture $facture): Facture
    {
        $mode = ModeFacturation::courant();

        if ($mode === ModeFacturation::Desactive) {
            throw new \RuntimeException(__('facturation.mode.normaliser_desactive'));
        }

        if ($mode === ModeFacturation::Boitier) {
            throw new \RuntimeException(__('facturation.mode.normaliser_poste'));
        }

        if ($facture->normalisation_statut === StatutNormalisation::Normalisee->value) {
            return $facture;
        }

        $facture = $this->figerEmission($facture);

        if ($facture->normalisation_statut === StatutNormalisation::AVerifier->value) {
            // Jamais retransmise automatiquement ; la relance par bouton passe par la vérification, pas ici.
            return $facture;
        }

        return $this->certifierEnLigne($facture);
    }

    /**
     * Certification MECeF — selon le MODE de la facturation normalisée
     * (docs/SPEC_FACTURATION_NORMALISEE_MECEF.md §1) :
     *
     *  - **Désactivé** : démonstration, `MECEF-DEMO-…`, sans valeur fiscale (inchangé) ;
     *  - **e-MECeF** : le SERVEUR certifie par l'API de la DGI. Une erreur classée
     *    (jeton refusé, limite, réseau, refus) laisse la facture « en attente » avec son
     *    motif, rejouable par le job — jamais une exception à l'émission ;
     *  - **Boîtier** : le serveur NE certifie PAS. La facture reste « en attente de
     *    normalisation par le poste » ; un poste avec boîtier la reprend à son passage.
     *
     * Une facture déjà NORMALISÉE n'est jamais retransmise (idempotence par facture).
     */
    public function certifier(Facture $facture): Facture
    {
        $mode = ModeFacturation::courant();

        // Idempotence : une facture deja normalisee ne l'est jamais deux fois.
        if ($facture->normalisation_statut === StatutNormalisation::Normalisee->value) {
            return $facture;
        }

        // Une facture portant deja un numero reel n'est pas retouchee.
        if ($facture->estFigee() && filled($facture->numero_mecef) && ! $facture->estCertificationDemonstration()) {
            return $facture;
        }

        // DESACTIVE = FACTURATION SIMPLE (decision du PO du 07/11/2026) : la facture est emise,
        // sans numero MECeF fictif, sans QR, sans mention. Plus aucun faux client.
        if ($mode === ModeFacturation::Desactive) {
            return $this->figerEmission($facture);
        }

        if ($mode === ModeFacturation::Boitier) {
            return $this->attendreLePoste($facture);
        }

        if ($mode === ModeFacturation::Emecef) {
            return $this->certifierEnLigne($facture);
        }

        return $facture;
    }

    /** Boîtier : le serveur ne certifie pas ; il le DIT sur la facture (sans écraser le poste). */
    private function attendreLePoste(Facture|Avoir $document): Facture|Avoir
    {
        $actuel = StatutNormalisation::depuis($document->normalisation_statut);

        // Le poste a peut-être déjà dit « refusée » ou « à vérifier » : on ne l'écrase pas.
        if ($actuel === null || $actuel === StatutNormalisation::EnAttente) {
            $document->update([
                'normalisation_statut' => StatutNormalisation::EnAttente->value,
                'normalisation_mode' => 'boitier',
                'normalisation_motif' => __('facturation.emecef.attente_poste'),
            ]);
        }

        return $document->refresh();
    }

    private function certifierEnLigne(Facture $facture): Facture
    {
        // Retry-After et réseau tombé : on n'insiste pas avant l'heure dite.
        if ($facture->emecef_prochain_essai_le !== null && $facture->emecef_prochain_essai_le->isFuture()) {
            return $facture;
        }

        try {
            $resultat = $this->mecef->certifier($facture);
        } catch (EmecefErreur $erreur) {
            $this->consignerEchec($facture, $erreur);

            return $facture->refresh();
        }

        $facture->update([
            'numero_mecef' => $resultat->nim,
            'qr_code_fiscal' => $resultat->cachetFiscal,
            'code_mecef' => $resultat->codeMecef,
            'statut' => 'certifiee',
            ...$this->champsNormalisee($resultat),
        ]);

        return $facture->refresh();
    }

    /** @return array<string, mixed> */
    private function champsNormalisee(CertificationMecefResultat $resultat): array
    {
        return [
            'normalisation_statut' => StatutNormalisation::Normalisee->value,
            'normalisation_mode' => 'emecef',
            'normalisation_motif' => null,
            'normalisation_compteur' => $resultat->compteur,
            'normalisee_le' => $resultat->dateCertification,
            'emecef_uid' => null,
            'emecef_uid_le' => null,
            'emecef_prochain_essai_le' => null,
        ];
    }

    /**
     * Une erreur CLASSÉE de la DGI : le statut et le motif (en français, jamais le jeton)
     * se rangent sur la pièce, le prochain essai respecte le délai demandé.
     */
    private function consignerEchec(Facture|Avoir $document, EmecefErreur $erreur): void
    {
        $secondes = $erreur->secondesAvantRejeu();

        $champs = [
            'normalisation_statut' => $erreur->statut()->value,
            'normalisation_mode' => 'emecef',
            'normalisation_motif' => mb_substr($erreur->getMessage(), 0, 500),
            'emecef_prochain_essai_le' => $secondes === null ? null : now()->addSeconds($secondes),
        ];

        // La facture reste VISIBLE comme non conforme (jamais « en attente » à perpétuité).
        if ($document instanceof Facture && ! $document->estFigee()) {
            $champs['statut'] = 'echec_certification';
        }

        $document->update($champs);
    }

    /**
     * Normalise l'avoir d'une facture NORMALISÉE : e-MECeF au serveur (type `FA`,
     * référence = code MECeF de la facture d'origine), boîtier : « en attente du poste ».
     * Ne lève jamais : un avoir créé n'est pas annulé parce que la DGI est injoignable.
     */
    public function certifierAvoir(Avoir $avoir): Avoir
    {
        $mode = ModeFacturation::courant();
        $facture = $avoir->facture()->first();

        if ($mode === ModeFacturation::Desactive || $facture === null || ! $facture->estNormalisee()) {
            return $avoir;
        }

        if ($avoir->normalisation_statut === StatutNormalisation::Normalisee->value) {
            return $avoir;
        }

        if ($mode === ModeFacturation::Boitier) {
            $this->attendreLePoste($avoir);

            return $avoir->refresh();
        }

        if ($avoir->emecef_prochain_essai_le !== null && $avoir->emecef_prochain_essai_le->isFuture()) {
            return $avoir;
        }

        if (! $this->mecef instanceof CertifieLesAvoirsInterface) {
            return $avoir;
        }

        try {
            $resultat = $this->mecef->certifierAvoir($avoir);
        } catch (EmecefErreur $erreur) {
            $this->consignerEchec($avoir, $erreur);

            return $avoir->refresh();
        }

        $avoir->update([
            'numero_mecef' => $resultat->nim,
            'qr_code_fiscal' => $resultat->cachetFiscal,
            'code_mecef' => $resultat->codeMecef,
            ...$this->champsNormalisee($resultat),
        ]);

        return $avoir->refresh();
    }

    /**
     * Range le résultat d'une normalisation faite AILLEURS — le boîtier CC300 d'un
     * poste, rendu par la synchronisation — SANS re-certifier : le serveur
     * n'appelle ni le boîtier ni la DGI ici (docs/SPEC_FACTURATION_NORMALISEE_MECEF.md).
     *
     * Une pièce déjà normalisée n'est jamais écrasée : le rejeu du même résultat
     * est un no-op, un résultat DIFFÉRENT est refusé.
     *
     * @param  array{statut: string, mode: string, motif?: ?string, numero_mecef?: ?string, qr_code?: ?string, code_mecef?: ?string, compteur?: ?string, date?: ?string}  $resultat
     */
    public function enregistrerNormalisation(Facture|Avoir $document, array $resultat): Facture|Avoir
    {
        $statut = StatutNormalisation::depuis($resultat['statut']);

        if ($statut === null) {
            throw new \RuntimeException(__('facturation.normalisation_statut_inconnu', ['statut' => $resultat['statut']]));
        }

        if (! in_array($resultat['mode'], ['boitier', 'emecef'], true)) {
            throw new \RuntimeException(__('facturation.normalisation_mode_inconnu', ['mode' => $resultat['mode']]));
        }

        if ($document->normalisation_statut === StatutNormalisation::Normalisee->value) {
            if ($statut === StatutNormalisation::Normalisee && ($resultat['numero_mecef'] ?? null) === $document->numero_mecef) {
                return $document;
            }

            throw new \RuntimeException(__('facturation.normalisation_deja_faite'));
        }

        $champs = [
            'normalisation_statut' => $statut->value,
            'normalisation_motif' => $statut === StatutNormalisation::Normalisee ? null : mb_substr((string) ($resultat['motif'] ?? ''), 0, 500),
            'normalisation_mode' => $resultat['mode'],
        ];

        if ($statut === StatutNormalisation::Normalisee) {
            $identite = (string) ($resultat['numero_mecef'] ?? '');
            $qr = (string) ($resultat['qr_code'] ?? '');

            if (preg_match('/^[A-Za-z0-9]+-[0-9]+$/', $identite) !== 1) {
                throw new \RuntimeException(__('facturation.normalisation_identite_invalide'));
            }

            if (! str_starts_with($qr, 'F;') || count(explode(';', $qr)) !== 5) {
                throw new \RuntimeException(__('facturation.normalisation_qr_invalide'));
            }

            $champs += [
                'numero_mecef' => $identite,
                'qr_code_fiscal' => $qr,
                'code_mecef' => $resultat['code_mecef'] ?? null,
                'normalisation_compteur' => $resultat['compteur'] ?? null,
                'normalisee_le' => $resultat['date'] ?? now(),
            ];

            // Une facture normalisée est figée ; un avoir n'a pas de cycle MECeF.
            if ($document instanceof Facture) {
                $champs['statut'] = 'certifiee';
            }
        }

        $document->update($champs);

        return $document->refresh();
    }

    /**
     * Émission d'un avoir — RG-03, unique chemin de correction.
     *
     * La facture d'origine reste rigoureusement inchangée : c'est le point de
     * la règle. Un test le vérifie explicitement.
     */
    public function emettreAvoir(Facture $facture, string $montant, string $motif, ?string $id = null): Avoir
    {
        if (bccomp($montant, (string) $facture->montant_ttc, self::PRECISION) > 0) {
            throw new \InvalidArgumentException(__('facturation.avoir_montant_excessif'));
        }

        // Dans une transaction : le numéro `AV-` y est alloué sous verrou.
        // `$id` : l'identifiant né sur un poste hors connexion (avoir partiel
        // synchronisé) — il rend le rejeu idempotent et permet au poste de
        // reconnaître son avoir à la descente.
        $avoir = DB::transaction(fn (): Avoir => Avoir::create([
            ...($id !== null ? ['id' => $id] : []),
            'facture_id' => $facture->id,
            'motif' => $motif,
            'montant' => $montant,
            'date_emission' => now()->toDateString(),
            'utilisateur_validation_id' => auth()->id(),
        ])->refresh());

        // Facturation normalisée : l'avoir d'une facture NORMALISÉE l'est aussi (e-MECeF
        // au serveur ; boîtier : en attente du poste). Hors transaction, sans jamais
        // faire échouer l'émission de l'avoir.
        return $this->certifierAvoir($avoir);
    }

    public function modeDemonstration(): bool
    {
        return ! $this->mecef->estModeReel();
    }
}
