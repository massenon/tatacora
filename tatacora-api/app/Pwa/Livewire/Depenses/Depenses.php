<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Depenses;

use App\Domain\Comptabilite\Services\PlanComptableService;
use App\Domain\Depenses\Exceptions\RefusRecuDepense;
use App\Domain\Depenses\Models\Depense;
use App\Domain\Depenses\Models\LigneDepense;
use App\Domain\Depenses\Services\DepenseService;
use App\Domain\Depenses\Services\RecuDepenseService;
use App\Exports\DepensesExport;
use App\Pwa\Livewire\Concerns\FormulaireModal;
use App\Pwa\Livewire\PageMetier;
use App\Pwa\Support\ExerciceConsulte;
use App\Pwa\Support\MontantFcfa;
use Barryvdh\DomPDF\Facade\Pdf;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Collection as EloquentCollection;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Illuminate\View\View;
use Livewire\Attributes\Title;
use Livewire\Attributes\Url;
use Livewire\WithFileUploads;
use Maatwebsite\Excel\Facades\Excel;
use RuntimeException;
use Symfony\Component\HttpFoundation\Response;

/**
 * Dépense courante (M10) — maître : `prototype_v2/pages/depenses.html`.
 *
 * En-tête (l.24-40), bande d'indicateurs (l.46-53, remplie par
 * `depenses.js` l.79-92), barre de filtres et tableau à sept colonnes
 * (l.56-84), puis la modale « Nouvelle Dépense » (l.91-170).
 *
 * ## LE DÉFAUT QUE CE LOT CORRIGE — aucune dépense n'a jamais été comptabilisée
 *
 * Ce composant importait `PasserEcritureService` et l'appelait derrière une
 * garde d'existence portant sur cette classe — qui n'existait nulle part. La
 * condition rendait `false` pour toujours : sans erreur, sans journal, sans
 * un mot à l'écran. La dépense partait dans `depenses`,
 * l'opérateur recevait son bandeau vert, et le grand livre, la balance, le
 * compte de résultat et la trésorerie ne voyaient jamais l'argent sortir.
 * C'est la forme exacte de PA-59/60/61 : un indicateur qui dit « tout va
 * bien » pendant que rien n'a lieu.
 *
 * Trois choses ont changé, et chacune ferme une porte :
 *
 * 1. **La garde d'existence a disparu.** Tant qu'elle était là, un renommage
 *    futur aurait rétabli le silence à l'identique.
 * 2. **Le composant n'écrit plus rien lui-même.** Il appelle
 *    `DepenseService::enregistrer()`, qui passe la pièce et la dépense dans la
 *    MÊME transaction : une pièce refusée n'écrit RIEN.
 * 3. **Les numéros de compte ont quitté ce fichier.** Il portait `601`, `614`,
 *    `6051`, `6052`, `628`, `5711`, `5311` — sept numéros qu'aucun plan
 *    comptable du dépôt ne contient (il porte `6011`, `5711`…). Aucune
 *    écriture n'ayant jamais été tentée, la divergence n'avait jamais eu
 *    l'occasion de se voir. Le sélecteur se remplit désormais depuis
 *    `PlanComptableService::comptesDeCharge()`, et les comptes de trésorerie
 *    vivent dans `DepenseService::TRESORERIES`, à un seul endroit.
 *
 * ## Le refus s'AFFICHE, il ne se range pas dans une colonne
 *
 * `enregistrer()` lève. Le `catch` posé ici n'avale rien : il ne prend QUE
 * `RuntimeException` — le type que le domaine emploie pour ses refus, tous
 * rendus par `__()` donc écrits pour un opérateur — et il rend le message à
 * l'écran par `addError()`. Toute autre exception repart telle quelle : une
 * erreur PDO ne doit jamais atteindre l'écran, elle y ferait fuir du SQL.
 *
 * ## ÉCART DÉLIBÉRÉ — la saisie est MULTI-LIGNES, le maître ne l'est pas
 *
 * ~~« La saisie est à UNE ligne, comme le maître. »~~ **Note périmée le
 * 31/08/2026, conservée barrée plutôt que supprimée** : elle a été vraie, elle
 * ne l'est plus, et la faire disparaître ferait relire demain une décision
 * comme un oubli. Elle disait ceci, et la mesure qui la fondait est exacte :
 * `prototype_v2/pages/depenses.html` l.104-150 porte UN montant, UN libellé, UN
 * compte de charge et UNE nature ; « + Ajouter une ligne » et « total général »
 * sont à zéro sur la page comme sur `depenses.js`. Le raisonnement invoqué —
 * Article 1.07, qui interdit d'ajouter un bloc non maquetté — était le bon
 * raisonnement appliqué à la mauvaise autorité.
 *
 * **DÉCISION DU PRODUCT OWNER DU 31/08/2026, qui prévaut sur le maître.** Ses
 * mots : *« une dépense globale peut contenir une ou plusieurs lignes de
 * libellé d'achats ou autre avec son prix ; on peut éditer et supprimer dans la
 * même modale »*. L'ordre de préséance du dépôt est celui-là — les mots du
 * client d'abord, la maquette ensuite —, et l'écart est donc désormais dans
 * l'AUTRE sens : la PWA fait PLUS que la maquette, ce qui se déclare au lieu de
 * se taire.
 *
 * Trois choses n'ont PAS changé, et c'est ce qui rend l'écart tenable :
 *
 * 1. **Le domaine était déjà multi-lignes** — `lignes_depense` existe,
 *    `DepenseService::enregistrer()` a toujours pris une LISTE, et une dépense
 *    à plusieurs lignes s'affichait déjà correctement dans le tableau (voir
 *    `valeursDistinctes()`). C'était l'écran seul qui bridait.
 * 2. **UNE seule transaction, UN seul appel** — la modale envoie la liste
 *    complète à `enregistrer()`, jamais une dépense par ligne. Une pièce
 *    refusée n'écrit toujours RIEN.
 * 3. **Le total n'est pas saisi et n'est pas envoyé** — il est recalculé par
 *    `totalDesLignes()` pour l'affichage, puis RECALCULÉ une seconde fois par
 *    `DepenseService::totaliser()` à l'enregistrement, qui seul fait foi. Un
 *    total posté par le navigateur serait un montant que personne n'a vérifié
 *    sur une pièce immuable.
 *
 * Ce qui reste GLOBAL à la dépense, et pourquoi : la date, la trésorerie, le
 * libellé de la pièce, la nature et le reçu. Le décaissement est unique — c'est
 * une seule sortie de caisse —, et la nature classe la dépense dans les deux
 * indicateurs « Marché » et « Services » du maître. Ce qui est PAR LIGNE : le
 * libellé de l'achat, son compte de charge et son montant, les trois éléments
 * que le Product Owner nomme.
 *
 * @see EF-M10-02 Saisie des écritures comptables
 * @see RG-11 Immutabilité — la correction passe par contre-passation
 * @see RG-12 Centre de coût obligatoire
 * @see RG-19 Convention d'export
 * @see LARAVEL_PWA.md §3, §5
 * @see DIRECTIVE_CONFORMITE_100.md Articles 1, 4, 6, 7, 8
 */
#[Title('Dépense courante — LogiReStock — TATACORA AFRIQUE')]
class Depenses extends PageMetier
{
    use FormulaireModal;
    use WithFileUploads;

    /** Le module RBAC de l'écran — `data-module="M10"` du maître (l.14). */
    public const MODULE = 'M10';

    /**
     * Les libellés des trésoreries — ceux du maître
     * (`depenses-engine.js` l.60-64).
     *
     * ⚠ Les COMPTES et les JOURNAUX ne sont pas ici, et ne doivent jamais y
     * revenir : ils vivent dans `DepenseService::TRESORERIES`, qui est ce que
     * l'écriture emploie réellement. Le maître écrit `5711`, `5311` et `521` ;
     * le plan comptable du dépôt porte `5711`, `552` et `5211`. Deux
     * tables auraient divergé, et c'est exactement ce qui s'est produit.
     * Les CLÉS, elles, doivent rester celles du service — un test le vérifie.
     *
     * @var array<string, string>
     */
    public const TRESORERIES = [
        'caisse' => 'Caisse',
        'momo' => 'Mobile Money',
        'banque' => 'Compte bancaire',
    ];

    /**
     * Les deux familles et les douze natures du maître
     * (`depenses-engine.js` l.70-85).
     *
     * Ce sont des libellés d'écran, pas une donnée réglementaire : ils
     * classent une dépense en « denrées » ou « charges externes » pour les
     * deux indicateurs du maître. Aucune table de natures n'existe au schéma —
     * le refus est nommé à l'écran plutôt que comblé par une migration.
     *
     * @var array<string, list<string>>
     */
    public const NATURES = [
        'Services' => ['Transport', 'Électricité / eau', 'Entretien et réparations', 'Communication', 'Blanchisserie'],
        'Marché' => ['Oignon', 'Tomate', 'Piment', 'Viande', 'Poisson', 'Igname', 'Riz'],
    ];

    /**
     * Taille maximale du reçu RANGÉ, en kilo-octets — `depenses-engine.js`
     * l.46. Une seule valeur, celle du service : le poste la dépose par la
     * synchronisation sous la même borne (lot L4, 27/10/2026). Ce n'est plus un
     * motif de refus à la saisie : au-delà, l'image est RÉDUITE jusqu'à cette
     * borne (`RecuDepenseService::preparer`, PO, 28/10/2026).
     */
    public const RECU_MAX_KO = RecuDepenseService::TAILLE_MAX_KO;

    // --- Filtres (maître l.58-64) ----------------------------------------

    #[Url(as: 'q')]
    public string $recherche = '';

    #[Url(as: 'du')]
    public string $du = '';

    #[Url(as: 'au')]
    public string $au = '';

    #[Url(as: 'tresorerie')]
    public string $tresorerie = '';

    #[Url(as: 'famille')]
    public string $famille = '';

    // --- Modale de saisie (maître l.104-161) -----------------------------

    /**
     * La forme d'une ligne vierge — un seul endroit.
     *
     * Les clés sont celles que `DepenseService::enregistrer()` attend
     * (`compte_charge`, `montant`, `libelle`) : les renommer ici obligerait à
     * traduire à l'enregistrement, et deux vocabulaires finissent par diverger.
     *
     * @var array<string, string>
     */
    private const LIGNE_VIDE = [
        'libelle' => '',
        'compte_charge' => '',
        'nature' => '',
        'montant' => '',
    ];

    public string $dateTransaction = '';

    public string $libelle = '';

    public string $tresorerieCode = '';

    /** Centre de coût explicite de la dépense (RG-12) ; vide = défaut du compte. */
    public string $centreId = '';

    /** Centre de coût du geste « Comptabiliser » (RG-12) — obligatoire, jamais déduit. */
    public string $centreRattrapage = '';

    // La propriete `nature` de tete est PURGEE (03/09/2026) : la categorie
    // vit sur chaque ligne (`lignes.*.nature`), voir enregistrerDepense().

    /**
     * Les lignes d'achat de la dépense — décision du Product Owner du
     * 31/08/2026 (voir l'entête).
     *
     * ⚠ C'est une propriété Livewire : le navigateur peut en poster n'importe
     * quoi, y compris des clés absentes ou des valeurs non numériques. Rien ici
     * ne présume de son contenu — `totalDesLignes()` ignore ce qui n'est pas un
     * nombre, et l'enregistrement ne lit que ce que la validation a rendu.
     *
     * @var array<int, array<string, string>>
     */
    public array $lignes = [];

    /** @var mixed Fichier téléversé — `Livewire\Features\SupportFileUploads`. */
    public $photoRecu = null;

    // --- Export ----------------------------------------------------------

    public string $formatExport = 'pdf';

    /**
     * Le registre FERMÉ des formulaires de l'écran.
     *
     * @return array<string, list<string>>
     */
    protected function formulaires(): array
    {
        return [
            'depense' => ['dateTransaction', 'libelle', 'tresorerieCode', 'centreId', 'photoRecu', 'lignes'],
            'export' => ['formatExport'],
        ];
    }

    /**
     * Les refus de validation, en clair et par LIGNE.
     *
     * `:position` est le remplacement de Laravel pour une règle à joker : il
     * rend le rang HUMAIN de la ligne (1 pour `lignes.0`). Sans lui, le message
     * porterait « lignes.2.montant », qui ne désigne rien pour un opérateur et
     * lui ferait compter les lignes à partir de zéro.
     *
     * @return array<string, string>
     */
    public function messages(): array
    {
        return [
            'lignes.required' => __('depenses_pwa.lignes_requises'),
            'lignes.array' => __('depenses_pwa.lignes_requises'),
            'lignes.min' => __('depenses_pwa.lignes_requises'),
            'lignes.*.libelle.required' => __('depenses_pwa.ligne_libelle_requis'),
            'lignes.*.libelle.max' => __('depenses_pwa.ligne_libelle_long'),
            'lignes.*.compte_charge.required' => __('depenses_pwa.ligne_compte_requis'),
            'lignes.*.compte_charge.exists' => __('depenses_pwa.ligne_compte_inconnu'),
            'lignes.*.montant.required' => __('depenses_pwa.ligne_montant_requis'),
            'lignes.*.montant.numeric' => __('depenses_pwa.ligne_montant_requis'),
            'lignes.*.montant.min' => __('depenses_pwa.ligne_montant_positif'),
        ];
    }

    public function mount(): void
    {
        $this->dateTransaction = now()->toDateString();
    }

    // =====================================================================
    // EF-M10-02 — la saisie, et sa garde
    // =====================================================================

    /**
     * Ouvre la modale « Nouvelle Dépense ».
     *
     * Le droit est exigé par `ouvrirFormulaire()` AVANT toute lecture :
     * présenter un formulaire à quelqu'un qui ne pourra pas le soumettre lui
     * fait perdre sa saisie et ne lui apprend rien.
     */
    public function ouvrirFormulaireDepense(): void
    {
        $this->ouvrirFormulaire('depense');

        // La date du jour par défaut, comme le maître (`depenses.js` l.196) :
        // c'est le cas courant, et une date vide ferait ressaisir la même
        // valeur vingt fois par semaine.
        $this->dateTransaction = now()->toDateString();

        // UNE ligne vierge, jamais zéro. `ouvrirFormulaire()` remet `lignes` à
        // sa valeur déclarée — le tableau vide —, et une modale ouverte sans
        // aucune ligne n'offrirait rien à remplir : il faudrait cliquer
        // « Ajouter une ligne » pour commencer à saisir une dépense, ce que
        // personne ne devine.
        $this->lignes = [self::LIGNE_VIDE];
    }

    /**
     * Ajoute une ligne d'achat vierge à la dépense en cours de saisie.
     *
     * ⚠ Cette méthode ne persiste rien — elle ne touche que l'état du
     * formulaire — et elle exige pourtant le droit d'écriture. C'est le motif
     * de la maison, et il a une raison : une méthode publique de composant est
     * atteignable par la route Livewire, et le jour où l'une d'elles écrira
     * réellement, la garde sera déjà en place plutôt qu'à ajouter. Le coût est
     * nul, l'oubli ne l'est pas.
     */
    public function ajouterLigneDepense(): void
    {
        $this->exigerEcriture(self::MODULE);

        $this->lignes[] = self::LIGNE_VIDE;
    }

    /**
     * Retire une ligne d'achat AVANT enregistrement — rien n'est supprimé en
     * base, puisque rien n'y est encore écrit.
     *
     * ⚠ Ce n'est PAS le « D » de CRUD, qui n'existe nulle part dans ce dépôt :
     * une dépense enregistrée ne se corrige que par contre-passation (RG-11).
     * Ici, la dépense n'existe pas encore ; retirer une ligne du formulaire est
     * l'équivalent d'effacer une saisie.
     *
     * La DERNIÈRE ligne ne part jamais : une dépense sans ligne n'existe pas —
     * `DepenseService::enregistrer()` la refuse par `depenses.sans_ligne` —, et
     * un formulaire vidé n'aurait plus rien à quoi rattacher un compte de
     * charge. La vue ne rend pas le bouton dans ce cas ; ce refus est la
     * seconde moitié de la même règle, celle qui tient quand l'appel vient du
     * navigateur.
     */
    public function retirerLigneDepense(int $index): void
    {
        $this->exigerEcriture(self::MODULE);

        if (count($this->lignes) <= 1) {
            return;
        }

        unset($this->lignes[$index]);
        $this->lignes = array_values($this->lignes);

        // Les erreurs sont indexées (`lignes.2.montant`) : après un retrait,
        // les rangs ont glissé et chaque message désignerait la ligne voisine.
        // Les effacer vaut mieux que de les faire mentir.
        $this->resetValidation();
    }

    /**
     * Enregistre la dépense ET sa pièce comptable, par le Service de domaine.
     *
     * Aucune règle comptable n'est écrite ici : le service pose la
     * contrepartie de trésorerie, passe la pièce et la valide dans la même
     * transaction. Si elle est refusée, RIEN n'est écrit — et le refus
     * s'affiche, il ne se range pas dans une colonne que personne ne lit.
     */
    public function enregistrerDepense(DepenseService $depenses): void
    {
        $valide = $this->validerEcriture([
            'dateTransaction' => ['required', 'date'],
            'libelle' => ['required', 'string', 'max:255'],
            'tresorerieCode' => ['required', 'string', 'in:'.implode(',', array_keys(self::TRESORERIES))],
            'centreId' => ['nullable', 'string', 'exists:centres_cout,id'],
            // La CATEGORIE vit sur CHAQUE ligne depuis le 03/09/2026
            // (directive PO : « plusieurs categories pour une meme
            // depense ») : le schema etait deja par-ligne
            // (`lignes_depense.nature`), seule la modale imposait une
            // categorie unique recopiee partout. Un marche du matin melange
            // Tomate, Viande et Transport — trois lignes, trois categories,
            // une seule piece.
            'lignes.*.nature' => ['required', 'string', 'in:'.implode(',', $this->naturesProposables())],
            // Pas de `max` : une image trop lourde est RÉDUITE (jusqu'à 400 Ko)
            // par `RecuDepenseService::preparer`, jamais refusée pour son poids
            // (PO, 28/10/2026). Reste refusé : ce qui n'est pas une image.
            'photoRecu' => ['nullable', 'image'],

            // La ventilation, LIGNE PAR LIGNE. Le joker fait porter le refus
            // sur `lignes.2.montant` et non sur le formulaire en bloc : une
            // dépense à six lignes dont une est vide doit dire LAQUELLE, sans
            // quoi l'opérateur relit les six.
            //
            // `min:1` sur le montant, jamais `numeric` seul : une ligne saisie
            // à zéro — ou laissée vide et postée comme `0` par le navigateur —
            // ne doit jamais devenir une ligne enregistrée. Elle produirait au
            // grand livre un débit nul sur un compte de charge, c'est-à-dire
            // une imputation qui affirme un achat sans argent.
            'lignes' => ['required', 'array', 'min:1'],
            'lignes.*.libelle' => ['required', 'string', 'max:255'],
            'lignes.*.compte_charge' => ['required', 'string', 'exists:plan_comptable,numero_compte'],
            'lignes.*.montant' => ['required', 'numeric', 'min:1'],
        ]);

        $recu = null;
        $empreinte = [];

        if ($this->photoRecu !== null) {
            // Le fichier est PRÉPARÉ avant d'être rangé : gardé tel quel s'il
            // tient en 400 Ko, réduit en JPEG sinon, refusé s'il est illisible.
            // L'empreinte, la taille et le type sont ceux du fichier RANGÉ (lot
            // L4) : ce sont elles que les autres postes reçoivent pour vérifier
            // ce qu'ils téléchargent — relues de ce qu'on écrit, jamais supposées.
            try {
                $prepare = app(RecuDepenseService::class)->preparer((string) $this->photoRecu->get());
            } catch (RefusRecuDepense $refus) {
                $this->addError('photoRecu', $refus->getMessage());

                return;
            }

            $chemin = RecuDepenseService::DOSSIER.'/'.Str::uuid()->toString().'.'.$prepare['extension'];
            Storage::disk('public')->put($chemin, $prepare['octets']);
            $recu = $chemin;
            $empreinte = [
                'recu_sha256' => $prepare['sha256'],
                'recu_taille' => strlen($prepare['octets']),
                'recu_type' => $prepare['type'],
            ];
        }

        $libelleDepense = trim((string) $valide['libelle']);

        // La nature et la famille sont celles de CHAQUE LIGNE (PO
        // 03/09/2026) : les indicateurs « Marché » et « Services » du maître
        // somment les lignes, et une dépense mêlée compte désormais chaque
        // ligne dans SA famille — plus une recopie de tête qui rangeait le
        // transport du marché en « denrées ».
        $lignes = [];

        foreach ($valide['lignes'] as $ligne) {
            $ligne = (array) $ligne;
            $natureLigne = (string) $ligne['nature'];

            $lignes[] = [
                'compte_charge' => (string) $ligne['compte_charge'],
                // Les montants restent des CHAÎNES de bout en bout : `bcadd`
                // les relit, et un flottant intermédiaire décalerait le total
                // d'une dépense à dix lignes.
                'montant' => (string) $ligne['montant'],
                'libelle' => trim((string) $ligne['libelle']),
                'nature' => $natureLigne,
                'famille' => $this->familleDeLaNature($natureLigne),
            ];
        }

        try {
            // UN SEUL appel, avec la liste COMPLÈTE — jamais une dépense par
            // ligne. Le service passe la pièce et les lignes dans la MÊME
            // transaction : une pièce refusée n'écrit rien du tout. Boucler ici
            // produirait N dépenses, N pièces, et laisserait la moitié d'un
            // marché du matin comptabilisée si la sixième était refusée.
            //
            // Aucun total n'est envoyé : `DepenseService::totaliser()` le
            // recalcule, et c'est lui qui fait foi.
            $depense = $depenses->enregistrer([
                'date_transaction' => (string) $valide['dateTransaction'],
                'tresorerie' => (string) $valide['tresorerieCode'],
                'centre_id' => ($valide['centreId'] ?? '') !== '' ? (string) $valide['centreId'] : null,
                'libelle' => $libelleDepense,
                'recu_path' => $recu,
                ...$empreinte,
                'lignes' => $lignes,
            ], Auth::user());
        } catch (RuntimeException $refus) {
            // PAS un `catch` avalant : le refus est NOMMÉ à l'écran, la modale
            // reste ouverte avec la saisie, et rien n'a été écrit en base.
            // Seul `RuntimeException` est repris — c'est le type que
            // `DepenseService` et `PasserEcritureService` emploient pour leurs
            // refus, tous rendus par `__()`. Une erreur PDO, elle, repart
            // telle quelle : la montrer ferait fuir du SQL à l'écran.
            //
            // La clé est `comptabilisation`, pas un champ de saisie : un refus
            // de pièce porte sur la dépense ENTIÈRE — journal, exercice, compte,
            // centre de coût —, jamais sur une ligne en particulier. L'accrocher
            // au montant d'une ligne ferait chercher l'erreur dans ce montant.
            $this->addError('comptabilisation', $refus->getMessage());

            return;
        }

        $this->terminerFormulaire(__('depenses_pwa.enregistree', [
            'montant' => MontantFcfa::format((string) $depense->montant_total),
        ]));
    }

    /**
     * Rattrapage : passe la pièce d'une dépense qui n'en a pas.
     *
     * Le geste est EXPLICITE, jamais automatique. Les dépenses antérieures à
     * ce lot n'ont aucune écriture — elles manquent au grand livre, et rien
     * dans le prototype ne permettait de les reprendre : il affichait le
     * défaut sans offrir de le corriger.
     */
    public function comptabiliserDepense(string $depense, DepenseService $depenses): void
    {
        $this->exigerEcriture(self::MODULE);

        $piece = Depense::query()->find($depense);

        if ($piece === null) {
            // Un identifiant inconnu est une erreur d'appel du composant, pas
            // une saisie : il ne mérite pas mieux qu'un refus muet.
            return;
        }

        try {
            $depenses->comptabiliser($piece, $this->centreRattrapage);
        } catch (RuntimeException $refus) {
            $this->addError('rattrapage', $refus->getMessage());

            return;
        }

        session()->flash('pwa-succes', __('depenses_pwa.rattrapage_fait', [
            'numero' => (string) $piece->numero,
        ]));
    }

    // =====================================================================
    // Export — PA-119 : ce qui est AFFICHÉ, et il DIT son filtre
    // =====================================================================

    /**
     * Ouvre la modale d'export, sur le format du bouton cliqué.
     *
     * Le maître pose DEUX boutons (« Export PDF », « Export Excel », l.66-67)
     * et n'a pas de modale ; la PWA en a une, unique et partagée. Le format
     * est donc pré-sélectionné par le bouton : sans cela, cliquer « Export
     * Excel » ouvrirait une modale positionnée sur PDF.
     */
    public function ouvrirExport(string $format = 'pdf'): void
    {
        $this->ouvrirFormulaire('export');
        $this->formatExport = $format === 'excel' ? 'excel' : 'pdf';
    }

    public function fermerModales(): void
    {
        $this->exigerEcriture(self::MODULE);
        $this->etatFormulaire = null;
    }

    /**
     * Produit le document sur la liste FILTRÉE, jamais sur le registre entier.
     *
     * Une liste vide se REFUSE : une page blanche ne dirait pas si le filtre
     * est trop étroit ou si la donnée n'existe pas (PA-119).
     */
    public function genererExport(): ?Response
    {
        $utilisateur = $this->exigerEcriture(self::MODULE);

        $lignes = $this->requete()->get();

        if ($lignes->isEmpty()) {
            $this->addError('formatExport', __('depenses_pwa.export_vide'));

            return null;
        }

        $this->etatFormulaire = null;
        $nom = __('depenses_pwa.export_fichier').'_'.now()->format('Y_m_d_His');

        if ($this->formatExport === 'excel') {
            /** @var Response $reponse */
            $reponse = Excel::download(new DepensesExport($lignes, $this->descriptionDuFiltre()), $nom.'.xlsx');

            return $reponse;
        }

        $pdf = Pdf::loadView('pdf.depenses-rapport', [
            'entete' => $this->enTeteRapport(__('depenses_pwa.export_document'), $this->descriptionDuFiltre()),
            'depenses' => $lignes,
            'total' => $this->totalDe($lignes),
            'libellesComptes' => $this->libellesComptes(),
            'filtre' => $this->descriptionDuFiltre(),
            'auteur' => $utilisateur->login,
        ])->setPaper('a4', 'landscape');

        return response()->streamDownload(static function () use ($pdf): void {
            echo $pdf->output();
        }, $nom.'.pdf');
    }

    // =====================================================================

    public function render(): View
    {
        $depenses = $this->requete()->get();

        return view('pwa.depenses.depenses', array_merge($this->socle(), [
            'depenses' => $depenses,
            'comptesDeCharge' => app(PlanComptableService::class)->comptesDeCharge(),
            'centresDeCout' => \App\Domain\Comptabilite\Models\CentreCout::query()->orderBy('libelle')->get(['id', 'libelle']),
            'libellesComptes' => $this->libellesComptes(),
            'naturesProposables' => self::NATURES,
            'total' => $this->totalDe($depenses),
            'moyenne' => $depenses->isEmpty() ? null : bcdiv($this->totalDe($depenses), (string) $depenses->count(), 2),
            'marche' => $this->totalParFamille($depenses, 'Marché'),
            'services' => $this->totalParFamille($depenses, 'Services'),
            // ⚠ `decaisseEnCaisse`, PAS `caisse` — renomme le 31/08/2026.
            // La cle `caisse` MASQUAIT le tableau homonyme que le socle
            // (`PageMetier` → `IndicateurCaisse`) fournit a la coquille :
            // `barre-superieure.blade.php` recevait une CHAINE de montant la
            // ou elle attend un tableau d'etat, et /pwa/depenses levait
            // « Cannot access offset of type string on string » — un 500
            // ne au raccord de deux variables justes chacune de son cote,
            // comme le <title> avant lui. Les cles du socle sont reservees.
            'decaisseEnCaisse' => $this->totalParTresorerie($depenses, 'caisse'),
            'sansEcriture' => $depenses->filter(static fn (Depense $d): bool => ! $d->estComptabilisee())->count(),
            'filtreApplique' => $this->filtreApplique(),

            // Le total de la SAISIE en cours, recalculé à chaque rendu — donc à
            // chaque frappe, les montants étant liés en `wire:model.live`. Il
            // est rendu en lecture seule et n'est jamais posté (règle n° 2 du
            // dépôt : toute valeur calculable est affichée, jamais saisie).
            'totalSaisi' => $this->totalDesLignes(),
        ]))->layout('layouts.pwa', ['module' => self::MODULE]);
    }

    // ------------------------------------------------------------ lectures

    /**
     * La requête filtrée — bâtie par le Service, affinée ici.
     *
     * `DepenseService::filtrer()` porte les quatre filtres du maître qui
     * touchent la table des dépenses. Le cinquième, la famille, vit sur les
     * LIGNES : il s'ajoute ici sur le `Builder` rendu plutôt que d'être
     * réécrit dans le domaine, qui est hors du périmètre de ce lot. Ce n'est
     * pas une seconde règle métier — c'est un prédicat de lecture.
     *
     * @return Builder<Depense>
     */
    private function requete(): Builder
    {
        $famille = $this->famille;
        // Sélecteur d'exercice global (PO, 20/10/2026) : la liste porte sur
        // l'exercice CONSULTÉ ; « du / au » l'affinent sans en sortir.
        [$du, $au] = ExerciceConsulte::datesDansLExercice($this->du, $this->au);

        return app(DepenseService::class)
            ->filtrer([
                'recherche' => $this->recherche,
                'du' => $du,
                'au' => $au,
                'tresorerie' => array_key_exists($this->tresorerie, self::TRESORERIES) ? $this->tresorerie : '',
            ])
            ->when(
                array_key_exists($famille, self::NATURES),
                static fn (Builder $q): Builder => $q->whereHas(
                    'lignes',
                    static fn (Builder $l): Builder => $l->where('famille', $famille),
                ),
            );
    }

    /**
     * Les libellés du plan comptable, indexés par numéro.
     *
     * Une seule requête pour tout le tableau : un `CompteComptable::where()`
     * dans la boucle d'affichage ferait une requête par ligne.
     *
     * @return array<string, string>
     */
    private function libellesComptes(): array
    {
        /** @var array<string, string> $libelles */
        $libelles = app(PlanComptableService::class)
            ->comptesDeCharge()
            ->pluck('libelle', 'numero_compte')
            ->all();

        return $libelles;
    }

    /**
     * Le total général de la saisie en cours — somme `bcadd` des lignes.
     *
     * ## Trois décisions, chacune pour un défaut évitable
     *
     * 1. **Sur des CHAÎNES, par `bcadd`**, jamais `array_sum()` : trois lignes
     *    à 0,1 F ne font pas 0,3 F en virgule flottante, et l'écart se verrait
     *    d'abord sur les gros totaux — c'est-à-dire le jour où il coûte.
     * 2. **Une ligne à moitié tapée est IGNORÉE, pas comptée à zéro et pas
     *    fatale.** `bcadd('12x', …)` lève en PHP 8 : sans ce filtre, une frappe
     *    intermédiaire ferait tomber la modale entière pendant la saisie. Ce
     *    total est un AFFICHAGE ; le refus des lignes vides, lui, tombe à
     *    l'enregistrement, où il peut nommer la ligne fautive.
     * 3. **Il ne fait pas foi.** `DepenseService::totaliser()` le recalcule sur
     *    les lignes validées, et c'est ce montant-là qui est écrit. Deux
     *    calculs pour deux usages : celui-ci sert l'œil pendant la saisie,
     *    l'autre sert la pièce comptable. Le navigateur n'en poste aucun.
     */
    private function totalDesLignes(): string
    {
        $total = '0.00';

        foreach ($this->lignes as $ligne) {
            $saisi = trim((string) ($ligne['montant'] ?? ''));

            // `is_numeric` couvre AUSSI la chaîne vide, qui n'en est pas un :
            // un `=== ''` de plus serait redondant, et il serait signalé par
            // `MotifsInterditsPwaTest` — la garde ne lit que le NOM de la
            // variable, pas ce qu'on en fait, et c'est ce qui la rend fiable.
            if (! is_numeric($saisi)) {
                continue;
            }

            $total = bcadd($total, bcadd($saisi, '0', 2), 2);
        }

        return $total;
    }

    /**
     * @param  EloquentCollection<int, Depense>  $depenses
     */
    private function totalDe(EloquentCollection $depenses): string
    {
        // La formule vit dans `DepenseService` depuis le 02/09/2026 : la
        // carte « Dépense courante » de l'accueil lit la même (PA-121).
        return DepenseService::totalDecaisse($depenses);
    }

    /**
     * @param  EloquentCollection<int, Depense>  $depenses
     */
    private function totalParFamille(EloquentCollection $depenses, string $famille): string
    {
        // Même extraction que `totalDe()` (02/09/2026, PA-121).
        return DepenseService::totalParFamille($depenses, $famille);
    }

    /**
     * @param  EloquentCollection<int, Depense>  $depenses
     */
    private function totalParTresorerie(EloquentCollection $depenses, string $tresorerie): string
    {
        $total = '0.00';

        foreach ($depenses as $depense) {
            if ($depense->tresorerie === $tresorerie) {
                $total = bcadd($total, (string) $depense->montant_total, 2);
            }
        }

        return $total;
    }

    /** @return list<string> */
    private function naturesProposables(): array
    {
        return array_merge(...array_values(self::NATURES));
    }

    private function familleDeLaNature(string $nature): string
    {
        foreach (self::NATURES as $famille => $natures) {
            if (in_array($nature, $natures, true)) {
                return $famille;
            }
        }

        // Inatteignable tant que la validation `in:` tient : la nature vient
        // d'un registre fermé. Le dire vaut mieux que de classer au hasard une
        // dépense dans « Services », ce qui fausserait deux indicateurs.
        throw new RuntimeException(__('depenses.famille_par_defaut'));
    }

    private function filtreApplique(): bool
    {
        return $this->recherche !== '' || $this->du !== '' || $this->au !== ''
            || $this->tresorerie !== '' || $this->famille !== '';
    }

    /**
     * Le filtre en toutes lettres — il PART avec le document (PA-119).
     *
     * Quelqu'un qui filtre puis exporte attend son filtre ; lui rendre le
     * registre entier lui ferait envoyer au comptable un document qu'il croit
     * avoir vérifié. Et un document qui ne dit pas son périmètre se lit comme
     * s'il portait tout.
     */
    private function descriptionDuFiltre(): string
    {
        $morceaux = [];
        $portee = ExerciceConsulte::libelle();
        if ($portee !== '') {
            $morceaux[] = $portee;
        }

        if ($this->recherche !== '') {
            $morceaux[] = __('depenses_pwa.filtre_recherche', ['terme' => $this->recherche]);
        }

        if ($this->du !== '') {
            $morceaux[] = __('depenses_pwa.filtre_du', ['date' => $this->du]);
        }

        if ($this->au !== '') {
            $morceaux[] = __('depenses_pwa.filtre_au', ['date' => $this->au]);
        }

        if (array_key_exists($this->tresorerie, self::TRESORERIES)) {
            $morceaux[] = __('depenses_pwa.filtre_tresorerie', ['libelle' => self::TRESORERIES[$this->tresorerie]]);
        }

        if (array_key_exists($this->famille, self::NATURES)) {
            $morceaux[] = __('depenses_pwa.filtre_famille', ['libelle' => $this->famille]);
        }

        return $morceaux === []
            ? __('depenses_pwa.filtre_tout')
            : implode(' · ', $morceaux);
    }

    /**
     * Les natures et les comptes d'une dépense, en clair.
     *
     * Le maître n'affiche qu'UNE nature et UN compte par ligne, parce que sa
     * saisie n'en produit qu'un. Le modèle, lui, admet plusieurs lignes : une
     * dépense qui en porte plusieurs rend ses valeurs distinctes dans la même
     * cellule, plutôt qu'en taire silencieusement toutes sauf une.
     *
     * @param  Collection<int, LigneDepense>  $lignes
     */
    public static function valeursDistinctes(Collection $lignes, string $colonne): string
    {
        $valeurs = $lignes->pluck($colonne)->filter()->unique()->values();

        return $valeurs->isEmpty() ? MontantFcfa::TIRET : $valeurs->implode(', ');
    }
}
