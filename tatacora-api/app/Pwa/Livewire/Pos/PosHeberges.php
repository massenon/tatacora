<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Pos;

use App\Domain\Facturation\Models\LigneFacture;
use App\Domain\Facturation\Services\EmissionFactureService;
use App\Domain\Hebergement\Models\Reservation;
use App\Domain\Ventes\Models\Panier;
use App\Domain\Ventes\Services\PanierService;
use App\Domain\Ventes\Services\VenteService;
use App\Pwa\Livewire\Concerns\FormulaireModal;
use App\Pwa\Livewire\PageMetier;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\View\View;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Title;
use Livewire\Attributes\Url;
use RuntimeException;

/**
 * Point de vente CLIENTS HEBERGES — maitre : prototype_v2/pages/pos-heberges.html.
 *
 * ## P4 — le panier de sejour est une TABLE depuis le 31/08/2026 (PA-161)
 *
 * Il vivait dans la SESSION HTTP, sous une cle calculee
 * (`panier_sejour_{id}`). Une session expire au bout de 120 minutes, est
 * propre a un navigateur et disparait a la deconnexion — pendant que l'ecran
 * promet, en sous-titre, un panier ouvert « de l'arrivee au depart ». Le
 * serveur qui prenait la releve au comptoir voisin ne voyait rien, et une
 * session expiree effacait une consommation deja servie.
 *
 * L'arbitrage (f) de PA-161 a tranche Q2 : la table `paniers` existe, et la
 * regle « un seul panier ouvert par sejour » est tenue par `PanierService`
 * sous `lockForUpdate()` — pas par un index unique, qui n'autoriserait qu'un
 * seul panier CLOTURE par sejour, MySQL n'ayant pas d'index partiel.
 *
 * ⚠ Le bandeau ambre « ouvert sur ce poste et dans ce navigateur seulement »
 * a ete RETIRE, et ce n'est pas un oubli : son motif a cesse d'etre vrai, et
 * un motif de refus perime transforme une decision en oubli (PA-144, PA-107,
 * PA-120). Ce qui reste vrai est dit a sa place : le panier survit au
 * changement d'equipe et de navigateur, et il ne quitte PAS ce serveur —
 * `paniers` n'est pas au registre `TABLES_SYNCHRONISABLES`, et annoncer une
 * synchronisation qui n'aura pas lieu serait PA-59/60/61.
 *
 * ## P3 — le `catch` qui detruisait le panier ET annoncait le succes
 *
 * L'ancienne cloture faisait, quand l'emission de facture levait — ce que
 * `CalculTvaService` fait DELIBEREMENT quand la TVA est active sans taux
 * (PA-62) — un `Session::forget('panier_sejour_…')` suivi d'une notification
 * de type `success`. Rien n'avait ete transfere : la consommation du client
 * etait detruite, et l'ecran affichait un succes.
 *
 * Le repli n'existe plus. Un echec de facturation NOMME ce qui s'est passe,
 * part au journal technique par `report()`, et laisse le panier INTACT — la
 * transaction est annulee, et le panier reste OUVERT en base : c'est la seule
 * copie de ce que le client a consomme.
 *
 * ## P3bis — les 20 000 F de repli
 *
 * `emettrePourReservation()` recevait le tarif de la categorie AVEC un repli
 * de 20 000 F code en dur : un tarif de nuit invente sur un document remis au
 * client. `categories_hebergement.tarif_base` est NOT NULL : ce repli n'etait
 * meme pas atteignable par une categorie presente — il ne pouvait servir qu'a
 * masquer une relation manquante. Quand le tarif manque, l'ecran le DIT et
 * refuse.
 *
 * ## P2 — la consommation entre au registre des ventes
 *
 * Le sejour ne produisait qu'une facture : rien n'atteignait `ventes`, donc
 * rien ne decrementait le stock, et l'indicateur « Porte en note » du journal
 * ne pouvait jamais quitter zero. La cloture enregistre desormais une VENTE en
 * `note_chambre` (non encaissee, donc creance) AVANT d'emettre la facture, par
 * `VenteService` — le meme chemin que le comptoir, la meme numerotation, la
 * meme deduction RG-05.
 *
 * ## Tourisme et location ne sont plus proposes (26/10/2026)
 *
 * Directive du PO : ni carte, ni pastille, ni mention. Le catalogue ne porte
 * que le bar et le restaurant ; {@see MODULES_DU_SEJOUR} reste la garde
 * defensive d'une action Livewire forgee.
 *
 * @see EF-M2-01 Emission de facture
 * @see RG-04 Facture consolidee multi-modules — AMENDEE le 02/09/2026
 *      (directive PO) : le toggle « Payer separement » de la modale de
 *      cloture permet une facture de consommations SEULES, l'hebergement
 *      etant facture plus tard par son propre chemin. Voir
 *      {@see $payerSeparement} et {@see cloturerEtFacturer()}.
 * @see RG-05 Sortie de stock automatique
 * @see docs/PROPOSITION_MODELE_PANIER_POS.md §5 (R-a a R-d)
 */
#[Layout('layouts.pwa')]
#[Title('Point de vente — clients hébergés — TATACORA AFRIQUE')]
class PosHeberges extends PageMetier
{
    use ComposePanier;
    use FormulaireModal;

    /** Le module RBAC de l'ecran : ce qui s'y vend est du bar et du restaurant. */
    public const MODULE = 'M5';

    /**
     * Les rayons que le panier d'un SEJOUR porte : bar et restaurant.
     */
    public const MODULES_DU_SEJOUR = ['M4', 'M5'];

    /** Emettre une facture est une ecriture sur M2, exigee EN PLUS. */
    public const MODULE_FACTURATION = 'M2';

    /** Le module d'hebergement, dont ce POS porte le poste de vente. */
    public const MODULE_HEBERGEMENT = 'M1';

    /** Les statuts de sejour qui peuvent recevoir une consommation. */
    private const STATUTS_EN_SEJOUR = ['confirmee', 'en_cours'];

    #[Url(as: 'sejour')]
    public ?string $selectedReservationId = null;

    #[Url(as: 'q')]
    public string $recherche = '';

    #[Url(as: 'cat')]
    public string $categorieActive = 'tout';

    /**
     * Le toggle « Payer separement » de la modale de cloture — directive PO
     * du 02/09/2026. `false` (defaut) : la facture porte les nuitees ET les
     * consommations, comme toujours. `true` : la facture emise ne porte QUE
     * les consommations, et la modale rappelle en toutes lettres ce qui
     * restera du sur la fiche du client.
     *
     * ⚠ AMENDEMENT DE RG-04 (« un seul document ») — directive PO du
     * 02/09/2026 : deux paiements separes signifient que l'hebergement sera
     * facture plus tard par son propre chemin. Ce n'est pas un contournement
     * de la regle, c'est sa levee explicite, datee.
     */
    public bool $payerSeparement = false;

    /** L'hebergement entre-t-il dans la facture de cette cloture ? */
    private function payerHebergement(): bool
    {
        return ! $this->payerSeparement;
    }

    /**
     * La remise du panier de sejour — type + valeur, motif de la fiche de
     * reservation (directive PO du 02/09/2026). Persistees sur le PANIER par
     * {@see appliquerRemise()} ; le net vient de `Panier::remiseSur()`,
     * l'auteur unique.
     */
    public string $remiseType = Panier::REMISE_AUCUNE;

    public string $remiseValeur = '';

    /**
     * Le registre FERME des modales de l'ecran.
     *
     * ⚠ `cloture` porte une liste VIDE : elle ne doit donc jamais etre ouverte
     * par `ouvrirFormulaire()`, qui ferait `reset([])` — c'est-a-dire remettre
     * a zero TOUTES les proprietes, `selectedReservationId` compris. Voir
     * {@see ouvrirClotureSejour()}.
     *
     * @return array<string, list<string>>
     */
    protected function formulaires(): array
    {
        return [
            'cloture' => [],
        ];
    }

    public function mount(): void
    {
        if ($this->selectedReservationId === null) {
            $this->selectedReservationId = $this->sejoursEnCours()->first()?->id;
        }
    }

    /**
     * @return Collection<int, Reservation>
     */
    private function sejoursEnCours(): Collection
    {
        return Reservation::query()
            ->with(['client', 'unite.categorie'])
            ->whereIn('statut', self::STATUTS_EN_SEJOUR)
            ->orderBy('date_arrivee')
            ->get();
    }

    /** Le POSTE de vente porte au panier et a la vente — jamais une caisse. */
    private function posteDeVente(): string
    {
        return VenteService::MODULES[self::MODULE_HEBERGEMENT];
    }

    // =====================================================================
    // Le panier du sejour — en BASE, sous la garantie de `PanierService`
    // =====================================================================

    /**
     * Le panier ouvert du sejour selectionne, ou `null`.
     *
     * LECTURE stricte : consulter un ecran n'ouvre aucun panier. Ouvrir a la
     * lecture creerait une ligne a chaque affichage, y compris pour un role
     * en `L` — et le KPI « Paniers ouverts » compterait des paniers que
     * personne n'a ouverts.
     */
    private function panierCourant(PanierService $paniers): ?Panier
    {
        return $this->selectedReservationId === null
            ? null
            : $paniers->panierOuvertDuSejour($this->selectedReservationId);
    }

    // =====================================================================
    // Le panier — chaque geste exige le droit d'ecrire
    // =====================================================================

    public function ajouterAuPanier(string $module, string $reference, PanierService $paniers): void
    {
        $this->exigerEcriture(self::MODULE);

        if ($this->selectedReservationId === null) {
            $this->notifier(__('pos_pwa.heberges.refus_aucun_sejour'), 'error');

            return;
        }

        if (! in_array($module, self::MODULES_DU_SEJOUR, true)) {
            // Defense du serveur : aucune carte ne propose ces rayons, mais une
            // action Livewire se pose depuis le navigateur.
            $this->notifier(__('pos_pwa.commun.reference_inconnue'), 'error');

            return;
        }

        /*
         * Ce controle-ci est celui de l'ECRAN : il rend les mots du maitre et
         * evite d'OUVRIR un panier de sejour sur un clic qui ne peut rien y
         * ajouter.
         *
         * ⚠ Il ne garantit RIEN sur le prix enregistre : c'est `PanierService`
         * qui relit le catalogue et fige prix et libelle. La redondance est
         * deliberee, et c'est la garde du SERVICE qui protege (PA-100).
         */
        $article = $this->resoudreArticle($module, $reference);

        if ($article === null) {
            $this->notifier(__('pos_pwa.commun.reference_inconnue'), 'error');

            return;
        }

        if (bccomp((string) $article['prix'], '0.00', self::PRECISION_MONTANT) <= 0) {
            $this->notifier(__('pos_pwa.commun.sans_prix', ['article' => $article['nom']]), 'error');

            return;
        }

        /*
         * L'ouverture est ce qui applique R-a : `PanierService` verrouille la
         * reservation, relit, et rend le panier deja ouvert s'il existe. Un
         * second caissier sur le meme sejour retombe donc sur le MEME panier,
         * jamais sur un second.
         */
        try {
            $panier = $paniers->ouvrirPourSejour($this->selectedReservationId, $this->posteDeVente());
            $paniers->ajouterLigne($panier, $module, $reference);
        } catch (RuntimeException $refus) {
            // Les refus du domaine sont ecrits POUR l'operateur
            // (`lang/fr/ventes.php`) et aucun ne porte de SQL.
            $this->notifier($refus->getMessage(), 'error');
        }
    }

    public function incrementerLigne(string $cle, PanierService $paniers): void
    {
        $this->exigerEcriture(self::MODULE);

        $this->deplacerQuantite($paniers, $cle, 1);
    }

    public function decrementerLigne(string $cle, PanierService $paniers): void
    {
        $this->exigerEcriture(self::MODULE);

        $this->deplacerQuantite($paniers, $cle, -1);
    }

    private function deplacerQuantite(PanierService $paniers, string $cle, int $delta): void
    {
        $panier = $this->panierCourant($paniers);

        if ($panier === null) {
            return;
        }

        try {
            $paniers->changerQuantite($panier, $cle, $delta);
        } catch (RuntimeException $refus) {
            $this->notifier($refus->getMessage(), 'error');
        }
    }

    public function retirerLigne(string $cle, PanierService $paniers): void
    {
        $this->exigerEcriture(self::MODULE);

        $panier = $this->panierCourant($paniers);

        if ($panier === null) {
            return;
        }

        try {
            $nom = $paniers->retirerLigne($panier, $cle);
        } catch (RuntimeException $refus) {
            $this->notifier($refus->getMessage(), 'error');

            return;
        }

        if ($nom === null) {
            return;
        }

        $this->notifier(__('pos_pwa.heberges.ligne_retiree', ['article' => $nom]));
    }

    /**
     * Applique la remise saisie au panier du sejour — directive PO 02/09/2026.
     *
     * La validation EST la formule : `PanierService::appliquerRemise()`
     * delegue a `Panier::remiseSur()` (bornes 0-100 %, jamais au-dela du
     * total, net jamais negatif). Aucune seconde arithmetique ici.
     */
    public function appliquerRemise(PanierService $paniers): void
    {
        $this->exigerEcriture(self::MODULE);

        // Un refus precedent ne doit pas survivre a une saisie corrigee.
        $this->resetErrorBag('remiseValeur');

        $panier = $this->panierCourant($paniers);

        if ($panier === null) {
            $this->notifier(__('pos_pwa.commun.remise_sans_panier'), 'error');

            return;
        }

        try {
            $paniers->appliquerRemise($panier, $this->remiseType, $this->remiseValeur);
        } catch (RuntimeException $refus) {
            $this->addError('remiseValeur', $refus->getMessage());
        }
    }

    // =====================================================================
    // La cloture — jamais silencieuse (PA-98), jamais destructrice (P3)
    // =====================================================================

    /**
     * ⚠ NE PASSE PAS par `ouvrirFormulaire()`, et la raison vaut d'etre lue.
     *
     * Le motif de formulaire fait `$this->reset($proprietes)` avec la liste du
     * registre. Or `Livewire\Component::reset([])` avec une liste VIDE ne
     * reinitialise pas « rien » : il reinitialise TOUT. Cette modale n'a aucun
     * champ, sa liste est donc vide — et l'ouvrir remettait
     * `selectedReservationId` a `null`, si bien que la cloture qui suivait
     * refusait avec « choisissez d'abord un sejour ». Le sejour etait pourtant
     * selectionne a l'ecran (31/08/2026).
     *
     * La garde d'ecriture reste posee, en toutes lettres. Le maitre demande
     * confirmation avant de clore un panier de sejour : une cloture anticipee
     * est possible, jamais silencieuse.
     */
    public function ouvrirClotureSejour(): void
    {
        $this->exigerEcriture(self::MODULE);

        $this->resetValidation();
        // Le toggle repart a « tout facturer » a chaque ouverture : payer
        // separement est un choix EXPLICITE, jamais un reste de la modale
        // precedente (directive PO 02/09/2026).
        $this->payerSeparement = false;
        $this->etatFormulaire = 'cloture';
    }

    public function cloturerEtFacturer(
        VenteService $ventes,
        EmissionFactureService $facturation,
        PanierService $paniers,
    ): void {
        $this->exigerEcriture(self::MODULE);
        // Emettre une facture est une ecriture sur M2 : n'exiger que M5
        // donnerait par le navigateur ce que l'API M2 refuse.
        $this->exigerEcriture(self::MODULE_FACTURATION);

        if ($this->selectedReservationId === null) {
            $this->notifier(__('pos_pwa.heberges.refus_aucun_sejour'), 'error');

            return;
        }

        $panier = $paniers->panierOuvertDuSejour($this->selectedReservationId);

        if ($panier === null || $panier->lignes->isEmpty()) {
            $this->notifier(__('pos_pwa.heberges.refus_panier_vide'), 'error');

            return;
        }

        if (in_array(self::MODULE_RESTAURANT, $panier->modules(), true)) {
            $this->exigerEcriture(self::MODULE_RESTAURANT);
        }

        $reservation = Reservation::with(['client', 'unite.categorie'])
            ->find($this->selectedReservationId);

        if ($reservation === null) {
            $this->notifier(__('pos_pwa.heberges.refus_aucun_sejour'), 'error');

            return;
        }

        /*
         * `unites_hebergement.categorie_id` et `categories_hebergement.
         * tarif_base` sont NOT NULL, avec une cle etrangere en RESTRICT : la
         * categorie et son tarif EXISTENT toujours. Le seul cas a refuser est
         * donc un tarif a zero — et il se lit par `bccomp()`, jamais par une
         * egalite, parce que c'est un montant.
         *
         * ⚠ Depuis la directive PO du 02/09/2026 (toggle « Payer
         * separement »), le tarif et le controle « deja facture » ne
         * s'appliquent qu'a la branche qui FACTURE l'hebergement : une
         * facture de consommations seules n'imprime aucune nuitee et ne
         * refacture rien.
         */
        $tarifNuit = (string) $reservation->unite->categorie->tarif_base;

        if ($this->payerHebergement()) {
            if (bccomp($tarifNuit, '0.00', self::PRECISION_MONTANT) <= 0) {
                // Aucun tarif de repli : facturer un chiffre que personne n'a
                // decide serait pire que refuser (P3bis).
                $this->notifier(__('pos_pwa.heberges.refus_tarif_absent'), 'error');

                return;
            }

            if ($this->dejaFacture($reservation->id)) {
                $this->notifier(__('pos_pwa.heberges.refus_deja_facture'), 'error');

                return;
            }
        }

        try {
            DB::transaction(function () use (
                $ventes,
                $facturation,
                $paniers,
                $reservation,
                $panier,
                $tarifNuit,
            ): void {
                /*
                 * La consommation entre AU REGISTRE DES VENTES, en note de
                 * chambre : elle n'est pas encaissee (c'est une creance reglee
                 * au depart), mais elle est numerotee, tracee et elle
                 * decremente le stock comme au comptoir (RG-05).
                 */
                $vente = $ventes->enregistrer([
                    'point_vente' => $this->posteDeVente(),
                    'client_id' => $reservation->client_id,
                    'reservation_id' => $reservation->id,
                    'table' => $reservation->unite?->numero,
                    'mode_paiement' => 'note_chambre',
                    // La remise du panier (PO 02/09/2026) : le net vient de
                    // l'auteur unique `Panier::remiseSur()`.
                    'remise_type' => (string) $panier->remise_type,
                    'remise_valeur' => (string) $panier->remise_valeur,
                    'utilisateur_id' => Auth::id(),
                    'lignes' => $paniers->lignesPourVente($panier),
                ]);

                /*
                 * Le panier se clot DANS la meme transaction que la vente : le
                 * laisser ouvert le ferait encaisser une seconde fois au coup
                 * suivant, et le clore hors transaction le fermerait sur une
                 * vente qu'un echec ulterieur aurait annulee.
                 */
                $paniers->cloturerSurVente($panier, $vente);

                /*
                 * Puis LA facture du sejour. Deux branches depuis le
                 * 02/09/2026 (amendement de RG-04, directive PO) :
                 * - hebergement PAYE : nuitees d'abord, consommations
                 *   ensuite — le document consolide historique ;
                 * - « Payer separement » : la facture ne porte QUE les
                 *   consommations. L'hebergement reste du sur la fiche
                 *   (`Reservation::resteAPayer()`), et sera facture plus
                 *   tard par son propre chemin — sans ligne M1, cette
                 *   facture ne consomme pas l'acompte de la reservation
                 *   (`Facture::SQL_ACOMPTES_LIES` ne lie que par M1).
                 */
                $facture = $this->payerHebergement()
                    ? $facturation->emettrePourReservation($reservation, $tarifNuit)
                    : $facturation->emettrePourConsommations($reservation);

                foreach ($vente->lignes()->get() as $ligne) {
                    $facturation->ajouterLigne(
                        facture: $facture,
                        moduleSource: (string) $ligne->module,
                        sourceId: (string) $ligne->id,
                        libelle: (string) $ligne->nom,
                        quantite: (string) $ligne->quantite,
                        prixUnitaire: (string) $ligne->prix_unitaire,
                    );
                }

                /*
                 * La remise entre a la facture en LIGNES DEDIEES negatives
                 * (directive PO 02/09/2026), une par module, prorata par
                 * `VenteService::ventilerAuNet()` — la MEME proration que la
                 * piece comptable de la vente : le TTC de la facture egale le
                 * net de la vente au centime, et la ventilation par module de
                 * `lignes_facture.source_module` reste exacte.
                 */
                $remiseVente = $vente->remiseDeduite();

                if (bccomp($remiseVente, '0.00', self::PRECISION_MONTANT) > 0) {
                    $this->ajouterLignesRemise($facturation, $facture, $vente);
                }
            });
        } catch (RuntimeException $refus) {
            // Refus du domaine : son message est ecrit pour l'operateur.
            $this->notifier($refus->getMessage(), 'error');

            return;
        } catch (\Throwable $erreur) {
            /*
             * ⚠ ICI ETAIT LE DEFAUT. La transaction a tout annule : le panier
             * est TOUJOURS OUVERT en base, avec ses lignes. La cause part au
             * journal technique : la remonter telle quelle ferait fuir du SQL
             * au comptoir.
             */
            report($erreur);
            $this->notifier(__('pos_pwa.heberges.refus_facturation'), 'error');

            return;
        }

        // Le message DIT ce qui a ete facture : une facture de consommations
        // seules annoncee comme « sejour facture » laisserait croire la fiche
        // soldee (PA-59/60/61, version toast).
        $this->terminerFormulaire($this->payerHebergement()
            ? __('pos_pwa.heberges.facture_emise', ['client' => $reservation->client->nom])
            : __('pos_pwa.heberges.facture_emise_consommations', ['client' => $reservation->client->nom]));
    }

    /**
     * Les lignes negatives de remise de la facture — une par module, au
     * prorata de `VenteService::ventilerAuNet()` (l'auteur unique de la
     * proration, partage avec la piece comptable).
     */
    private function ajouterLignesRemise(
        EmissionFactureService $facturation,
        \App\Domain\Facturation\Models\Facture $facture,
        \App\Domain\Ventes\Models\Vente $vente,
    ): void {
        $brutParModule = [];
        $totalBrut = '0.00';

        foreach ($vente->lignes()->get() as $ligne) {
            $module = (string) $ligne->module;
            $brutParModule[$module] = bcadd(
                $brutParModule[$module] ?? '0.00',
                (string) $ligne->montant,
                self::PRECISION_MONTANT,
            );
            $totalBrut = bcadd($totalBrut, (string) $ligne->montant, self::PRECISION_MONTANT);
        }

        $netParModule = VenteService::ventilerAuNet(
            $brutParModule,
            $totalBrut,
            (string) $vente->montant_total,
        );

        foreach ($brutParModule as $module => $brut) {
            $part = bcsub($brut, $netParModule[$module], self::PRECISION_MONTANT);

            if (bccomp($part, '0.00', self::PRECISION_MONTANT) <= 0) {
                continue;
            }

            $facturation->ajouterLigne(
                facture: $facture,
                moduleSource: $module,
                sourceId: (string) $vente->id,
                libelle: __('ventes.remise_ligne_facture').' — '.(VenteService::MODULES[$module] ?? $module),
                quantite: '1.00',
                prixUnitaire: '-'.$part,
            );
        }
    }

    /**
     * Ce sejour porte-t-il deja une facture ? Une seconde emission
     * refacturerait les nuitees.
     */
    private function dejaFacture(string $reservationId): bool
    {
        return LigneFacture::query()
            ->where('source_module', self::MODULE_HEBERGEMENT)
            ->where('source_id', $reservationId)
            ->exists();
    }

    /**
     * Ferme la modale ouverte — exigee par le chassis partage.
     *
     * LECTURE : fermer ne touche aucune table.
     */
    public function fermerModales(): void
    {
        $this->etatFormulaire = null;
        $this->resetValidation();
    }

    // =====================================================================

    public function render(PanierService $paniers): View
    {
        $sejours = $this->sejoursEnCours();

        // Bar et restaurant seulement (directive PO du 26/10/2026).
        $catalogueComplet = $this->catalogue([
            self::MODULE_BAR,
            self::MODULE_RESTAURANT,
        ]);

        // UNE requete pour tous les sejours affiches : une par ligne rendrait
        // la liste inutilisable des la haute saison.
        $paniersParSejour = $paniers->paniersOuvertsDesSejours(
            $sejours->map(fn (Reservation $r): string => (string) $r->id)->all(),
        );

        $panier = $this->selectedReservationId === null
            ? null
            : $paniersParSejour->get($this->selectedReservationId);

        // Le net vient de l'auteur unique, en version TOLERANTE a
        // l'affichage (`Panier::remisePourAffichage()`) : une remise devenue
        // hors bornes rend le brut, et c'est la cloture qui refuse en
        // nommant la cause.
        $remisePanier = $panier?->remisePourAffichage() ?? '0.00';
        $totalNet = $panier?->totalNetPourAffichage() ?? '0.00';

        /*
         * Le RECAPITULATIF de la modale de cloture (directive PO 02/09/2026) :
         * nuitees × tarif — LA MEME source que `cloturerEtFacturer()`
         * (`categories_hebergement.tarif_base`), pour ne jamais afficher un
         * chiffre et en facturer un autre.
         */
        $reservationActive = $sejours->firstWhere('id', $this->selectedReservationId);
        $tarifNuitActif = $reservationActive === null
            ? '0.00'
            : (string) $reservationActive->unite->categorie->tarif_base;
        $nuiteesActives = $reservationActive?->nombreNuitees() ?? 0;
        $totalHebergement = bcmul((string) $nuiteesActives, $tarifNuitActif, self::PRECISION_MONTANT);

        // Les KPI du maitre — comptes sur les paniers REELS, jamais sur une
        // colonne que personne n'ecrit (PA-126).
        $encours = '0.00';

        foreach ($paniersParSejour as $panierSejour) {
            // NET par panier (PO 02/09/2026) : l'en-cours dit ce qui sera
            // reellement facture, pas un brut que la remise a deja reduit.
            $encours = bcadd($encours, $panierSejour->totalNetPourAffichage(), self::PRECISION_MONTANT);
        }

        return view('pwa.pos.heberges', array_merge($this->socle(), [
            'sejours' => $sejours,
            'paniersParSejour' => $paniersParSejour,
            'reservationActive' => $reservationActive,
            'catalogue' => $this->filtrerCatalogue(
                $catalogueComplet,
                'tout',
                $this->categorieActive,
                $this->recherche,
            ),
            'categories' => $this->categoriesDuCatalogue($catalogueComplet),
            'panier' => $panier,
            'totalPanier' => $panier?->total() ?? '0.00',
            'remisePanier' => $remisePanier,
            'totalNet' => $totalNet,
            'nuiteesActives' => $nuiteesActives,
            'tarifNuitActif' => $tarifNuitActif,
            'totalHebergement' => $totalHebergement,
            'ventilation' => $panier?->ventilationParModule() ?? [],
            'paniersOuverts' => $paniersParSejour->count(),
            'encoursSejours' => $encours,
            'modules' => VenteService::MODULES,
        ]))->layout('layouts.pwa', [
            'module' => self::MODULE,
            'title' => __('pos_pwa.heberges.titre_page'),
        ]);
    }
}
