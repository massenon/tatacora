<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Pos;

use App\Domain\Bar\Models\CarteBoisson;
use App\Domain\Restaurant\Models\Plat;
use App\Domain\Tourisme\Models\Circuit;
use App\Domain\Vehicules\Models\Vehicule;
use App\Domain\Ventes\Services\VenteService;
use App\Pwa\Livewire\Restaurant\CarteRestaurant;
use Illuminate\Support\Collection;

/**
 * Ce que les DEUX points de vente ont en commun — ecrit une fois.
 *
 * Maitres : prototype_v2/pages/pos.html et prototype_v2/pages/pos-heberges.html.
 *
 * ## Le POS n'est pas une structure, c'est un ECRAN (PA-98)
 *
 * La difference entre les deux points de vente tient dans le type de vente et
 * le sejour rattache, et nulle part ailleurs : le catalogue, la resolution des
 * references et la mise en forme des rayons sont les memes des deux cotes. Les
 * recopier aurait produit deux affichages qui divergent le jour ou l'un des
 * deux change — le defaut que ce depot a deja paye trois fois.
 *
 * ## Ce trait ne fait plus AUCUN calcul de panier (31/08/2026, PA-161)
 *
 * Il portait l'arithmetique — ajout de ligne, quantite, total, ventilation —
 * parce que le panier vivait en session ou en propriete de composant. Le
 * panier est desormais une table : le total vit sur {@see \App\Domain\Ventes\Models\Panier},
 * et toute ecriture passe par {@see \App\Domain\Ventes\Services\PanierService}.
 * Les laisser ici aurait donne DEUX arithmetiques du meme panier, celle de
 * l'ecran et celle du domaine, qui auraient fini par ne plus dire le meme
 * total sur la meme commande.
 *
 * ## Le prix et le libelle ne viennent JAMAIS de l'ecran
 *
 * Le maitre porte le montant dans le DOM (`data-ajouter` avec son prix) et le
 * renvoie tel quel. Ici l'ecran ne transmet qu'un MODULE et une REFERENCE : le
 * serveur relit le catalogue et FIGE le prix et le libelle a l'ajout, comme
 * `VenteService` les fige a l'encaissement et comme `tarifNuit` les fige a la
 * reservation (PA-55, PA-98). Sans cela, n'importe qui pouvait appeler
 * l'action Livewire avec le prix de son choix : le panier, le ticket et la
 * facture l'auraient repris sans un mot.
 *
 * ⚠ La resolution que fait `resoudreArticle()` sert l'AFFICHAGE et les
 * messages du maitre — pas la garantie. Ce qui est ecrit en base vient de
 * `PanierService`, qui relit le catalogue pour son propre compte.
 *
 * ## Un trait, pas une classe abstraite
 *
 * Une classe de plus sous `app/Pwa/Livewire/` entrerait dans la surface
 * d'actions relue par `PwaActionsReluesTest`, qui compte les composants. Un
 * trait en est explicitement exclu (`trait_exists`), et ses methodes sont
 * relues a travers chaque classe qui l'utilise — la seule lecture qui compte.
 * Toutes ses methodes sont donc `protected` : une methode publique posee ici
 * deviendrait une action Livewire sur les deux ecrans a la fois.
 *
 * @see EF-M5-06 Vente au comptoir du bar
 * @see EF-M4-03 Prise de commande
 * @see RG-05 Sortie de stock automatique
 */
trait ComposePanier
{
    /** Precision de tout calcul monetaire — DECIMAL(15,2), jamais un flottant. */
    protected const PRECISION_MONTANT = 2;

    /**
     * Les rayons que les deux ecrans savent lire, et leur module.
     *
     * `VenteService::MODULES_ENCAISSABLES` decide, lui, lesquels peuvent etre
     * ENCAISSES — ce n'est pas la meme question, et les confondre a deja
     * produit un ecran qui proposait quatre rayons sur cinq sans rien pouvoir
     * en faire (PA-129). Un rayon non encaissable reste AFFICHE avec sa
     * raison ; l'omettre le rendrait indiscernable d'un rayon vide. Depuis le
     * 22/10/2026 le tourisme et la location sont encaissables au comptoir
     * (`PosComptant`) ; le POS des clients heberges, lui, les refuse encore.
     */
    protected const MODULE_BAR = 'M5';

    protected const MODULE_RESTAURANT = 'M4';

    protected const MODULE_TOURISME = 'M9';

    protected const MODULE_VEHICULES = 'M8';

    /** Le toast du maitre — message et couleur. */
    public ?string $toastMessage = null;

    public string $toastType = 'success';

    protected function notifier(string $message, string $type = 'success'): void
    {
        $this->toastMessage = $message;
        $this->toastType = $type;
    }

    // =====================================================================
    // Le catalogue — lu une fois, jamais une requete par ligne
    // =====================================================================

    /**
     * Le catalogue des rayons demandes, deja mis en forme pour l'affichage.
     *
     * `with()` sur les relations lues : le catalogue est une liste longue, et
     * une requete par article la rendrait inutilisable des la premiere carte
     * un peu fournie.
     *
     * Chaque article porte `encaissable`, derive de
     * `VenteService::MODULES_ENCAISSABLES` : le rayon reste AFFICHE meme quand
     * il ne peut pas etre porte au panier, et l'ecran dit pourquoi (PA-24). Le
     * drapeau est pose ici plutot que dans chaque ecran — deux calculs du meme
     * fait finiraient par diverger.
     *
     * @param  list<string>  $modules
     * @return Collection<int, array<string, mixed>>
     */
    protected function catalogue(array $modules): Collection
    {
        /** @var Collection<int, array<string, mixed>> $articles */
        $articles = collect();

        if (in_array(self::MODULE_BAR, $modules, true)) {
            $articles = $articles->concat(
                CarteBoisson::query()
                    ->with('article')
                    ->orderBy('categorie')
                    ->orderBy('libelle')
                    ->get()
                    ->map(fn (CarteBoisson $b): array => $this->depuisBoisson($b))
                    ->all(),
            );
        }

        if (in_array(self::MODULE_RESTAURANT, $modules, true)) {
            $articles = $articles->concat(
                Plat::query()
                    ->with(['menu', 'recette.ingredients'])
                    ->orderBy('categorie')
                    ->orderBy('libelle')
                    ->get()
                    ->map(fn (Plat $p): array => $this->depuisPlat($p))
                    ->all(),
            );
        }

        if (in_array(self::MODULE_TOURISME, $modules, true)) {
            $articles = $articles->concat(
                Circuit::query()->orderBy('nom')->get()
                    ->map(fn (Circuit $c): array => $this->depuisCircuit($c))
                    ->all(),
            );
        }

        if (in_array(self::MODULE_VEHICULES, $modules, true)) {
            $articles = $articles->concat(
                Vehicule::query()->orderBy('immatriculation')->get()
                    ->map(fn (Vehicule $v): array => $this->depuisVehicule($v))
                    ->all(),
            );
        }

        return $articles->values();
    }

    /**
     * Le catalogue filtre par famille, categorie et recherche.
     *
     * ⚠ Le filtre de catalogue N'EST PAS la caisse (PA-79) : il ne change ni
     * le point de vente, ni le panier, ni ce qui sera encaisse. Le maitre le
     * dit lui-meme dans l'infobulle de son selecteur (pos.html l.60).
     *
     * @param  Collection<int, array<string, mixed>>  $articles
     * @return Collection<int, array<string, mixed>>
     */
    protected function filtrerCatalogue(
        Collection $articles,
        string $famille,
        string $categorie,
        string $recherche,
    ): Collection {
        $resultat = $articles;

        if ($famille !== 'tout') {
            $resultat = $resultat->filter(fn (array $a): bool => $a['famille'] === $famille);
        }

        if ($categorie !== 'tout') {
            $resultat = $resultat->filter(fn (array $a): bool => $a['categorie'] === $categorie);
        }

        $terme = trim($recherche);

        if ($terme !== '') {
            $resultat = $resultat->filter(
                fn (array $a): bool => mb_stripos((string) $a['nom'], $terme) !== false,
            );
        }

        return $resultat->values();
    }

    /**
     * Les categories presentes au catalogue, dans l'ordre du maitre : « Tout »
     * puis celles qui portent reellement un article.
     *
     * @param  Collection<int, array<string, mixed>>  $articles
     * @return array<string, string> cle => libelle
     */
    protected function categoriesDuCatalogue(Collection $articles): array
    {
        $categories = ['tout' => __('pos_pwa.commun.categorie_tout')];

        foreach ($articles as $article) {
            $cle = (string) $article['categorie'];

            if ($cle !== '' && ! array_key_exists($cle, $categories)) {
                $categories[$cle] = (string) $article['categorie_libelle'];
            }
        }

        return $categories;
    }

    // =====================================================================
    // La resolution d'une reference — le seul chemin d'entree au panier
    // =====================================================================

    /**
     * Relit le catalogue pour une reference, ou rend `null` si elle n'y est
     * plus. Le prix et le libelle rendus ici sont ceux qui seront FIGES.
     *
     * @return array<string, mixed>|null
     */
    protected function resoudreArticle(string $module, string $reference): ?array
    {
        $article = match ($module) {
            self::MODULE_BAR => CarteBoisson::with('article')->find($reference),
            self::MODULE_RESTAURANT => Plat::with(['menu', 'recette.ingredients'])->find($reference),
            self::MODULE_TOURISME => Circuit::find($reference),
            self::MODULE_VEHICULES => Vehicule::find($reference),
            default => null,
        };

        if ($article === null) {
            return null;
        }

        return match ($module) {
            self::MODULE_BAR => $this->depuisBoisson($article),
            self::MODULE_RESTAURANT => $this->depuisPlat($article),
            self::MODULE_TOURISME => $this->depuisCircuit($article),
            default => $this->depuisVehicule($article),
        };
    }

    /**
     * @return array<string, mixed>
     */
    private function depuisBoisson(CarteBoisson $boisson): array
    {
        return [
            'module' => self::MODULE_BAR,
            'reference_id' => $boisson->id,
            'nom' => $boisson->libelle,
            'prix' => (string) $boisson->prix_vente,
            'categorie' => (string) $boisson->categorie,
            // Le LIBELLÉ français de l'enum, jamais son code brut : « locale »
            // affiché tel quel sur une chip est le défaut corrigé le
            // 02/09/2026. Source unique : {@see CarteBoisson::CATEGORIES}.
            'categorie_libelle' => CarteBoisson::CATEGORIES[$boisson->categorie] ?? (string) $boisson->categorie,
            'famille' => __('pos_pwa.comptant.famille_bar'),
            'encaissable' => true,
            /*
             * `cartes_boisson.article_id` est NOT NULL au schema : une boisson
             * de la carte decremente TOUJOURS un stock, et le point orange du
             * maitre ne la vise jamais. Un controle de nullite ici serait une
             * condition qui ne peut pas etre fausse — elle laisserait croire
             * que le cas est traite alors qu'il n'existe pas.
             */
            'lien_stock' => true,
            // Une boisson n'a pas de fiche technique : `cartes_boisson` porte
            // son article directement. La marque des compositions posees ne la
            // vise jamais — la cle est rendue `false` plutot qu'absente, pour
            // que la vue n'ait pas a distinguer « pas provisoire » de « pas de
            // cle » (meme discipline que `lien_stock`).
            'composition_provisoire' => false,
            'prestation' => false,
        ];
    }

    /**
     * @return array<string, mixed>
     */
    private function depuisPlat(Plat $plat): array
    {
        return [
            'module' => self::MODULE_RESTAURANT,
            'reference_id' => $plat->id,
            'nom' => $plat->libelle,
            'prix' => (string) $plat->prix_vente,
            'categorie' => (string) ($plat->categorie ?? 'restauration'),
            /*
             * LE RAYON DU MAÎTRE, PAS LE NOM DU MENU (corrigé le 02/09/2026).
             *
             * `$plat->menu->libelle` vaut « Carte du restaurant » pour TOUS
             * les plats — un seul menu les porte tous — donc chaque chip
             * répétait ce même texte huit fois là où le maître montre huit
             * rayons distincts (Entrées, Plats complets, Nos sauces…).
             * `RestaurantSeeder` sème `plats.categorie` avec le libellé EXACT
             * du rayon (l.241) précisément pour cet usage.
             */
            /*
             * LE LIBELLE du rayon, jamais son CODE (04/09/2026).
             *
             * `plats.categorie` porte desormais le code (`entrees`,
             * `sandwicherie`, `formules`...) et non plus le libelle affiche :
             * c'est ce que le filtre des ecrans interroge, et un libelle
             * stocke ne correspondait a aucune option. Rendu tel quel sur une
             * chip du comptoir, « entrees » serait le defaut corrige le
             * 02/09/2026 pour le bar, ou « locale » s'affichait a l'ecran.
             *
             * Repli sur la valeur brute : une categorie hors registre —
             * ancienne donnee, import — s'affiche telle quelle plutot que de
             * disparaitre.
             */
            'categorie_libelle' => CarteRestaurant::CATEGORIES[$plat->categorie ?? '']
                ?? (string) ($plat->categorie ?? ''),
            'famille' => __('pos_pwa.comptant.famille_restaurant'),
            'encaissable' => true,
            /*
             * Le point orange du maitre (pos.html l.488) : « vendable, mais ne
             * decremente aucun stock — fiche technique absente ».
             *
             * Un plat a DEUX chemins de decrement, et les deux comptent : le
             * lien direct a un article (`aUnLienDirectAuStock()`, qui exige le
             * conditionnement en plus de l'article) ou les ingredients de sa
             * recette. N'en lire qu'un allumerait le point orange sur la
             * moitie d'une carte parfaitement suivie.
             */
            'lien_stock' => $plat->aUnLienDirectAuStock()
                || ($plat->recette?->ingredients->isNotEmpty() ?? false),
            /*
             * La marque « composition provisoire » (04/09/2026) — le pendant
             * du point orange, un cran plus discret et tout aussi necessaire.
             *
             * Un plat dont la fiche est provisoire EST vendable et decremente
             * bel et bien : ses quantites ont simplement ete POSEES pour
             * debloquer le service, jamais pesees. Le point orange dit « rien
             * ne sort du stock » ; celle-ci dit « ce qui sort est approximatif ».
             * Les confondre ferait croire l'un ou l'autre a tort.
             *
             * ⚠ Elle ne vaut que par la RECETTE : un plat a lien direct au
             * stock decremente un article unique, sans nomenclature a deviner.
             */
            'composition_provisoire' => ! $plat->aUnLienDirectAuStock()
                && ($plat->recette?->composition_provisoire === true),
            'prestation' => false,
        ];
    }

    /**
     * @return array<string, mixed>
     */
    private function depuisCircuit(Circuit $circuit): array
    {
        return [
            'module' => self::MODULE_TOURISME,
            'reference_id' => $circuit->id,
            'nom' => $circuit->nom,
            'prix' => (string) $circuit->prix,
            'categorie' => 'prestations',
            'categorie_libelle' => __('pos_pwa.heberges.categorie_prestations'),
            'famille' => __('pos_pwa.comptant.famille_tourisme'),
            'lien_stock' => false,
            // Une prestation ne se cuisine pas : aucune fiche technique, donc
            // aucune quantite posee a signaler.
            'composition_provisoire' => false,
            // Encaissable au comptoir depuis le 22/10/2026 (directive du PO) :
            // `circuits.prix` est le prix fige. Le point orange du maitre ne la
            // vise pas — une prestation ne decremente aucun stock, elle n'en a
            // pas a decrementer.
            'prestation' => true,
            'encaissable' => true,
        ];
    }

    /**
     * @return array<string, mixed>
     */
    private function depuisVehicule(Vehicule $vehicule): array
    {
        return [
            'module' => self::MODULE_VEHICULES,
            'reference_id' => $vehicule->id,
            'nom' => $vehicule->immatriculation.' ('.$vehicule->categorie.')',
            'prix' => (string) $vehicule->tarif_jour,
            'categorie' => 'prestations',
            'categorie_libelle' => __('pos_pwa.heberges.categorie_prestations'),
            'famille' => __('pos_pwa.comptant.famille_location'),
            'lien_stock' => false,
            // Une prestation ne se cuisine pas : aucune fiche technique, donc
            // aucune quantite posee a signaler.
            'composition_provisoire' => false,
            // Encaissable au comptoir depuis le 22/10/2026 : `vehicules.tarif_jour`
            // est le prix fige, la quantite est un nombre de jours.
            'prestation' => true,
            'encaissable' => true,
        ];
    }

}
