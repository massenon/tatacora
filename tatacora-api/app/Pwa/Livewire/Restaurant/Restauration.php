<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Restaurant;

use App\Domain\Carte\Models\IndisponibiliteCarte;
use App\Domain\Carte\Services\DisponibiliteCarteService;
use App\Domain\Restaurant\Models\Menu;
use App\Domain\Restaurant\Models\Plat;
use App\Domain\Restaurant\Models\Recette;
use App\Domain\Restaurant\Services\CartePlatMenuService;
use App\Domain\Restaurant\Services\CompositionRecetteService;
use App\Domain\Restaurant\Services\ReferentielRecetteService;
use App\Domain\Stocks\Models\Article;
use App\Pwa\Livewire\Concerns\FormulaireModal;
use App\Pwa\Livewire\PageMetier;
use App\Pwa\Support\MontantFcfa;
use Illuminate\Support\Facades\DB;
use Illuminate\View\View;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Title;
use Livewire\Attributes\Url;
use RuntimeException;

/**
 * Catalogue des plats — « Restaurant & Cuisine » (M4).
 *
 * Maître : `prototype_v2/pages/m4-restauration.html`.
 *
 * ## Deux défauts bloquants fermés ici
 *
 * 1. **`supprimerPlat()` faisait `$plat->delete()`**, derrière un
 *    `wire:confirm="Supprimer ce plat ?"` — la boîte grise du navigateur, hors
 *    charte, sans nom d'élément ni explication. Le « D » de CRUD n'existe
 *    nulle part dans ce dépôt, et `lignes_commande_restaurant` référence
 *    `plats` en `restrictOnDelete` : la ligne de commande serait devenue
 *    illisible, ou la suppression aurait échoué sur une erreur SQL.
 * 2. **Aucun contrôle RBAC d'écriture.** Un rôle sans droit M4 créait,
 *    modifiait et supprimait des plats depuis son navigateur.
 *
 * ## Archiver un plat, c'est LE RETIRER DE LA CARTE
 *
 * `plats` ne porte aucune colonne d'archivage ni de statut (relevé
 * `SHOW COLUMNS FROM plats` du 31/08/2026 : quatorze colonnes, aucune). Le
 * geste métier équivalent existe, et il est du maître : le motif `retire`
 * d'`IndisponibiliteCarte`, « décision commerciale », qui se lève depuis la
 * carte du restaurant. Rien n'est effacé, tout est restaurable — exactement ce
 * que promet la modale d'archivage partagée.
 *
 * ## Le formulaire EXIGE un menu et une recette, parce que le schéma les exige
 *
 * `plats.menu_id` et `plats.recette_id` sont tous deux NOT NULL. Le formulaire
 * livré proposait « Aucune fiche technique » et fabriquait un menu par
 * `Menu::firstOrCreate()` depuis la catégorie : le premier aurait fait échouer
 * l'insertion, le second inventait une carte que personne n'avait demandée.
 * Les deux sont désormais de vraies clés étrangères choisies dans une liste.
 *
 * ## …ET C'ÉTAIT UNE IMPASSE, jusqu'au 03/09/2026
 *
 * Deux vraies clés étrangères obligatoires, et AUCUN écran de la PWA ne créait
 * ni menu ni recette : `CartePlatMenuService::creerMenu()` et
 * `ReferentielRecetteService::creer()` n'avaient qu'un appelant chacun, leur
 * contrôleur d'API. Sur une base neuve — celle d'une mise en service — le
 * formulaire « Nouveau plat » présentait donc deux sélecteurs VIDES, sans dire
 * pourquoi ni où aller. Constat du Product Owner ; même racine que PA-128 :
 * une donnée que rien n'écrit est une donnée absente, et un écran qui la
 * demande sans offrir le geste qui la crée est un cul-de-sac.
 *
 * Les deux gestes sont désormais rendus ici, par leur Service de domaine, dans
 * deux modales secondaires — atteignables depuis l'en-tête de la page ET
 * depuis le formulaire de plat, à l'endroit exact du champ qui les exige. Le
 * retour au formulaire de plat conserve la saisie et PRÉ-SÉLECTIONNE ce qui
 * vient d'être créé : faire retaper le plat serait punir l'utilisateur d'avoir
 * suivi le seul chemin possible.
 *
 * ## La composition d'une recette ferme le textarea de PA-23
 *
 * Le maître porte « Ingrédients principaux » en TEXTE LIBRE
 * (`m4-restauration.html`, `champsFormulaire`). Porté tel quel, aucune
 * décrémentation de stock n'est possible et la fiche technique ne sert à rien
 * (PA-23, `SPEC_ECRAN_M4_RESTAURANT.md` §6). Le sous-formulaire livré ici est
 * celui que PA-23 réclame : de vraies clés étrangères vers `articles`, avec
 * leurs quantités, écrites par `CompositionRecetteService`.
 *
 * ⚠ Le COÛT MATIÈRE n'est PAS un champ. Il se calcule depuis les lignes et le
 * coût moyen pondéré de chaque article (M6) — le saisir le ferait diverger de
 * sa composition dès le premier ingrédient ajouté. Il est annoncé après
 * l'enregistrement, dans ses TROIS états (`CoutMatiere`) : un montant, un coût
 * incomplet qui NOMME les articles non valorisés, ou une composition vide. Un
 * « 0 F » à la place des deux derniers serait PA-126 sur l'écran même où l'on
 * fixe un prix de vente.
 *
 * ## …ET LA CRÉATION SEULE NE DÉBLOQUAIT RIEN (04/09/2026)
 *
 * Constat du Product Owner : **aucune vente n'était possible au POS
 * restaurant.** Relevé en base de développement — 83 plats, 83 recettes,
 * **3 lignes d'`ingredients_recette` en tout**. Chaque plat avait donc bien
 * une fiche technique, et elle était VIDE ; or une fiche vide n'est pas une
 * fiche qui ne consomme rien, c'est une vente REFUSÉE :
 * `DeductionStockCuisineService` lève `RecetteManquanteException` sur une
 * nomenclature vide, précisément pour qu'un plat ne se vende jamais sans
 * décrémenter quoi que ce soit.
 *
 * Le geste manquant n'était pas la création — livrée le 03/09/2026 — mais la
 * **composition d'une fiche EXISTANTE** : il n'y avait pas
 * d'`ouvrirModificationRecette()`, et les 83 fiches vides étaient donc
 * inatteignables depuis la PWA. Même forme que PA-128 et PA-129 : une donnée
 * que rien n'écrit est une donnée absente, à ceci près qu'ici la donnée
 * existait à moitié — l'entête sans son contenu — ce qui la rendait invisible
 * à tout compte de couverture fondé sur `recettes`.
 *
 * L'écran porte donc trois onglets (ajout au maître, déclaré dans la vue) :
 * le catalogue des plats, les **fiches techniques** et les **menus**. Le
 * second liste les 83 fiches avec leur nombre d'ingrédients, leur coût matière
 * et leur ÉTAT — « composée » ou « vide, ne décrémente rien » —, et porte le
 * filtre qui isole les vides : à 83 lignes, les retrouver à l'œil est
 * impraticable.
 *
 * ## Le référentiel POSE des compositions, et il le DIT
 *
 * La première version de ce lot refusait de semer quoi que ce soit : « un
 * grammage inventé décrémenterait un stock réel ». Le Product Owner a tranché
 * l'inverse le jour même — débloquer le service d'abord, « on pourra modifier
 * ». C'est mot pour mot la décision de PA-161 (b) sur les prix (« mets des
 * prix, on le modifiera après »), et elle appelle la même protection, pas un
 * blanc-seing : `recettes.composition_provisoire` marque les 82 fiches semées
 * par `RestaurantSeeder`, l'onglet et le point de vente l'affichent, et la
 * marque TOMBE d'elle-même dès que le cuisinier enregistre la composition
 * (`CompositionRecetteService`, unique auteur). Sans elle, une quantité
 * devinée et une quantité pesée seraient indiscernables, et l'écart ne se
 * verrait qu'à l'inventaire — imputé à une perte physique qui n'a pas eu lieu.
 *
 * ⚠ Le refus subsiste sur un point : aucune quantité n'est posée sous 0,005.
 * `mouvements_stock.quantite` étant un `DECIMAL(10,2)` (PA-38), une ligne plus
 * fine serait arrondie à zéro — elle figurerait à la fiche sans rien
 * décrémenter, ce que la fiche existe précisément pour empêcher.
 *
 * @see EF-M4-01 Gestion des menus et cartes
 * @see EF-M4-02 Fiches techniques (recettes)
 * @see RG-02 Aucune suppression physique — la correction est un geste métier
 * @see RG-05 Sortie de stock automatique — c'est la composition qui la rend possible
 * @see LARAVEL_PWA.md §3, §5
 * @see DIRECTIVE_CONFORMITE_100.md Articles 3.3, 4.6
 */
#[Layout('layouts.pwa')]
#[Title('Restaurant & Cuisine — LogiReStock — TATACORA AFRIQUE')]
class Restauration extends PageMetier
{
    use FormulaireModal;

    /** Le module RBAC de l'écran — `data-module="M4"` au maître. */
    public const MODULE = 'M4';

    /**
     * Les statuts de commande qui ENGAGENT un plat.
     *
     * `servie` et `cloturee` n'engagent plus rien : le plat est parti en
     * salle, le retirer de la carte du jour ne rend aucune ligne illisible.
     * `annulee` non plus. Les inclure interdirait de retirer de la carte tout
     * plat jamais commandé — c'est-à-dire les plats populaires, exactement
     * ceux qu'une rupture concerne.
     *
     * @var list<string>
     */
    public const STATUTS_ENGAGEANTS = ['en_preparation', 'transmise_cuisine'];

    /**
     * Une ligne de composition vierge — écrite UNE fois.
     *
     * Aucune quantité par défaut : « 1 » serait un chiffre inventé sur une
     * donnée de stock, validé sans être relu (même raison que l'absence de
     * prix par défaut sur le formulaire de plat).
     *
     * @var array<string, string>
     */
    private const LIGNE_INGREDIENT_VIDE = ['article_id' => '', 'quantite_unitaire' => ''];

    /**
     * Le registre FERMÉ des onglets — ajout au maître (04/09/2026).
     *
     * `m4-restauration.html` n'a AUCUN onglet : son corps entier est délégué
     * au moteur CRUD générique, qui rend un tableau et rien d'autre. Les deux
     * onglets ajoutés portent les deux référentiels que ce tableau exige sans
     * les offrir — `plats.recette_id` et `plats.menu_id` sont NOT NULL — et
     * dont l'absence de composition bloquait la vente au comptoir.
     *
     * Un onglet hors registre retombe sur `plats` : une valeur forcée depuis
     * le navigateur ne doit pas rendre une page vide sans rien dire.
     *
     * @var list<string>
     */
    public const ONGLETS = ['plats', 'fiches', 'menus'];

    #[Url(as: 'onglet')]
    public string $onglet = 'plats';

    #[Url(as: 'q')]
    public string $recherche = '';

    #[Url(as: 'categorie')]
    public string $categorie = '';

    // ---- Filtres de l'onglet « Fiches techniques » (04/09/2026) ---------

    /**
     * Recherche par libellé de fiche — sa PROPRE clé d'URL.
     *
     * Partager `q` avec le catalogue ferait qu'un terme tapé sur un onglet
     * viderait l'autre sans que rien ne le montre (même raison qu'à
     * `EcranDeCarte`, onglet « Ventes du rayon »).
     */
    #[Url(as: 'qf')]
    public string $rechercheFiche = '';

    /**
     * « Fiches vides seulement » — LE filtre qui rend le blocage visible.
     *
     * Avec 83 fiches dont l'immense majorité est vide, les repérer à l'œil sur
     * neuf pages est impraticable : c'est exactement la situation où l'on
     * conclut que « l'écran ne marche pas » plutôt que « la donnée manque ».
     */
    #[Url(as: 'vides')]
    public bool $videsSeulement = false;

    /**
     * 10 lignes par page — la valeur du moteur du maitre (`crud-engine.js`
     * l.21). Meme mecanisme que `Achats` : propriete `#[Url]` passee en
     * quatrieme argument de `paginate()`, jamais `WithPagination` (PA-67).
     */
    public const PAR_PAGE = 10;

    #[Url(as: 'page')]
    public int $pageCourante = 1;

    /**
     * La SELECTION du tableau — identifiants coches (`crud-engine.js`
     * `.case-ligne`). Ses deux consommateurs du maitre sont nommes : l'export
     * de selection n'existe pas encore sur cet ecran (aucun export M4 n'est
     * porte), la suppression groupee est interdite partout (RG-02, Article 6).
     * La case reste le contrat du tableau generique, et le compteur
     * « N selectionne(s) » rend la selection visible.
     *
     * @var list<string>
     */
    public array $selection = [];

    /** La case d'entete du maitre (`crud-ui.js` l.66, `#crud-case-tout`). */
    public bool $toutSelectionne = false;

    public function updatedToutSelectionne(bool $valeur): void
    {
        $this->selection = $valeur
            ? $this->requetePlats()->pluck('id')->map(static fn ($id): string => (string) $id)->all()
            : [];
    }

    /**
     * Un filtre qui change remet la selection ET la page a leur depart
     * (meme raison que `Achats` : une selection survivante serait invisible).
     *
     * ⚠ `onglet` en fait partie depuis le 04/09/2026, et c'est indispensable :
     * les deux onglets se partagent `pageCourante` (le motif d'`Achats`), et
     * passer aux fiches depuis la page 7 du catalogue afficherait une page qui
     * n'existe pas — un tableau vide sur une liste de 83 lignes.
     *
     * @param  mixed  $valeur
     */
    public function updated(string $propriete, $valeur): void
    {
        if (in_array($propriete, ['recherche', 'categorie', 'onglet', 'rechercheFiche', 'videsSeulement'], true)) {
            $this->selection = [];
            $this->toutSelectionne = false;
            $this->pageCourante = 1;
        }
    }

    /**
     * L'onglet réellement affiché — jamais la propriété brute.
     *
     * Elle est `#[Url]`, donc écrite depuis la barre d'adresse : `?onglet=x`
     * rendrait une page sans aucun panneau, indiscernable d'un écran cassé.
     */
    protected function ongletValide(): string
    {
        return in_array($this->onglet, self::ONGLETS, true) ? $this->onglet : 'plats';
    }

    // ---- Formulaire de plat ---------------------------------------------

    public ?string $platCibleId = null;

    public string $libelleSaisi = '';

    public string $prixVenteSaisi = '';

    public string $categorieSaisie = 'plats';

    public ?string $menuIdSaisi = null;

    public ?string $recetteIdSaisie = null;

    /**
     * PA-161 (b) — la marque « prix provisoire », une DECISION qui se coche.
     *
     * « Corrige a la main » n'est PAS ici : c'est un FAIT, deduit par
     * `App\Domain\Carte\MarquesDePrix` quand le prix d'un plat marque
     * provisoire change. Le faire cocher reviendrait a demander a quelqu'un de
     * declarer ce qu'il vient de faire, et il l'oublierait.
     */
    public bool $prixProvisoireSaisi = false;

    // ---- Formulaire de menu (03/09/2026) --------------------------------

    /** La carte en cours de modification — `null` : création (04/09/2026). */
    public ?string $menuCibleId = null;

    public string $menuLibelleSaisi = '';

    /** Registre FERMÉ, aligné sur l'`enum` MySQL — voir `Menu::TYPES`. */
    public string $menuTypeSaisi = 'local';

    /**
     * Les dates ENCADRENT la saison, elles ne la déclarent pas.
     *
     * Nullables au schéma : un menu permanent n'en a pas. Chaîne vide plutôt
     * que `null` ici parce qu'un `<input type="date">` rend « » quand il est
     * vide ; la conversion en `null` se fait à l'enregistrement, une fois.
     */
    public string $menuDateDebutSaisie = '';

    public string $menuDateFinSaisie = '';

    // ---- Formulaire de fiche technique (03/09/2026) ---------------------

    /**
     * La fiche en cours de composition — `null` : création (04/09/2026).
     *
     * C'est LA propriété qui manquait : sans elle, le formulaire ne savait que
     * créer, et les 83 fiches vides déjà en base n'avaient aucun chemin.
     */
    public ?string $recetteCibleId = null;

    public string $recetteLibelleSaisi = '';

    /**
     * La composition en cours de saisie — le sous-formulaire de PA-23.
     *
     * De VRAIES clés étrangères vers `articles`, jamais le textarea
     * « Ingrédients principaux » du maître : une chaîne ne se rattache à aucun
     * article, donc ne décrémente aucun stock.
     *
     * ⚠ Le type est `array<string, string>` et NON une forme fermée : c'est une
     * propriété Livewire, donc écrite depuis le navigateur. Lui promettre ses
     * deux clés ferait disparaître les `??` qui les protègent, et un lot forgé
     * sans `article_id` lèverait une erreur PHP au lieu d'un refus lisible.
     *
     * @var list<array<string, string>>
     */
    public array $ingredientsSaisis = [];

    /**
     * Le terme de recherche du sélecteur d'article.
     *
     * Même geste que la modale « Lier au stock » : la PWA n'a pas de composant
     * `SelectRecherche`, le filtre est fait au SERVEUR et le `<select>` ne rend
     * que ce qui reste. ⚠ Les articles DÉJÀ CHOISIS restent proposés quel que
     * soit le terme : les filtrer ferait disparaître de son propre `<select>`
     * une ligne déjà saisie, et l'utilisateur la croirait perdue.
     */
    public string $rechercheArticleIngredient = '';

    /**
     * Vrai quand la modale secondaire a été ouverte DEPUIS le formulaire de
     * plat — la seule chose qui distingue les deux chemins.
     *
     * Sans elle, créer le menu qui manque fermerait le formulaire de plat et
     * jetterait ce qui y était déjà tapé : l'utilisateur serait puni d'avoir
     * suivi le seul chemin que l'écran lui laissait.
     */
    public bool $retourAuPlat = false;

    /**
     * @return array<string, list<string>>
     */
    protected function formulaires(): array
    {
        return [
            'plat' => [
                'platCibleId',
                'libelleSaisi',
                'prixVenteSaisi',
                'categorieSaisie',
                'menuIdSaisi',
                'recetteIdSaisie',
                'prixProvisoireSaisi',
            ],
            'menu' => [
                'menuCibleId',
                'menuLibelleSaisi',
                'menuTypeSaisi',
                'menuDateDebutSaisie',
                'menuDateFinSaisie',
                'retourAuPlat',
            ],
            'recette' => [
                'recetteCibleId',
                'recetteLibelleSaisi',
                'ingredientsSaisis',
                'rechercheArticleIngredient',
                'retourAuPlat',
            ],
            'archivage' => ['platCibleId'],
        ];
    }

    // =====================================================================
    // Écritures
    // =====================================================================

    public function ouvrirCreationPlat(): void
    {
        $this->ouvrirFormulaire('plat');

        // Aucun prix par défaut : « 1500 » était un montant inventé, préposé
        // dans un champ que l'on valide sans le relire.
        $this->categorieSaisie = (string) array_key_first(CarteRestaurant::CATEGORIES);
    }

    public function ouvrirModificationPlat(string $platId): void
    {
        $this->ouvrirFormulaire('plat');

        $plat = Plat::find($platId);

        if (! $plat instanceof Plat) {
            abort(404);
        }

        $this->platCibleId = $plat->id;
        $this->libelleSaisi = (string) $plat->libelle;
        $this->prixVenteSaisi = (string) $plat->prix_vente;
        $this->categorieSaisie = (string) ($plat->categorie ?? array_key_first(CarteRestaurant::CATEGORIES));
        $this->menuIdSaisi = $plat->menu_id;
        $this->recetteIdSaisie = $plat->recette_id;
        $this->prixProvisoireSaisi = $plat->prix_provisoire === true;
    }

    /**
     * Crée ou met à jour le plat — par `CartePlatMenuService`, jamais en direct.
     *
     * Le service contrôle la cohérence du lien direct au stock (les deux
     * colonnes vont ensemble) : écrire `Plat::create()` ici contournerait ce
     * contrôle et rendrait la PWA capable de produire un état que l'API
     * refuse.
     */
    public function enregistrerPlat(): void
    {
        $valide = $this->validerEcriture([
            'libelleSaisi' => ['required', 'string', 'max:255'],
            'prixVenteSaisi' => ['required', 'numeric', 'min:0'],
            'categorieSaisie' => ['required', 'string', 'in:'.implode(',', array_keys(CarteRestaurant::CATEGORIES))],
            // Vraies clés étrangères, jamais du texte libre ni un menu
            // fabriqué à la volée : les deux colonnes sont NOT NULL.
            'menuIdSaisi' => ['required', 'string', 'exists:menus,id'],
            'recetteIdSaisie' => ['required', 'string', 'exists:recettes,id'],
            'prixProvisoireSaisi' => ['boolean'],
        ]);

        $donnees = [
            'libelle' => (string) $valide['libelleSaisi'],
            'prix_vente' => (string) $valide['prixVenteSaisi'],
            'categorie' => (string) $valide['categorieSaisie'],
            'menu_id' => (string) $valide['menuIdSaisi'],
            'recette_id' => (string) $valide['recetteIdSaisie'],
            // ⚠ `prix_corrige_main` n'est PAS soumis, et c'est deliberé :
            // `MarquesDePrix::completer()` ne le deduit que lorsque l'appelant
            // ne l'a pas tranche lui-meme. L'envoyer ici, meme a `false`,
            // desarmerait la deduction a chaque enregistrement.
            'prix_provisoire' => (bool) $valide['prixProvisoireSaisi'],
        ];

        $service = app(CartePlatMenuService::class);

        try {
            if ($this->platCibleId === null) {
                $plat = $service->creerPlat($donnees);
                $message = __('carte_pwa.restauration.cree', ['plat' => $plat->libelle]);
            } else {
                $plat = Plat::find($this->platCibleId);

                if (! $plat instanceof Plat) {
                    abort(404);
                }

                $plat = $service->modifierPlat($plat, $donnees);
                $message = __('carte_pwa.restauration.modifie', ['plat' => $plat->libelle]);
            }
        } catch (RuntimeException $refus) {
            $this->addError('libelleSaisi', $refus->getMessage());

            return;
        }

        $this->terminerFormulaire($message);
    }

    // ---- Menu (EF-M4-01) -------------------------------------------------

    /**
     * Ouvre la création de menu — depuis l'en-tête, ou depuis le champ « Menu »
     * du formulaire de plat quand aucun menu n'existe encore.
     *
     * L'ordre compte : `ouvrirFormulaire()` remet à zéro les propriétés
     * DÉCLARÉES du formulaire « menu », `retourAuPlat` comprise. Le drapeau se
     * relève donc APRÈS, jamais avant.
     */
    public function ouvrirCreationMenu(): void
    {
        $depuisLePlat = $this->etatFormulaire === 'plat';

        $this->ouvrirFormulaire('menu');

        $this->retourAuPlat = $depuisLePlat;
    }

    /**
     * Ouvre une carte EXISTANTE — l'onglet « Menus » (04/09/2026).
     *
     * Le maître ne porte aucun écran de menu : sa « catégorie » est un simple
     * libellé de badge. Ici c'est une vraie table, et jusqu'à ce jour elle
     * n'avait qu'une écriture — la création. Une saison mal saisie était donc
     * définitive, et `menus` n'a aucune colonne d'archivage : la corriger est
     * le seul geste possible (RG-02, le « D » de CRUD n'existe nulle part).
     */
    public function ouvrirModificationMenu(string $menuId): void
    {
        $this->ouvrirFormulaire('menu');

        $menu = Menu::find($menuId);

        if (! $menu instanceof Menu) {
            abort(404);
        }

        $this->menuCibleId = $menu->id;
        $this->menuLibelleSaisi = (string) $menu->libelle;
        $this->menuTypeSaisi = (string) $menu->type;
        $this->menuDateDebutSaisie = $menu->date_debut?->format('Y-m-d') ?? '';
        $this->menuDateFinSaisie = $menu->date_fin?->format('Y-m-d') ?? '';
    }

    /**
     * Crée ou met à jour le menu — par `CartePlatMenuService`, jamais
     * `Menu::create()` dans le composant (`LARAVEL_PWA.md` §3).
     *
     * Les règles reprennent celles d'`EnregistrerMenuRequest` : la PWA et
     * l'API doivent refuser la même chose. `after_or_equal` n'est posée que
     * si une date de début est saisie — appliquée à une chaîne vide, elle
     * comparerait la date de fin à une date qui n'existe pas.
     */
    public function enregistrerMenu(): void
    {
        $regles = [
            'menuLibelleSaisi' => ['required', 'string', 'max:255'],
            'menuTypeSaisi' => ['required', 'string', 'in:'.implode(',', Menu::TYPES)],
            'menuDateDebutSaisie' => ['nullable', 'date'],
            'menuDateFinSaisie' => ['nullable', 'date'],
        ];

        if (trim($this->menuDateDebutSaisie) !== '') {
            $regles['menuDateFinSaisie'][] = 'after_or_equal:menuDateDebutSaisie';
        }

        $valide = $this->validerEcriture($regles);

        // La cible est résolue AVANT le `try` : `abort(404)` lève une
        // `NotFoundHttpException`, qui étend `RuntimeException` — dans le bloc
        // ci-dessous, un identifiant inconnu serait donc affiché comme un refus
        // métier au lieu de rendre un 404.
        $cible = null;

        if ($this->menuCibleId !== null) {
            $cible = Menu::find($this->menuCibleId);

            if (! $cible instanceof Menu) {
                abort(404);
            }
        }

        $donnees = [
            'libelle' => trim((string) $valide['menuLibelleSaisi']),
            'type' => (string) $valide['menuTypeSaisi'],
            'date_debut' => $this->dateOuNull($this->menuDateDebutSaisie),
            'date_fin' => $this->dateOuNull($this->menuDateFinSaisie),
        ];

        $service = app(CartePlatMenuService::class);

        try {
            $menu = $cible instanceof Menu
                ? $service->modifierMenu($cible, $donnees)
                : $service->creerMenu($donnees);
        } catch (RuntimeException $refus) {
            $this->addError('menuLibelleSaisi', $refus->getMessage());

            return;
        }

        if ($this->retourAuPlat) {
            $this->menuIdSaisi = $menu->id;
        }

        // Deux appels LITTÉRAUX plutôt qu'une clé construite : une clé
        // assemblée est invisible à `MessagesUtilisateurTest`, qui vérifie que
        // toute clé appelée existe — le piège déjà rencontré sur
        // `typesDeMenu()` le 03/09/2026.
        $message = $cible instanceof Menu
            ? __('carte_pwa.restauration.menu_modifie', ['libelle' => $menu->libelle])
            : __('carte_pwa.restauration.menu_cree', ['libelle' => $menu->libelle]);

        $this->revenirOuFermer((string) $message);
    }

    // ---- Fiche technique (EF-M4-02) --------------------------------------

    /**
     * Ouvre la création de fiche technique, avec UNE ligne de composition
     * offerte : un sous-formulaire vide ne dirait pas qu'on peut en ajouter.
     */
    public function ouvrirCreationRecette(): void
    {
        $depuisLePlat = $this->etatFormulaire === 'plat';

        $this->ouvrirFormulaire('recette');

        $this->retourAuPlat = $depuisLePlat;
        $this->ingredientsSaisis = [self::LIGNE_INGREDIENT_VIDE];
    }

    /**
     * LE GESTE QUI MANQUAIT — composer une fiche technique EXISTANTE
     * (04/09/2026).
     *
     * Sans lui, les 83 fiches vides de la base de démonstration étaient
     * inatteignables : l'écran savait créer une 84e fiche, jamais remplir
     * celles auxquelles les 83 plats sont déjà rattachés. Le POS restaurant
     * refusait donc toute vente (`RecetteManquanteException`), et la seule
     * sortie apparente — créer une nouvelle fiche puis rebrancher chaque plat
     * dessus — aurait laissé 83 fiches orphelines derrière elle.
     *
     * ⚠ La composition est lue par `CompositionRecetteService::lignes()`, pas
     * par la relation `Recette::ingredients()` : le service est l'unique
     * auteur de ces lignes, et il en fixe la précision (`DECIMAL(10,3)`).
     * Relire le pivot ici rendrait « 0.4 » là où le formulaire doit reproposer
     * « 0.400 », et l'enregistrement suivant réécrirait une quantité
     * différente de celle affichée.
     *
     * Une fiche déjà vide reçoit UNE ligne vierge — sans elle, l'écran
     * n'offrirait aucun champ à remplir sur la fiche même qu'on vient d'ouvrir
     * pour la remplir.
     */
    public function ouvrirModificationRecette(string $recetteId): void
    {
        $this->ouvrirFormulaire('recette');

        $recette = Recette::find($recetteId);

        if (! $recette instanceof Recette) {
            abort(404);
        }

        $this->recetteCibleId = $recette->id;
        $this->recetteLibelleSaisi = (string) $recette->libelle;

        $lignes = app(CompositionRecetteService::class)->lignes($recette);

        $this->ingredientsSaisis = $lignes === []
            ? [self::LIGNE_INGREDIENT_VIDE]
            : array_map(
                static fn (array $ligne): array => [
                    'article_id' => $ligne['article_id'],
                    'quantite_unitaire' => $ligne['quantite_unitaire'],
                ],
                $lignes,
            );
    }

    public function ajouterIngredient(): void
    {
        $this->exigerEcriture(self::MODULE);

        $this->ingredientsSaisis[] = self::LIGNE_INGREDIENT_VIDE;
    }

    public function retirerIngredient(int $index): void
    {
        $this->exigerEcriture(self::MODULE);

        unset($this->ingredientsSaisis[$index]);

        // Réindexée : `ingredientsSaisis.*` de la validation et le `wire:key`
        // de la vue supposent des indices contigus.
        $this->ingredientsSaisis = array_values($this->ingredientsSaisis);
    }

    /**
     * Crée OU compose la fiche technique, entête et composition, dans UNE
     * transaction.
     *
     * ## Pourquoi la transaction, et non deux appels de suite
     *
     * `ReferentielRecetteService` écrit l'entête, et la composition part
     * ensuite chez `CompositionRecetteService` — seul auteur de
     * `ingredients_recette` et de `recettes.cout_matiere_calcule`. Un refus sur
     * la seconde moitié laisserait une recette ORPHELINE, sans ingrédient,
     * indiscernable d'une fiche volontairement vide : elle apparaîtrait au
     * sélecteur du formulaire de plat et ne décrémenterait jamais rien.
     *
     * `remplacerComposition()` est appelée même sur une liste vide : c'est le
     * chemin qui écrit le coût matière, et le brancher ferait deux chemins là
     * où il n'en faut qu'un.
     *
     * ## La composition est REMPLACÉE, jamais fusionnée
     *
     * C'est le contrat de `remplacerComposition()`, et il commande la forme du
     * formulaire : ce que l'écran affiche EST la fiche après enregistrement.
     * Une ligne retirée à l'écran disparaît réellement de la nomenclature —
     * sans quoi le plat continuerait de décrémenter un article que la fiche ne
     * mentionne plus, et l'écart n'apparaîtrait qu'à l'inventaire.
     */
    public function enregistrerRecette(): void
    {
        $this->exigerEcriture(self::MODULE);

        // Les lignes ENTIÈREMENT vides sont retirées avant validation : un
        // « Ajouter un ingrédient » cliqué puis abandonné ne doit pas refuser
        // l'enregistrement d'une fiche par ailleurs correcte.
        $this->ingredientsSaisis = array_values(array_filter(
            $this->ingredientsSaisis,
            static fn (array $ligne): bool => trim((string) ($ligne['article_id'] ?? '')) !== ''
                || trim((string) ($ligne['quantite_unitaire'] ?? '')) !== '',
        ));

        $valide = $this->validerEcriture([
            'recetteLibelleSaisi' => ['required', 'string', 'max:255'],
            'ingredientsSaisis' => ['array'],
            // `distinct` : `ingredients_recette` a pour clé primaire le couple
            // (recette_id, article_id). Deux fois le même article ferait lever
            // une violation d'intégrité illisible au lieu d'un refus lisible.
            'ingredientsSaisis.*.article_id' => ['required', 'string', 'distinct', 'exists:articles,id'],
            // `gt:0` : une quantité nulle est une ligne qui ne décrémente
            // rien, écrite comme si elle décrémentait quelque chose.
            'ingredientsSaisis.*.quantite_unitaire' => ['required', 'numeric', 'gt:0'],
        ]);

        /** @var list<array{article_id: string, quantite_unitaire: string}> $lignes */
        $lignes = [];

        foreach ($valide['ingredientsSaisis'] ?? [] as $ligne) {
            $lignes[] = [
                'article_id' => (string) $ligne['article_id'],
                'quantite_unitaire' => (string) $ligne['quantite_unitaire'],
            ];
        }

        // Résolue AVANT le `try` : `abort(404)` lève une
        // `NotFoundHttpException`, qui étend `RuntimeException` — attrapée
        // plus bas, elle s'afficherait comme un refus métier.
        $cible = null;

        if ($this->recetteCibleId !== null) {
            $cible = Recette::find($this->recetteCibleId);

            if (! $cible instanceof Recette) {
                abort(404);
            }
        }

        $compositions = app(CompositionRecetteService::class);
        $referentiel = app(ReferentielRecetteService::class);
        $libelle = trim((string) $valide['recetteLibelleSaisi']);

        try {
            $recette = DB::transaction(
                static fn (): Recette => $compositions->remplacerComposition(
                    $cible instanceof Recette
                        ? $referentiel->modifier($cible, ['libelle' => $libelle])
                        : $referentiel->creer(['libelle' => $libelle]),
                    $lignes,
                ),
            );
        } catch (RuntimeException $refus) {
            $this->addError('recetteLibelleSaisi', $refus->getMessage());

            return;
        }

        if ($this->retourAuPlat) {
            $this->recetteIdSaisie = $recette->id;
        }

        $this->revenirOuFermer($this->messageDeRecette($recette, $cible === null));
    }

    /**
     * Ferme une modale secondaire — et rend la main au formulaire de plat
     * quand c'est de là qu'elle a été ouverte.
     *
     * `$set('etatFormulaire', null)` aurait suffi à fermer, et aurait perdu en
     * silence la saisie du plat en cours.
     */
    public function fermerFormulaireSecondaire(): void
    {
        $this->exigerEcriture(self::MODULE);

        if ($this->retourAuPlat) {
            $this->retourAuPlat = false;
            $this->etatFormulaire = 'plat';

            return;
        }

        $this->etatFormulaire = null;
    }

    /**
     * Ouvre la confirmation de retrait — les verrous sont calculés AVANT.
     *
     * Le maître masque le bouton de confirmation quand plus rien n'est
     * archivable (`crud-ui.js` l.136) : le laisser visible et inerte
     * laisserait croire à une panne.
     */
    public function ouvrirRetraitDuPlat(string $platId): void
    {
        $this->ouvrirFormulaire('archivage');

        $plat = Plat::find($platId);

        if (! $plat instanceof Plat) {
            abort(404);
        }

        $this->platCibleId = $plat->id;
    }

    /**
     * Retire le plat de la carte — rien n'est effacé, tout est restaurable.
     *
     * Les verrous sont RECALCULÉS ici : ceux affichés datent de l'ouverture de
     * la modale, une commande a pu naître depuis. Même précaution que M8.
     */
    public function confirmerRetraitDuPlat(): void
    {
        $this->exigerEcriture(self::MODULE);

        $plat = $this->platCibleId === null ? null : Plat::find($this->platCibleId);

        if (! $plat instanceof Plat) {
            abort(404);
        }

        if ($this->verrousDuPlat($plat) !== []) {
            // Le bouton n'est pas rendu dans cet état : y arriver signifie que
            // la propriété a été forcée depuis le navigateur, ou qu'une
            // commande est née pendant que la modale était ouverte.
            $this->ouvrirRetraitDuPlat($plat->id);

            return;
        }

        try {
            app(DisponibiliteCarteService::class)->rendreIndisponible(
                $plat,
                'retire',
            );
        } catch (RuntimeException $refus) {
            $this->addError('platCibleId', $refus->getMessage());

            return;
        }

        $this->terminerFormulaire(__('carte_pwa.restauration.archive', [
            'plat' => $plat->libelle,
        ]));
    }

    // =====================================================================
    // Auxiliaires des deux modales secondaires
    // =====================================================================

    /** Un `<input type="date">` vide rend « » ; la colonne, elle, est nullable. */
    private function dateOuNull(string $saisie): ?string
    {
        return trim($saisie) === '' ? null : trim($saisie);
    }

    /**
     * Clôt le geste secondaire : retour au formulaire de plat s'il attend, sinon
     * fermeture franche. Le message de succès part dans les deux cas.
     */
    private function revenirOuFermer(string $message): void
    {
        if ($this->retourAuPlat) {
            $this->retourAuPlat = false;
            $this->etatFormulaire = 'plat';
            session()->flash('pwa-succes', $message);

            return;
        }

        $this->terminerFormulaire($message);
    }

    /**
     * Ce que la fiche technique COÛTE, dit dans ses trois états — jamais zéro.
     *
     * Le coût vient de `CompositionRecetteService`, l'unique auteur de la
     * formule : le recalculer ici en ferait une seconde, et les deux
     * divergeraient au premier changement (PA-121). Un coût incomplet NOMME
     * les articles jamais réceptionnés, dont le coût moyen pondéré vaut zéro :
     * ils ne sont pas gratuits, ils sont non valorisés (M6).
     */
    private function messageDeRecette(Recette $recette, bool $creation): string
    {
        $cout = app(CompositionRecetteService::class)->coutMatiere($recette);

        // Six clés LITTÉRALES plutôt qu'un préfixe assemblé : une clé
        // construite est invisible à `MessagesUtilisateurTest`, qui vérifie que
        // toute clé appelée existe (piège mesuré le 03/09/2026 sur
        // `typesDeMenu()`).
        if ($cout->compositionVide) {
            $message = $creation
                ? __('carte_pwa.restauration.recette_creee_sans_ingredient', ['recette' => $recette->libelle])
                : __('carte_pwa.restauration.recette_modifiee_sans_ingredient', ['recette' => $recette->libelle]);

            return (string) $message;
        }

        if ($cout->incomplet) {
            $parametres = [
                'recette' => $recette->libelle,
                'articles' => implode(', ', $cout->articlesSansCout),
            ];

            $message = $creation
                ? __('carte_pwa.restauration.recette_creee_cout_incomplet', $parametres)
                : __('carte_pwa.restauration.recette_modifiee_cout_incomplet', $parametres);

            return (string) $message;
        }

        $parametres = [
            'recette' => $recette->libelle,
            'cout' => MontantFcfa::format((string) $cout->montant),
        ];

        $message = $creation
            ? __('carte_pwa.restauration.recette_creee', $parametres)
            : __('carte_pwa.restauration.recette_modifiee', $parametres);

        return (string) $message;
    }

    /**
     * Les types de carte proposés — les trois valeurs de l'`enum` `menus.type`.
     *
     * ⚠ Les clés de langue sont LITTÉRALES, et c'est la seule forme possible :
     * `__('…menu_type_'.$type)` est invisible à `MessagesUtilisateurTest`, qui
     * vérifie que toute clé appelée existe — mesuré le 03/09/2026, il a signalé
     * la clé tronquée `carte_pwa.restauration.menu_type_`. Une clé absente
     * n'aurait alors été vue par personne avant l'écran.
     *
     * ⚠ Cette liste et `Menu::TYPES` sont donc DEUX listes, ce que ce dépôt
     * refuse d'ordinaire. La divergence est fermée par un test, pas par une
     * promesse : `le_formulaire_de_menu_offre_exactement_les_types_de_l_enum`
     * relit le HTML rendu et exige une option par valeur de l'enum.
     *
     * @return array<string, string>
     */
    private function typesDeMenu(): array
    {
        return [
            'local' => (string) __('carte_pwa.restauration.menu_type_local'),
            'europeen' => (string) __('carte_pwa.restauration.menu_type_europeen'),
            'special' => (string) __('carte_pwa.restauration.menu_type_special'),
        ];
    }

    /**
     * Les articles proposés au sélecteur d'ingrédient — filtrés au serveur.
     *
     * ⚠ Les articles DÉJÀ CHOISIS sont toujours proposés, quel que soit le
     * terme : sans cette union, taper une recherche ferait disparaître de son
     * propre `<select>` une ligne déjà saisie. La valeur, elle, survivrait dans
     * la propriété Livewire — l'écran montrerait donc un champ vide sur une
     * donnée présente, ce qui est pire qu'une perte franche.
     *
     * @return \Illuminate\Database\Eloquent\Collection<int, Article>
     */
    private function articlesProposes(): \Illuminate\Database\Eloquent\Collection
    {
        $terme = trim($this->rechercheArticleIngredient);

        $dejaChoisis = array_values(array_filter(array_map(
            static fn (array $ligne): string => trim((string) ($ligne['article_id'] ?? '')),
            $this->ingredientsSaisis,
        ), static fn (string $id): bool => $id !== ''));

        return Article::query()
            ->when(
                $terme !== '',
                static fn ($q) => $q->where(
                    static fn ($interne) => $interne
                        ->where('libelle', 'like', '%'.$terme.'%')
                        ->orWhereIn('id', $dejaChoisis),
                ),
            )
            ->orderBy('libelle')
            ->get();
    }

    // =====================================================================
    // Lecture
    // =====================================================================

    /**
     * Ce qui EMPÊCHE de retirer ce plat de la carte, en clair.
     *
     * @return list<string>
     */
    protected function verrousDuPlat(Plat $plat): array
    {
        $verrous = [];

        $indisponibilite = app(DisponibiliteCarteService::class)->indisponibilite($plat);

        if ($indisponibilite instanceof IndisponibiliteCarte) {
            $verrous[] = __('carte_pwa.restauration.verrou_deja_retire', [
                'motif' => $indisponibilite->libelleMotif(),
            ]);
        }

        $engagements = DB::table('lignes_commande_restaurant')
            ->join(
                'commandes_restaurant',
                'commandes_restaurant.id',
                '=',
                'lignes_commande_restaurant.commande_id',
            )
            ->where('lignes_commande_restaurant.plat_id', $plat->id)
            ->whereIn('commandes_restaurant.statut', self::STATUTS_ENGAGEANTS)
            ->orderByDesc('commandes_restaurant.date_commande')
            ->limit(5)
            ->pluck('commandes_restaurant.id');

        if ($engagements->isNotEmpty()) {
            $verrous[] = __('carte_pwa.restauration.verrou_commandes', [
                'nombre' => $engagements->count(),
                'liste' => $engagements->implode(', '),
            ]);
        }

        return $verrous;
    }

    /**
     * La requête des plats AFFICHÉS, filtres compris — le seul chemin qui la
     * produit, partagé par `render()` et la sélection (PA-119).
     *
     * @return \Illuminate\Database\Eloquent\Builder<Plat>
     */
    private function requetePlats(): \Illuminate\Database\Eloquent\Builder
    {
        $categorie = array_key_exists($this->categorie, CarteRestaurant::CATEGORIES)
            ? $this->categorie
            : null;
        $terme = trim($this->recherche);

        return Plat::query()
            ->with(['menu', 'recette.ingredients'])
            ->when($categorie !== null, static fn ($q) => $q->where('categorie', $categorie))
            ->when($terme !== '', static fn ($q) => $q->where('libelle', 'like', '%'.$terme.'%'))
            ->orderBy('categorie')
            ->orderBy('libelle');
    }

    /**
     * L'onglet « Fiches techniques » — la liste, ses états et ses coûts.
     *
     * ## Le coût vient du SERVICE, jamais d'un calcul refait ici
     *
     * `CompositionRecetteService::coutMatiere()` est l'unique auteur de la
     * formule (quantité × coût moyen pondéré, `bcmul`/`bcadd`). Le recalculer
     * dans l'écran en ferait une seconde, et les deux divergeraient au premier
     * changement — PA-121, la leçon des séries du tableau de bord. C'est un
     * appel par ligne affichée, soit dix : le mesurer en un `GROUP BY` unique
     * dupliquerait les prédicats (CMP nul = article NON VALORISÉ, pas gratuit)
     * exactement là où ils comptent.
     *
     * ⚠ Ce que l'écran affiche est un objet `CoutMatiere`, jamais un montant :
     * ses trois états sont la substance de PA-126 sur cet écran-ci. Un « 0 F »
     * à la place de « composition vide » se lirait comme un plat gratuit.
     *
     * @return array{page: \Illuminate\Contracts\Pagination\LengthAwarePaginator<int, Recette>, couts: array<string, \App\Domain\Restaurant\ReadModels\CoutMatiere>, total: int, vides: int, provisoires: int}
     */
    private function pageDesFiches(): array
    {
        $terme = trim($this->rechercheFiche);

        $page = Recette::query()
            ->withCount('ingredients')
            // `ingredients` est charge, pas seulement compte :
            // `decrementeUnStockSuivi()` lit le mode de suivi de chaque
            // article, et l'appeler par ligne sur une liste paginee ferait
            // sinon N+1.
            ->with(['plats', 'ingredients'])
            ->when($terme !== '', static fn ($q) => $q->where('libelle', 'like', '%'.$terme.'%'))
            // Le filtre qui rend le blocage praticable : sur 83 fiches, les
            // vides sont celles dont la vente est REFUSÉE au comptoir.
            ->when($this->videsSeulement, static fn ($q) => $q->whereDoesntHave('ingredients'))
            ->orderBy('libelle')
            ->paginate(self::PAR_PAGE, ['*'], 'page', max(1, $this->pageCourante));

        $compositions = app(CompositionRecetteService::class);
        $couts = [];

        foreach ($page as $recette) {
            $couts[(string) $recette->id] = $compositions->coutMatiere($recette);
        }

        return [
            'page' => $page,
            'couts' => $couts,
            // Les compteurs portent sur le RÉFÉRENTIEL ENTIER, jamais sur la
            // page : « 3 fiches vides » sur une page filtrée laisserait croire
            // que le reste est composé.
            'total' => Recette::query()->count(),
            'vides' => Recette::query()->whereDoesntHave('ingredients')->count(),
            'provisoires' => Recette::query()->where(Recette::PROVISOIRE, true)->count(),
        ];
    }

    public function render(): View
    {
        $onglet = $this->ongletValide();

        /** @var \Illuminate\Database\Eloquent\Collection<int, Plat> $tous */
        $tous = Plat::query()
            ->with(['menu', 'recette.ingredients'])
            ->orderBy('categorie')
            ->orderBy('libelle')
            ->get();

        // UNE requête d'indisponibilité pour tout l'écran : la colonne
        // « Disponible » du maître ne se lit nulle part ailleurs, et la
        // demander par ligne ferait N+1 sur tout le catalogue.
        $indisponibilites = app(DisponibiliteCarteService::class)
            ->indisponibilitesEnCours('plat');

        // PAGINATION du maître (`crud-engine.js` l.21) — le filtrage est passé
        // en SQL avec elle : filtrer une collection puis la découper à la main
        // referait le travail de `paginate()` en moins fiable. `LIKE` est
        // insensible à la casse sur MySQL, comme l'était `mb_stripos`.
        $lignes = $this->requetePlats()
            ->paginate(self::PAR_PAGE, ['*'], 'page', max(1, $this->pageCourante));

        $avecFiche = $tous->filter(
            static fn (Plat $plat): bool => $plat->recette !== null
                && $plat->recette->ingredients->isNotEmpty(),
        )->count();

        $platCible = $this->platCibleId === null ? null : Plat::find($this->platCibleId);

        $recetteCible = $this->recetteCibleId === null ? null : Recette::find($this->recetteCibleId);

        return view('pwa.restaurant.restauration', array_merge($this->socle(), [
            'onglet' => $onglet,
            // Les deux onglets ajoutés ne sont calculés QUE lorsqu'ils sont
            // affichés : la liste des fiches coûte une requête de coût matière
            // par ligne, et l'onglet des plats n'en a aucun besoin.
            'fiches' => $onglet === 'fiches' ? $this->pageDesFiches() : null,
            'menusListe' => $onglet === 'menus'
                ? Menu::query()->withCount('plats')->orderBy('libelle')->get()
                : null,
            // Le coût de la fiche OUVERTE, en lecture seule : il dit ce que la
            // composition affichée valait AVANT la saisie en cours. Recalculé
            // à l'enregistrement, jamais depuis les champs du formulaire — un
            // coût qui suivrait la frappe serait un champ déguisé.
            'coutFicheCible' => $recetteCible instanceof Recette
                ? app(CompositionRecetteService::class)->coutMatiere($recetteCible)
                : null,
            'ficheCibleProvisoire' => $recetteCible instanceof Recette
                && $recetteCible->composition_provisoire === true,
            'lignes' => $lignes,
            'indisponibilites' => $indisponibilites,
            'categories' => CarteRestaurant::CATEGORIES,
            'menus' => Menu::query()->orderBy('libelle')->get(),
            'recettes' => Recette::query()->orderBy('libelle')->get(),
            // Les deux modales secondaires (03/09/2026) — sans elles, les deux
            // sélecteurs ci-dessus peuvent être VIDES sur une base neuve, et
            // aucun geste de l'écran ne permet d'en sortir.
            'typesMenu' => $this->typesDeMenu(),
            'articlesIngredient' => $this->articlesProposes(),
            'total' => $tous->count(),
            'avecFiche' => $avecFiche,
            'sansFiche' => $tous->count() - $avecFiche,
            'retires' => $indisponibilites->count(),
            'platCible' => $platCible,
            'verrous' => $platCible instanceof Plat ? $this->verrousDuPlat($platCible) : [],
            // PA-161 (b) — un ÉTAT dérivé, en lecture seule : la marque
            // « corrigé à la main » est un fait, pas une case à cocher.
            'platCorrigeMain' => $platCible instanceof Plat && $platCible->prix_corrige_main === true,
            // `data-module="M4"` du `<body>` au maître (l.16).
        ]))->layout('layouts.pwa', ['module' => self::MODULE]);
    }
}
