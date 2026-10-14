<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Pos;

use App\Domain\Caisse\Models\SessionCaisse;
use App\Domain\Stocks\Exceptions\RuptureStockException;
use App\Domain\Stocks\Models\PointStockage;
use App\Domain\Stocks\Services\StockTheoriqueService;
use App\Domain\Ventes\Models\Panier;
use App\Domain\Ventes\Models\Vente;
use App\Domain\Ventes\Services\PanierService;
use App\Domain\Ventes\Services\TableSalleService;
use App\Domain\Ventes\Services\VenteService;
use App\Models\User;
use App\Pwa\Livewire\Concerns\FormulaireModal;
use App\Pwa\Livewire\PageMetier;
use App\Pwa\Support\MontantFcfa;
use App\Shared\ReportEngine\Services\ReportHeaderService;
use Barryvdh\DomPDF\Facade\Pdf;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\View\View;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Title;
use Livewire\Attributes\Url;
use RuntimeException;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * Point de vente COMPTANT — maitre : prototype_v2/pages/pos.html.
 *
 * ## Les trois defauts que cet ecran portait (PA-159, lot POS)
 *
 * **P1 — le repas encaisse et enregistre nulle part.** `encaisser()` faisait
 * `array_filter($panier, fn ($l) => $l['type'] === 'boisson')` et ne persistait
 * que ces lignes. Le ticket, lui, totalisait le panier ENTIER, et le message
 * disait « Vente encaissee avec succes ! ». Le client payait son repas, la
 * caisse affichait le bon total, et le repas n'apparaissait ni au journal des
 * ventes ni dans la deduction de stock cuisine. Il n'y a plus qu'un appel,
 * `VenteService::enregistrer()`, avec TOUTES les lignes et leur module.
 *
 * **P2 — deux registres qui ne se rencontraient jamais.** L'ecran ecrivait
 * `ventes_bar` pendant que le journal lisait `ventes`. Le numero etait
 * fabrique sur place a partir d'un prefixe d'UUID, ou d'un `date('YmdHis')`
 * quand le panier n'avait pas de boisson : deux ventes de la meme seconde
 * portaient le meme numero. La sequence est desormais allouee par le service,
 * sous verrou pessimiste, et AUCUN numero n'est fabrique ici.
 *
 * **P5 — une vente supprimee.** `annulerVente()` appelait la suppression
 * Eloquent sur une table financiere. Une vente ne se supprime pas : elle
 * s'ANNULE, avec
 * motif obligatoire, horodatage et compensation de stock (RG-02).
 *
 * ## Le prix ne vient jamais de l'ecran
 *
 * `ajouterAuPanier()` recoit un MODULE et une REFERENCE, jamais un montant :
 * le prix et le libelle sont relus du catalogue et figes (voir
 * {@see ComposePanier}). L'ancienne signature acceptait le prix depuis le DOM
 * — n'importe qui pouvait appeler l'action avec le sien.
 *
 * ## P4 — les paniers de salle sont une TABLE depuis le 31/08/2026 (PA-161)
 *
 * `paniersParTable` etait une propriete de composant : les paniers de toutes
 * les tables mouraient au rechargement de la page, et n'existaient que dans
 * l'onglet du navigateur qui les avait ouverts. Le serveur qui prenait la
 * releve ne voyait aucune commande en cours. Ils vivent desormais dans
 * `paniers`, un par `(point_vente, table_id)`, et l'unicite du panier ouvert
 * est tenue par `PanierService` sous verrou — l'arbitrage (f) de PA-161 ayant
 * tranche Q2 en faveur du service, MySQL n'ayant pas d'index partiel.
 *
 * Consequence visible : l'etat d'une table se DERIVE de son panier reel. Le
 * troisieme etat du maitre — « ouverte » — devient atteignable, la ou l'ecran
 * n'en rendait que deux : une table dont on a vide le panier reste ouverte,
 * elle n'est pas redevenue libre.
 *
 * ⚠ Ces paniers ne quittent PAS ce serveur : `paniers` n'est pas au registre
 * `TABLES_SYNCHRONISABLES`. L'ecran dit « enregistre sur ce poste », jamais
 * « en attente de synchronisation » (PA-59/60/61).
 *
 * ## Le POSTE n'est pas la CAISSE (PA-79)
 *
 * `ventes.point_vente` porte l'espace ou la vente a lieu ; la session de
 * caisse porte le TIROIR qui l'encaisse. Le schema ne connait qu'un tiroir
 * pour ce comptoir (`sessions_caisse.point_vente` est un enum de trois
 * valeurs, et aucune table ne rattache un espace de salle a une caisse) :
 * inventer ce rattachement produirait un fond de caisse par espace que
 * personne ne compte.
 *
 * @see EF-M5-06 Vente au comptoir du bar
 * @see EF-M4-03 Prise de commande
 * @see RG-02 Aucune suppression — une vente s'annule
 * @see RG-05 Sortie de stock automatique
 * @see RG-06 Rupture assumee, jamais subie en silence
 */
#[Layout('layouts.pwa')]
#[Title('Point de vente comptant — TATACORA AFRIQUE')]
class PosComptant extends PageMetier
{
    use ComposePanier;
    use FormulaireModal;

    /**
     * Le module RBAC de l'ecran. Un ticket qui porte des plats exige EN PLUS
     * le droit sur M4 : voir {@see encaisser()}.
     */
    public const MODULE = 'M5';

    /** Le tiroir de caisse de ce comptoir — enum `sessions_caisse.point_vente`. */
    public const POINT_CAISSE = 'bar';

    /**
     * Le plan de salle — le REFERENTIEL `tables_salle`, plus un registre
     * d'ecran (02/09/2026).
     *
     * ⚠ La constante `PLAN_DE_SALLE` qui vivait ici est RETIREE, et c'etait
     * annonce dans sa propre documentation (« le jour ou une table
     * `tables_service` existera, il disparaitra d'ici ») : la table
     * `tables_salle` existe, `TableSalleService` en est l'unique auteur, et
     * l'onglet « Espaces & tables » de Parametres cree, renumerote et
     * desactive sans intervention technique — la demande explicite de
     * l'atelier que le registre code en dur contredisait.
     *
     * L'etat `fermee` du maitre reste NON rendu ici, mais la raison a change
     * (l'ancienne — « aucun drapeau `actif` n'existe » — a cesse d'etre
     * vraie) : le plan du POS ne contient QUE les tables actives, une table
     * desactivee est RETIREE de la salle, pas barree — meme regle que les
     * boutons d'action (Article 3.3). Les TROIS autres etats du maitre sont
     * rendus depuis le 31/08/2026 : `libre`, `ouverte`, `en_cours`.
     *
     * Memoise par requete : trois appelants par rendu, une seule requete.
     *
     * @var array<string, list<array{id: string, libelle: string, places: int}>>|null
     */
    private ?array $planDeSalleMemo = null;

    /**
     * @return array<string, list<array{id: string, libelle: string, places: int}>>
     */
    private function planDeSalle(): array
    {
        return $this->planDeSalleMemo ??= app(TableSalleService::class)->planDeSalle();
    }

    /** Le poste affiche quand la vente n'a pas de table. */
    public const POSTE_COMPTOIR = 'Bar';

    /**
     * Les trois etats de table que l'ecran rend, dans l'ordre du maitre.
     *
     * Le quatrieme (`fermee`) n'est pas rendu : voir {@see planDeSalle()}.
     */
    public const ETAT_LIBRE = 'libre';

    public const ETAT_OUVERTE = 'ouverte';

    public const ETAT_EN_COURS = 'en_cours';

    #[Url(as: 'famille')]
    public string $famille = 'tout';

    #[Url(as: 'q')]
    public string $recherche = '';

    #[Url(as: 'cat')]
    public string $categorieActive = 'tout';

    #[Url(as: 'table')]
    public ?string $selectedTableId = null;

    public string $modePaiement = 'especes';

    /**
     * Le client de la vente au comptoir — TEXTE LIBRE facultatif, plus un
     * sélecteur du référentiel M3 (directive PO du 02/09/2026).
     *
     * ⚠ ÉCART ASSUMÉ à « tout champ relationnel est une vraie clé étrangère,
     * jamais du texte libre » : ce champ n'est PAS relationnel. La vente au
     * comptoir est anonyme par nature ; ce nom est une MENTION imprimée sur
     * le ticket et la facture (`ventes.client_mention`), il n'alimente aucun
     * registre client et ne porte aucun solde. La vraie FK `ventes.client_id`
     * reste au schéma pour le POS des clients hébergés et les ventes déjà
     * liées — le NOUVEAU flux comptant n'écrit que la mention.
     */
    public string $clientMention = '';

    /**
     * La remise du panier courant — type + valeur, le motif de la fiche de
     * réservation (directive PO du 02/09/2026). Persistées sur le PANIER par
     * {@see appliquerRemise()} : le net est dérivé par l'auteur unique
     * `Panier::remiseSur()`, jamais recalculé ici.
     */
    public string $remiseType = Panier::REMISE_AUCUNE;

    public string $remiseValeur = '';

    /**
     * Vrai des que l'operateur a explicitement choisi le comptoir (bouton
     * « Vendre au comptoir »). `false` par defaut — jamais un choix implicite.
     *
     * ## Ce que cette propriete corrige (01/09/2026)
     *
     * `posteCourant()` retombait TOUJOURS sur `POSTE_COMPTOIR` des qu'aucune
     * table n'etait selectionnee : le comptoir etait donc PRESELECTIONNE des
     * le premier affichage de l'ecran, et `ajouterAuPanier()` ouvrait un
     * panier au comptoir sur le tout premier clic d'un article — sans qu'aucun
     * choix n'ait ete pose. Le maitre (pos.html l.94-97) affiche « Aucun
     * panier ouvert — Choisissez une table ou le comptoir dans la salle. »
     * tant qu'aucun des deux n'a ete choisi : {@see posteEstChoisi()} rend cet
     * etat atteignable cote serveur, en s'ajoutant a `selectedTableId`.
     *
     * Non liee a l'URL, deliberement : le maitre ne conserve pas non plus ce
     * choix au rechargement (`contexteVente` y est une variable JS en
     * memoire, remise a `null` a chaque chargement de page).
     */
    public bool $comptoirChoisi = false;

    /**
     * Fond de caisse et montant compte : des CHAINES, jamais des flottants,
     * et sans valeur par defaut. Un fond de caisse prerempli serait un montant
     * invente sur une piece financiere — la lecon de PA-53.
     */
    public string $fondCaisseSaisi = '';

    public string $montantConstateSaisi = '';

    /** La vente qui vient d'etre encaissee — relue en base, jamais recopiee. */
    public ?string $derniereVenteId = null;

    /** La vente visee par la modale d'annulation, et son motif obligatoire. */
    public ?string $venteAAnnulerId = null;

    public string $motifAnnulation = '';

    /**
     * Le detail d'une rupture de stock en attente de confirmation (RG-06).
     * `null` : aucune rupture en suspens.
     */
    public ?string $ruptureConstatee = null;

    /**
     * Le registre FERME des modales de l'ecran (motif `FormulaireModal`).
     *
     * ⚠ Une entree a la liste VIDE ne doit JAMAIS etre ouverte par
     * `ouvrirFormulaire()` : `Livewire\Component::reset([])` reinitialise
     * TOUTES les proprietes du composant, dont la table selectionnee et le
     * mode de reglement. `journal` et `ticket` sont donc ouvertes en posant
     * `etatFormulaire` directement, avec leur garde d'ecriture. Elles restent
     * inscrites ici parce que ce registre nomme les modales de l'ecran, pas
     * seulement celles qui portent un champ.
     *
     * @return array<string, list<string>>
     */
    protected function formulaires(): array
    {
        return [
            'ouverture-caisse' => ['fondCaisseSaisi'],
            'cloture-caisse' => ['montantConstateSaisi'],
            'journal' => [],
            'ticket' => [],
            'annulation' => ['venteAAnnulerId', 'motifAnnulation'],
            'rupture' => ['ruptureConstatee'],
        ];
    }

    // =====================================================================
    // Lecture — aucune de ces methodes n'est publique : l'etat d'affichage
    // se pilote par `$set`, qui n'est pas une action du composant.
    // =====================================================================

    /**
     * Le panier ouvert du poste courant, ou `null`.
     *
     * LECTURE stricte : afficher l'ecran n'ouvre aucun panier. Ouvrir a la
     * lecture creerait un panier a chaque affichage, y compris pour un role en
     * `L`, et le plan de salle passerait « ouverte » sur toutes les tables que
     * personne n'a servies — l'indicateur qui affirme un etat que rien n'a
     * produit (PA-59/60/61).
     */
    private function panierCourant(PanierService $paniers): ?Panier
    {
        return $paniers->panierOuvertDuPoste($this->posteCourant(), $this->selectedTableId);
    }

    /**
     * La table selectionnee, ou `null` au comptoir.
     *
     * @return array{id: string, libelle: string, places: int, espace: string}|null
     */
    private function tableSelectionnee(): ?array
    {
        foreach ($this->planDeSalle() as $espace => $tables) {
            foreach ($tables as $table) {
                if ($table['id'] === $this->selectedTableId) {
                    return $table + ['espace' => $espace];
                }
            }
        }

        return null;
    }

    /** Le POSTE de la vente : l'espace de la table, ou le comptoir. */
    private function posteCourant(): string
    {
        return $this->tableSelectionnee()['espace'] ?? self::POSTE_COMPTOIR;
    }

    /**
     * Vrai des qu'une table OU le comptoir a ete explicitement choisi.
     *
     * @see $comptoirChoisi
     */
    private function posteEstChoisi(): bool
    {
        return $this->selectedTableId !== null || $this->comptoirChoisi;
    }

    private function sessionOuverte(): ?SessionCaisse
    {
        return SessionCaisse::query()
            ->where('point_vente', self::POINT_CAISSE)
            ->whereNull('date_cloture')
            ->latest('date_ouverture')
            ->first();
    }

    // =====================================================================
    // Le panier — chaque geste exige le droit d'ecrire sur M5
    // =====================================================================

    /**
     * Ajoute UNE unite d'une reference au panier courant.
     *
     * Ni prix ni libelle en parametre : ils sont relus du catalogue et figes.
     */
    public function ajouterAuPanier(string $module, string $reference, PanierService $paniers): void
    {
        $this->exigerEcriture(self::MODULE);

        /*
         * Le maitre (pos.html l.94-97) exige une table OU le comptoir choisi
         * AVANT tout ajout : « Aucun panier ouvert — Choisissez une table ou
         * le comptoir dans la salle. » `posteCourant()` retombant toujours sur
         * le comptoir par defaut, ce controle est ce qui empeche un panier de
         * s'ouvrir au comptoir sur un clic qui n'a rien choisi.
         */
        if (! $this->posteEstChoisi()) {
            $this->notifier(__('pos_pwa.comptant.panier_choisir'), 'error');

            return;
        }

        /*
         * Ce controle-ci est celui de l'ECRAN : il rend les mots du maitre
         * (pos.html l.520) et, surtout, il evite d'OUVRIR un panier — donc de
         * faire passer une table a « ouverte » — sur un clic qui ne peut rien
         * ajouter.
         *
         * ⚠ Il ne garantit RIEN sur le prix enregistre : c'est `PanierService`
         * qui relit le catalogue et fige prix et libelle. Si cette resolution
         * d'ecran mentait, la ligne ecrite resterait juste. La redondance est
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

        try {
            $panier = $paniers->ouvrirPourPoste(
                $this->posteCourant(),
                $this->selectedTableId,
                $this->sessionOuverte()?->id,
            );
            $paniers->ajouterLigne($panier, $module, $reference);
        } catch (RuntimeException $refus) {
            // Les refus du domaine sont ecrits POUR l'operateur
            // (`lang/fr/ventes.php`), et aucun ne porte de SQL.
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

        $this->notifier(__('pos_pwa.comptant.ligne_retiree', ['article' => $nom]));
    }

    /**
     * Vide le panier SANS liberer la table — geste « Vider » du maitre.
     *
     * La table reste OUVERTE : le client est toujours assis. C'est l'etat
     * `ouverte` du maitre, que l'ecran ne pouvait pas rendre tant que le panier
     * vivait en memoire (un panier vide y etait indiscernable d'une table
     * libre).
     */
    public function viderPanier(PanierService $paniers): void
    {
        $this->exigerEcriture(self::MODULE);

        $panier = $this->panierCourant($paniers);

        if ($panier === null) {
            return;
        }

        try {
            $paniers->vider($panier);
        } catch (RuntimeException $refus) {
            $this->notifier($refus->getMessage(), 'error');
        }
    }

    /**
     * Applique la remise saisie au panier courant — directive PO 02/09/2026.
     *
     * La validation EST la formule : `PanierService::appliquerRemise()`
     * délègue à `Panier::remiseSur()`, qui borne (0-100 %, jamais au-delà du
     * total) et refuse tout net négatif. Aucune seconde arithmétique ici.
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

    /**
     * Abandonne le panier et revient au comptoir — le geste du maitre.
     *
     * Le panier est CLOTURE sans vente, jamais supprime : la table redevient
     * libre, et le registre garde la trace qu'elle a ete ouverte puis quittee.
     * L'effacer rendrait cette minute indiscernable d'une table jamais servie.
     */
    public function abandonnerPanier(PanierService $paniers): void
    {
        $this->exigerEcriture(self::MODULE);

        $panier = $this->panierCourant($paniers);

        if ($panier !== null) {
            try {
                $paniers->abandonner($panier);
            } catch (RuntimeException $refus) {
                $this->notifier($refus->getMessage(), 'error');

                return;
            }
        }

        $this->selectedTableId = null;
        $this->notifier(__('pos_pwa.comptant.panier_abandonne'), 'info');
    }

    // =====================================================================
    // L'encaissement — un SEUL appel, toutes les lignes, tous les rayons
    // =====================================================================

    public function encaisser(VenteService $ventes, PanierService $paniers): void
    {
        $this->exigerEcriture(self::MODULE);

        $this->encaissementReel($ventes, $paniers, validationRupture: false);
    }

    /**
     * RG-06 — la rupture est ASSUMEE par un utilisateur habilite, jamais subie
     * en silence. Le maitre pose la meme question (« Vendre quand meme »).
     */
    public function encaisserMalgreRupture(VenteService $ventes, PanierService $paniers): void
    {
        $this->exigerEcriture(self::MODULE);

        $this->encaissementReel($ventes, $paniers, validationRupture: true);
    }

    private function encaissementReel(
        VenteService $ventes,
        PanierService $paniers,
        bool $validationRupture,
    ): void {
        $panier = $this->panierCourant($paniers);

        if ($panier === null || $panier->lignes->isEmpty()) {
            $this->notifier(__('pos_pwa.comptant.refus_panier_vide'), 'error');

            return;
        }

        /*
         * Un ticket qui melange le bar et le restaurant est une ecriture sur
         * DEUX modules : `VenteService` cree et transmet une commande de
         * cuisine pour les lignes M4 (RG-05). N'exiger que M5 donnerait a un
         * barman, par le navigateur, ce que l'API M4 lui refuse (PA-65).
         */
        if (in_array(self::MODULE_RESTAURANT, $panier->modules(), true)) {
            $this->exigerEcriture(self::MODULE_RESTAURANT);
        }

        /*
         * « Porté sur la note de chambre » n'existe pas au comptoir — aucune
         * chambre n'y porte de note (directive PO du 02/09/2026). Le mode a
         * disparu du sélecteur, mais une propriété Livewire se pose depuis le
         * navigateur : le refus serveur est ce qui tient.
         */
        if (VenteService::estModeNoteChambre($this->modePaiement)) {
            $this->notifier(__('pos_pwa.comptant.refus_note_chambre_comptoir'), 'error');

            return;
        }

        $session = $this->sessionOuverte();

        if ($session === null) {
            $this->notifier(__('pos_pwa.comptant.refus_sans_caisse'), 'error');

            return;
        }

        $table = $this->tableSelectionnee();

        try {
            /*
             * La vente ET la cloture du panier dans la MEME transaction : un
             * panier laisse ouvert sur une vente enregistree serait encaisse
             * une seconde fois au coup suivant, et une cloture posee hors
             * transaction survivrait a une vente que le stock a fait echouer.
             */
            $vente = DB::transaction(function () use (
                $ventes,
                $paniers,
                $panier,
                $session,
                $table,
                $validationRupture,
            ): Vente {
                $vente = $ventes->enregistrer([
                    'session_id' => $session->id,
                    'point_vente' => $this->posteCourant(),
                    // Le NOUVEAU flux comptant n'écrit que la MENTION, jamais
                    // une FK client (décision PO 02/09/2026 — voir
                    // `$clientMention`).
                    'client_id' => null,
                    'client_mention' => $this->clientMention,
                    'table' => $table['libelle'] ?? null,
                    'table_id' => $table['id'] ?? null,
                    'mode_paiement' => $this->modePaiement,
                    // La remise vient du PANIER, où `appliquerRemise()` l'a
                    // posée : le net est dérivé par `Panier::remiseSur()`,
                    // l'auteur unique — même formule à l'écran et à la pièce.
                    'remise_type' => (string) $panier->remise_type,
                    'remise_valeur' => (string) $panier->remise_valeur,
                    'utilisateur_id' => Auth::id(),
                    'validation_rupture' => $validationRupture,
                    // Ni prix ni libelle : le service les fige depuis le catalogue.
                    'lignes' => $paniers->lignesPourVente($panier),
                ]);

                $paniers->cloturerSurVente($panier, $vente);

                return $vente;
            });
        } catch (RuptureStockException $rupture) {
            // Nommee a l'ecran comme une QUESTION, pas comme une panne : le
            // panier reste intact et l'operateur decide (RG-06).
            $this->ruptureConstatee = $rupture->getMessage();
            $this->etatFormulaire = 'rupture';

            return;
        } catch (RuntimeException $refus) {
            /*
             * Les refus du domaine sont ecrits POUR l'operateur
             * (`lang/fr/ventes.php`) : les afficher tels quels lui dit quoi
             * corriger, et aucun d'eux ne porte de SQL.
             */
            $this->notifier($refus->getMessage(), 'error');

            return;
        } catch (\Throwable $erreur) {
            /*
             * Tout le reste part au journal technique et ne remonte PAS a
             * l'ecran : un message d'exception brut y ferait fuir du SQL. La
             * transaction est annulee, donc le panier est TOUJOURS OUVERT avec
             * ses lignes — c'est la seule copie de la commande.
             */
            report($erreur);
            $this->notifier(__('pos_pwa.comptant.refus_encaissement'), 'error');

            return;
        }

        // Aucun vidage ici : la cloture s'est faite DANS la transaction. La
        // table redevient libre parce que son panier n'est plus ouvert, pas
        // parce qu'on aurait efface une variable d'ecran.
        $this->derniereVenteId = $vente->id;
        $this->ruptureConstatee = null;
        // La mention et la remise appartiennent a la vente qui vient d'etre
        // encaissee : le prochain client ne doit pas en heriter.
        $this->clientMention = '';
        $this->remiseType = Panier::REMISE_AUCUNE;
        $this->remiseValeur = '';
        $this->etatFormulaire = 'ticket';
        $this->notifier(__('pos_pwa.comptant.vente_enregistree', ['numero' => $vente->numero]));
    }

    /**
     * Le TICKET de la vente, rendu en A4 (PA-101).
     *
     * Ticket et facture sont la meme piece sur deux papiers : ajouter un
     * format est un ajout de RENDU. Aucun cachet fiscal n'est invente — le
     * gabarit reserve et NOMME son emplacement, sans rien de scannable.
     */
    public function imprimerTicketA4(ReportHeaderService $entetes): ?StreamedResponse
    {
        $utilisateur = $this->exigerEcriture(self::MODULE);

        $vente = $this->derniereVenteId === null
            ? null
            : Vente::with('lignes')->find($this->derniereVenteId);

        if ($vente === null) {
            $this->notifier(__('pos_pwa.journal.refus_vente_absente'), 'error');

            return null;
        }

        $pdf = Pdf::loadView('pdf.facture-ticket', [
            'vente' => $vente,
            'quand' => now()->format('d/m/Y H:i'),
            'auteur' => $this->auteur(),
            // En-tete etablissement — source unique RG-19, jamais recopiee en dur.
            'entete' => $entetes->genererEnTete(
                typeRapport: __('pos_pwa.document.ticket_titre'),
                periode: '',
                auteur: $utilisateur,
            ),
        ])->setPaper('a4', 'portrait');

        return response()->streamDownload(
            static function () use ($pdf): void {
                echo $pdf->output();
            },
            'ticket_'.$vente->numero.'.pdf',
        );
    }

    // =====================================================================
    // La caisse — UN seul chemin d'ecriture, sans repli (P7)
    // =====================================================================

    public function ouvrirFormulaireOuvertureCaisse(): void
    {
        $this->ouvrirFormulaire('ouverture-caisse');
    }

    /**
     * ⚠ NE PASSE PAS par le pre-remplissage habituel d'`ouvrirFormulaire()`,
     * et la raison vaut d'etre lue.
     *
     * Le montant constate est pre-rempli du THEORIQUE — maitre,
     * `caisse-ui.js` l.146 (`value="${theorique}"`) — jamais d'une valeur
     * inventee : c'est un montant REELLEMENT CALCULE (fond + especes
     * encaissees), que le caissier corrige au comptage. Ce n'est pas le
     * defaut refuse par PA-53 (un taux suppose sur une piece financiere) :
     * c'est la meme donnee que celle affichee dans le recapitulatif juste
     * au-dessus du champ.
     */
    public function ouvrirFormulaireClotureCaisse(): void
    {
        $this->ouvrirFormulaire('cloture-caisse');

        $session = $this->sessionOuverte();

        if ($session !== null) {
            $this->montantConstateSaisi = $this->theoriqueDeLaSession($session);
        }
    }

    /**
     * ⚠ NE PASSE PAS par `ouvrirFormulaire()`, et la raison vaut d'etre lue.
     *
     * Le motif de formulaire fait `$this->reset($proprietes)` avec la liste du
     * registre. Or `Livewire\Component::reset([])` avec une liste VIDE ne
     * reinitialise pas « rien » : il reinitialise TOUT. Le journal du jour n'a
     * aucun champ, sa liste est donc vide — et l'ouvrir aurait vide
     * `paniersParTable`, c'est-a-dire la commande en cours, pour afficher un
     * ecran de consultation. Trouve par un test qui echouait sur un panier
     * devenu introuvable (31/08/2026).
     *
     * LECTURE — inscrite comme telle dans `METHODES_DE_LECTURE` le 31/08/2026 :
     * le journal du jour est un ecran de CONSULTATION. Un role en `L` sur M5
     * atteint deja cette page (`module:M5,L`) ; lui interdire d'y lire les
     * ventes du jour n'aurait protege aucune donnee. Les gestes qu'il contient
     * — annuler une vente — gardent, eux, leur propre garde.
     */
    public function ouvrirJournalDuJour(): void
    {
        $this->resetValidation();
        $this->etatFormulaire = 'journal';
    }

    public function ouvrirCaisse(): void
    {
        $donnees = $this->validerEcriture([
            'fondCaisseSaisi' => ['required', 'numeric', 'min:0'],
        ]);

        if ($this->sessionOuverte() !== null) {
            $this->addError('fondCaisseSaisi', __('pos_pwa.comptant.refus_caisse_deja_ouverte'));

            return;
        }

        SessionCaisse::create([
            'point_vente' => self::POINT_CAISSE,
            'utilisateur_ouverture_id' => Auth::id(),
            'date_ouverture' => now(),
            'montant_fond' => (string) $donnees['fondCaisseSaisi'],
        ]);

        $this->terminerFormulaire(__('pos_pwa.comptant.caisse_ouverte_message', [
            'point' => self::POINT_CAISSE,
        ]));
    }

    public function cloturerCaisse(): void
    {
        $donnees = $this->validerEcriture([
            'montantConstateSaisi' => ['required', 'numeric', 'min:0'],
        ]);

        $session = $this->sessionOuverte();

        if ($session === null) {
            $this->addError('montantConstateSaisi', __('pos_pwa.comptant.refus_sans_caisse'));

            return;
        }

        $theorique = $this->theoriqueDeLaSession($session);
        $constate = (string) $donnees['montantConstateSaisi'];
        $ecart = bcsub($constate, $theorique, self::PRECISION_MONTANT);

        $session->update([
            'date_cloture' => now(),
            'montant_theorique' => $theorique,
            'montant_constate' => $constate,
        ]);

        // Maitre — `caisse-ui.js` l.157-158 : « aucun ecart » plutot qu'un
        // ecart de zero, jamais un signe brut sur une piece financiere.
        $this->terminerFormulaire(
            bccomp($ecart, '0.00', self::PRECISION_MONTANT) === 0
                ? __('pos_pwa.comptant.caisse_cloturee_sans_ecart', ['point' => self::POINT_CAISSE])
                : __('pos_pwa.comptant.caisse_cloturee', [
                    'point' => self::POINT_CAISSE,
                    'ecart' => MontantFcfa::format($ecart),
                ]),
        );
    }

    /**
     * Le nom de qui edite le document (RG-15).
     *
     * `Auth::user()` est type non-nullable par l'analyse statique, mais un
     * document peut etre demande hors session : le `instanceof` dit les deux
     * verites a la fois.
     */
    private function auteur(): string
    {
        $utilisateur = Auth::user();

        return $utilisateur instanceof User ? $utilisateur->login : '';
    }

    /**
     * Ce qui est REELLEMENT dans le tiroir en especes : les ventes en
     * especes, validees, de la session — maitre, `caisse-ui.js` l.134-136.
     * Mobile Money, carte, virement et note de chambre en sont exclus : seuls
     * des billets remplissent un tiroir. Une vente annulee n'y est pas — la
     * confondre ferait chercher un ecart de caisse qui n'existe pas.
     */
    private function especesDeLaSession(string $sessionId): string
    {
        return (string) Vente::query()
            ->where('session_id', $sessionId)
            ->where('statut', 'validee')
            ->where('mode_paiement', 'especes')
            ->sum('montant_total');
    }

    /**
     * Fond de caisse + especes encaissees — maitre, `caisse-ui.js` l.137
     * (`theorique = s.fond_caisse + especes`). C'est la SEULE source du
     * theorique : le recapitulatif de la modale et la cloture elle-meme
     * l'appellent tous deux, pour ne jamais afficher un chiffre et en
     * enregistrer un autre.
     */
    private function theoriqueDeLaSession(SessionCaisse $session): string
    {
        return bcadd(
            (string) $session->montant_fond,
            $this->especesDeLaSession($session->id),
            self::PRECISION_MONTANT,
        );
    }

    // =====================================================================
    // L'annulation — RG-02 : elle conserve la vente, elle ne l'efface pas
    // =====================================================================

    public function ouvrirAnnulationVente(string $venteId): void
    {
        $this->ouvrirFormulaire('annulation');
        $this->venteAAnnulerId = $venteId;
    }

    public function annulerVente(VenteService $ventes): void
    {
        $this->exigerEcriture(self::MODULE);

        if (trim($this->motifAnnulation) === '') {
            $this->addError('motifAnnulation', __('pos_pwa.comptant.refus_motif_obligatoire'));

            return;
        }

        $vente = $this->venteAAnnulerId === null ? null : Vente::find($this->venteAAnnulerId);

        if ($vente === null) {
            $this->addError('motifAnnulation', __('pos_pwa.journal.refus_vente_absente'));

            return;
        }

        try {
            $ventes->annuler($vente, trim($this->motifAnnulation));
        } catch (RuntimeException $refus) {
            $this->addError('motifAnnulation', $refus->getMessage());

            return;
        }

        $this->terminerFormulaire(__('pos_pwa.comptant.vente_annulee', [
            'numero' => $vente->numero,
        ]));
        $this->reset(['venteAAnnulerId', 'motifAnnulation']);
    }

    /**
     * Ferme la modale ouverte — exigee par le chassis partage
     * (`components/pwa/modale.blade.php`), qui la nomme.
     *
     * LECTURE : fermer ne touche aucune table, et la garder sous
     * `exigerEcriture()` aurait laisse un role en `L` ouvrir le journal du
     * jour sans pouvoir le refermer.
     */
    public function fermerModales(): void
    {
        $this->etatFormulaire = null;
        $this->ruptureConstatee = null;
        $this->resetValidation();
    }

    // =====================================================================

    /**
     * L'etat de chaque table du plan de salle, derive des paniers REELS.
     *
     * Trois etats sur les quatre du maitre (`etatTable()`, pos.html l.300) :
     * `fermee` derive de `table.actif`, qu'aucune donnee ne porte. Les trois
     * autres se LISENT du registre — aucune colonne d'etat n'est stockee, et
     * c'est deliberé : une colonne que rien ne tient a jour deviendrait fausse
     * a la premiere vente encaissee depuis un autre poste (PA-126).
     *
     * ⚠ Le LIBELLE est resolu ici, jamais par une cle CONCATENEE dans la vue.
     * Coller le nom de l'etat derriere un prefixe de traduction fonctionnerait
     * a l'ecran et serait invisible a `MessagesUtilisateurTest`, qui ne relit
     * que des cles litterales : une cle manquante ne tomberait qu'au comptoir,
     * sous la forme d'un identifiant technique affiche au client. Les trois
     * cles sont donc ecrites en toutes lettres, et le registre est ferme.
     * (Constate le 31/08/2026 : la premiere version de cet ecran concatenait,
     * et la garde l'a signalee.)
     *
     * @param  Collection<string, Panier>  $paniersOuverts
     * @return array<string, array{etat: string, libelle: string, total: string}>
     */
    private function etatsDesTables(Collection $paniersOuverts): array
    {
        $etats = [];

        foreach ($this->planDeSalle() as $tables) {
            foreach ($tables as $table) {
                $panier = $paniersOuverts->get($table['id']);

                $etat = match (true) {
                    $panier === null => self::ETAT_LIBRE,
                    $panier->lignes->isEmpty() => self::ETAT_OUVERTE,
                    default => self::ETAT_EN_COURS,
                };

                $etats[$table['id']] = [
                    'etat' => $etat,
                    'libelle' => match ($etat) {
                        self::ETAT_OUVERTE => __('pos_pwa.comptant.etat_ouverte'),
                        self::ETAT_EN_COURS => __('pos_pwa.comptant.etat_en_cours'),
                        default => __('pos_pwa.comptant.etat_libre'),
                    },
                    'total' => $panier?->total() ?? '0.00',
                ];
            }
        }

        return $etats;
    }

    public function render(StockTheoriqueService $stocks, PanierService $paniers): View
    {
        $session = $this->sessionOuverte();
        $pointBar = PointStockage::where('type', self::POINT_CAISSE)->first();

        $catalogueComplet = $this->catalogue([self::MODULE_BAR, self::MODULE_RESTAURANT]);

        $catalogueAffiche = $this->filtrerCatalogue(
            $catalogueComplet,
            $this->famille,
            $this->categorieActive,
            $this->recherche,
        )->map(function (array $article) use ($stocks, $pointBar): array {
            $article['stock'] = ($pointBar !== null && $article['module'] === self::MODULE_BAR)
                ? $stocks->stock((string) $article['reference_id'], $pointBar->id)
                : null;

            return $article;
        });

        $ventesDeLaSession = $session === null
            ? collect()
            : Vente::with('lignes')
                ->where('session_id', $session->id)
                ->orderByDesc('created_at')
                ->get();

        // UNE requete pour tout le plan de salle et le comptoir : une par
        // table ferait autant d'allers-retours que la salle a de couverts.
        $paniersOuverts = $paniers->paniersComptantOuverts();
        $panier = $paniersOuverts->get($this->selectedTableId ?? '');

        // Le net vient de l'auteur unique, en version TOLERANTE a
        // l'affichage (`Panier::remisePourAffichage()`) : une remise devenue
        // hors bornes rend le brut, et c'est l'encaissement qui refuse en
        // nommant la cause — la tolerance ne vit jamais sur le chemin de
        // l'argent.
        $remisePanier = $panier?->remisePourAffichage() ?? '0.00';
        $totalNet = $panier?->totalNetPourAffichage() ?? '0.00';

        // Le RECAP de la modale de cloture — maitre, `caisse-ui.js`
        // l.140-143 : fond, especes encaissees, theorique. Calcule ici, pas
        // dans la vue, pour que la modale affiche EXACTEMENT ce que
        // `cloturerCaisse()` enregistrera.
        $especesSession = $session === null ? '0.00' : $this->especesDeLaSession($session->id);
        $theoriqueSession = $session === null ? '0.00' : $this->theoriqueDeLaSession($session);

        return view('pwa.pos.comptant', array_merge($this->socle(), [
            'session' => $session,
            'catalogue' => $catalogueAffiche,
            'categories' => $this->categoriesDuCatalogue($catalogueComplet),
            'planDeSalle' => $this->planDeSalle(),
            'etatsDesTables' => $this->etatsDesTables($paniersOuverts),
            'tableSelectionnee' => $this->tableSelectionnee(),
            'poste' => $this->posteCourant(),
            'panier' => $panier,
            'totalPanier' => $panier?->total() ?? '0.00',
            'especesSession' => $especesSession,
            'theoriqueSession' => $theoriqueSession,
            'ventesDeLaSession' => $ventesDeLaSession,
            'derniereVente' => $this->derniereVenteId === null
                ? null
                : Vente::with('lignes')->find($this->derniereVenteId),
            /*
             * Le sélecteur de clients M3 a quitté le comptoir (PO,
             * 02/09/2026) : la vente comptant est anonyme, le champ est une
             * mention en texte libre. Le registre COMPLET des modes reste
             * nécessaire à l'affichage du journal (les ventes en note des
             * clients hébergés y figurent), seul le SÉLECTEUR est réduit.
             */
            'modesPaiement' => VenteService::MODES_PAIEMENT,
            'modesPaiementComptoir' => VenteService::modesPaiementComptoir(),
            // La remise du panier courant — le montant vient du modèle
            // (auteur unique), jamais d'une seconde formule de vue.
            'remisePanier' => $remisePanier,
            'totalNet' => $totalNet,
        ]))->layout('layouts.pwa', [
            'module' => self::MODULE,
            'title' => __('pos_pwa.comptant.titre_page'),
        ]);
    }
}
