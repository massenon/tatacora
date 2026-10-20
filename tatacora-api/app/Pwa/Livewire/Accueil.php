<?php

declare(strict_types=1);

namespace App\Pwa\Livewire;

use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Domain\Comptabilite\ReadModels\IndicateursComptables;
use App\Domain\Comptabilite\Services\AnalytiqueService;
use App\Domain\Comptabilite\Services\IndicateursComptablesService;
use App\Domain\Crm\Models\Client;
use App\Domain\Crm\Services\EnregistrementClientService;
use App\Domain\Crm\Services\SoldeClientService;
use App\Domain\Depenses\Services\DepenseService;
use App\Domain\Facturation\Models\Facture;
use App\Domain\Facturation\Models\LigneFacture;
use App\Domain\Facturation\Services\EncaissementFactureService;
use App\Domain\Hebergement\Models\CanalReservation;
use App\Domain\Hebergement\Models\Reservation;
use App\Domain\Hebergement\Models\Sejour;
use App\Domain\Hebergement\Models\UniteHebergement;
use App\Domain\Hebergement\Services\DisponibiliteService;
use App\Domain\Hebergement\Services\ReservationService;
use App\Domain\Hebergement\Services\SejourService;
use App\Domain\Rh\Services\LivreDePaieService;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Services\StockTheoriqueService;
use App\Domain\TableauxDeBord\Data\Periode;
use App\Domain\TableauxDeBord\Services\TableauDeBordService;
use App\Domain\Tourisme\Services\ReservationTourService;
use App\Domain\Vehicules\Models\Vehicule;
use App\Domain\Vehicules\Services\ParcVehiculeService;
use App\Domain\Ventes\Models\Vente;
use App\Domain\Ventes\Services\VenteService;
use App\Exports\DashboardExport;
use App\Models\User;
use App\Pwa\Livewire\Concerns\FormulaireModal;
use App\Pwa\Livewire\Tourisme\Departs as EcranTourisme;
use App\Pwa\Livewire\Vehicules\Locations as EcranVehicules;
use App\Pwa\Support\ExerciceConsulte;
use App\Pwa\Support\MenuLateral;
use App\Pwa\Support\MontantFcfa;
use App\Shared\Integrite\Exceptions\ChevauchementDetecteException;
use Barryvdh\DomPDF\Facade\Pdf;
use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Collection as EloquentCollection;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Route;
use Illuminate\View\View;
use Livewire\Attributes\Title;
use Livewire\Attributes\Url;
use Maatwebsite\Excel\Facades\Excel;
use RuntimeException;
use Symfony\Component\HttpFoundation\BinaryFileResponse;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * Tableau de bord M11 — maître : `prototype_v2/pages/tableau-de-bord.html`.
 *
 * @see EF-M11-01 Tableau de bord global
 * @see EF-M11-03 Indicateurs comparatifs
 * @see EF-M11-04 Filtres dynamiques par période
 * @see RG-01 Prévention des doubles réservations
 * @see RG-02 Disponibilité toujours calculée
 * @see RG-18 Détection de doublons — avertissante, jamais bloquante
 *
 * ## AUCUN CHIFFRE N'EST ÉCRIT DANS CE FICHIER (A2, 31/08/2026)
 *
 * La version précédente portait `$caPaye = 200000` et `$totalDepenses = 165000`
 * comme valeurs de repli **dans un `catch`** : un échec de lecture affichait
 * 200 000 F de chiffre d'affaires, avec la même typographie et la même carte
 * qu'un chiffre réel. C'est la faute la plus grave qu'un tableau de bord puisse
 * commettre — on décide sur ces nombres. Sept autres replis du même genre
 * l'accompagnaient (`$tauxOcc = 30`, `$stocksCritiquesCount = 2`, « Factures en
 * attente : 2 », « Employés actifs : 4 »), et six blocs `try { … } catch
 * (\Throwable) { return collect(); }` rendaient « 0 chambre disponible »
 * indiscernable d'un hôtel complet.
 *
 * Les huit indicateurs viennent désormais de `TableauDeBordService`, et de lui
 * seul. **Un seul `catch` subsiste**, autour de la bande d'indicateurs : il ne
 * remplace aucun chiffre, il rend la bande vide en DISANT que rien n'a été
 * mesuré (`accueil_pwa.lecture_impossible`). Sans lui, une seule agrégation en
 * défaut emporterait la page entière ; avec un chiffre de repli, elle mentirait.
 * Ce chemin est réellement exécuté par un test, qui lie un service en échec :
 * une branche de secours jamais empruntée est exactement PA-59/60/61.
 *
 * ## LES GESTES PASSENT PAR LES SERVICES DE DOMAINE, JAMAIS PAR ELOQUENT NU
 *
 * La version précédente créait la réservation rapide par `Reservation::create()`
 * : **RG-01 était contournable depuis le tableau de bord**, sans verrou
 * pessimiste ni transaction, sur les mêmes tables que l'écran M1 protège. Deux
 * réceptionnistes validant la même chambre passaient tous les deux. Le check-in
 * écrivait `unites_hebergement.statut = 'Occupée'` à la main — une valeur qui
 * n'est même pas dans l'`enum` (`libre|occupee|reservee|nettoyage|hors_service`),
 * et qui ne « marchait » que par la collation insensible à la casse de MySQL.
 *
 * Quatre services portent désormais ces gestes, et ils portent aussi leurs
 * verrous : `ReservationService` (RG-01), `SejourService` (check-in, check-out),
 * `EnregistrementClientService` (RG-18), `DisponibiliteService` (RG-02).
 *
 * ## ⚠ LE DROIT EXIGÉ N'EST PAS CELUI DE L'ÉCRAN — ET IL NE PEUT PAS L'ÊTRE SEUL
 *
 * Les actions rapides de cet écran écrivent sur **d'autres modules que M11** :
 * créer un client est une écriture M3, une réservation et un check-in sont des
 * écritures M1. Exiger `M11 = C` et rien d'autre exigerait le droit sur le
 * MAUVAIS module — un rôle sans M1 créerait une réservation avec son seul droit
 * M11, et la garde passerait quand même. Chaque geste exige donc le module
 * qu'il écrit RÉELLEMENT, nommé au-dessus de l'appel.
 *
 * `self::MODULE` (M11) est exigé **en plus**, et ce n'est pas décoratif :
 * `PwaEcritureAutoriseeTest` refuse tout appel d'`exigerEcriture()` qui ne
 * recevrait pas `self::MODULE` — sans quoi un littéral pourrait désigner
 * n'importe quel écran sans que personne ne le relise. C'est le même cumul que
 * `Reservations::ouvrirCreationClient` (PA-116).
 *
 * ⚠ CONSÉQUENCE À ARBITRER, ET ELLE EST ÉCRITE PLUTÔT QUE DÉCOUVERTE PLUS TARD :
 * `receptionniste` a `M11 = 'L'` (matrice RBAC, `RolePermissionSeeder`). Les
 * raccourcis de CET écran lui sont donc fermés, alors que les écrans M1
 * (`/pwa/reservations`, `/pwa/hebergement`) lui restent entièrement ouverts —
 * la fonction n'est perdue nulle part, seul le raccourci l'est. Les boutons
 * sont masqués pour ces rôles (1ᵉʳ niveau RBAC), jamais rendus inertes.
 * Question ouverte auprès du Product Owner (31/08/2026).
 *
 * ## CET ÉCRAN PORTE DEUX PAGES DU MAÎTRE, ET LA SECONDE LE DIT ELLE-MÊME
 *
 * L'onglet « Pilotage consolidé » (`?panel=pilotage`) est le portage de
 * `prototype_v2/pages/m11-pilotage.html`. Ce n'est pas une interprétation : le
 * maître l'écrit dans son propre bandeau (l.51-59) — « Le pilotage consolidé
 * est désormais un onglet du **Tableau de bord**. Cette page reste accessible
 * par son URL — un favori ne doit pas tomber dans le vide — mais elle n'est
 * plus au menu. » La fusion est datée du 18/08/2026 dans son commentaire
 * (l.46-50), et `tableau-de-bord.html` porte effectivement le panneau
 * (`data-panneau-tb="pilotage"`, l.162-227) avec les mêmes blocs.
 *
 * ⚠ LA CITATION CI-DESSUS EST CE QUI REND CE PORTAGE MESURABLE.
 * `prototype_v2/tests/t-trois-sources.js` n'entretient AUCUNE table de
 * correspondance : il ancre chaque page sur le commentaire qui la cite. Le
 * panneau existait depuis la vague M11 et la page apparaissait pourtant comme
 * NON PORTÉE — rien n'était comparé, ni son titre, ni ses contrôles. Le portage
 * était fait, la mesure ne le voyait pas.
 *
 * ECART DELIBERE — `m11-pilotage.html` l.51-59 (bandeau de compatibilité)
 * Le maître : un bandeau « Page conservée pour compatibilité » et un bouton
 * « Ouvrir le tableau de bord ».
 * Ici : ni l'un ni l'autre.
 * Raison : ce bandeau n'a de sens que sur une page qui SURVIT à sa propre
 * fusion — le maître garde le fichier pour qu'un favori ne tombe pas dans le
 * vide. La PWA n'a jamais eu de seconde URL de pilotage : il n'existe aucun
 * favori à rattraper, et un bandeau annonçant une redirection vers la page où
 * l'on se trouve déjà serait un contrôle inerte (Article 6).
 * Refus déclaré : maitre-refuse:m11-pilotage.html#page
 *
 * ## PLUS AUCUNE SECTION DE REFUS N'EST RENDUE — directive du 31/08/2026
 *
 * Le bas de page portait un panneau « Ce que cet écran ne fait pas, et
 * pourquoi » de dix entrées. Il est supprimé : ce qui ne peut pas être réel est
 * OMIS et déclaré ici, en jeton code. Les dix motifs ont été RELUS avant d'être
 * déplacés — un motif recopié sans être revérifié est exactement PA-144 — et
 * deux d'entre eux étaient devenus faux le jour même :
 *
 * ### 1. Les graphiques : le refus est LEVÉ, ils sont rendus
 *
 * ECART LEVÉ — `tableau-de-bord.html` l.120 (`graphique-ca`)
 * L'ancien motif disait « Chart.js n'est PAS vendorisé dans
 * `public/assets/js/vendor/` ». C'était vrai le matin et faux l'après-midi :
 * `public/assets/js/vendor/chart.umd.min.js` existe depuis le 31/08/2026, copié
 * à l'identique depuis `prototype_v2/assets/js/vendor/` (205 637 octets, le
 * fichier même que le maître charge). Le graphique « Chiffre d'affaires vs
 * Dépenses » est donc rendu comme au maître : `type: 'bar'`, deux jeux
 * (`#14213D` et `#C62828`), `borderRadius: 5`, légende en bas, axe Y en
 * milliers — `pages/tableau-de-bord.js` l.436-448.
 *
 * ⚠ LES DONNÉES NE CHANGENT PAS AVEC LE DESSIN. Chaque point vient de
 * `TableauDeBordService::serieMensuelle()`, exactement comme la bande
 * d'indicateurs (PA-121). Et le graphique n'apparaît QUE si la série a été lue :
 * `$series === null` rend la phrase « rien n'a été mesuré », jamais un canevas
 * vide — un graphique plat se lit comme une activité nulle, pas comme une
 * absence de mesure.
 *
 * ### 2. Les exports côté client du maître ne sont PAS copiés
 *
 * ECART DELIBERE — `tableau-de-bord.html` l.9-10 (`jspdf`, `xlsx`)
 * Le maître : deux bibliothèques chargées dans la page pour produire le PDF et
 * le classeur DANS le navigateur.
 * Ici : aucune des deux.
 * Raison : la PWA exporte côté SERVEUR — DomPDF (PA-47, pur PHP, cPanel
 * mutualisé interdit les binaires) et Maatwebsite/Excel, par `ouvrirExport()`
 * et `genererExport()`. Embarquer 1,2 Mo de bibliothèques qu'aucune ligne
 * n'appellerait serait du code mort servi à chaque chargement de page.
 * Refus déclaré : maitre-refuse:tableau-de-bord.html#exports-client
 *
 * ### 3. Les quatre graphiques : le refus est LEVÉ, ils sont rendus (02/09/2026)
 *
 * ECART LEVÉ — `tableau-de-bord.html` l.125 (`graphique-repartition`),
 * l.132 (`graphique-ventes`), et `m11-pilotage.html` l.98 (`graphe-centres`),
 * l.105 (`graphe-creances`)
 *
 * Le motif écrit le 31/08/2026 tenait en une phrase : « les quatre comptent une
 * grandeur que le serveur ne porte pas ». Repris au mot le 02/09/2026, il était
 * VRAI pour un quart, à moitié vrai pour un autre, et FAUX pour la moitié
 * restante. C'est précisément la forme de PA-144 : une raison datée, jamais
 * rouverte, qui transforme une décision en oubli.
 *
 * — « Réservations par activité » et « 📊 Statistiques de ventes par activité » :
 *   la mesure du maître — le nombre de réservations incluant chaque service —
 *   reste bien introuvable au schéma (PA-110). Mais une ventilation par
 *   activité, elle, EXISTE : `lignes_facture.source_module` (RG-04), déjà
 *   servie par `TableauDeBordService::ventilationParActivite()`. Les deux
 *   graphiques sont donc rendus, aux emplacements et aux types de tracé du
 *   maître (anneau, puis barres horizontales), et leur SOUS-TITRE dit la
 *   mesure réellement calculée — PA-49 appliqué à la lettre. UNE seule lecture
 *   alimente les deux tracés : deux agrégats parallèles finiraient par
 *   diverger (PA-121).
 * — « Marge sur coûts directs par activité » : le motif disait que les charges
 *   « ne portent aucun centre d'analyse au schéma ». FAUX —
 *   `ecritures_comptables.centre_id` est NOT NULL (RG-12), et
 *   `AnalytiqueService` produit exactement cette marge, jusqu'au sous-titre du
 *   maître, qui est le motif de son propre `ReadModel`
 *   (`charges_de_structure_non_reparties`). Le graphique appelle ce Service ;
 *   rien n'est recalculé ici.
 * — « Créances par ancienneté » : le motif disait « sans date d'échéance sur
 *   `factures`, et PA-20 laisse la balance âgée non arbitrée ». L'échéance
 *   manque en effet — c'est pourquoi l'âge est compté depuis
 *   `date_emission`, et l'écran LE DIT sous le graphique. PA-20 porte sur la
 *   POLITIQUE (relancer, provisionner, passer en perte), et aucune de ces trois
 *   décisions n'est prise ici : afficher des faits datés n'est pas trancher une
 *   politique, c'est ce qui permettra de la trancher. Le prédicat d'impayé
 *   vient de `SoldeClientService`, jamais réécrit.
 *
 * ### 4. Ce qui reste refusé, re-vérifié le 02/09/2026
 *
 * — badge « Réseau Synchronisé » : la PWA n'a AUCUNE pile hors ligne, elle lit
 *   le serveur en direct. Afficher « synchronisé » serait affirmer un état que
 *   personne ne vérifie (PA-61).
 * — le CHAMP « Canal de réservation » de la modale rapide : `reservations` ne
 *   porte aucun canal (PA-29). ⚠ LES COLONNES, ELLES, SONT DÉSORMAIS RENDUES
 *   avec un tiret — un tiret est un fait d'écran, il dit « rien à afficher »
 *   sans rien inventer. Un CHAMP de saisie, lui, promettrait un
 *   enregistrement : il jetterait la saisie en silence. La distinction n'est
 *   pas cosmétique, c'est celle entre une absence montrée et une absence
 *   masquée.
 * — colonne « Unité » du tableau des chambres : RENDUE avec un tiret, même
 *   raisonnement. `unites_hebergement` porte un seul identifiant, `numero`,
 *   déjà rendu en « Code » — le répéter sous un second en-tête laisserait
 *   croire à deux données.
 * — les cinq autres rapports du maître — « Liste des réservations », « État
 *   des stocks », « État de créances », « État de recettes », « État de
 *   ventes » : REFUS LEVÉ le 02/09/2026, voir §6 ci-dessous. Le motif tenait
 *   au RBAC du Studio des états (M14), toujours vrai pour un état SUR MESURE
 *   qui interroge n'importe quelle table — mais aucun des cinq ne le fait
 *   plus : chacun se construit désormais depuis une collection que CET écran
 *   a déjà lue, sous le droit qu'il a déjà vérifié pour l'afficher (PA-119).
 *
 * ### 5. Deux refus de plus sont LEVÉS, et la raison de chacun est datée
 *
 * — « meilleures ventes » : le motif disait « aucun Service de domaine ne la
 *   calcule ». Le registre `lignes_vente` porte `module`, `nom`, `quantite` et
 *   `montant`, alimenté par `VenteService` ; les quatre classements du maître
 *   sont rendus. ⚠ DEUX SUR QUATRE SONT STRUCTURELLEMENT VIDES et le disent :
 *   `VenteService::MODULES_ENCAISSABLES` ne contient que M4 et M5 — un
 *   encaissement de tourisme ou de location est refusé par le domaine faute de
 *   catalogue serveur. La carte est rendue avec son état vide, jamais omise :
 *   la retirer ferait croire que le classement n'existe pas.
 * — les quatre sélecteurs du tableau croisé : le motif disait « deux sources
 *   seulement sont servies, et les réservations ne portent AUCUN montant ».
 *   La première moitié était fausse — `lignes_vente`, `lignes_depense` et
 *   `reservations` existent tous trois. La seconde est vraie, et elle est
 *   CONSERVÉE là où elle compte : le montant d'une réservation est son
 *   ACOMPTE, seul montant que le schéma porte, et la note sous le tableau le
 *   dit. Les neuf axes et les quatre mesures du maître sont des registres
 *   FERMÉS ({@see self::AXES_CROISE}, {@see self::MESURES_CROISE}).
 *
 * Refus déclarés depuis cette classe :
 *   maitre-refuse:tableau-de-bord.html#reseau-synchronise
 *   maitre-refuse:tableau-de-bord.html#canal-rapide
 *
 * Les quatre autres vivent dans la VUE, à côté du code qu'ils décrivent —
 * `#exports-client`, `#services-canal`, `#unite-libelle` et les deux de
 * `m11-pilotage.html`. Les recopier ici en ferait deux listes, qui
 * divergeraient : c'est la liste de la vue qui fait foi pour ce qu'elle rend.
 *
 * ## §6 — LES SIX RAPPORTS DE LA MODALE (02/09/2026)
 *
 * `TYPES_RAPPORT` porte désormais les six clés du maître, dans son ordre
 * (`rapports-engine.js` l.56-189). `synthese` est inchangé. Les cinq autres
 * — `reservations`, `stocks`, `creances`, `recettes`, `ventes` — remplacent
 * `serie` et `activite`, qui ne figuraient même pas au registre du maître et
 * n'avaient donc rien à porter comme conformité. Chacun se construit depuis
 * une lecture QUE CET ÉCRAN A DÉJÀ FAITE pour se peindre lui-même :
 *
 * — `reservations` : la même requête que « Réservations du jour », bornée à
 *   la PÉRIODE sélectionnée plutôt qu'au seul jour courant — le maître filtre
 *   sur `date_debut`, l'équivalent serveur est `date_arrivee`.
 * — `stocks` : `articlesCritiques()`, déjà lue pour la bande d'alerte et la
 *   modale « Stocks critiques ». Le maître traite un stock comme un ÉTAT à
 *   l'instant, jamais filtré par période (`RAPPORTS_HORS_PERIODE`) — ce
 *   rapport ne l'est pas non plus.
 * — `creances` : `creancesParAnciennete()`, déjà lue pour le graphique du
 *   même nom — les quatre tranches, jamais une liste par client qu'aucun
 *   bloc de cet écran ne montre.
 * — `recettes` et `ventes` : `faitsCroises()`, déjà appelée par le tableau
 *   croisé — jamais un second agrégat des mêmes montants (PA-121).
 *
 * ⚠ Aucun des cinq n'exige de droit supplémentaire : chacun réutilise une
 * lecture déjà gardée par le droit de son module (M1, M6, M3) au moment où
 * elle a été construite pour la page. Un rôle qui ne verrait pas les
 * réservations du jour ne peut pas non plus exporter la liste des
 * réservations — la même collection, jamais recalculée sans son droit.
 *
 * ## « À TRAITER » LIT PLUSIEURS SOURCES, ET CHACUNE EST RÉELLE
 *
 * Le maître agrège dix alertes de sept moteurs (`m11-pilotage.js` l.150-200).
 * Le panneau n'en portait qu'UNE — le stock sous seuil — ce qui rendait
 * « Aucune alerte » sur un exercice comptable déséquilibré. Cinq familles sont
 * désormais lues, toutes par des Services existants : le déséquilibre et les
 * brouillons par `IndicateursComptablesService`, les créances par
 * `SoldeClientService`, les factures non soldées et les réservations à
 * confirmer par `TableauDeBordService`, le stock par `StockTheoriqueService`.
 *
 * ⚠ CHAQUE FAMILLE EST GARDÉE PAR LE DROIT DE SON MODULE, pas par M11. Lire un
 * déséquilibre comptable est une lecture M10 ; les créances, M3 ; le stock, M6.
 * Une alerte servie sans son droit rendrait par le panneau ce que l'écran du
 * module refuse — c'est la forme exacte du défaut corrigé sur les raccourcis.
 *
 * ⚠ ET UNE SOURCE NON CONSULTÉE N'EST JAMAIS « AUCUNE ALERTE ». Le panneau dit
 * combien de sources il a réellement lues : sans cette phrase, un rôle sans
 * droit M10 lirait « rien à traiter » sur une comptabilité en défaut.
 */
#[Title('Tableau de bord — TATACORA AFRIQUE')]
final class Accueil extends PageMetier
{
    use FormulaireModal;

    /**
     * Écrans exposés par la PWA — `LARAVEL_PWA.md` §2, liste FERMÉE.
     *
     * Toute addition est une extension de périmètre : la PWA n'expose pas
     * « les modules auxquels l'utilisateur a droit », elle expose un
     * sous-ensemble délibérément restreint. M10 y a été ajouté le 27/08/2026,
     * hors table du §2, et le libellé le dit (`lang/fr/pwa.php`).
     *
     * Seuls les codes module figurent ici : les libellés visibles vivent dans
     * `lang/fr/pwa.php` sous `pwa.ecrans.<module>` (06 §4.4). Les dupliquer
     * ici ferait diverger silencieusement le texte affiché de sa traduction —
     * c'est précisément ce que vérifie
     * `MessagesUtilisateurTest::chaque_ecran_expose_par_la_pwa_a_son_libelle_traduit`,
     * qui lit cette constante.
     *
     * ⚠ 31/08/2026 — `ecransVisibles()`, son seul consommateur applicatif,
     * avait disparu à une réécriture : la constante n'était plus lue que par la
     * garde i18n, c'est-à-dire du code mort déguisé en contrat. L'usage est
     * RÉTABLI (bloc « Consultation de secours » de l'onglet Exploitation), et
     * il filtre par droit réel — le maître filtre lui aussi ses cartes d'accès.
     *
     * @var array<int, string>
     */
    public const ECRANS_AUTORISES = ['M11', 'M1', 'M6', 'M2', 'M3', 'M14', 'M10'];

    /** Le module de l'écran — celui que porte le `data-module` du maître. */
    public const MODULE = 'M11';

    /** Module réellement écrit par la réservation rapide et les deux séjours. */
    public const MODULE_HEBERGEMENT = 'M1';

    /** Module réellement écrit par la création de client (PA-116). */
    public const MODULE_CLIENT = 'M3';

    /** Module réellement LU par la modale « Stocks critiques ». */
    public const MODULE_STOCKS = 'M6';

    /** Module réellement LU par la modale « Rapport » (moteur d'états). */
    public const MODULE_ETATS = 'M14';

    /** Module réellement LU par les alertes comptables du pilotage consolidé. */
    public const MODULE_COMPTABILITE = 'M10';

    /** Module réellement LU par le lien « Factures non soldées » du pilotage. */
    public const MODULE_FACTURATION = 'M2';

    /**
     * Module réellement LU par la carte « Masse salariale » du pilotage et
     * par la carte « Personnel & paie » du bloc « Par module » (02/09/2026).
     */
    public const MODULE_RH = 'M13';

    /**
     * Les trois fenêtres de la série du maître (`tableau-de-bord.html` l.114-116).
     *
     * Registre FERMÉ : `?mois=600` ferait exécuter 1 200 requêtes sur un
     * hébergement mutualisé, depuis une URL que n'importe qui compose.
     * `TableauDeBordService::MOIS_MAX` borne déjà côté service ; on ne s'en
     * remet pas à lui seul, parce que la borne du service dit « pas plus de
     * douze » quand celle-ci dit « ces trois-là, et pas d'autre ».
     *
     * @var array<int, int>
     */
    public const MOIS_SERIE = [3, 6, 12];

    /**
     * Les axes croisables — registre FERMÉ, portage de `croise-engine.js`
     * l.126-152.
     *
     * La clé est celle du maître ; la valeur est le nom du champ du FAIT, tel
     * que `faitsCroises()` le produit. Un axe sans champ ne peut pas exister,
     * donc aucun ne peut retomber silencieusement sur `null` — c'est la raison
     * que le maître écrit lui-même au-dessus de sa propre liste.
     *
     * ⚠ `mois` porte une CLÉ DE TRI distincte de son libellé (`tri_mois`) :
     * « août » précède « décembre » dans l'alphabet et le suit dans l'année.
     * Trier sur le libellé rendrait une chronologie fausse, et une courbe
     * fausse se lit exactement comme une vraie.
     *
     * @var array<string, string>
     */
    public const AXES_CROISE = [
        'source' => 'source',
        'module' => 'module',
        'activite' => 'activite',
        'libelle' => 'libelle',
        'tiers' => 'tiers',
        'mode' => 'mode',
        'jour' => 'jour',
        'mois' => 'mois',
        'aucun' => 'aucun',
    ];

    /**
     * Les quatre mesures du maître (`croise-engine.js` l.154-159).
     *
     * `true` = mesure monétaire (rendue en F CFA), `false` = un compte.
     *
     * @var array<string, bool>
     */
    public const MESURES_CROISE = [
        'montant' => true,
        'encaisse' => true,
        'quantite' => false,
        'nombre' => false,
    ];

    /**
     * Les trois registres de faits — fermés et justifiés source par source.
     *
     * ⚠ LES FACTURES SONT VOLONTAIREMENT ABSENTES, et c'est la décision la
     * plus importante de ce croisement : une facture est le DOCUMENT d'une
     * vente ou d'une réservation déjà comptée. L'ajouter doublerait chaque
     * montant — plausible, jamais rond, impossible à rapprocher de la caisse.
     * Le maître l'écrit en toutes lettres (`croise-engine.js` l.17-20) et son
     * paragraphe d'introduction le répète au lecteur.
     *
     * @var list<string>
     */
    public const SOURCES_CROISE = ['ventes', 'depenses', 'reservations'];

    /**
     * Les bornes des tranches d'ancienneté de créance, en JOURS.
     *
     * ⚠ CE N'EST PAS UN ARBITRAGE DE POLITIQUE DE RELANCE — PA-20 reste
     * OUVERTE, et rien ici ne la tranche. Ces bornes découpent des FAITS
     * DATÉS : l'âge d'une facture certifiée non soldée, compté depuis sa
     * `date_emission`. Le maître les affiche telles quelles
     * (`tableau-de-bord.html` l.211-214, « Au-delà de 90 jours, le
     * recouvrement devient incertain »). Ce que PA-20 laisse ouvert, c'est ce
     * qu'on FAIT d'une créance de 95 jours — relance, provision, passage en
     * perte —, et aucune de ces trois décisions n'est prise ici.
     *
     * @var list<int>
     */
    public const TRANCHES_CREANCES = [30, 60, 90];

    /**
     * Les quatre classements de « meilleures ventes » — `indicateurs-engine.js`
     * l.31-36, avec leurs modules et leur critère de tri.
     *
     * Le critère est ANNONCÉ à l'écran : un classement par quantité et un
     * classement par montant ne donnent pas le même ordre, et le lecteur doit
     * savoir lequel il regarde (le maître le dit aussi, l.706-708).
     *
     * @var array<string, array{modules: list<string>, tri: string}>
     */
    public const CLASSEMENTS_VENTES = [
        'food' => ['modules' => ['M4'], 'tri' => 'quantite'],
        'drinks' => ['modules' => ['M5'], 'tri' => 'quantite'],
        'circuit' => ['modules' => ['M9'], 'tri' => 'montant'],
        'location' => ['modules' => ['M8'], 'tri' => 'montant'],
    ];

    /** Nombre d'entrées par classement — `tableau-de-bord.js` l.685. */
    public const TOP_VENTES_LIMITE = 5;

    /**
     * Les SIX rapports du maître (`rapports-engine.js` l.56-189) — registre
     * fermé, désormais complet (02/09/2026).
     *
     * ## REFUS LEVÉ — le motif « RBAC du module source » ne tenait pas
     *
     * La version précédente n'en portait que trois (`synthese`, `serie`,
     * `activite`) — deux qui ne figurent même pas au maître — et refusait les
     * cinq autres au motif que « le moteur d'états applique le RBAC du module
     * SOURCE ». C'était vrai du Studio des états (M14), mais chacun des cinq
     * rapports manquants se construit ici depuis une collection QUE CET ÉCRAN
     * A DÉJÀ LUE, sous le droit qu'il a déjà vérifié pour l'afficher —
     * `reservationsDuJour()`/une variante bornée à la période (M1),
     * `articlesCritiques()` (M6), `creancesParAnciennete()` (M3),
     * `faitsCroises()` (déjà appelé par le tableau croisé). Aucun n'ouvre un
     * accès que la page n'offrait pas déjà : PA-119, appliqué au pied de la
     * lettre.
     *
     * ⚠ `stocks` et `creances` reprennent PA-119, pas les colonnes du maître.
     * `stocks` liste les articles SOUS LE SEUIL (ce que « Stocks critiques »
     * affiche déjà), pas tout le référentiel — le maître écrit lui-même
     * qu'un stock est un ÉTAT à l'instant, jamais filtré par période
     * (`RAPPORTS_HORS_PERIODE`). `creances` reprend les QUATRE TRANCHES
     * d'ancienneté déjà affichées au graphique, pas une liste par client — une
     * liste nominative n'est affichée nulle part sur cet écran, l'exporter
     * ouvrirait une donnée que la page ne montre pas.
     *
     * @var array<int, string>
     */
    public const TYPES_RAPPORT = ['synthese', 'reservations', 'stocks', 'creances', 'recettes', 'ventes'];

    /**
     * Les quatre types de client, valeur du SCHÉMA => clé de libellé du maître.
     *
     * ⚠ `clients.type_client` est un `enum('particulier','groupe','agence',
     * 'structure')`. Le maître écrit « Agence partenaire » : c'est le libellé,
     * jamais la valeur. Les confondre casse l'insertion.
     *
     * @var array<string, string>
     */
    public const TYPES_CLIENT = [
        'particulier' => 'accueil_pwa.modale_client.type_particulier',
        'groupe' => 'accueil_pwa.modale_client.type_groupe',
        'agence' => 'accueil_pwa.modale_client.type_agence',
        'structure' => 'accueil_pwa.modale_client.type_structure',
    ];

    /** Nombre d'articles critiques listés dans la modale — au-delà, on renvoie à M6. */
    public const PLAFOND_CRITIQUES = 50;

    #[Url(as: 'panel')]
    public string $onglet = 'exploitation';

    #[Url(as: 'periode')]
    public string $filtrePeriode = 'mois';

    #[Url(as: 'du')]
    public string $du = '';

    #[Url(as: 'au')]
    public string $au = '';

    #[Url(as: 'mois')]
    /** 3 mois par defaut, comme au maitre (rapport de conformite du
     * 01/09/2026 : son bouton actif au chargement est « 3 mois »). */
    public int $moisSerie = 3;

    // ---- Fiche client rapide (écriture M3) -------------------------------
    public string $clientNom = '';

    public string $clientPrenom = '';

    public string $clientTelephone = '';

    public string $clientType = 'particulier';

    // ---- Réservation rapide (écriture M1) --------------------------------
    public ?string $resaClientId = null;

    public ?string $resaUniteId = null;

    public string $resaDateArrivee = '';

    public int $resaNuits = 1;

    /** Canal OBLIGATOIRE, comme au maître : jusqu'au 24/08/2026 sa
     * réservation rapide écrivait « Physique » d'office, et les statistiques
     * par canal comptaient au comptoir ce qui venait de Booking. */
    public ?string $resaCanalId = null;

    /** Le client peut être CRÉÉ depuis la modale (demande du Product Owner,
     * 01/09/2026) — trois champs, ceux de la modale client du maître. */
    public bool $resaNouveauClient = false;

    public string $resaClientNom = '';

    public string $resaClientTelephone = '';

    public string $resaClientType = 'particulier';

    // ---- Séjour : check-in / check-out (écriture M1) ---------------------
    public ?string $sejourReservationId = null;

    /**
     * Check-in DEPUIS « Chambres disponibles » — écriture M1, réservation ET
     * séjour dans la même transaction (`tableau-de-bord.js` l.283-324 :
     * `modale-checkin-rapide`, client + nombre de nuits, rien d'autre).
     *
     * Champs SÉPARÉS de la réservation rapide ci-dessus, délibérément : ce
     * sont deux modales du maître, de formes différentes (celle-ci n'a ni
     * canal ni sélection d'unité, l'unité est déjà connue du clic). Les
     * fusionner mélangerait l'état de deux formulaires qui ne s'ouvrent
     * jamais ensemble, pour l'unique bénéfice de compter moins de propriétés.
     */
    public ?string $checkinUniteId = null;

    public int $checkinNuits = 1;

    public ?string $checkinClientId = null;

    public bool $checkinNouveauClient = false;

    public string $checkinClientNom = '';

    public string $checkinClientTelephone = '';

    public string $checkinClientType = 'particulier';

    // ---- Modale « Payer » (PA-165, 02/09/2026) — recouvrement de la
    // facture qui couvre une réservation du jour --------------------------

    public ?string $payerReservationId = null;

    public string $payerClientNom = '';

    public ?string $payerFactureId = null;

    public string $payerMontant = '';

    public string $payerMode = 'especes';

    // ---- Tableau croisé dynamique ----------------------------------------
    //
    // Quatre PROPRIÉTÉS, aucune méthode publique de plus : `wire:model.live`
    // suffit à recalculer le croisement, et chaque méthode publique ajoutée à
    // un composant PWA est une action de plus à relire (`PwaActionsReluesTest`).
    // Les valeurs par défaut sont celles du maître (`tableau-de-bord.js`
    // l.531-534 : lignes = activité, colonnes = mois).
    public string $croiseLigne = 'activite';

    public string $croiseColonne = 'mois';

    public string $croiseMesure = 'montant';

    /** @var array<int, string> */
    public array $croiseSources = self::SOURCES_CROISE;

    // ---- Rapport et export ------------------------------------------------
    public string $typeRapport = 'synthese';

    public string $formatExport = 'pdf';

    /**
     * Le registre FERMÉ des formulaires de l'écran.
     *
     * `stocks-critiques` n'y figure pas : c'est un panneau de LECTURE, ouvert
     * par `$set('etatFormulaire', …)` depuis la vue. L'inscrire ici exigerait
     * le droit d'écriture pour consulter une liste que la page affiche déjà.
     *
     * @return array<string, list<string>>
     */
    protected function formulaires(): array
    {
        return [
            'client' => ['clientNom', 'clientPrenom', 'clientTelephone', 'clientType'],
            'reservation' => [
                'resaClientId', 'resaUniteId', 'resaDateArrivee', 'resaNuits', 'resaCanalId',
                'resaNouveauClient', 'resaClientNom', 'resaClientTelephone', 'resaClientType',
            ],
            'checkin' => ['sejourReservationId'],
            'checkout' => ['sejourReservationId'],
            'checkin-chambre' => [
                'checkinUniteId', 'checkinNuits', 'checkinClientId', 'checkinNouveauClient',
                'checkinClientNom', 'checkinClientTelephone', 'checkinClientType',
            ],
            'payer' => [
                'payerReservationId', 'payerClientNom', 'payerFactureId', 'payerMontant', 'payerMode',
            ],
        ];
    }

    public function mount(): void
    {
        $this->resaDateArrivee = CarbonImmutable::today()->toDateString();
    }

    // =====================================================================
    // Ajouter un client — écriture M3
    // =====================================================================

    public function ouvrirClientRapide(): void
    {
        // Le droit du module RÉELLEMENT écrit : créer une fiche client est une
        // écriture M3, pas M11. `ouvrirFormulaire()` exige `self::MODULE`
        // (M11) — il ne dit rien de M3, et sans la ligne ci-dessous un rôle
        // sans M3 se verrait offrir un formulaire que l'enregistrement
        // refuserait, après la saisie.
        // LES DEUX DROITS, et ce n'est pas une redondance. Celui de
        // l'ECRAN (`self::MODULE`, M11) est exige par le motif de
        // formulaire ; il est ecrit ici EN TOUTES LETTRES pour que la
        // garde statique voie les deux modules sur la meme methode — un
        // droit implicite ne se relit pas. Celui du module REELLEMENT
        // ecrit vient ensuite : sans lui, le droit serait exige sur le
        // mauvais module et la garde passerait quand meme.
        $this->exigerEcriture(self::MODULE);

        $this->exigerEcriture(self::MODULE_CLIENT);

        $this->ouvrirFormulaire('client');
    }

    /**
     * RG-18 — la détection de doublon est AVERTISSANTE, jamais bloquante : elle
     * vit dans `EnregistrementClientService`. Bloquer pousserait à déformer
     * l'orthographe, recréant le doublon que la règle évite.
     *
     * ⚠ AUCUN TÉLÉPHONE FABRIQUÉ. Le motif `'0100000000'` a été retiré de M1 le
     * 31/08/2026 : il inscrivait un numéro inventé sur une fiche client réelle
     * — celui qu'on appellerait pour confirmer une arrivée.
     */
    public function enregistrerClientRapide(EnregistrementClientService $clients): void
    {
        // Le module RÉELLEMENT écrit, en plus de celui de l'écran que
        // `validerEcriture()` exige. Les deux, et pas l'un pour l'autre : la
        // synchronisation vérifie les droits PAR OPÉRATION (PA-65).
        // LES DEUX DROITS, et ce n'est pas une redondance. Celui de
        // l'ECRAN (`self::MODULE`, M11) est exige par le motif de
        // formulaire ; il est ecrit ici EN TOUTES LETTRES pour que la
        // garde statique voie les deux modules sur la meme methode — un
        // droit implicite ne se relit pas. Celui du module REELLEMENT
        // ecrit vient ensuite : sans lui, le droit serait exige sur le
        // mauvais module et la garde passerait quand meme.
        $this->exigerEcriture(self::MODULE);

        $this->exigerEcriture(self::MODULE_CLIENT);

        $donnees = $this->validerEcriture([
            'clientNom' => ['required', 'string', 'max:255'],
            'clientPrenom' => ['nullable', 'string', 'max:255'],
            'clientTelephone' => ['required', 'string', 'max:255'],
            'clientType' => ['required', 'in:'.implode(',', array_keys(self::TYPES_CLIENT))],
        ]);

        $resultat = $clients->creer([
            'nom' => $donnees['clientNom'],
            'prenom' => ($donnees['clientPrenom'] ?? '') === '' ? null : $donnees['clientPrenom'],
            'telephone' => $donnees['clientTelephone'],
            'type_client' => $donnees['clientType'],
        ]);

        $nom = $donnees['clientNom'];

        // La fiche créée est sélectionnée : c'est en général pour la
        // réservation qu'on vient de la créer.
        $this->resaClientId = $resultat['client']->id;

        $this->terminerFormulaire(
            $resultat['avertissement_doublon']
                ?? __('accueil_pwa.modale_client.succes', ['nom' => $nom]),
        );
    }

    // =====================================================================
    // Réservation rapide — écriture M1, RG-01 sous verrou
    // =====================================================================

    public function ouvrirReservationRapide(): void
    {
        // Écriture M1 : le droit de l'écran (M11) ne dit rien de l'hébergement.
        // LES DEUX DROITS, et ce n'est pas une redondance. Celui de
        // l'ECRAN (`self::MODULE`, M11) est exige par le motif de
        // formulaire ; il est ecrit ici EN TOUTES LETTRES pour que la
        // garde statique voie les deux modules sur la meme methode — un
        // droit implicite ne se relit pas. Celui du module REELLEMENT
        // ecrit vient ensuite : sans lui, le droit serait exige sur le
        // mauvais module et la garde passerait quand meme.
        $this->exigerEcriture(self::MODULE);

        $this->exigerEcriture(self::MODULE_HEBERGEMENT);

        $this->ouvrirFormulaire('reservation');

        $this->resaDateArrivee = CarbonImmutable::today()->toDateString();
        $this->resaNuits = 1;
    }

    /**
     * RG-01 — la garantie appartient à `ReservationService`, sous verrou
     * pessimiste et transaction. Un `Reservation::create()` posé ici
     * contournerait le verrou **sans lever la moindre erreur** : deux
     * réceptionnistes validant la même chambre passeraient tous les deux.
     *
     * Le client est une VRAIE clé étrangère choisie dans le référentiel : ni
     * nom tapé au clavier, ni téléphone fabriqué.
     *
     * Le conflit arrive comme une erreur de validation lisible et la modale
     * RESTE ouverte : fermer sur un refus ferait retaper les dates.
     */
    public function enregistrerReservationRapide(ReservationService $reservations): void
    {
        // Écriture M1, en plus du droit d'écran exigé par `validerEcriture()`.
        // LES DEUX DROITS, et ce n'est pas une redondance. Celui de
        // l'ECRAN (`self::MODULE`, M11) est exige par le motif de
        // formulaire ; il est ecrit ici EN TOUTES LETTRES pour que la
        // garde statique voie les deux modules sur la meme methode — un
        // droit implicite ne se relit pas. Celui du module REELLEMENT
        // ecrit vient ensuite : sans lui, le droit serait exige sur le
        // mauvais module et la garde passerait quand meme.
        $this->exigerEcriture(self::MODULE);

        $this->exigerEcriture(self::MODULE_HEBERGEMENT);

        // Créer la fiche client depuis la modale est une écriture M3, en plus
        // de M1 : la synchronisation vérifie les droits PAR OPÉRATION (PA-65),
        // et l'écran suit la même règle.
        if ($this->resaNouveauClient) {
            $this->exigerEcriture(self::MODULE_CLIENT);
        }

        $donnees = $this->validerEcriture([
            // Le client vient du référentiel OU des trois champs du maître —
            // jamais des deux, jamais d'aucun.
            'resaClientId' => $this->resaNouveauClient
                ? ['nullable']
                : ['required', 'uuid', 'exists:clients,id'],
            'resaClientNom' => $this->resaNouveauClient
                ? ['required', 'string', 'max:255']
                : ['nullable'],
            'resaClientTelephone' => $this->resaNouveauClient
                ? ['required', 'string', 'max:255']
                : ['nullable'],
            'resaClientType' => ['required', 'in:'.implode(',', array_keys(self::TYPES_CLIENT))],
            'resaUniteId' => ['required', 'uuid', 'exists:unites_hebergement,id'],
            // Obligatoire, comme au maître (`data-regle-requis` sur le champ) ;
            // un canal désactivé n'est plus proposable à la SAISIE.
            'resaCanalId' => ['required', 'uuid', 'exists:canaux_reservation,id'],
            'resaDateArrivee' => ['required', 'date'],
            // Bornes du maître : au moins une nuit, et le plafond évite qu'une
            // saisie à trois chiffres bloque une chambre jusqu'en 2030.
            'resaNuits' => ['required', 'integer', 'min:1', 'max:365'],
        ]);

        $arrivee = CarbonImmutable::parse((string) $donnees['resaDateArrivee']);

        try {
            // Client et réservation dans la MÊME transaction — la règle de
            // PA-116, côté serveur : si RG-01 refuse la chambre, le client
            // créé pour cette fiche est repris aussi. Sans cela, chaque
            // nouvel essai après conflit créerait un doublon de fiche.
            \Illuminate\Support\Facades\DB::transaction(function () use ($reservations, $donnees, $arrivee): void {
                $clientId = (string) ($donnees['resaClientId'] ?? '');

                if ($this->resaNouveauClient) {
                    // RG-18 : la détection de doublon AVERTIT, elle ne bloque
                    // pas — même service que la modale « Ajouter un client ».
                    $resultat = app(EnregistrementClientService::class)->creer([
                        'nom' => (string) $donnees['resaClientNom'],
                        'telephone' => (string) $donnees['resaClientTelephone'],
                        'type_client' => (string) $donnees['resaClientType'],
                    ]);

                    $clientId = $resultat['client']->id;
                }

                $reservations->creer([
                    'client_id' => $clientId,
                    'unite_id' => $donnees['resaUniteId'],
                    'canal_id' => $donnees['resaCanalId'],
                    'date_arrivee' => $arrivee->toDateString(),
                    'date_depart' => $arrivee->addDays((int) $donnees['resaNuits'])->toDateString(),
                ]);
            });
        } catch (ChevauchementDetecteException $conflit) {
            $this->addError('resaUniteId', $conflit->getMessage());

            return;
        }

        $this->terminerFormulaire(__('accueil_pwa.modale_reservation.succes'));
    }

    // =====================================================================
    // Check-in / check-out — écriture M1, `SejourService` et lui seul
    // =====================================================================

    public function ouvrirCheckinRapide(string $reservationId): void
    {
        // LES DEUX DROITS, et ce n'est pas une redondance. Celui de
        // l'ECRAN (`self::MODULE`, M11) est exige par le motif de
        // formulaire ; il est ecrit ici EN TOUTES LETTRES pour que la
        // garde statique voie les deux modules sur la meme methode — un
        // droit implicite ne se relit pas. Celui du module REELLEMENT
        // ecrit vient ensuite : sans lui, le droit serait exige sur le
        // mauvais module et la garde passerait quand meme.
        $this->exigerEcriture(self::MODULE);

        $this->exigerEcriture(self::MODULE_HEBERGEMENT);

        $this->ouvrirFormulaire('checkin');

        $this->sejourReservationId = Reservation::findOrFail($reservationId)->id;
    }

    /**
     * EF-M1-03 — `SejourService::checkin()` porte le verrou pessimiste sur la
     * réservation et l'écriture du cycle de l'unité. Écrire
     * `sejours.date_checkin_reel` à la main, comme le faisait la version
     * précédente, laisserait deux réceptionnistes créer deux séjours pour un
     * seul client — et `Sejour::estEnCours()` deviendrait indécidable.
     *
     * Le refus du service (réservation annulée, séjour déjà commencé, unité
     * hors service) est rendu comme une erreur de validation sur la modale,
     * jamais avalé.
     */
    public function confirmerCheckin(SejourService $sejours): void
    {
        // LES DEUX DROITS, et ce n'est pas une redondance. Celui de
        // l'ECRAN (`self::MODULE`, M11) est exige par le motif de
        // formulaire ; il est ecrit ici EN TOUTES LETTRES pour que la
        // garde statique voie les deux modules sur la meme methode — un
        // droit implicite ne se relit pas. Celui du module REELLEMENT
        // ecrit vient ensuite : sans lui, le droit serait exige sur le
        // mauvais module et la garde passerait quand meme.
        $this->exigerEcriture(self::MODULE);

        $this->exigerEcriture(self::MODULE_HEBERGEMENT);

        $donnees = $this->validerEcriture([
            'sejourReservationId' => ['required', 'uuid', 'exists:reservations,id'],
        ]);

        $reservation = Reservation::with('client')->findOrFail($donnees['sejourReservationId']);

        try {
            $sejours->checkin($reservation);
        } catch (RuntimeException $refus) {
            $this->addError('sejourReservationId', $refus->getMessage());

            return;
        }

        $this->terminerFormulaire(__('accueil_pwa.modale_checkin.succes', [
            'client' => $reservation->client?->nomComplet() ?? '',
        ]));
    }

    public function ouvrirCheckoutRapide(string $reservationId): void
    {
        // LES DEUX DROITS, et ce n'est pas une redondance. Celui de
        // l'ECRAN (`self::MODULE`, M11) est exige par le motif de
        // formulaire ; il est ecrit ici EN TOUTES LETTRES pour que la
        // garde statique voie les deux modules sur la meme methode — un
        // droit implicite ne se relit pas. Celui du module REELLEMENT
        // ecrit vient ensuite : sans lui, le droit serait exige sur le
        // mauvais module et la garde passerait quand meme.
        $this->exigerEcriture(self::MODULE);

        $this->exigerEcriture(self::MODULE_HEBERGEMENT);

        $this->ouvrirFormulaire('checkout');

        $this->sejourReservationId = Reservation::findOrFail($reservationId)->id;
    }

    /**
     * EF-M1-04 — l'unité passe en `nettoyage`, jamais en `libre` : elle n'est
     * pas prête à recevoir tant que le ménage n'est pas fait. C'est
     * `SejourService` qui le décide, pas cet écran.
     */
    public function confirmerCheckout(SejourService $sejours): void
    {
        // LES DEUX DROITS, et ce n'est pas une redondance. Celui de
        // l'ECRAN (`self::MODULE`, M11) est exige par le motif de
        // formulaire ; il est ecrit ici EN TOUTES LETTRES pour que la
        // garde statique voie les deux modules sur la meme methode — un
        // droit implicite ne se relit pas. Celui du module REELLEMENT
        // ecrit vient ensuite : sans lui, le droit serait exige sur le
        // mauvais module et la garde passerait quand meme.
        $this->exigerEcriture(self::MODULE);

        $this->exigerEcriture(self::MODULE_HEBERGEMENT);

        $donnees = $this->validerEcriture([
            'sejourReservationId' => ['required', 'uuid', 'exists:reservations,id'],
        ]);

        $sejour = Sejour::where('reservation_id', $donnees['sejourReservationId'])
            ->whereNull('date_checkout_reel')
            ->first();

        if ($sejour === null) {
            $this->addError('sejourReservationId', __('sejour.deja_parti', ['date' => '']));

            return;
        }

        try {
            $sejours->checkout($sejour);
        } catch (RuntimeException $refus) {
            $this->addError('sejourReservationId', $refus->getMessage());

            return;
        }

        $this->terminerFormulaire(__('accueil_pwa.modale_checkout.succes'));
    }

    // =====================================================================
    // Check-in DEPUIS « Chambres disponibles » — écriture M1 (+ M3 si client
    // créé), réservation ET séjour dans la MÊME transaction
    // =====================================================================

    /**
     * `tableau-de-bord.js` l.284-294 (`ouvrirCheckinRapide(idUnite)`) — le
     * bouton VERT de la table « Chambres disponibles », jamais celui de
     * « Réservations du jour » (qui n'en a pas au maître).
     */
    public function ouvrirCheckinDepuisChambre(string $uniteId): void
    {
        // LES DEUX DROITS, et ce n'est pas une redondance. Celui de
        // l'ECRAN (`self::MODULE`, M11) est exige par le motif de
        // formulaire ; il est ecrit ici EN TOUTES LETTRES pour que la
        // garde statique voie les deux modules sur la meme methode — un
        // droit implicite ne se relit pas. Celui du module REELLEMENT
        // ecrit vient ensuite : sans lui, le droit serait exige sur le
        // mauvais module et la garde passerait quand meme.
        $this->exigerEcriture(self::MODULE);

        $this->exigerEcriture(self::MODULE_HEBERGEMENT);

        $this->ouvrirFormulaire('checkin-chambre');

        $this->checkinUniteId = UniteHebergement::findOrFail($uniteId)->id;
        $this->checkinNuits = 1;
    }

    /**
     * Crée la réservation du jour ET enregistre l'arrivée dans la MÊME
     * transaction — un client qui se présente au comptoir sans réservation
     * préalable n'en a jamais eu, et créer l'une sans l'autre laisserait soit
     * une chambre réservée mais vide (personne n'a pointé), soit un séjour
     * sans réservation qui le porte.
     *
     * RG-01 reste sous le verrou de `ReservationService` — ce chemin ne
     * contourne rien : c'est la même fabrique que la réservation rapide.
     */
    public function confirmerCheckinDepuisChambre(
        ReservationService $reservations,
        SejourService $sejours,
    ): void {
        // LES DEUX DROITS, et ce n'est pas une redondance. Celui de
        // l'ECRAN (`self::MODULE`, M11) est exige par le motif de
        // formulaire ; il est ecrit ici EN TOUTES LETTRES pour que la
        // garde statique voie les deux modules sur la meme methode — un
        // droit implicite ne se relit pas. Celui du module REELLEMENT
        // ecrit vient ensuite : sans lui, le droit serait exige sur le
        // mauvais module et la garde passerait quand meme.
        $this->exigerEcriture(self::MODULE);

        $this->exigerEcriture(self::MODULE_HEBERGEMENT);

        // Créer la fiche client depuis la modale est une écriture M3, en plus
        // de M1 : la synchronisation vérifie les droits PAR OPÉRATION (PA-65).
        if ($this->checkinNouveauClient) {
            $this->exigerEcriture(self::MODULE_CLIENT);
        }

        $donnees = $this->validerEcriture([
            'checkinUniteId' => ['required', 'uuid', 'exists:unites_hebergement,id'],
            'checkinClientId' => $this->checkinNouveauClient
                ? ['nullable']
                : ['required', 'uuid', 'exists:clients,id'],
            'checkinClientNom' => $this->checkinNouveauClient
                ? ['required', 'string', 'max:255']
                : ['nullable'],
            'checkinClientTelephone' => $this->checkinNouveauClient
                ? ['required', 'string', 'max:255']
                : ['nullable'],
            'checkinClientType' => ['required', 'in:'.implode(',', array_keys(self::TYPES_CLIENT))],
            'checkinNuits' => ['required', 'integer', 'min:1', 'max:365'],
        ]);

        $arrivee = CarbonImmutable::today();

        try {
            DB::transaction(function () use ($reservations, $sejours, $donnees, $arrivee): void {
                $clientId = (string) ($donnees['checkinClientId'] ?? '');

                if ($this->checkinNouveauClient) {
                    // RG-18 : la détection de doublon AVERTIT, elle ne bloque
                    // pas — même service que les deux autres modales client.
                    $resultat = app(EnregistrementClientService::class)->creer([
                        'nom' => (string) $donnees['checkinClientNom'],
                        'telephone' => (string) $donnees['checkinClientTelephone'],
                        'type_client' => (string) $donnees['checkinClientType'],
                    ]);

                    $clientId = $resultat['client']->id;
                }

                // Canal « Physique », comme le maître le fait pour CE geste
                // précis (`tableau-de-bord.js` l.312 : `canal: 'Physique'`) —
                // un client qui se présente sans réservation n'est venu par
                // aucun canal de démarchage. Sélection par LIBELLÉ EXACT,
                // jamais `LIKE` (règle du dépôt) ; `canal_id` est NULLABLE
                // (PA-163) : un référentiel non semé ne bloque pas le geste,
                // il laisse simplement le canal absent, comme une fiche
                // antérieure à PA-163.
                $canal = CanalReservation::where('nom', 'Physique')->first();

                $reservation = $reservations->creer([
                    'client_id' => $clientId,
                    'unite_id' => $donnees['checkinUniteId'],
                    'canal_id' => $canal?->id,
                    'date_arrivee' => $arrivee->toDateString(),
                    'date_depart' => $arrivee->addDays((int) $donnees['checkinNuits'])->toDateString(),
                ]);

                $sejours->checkin($reservation);
            });
        } catch (ChevauchementDetecteException $conflit) {
            $this->addError('checkinUniteId', $conflit->getMessage());

            return;
        } catch (RuntimeException $refus) {
            $this->addError('checkinUniteId', $refus->getMessage());

            return;
        }

        $this->terminerFormulaire(__('accueil_pwa.modale_checkin_chambre.succes'));
    }

    // =====================================================================
    // « Payer » (PA-165, 02/09/2026) — écriture M2 depuis M11
    // =====================================================================

    /**
     * `tableau-de-bord.js` l.342 (« Payer ») — REND désormais réellement,
     * quand une facture FIGÉE non soldée couvre la réservation (lignes de
     * source M1). Le jeton `maitre-refuse:tableau-de-bord.html#bouton-payer`
     * est retiré : PA-21 est levée par `EncaissementFactureService`, premier
     * writer de `paiements` (02/09/2026).
     */
    public function ouvrirRecouvrementDuJour(string $reservationId): void
    {
        // LES DEUX DROITS, et ce n'est pas une redondance. Celui de
        // l'ECRAN (`self::MODULE`, M11) est exige par le motif de
        // formulaire ; il est ecrit ici EN TOUTES LETTRES pour que la
        // garde statique voie les deux modules sur la meme methode — un
        // droit implicite ne se relit pas. Celui du module REELLEMENT
        // ecrit vient ensuite : sans lui, le droit serait exige sur le
        // mauvais module et la garde passerait quand meme.
        $this->exigerEcriture(self::MODULE);

        $this->exigerEcriture(self::MODULE_FACTURATION);

        $reservation = Reservation::with('client')->findOrFail($reservationId);
        $facture = $this->factureAPayer($reservation);

        if ($facture === null) {
            $this->addError('payerReservationId', __('accueil_pwa.modale_payer.aucune_facture'));

            return;
        }

        $this->ouvrirFormulaire('payer');

        $this->payerReservationId = $reservation->id;
        $this->payerClientNom = $reservation->client?->nomComplet() ?? '';
        $this->payerFactureId = $facture->id;
        $this->payerMontant = $facture->resteDu();
        $this->payerMode = 'especes';
    }

    /**
     * ⚠ Le refus du Service est AFFICHÉ tel quel, jamais avalé — un
     * sur-encaissement REFUSÉ doit rester lisible, modale ouverte
     * (PA-59/60/61).
     */
    public function confirmerRecouvrementDuJour(EncaissementFactureService $encaissements): void
    {
        // LES DEUX DROITS, et ce n'est pas une redondance. Celui de
        // l'ECRAN (`self::MODULE`, M11) est exige par le motif de
        // formulaire ; il est ecrit ici EN TOUTES LETTRES pour que la
        // garde statique voie les deux modules sur la meme methode — un
        // droit implicite ne se relit pas. Celui du module REELLEMENT
        // ecrit vient ensuite : sans lui, le droit serait exige sur le
        // mauvais module et la garde passerait quand meme.
        $this->exigerEcriture(self::MODULE);

        $this->exigerEcriture(self::MODULE_FACTURATION);

        $donnees = $this->validerEcriture([
            'payerFactureId' => ['required', 'uuid', 'exists:factures,id'],
            'payerMontant' => ['required', 'numeric', 'gt:0'],
            'payerMode' => ['required', 'in:'.implode(',', array_keys(EncaissementFactureService::TRESORERIE_PAR_MODE))],
        ]);

        $facture = Facture::findOrFail((string) $donnees['payerFactureId']);

        try {
            $encaissements->encaisser(
                $facture,
                (string) $donnees['payerMontant'],
                (string) $donnees['payerMode'],
            );
        } catch (RuntimeException $refus) {
            $this->addError('payerMontant', $refus->getMessage());

            return;
        }

        $this->terminerFormulaire(__('accueil_pwa.modale_payer.succes', ['client' => $this->payerClientNom]));
    }

    /**
     * La facture FIGÉE et NON SOLDÉE qui couvre cette réservation, ou
     * `null`. `LigneFacture` porte le couple `(source_module, source_id)`
     * qui relie une facture à la réservation qu'elle facture (RG-04) —
     * même lien que `PosHeberges::dejaFacture()`.
     */
    private function factureAPayer(Reservation $reservation): ?Facture
    {
        $factureId = LigneFacture::query()
            ->where('source_module', self::MODULE_HEBERGEMENT)
            ->where('source_id', $reservation->id)
            ->value('facture_id');

        if ($factureId === null) {
            return null;
        }

        $facture = Facture::find($factureId);

        if ($facture === null || ! $facture->estFigee() || $facture->estSoldee()) {
            return null;
        }

        return $facture;
    }

    // =====================================================================
    // Fermeture des modales — état d'interface, aucune table touchée
    // =====================================================================

    public function fermerModales(): void
    {
        $this->etatFormulaire = null;
        $this->resetValidation();
    }

    // =====================================================================
    // Export et rapport — AUCUN droit d'écriture exigé (31/08/2026)
    // =====================================================================

    /**
     * Un export ne produit rien de neuf : il rend, sur un autre papier, des
     * données que l'utilisateur a déjà sous les yeux. Exiger le niveau `C`
     * retirerait la fonction à tous les rôles en lecture — et le droit de LIRE
     * est déjà porté par la route.
     *
     * ⚠ Aucune de ces méthodes ne doit archiver sa propre sortie : le jour où
     * elle le ferait, elle redeviendrait une écriture et
     * `PwaEcritureAutoriseeTest` le dirait.
     */
    public function ouvrirExport(string $format = 'pdf'): void
    {
        $this->formatExport = in_array($format, ['pdf', 'excel'], true) ? $format : 'pdf';
        $this->etatFormulaire = 'export';
    }

    /**
     * PA-119 — l'export porte sur CE QUI EST AFFICHÉ, et il DIT son filtre.
     * Une liste vide se REFUSE : elle ne produit pas une page blanche que le
     * comptable prendrait pour un registre vide.
     */
    public function genererExport(TableauDeBordService $service): BinaryFileResponse|StreamedResponse|null
    {
        $periode = $this->periode();
        $type = in_array($this->typeRapport, self::TYPES_RAPPORT, true)
            ? $this->typeRapport
            : 'synthese';

        $lignes = $this->lignesRapport($service, $type, $periode);

        if ($lignes === []) {
            // PA-119 — une liste vide se REFUSE. La modale RESTE ouverte et
            // porte l'erreur : un fichier vide serait pris pour un registre
            // vide, et personne ne saurait qu'il n'a rien été mesuré.
            $this->addError('typeRapport', __('accueil_pwa.modale_rapport.vide'));

            return null;
        }

        $this->etatFormulaire = null;

        return $this->formatExport === 'excel'
            ? $this->exporterExcel($lignes, $type, $periode)
            : $this->exporterPdf($lignes, $type, $periode);
    }

    // =====================================================================
    // Les écrans de consultation — RG-16, 1ᵉʳ niveau (masquage d'interface)
    // =====================================================================

    /**
     * Les sept écrans de `ECRANS_AUTORISES`, filtrés par le droit RÉEL.
     *
     * Un écran sans droit est ABSENT, jamais grisé : lister un écran qu'on ne
     * peut pas ouvrir renseigne sur la structure interne du système sans aucun
     * bénéfice. Le niveau vient de `User::niveauSurModule()`, la même source
     * que le middleware `module:` — jamais un second calcul.
     *
     * @return list<array{module: string, libelle: string, description: string, niveau: string, url: string|null}>
     */
    public function ecransVisibles(): array
    {
        /** @var User|null $utilisateur */
        $utilisateur = Auth::user();

        if ($utilisateur === null || ! $utilisateur->estActif()) {
            return [];
        }

        $routes = [
            'M11' => 'pwa.accueil',
            'M1' => 'pwa.hebergement',
            'M6' => 'pwa.stocks.liste',
            'M2' => 'pwa.facturation',
            'M3' => 'pwa.clients',
            'M14' => 'pwa.etats.studio',
            'M10' => 'pwa.comptabilite.hub',
        ];

        $ecrans = [];

        foreach (self::ECRANS_AUTORISES as $module) {
            $niveau = $utilisateur->niveauSurModule($module);

            if ($niveau === '-') {
                continue;
            }

            // Le registre couvre les sept modules de `ECRANS_AUTORISES` : y
            // ajouter un module sans sa route ferait rougir l'analyse statique,
            // ce qui vaut mieux qu'un `?? null` silencieux.
            $route = $routes[$module];

            $ecrans[] = [
                'module' => $module,
                'libelle' => (string) __('pwa.ecrans.'.$module.'.libelle'),
                'description' => (string) __('pwa.ecrans.'.$module.'.description'),
                'niveau' => $niveau,
                // Un lien mort promettrait une page qui n'existe pas : l'entrée
                // est rendue inerte et le dit (`pwa.accueil.ecran_a_venir`).
                'url' => Route::has($route) ? route($route) : null,
            ];
        }

        return $ecrans;
    }

    // =====================================================================
    // Rendu
    // =====================================================================

    public function render(
        TableauDeBordService $service,
        DisponibiliteService $disponibilites,
        SoldeClientService $soldes,
    ): View {
        $periode = $this->periode();

        // ⚠ LE SEUL `catch` DE CE FICHIER, ET IL NE REMPLACE AUCUN CHIFFRE.
        //
        // `indicateurs()` exécute quatorze agrégations sur huit domaines. Une
        // seule en défaut emporterait la page entière ; un chiffre de repli la
        // ferait mentir. La bande est donc rendue VIDE, avec la phrase qui dit
        // que rien n'a été mesuré. Ce chemin est réellement exécuté par un
        // test qui lie un service en échec — une branche de secours jamais
        // empruntée est exactement PA-59/60/61.
        $indicateurs = null;
        $series = null;
        $ventilation = null;
        $occupation = null;

        // ⚠ LE DROIT SE VERIFIE AVANT LE CALCUL, PAS A L'AFFICHAGE.
        //
        // Calculer puis masquer laisserait les quatorze agrégations s'exécuter
        // pour un rôle qui n'y a pas droit : les chiffres existeraient dans la
        // réponse Livewire (l'instantané est sérialisé au client) avant même
        // qu'une vue décide de ne pas les peindre. Le seul masquage qui vaut
        // est celui qui ne produit pas la donnée.
        $tableauDeBordAutorise = $this->peutLire(self::MODULE);

        if ($tableauDeBordAutorise) {
            try {
                $indicateurs = $service->indicateurs($periode);
                $series = $service->serieMensuelle($this->moisSerieBornee(), ExerciceConsulte::reference());
                $ventilation = $service->ventilationParActivite($periode);
                $occupation = $service->tauxOccupation($periode);
            } catch (\Throwable $echec) {
                // Le message technique ne va PAS à l'écran : il fuiterait du SQL.
                report($echec);
            }
        }

        $aujourdhui = CarbonImmutable::today();

        // Lu UNE fois, servi deux fois : le tableau « Réservations du jour »
        // ET le calcul du bouton « Payer » (PA-165), qui a besoin de la MÊME
        // collection — jamais une seconde requête pour la même journée.
        $reservationsDuJour = $this->reservationsDuJour($aujourdhui);

        // M6 : la modale « Stocks critiques » liste des articles sous seuil.
        // Sans droit de lecture sur M6, elle n'est pas offerte et la liste
        // n'est pas construite. Calculée UNE fois : le panneau « À traiter » et
        // la modale lisent la même collection, jamais deux requêtes.
        $articlesCritiques = $this->peutLire(self::MODULE_STOCKS) ? $this->articlesCritiques() : collect();

        $creances = $soldes->totaux();

        // M10 : lu UNE fois, servi deux fois — au panneau « À traiter » et à la
        // carte « Résultat net » du pilotage. `genererPourExercice()` produit
        // la balance, le compte de résultat ET le bilan de l'exercice : le
        // rappeler pour la seconde carte doublerait trois agrégations
        // complètes, et deux lectures du même exercice à quelques
        // millisecondes d'écart pourraient rendre deux chiffres.
        $comptables = $tableauDeBordAutorise && $this->peutLire(self::MODULE_COMPTABILITE)
            ? $this->indicateursComptables()
            : null;

        // « À traiter » n'est construit que pour qui a droit au pilotage : ses
        // entrées agrègent des lectures de quatre modules, exactement comme la
        // bande d'indicateurs. Le droit se vérifie AVANT le calcul.
        $aTraiter = $tableauDeBordAutorise
            ? $this->alertesPilotage($comptables, $indicateurs, $creances, $articlesCritiques)
            : ['alertes' => [], 'sources' => 0, 'sourcesPossibles' => 0];

        // ---- Les blocs ajoutés le 02/09/2026 pour suivre le maître ---------
        //
        // Chacun est calculé APRÈS son contrôle de droit, jamais rendu puis
        // masqué : l'instantané Livewire est sérialisé au client, et une
        // donnée calculée existe dans la réponse avant qu'une vue décide de
        // ne pas la peindre.
        $margeActivite = $tableauDeBordAutorise && $this->peutLire(self::MODULE_COMPTABILITE)
            ? $this->margeParActivite()
            : null;

        $creancesAnciennete = $tableauDeBordAutorise && $this->peutLire(self::MODULE_CLIENT)
            ? $this->creancesParAnciennete()
            : null;

        // « Masse salariale » (carte 6 du pilotage) et la carte « Personnel &
        // paie » du bloc « Par module » — REFUS LEVÉ le 02/09/2026 : l'ancien
        // motif confondait la MASSE SALARIALE (somme des bruts, un fait) et le
        // COÛT EMPLOYEUR TOTAL (une fourchette, PA-53). `LivreDePaieService::
        // totaux()` sépare déjà les deux — `brut` est un chiffre réel,
        // `cout_min`/`cout_max` restent une fourchette, jamais un total unique.
        $paie = $tableauDeBordAutorise && $this->peutLire(self::MODULE_RH)
            ? $this->totauxPaie()
            : null;

        // « Par module » — les neuf cartes du maître (directive du
        // 02/09/2026), construites APRÈS les lectures qu'elles réutilisent
        // ($indicateurs, $creances, $comptables, $paie, $articlesCritiques)
        // et chacune derrière le droit de SON module, vérifié avant tout
        // calcul.
        $cartesModules = $tableauDeBordAutorise
            ? $this->cartesParModule(
                $periode,
                $indicateurs,
                $creances,
                $creancesAnciennete,
                $comptables,
                $paie,
                $articlesCritiques,
                $soldes,
            )
            : [];

        return view('pwa.livewire.accueil', array_merge($this->socle(), [
            'module' => self::MODULE,
            'periode' => $periode,
            // Le récapitulatif nomme des ARRIVÉES et des DÉPARTS : ce sont des
            // données M1, et l'encaissement du jour une donnée consolidée M11.
            // Les deux droits, pas l'un pour l'autre.
            'recapJour' => $tableauDeBordAutorise && $this->peutLire(self::MODULE_HEBERGEMENT)
                ? $this->recapDuJour($aujourdhui)
                : null,
            'margeActivite' => $margeActivite,
            'creancesAnciennete' => $creancesAnciennete,
            'paie' => $paie,
            'cartesModules' => $cartesModules,
            'topVentes' => $tableauDeBordAutorise ? $this->meilleuresVentes($periode) : [],
            'croise' => $tableauDeBordAutorise ? $this->croiser($periode) : null,
            'croiseSourcesRetenues' => $this->sourcesCroiseValides(),
            'periodeRefusee' => $this->periodeRefusee(),
            'indicateurs' => $indicateurs,
            'series' => $series,
            'ventilation' => $ventilation,
            'occupation' => $occupation,
            'creances' => $creances,
            'comptables' => $comptables,
            'aTraiter' => $aTraiter,
            'reservationsDuJour' => $reservationsDuJour,
            'sejoursEnCours' => $this->sejoursEnCours(),
            'chambresDisponibles' => $this->chambresDisponibles($disponibilites, $aujourdhui),
            'articlesCritiques' => $articlesCritiques,
            'clients' => Client::query()->orderBy('nom')->orderBy('id')->get(),
            'canaux' => CanalReservation::proposables(),
            'unitesLibres' => $this->unitesPourReservation($disponibilites),
            'reservationSejour' => $this->reservationSejour(),
            'checkinUnite' => $this->checkinUnite(),
            // Les réservations du jour dont une facture FIGÉE non soldée
            // couvre le séjour — le bouton « Payer » ne se rend QUE pour
            // celles-là (id de réservation => id de facture).
            'facturesAPayer' => $reservationsDuJour
                ->mapWithKeys(fn (Reservation $r): array => [$r->id => $this->factureAPayer($r)?->id])
                ->filter(),
            'peutEncaisser' => $this->peutEcrire(self::MODULE_FACTURATION),
            'ecrans' => $this->ecransVisibles(),
            'peutEcrireHebergement' => $this->peutEcrire(self::MODULE_HEBERGEMENT),
            'peutEcrireClient' => $this->peutEcrire(self::MODULE_CLIENT),

            // Le pilotage M11 et les deux raccourcis qui lisent d'AUTRES
            // modules. `articlesCritiques()` lit M6 et le rapport passe par le
            // moteur d'états (M14) : les offrir sans droit rendrait la donnée
            // par la modale, là où l'écran vient de la retirer de la page.
            'tableauDeBordAutorise' => $tableauDeBordAutorise,
            'ongletAffiche' => $tableauDeBordAutorise ? $this->onglet : 'exploitation',
            'peutLireStocks' => $this->peutLire(self::MODULE_STOCKS),
            'peutLireEtats' => $this->peutLire(self::MODULE_ETATS),
            'peutLireHebergement' => $this->peutLire(self::MODULE_HEBERGEMENT),
        ]))->layout('layouts.pwa', [
            'module' => self::MODULE,
            // Le titre d'onglet suit le titre de la page : annoncer « Tableau
            // de bord » a un role qui n'a pas M11 nommerait un ecran qu'il ne
            // recoit pas.
            'title' => $tableauDeBordAutorise
                ? __('accueil_pwa.titre_page')
                : __('pwa.accueil.titre').' — '.__('pwa.marque'),
        ]);
    }

    // =====================================================================
    // Période — A3 : refusée ET nommée, jamais 500, jamais un repli muet
    // =====================================================================

    /**
     * La période demandée, ou celle par défaut quand le code n'existe pas.
     *
     * `Periode::resoudre()` REFUSE tout code inconnu — c'est son contrat, et il
     * est juste : un repli silencieux ferait afficher les chiffres du mois sous
     * le libellé d'une période demandée pour tout autre chose. Mais le code
     * arrive ici d'une propriété `#[Url]` : `?periode=ce_siecle` produisait un
     * **500** sur une URL que n'importe qui compose. Le code est donc validé
     * contre le registre fermé `CODES_CALENDAIRES` — exposé pour cela — et le
     * repli est DIT à l'écran (`periodeRefusee()`), jamais tu.
     */
    private function periode(): Periode
    {
        // Sélecteur d'exercice global (PO, 20/10/2026) : les périodes
        // relatives se calculent dans l'exercice CONSULTÉ, et une période
        // personnalisée y est bornée.
        [$du, $au] = $this->bornerAExercice($this->du, $this->au);

        return Periode::resoudre($this->codePeriodeValide(), $du, $au, ExerciceConsulte::reference());
    }

    /**
     * Les dates saisies, ramenées dans l'exercice consulté (une date vide
     * reste vide : la période personnalisée n'est pas encore saisie).
     *
     * @return array{0: string, 1: string}
     */
    private function bornerAExercice(string $du, string $au): array
    {
        $bornes = ExerciceConsulte::bornes();
        if ($bornes === null || $du === '' || $au === '') {
            return [$du, $au];
        }

        $premier = $bornes[0]->toDateString();
        $dernier = $bornes[1]->subDay()->toDateString();

        return [max($premier, min($dernier, $du)), max($premier, min($dernier, $au))];
    }

    private function codePeriodeValide(): string
    {
        return in_array($this->filtrePeriode, Periode::CODES_CALENDAIRES, true)
            ? $this->filtrePeriode
            : 'mois';
    }

    /** Le code refusé, ou `null` quand la demande a été comprise. */
    private function periodeRefusee(): ?string
    {
        return $this->filtrePeriode === $this->codePeriodeValide()
            ? null
            : $this->filtrePeriode;
    }

    private function moisSerieBornee(): int
    {
        return in_array($this->moisSerie, self::MOIS_SERIE, true) ? $this->moisSerie : 6;
    }

    // =====================================================================
    // Lectures d'écran
    // =====================================================================

    /**
     * Les réservations qui couvrent aujourd'hui — bornes semi-ouvertes, comme
     * RG-01 : une réservation qui part aujourd'hui n'occupe plus la nuit.
     *
     * @return EloquentCollection<int, Reservation>
     */
    private function reservationsDuJour(CarbonImmutable $jour): EloquentCollection
    {
        return Reservation::query()
            // `with()` : sans lui, la colonne « Client » ferait une requête par
            // ligne du tableau. `canal` et `lignes` alimentent les colonnes
            // du maître, rendues depuis PA-163.
            ->with(['client', 'unite.categorie', 'canal', 'lignes'])
            ->whereNot('statut', 'annulee')
            ->whereDate('date_arrivee', '<=', $jour->toDateString())
            ->whereDate('date_depart', '>', $jour->toDateString())
            ->orderBy('date_arrivee')
            ->orderBy('id')
            ->get();
    }

    /**
     * Les réservations dont le séjour est OUVERT — check-in fait, check-out pas
     * encore. Source : `sejours`, jamais `unites_hebergement.statut`, qui dit
     * qu'une chambre est occupée sans dire par qui (docblock `SejourService`).
     *
     * @return Collection<int, string> identifiants de réservation
     */
    private function sejoursEnCours(): Collection
    {
        return Sejour::query()
            ->whereNull('date_checkout_reel')
            ->pluck('reservation_id');
    }

    /**
     * Les unités libres CETTE NUIT — calculées, jamais lues dans une colonne.
     *
     * ⚠ `unites_hebergement.statut` n'est PAS la disponibilité (RG-02, et le
     * docblock du modèle l'écrit). La version précédente faisait
     * `where('statut', 'Libre')` — avec un L majuscule que l'`enum` ne contient
     * pas, et qui ne « marchait » que par la collation insensible à la casse de
     * MySQL. Elle aurait de toute façon répondu faux : une chambre libre ce
     * soir mais réservée demain n'est pas « occupée ».
     *
     * @return Collection<int, UniteHebergement>
     */
    private function chambresDisponibles(
        DisponibiliteService $disponibilites,
        CarbonImmutable $jour,
    ): Collection {
        return $this->avecCategorie(
            $disponibilites->unitesDisponibles(
                $jour->toDateString(),
                $jour->addDay()->toDateString(),
            ),
        );
    }

    /**
     * Les unités libres sur la période saisie dans la modale de réservation.
     *
     * @return Collection<int, UniteHebergement>
     */
    private function unitesPourReservation(DisponibiliteService $disponibilites): Collection
    {
        if ($this->etatFormulaire !== 'reservation' || $this->resaDateArrivee === '') {
            return new Collection();
        }

        $arrivee = CarbonImmutable::parse($this->resaDateArrivee);
        $nuits = max(1, $this->resaNuits);

        return $this->avecCategorie(
            $disponibilites->unitesDisponibles(
                $arrivee->toDateString(),
                $arrivee->addDays($nuits)->toDateString(),
            ),
        );
    }

    /**
     * Recharge les unités avec leur catégorie — DEUX requêtes, jamais une par
     * ligne. `DisponibiliteService` reste l'autorité sur QUI est libre (RG-02) ;
     * on ne fait ici que ramener le tarif et le libellé de catégorie, qui
     * vivent sur `categories_hebergement`.
     *
     * @param  Collection<int, UniteHebergement>  $unites
     * @return Collection<int, UniteHebergement>
     */
    private function avecCategorie(Collection $unites): Collection
    {
        $identifiants = $unites->pluck('id')->all();

        if ($identifiants === []) {
            return new Collection();
        }

        return UniteHebergement::query()
            ->with('categorie')
            ->whereIn('id', $identifiants)
            ->orderBy('numero')
            ->get()
            ->toBase();
    }

    private function reservationSejour(): ?Reservation
    {
        if ($this->sejourReservationId === null) {
            return null;
        }

        return Reservation::with(['client', 'unite'])->find($this->sejourReservationId);
    }

    /** L'unité de la modale « Check-in » ouverte depuis « Chambres disponibles ». */
    private function checkinUnite(): ?UniteHebergement
    {
        if ($this->checkinUniteId === null) {
            return null;
        }

        return UniteHebergement::with('categorie')->find($this->checkinUniteId);
    }

    // =====================================================================
    // « À traiter » — les alertes opérationnelles, tous modules confondus
    // =====================================================================

    /**
     * Les alertes du panneau « À traiter » (`m11-pilotage.js` l.150-200).
     *
     * ## CE QUI EST RENDU EST CE QUI A ÉTÉ LU, ET RIEN D'AUTRE
     *
     * Chaque entrée naît d'une mesure réelle d'un Service de domaine. Aucune
     * n'est fabriquée, aucune n'est déduite d'un chiffre absent : le maître
     * pose la règle dans son propre en-tête — « Un moteur absent n'est pas un
     * zéro », et une lecture qui échoue rend `null`, jamais `0`.
     *
     * ## LE DROIT DE CHAQUE SOURCE EST CELUI DE SON MODULE
     *
     * Le déséquilibre comptable et les brouillons sont des lectures M10, les
     * créances M3, le stock M6, les indicateurs M11. Un rôle sans droit sur un
     * module n'en reçoit pas l'alerte — et le nombre de sources réellement
     * consultées est retourné avec elles, parce que « aucune alerte » et « rien
     * n'a été lu » ne se disent pas de la même façon (Article 7).
     *
     * @param  array<string, array{valeur: string, precedent: string, variation_pct: string|null, unite: string}>|null  $indicateurs
     * @param  array{total_du: string, nb_pieces: int, nb_clients: int}  $creances
     * @param  Collection<int, \stdClass>  $articlesCritiques
     * @return array{alertes: list<array{gravite: string, titre: string, detail: string, url: string|null}>, sources: int, sourcesPossibles: int}
     */
    private function alertesPilotage(
        ?IndicateursComptables $comptables,
        ?array $indicateurs,
        array $creances,
        Collection $articlesCritiques,
    ): array {
        $alertes = [];
        $sources = 0;
        $possibles = 0;

        // --- M10 : équilibre comptable et brouillons -----------------------
        //
        // `$comptables` est `null` de deux façons, et l'appelant les a déjà
        // distinguées : droit M10 absent, ou aucun exercice ouvert. Dans les
        // deux cas la source n'a rien dit, et rien n'est affirmé à sa place.
        $possibles++;

        if ($comptables !== null) {
            $sources++;

            if (! $comptables->equilibre) {
                $alertes[] = [
                    'gravite' => 'rouge',
                    'titre' => __('accueil_pwa.alertes.compta_desequilibree'),
                    'detail' => __('accueil_pwa.alertes.compta_desequilibree_detail'),
                    'url' => route('pwa.comptabilite.balance', ['exercice' => $comptables->exerciceId]),
                ];
            }

            if ($comptables->statuts->brouillon > 0) {
                $alertes[] = [
                    'gravite' => 'amber',
                    'titre' => __('accueil_pwa.alertes.brouillons', ['nombre' => $comptables->statuts->brouillon]),
                    'detail' => __('accueil_pwa.alertes.brouillons_detail'),
                    'url' => route('pwa.comptabilite.journal', [
                        'exercice' => $comptables->exerciceId,
                        'statut' => 'brouillon',
                    ]),
                ];
            }
        }

        // --- M3 : créances clients -----------------------------------------
        $possibles++;
        if ($this->peutLire(self::MODULE_CLIENT)) {
            $sources++;

            if (bccomp($creances['total_du'], '0.00', 2) === 1) {
                $alertes[] = [
                    'gravite' => 'amber',
                    'titre' => __('accueil_pwa.alertes.creances', [
                        'montant' => MontantFcfa::format($creances['total_du']),
                    ]),
                    'detail' => __('accueil_pwa.creances.pieces', [
                        'nombre' => $creances['nb_pieces'],
                        'clients' => $creances['nb_clients'],
                    ]),
                    'url' => route('pwa.clients'),
                ];
            }
        }

        // --- M11 : factures non soldées et réservations à confirmer --------
        //
        // Les deux viennent de la bande d'indicateurs déjà calculée : les
        // relire ferait deux requêtes pour un seul chiffre, et deux formules
        // qui finiraient par diverger (PA-121).
        $possibles++;
        if ($indicateurs !== null) {
            $sources++;

            if ((int) $indicateurs['factures_impayees']['valeur'] > 0) {
                $alertes[] = [
                    'gravite' => 'amber',
                    'titre' => __('accueil_pwa.alertes.factures_non_soldees', [
                        'nombre' => (int) $indicateurs['factures_impayees']['valeur'],
                    ]),
                    'detail' => __('accueil_pwa.kpi.factures_impayees.note'),
                    'url' => $this->peutLire(self::MODULE_FACTURATION) ? route('pwa.facturation') : null,
                ];
            }

            if ((int) $indicateurs['reservations_en_attente']['valeur'] > 0) {
                $alertes[] = [
                    'gravite' => 'info',
                    'titre' => __('accueil_pwa.alertes.reservations_en_attente', [
                        'nombre' => (int) $indicateurs['reservations_en_attente']['valeur'],
                    ]),
                    'detail' => __('accueil_pwa.kpi.reservations_en_attente.note'),
                    'url' => $this->peutLire(self::MODULE_HEBERGEMENT) ? route('pwa.reservations') : null,
                ];
            }
        }

        // --- M6 : articles sous le seuil d'alerte ---------------------------
        $possibles++;
        if ($this->peutLire(self::MODULE_STOCKS)) {
            $sources++;

            if ($articlesCritiques->isNotEmpty()) {
                $alertes[] = [
                    'gravite' => 'amber',
                    'titre' => __('accueil_pwa.alertes.stock_critique', ['nombre' => $articlesCritiques->count()]),
                    'detail' => __('accueil_pwa.alertes.stock_critique_detail'),
                    // ⚠ `pwa.stocks.liste`, jamais `pwa.stocks` — corrigé le 31/08/2026.
                    //
                    // Le groupe des routes stocks se nomme `pwa.stocks.` et sa
                    // premiere entree `liste` : `pwa.stocks` n'existe pas, et
                    // `route()` LEVE sur un nom inconnu. Le defaut a atteint la
                    // production locale (500 sur /pwa) parce que cette alerte ne
                    // se REND que s'il existe un article critique : la base de
                    // test n'en avait pas, la branche n'etait jamais executee,
                    // et la garde de chargement etait verte a cote du defaut.
                    // C'est ce qui a fait ecrire `RoutesNommeesExistentTest` :
                    // un nom de route se verifie statiquement, pas seulement en
                    // esperant que le rendu passe par la.
                    'url' => route('pwa.stocks.liste'),
                ];
            }
        }

        return ['alertes' => $alertes, 'sources' => $sources, 'sourcesPossibles' => $possibles];
    }

    /**
     * Les indicateurs comptables de l'exercice OUVERT, ou `null`.
     *
     * ## POURQUOI L'EXERCICE OUVERT, ET POURQUOI C'EST L'EXCEPTION
     *
     * `MODULE_COMPTABILITE_COMPLET.md` §1 impose que tout ÉCRAN de M10 filtre
     * par un exercice CHOISI — jamais un repli silencieux, parce que deux
     * postes ouverts sur la même page rendraient deux années le jour d'une
     * bascule. Ici, il ne s'agit pas d'un écran M10 mais d'une ALERTE : la
     * question posée est « y a-t-il quelque chose à traiter aujourd'hui ? »,
     * et elle ne porte que sur l'exercice en cours. L'année est nommée dans le
     * texte de l'alerte, et le lien mène à l'écran M10 avec cet exercice — le
     * repli n'est donc ni silencieux, ni inspectable ailleurs.
     *
     * Aucun exercice ouvert : `null`, et la source compte comme NON consultée.
     * Un `false` sur `equilibre` serait ici une affirmation gratuite.
     */
    private function indicateursComptables(): ?IndicateursComptables
    {
        $exercice = ExerciceComptable::query()->where('statut', 'ouvert')->orderByDesc('annee')->first();

        if (! $exercice instanceof ExerciceComptable) {
            return null;
        }

        return app(IndicateursComptablesService::class)->genererPourExercice(
            $exercice,
            EcritureComptable::STATUTS,
            EcritureComptable::FILTRE_STATUT_TOUTES,
        );
    }

    /**
     * Les articles sous leur seuil d'alerte — stock CALCULÉ, jamais stocké.
     *
     * ⚠ `articles.quantite_stock` N'EXISTE PAS (schéma relu le 31/08/2026). La
     * version précédente interrogeait cette colonne, retombait sur son `catch`
     * et affichait « 2 articles en alerte » — un chiffre écrit en dur, sur
     * l'écran où l'on décide de réapprovisionner.
     *
     * La RÈGLE de calcul reste celle de M6 : `StockTheoriqueService::
     * EXPRESSION_SOLDE`, employée telle quelle. La recopier ferait diverger cet
     * écran de l'état des stocks le jour où un type de mouvement serait ajouté
     * — c'est ainsi que `TableauDeBordService::valeurStock()` procède déjà.
     *
     * @return Collection<int, \stdClass>
     */
    private function articlesCritiques(): Collection
    {
        return DB::table('articles')
            ->leftJoin('mouvements_stock', 'articles.id', '=', 'mouvements_stock.article_id')
            ->groupBy('articles.id', 'articles.libelle', 'articles.unite_mesure', 'articles.seuil_alerte')
            ->havingRaw(StockTheoriqueService::EXPRESSION_SOLDE.' <= articles.seuil_alerte')
            ->selectRaw('articles.id AS id, articles.libelle AS libelle')
            ->selectRaw('articles.unite_mesure AS unite_mesure, articles.seuil_alerte AS seuil_alerte')
            ->selectRaw(StockTheoriqueService::EXPRESSION_SOLDE.' AS stock')
            ->orderBy('articles.libelle')
            ->limit(self::PLAFOND_CRITIQUES)
            ->get()
            ->map(static function (\stdClass $ligne): \stdClass {
                $ligne->stock = bcadd((string) $ligne->stock, '0', 2);
                $ligne->seuil_alerte = bcadd((string) $ligne->seuil_alerte, '0', 2);

                return $ligne;
            });
    }

    // =====================================================================
    // Récapitulatif de la journée — `tableau-de-bord.js` l.392-410
    // =====================================================================

    /**
     * Les quatre compteurs du bandeau sombre : arrivées, départs, nouvelles
     * réservations, encaissé du jour.
     *
     * ## CHAQUE CHIFFRE EST UN COMPTE RÉEL, ET AUCUN N'EST DÉDUIT D'UN AUTRE
     *
     * Le maître déduit ses « nouvelles réservations » de l'HORODATAGE CONTENU
     * DANS L'IDENTIFIANT (`res-` + `Date.now()`, l.395) — un artifice de
     * `localStorage` qui n'a aucun équivalent ici, et qui serait faux dès
     * qu'un identifiant viendrait d'ailleurs. Le serveur porte `date_creation`
     * (trait `Auditable`), qui dit exactement la même chose sans le deviner.
     *
     * ⚠ « Encaissé aujourd'hui » compte les VENTES ENCAISSÉES, pas les
     * acomptes de réservation comme le fait le maître (l.398). La raison est
     * de schéma : `reservations.acompte` est un montant PORTÉ sur la fiche,
     * sans date de règlement — le sommer par date d'arrivée compterait comme
     * encaissé aujourd'hui l'acompte versé il y a trois semaines. Une vente
     * porte `encaisse` et son horodatage : c'est le seul argent dont le
     * serveur sait qu'il est entré aujourd'hui. Le libellé le dit.
     *
     * @return array{arrivees: int, departs: int, nouvelles: int, encaisse: string}
     */
    private function recapDuJour(CarbonImmutable $jour): array
    {
        $date = $jour->toDateString();

        $arrivees = Reservation::query()
            ->whereNot('statut', 'annulee')
            ->whereDate('date_arrivee', $date)
            ->count();

        $departs = Reservation::query()
            ->whereNot('statut', 'annulee')
            ->whereDate('date_depart', $date)
            ->count();

        $nouvelles = Reservation::query()
            ->whereDate('date_creation', $date)
            ->count();

        // `bcadd` sur l'agrégat : MySQL rend un `SUM(DECIMAL)` en chaîne et un
        // `SUM` vide en `null`. Un cast flottant ici ferait entrer un montant
        // dans un type que la règle projet interdit.
        $encaisse = DB::table('ventes')
            ->where('statut', 'validee')
            ->where('encaisse', true)
            ->whereDate('created_at', $date)
            ->sum('montant_total');

        return [
            'arrivees' => $arrivees,
            'departs' => $departs,
            'nouvelles' => $nouvelles,
            'encaisse' => bcadd((string) $encaisse, '0', 2),
        ];
    }

    // =====================================================================
    // Marge sur coûts directs par activité — `m11-pilotage.html` l.98
    // =====================================================================

    /**
     * Les marges par centre d'analyse de l'exercice OUVERT, ou `null`.
     *
     * ## LE CALCUL N'EST PAS RÉÉCRIT ICI, ET C'EST TOUT L'INTÉRÊT
     *
     * `AnalytiqueService` produit déjà exactement ce que le maître trace :
     * produits moins charges par centre, charges de structure NON RÉPARTIES —
     * son propre `ReadModel` porte le motif `charges_de_structure_non_reparties`,
     * qui est mot pour mot le sous-titre du maître. Recalculer une ventilation
     * ici poserait une seconde source de vérité à côté de M10 : le jour où la
     * règle de classe 8 changerait, l'écran d'analytique et ce graphique
     * afficheraient deux marges différentes pour la même activité.
     *
     * `null` a deux causes, et l'appelant les a déjà distinguées : droit M10
     * absent, ou aucun exercice ouvert. Dans les deux cas rien n'est affirmé —
     * un graphique à barres nulles se lirait comme une exploitation sans marge.
     *
     * @return list<array{libelle: string, resultat: string}>|null
     */
    private function margeParActivite(): ?array
    {
        $exercice = ExerciceComptable::query()->where('statut', 'ouvert')->orderByDesc('annee')->first();

        if (! $exercice instanceof ExerciceComptable) {
            return null;
        }

        $analytique = app(AnalytiqueService::class)->genererPourExercice(
            $exercice->id,
            EcritureComptable::STATUTS,
            EcritureComptable::FILTRE_STATUT_TOUTES,
        );

        return array_map(
            static fn ($ligne): array => [
                'libelle' => $ligne->libelle,
                'resultat' => $ligne->resultat,
            ],
            $analytique->centres,
        );
    }

    // =====================================================================
    // Créances par ancienneté — `m11-pilotage.html` l.105
    // =====================================================================

    /**
     * Les quatre tranches d'âge des créances, en montants réels.
     *
     * ## LE PRÉDICAT VIENT DE M3, IL N'EST PAS RÉÉCRIT
     *
     * `SoldeClientService::appliquerPredicatImpayee()` est LA définition d'une
     * créance sur ce serveur — facture certifiée dont le reste dû est positif —
     * et `SQL_RESTE_DU` en est le montant. Les recopier ici donnerait deux
     * formules pour la même grandeur, exactement le défaut que ce service a
     * été extrait pour fermer.
     *
     * ## ⚠ CE GRAPHIQUE NE TRANCHE PAS PA-20, ET IL NE LE PEUT PAS
     *
     * PA-20 laisse ouverte la POLITIQUE de balance âgée : ce qu'on fait d'une
     * créance de 95 jours (relancer, provisionner, passer en perte) et sur
     * quelle date d'échéance on la calcule. Rien de tout cela n'est décidé
     * ici. Ce qui est rendu, c'est l'ÂGE MESURÉ depuis `factures.date_emission`
     * — une colonne qui existe, sur des pièces qui existent. Afficher des
     * faits datés n'est pas arbitrer une politique ; c'est même ce qui
     * permettra de l'arbitrer.
     *
     * Le maître emploie une échéance ; `factures` n'en porte aucune, et le
     * sous-titre de la carte le dit à l'écran plutôt que de laisser croire
     * qu'un délai de paiement a été appliqué.
     *
     * @return list<array{cle: string, montant: string, pieces: int}>
     */
    private function creancesParAnciennete(): array
    {
        $aujourdhui = CarbonImmutable::today();
        $tranches = [];
        $borneBasse = 0;

        foreach (self::TRANCHES_CREANCES as $borneHaute) {
            $tranches[] = $this->trancheCreance(
                (string) $borneBasse . '_' . (string) $borneHaute,
                // Une facture de N jours entre dans la tranche dont la borne
                // haute est la première à la couvrir : bornes semi-ouvertes,
                // comme RG-01 — sans quoi une facture de 30 jours pile
                // compterait deux fois.
                $aujourdhui->subDays($borneHaute),
                $borneBasse === 0 ? null : $aujourdhui->subDays($borneBasse),
            );

            $borneBasse = $borneHaute;
        }

        $tranches[] = $this->trancheCreance(
            'plus_' . (string) $borneBasse,
            null,
            $aujourdhui->subDays($borneBasse),
        );

        return $tranches;
    }

    /**
     * Une tranche : montant dû et nombre de pièces émises dans la fenêtre.
     *
     * @return array{cle: string, montant: string, pieces: int}
     */
    private function trancheCreance(string $cle, ?CarbonImmutable $depuis, ?CarbonImmutable $jusqua): array
    {
        $requete = SoldeClientService::appliquerPredicatImpayee(DB::table('factures'));

        if ($depuis !== null) {
            $requete->whereDate('factures.date_emission', '>', $depuis->toDateString());
        }

        if ($jusqua !== null) {
            $requete->whereDate('factures.date_emission', '<=', $jusqua->toDateString());
        }

        /** @var object{montant: string|int|null, pieces: int|string}|null $ligne */
        $ligne = $requete
            ->selectRaw('SUM' . SoldeClientService::SQL_RESTE_DU . ' AS montant')
            ->selectRaw('COUNT(*) AS pieces')
            ->first();

        return [
            'cle' => $cle,
            'montant' => bcadd((string) ($ligne->montant ?? '0'), '0', 2),
            'pieces' => (int) ($ligne->pieces ?? 0),
        ];
    }

    // =====================================================================
    // Paie — carte « Masse salariale » du pilotage, carte « Personnel & paie »
    // =====================================================================

    /**
     * Les totaux de paie du mois EN COURS — `LivreDePaieService::totaux()`,
     * jamais recalculé ici.
     *
     * ## `brut` (masse salariale) N'EST PAS `cout_max` (coût employeur)
     *
     * Le motif de refus qu'il remplace confondait les deux : `brut` est la
     * SOMME DES SALAIRES DE BASE des bulletins réellement établis — un fait,
     * pas une estimation. `CalculPaieService` refuse un total UNIQUE de
     * charge patronale tant que le taux CNSS « risques professionnels »
     * n'est pas confirmé pour l'hôtellerie (PA-53) ; `cout_min`/`cout_max`
     * publient l'écart au lieu de le moyenner. Aucun des deux total ne sort
     * d'ici — `LivreDePaieService::totaux()` les porte déjà séparément.
     *
     * `effectif` compte les BULLETINS retenus (annulés exclus), pas les
     * employés actifs au référentiel : deux mesures voisines mais distinctes,
     * et c'est celle du maître (`PaieEngine.kpis()` compte les bulletins du
     * mois, `m11-pilotage.js` l.129-131).
     *
     * @return array{periode: string, effectif: int, brut: string, cout_min: string, cout_max: string, vps: string}
     */
    private function totauxPaie(): array
    {
        $periode = CarbonImmutable::today()->format('Y-m');
        $totaux = app(LivreDePaieService::class)->totaux($periode);

        return [
            'periode' => $periode,
            'effectif' => $totaux['effectif'],
            'brut' => $totaux['brut'],
            'cout_min' => $totaux['cout_min'],
            'cout_max' => $totaux['cout_max'],
            'vps' => $totaux['vps'],
        ];
    }

    // =====================================================================
    // « Par module » — les NEUF cartes du maître (`m11-pilotage.js`
    // `rendreModules()` l.362-475), en données réelles (02/09/2026)
    // =====================================================================

    /**
     * Les neuf cartes « Par module », dans l'ordre du maître, chacune gardée
     * par le droit de SON module — `MenuLateral::peutVoirRoute()`, la même
     * règle que le menu latéral, vérifiée AVANT tout calcul : une carte non
     * autorisée n'est jamais calculée puis masquée, ses chiffres n'entrent
     * pas dans l'instantané Livewire.
     *
     * Chaque valeur vient d'un Service existant ou d'une lecture que cet
     * écran fait déjà pour se peindre — jamais une seconde formule d'un
     * agrégat écrit ailleurs (PA-121). Les extractions du 02/09/2026 (état
     * dérivé sur `Reservation`, agrégats M8 dans `ParcVehiculeService`,
     * départs M9 dans `ReservationTourService`, familles de dépenses dans
     * `DepenseService`, encaissé 30 j dans `SoldeClientService`) existent
     * précisément pour que l'écran du module et cette carte lisent le même
     * auteur.
     *
     * @param  array{total_du: string, nb_pieces: int, nb_clients: int}  $creances
     * @param  list<array{cle: string, montant: string, pieces: int}>|null  $creancesAnciennete
     * @param  array{periode: string, effectif: int, brut: string, cout_min: string, cout_max: string, vps: string}|null  $paie
     * @param  array<string, array{valeur: string, precedent: string, variation_pct: string|null, unite: string}>|null  $indicateurs
     * @param  Collection<int, \stdClass>  $articlesCritiques
     * @return list<array{cle: string, titre: string, badge: string, url: string, lignes: list<array{libelle: string, valeur: string, classe: string}>, note: string|null}>
     */
    private function cartesParModule(
        Periode $periode,
        ?array $indicateurs,
        array $creances,
        ?array $creancesAnciennete,
        ?IndicateursComptables $comptables,
        ?array $paie,
        Collection $articlesCritiques,
        SoldeClientService $soldes,
    ): array {
        /** @var User|null $utilisateur */
        $utilisateur = Auth::user();
        $tiret = (string) __('accueil_pwa.tiret');
        $cartes = [];

        // 1. Réservations & hébergement (M1) — états dérivés des dates,
        // jamais un statut stocké (PA-111).
        if (MenuLateral::peutVoirRoute($utilisateur, 'pwa.reservations')) {
            $m1 = $this->moduleReservations();
            $cartes[] = [
                'cle' => 'reservations',
                'titre' => (string) __('accueil_pwa.pilotage.modules.reservations.titre'),
                'badge' => 'M1',
                'url' => route('pwa.reservations'),
                'lignes' => [
                    ['libelle' => (string) __('accueil_pwa.pilotage.modules.reservations.a_venir'), 'valeur' => (string) $m1['a_venir'], 'classe' => ''],
                    ['libelle' => (string) __('accueil_pwa.pilotage.modules.reservations.en_cours'), 'valeur' => (string) $m1['en_cours'], 'classe' => ''],
                    ['libelle' => (string) __('accueil_pwa.pilotage.modules.reservations.nuitees'), 'valeur' => (string) $m1['nuitees'], 'classe' => ''],
                    [
                        'libelle' => (string) __('accueil_pwa.pilotage.modules.reservations.reste'),
                        'valeur' => MontantFcfa::format($m1['reste_a_encaisser']),
                        'classe' => bccomp($m1['reste_a_encaisser'], '0.00', 2) > 0 ? 'text-red-600' : '',
                    ],
                ],
                'note' => null,
            ];
        }

        // 2. Point de vente — aujourd'hui (M4/M5). Le menu ouvre le POS sur
        // le droit M5 (`MenuLateral::NAVIGATION`) ; le badge « M4 / M5 » est
        // celui du maître, qui additionne bar et restaurant dans la même
        // carte.
        if (MenuLateral::peutVoirRoute($utilisateur, 'pwa.pos.comptant')) {
            $pos = $this->moduleVentesDuJour(CarbonImmutable::today());
            $cartes[] = [
                'cle' => 'pos',
                'titre' => (string) __('accueil_pwa.pilotage.modules.pos.titre'),
                'badge' => 'M4 / M5',
                'url' => route('pwa.pos.comptant'),
                'lignes' => [
                    ['libelle' => (string) __('accueil_pwa.pilotage.modules.pos.ventes'), 'valeur' => (string) $pos['ventes'], 'classe' => ''],
                    ['libelle' => (string) __('accueil_pwa.pilotage.modules.pos.ca'), 'valeur' => MontantFcfa::format($pos['chiffre_affaires']), 'classe' => ''],
                    ['libelle' => (string) __('accueil_pwa.pilotage.modules.pos.panier_moyen'), 'valeur' => MontantFcfa::format($pos['panier_moyen']), 'classe' => ''],
                    ['libelle' => (string) __('accueil_pwa.pilotage.modules.pos.note_chambre'), 'valeur' => MontantFcfa::format($pos['porte_en_note']), 'classe' => ''],
                ],
                'note' => $pos['sans_impact_stock'] > 0
                    ? (string) __('accueil_pwa.pilotage.modules.pos.note', ['nombre' => $pos['sans_impact_stock']])
                    : null,
            ];
        }

        // 3. Stocks (M6). La valeur vient de la MÊME lecture que la carte
        // KPI « Valeur du stock » ($indicateurs, `TableauDeBordService::
        // valeurStock()` — l'auteur unique du total au coût moyen pondéré,
        // le CMP étant écrit par `ValorisationStockService`) ; « Sous
        // seuil » est le compte de la MÊME collection que l'alerte du
        // panneau « À traiter » — deux chiffres différents sur le même
        // écran seraient deux vérités.
        if (MenuLateral::peutVoirRoute($utilisateur, 'pwa.stocks.liste')) {
            $stocks = $this->moduleStocks();
            $sousSeuil = $articlesCritiques->count();
            $cartes[] = [
                'cle' => 'stocks',
                'titre' => (string) __('accueil_pwa.pilotage.modules.stocks.titre'),
                'badge' => 'M6',
                'url' => route('pwa.stocks.liste'),
                'lignes' => [
                    ['libelle' => (string) __('accueil_pwa.pilotage.modules.stocks.suivies'), 'valeur' => (string) $stocks['permanents'], 'classe' => ''],
                    ['libelle' => (string) __('accueil_pwa.pilotage.modules.stocks.journalier'), 'valeur' => (string) $stocks['journaliers'], 'classe' => ''],
                    [
                        'libelle' => (string) __('accueil_pwa.pilotage.modules.stocks.valeur'),
                        // `$indicateurs` est `null` quand la bande KPI n'a pas
                        // pu être mesurée : un tiret, jamais un zéro plausible.
                        'valeur' => $indicateurs === null ? $tiret : MontantFcfa::format($indicateurs['valeur_stock']['valeur']),
                        'classe' => '',
                    ],
                    [
                        'libelle' => (string) __('accueil_pwa.pilotage.modules.stocks.sous_seuil'),
                        'valeur' => (string) $sousSeuil,
                        'classe' => $sousSeuil > 0 ? 'text-amber-600' : '',
                    ],
                ],
                'note' => null,
            ];
        }

        // 4. Location de véhicules (M8) — les agrégats de l'écran M8, sur SA
        // fenêtre par défaut (aujourd'hui → +14 jours) : la carte annonce ce
        // que l'écran qu'elle ouvre affiche. ÉCART assumé avec le maître
        // (02/09/2026) : lui passe le filtre du/au du panneau à son moteur ;
        // ici la fenêtre est celle de l'écran, sans quoi la carte et l'écran
        // rendraient deux chiffres pour la même grandeur.
        if (MenuLateral::peutVoirRoute($utilisateur, 'pwa.vehicules')) {
            $m8 = $this->moduleVehicules();
            $cartes[] = [
                'cle' => 'vehicules',
                'titre' => (string) __('accueil_pwa.pilotage.modules.vehicules.titre'),
                'badge' => 'M8',
                'url' => route('pwa.vehicules'),
                'lignes' => [
                    ['libelle' => (string) __('accueil_pwa.pilotage.modules.vehicules.parc'), 'valeur' => (string) $m8['parc'], 'classe' => ''],
                    ['libelle' => (string) __('accueil_pwa.pilotage.modules.vehicules.contrats'), 'valeur' => (string) $m8['contrats_actifs'], 'classe' => ''],
                    ['libelle' => (string) __('accueil_pwa.pilotage.modules.vehicules.ca'), 'valeur' => MontantFcfa::format($m8['chiffre_affaires']), 'classe' => ''],
                    ['libelle' => (string) __('accueil_pwa.pilotage.modules.vehicules.jours'), 'valeur' => (string) $m8['jours_loues'], 'classe' => ''],
                ],
                'note' => $m8['immobilises'] > 0
                    ? (string) __('accueil_pwa.pilotage.modules.vehicules.note', ['nombre' => $m8['immobilises']])
                    : null,
            ];
        }

        // 5. Tourisme & circuits (M9) — mêmes départs dérivés que l'écran
        // M9, sur SA fenêtre par défaut (aujourd'hui → +30 jours), départs
        // planifiés seulement (le filtre par défaut de l'écran).
        if (MenuLateral::peutVoirRoute($utilisateur, 'pwa.tourisme')) {
            $m9 = $this->moduleTourisme();
            $cartes[] = [
                'cle' => 'tourisme',
                'titre' => (string) __('accueil_pwa.pilotage.modules.tourisme.titre'),
                'badge' => 'M9',
                'url' => route('pwa.tourisme'),
                'lignes' => [
                    ['libelle' => (string) __('accueil_pwa.pilotage.modules.tourisme.departs'), 'valeur' => (string) $m9['departs'], 'classe' => ''],
                    ['libelle' => (string) __('accueil_pwa.pilotage.modules.tourisme.places'), 'valeur' => $m9['places_vendues'].' / '.$m9['capacite_offerte'], 'classe' => ''],
                    [
                        'libelle' => (string) __('accueil_pwa.pilotage.modules.tourisme.remplissage'),
                        // `null` n'est pas « 0 % » : sans capacité offerte, le
                        // taux n'est pas calculable (le maître rend « — »).
                        'valeur' => $m9['taux_remplissage'] === null ? $tiret : $m9['taux_remplissage'].' %',
                        'classe' => $m9['taux_remplissage'] !== null && $m9['taux_remplissage'] < 50 ? 'text-amber-600' : '',
                    ],
                    ['libelle' => (string) __('accueil_pwa.pilotage.modules.tourisme.ca'), 'valeur' => MontantFcfa::format($m9['chiffre_affaires']), 'classe' => ''],
                ],
                'note' => $m9['duree_indeterminee'] > 0
                    ? (string) __('accueil_pwa.pilotage.modules.tourisme.note', ['nombre' => $m9['duree_indeterminee']])
                    : null,
            ];
        }

        // 6. Personnel & paie (M13) — `LivreDePaieService::totaux()`, déjà lu
        // par la carte KPI « Masse salariale ». Le coût employeur est une
        // FOURCHETTE (PA-53) : jamais un total unique, et la note du maître
        // — fixe, pas conditionnelle — dit pourquoi. « Effectif actif » est
        // le mot du maître, et sa mesure est celle du maître aussi : les
        // bulletins du mois (`PaieEngine.kpis()`), pas le référentiel.
        if ($paie !== null && MenuLateral::peutVoirRoute($utilisateur, 'pwa.paie')) {
            $cartes[] = [
                'cle' => 'paie',
                'titre' => (string) __('accueil_pwa.pilotage.module_paie_titre'),
                'badge' => 'M13',
                'url' => route('pwa.paie'),
                'lignes' => [
                    ['libelle' => (string) __('accueil_pwa.pilotage.modules.paie.effectif'), 'valeur' => (string) $paie['effectif'], 'classe' => ''],
                    ['libelle' => (string) __('accueil_pwa.pilotage.masse_salariale'), 'valeur' => MontantFcfa::format($paie['brut']), 'classe' => ''],
                    [
                        'libelle' => (string) __('accueil_pwa.pilotage.modules.paie.cout'),
                        'valeur' => (string) __('accueil_pwa.pilotage.modules.paie.cout_valeur', [
                            'min' => MontantFcfa::format($paie['cout_min']),
                            'max' => MontantFcfa::format($paie['cout_max']),
                        ]),
                        'classe' => 'text-amber-700',
                    ],
                    // « 0 F si aucun bulletin » : `LivreDePaieService::totaux()`
                    // rend '0.00' quand rien n'est établi — un fait, pas un repli.
                    ['libelle' => (string) __('accueil_pwa.pilotage.module_paie_vps'), 'valeur' => MontantFcfa::format($paie['vps']), 'classe' => ''],
                ],
                'note' => (string) __('accueil_pwa.pilotage.modules.paie.note'),
            ];
        }

        // 7. Clients & créances (M3) — tout vient de `SoldeClientService` :
        // les totaux, la tranche +90 j (déjà lue pour le graphique
        // « Créances par ancienneté », jamais une seconde requête) et
        // l'encaissé réel des 30 derniers jours (paiements ACTIFS).
        if ($creancesAnciennete !== null && MenuLateral::peutVoirRoute($utilisateur, 'pwa.clients')) {
            $plus90 = '0.00';

            foreach ($creancesAnciennete as $tranche) {
                if ($tranche['cle'] === 'plus_90') {
                    $plus90 = $tranche['montant'];
                }
            }

            $encaisse30j = $soldes->encaisseDepuis(CarbonImmutable::now()->subDays(30));

            $cartes[] = [
                'cle' => 'creances',
                'titre' => (string) __('accueil_pwa.pilotage.module_creances_titre'),
                'badge' => 'M3',
                'url' => route('pwa.clients'),
                'lignes' => [
                    ['libelle' => (string) __('accueil_pwa.pilotage.module_creances_clients'), 'valeur' => (string) $creances['nb_clients'], 'classe' => ''],
                    ['libelle' => (string) __('accueil_pwa.pilotage.module_creances_total'), 'valeur' => MontantFcfa::format($creances['total_du']), 'classe' => ''],
                    [
                        'libelle' => (string) __('accueil_pwa.pilotage.modules.creances.douteux'),
                        'valeur' => MontantFcfa::format($plus90),
                        'classe' => bccomp($plus90, '0.00', 2) > 0 ? 'text-red-600' : '',
                    ],
                    [
                        'libelle' => (string) __('accueil_pwa.pilotage.modules.creances.encaisse_30j'),
                        'valeur' => MontantFcfa::format($encaisse30j),
                        'classe' => 'text-emerald-600',
                    ],
                ],
                'note' => null,
            ];
        }

        // 8. Comptabilité (M10) — l'exercice COURANT, déjà lu pour la carte
        // KPI « Résultat net ». Le résultat net n'apparaît PAS ici : seuls
        // VA et EBE sont calculables sans taux d'IS (la carte KPI, elle,
        // porte l'avertissement « avant impôt »). Sans exercice ouvert, la
        // carte rend des tirets et le DIT — jamais des zéros plausibles.
        if (MenuLateral::peutVoirRoute($utilisateur, 'pwa.comptabilite.hub')) {
            $cartes[] = [
                'cle' => 'compta',
                'titre' => (string) __('accueil_pwa.pilotage.module_compta_titre'),
                'badge' => 'M10',
                'url' => route('pwa.comptabilite.hub'),
                'lignes' => [
                    ['libelle' => (string) __('accueil_pwa.pilotage.module_compta_va'), 'valeur' => $comptables === null ? $tiret : MontantFcfa::format($comptables->valeurAjoutee), 'classe' => ''],
                    [
                        'libelle' => (string) __('accueil_pwa.pilotage.module_compta_ebe'),
                        'valeur' => $comptables === null ? $tiret : MontantFcfa::format($comptables->excedentBrut),
                        'classe' => $comptables !== null && MontantFcfa::estNegatif($comptables->excedentBrut) ? 'text-red-600' : '',
                    ],
                    ['libelle' => (string) __('accueil_pwa.pilotage.module_compta_bilan'), 'valeur' => $comptables === null ? $tiret : MontantFcfa::format($comptables->totalBilan), 'classe' => ''],
                    ['libelle' => (string) __('accueil_pwa.pilotage.module_compta_pieces'), 'valeur' => $comptables === null ? $tiret : (string) ($comptables->statuts->brouillon + $comptables->statuts->validee), 'classe' => ''],
                ],
                'note' => match (true) {
                    $comptables === null => (string) __('accueil_pwa.pilotage.modules.compta.absent'),
                    $comptables->statuts->brouillon > 0 => (string) __('accueil_pwa.pilotage.module_compta_note', ['nombre' => $comptables->statuts->brouillon]),
                    default => null,
                },
            ];
        }

        // 9. Dépense courante (M10) — la période du panneau, comme au maître
        // (« un total toutes périodes à côté de KPI filtrés donnerait deux
        // vérités sur le même écran », `m11-pilotage.js` l.68-70).
        if (MenuLateral::peutVoirRoute($utilisateur, 'pwa.depenses')) {
            $depenses = $this->moduleDepenses($periode);
            $cartes[] = [
                'cle' => 'depenses',
                'titre' => (string) __('accueil_pwa.pilotage.modules.depenses.titre'),
                'badge' => 'M10',
                'url' => route('pwa.depenses'),
                'lignes' => [
                    ['libelle' => (string) __('accueil_pwa.pilotage.modules.depenses.total'), 'valeur' => MontantFcfa::format($depenses['total']), 'classe' => ''],
                    ['libelle' => (string) __('accueil_pwa.pilotage.modules.depenses.nombre'), 'valeur' => (string) $depenses['nombre'], 'classe' => ''],
                    // « Marché » et « Services » : les deux FAMILLES réelles de
                    // `lignes_depense.famille` (registre `Depenses::NATURES`,
                    // les mots mêmes du maître) — PAS des centres de coût :
                    // `depenses` ne porte aucun `centre_id`, le centre vit sur
                    // la pièce comptable (RG-12). Adaptation documentée le
                    // 02/09/2026 : la ventilation du maître est reprise par
                    // famille, la seule que le schéma des dépenses porte.
                    ['libelle' => $depenses['familles'][0]['famille'], 'valeur' => MontantFcfa::format($depenses['familles'][0]['montant']), 'classe' => ''],
                    ['libelle' => $depenses['familles'][1]['famille'], 'valeur' => MontantFcfa::format($depenses['familles'][1]['montant']), 'classe' => ''],
                ],
                // La note « N dépense(s) non comptabilisée(s) » du maître est
                // IMPOSSIBLE par construction depuis PA-159 : `DepenseService::
                // enregistrer()` passe la pièce dans la MÊME transaction que la
                // dépense, et un refus n'écrit rien du tout — il ne peut pas
                // exister de dépense sans écriture. Reste la vigilance
                // « sans reçu », que `depenses.recu_path` porte réellement.
                'note' => $depenses['sans_recu'] > 0
                    ? (string) __('accueil_pwa.pilotage.modules.depenses.sans_recu', ['nombre' => $depenses['sans_recu']])
                    : null,
            ];
        }

        return $cartes;
    }

    /**
     * La carte M1 : états dérivés, nuitées et reste à encaisser réels.
     *
     * Les états viennent de `Reservation::etatDerive()` — la formule de
     * l'écran Réservations, remontée sur le modèle (PA-111/PA-121). Les
     * nuitées portent sur les séjours à venir et en cours (le maître exclut
     * les annulées ; la directive du 02/09/2026 précise « à venir + en
     * cours »). Le reste à encaisser est `Reservation::resteAPayer()` — LA
     * formule de la fiche (sous-total − remise − acompte), jamais une
     * seconde ; une fiche sans `tarif_nuit` figé (antérieure à PA-163) rend
     * `null` et n'entre pas dans la somme — l'additionner comme zéro
     * inventerait un « rien à encaisser » sur un séjour dont le montant
     * n'est pas connu.
     *
     * @return array{a_venir: int, en_cours: int, nuitees: int, reste_a_encaisser: string}
     */
    private function moduleReservations(): array
    {
        $aujourdhui = CarbonImmutable::today();

        // `with('lignes')` : `resteAPayer()` somme les lignes de services de
        // la fiche — sans lui, une requête par réservation.
        $reservations = Reservation::query()
            ->whereNot('statut', 'annulee')
            ->with('lignes')
            ->get();

        $aVenir = 0;
        $enCours = 0;
        $nuitees = 0;
        $reste = '0.00';

        foreach ($reservations as $reservation) {
            $etat = $reservation->etatDerive($aujourdhui);

            if ($etat === 'a_venir') {
                $aVenir++;
            }

            if ($etat === 'en_cours') {
                $enCours++;
            }

            if ($etat === 'a_venir' || $etat === 'en_cours') {
                $nuitees += $reservation->nombreNuitees();
            }

            $resteFiche = $reservation->resteAPayer();

            if ($resteFiche !== null) {
                $reste = bcadd($reste, $resteFiche, 2);
            }
        }

        return [
            'a_venir' => $aVenir,
            'en_cours' => $enCours,
            'nuitees' => $nuitees,
            'reste_a_encaisser' => $reste,
        ];
    }

    /**
     * La carte M4/M5 : les ventes du JOUR, par les prédicats du modèle —
     * `estAnnulee()`, `encaisse`, `aDesLignesSansImpactStock()` — les mêmes
     * que l'écran Historique des ventes, jamais réécrits en SQL (PA-121).
     * Une vente annulée n'est pas une vente ; « porté en note » est
     * `encaisse = false` (mode `note_chambre`, `VenteService`).
     *
     * @return array{ventes: int, chiffre_affaires: string, panier_moyen: string, porte_en_note: string, sans_impact_stock: int}
     */
    private function moduleVentesDuJour(CarbonImmutable $jour): array
    {
        $validees = Vente::query()
            ->whereDate('created_at', $jour->toDateString())
            ->get()
            ->filter(static fn (Vente $vente): bool => ! $vente->estAnnulee());

        $nombre = $validees->count();
        $chiffreAffaires = '0.00';
        $porteEnNote = '0.00';

        foreach ($validees as $vente) {
            $chiffreAffaires = bcadd($chiffreAffaires, (string) $vente->montant_total, 2);

            if (! $vente->encaisse) {
                $porteEnNote = bcadd($porteEnNote, (string) $vente->montant_total, 2);
            }
        }

        return [
            'ventes' => $nombre,
            'chiffre_affaires' => $chiffreAffaires,
            // « 0 F si aucune » (directive du 02/09/2026) : un panier moyen
            // sans vente n'existe pas, et le maître rend fcfa(0).
            'panier_moyen' => $nombre === 0 ? '0.00' : bcdiv($chiffreAffaires, (string) $nombre, 2),
            'porte_en_note' => $porteEnNote,
            'sans_impact_stock' => $validees
                ->filter(static fn (Vente $vente): bool => $vente->aDesLignesSansImpactStock())
                ->count(),
        ];
    }

    /**
     * La carte M6 : répartition du référentiel par type de suivi — le même
     * partage que `Article::estSuiviEnStock()` (`suivi !== 'journalier'`),
     * celui de l'écran Stocks (`ConsultationStockService::etatConsolide()`),
     * compté en UNE requête plutôt qu'en chargeant tous les articles.
     *
     * @return array{permanents: int, journaliers: int}
     */
    private function moduleStocks(): array
    {
        /** @var object{total: int|string, journaliers: int|string|null} $ligne */
        $ligne = Article::query()
            ->selectRaw('COUNT(*) AS total')
            ->selectRaw("SUM(CASE WHEN suivi = 'journalier' THEN 1 ELSE 0 END) AS journaliers")
            ->toBase()
            ->first();

        $journaliers = (int) ($ligne->journaliers ?? 0);

        return [
            'permanents' => (int) $ligne->total - $journaliers,
            'journaliers' => $journaliers,
        ];
    }

    /**
     * La carte M8 : les agrégats de l'écran Véhicules — même fenêtre par
     * défaut (`Locations::JOURS_PAR_DEFAUT`), même requête
     * (`ParcVehiculeService::contratsSurFenetre()`), même formule
     * (`agregerContratsActifs()`). « Immobilisé » est
     * `Vehicule::STATUTS_IMMOBILISES`, le complément exact des statuts
     * louables.
     *
     * @return array{parc: int, immobilises: int, contrats_actifs: int, jours_loues: int, chiffre_affaires: string, reste_a_encaisser: string}
     */
    private function moduleVehicules(): array
    {
        $debut = CarbonImmutable::today();
        $fin = $debut->addDays(EcranVehicules::JOURS_PAR_DEFAUT);

        $agregats = ParcVehiculeService::agregerContratsActifs(
            app(ParcVehiculeService::class)->contratsSurFenetre($debut, $fin)->get(),
        );

        return $agregats + [
            'parc' => Vehicule::query()->count(),
            'immobilises' => Vehicule::query()->whereIn('statut', Vehicule::STATUTS_IMMOBILISES)->count(),
        ];
    }

    /**
     * La carte M9 : les départs dérivés de l'écran Tourisme — même fenêtre
     * par défaut (`Departs::JOURS_PAR_DEFAUT`), même dérivation
     * (`ReservationTourService::departsDerives()`), même agrégation
     * (`agregerDeparts()`). Seuls les départs PLANIFIÉS comptent — le filtre
     * par défaut de l'écran : un départ dont toutes les lignes sont annulées
     * n'est plus un départ. Le compte « durée indéterminée » porte sur ces
     * départs (celui du maître) — l'écran M9 compte, lui, les CIRCUITS du
     * catalogue : deux mesures voisines, celle du maître est retenue ici.
     *
     * @return array{departs: int, places_vendues: int, capacite_offerte: int, complets: int, chiffre_affaires: string, taux_remplissage: float|null, duree_indeterminee: int}
     */
    private function moduleTourisme(): array
    {
        $debut = CarbonImmutable::today();
        $fin = $debut->addDays(EcranTourisme::JOURS_PAR_DEFAUT);

        $service = app(ReservationTourService::class);
        $departs = $service->departsDerives($service->reservationsSurFenetre($debut, $fin));

        return ReservationTourService::agregerDeparts(
            array_values(array_filter($departs, static fn (array $depart): bool => ! $depart['annule'])),
        );
    }

    /**
     * La carte « Dépense courante » : la période du panneau, la requête du
     * domaine (`DepenseService::filtrer()`) et SES formules
     * (`totalDecaisse()`, `totalParFamille()`) — celles que l'écran Dépenses
     * appelle aussi. Les familles rendues sont « Marché » puis « Services »,
     * l'ordre du maître.
     *
     * @return array{total: string, nombre: int, familles: list<array{famille: string, montant: string}>, sans_recu: int}
     */
    private function moduleDepenses(Periode $periode): array
    {
        $depenses = app(DepenseService::class)->filtrer([
            'du' => $periode->debut->toDateString(),
            // `Periode::fin` est le premier instant EXCLU ; `filtrer()` borne
            // `date_transaction <= au` (inclusif) — la veille, donc.
            'au' => $periode->fin->subDay()->toDateString(),
        ])->get();

        return [
            'total' => DepenseService::totalDecaisse($depenses),
            'nombre' => $depenses->count(),
            'familles' => [
                ['famille' => 'Marché', 'montant' => DepenseService::totalParFamille($depenses, 'Marché')],
                ['famille' => 'Services', 'montant' => DepenseService::totalParFamille($depenses, 'Services')],
            ],
            'sans_recu' => $depenses
                ->filter(static fn ($depense): bool => $depense->recu_path === null)
                ->count(),
        ];
    }

    // =====================================================================
    // Meilleures ventes — `indicateurs-engine.js` l.58-95
    // =====================================================================

    /**
     * Les quatre classements du maître, calculés sur le registre RÉEL des
     * lignes de vente.
     *
     * Le refus qui figurait ici — « aucun Service de domaine ne la calcule » —
     * a cessé d'être vrai : `lignes_vente` porte `module`, `nom`, `quantite`
     * et `montant`, et le registre est alimenté par `VenteService`. Le motif
     * est daté de sa levée plutôt que recopié (PA-144).
     *
     * ⚠ DEUX DES QUATRE CLASSEMENTS SONT STRUCTURELLEMENT VIDES AUJOURD'HUI,
     * et ce n'est pas une panne : `VenteService::MODULES_ENCAISSABLES` ne
     * contient que M4 et M5 — un encaissement de tourisme (M9) ou de location
     * (M8) est REFUSÉ par le domaine faute de catalogue serveur d'où figer un
     * prix. Les cartes sont rendues avec leur état vide, jamais omises : les
     * retirer ferait croire que le classement n'existe pas, quand il existe et
     * n'a simplement rien à classer.
     *
     * @return list<array{cle: string, tri: string, lignes: list<array{nom: string, quantite: int, montant: string}>}>
     */
    private function meilleuresVentes(Periode $periode): array
    {
        $classements = [];

        foreach (self::CLASSEMENTS_VENTES as $cle => $definition) {
            $lignes = DB::table('lignes_vente')
                ->join('ventes', 'lignes_vente.vente_id', '=', 'ventes.id')
                // Une vente annulée n'est pas une vente : la compter la
                // ferait figurer au palmarès du mois où elle a été reprise.
                ->whereNot('ventes.statut', 'annulee')
                ->whereBetween('ventes.created_at', [$periode->debut, $periode->fin])
                ->whereIn('lignes_vente.module', $definition['modules'])
                ->groupBy('lignes_vente.nom')
                ->selectRaw('lignes_vente.nom AS nom')
                ->selectRaw('SUM(lignes_vente.quantite) AS quantite')
                ->selectRaw('SUM(lignes_vente.montant) AS montant')
                // Le tri du maître : le critère annoncé d'abord, l'autre en
                // départage — sans quoi deux exécutions rendraient deux ordres
                // sur une égalité.
                ->orderByDesc($definition['tri'] === 'quantite' ? 'quantite' : 'montant')
                ->orderByDesc($definition['tri'] === 'quantite' ? 'montant' : 'quantite')
                ->orderBy('lignes_vente.nom')
                ->limit(self::TOP_VENTES_LIMITE)
                ->get();

            $classements[] = [
                'cle' => $cle,
                'tri' => $definition['tri'],
                'lignes' => $lignes
                    ->map(static fn (\stdClass $ligne): array => [
                        'nom' => (string) $ligne->nom,
                        'quantite' => (int) $ligne->quantite,
                        'montant' => bcadd((string) $ligne->montant, '0', 2),
                    ])
                    ->all(),
            ];
        }

        return $classements;
    }

    // =====================================================================
    // Tableau croisé dynamique — `croise-engine.js`
    // =====================================================================

    /**
     * Les sources réellement retenues — intersection du registre fermé et de
     * ce que les cases à cocher ont renvoyé.
     *
     * Une case cochée par une valeur inconnue (`croiseSources` est une
     * propriété publique, donc composable depuis le client) ne peut pas
     * inventer une source : elle est simplement absente du filtre.
     *
     * @return list<string>
     */
    private function sourcesCroiseValides(): array
    {
        return array_values(array_filter(
            self::SOURCES_CROISE,
            fn (string $source): bool => in_array($source, $this->croiseSources, true),
        ));
    }

    private function axeCroiseValide(string $demande, string $defaut): string
    {
        return array_key_exists($demande, self::AXES_CROISE) ? $demande : $defaut;
    }

    /**
     * Le croisement complet : grille, totaux de lignes, de colonnes, général.
     *
     * ## UNE TABLE DE FAITS, APLATIE AU NIVEAU DE LA LIGNE
     *
     * Chaque source est aplatie à la LIGNE, jamais à la pièce : une vente de
     * trois articles donne trois faits. Sans cela, croiser par produit serait
     * impossible et le total par catégorie retomberait sur la catégorie du
     * premier article (`croise-engine.js` l.55-60).
     *
     * ## LES DÉPENSES COMPTENT EN NÉGATIF
     *
     * Le total est un SOLDE, pas une somme. Additionner recettes et charges
     * donnerait leur somme au lieu de leur différence — et le chiffre serait
     * faux dans le sens le plus flatteur.
     *
     * @return array{lignes: list<string>, colonnes: list<string>, grille: list<list<string>>, totauxLignes: list<string>, totauxColonnes: list<string>, total: string, nbFaits: int, vide: bool, monnaie: bool, axeLigne: string, mesure: string}
     */
    private function croiser(Periode $periode): array
    {
        $axeLigne = $this->axeCroiseValide($this->croiseLigne, 'activite');
        $axeColonne = $this->axeCroiseValide($this->croiseColonne, 'mois');
        $mesure = array_key_exists($this->croiseMesure, self::MESURES_CROISE) ? $this->croiseMesure : 'montant';

        $faits = $this->faitsCroises($periode, $this->sourcesCroiseValides());

        $cellules = [];
        $lignes = [];
        $colonnes = [];

        foreach ($faits as $fait) {
            $cl = $fait[$axeLigne];
            $cc = $fait[$axeColonne];

            // La clé de TRI d'un mois est sa clé chronologique (`AAAA-MM`),
            // jamais son libellé français.
            $lignes[$cl] = $axeLigne === 'mois' ? $fait['tri_mois'] : $cl;
            $colonnes[$cc] = $axeColonne === 'mois' ? $fait['tri_mois'] : $cc;

            // Séparateur NUL écrit en ÉCHAPPEMENT, jamais en octet brut : un
            // octet de contrôle rendrait ce fichier binaire pour grep, ce que
            // `CaracteresDeControleTest` refuse — et le maître a été corrigé
            // pour la même raison.
            $cle = $cl . "\u{0000}" . $cc;
            $cellules[$cle] = bcadd($cellules[$cle] ?? '0.00', $fait[$mesure], 2);
        }

        asort($lignes);
        asort($colonnes);

        $nomsLignes = array_keys($lignes);
        $nomsColonnes = array_keys($colonnes);

        $grille = [];
        $totauxLignes = [];

        foreach ($nomsLignes as $nomLigne) {
            $rangee = [];
            $totalLigne = '0.00';

            foreach ($nomsColonnes as $nomColonne) {
                $valeur = $cellules[$nomLigne . "\u{0000}" . $nomColonne] ?? '0.00';
                $rangee[] = $valeur;
                $totalLigne = bcadd($totalLigne, $valeur, 2);
            }

            $grille[] = $rangee;
            $totauxLignes[] = $totalLigne;
        }

        $totauxColonnes = [];

        foreach (array_keys($nomsColonnes) as $index) {
            $total = '0.00';

            foreach ($grille as $rangee) {
                $total = bcadd($total, $rangee[$index], 2);
            }

            $totauxColonnes[] = $total;
        }

        $totalGeneral = '0.00';

        foreach ($totauxLignes as $total) {
            $totalGeneral = bcadd($totalGeneral, $total, 2);
        }

        return [
            'lignes' => array_map('strval', $nomsLignes),
            'colonnes' => array_map('strval', $nomsColonnes),
            'grille' => $grille,
            'totauxLignes' => $totauxLignes,
            'totauxColonnes' => $totauxColonnes,
            'total' => $totalGeneral,
            'nbFaits' => count($faits),
            // « — » quand il n'y a AUCUN fait : une grille vide et une grille
            // de zéros ne disent pas la même chose (Article 7).
            'vide' => $faits === [],
            'monnaie' => self::MESURES_CROISE[$mesure],
            'axeLigne' => $axeLigne,
            'mesure' => $mesure,
        ];
    }

    /**
     * La table de faits, une entrée par ligne élémentaire.
     *
     * ⚠ LA MESURE « MONTANT » D'UNE RÉSERVATION EST SON ACOMPTE, ET C'EST DIT
     * À L'ÉCRAN. `reservations` ne porte AUCUN montant de séjour au schéma
     * serveur — ni tarif, ni total (PA-29, PA-57) : `acompte` est le seul
     * montant qui existe. Le rendre sous l'intitulé « Montant » sans le nommer
     * ferait lire un chiffre de séjour là où il n'y a qu'un versement, et la
     * note sous le tableau le dit explicitement.
     *
     * @param  list<string>  $sources
     * @return list<array<string, string>>
     */
    private function faitsCroises(Periode $periode, array $sources): array
    {
        $faits = [];

        if (in_array('ventes', $sources, true)) {
            $lignes = DB::table('lignes_vente')
                ->join('ventes', 'lignes_vente.vente_id', '=', 'ventes.id')
                ->whereNot('ventes.statut', 'annulee')
                ->whereBetween('ventes.created_at', [$periode->debut, $periode->fin])
                ->select([
                    'ventes.created_at',
                    'ventes.point_vente',
                    'ventes.mode_paiement',
                    'ventes.encaisse',
                    'lignes_vente.module',
                    'lignes_vente.categorie',
                    'lignes_vente.nom',
                    'lignes_vente.quantite',
                    'lignes_vente.montant',
                ])
                ->get();

            foreach ($lignes as $ligne) {
                $montant = bcadd((string) $ligne->montant, '0', 2);

                $faits[] = $this->fait(
                    date: CarbonImmutable::parse((string) $ligne->created_at),
                    source: (string) __('accueil_pwa.croise.sources_libelles.ventes'),
                    module: (string) $ligne->module,
                    activite: (string) $ligne->categorie,
                    libelle: (string) $ligne->nom,
                    tiers: (string) $ligne->point_vente,
                    mode: (string) ($this->libelleMode((string) $ligne->mode_paiement)),
                    quantite: (string) (int) $ligne->quantite,
                    montant: $montant,
                    // Une note de chambre est une CRÉANCE, pas un
                    // encaissement : elle compte au chiffre d'affaires et pas
                    // à la caisse. C'est précisément pourquoi les deux mesures
                    // existent séparément.
                    encaisse: (bool) $ligne->encaisse ? $montant : '0.00',
                );
            }
        }

        if (in_array('depenses', $sources, true)) {
            $lignes = DB::table('lignes_depense')
                ->join('depenses', 'lignes_depense.depense_id', '=', 'depenses.id')
                ->whereBetween('depenses.date_transaction', [
                    $periode->debut->toDateString(),
                    $periode->fin->toDateString(),
                ])
                ->select([
                    'depenses.date_transaction',
                    'depenses.tresorerie',
                    'lignes_depense.famille',
                    'lignes_depense.nature',
                    'lignes_depense.montant',
                ])
                ->get();

            foreach ($lignes as $ligne) {
                // Une dépense est un DÉCAISSEMENT : elle compte en négatif.
                $montant = bcsub('0.00', bcadd((string) $ligne->montant, '0', 2), 2);

                $faits[] = $this->fait(
                    date: CarbonImmutable::parse((string) $ligne->date_transaction),
                    source: (string) __('accueil_pwa.croise.sources_libelles.depenses'),
                    module: self::MODULE_COMPTABILITE,
                    activite: (string) $ligne->famille,
                    libelle: (string) $ligne->nature,
                    tiers: (string) $ligne->tresorerie,
                    mode: (string) __('accueil_pwa.tiret'),
                    quantite: '1',
                    montant: $montant,
                    encaisse: $montant,
                );
            }
        }

        if (in_array('reservations', $sources, true)) {
            $lignes = DB::table('reservations')
                ->leftJoin('clients', 'reservations.client_id', '=', 'clients.id')
                ->whereNot('reservations.statut', 'annulee')
                ->whereBetween('reservations.date_arrivee', [
                    $periode->debut->toDateString(),
                    $periode->fin->toDateString(),
                ])
                ->select([
                    'reservations.date_arrivee',
                    'reservations.acompte',
                    'clients.nom',
                    'clients.prenom',
                ])
                ->get();

            foreach ($lignes as $ligne) {
                $acompte = bcadd((string) ($ligne->acompte ?? '0'), '0', 2);

                $faits[] = $this->fait(
                    date: CarbonImmutable::parse((string) $ligne->date_arrivee),
                    source: (string) __('accueil_pwa.croise.sources_libelles.reservations'),
                    module: self::MODULE_HEBERGEMENT,
                    activite: (string) __('accueil_pwa.croise.activite_hebergement'),
                    libelle: trim((string) $ligne->nom . ' ' . (string) $ligne->prenom),
                    // Le CANAL du maître n'existe pas au schéma serveur
                    // (PA-29) : le tiret est un fait d'écran, pas une valeur
                    // inventée.
                    tiers: (string) __('accueil_pwa.tiret'),
                    mode: (string) __('accueil_pwa.tiret'),
                    quantite: '1',
                    montant: $acompte,
                    encaisse: $acompte,
                );
            }
        }

        return $faits;
    }

    /**
     * Un fait, réduit aux axes et aux mesures — jamais un objet libre.
     *
     * @return array<string, string>
     */
    private function fait(
        CarbonImmutable $date,
        string $source,
        string $module,
        string $activite,
        string $libelle,
        string $tiers,
        string $mode,
        string $quantite,
        string $montant,
        string $encaisse,
    ): array {
        $tiret = (string) __('accueil_pwa.tiret');

        return [
            'source' => $source,
            'module' => $module === '' ? $tiret : $module,
            'activite' => $activite === '' ? $tiret : $activite,
            'libelle' => $libelle === '' ? $tiret : $libelle,
            'tiers' => $tiers === '' ? $tiret : $tiers,
            'mode' => $mode === '' ? $tiret : $mode,
            'jour' => $date->format('d/m/Y'),
            // Clé de tri CHRONOLOGIQUE du jour — `rapports-engine.js` trie ses
            // « État de recettes » et « État de ventes » sur la date ISO du
            // fait, jamais sur `jour` (d/m/Y), qui ne trie pas chronologiquement.
            'jour_iso' => $date->toDateString(),
            'mois' => $date->translatedFormat('F Y'),
            'tri_mois' => $date->format('Y-m'),
            'aucun' => (string) __('accueil_pwa.croise.total'),
            'quantite' => $quantite,
            'nombre' => '1',
            'montant' => $montant,
            'encaisse' => $encaisse,
        ];
    }

    /** Le libellé d'un mode de paiement — registre de `VenteService`, jamais recopié. */
    private function libelleMode(string $code): string
    {
        return VenteService::MODES_PAIEMENT[$code] ?? $code;
    }

    /**
     * Le droit de LIRE un module — même source que le middleware `module:`
     * et que `MenuLateral`, jamais une seconde règle.
     *
     * ## Le défaut fermé le 31/08/2026 : cet écran n'exigeait AUCUN droit
     *
     * `/pwa` est la page d'atterrissage : sa route ne porte pas de middleware
     * `module:M11`, et c'est délibéré — sans elle, un rôle sans M11 n'aurait
     * plus aucune page où arriver après sa connexion. Mais le composant, lui,
     * ne vérifiait rien non plus : il calculait et rendait les **quatorze
     * indicateurs consolidés** — chiffre d'affaires encaissé, dépenses,
     * trésorerie, créances, marge —, les séries mensuelles, la ventilation par
     * activité et le taux d'occupation, **à tout compte authentifié**.
     *
     * Un `guide` (`M11 = '-'`) recevait donc l'intégralité du pilotage
     * financier du Gîte sur sa page d'accueil, alors que la matrice RBAC le
     * lui refuse et que la route `GET /api/v1/tableau-de-bord` le refuse aussi.
     * Le masquage d'interface manquait, le contrôle de service manquait : les
     * trois niveaux exigés par `02_SOFTWARE_ARCHITECTURE.md` valaient zéro sur
     * cet écran.
     *
     * ⚠ Le refus doit se DISTINGUER de l'absence de mesure. `$indicateurs`
     * vaut déjà `null` quand une agrégation échoue, et la bande dit alors
     * « rien n'a été mesuré ». Rendre le même écran à un rôle sans droit
     * ferait chercher une panne là où il n'y a qu'un droit manquant — c'est
     * l'écart que PA-120 nomme entre « injoignable » et « refusé ».
     */
    private function peutLire(string $module): bool
    {
        /** @var User|null $utilisateur */
        $utilisateur = Auth::user();

        return $utilisateur !== null
            && $utilisateur->estActif()
            && $utilisateur->niveauSurModule($module) !== '-';
    }

    /** Le niveau réel sur un module — même source que le middleware `module:`. */
    private function peutEcrire(string $module): bool
    {
        /** @var User|null $utilisateur */
        $utilisateur = Auth::user();

        return $utilisateur !== null
            && $utilisateur->estActif()
            && $utilisateur->niveauSurModule($module) === 'C'
            // Le raccourci vit sur CET écran : son droit d'écriture est exigé
            // en plus de celui du module écrit (voir l'entête de classe).
            && $utilisateur->niveauSurModule(self::MODULE) === 'C';
    }

    // =====================================================================
    // Fabrique des six rapports — ce que l'écran a DÉJÀ LU, et rien de plus
    // =====================================================================

    /**
     * @return list<list<string>>
     */
    private function lignesRapport(TableauDeBordService $service, string $type, Periode $periode): array
    {
        return match ($type) {
            'reservations' => $this->lignesReservationsRapport($periode),
            'stocks' => $this->lignesStocksRapport(),
            'creances' => $this->lignesCreancesRapport(),
            'recettes' => $this->lignesRecettesRapport($periode),
            'ventes' => $this->lignesVentesRapport($periode),
            // ⚠ UNE SEULE fois : `indicateurs()` exécute quatorze agrégations,
            // et la même période ne se recalcule pas deux fois.
            default => $this->lignesIndicateurs($service->indicateurs($periode)),
        };
    }

    /**
     * « Liste des réservations » — les SIX colonnes du maître
     * (`rapports-engine.js` l.76-88), sur la période sélectionnée en haut de
     * page (le maître filtre sur `date_debut` ; ici `date_arrivee`, son
     * équivalent serveur).
     *
     * `sousTotal()`/`resteAPayer()` rendent `null` quand `tarif_nuit` manque
     * (réservations antérieures à PA-163) : un tiret, jamais un zéro qui se
     * lirait comme un séjour gratuit.
     *
     * @return list<list<string>>
     */
    private function lignesReservationsRapport(Periode $periode): array
    {
        $tiret = (string) __('accueil_pwa.tiret');

        return Reservation::query()
            ->with(['client', 'canal'])
            ->whereNot('statut', 'annulee')
            ->whereBetween('date_arrivee', [$periode->debut->toDateString(), $periode->fin->toDateString()])
            ->orderBy('date_arrivee')
            ->orderBy('id')
            ->get()
            ->map(fn (Reservation $reservation): array => [
                trim((string) $reservation->client?->nom.' '.(string) $reservation->client?->prenom),
                $reservation->canal === null ? $tiret : $reservation->canal->nom,
                $reservation->date_arrivee->format('d/m/Y'),
                $reservation->date_depart->format('d/m/Y'),
                $reservation->sousTotal() ?? $tiret,
                $reservation->resteAPayer() ?? $tiret,
            ])
            ->all();
    }

    /**
     * « État des stocks » — PA-119 : ce que « Stocks critiques » affiche déjà,
     * jamais tout le référentiel. Chaque ligne est SOUS le seuil par
     * construction : `articlesCritiques()` ne renvoie qu'elles.
     *
     * @return list<list<string>>
     */
    private function lignesStocksRapport(): array
    {
        $etat = (string) __('accueil_pwa.modale_rapport.stocks_etat');

        return $this->articlesCritiques()
            ->map(static fn (\stdClass $article): array => [
                (string) $article->libelle,
                (string) $article->stock,
                (string) $article->seuil_alerte,
                $etat,
            ])
            ->all();
    }

    /**
     * « État de créances » — PA-119 : les QUATRE TRANCHES déjà affichées au
     * graphique « Créances par ancienneté », jamais une liste nominative
     * qu'aucun bloc de cet écran ne montre.
     *
     * @return list<list<string>>
     */
    private function lignesCreancesRapport(): array
    {
        return array_map(
            static fn (array $tranche): array => [
                (string) __('accueil_pwa.creances.tranches.'.$tranche['cle']),
                (string) $tranche['pieces'],
                $tranche['montant'],
            ],
            $this->creancesParAnciennete(),
        );
    }

    /**
     * « État de recettes » — les CINQ colonnes du maître
     * (`rapports-engine.js` l.152-166), agrégées par jour depuis la MÊME
     * table de faits que le tableau croisé (`faitsCroises()`), jamais un
     * second agrégat (PA-121). Le maître exclut uniquement les Dépenses
     * (`f.source !== 'Dépenses'`) ; ventes et réservations comptent toutes
     * deux au chiffre d'affaires du jour.
     *
     * @return list<list<string>>
     */
    private function lignesRecettesRapport(Periode $periode): array
    {
        $parJour = [];

        foreach ($this->faitsCroises($periode, ['ventes', 'reservations']) as $fait) {
            $iso = $fait['jour_iso'];
            $parJour[$iso] ??= ['jour' => $fait['jour'], 'ca' => '0.00', 'encaisse' => '0.00', 'lignes' => 0];
            $parJour[$iso]['ca'] = bcadd($parJour[$iso]['ca'], $fait['montant'], 2);
            $parJour[$iso]['encaisse'] = bcadd($parJour[$iso]['encaisse'], $fait['encaisse'], 2);
            $parJour[$iso]['lignes']++;
        }

        ksort($parJour);

        return array_map(
            static fn (array $j): array => [
                $j['jour'],
                (string) $j['lignes'],
                $j['ca'],
                $j['encaisse'],
                // Écart = ce qui a été facturé sans être encaissé — une note de
                // chambre, par exemple. Jamais négatif : l'encaissé ne dépasse
                // pas le chiffre d'affaires du même jour.
                bcsub($j['ca'], $j['encaisse'], 2),
            ],
            array_values($parJour),
        );
    }

    /**
     * « État de ventes » — les SEPT colonnes du maître (`rapports-engine.js`
     * l.170-188), chronologiques (`jour_iso`, jamais `jour` qui ne trie pas).
     * Même table de faits que le tableau croisé, filtrée sur la seule source
     * Ventes — les réservations n'y figurent pas au maître.
     *
     * @return list<list<string>>
     */
    private function lignesVentesRapport(Periode $periode): array
    {
        $faits = $this->faitsCroises($periode, ['ventes']);

        usort($faits, static fn (array $a, array $b): int => $a['jour_iso'] <=> $b['jour_iso']);

        return array_map(
            static fn (array $f): array => [
                $f['jour'], $f['libelle'], $f['activite'], $f['tiers'],
                $f['quantite'], $f['montant'], $f['mode'],
            ],
            $faits,
        );
    }

    /**
     * Les huit indicateurs mis en lignes de rapport.
     *
     * Le libellé vient de la MÊME clé de langue que la carte affichée : deux
     * intitulés pour le même chiffre finiraient par diverger, et c'est le
     * document imprimé qui porterait le mauvais.
     *
     * @param  array<string, array{valeur: string, precedent: string, variation_pct: string|null, unite: string}>  $indicateurs
     * @return list<array{0: string, 1: string, 2: string}>
     */
    private function lignesIndicateurs(array $indicateurs): array
    {
        $lignes = [];

        foreach ($indicateurs as $cle => $kpi) {
            $lignes[] = [
                (string) __('accueil_pwa.kpi.'.$cle.'.libelle'),
                $kpi['valeur'],
                // `null` n'est pas « 0 % » : une base précédente nulle n'a pas
                // de variation, et l'écrire zéro dirait « stable ».
                $kpi['variation_pct'] ?? (string) __('accueil_pwa.tiret'),
            ];
        }

        return $lignes;
    }

    /**
     * @return list<string>
     */
    private function enTetesRapport(string $type): array
    {
        return match ($type) {
            // Les colonnes du maître pour chaque rapport — `rapports-engine.js`.
            // Les reformuler ferait porter au document remis des intitulés que
            // le client n'a jamais vus.
            'reservations' => [
                (string) __('accueil_pwa.modale_rapport.reservations_col_client'),
                (string) __('accueil_pwa.modale_rapport.reservations_col_canal'),
                (string) __('accueil_pwa.modale_rapport.reservations_col_arrivee'),
                (string) __('accueil_pwa.modale_rapport.reservations_col_depart'),
                (string) __('accueil_pwa.modale_rapport.reservations_col_total'),
                (string) __('accueil_pwa.modale_rapport.reservations_col_reste'),
            ],
            'stocks' => [
                (string) __('accueil_pwa.modale_rapport.stocks_col_article'),
                (string) __('accueil_pwa.modale_rapport.stocks_col_quantite'),
                (string) __('accueil_pwa.modale_rapport.stocks_col_seuil'),
                (string) __('accueil_pwa.modale_rapport.stocks_col_etat'),
            ],
            'creances' => [
                (string) __('accueil_pwa.modale_rapport.creances_col_tranche'),
                (string) __('accueil_pwa.modale_rapport.creances_col_pieces'),
                (string) __('accueil_pwa.modale_rapport.creances_col_montant'),
            ],
            'recettes' => [
                (string) __('accueil_pwa.modale_rapport.recettes_col_date'),
                (string) __('accueil_pwa.modale_rapport.recettes_col_mouvements'),
                (string) __('accueil_pwa.modale_rapport.recettes_col_ca'),
                (string) __('accueil_pwa.modale_rapport.recettes_col_encaisse'),
                (string) __('accueil_pwa.modale_rapport.recettes_col_ecart'),
            ],
            'ventes' => [
                (string) __('accueil_pwa.modale_rapport.ventes_col_date'),
                (string) __('accueil_pwa.modale_rapport.ventes_col_produit'),
                (string) __('accueil_pwa.modale_rapport.ventes_col_activite'),
                (string) __('accueil_pwa.modale_rapport.ventes_col_point_vente'),
                (string) __('accueil_pwa.modale_rapport.ventes_col_quantite'),
                (string) __('accueil_pwa.modale_rapport.ventes_col_montant'),
                (string) __('accueil_pwa.modale_rapport.ventes_col_mode'),
            ],
            default => [
                (string) __('accueil_pwa.col_indicateur'),
                (string) __('accueil_pwa.col_valeur'),
                (string) __('accueil_pwa.col_detail'),
            ],
        };
    }

    /**
     * @param  list<list<string>>  $lignes
     */
    private function exporterPdf(array $lignes, string $type, Periode $periode): StreamedResponse
    {
        $titre = (string) __('accueil_pwa.modale_rapport.'.$type);

        $pdf = Pdf::loadView('pdf.dashboard-rapport', [
            'entete' => $this->enTeteRapport($titre, $periode->libelle()),
            'titre' => $titre,
            'entetes' => $this->enTetesRapport($type),
            'lignes' => $lignes,
        ])->setPaper('a4', 'portrait');

        return response()->streamDownload(
            static function () use ($pdf): void {
                echo $pdf->output();
            },
            'tableau_de_bord_'.$type.'_'.CarbonImmutable::now()->format('Ymd_His').'.pdf',
        );
    }

    /**
     * ⚠ « Excel » est rendu en CSV quand la bibliothèque XLSX est absente —
     * BOM UTF-8 et point-virgule, convention serveur RG-19. L'écart est nommé,
     * jamais masqué : un fichier `.xlsx` qui contiendrait du CSV s'ouvrirait
     * sur un avertissement de corruption chez le comptable.
     *
     * @param  list<list<string>>  $lignes
     */
    private function exporterExcel(array $lignes, string $type, Periode $periode): BinaryFileResponse|StreamedResponse
    {
        $titre = (string) __('accueil_pwa.modale_rapport.'.$type);
        $horodatage = CarbonImmutable::now()->format('Ymd_His');

        if (class_exists(Excel::class)) {
            return Excel::download(
                new DashboardExport($lignes, $this->enTetesRapport($type), $titre, $periode->libelle()),
                'tableau_de_bord_'.$type.'_'.$horodatage.'.xlsx',
            );
        }

        $entetes = $this->enTetesRapport($type);

        return response()->streamDownload(
            static function () use ($lignes, $entetes, $titre, $periode): void {
                $sortie = fopen('php://output', 'w');

                if ($sortie === false) {
                    return;
                }

                // BOM UTF-8 : sans lui, Excel lit « Dépenses » en « DÃ©penses ».
                fwrite($sortie, "\xEF\xBB\xBF");
                fputcsv($sortie, [$titre], ';');
                fputcsv($sortie, [$periode->libelle()], ';');
                fputcsv($sortie, [], ';');
                fputcsv($sortie, $entetes, ';');

                foreach ($lignes as $ligne) {
                    fputcsv($sortie, $ligne, ';');
                }

                fclose($sortie);
            },
            'tableau_de_bord_'.$type.'_'.$horodatage.'.csv',
            ['Content-Type' => 'text/csv; charset=UTF-8'],
        );
    }

}
