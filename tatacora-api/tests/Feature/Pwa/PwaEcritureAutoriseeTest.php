<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Pwa\Livewire\Concerns\FormulaireModal;
use App\Pwa\Support\AutoriseArchivage;
use App\Pwa\Support\AutoriseEcriture;
use Database\Seeders\RolePermissionSeeder;
use PHPUnit\Framework\Attributes\Test;
use ReflectionClass;
use ReflectionMethod;
use Tests\TestCase;

/**
 * Toute action d'écriture de la PWA exige un droit — et le PROUVE.
 *
 * ## Ce test est l'INVERSE de `PwaActionsReluesTest`, pas sa suppression
 *
 * Le Product Owner a tranché le 27/08/2026 : la PWA doit permettre toutes les
 * opérations. Jusque-là, deux gardes tenaient la lecture seule —
 * `ForcerLectureSeule` sur les routes `/pwa`, et une liste fermée d'actions
 * Livewire, seul chemin que le middleware ne couvre pas (PA-67).
 *
 * Les retirer sans rien mettre à la place aurait laissé les écritures du canal
 * `web` **sans aucun contrôle d'accès**, alors que le canal `sanctum` en impose
 * un sur 30 routes sur 35. La garde est donc inversée, pas levée :
 *
 * - avant : « aucune action publique n'écrit » ;
 * - après : « toute action publique écrit sous condition de droit, et le
 *   fichier le montre ».
 *
 * ## Elle PRÉSUME l'écriture — c'est le cœur du contrat
 *
 * Une méthode publique inconnue est traitée comme une écriture. Pour être
 * acceptée sans autorisation, elle doit être **inscrite** dans la liste des
 * méthodes de lecture ci-dessous, donc relue par quelqu'un. C'est la règle
 * générale du dépôt appliquée ici : *un cas ajouté demain ne doit pas obtenir
 * un comportement par omission*.
 *
 * ## Elle VOIT une écriture passée par un Service de domaine (28/08/2026)
 *
 * `LARAVEL_PWA.md` §3 impose d'appeler le `Service` de domaine — et jusqu'au
 * 28/08/2026, cette garde ne détectait QUE l'Eloquent nu : le motif que tout
 * le plan CRUD généralise était précisément celui auquel elle était aveugle.
 * Un registre des méthodes d'écriture des Services est donc construit **par
 * réflexion sur `app/Domain/x/Services`** — jamais recopié à la main, deux
 * listes finissant toujours par diverger — et un appel `->creer(`,
 * `->enregistrerPiece(`… dans un composant PWA compte comme une persistance.
 * La règle de reconnaissance et ses limites sont documentées sur
 * `registreEcrituresDeServices()`.
 *
 * ## Et elle ferme le trou de la liste : une écriture CACHÉE dans une lecture
 *
 * Inscrire `render()` comme méthode de lecture ne dispense de rien : le corps
 * de **chaque** méthode, inscrite ou non, est relu à la recherche d'un appel
 * de persistance — Eloquent OU Service. Sans cela, il suffirait d'écrire dans
 * `render()` pour échapper au contrat.
 *
 * ## `exigerEcriture()` reçoit le module DE L'ÉCRAN, jamais un littéral
 *
 * `exigerEcriture('M1')` écrit dans un composant M7 passerait tous les
 * contrôles d'existence : le droit serait exigé, mais sur le mauvais module.
 * Tout appel doit donc s'écrire `exigerEcriture(self::MODULE)` (ou
 * `static::MODULE`), et la constante `MODULE` doit exister et porter un
 * module de la matrice RBAC. Ce que ce contrôle ne couvre PAS : une constante
 * `MODULE` elle-même fausse (un écran M7 déclarant `MODULE = 'M1'`) — la
 * correspondance écran → module n'a pas de source dérivable, elle se relit.
 *
 * ## Elle ÉCHOUE si la source manque, et porte des planchers
 *
 * Un balayage vide est vert. C'est le défaut que cette garde protège, et il
 * est arrivé trois fois dans ce dépôt.
 */
final class PwaEcritureAutoriseeTest extends TestCase
{
    /**
     * Les méthodes publiques qui NE sont PAS des écritures.
     *
     * Liste fermée. Trois familles, et aucune n'est un joker :
     *
     * 1. les points d'entrée du CADRE Livewire (`render`, `mount`, `boot`,
     *    `hydrate`, `dehydrate`, `updated…`, `rules`, …) ;
     * 2. la SESSION — se connecter et se déconnecter écrivent la session, pas
     *    une table métier. Elles ne relèvent d'aucun module, donc d'aucun
     *    niveau RBAC : exiger un droit pour se déconnecter enfermerait dehors
     *    un utilisateur au rôle mal configuré ;
     * 3. la NAVIGATION et le calcul d'affichage, qui ne touchent aucune table.
     */
    private const METHODES_DE_LECTURE = [
        'render',
        'mount',
        'boot',
        'booted',
        'hydrate',
        'dehydrate',
        'rules',
        'messages',
        'validationAttributes',
        'paginationView',
        'placeholder',
        'seConnecter',
        'seDeconnecter',
        'ecransVisibles',

        // Le verrou de session — `deverrouiller()` (01/09/2026). Même
        // famille que `seConnecter`/`seDeconnecter` juste au-dessus : il
        // écrit la SESSION (via `Auth::validate()`, qui ne persiste rien),
        // jamais une table métier, donc aucun niveau RBAC n'a de sens ici.
        'deverrouiller',

        // Les modales d'ouverture — `avancer()` (02/09/2026) : ne touche que
        // l'etape courante et le drapeau de SESSION pose a la connexion,
        // jamais une table metier — meme famille que `deverrouiller`.
        'avancer',

        // 4. L'EXPORT ET L'IMPRESSION — inscrits le 31/08/2026.
        //
        // Un export ne produit rien de neuf : il rend, sur un autre papier,
        // des données que l'utilisateur a déjà sous les yeux. Exiger le
        // niveau `C` pour exporter retirerait la fonction à tous les rôles en
        // lecture — un `magasinier` en `L` sur M6 ne pouvait plus sortir son
        // état de stock, alors que l'écran le lui affiche.
        //
        // L'export n'ajoute aucun accès : il ne rend que ce que le composant
        // affichait déjà. C'est la présomption d'écriture de cette garde qui
        // débordait, pas le code.
        //
        // ⚠ Précision qui compte, écrite plutôt que tue (31/08/2026) : ce
        // n'est PAS le middleware `module:M#,L` qui protège cet appel. Le
        // middleware garde la route `/pwa/…`, donc le GET initial ; l'action
        // Livewire passe, elle, par la route dédiée du paquet, hors du
        // groupe (PA-67). Ce qui tient réellement, c'est qu'appeler l'action
        // exige un instantané de composant valide, qu'un rôle privé de
        // l'écran n'obtient jamais légitimement.
        //
        // La nuance est notée parce qu'une justification fausse dans une
        // garde est exactement ce que ce dépôt appelle un motif périmé : le
        // jour où quelqu'un relira cette liste pour décider d'une entrée, il
        // doit lire la vraie raison, pas une raison plausible.
        //
        // ⚠ Les inscrire ne les dispense de RIEN : le corps de chaque
        // méthode, inscrite ou non, reste relu à la recherche d'un appel de
        // persistance (voir l'entête). Le jour où un `genererExport`
        // archiverait sa propre sortie, il redeviendrait une écriture et
        // cette garde le dirait.
        'ouvrirExport',
        'genererExport',
        'exporterPdf',
        // `exporterExcel` a QUITTÉ cette liste le 02/09/2026 : plus aucune
        // méthode publique ne porte ce nom (export unifié, dérogation PO du
        // 01/09/2026 — `ClientsCreances` et `Facturation` sont passées à
        // `ouvrirExport`/`genererExport`). Une entrée sans appelant est un
        // joker dormant : un futur `exporterExcel` qui ÉCRIRAIT serait
        // exempté d'office par elle.
        'telechargerModeleCsv',
        'imprimerFichePrix',
        'imprimerRapportInventairePdf',
        'telechargerTicket',
        'ouvrirJournalDuJour',
        'imprimerReleveClient',

        // 5. L'ÉTAT D'INTERFACE — fermer une modale, changer d'onglet.
        //
        // Ces deux gestes ne touchent aucune table et ne révèlent aucune
        // donnée que la page ne rendait pas déjà. `fermerModales` est
        // l'inverse exact d'une ouverture : refuser la fermeture à un rôle
        // qui a réussi à ouvrir l'enfermerait dans la modale.
        //
        // `changerOnglet` reste ici parce que l'onglet est une VUE. Si un
        // onglet donne un jour accès à des données d'un autre module, ce
        // n'est pas cette liste qu'il faut élargir : c'est le middleware de
        // la route qui doit le dire.
        'fermerModales',
        'changerOnglet',

        // 6. UNE LECTURE SEULE explicitement nommée — PA-165 (02/09/2026).
        //
        // `ClientsCreances::ouvrirHistoriqueClient()` ouvre le relevé
        // (relances + paiements) d'un client déjà affiché dans le registre
        // de la page : consulter n'écrit rien, même famille que l'export.
        'ouvrirHistoriqueClient',

        // 7. IDEM, sur M4/M5 — demande du Product Owner du 01/09/2026.
        //
        // `EcranDeCarte::ouvrirHistoriquePrix()` ouvre la trace d'un article
        // déjà affiché dans le registre de la page (`historique_prix_carte`,
        // écrite par `CarteBoissonObserver`/`PlatObserver`) : consulter
        // n'écrit rien, même famille qu'`ouvrirHistoriqueClient` juste
        // au-dessus.
        'ouvrirHistoriquePrix',

        // 7 bis. L'ONGLET « VENTES DU RAYON » de `EcranDeCarte` — ajout du
        // 03/09/2026 (Product Owner), sur `CarteBar` (M5) et
        // `CarteRestaurant` (M4).
        //
        // Il n'ajoute QU'UNE méthode publique, `updated()` : le crochet du
        // cadre Livewire qui remet la pagination à 1 quand un filtre change.
        // Elle est une LECTURE — elle touche `$pageCourante`, une propriété
        // d'affichage, et rien d'autre.
        //
        // ⚠ Elle N'EST PAS inscrite dans cette liste, et c'est délibéré : le
        // balayage exempte déjà tout nom commençant par `updated` (voir plus
        // bas, `str_starts_with($methode->getName(), 'updated')`), parce que
        // ce sont des points d'entrée du cadre et non des boutons. Une entrée
        // littérale ici serait redondante avec cette règle — et cette liste
        // vient précisément de perdre `exporterExcel` pour cause d'entrée
        // sans effet. Ce paragraphe tient donc la relecture que l'entrée
        // aurait tenue.
        //
        // ⚠ L'exemption de préfixe ne dispense de RIEN : le corps de
        // `updated()` reste relu par le contrôle (1) — le jour où elle
        // persisterait quoi que ce soit, la garde le dirait.
        //
        // Les FILTRES de l'onglet (recherche, statut, plage de dates) et la
        // page courante sont des propriétés `#[Url]`, jamais des actions :
        // ils n'ajoutent aucune surface publique. Le changement d'onglet
        // passe par `$set('onglet', 'ventes')`, une expression du cadre.

        // 8. Mon profil — `ouvrirFormulaireMotDePasse()` (01/09/2026). Remet
        // la saisie et les erreurs à zéro, comme `FormulaireModal::
        // ouvrirFormulaire()` ailleurs, mais écrite à la main ici : cet
        // écran ne porte aucun module RBAC (voir `MonProfil`). N'écrit rien.
        'ouvrirFormulaireMotDePasse',

        // 9. Contact éditeur — `ouvrirFormulaireMessage()`/
        // `ouvrirFormulaireBug()` (01/09/2026). Même famille : remise à zéro
        // de la saisie et des erreurs, aucun module RBAC sur cet écran.
        'ouvrirFormulaireMessage',
        'ouvrirFormulaireBug',

        // 10. Import & Export — `telechargerSauvegarde()` (01/09/2026) :
        // lit un fichier de sauvegarde DÉJÀ produit, même famille que
        // `telechargerTicket`. Ne produit rien de neuf. (Le fichier témoin
        // « téléchargée » posé au passage est un marqueur du système de
        // fichiers, jamais une table — 02/09/2026.)
        'telechargerSauvegarde',

        // 10bis. Import & Export — `exporterTable()` (02/09/2026) : rend le
        // contenu JSON d'une table de la liste FERMÉE d'`ExportTableService`
        // (jamais `utilisateurs` ni les jetons), même famille que l'export.
        // Aucune persistance.
        'exporterTable',

        // 10. Les trois écritures HORS MODULE elles-mêmes (voir
        // `ECRITURES_HORS_MODULE` ci-dessous) doivent AUSSI figurer ici :
        // sans quoi la règle (2) — « méthode publique inconnue présumée
        // écriture » — les signalerait quand même, l'exemption de
        // `ECRITURES_HORS_MODULE` ne couvrant que la règle (1). Même
        // schéma que `seConnecter`, déjà inscrite ci-dessus dans les deux
        // registres à la fois.
        'changerMotDePasse',
        'envoyerMessage',
        'signalerBug',
        // `ClocheNotifications` (01/09/2026) — même schéma : inscrites dans
        // les deux registres, l'exemption hors-module ne couvrant que la
        // règle (1).
        'marquerToutLu',
        'marquerLu',

        // 11. M10 — `Hub::ouvrirPlanAmortissement()` (Vague E, 01/09/2026).
        //
        // Ouvre le plan d'amortissement d'une immobilisation déjà affichée
        // dans le tableau de l'onglet « Immobilisations » : consulter n'écrit
        // rien, même famille qu'`ouvrirHistoriqueClient`/`ouvrirHistoriquePrix`
        // ci-dessus. `ImmobilisationService::planAmortissement()` est une
        // LECTURE pure (aucun `create`/`update`/`save`).
        'ouvrirPlanAmortissement',
    ];

    /**
     * Les écritures qui ne relèvent d'AUCUN module, nommées une par une.
     *
     * Liste fermée, jamais un motif. Une seule entrée à ce jour, et sa raison
     * doit être relue avant d'en ajouter une seconde :
     *
     * `Connexion::seConnecter` horodate `derniere_connexion` sur la ligne de
     * l'utilisateur **qui est en train de s'authentifier**
     * (`app/Pwa/Livewire/Connexion.php` l.98). Cette écriture précède tout
     * contexte de module : au moment où elle a lieu, on vient justement
     * d'établir qui est l'utilisateur. La soumettre à un niveau RBAC
     * enfermerait dehors quiconque a un rôle mal configuré — c'est-à-dire
     * exactement les comptes qu'un administrateur doit pouvoir dépanner en se
     * connectant.
     *
     * ⚠ Cette exemption ne couvre QUE cette méthode de cette classe. Elle ne
     * s'étend pas à `Connexion` entière : une seconde écriture ajoutée là
     * serait signalée.
     *
     * `MonProfil::changerMotDePasse` (01/09/2026) — même famille : elle
     * modifie `utilisateurs.mot_de_passe_hash` du compte QUI FAIT LA
     * DEMANDE, jamais celui d'un tiers. `mon-profil.html` ne porte aucun
     * `data-module`, et exiger un niveau RBAC sur un module métier
     * enfermerait dehors, mot de passe compris, un utilisateur dont la
     * matrice de droits est mal configurée — exactement le cas que cette
     * même exemption protège déjà pour la connexion.
     *
     * `ContactEditeur::envoyerMessage`/`ContactEditeur::signalerBug`
     * (01/09/2026) — même famille : contacter l'éditeur ou signaler un bug
     * n'est pas une opération sur un module métier, c'est un geste que TOUT
     * compte authentifié doit pouvoir faire — y compris, surtout, un rôle
     * dont la matrice de droits est mal configurée et qui a besoin de le
     * signaler. `contact-editeur.html` ne porte aucun `data-module`.
     */
    /**
     * Les ecritures MULTI-MODULES d'un composant transverse (02/09/2026).
     *
     * `AlertesOuvertureModales` porte deux gestes de modules DIFFERENTS —
     * le check-out (M1) et la relance (M3) — que le maitre pose dans la meme
     * modale d'ouverture. `self::MODULE` ne peut pas designer les deux : le
     * registre ci-dessous declare, methode par methode, le module exact que
     * le litteral DOIT porter, et la garde verifie cette correspondance —
     * meme securite que `self::MODULE`, relue ici au lieu de la classe.
     * Liste FERMEE : une ecriture multi-modules ajoutee demain s'inscrit,
     * donc se relit.
     *
     * @var array<string, string>
     */
    private const ECRITURES_MULTI_MODULES = [
        'AlertesOuvertureModales::effectuerCheckOutOuverture' => 'M1',
        'AlertesOuvertureModales::tracerRelanceOuverture' => 'M3',
    ];

    private const ECRITURES_HORS_MODULE = [
        'Connexion::seConnecter',
        'MonProfil::changerMotDePasse',
        'ContactEditeur::envoyerMessage',
        'ContactEditeur::signalerBug',

        // `ClocheNotifications` (01/09/2026) — même famille : ces deux
        // gestes n'écrivent que l'état « vu » (`alertes_vues`) du compte QUI
        // FAIT LE GESTE, jamais une donnée métier. Le RBAC s'applique en
        // LECTURE : chaque alerte est filtrée par le module qu'elle concerne
        // (`MenuLateral::moduleAccessible`), la même source que le menu.
        'ClocheNotifications::marquerToutLu',
        'ClocheNotifications::marquerLu',
    ];

    /**
     * Les appels de Service que le registre marque « écriture » et qui n'en
     * sont PAS sur le composant nommé — l'échappatoire aux collisions de nom.
     *
     * Le registre des écritures de Services est un jeu de NOMS (voir
     * `registreEcrituresDeServices()`) : un composant qui appellerait sur un
     * autre objet une méthode homonyme d'une écriture de Service serait
     * signalé à tort. VIDE à ce jour — aucune collision mesurée. Chaque
     * entrée future s'écrit `Classe::methode` avec sa raison en commentaire,
     * et la relecture est le prix de l'entrée : sans cette liste, le premier
     * faux positif ferait élargir `METHODES_DE_LECTURE`, qui est un joker.
     *
     * (Méthode plutôt que constante : PHPStan fige le type d'une constante
     * vide en `array{}` et refuse le `in_array` qui la lit.)
     *
     * @return list<string>
     */
    private function appelsHomonymesRelus(): array
    {
        return [];
    }

    /**
     * Ce qui, dans un corps de méthode, PERSISTE quelque chose via Eloquent.
     *
     * Volontairement étroit et nommé, jamais un motif large : un motif vague
     * produirait des faux positifs — `$collection->update()` d'une vue, un
     * `save()` de session — et le premier développeur qui en rencontrerait un
     * désarmerait la garde entière.
     *
     * Ce que ces motifs ne couvrent PAS, mesuré le 28/08/2026 : `increment`,
     * `decrement`, `touch`, `attach`/`detach`/`sync`, `firstOrCreate`,
     * `createMany`. Aucun Service ni composant du dépôt ne les emploie à ce
     * jour ; le premier qui en emploierait un doit ajouter le motif ET son
     * échantillon au cas `les_motifs_de_persistance_mordent…`.
     *
     * @return array<string, string>
     */
    private function motifsDePersistance(): array
    {
        return [
            'save' => '/->\s*save\s*\(/',
            'create' => '/::\s*create\s*\(|->\s*create\s*\(/',
            'update' => '/->\s*update\s*\(/',
            'delete' => '/->\s*delete\s*\(|->\s*forceDelete\s*\(/',
            'updateOrCreate' => '/updateOrCreate\s*\(/',
            'insert' => '/->\s*insert\s*\(/',
            'requete_brute' => '/DB::\s*(statement|insert|update|delete)\s*\(/',
        ];
    }

    // ================================================================
    // Le registre des écritures de Services — construit, jamais recopié
    // ================================================================

    /**
     * Les noms des méthodes PUBLIQUES d'un Service de domaine qui écrivent.
     *
     * ## La règle de reconnaissance, décidée sur mesure (28/08/2026)
     *
     * Mesure préalable sur les 46 fichiers de `app/Domain/x/Services` :
     * les écritures directes se voient toutes par les motifs de persistance
     * d'Eloquent — mais `MouvementStockService::entree/sortie/perte`
     * délèguent à une méthode PRIVÉE (`enregistrer`), et
     * `DeductionStockCuisineService::deduire` écrit via le Service d'un
     * AUTRE domaine. La règle est donc en trois pas :
     *
     * 1. une méthode (toute visibilité) dont le corps porte un motif de
     *    persistance écrit ;
     * 2. fermeture INTRA-classe : une méthode qui appelle par `$this->`,
     *    `self::` ou `static::` une méthode écrivante de sa classe écrit ;
     * 3. fermeture INTER-services, par NOM : une méthode qui porte
     *    `->nom(` où `nom` est une écriture publique déjà connue écrit.
     *    Répété jusqu'au point fixe.
     *
     * ## Ce que la règle ne couvre pas, et c'est écrit plutôt que caché
     *
     * - Un appel DYNAMIQUE (`$service->{$methode}()`, `call_user_func`) est
     *   invisible — aucun ne figure au dépôt.
     * - Une écriture portée par une méthode de MODÈLE métier (un
     *   `$facture->figer()` qui ferait `save()` en interne) : seuls les
     *   Services sont balayés. Aucun composant PWA n'appelle de méthode de
     *   modèle écrivante à ce jour ; l'Eloquent nu, lui, reste vu par les
     *   motifs directs.
     * - La fermeture par nom (pas 3) sur-approxime : elle marquerait un appel
     *   homonyme sur un objet qui n'est pas un Service. Les faux positifs se
     *   règlent par `APPELS_HOMONYMES_RELUS`, jamais en élargissant les
     *   méthodes de lecture.
     * - Comme tout ce fichier, le balayage lit le SOURCE : un appel écrit
     *   dans un commentaire compte. C'est le prix du contrat, le même que
     *   celui de `t-trois-sources.js`, et il penche du côté sûr.
     *
     * ## Le pas 2 est redondant AUJOURD'HUI, et c'est mesuré, pas supposé
     *
     * Mutation du 28/08/2026 : neutraliser le pas 2 n'a fait rougir aucun
     * ancrage — chaque délégation intra-classe du dépôt passe par un nom qui
     * est AUSSI une écriture publique d'un autre Service
     * (`MouvementStockService::enregistrer`, privée, est homonyme de
     * `VenteBarService::enregistrer`, publique), donc le pas 3 la rattrape.
     * Le pas 2 est conservé parce que cette redondance est un ACCIDENT de
     * nommage : renommer la méthode de `VenteBarService` la ferait disparaître
     * en silence. L'ancrage qui le prouve calcule le registre SANS le pas 3
     * (`$fermetureInterServices: false`) — là, seul le pas 2 peut voir
     * `sortie`.
     *
     * @return list<string> noms triés, dédupliqués
     */
    private function registreEcrituresDeServices(bool $fermetureInterServices = true): array
    {
        $racine = app_path('Domain');
        $this->assertDirectoryExists(
            $racine,
            'Le repertoire des domaines est introuvable : le registre des '
            .'ecritures de Services serait vide, donc la garde aveugle aux '
            .'appels de Service — le defaut meme qu elle ferme.',
        );

        $fichiers = glob($racine.'/*/Services/*.php') ?: [];

        // Plancher : 46 fichiers mesurés le 28/08/2026. En dessous de 40, un
        // dossier a été déplacé et le balayage est devenu creux, donc vert.
        $this->assertGreaterThanOrEqual(
            40,
            count($fichiers),
            'Seuls '.count($fichiers).' fichiers de Service relus, contre 46 '
            .'mesures. Le registre des ecritures est devenu creux.',
        );

        // ---- pas 1 : les écritures directes, toutes visibilités ----------
        /** @var array<class-string, array<string, array{src: string, ecrit: bool, publique: bool}>> $classes */
        $classes = [];

        foreach ($fichiers as $fichier) {
            $relatif = str_replace([$racine, '.php'], '', $fichier);
            $classe = 'App\\Domain'.str_replace('/', '\\', str_replace('\\', '/', $relatif));

            if (interface_exists($classe)) {
                continue;
            }
            $this->assertTrue(
                class_exists($classe),
                "Le fichier de Service {$fichier} ne porte pas la classe {$classe} : "
                .'le registre ne peut pas le relire, et une ecriture y serait invisible.',
            );

            $reflet = new ReflectionClass($classe);
            foreach ($reflet->getMethods() as $methode) {
                if ($methode->getDeclaringClass()->getName() !== $classe
                    || $methode->isConstructor() || $methode->isAbstract()) {
                    continue;
                }
                $source = $this->sourceDe($methode);
                $ecrit = false;
                foreach ($this->motifsDePersistance() as $motif) {
                    if (preg_match($motif, $source) === 1) {
                        $ecrit = true;
                        break;
                    }
                }
                $classes[$classe][$methode->getName()] = [
                    'src' => $source,
                    'ecrit' => $ecrit,
                    'publique' => $methode->isPublic(),
                ];
            }
        }

        // ---- pas 2 et 3 : fermetures, jusqu'au point fixe ----------------
        do {
            $change = false;

            // Les noms publics écrivants connus à ce tour, pour le pas 3.
            $publiques = [];
            foreach ($classes as $methodes) {
                foreach ($methodes as $nom => $infos) {
                    if ($infos['ecrit'] && $infos['publique']) {
                        $publiques[$nom] = true;
                    }
                }
            }
            $motifInterServices = $publiques === []
                ? null
                : '/->\s*(?:'.implode('|', array_map('preg_quote', array_keys($publiques))).')\s*\(/';

            foreach ($classes as $classe => $methodes) {
                foreach ($methodes as $nom => $infos) {
                    if ($infos['ecrit']) {
                        continue;
                    }

                    // pas 2 — intra-classe, toutes visibilités.
                    foreach ($methodes as $autre => $infosAutre) {
                        if ($infosAutre['ecrit'] && preg_match(
                            '/(?:\$this->|self::|static::)\s*'.preg_quote($autre, '/').'\s*\(/',
                            $infos['src'],
                        ) === 1) {
                            $classes[$classe][$nom]['ecrit'] = true;
                            $change = true;
                            continue 2;
                        }
                    }

                    // pas 3 — inter-services, par nom public.
                    if ($fermetureInterServices
                        && $motifInterServices !== null
                        && preg_match($motifInterServices, $infos['src']) === 1) {
                        $classes[$classe][$nom]['ecrit'] = true;
                        $change = true;
                    }
                }
            }
        } while ($change);

        $registre = [];
        foreach ($classes as $methodes) {
            foreach ($methodes as $nom => $infos) {
                if ($infos['ecrit'] && $infos['publique']) {
                    $registre[$nom] = true;
                }
            }
        }
        $registre = array_keys($registre);
        sort($registre);

        return $registre;
    }

    /**
     * Les TRAITS de motif dont les méthodes peuvent garder pour leurs
     * appelants.
     *
     * `AutoriseArchivage` a rejoint la liste le 03/09/2026 (archivage des
     * référentiels, demande du Product Owner) : son `exigerArchivage()`
     * appelle `exigerEcriture(static::MODULE)` PUIS ajoute la condition de
     * rôle et de bascule. L'inscrire ici plutôt que d'écrire les deux appels
     * dans chaque action évite qu'un écran garde l'écriture et OUBLIE la
     * seconde moitié — le contrôle qui compte n'a alors plus d'auteur unique.
     *
     * @var list<class-string>
     */
    private const TRAITS_DE_MOTIF = [
        FormulaireModal::class,
        AutoriseArchivage::class,
    ];

    /**
     * Les méthodes des motifs `FormulaireModal` et `AutoriseArchivage` qui
     * GARDENT elles-mêmes — un appel `$this->ouvrirFormulaire(…)` ou
     * `$this->exigerArchivage()` vaut `exigerEcriture(self::MODULE)`.
     *
     * Dérivées des traits par réflexion, jamais listées : une méthode d'un
     * motif n'est un délégué gardé QUE si son corps porte réellement
     * `exigerEcriture(static::MODULE)` — retirer la garde d'un trait retire
     * aussitôt le laissez-passer de tous ses appelants.
     *
     * @return list<string>
     */
    private function deleguesGardesDuMotif(): array
    {
        $delegues = [];

        foreach (self::TRAITS_DE_MOTIF as $trait) {
            $reflet = new ReflectionClass($trait);

            foreach ($reflet->getMethods() as $methode) {
                if (preg_match(
                    '/\$this->exigerEcriture\(\s*(?:self|static)::MODULE\s*\)/',
                    $this->sourceDe($methode),
                ) === 1) {
                    $delegues[] = $methode->getName();
                }
            }
        }

        $delegues = array_values(array_unique($delegues));
        sort($delegues);

        return $delegues;
    }

    /**
     * Le répertoire des composants, relu en dur : il ne doit pas disparaître.
     *
     * @return list<string> les chemins absolus des fichiers de composants
     */
    private function fichiersDesComposants(): array
    {
        $racine = app_path('Pwa/Livewire');

        $this->assertDirectoryExists(
            $racine,
            'Le répertoire des composants PWA est introuvable. Cette garde '
            .'échoue plutôt que de sauter : un balayage vide serait vert, et '
            .'c est exactement le défaut qu elle protège.',
        );

        $fichiers = [];
        $iterateur = new \RecursiveIteratorIterator(
            new \RecursiveDirectoryIterator($racine, \FilesystemIterator::SKIP_DOTS),
        );
        foreach ($iterateur as $fichier) {
            if ($fichier->isFile() && $fichier->getExtension() === 'php') {
                $fichiers[] = $fichier->getPathname();
            }
        }
        sort($fichiers);

        return $fichiers;
    }

    /** La classe portée par un fichier de composant. */
    private function classeDe(string $chemin): string
    {
        $relatif = str_replace([app_path('Pwa'), '.php'], '', $chemin);
        $relatif = str_replace(['/', '\\'], '\\', $relatif);

        return 'App\\Pwa'.$relatif;
    }

    /** Le code source d'une méthode, lu dans son fichier. */
    private function sourceDe(ReflectionMethod $methode): string
    {
        $fichier = $methode->getFileName();
        if ($fichier === false) {
            return '';
        }
        $lignes = file($fichier);
        if ($lignes === false) {
            return '';
        }

        return implode(
            '',
            array_slice(
                $lignes,
                $methode->getStartLine() - 1,
                $methode->getEndLine() - $methode->getStartLine() + 1,
            ),
        );
    }

    // =====================================================================

    #[Test]
    public function les_motifs_de_persistance_mordent_sur_un_echantillon_fabrique(): void
    {
        // Sans ce cas, un motif cassé ne correspondrait plus à rien et tout le
        // balayage passerait à vide — donc vert. Le dépôt en a trois
        // occurrences réelles (un `\b` de regex devenu l octet 0x08).
        $motifs = $this->motifsDePersistance();

        $this->assertMatchesRegularExpression($motifs['save'], '$f->save();');
        $this->assertMatchesRegularExpression($motifs['create'], 'Fournisseur::create($d);');
        $this->assertMatchesRegularExpression($motifs['update'], '$f->update($d);');
        $this->assertMatchesRegularExpression($motifs['delete'], '$f->delete();');
        $this->assertMatchesRegularExpression($motifs['insert'], '$q->insert($d);');
        $this->assertMatchesRegularExpression(
            $motifs['requete_brute'],
            'DB::statement("DELETE FROM x");',
        );

        // Et ils ne mordent pas sur une lecture — un motif qui refuserait tout
        // serait aussi inutile qu un motif qui n accepte rien.
        $this->assertDoesNotMatchRegularExpression($motifs['save'], '$x = $q->get();');
        $this->assertDoesNotMatchRegularExpression($motifs['update'], '$x = $q->first();');
    }

    #[Test]
    public function le_registre_des_ecritures_de_services_reconnait_les_cas_mesures(): void
    {
        $registre = $this->registreEcrituresDeServices();

        // Plancher : 27 noms mesurés le 28/08/2026. En dessous de 20, la
        // réflexion s'est cassée quelque part et le balayage des composants
        // ne verrait plus les appels de Service — vert, donc.
        $this->assertGreaterThanOrEqual(
            20,
            count($registre),
            'Le registre des ecritures de Services est tombe a '.count($registre)
            .' noms : la reconnaissance est devenue creuse.',
        );

        // Ancrages POSITIFS, un par pas de la règle :
        // - écriture directe ;
        $this->assertContains('enregistrerPiece', $registre, 'EcritureComptableService::enregistrerPiece (ecriture directe) n est plus reconnue.');
        // - écriture cachée derrière une méthode PRIVÉE de la même classe.
        //   ⚠ Sur le registre COMPLET, `sortie` est aussi atteinte par le
        //   pas 3 (collision de nom avec `VenteBarService::enregistrer`) : la
        //   premiere version de cet ancrage n a pas mordu quand le pas 2 a
        //   ete neutralise. On calcule donc le registre SANS pas 3 — la,
        //   seule la fermeture intra-classe peut la voir.
        $this->assertContains(
            'sortie',
            $this->registreEcrituresDeServices(fermetureInterServices: false),
            'MouvementStockService::sortie (ecriture via une methode privee) n est plus reconnue : la fermeture intra-classe est cassee.',
        );
        // - écriture via le Service d'un AUTRE domaine.
        $this->assertContains('deduire', $registre, 'DeductionStockCuisineService::deduire (ecriture via un autre Service) n est plus reconnue : la fermeture inter-services est cassee.');

        // Ancrage NÉGATIF : une lecture pure ne doit pas y entrer, sinon le
        // registre finit par couvrir tout et ne plus rien dire.
        $this->assertNotContains('indicateurs', $registre, 'TableauDeBordService::indicateurs (lecture pure) est marquee ecriture : la regle sur-approxime au point de tout couvrir.');

        // Et le motif composé mord sur un appel fabriqué, pas sur un homonyme
        // préfixé — même précaution que pour les motifs Eloquent.
        $motif = '/->\s*(?:'.implode('|', array_map('preg_quote', $registre)).')\s*\(/';
        $this->assertMatchesRegularExpression($motif, '$this->reservations->creer($donnees);');
        $this->assertDoesNotMatchRegularExpression($motif, '$this->creerAffichage($donnees);');
    }

    #[Test]
    public function le_motif_de_formulaire_porte_au_moins_ses_deux_delegues_gardes(): void
    {
        $delegues = $this->deleguesGardesDuMotif();

        // `ouvrirFormulaire` et `validerEcriture` sont les deux gestes gardés
        // du motif (lot 0.2). S'ils sortent de cette liste, c'est que leur
        // corps n'appelle plus `exigerEcriture(static::MODULE)` — et chaque
        // écran qui leur délègue vient de perdre sa garde en silence.
        $this->assertContains('ouvrirFormulaire', $delegues);
        $this->assertContains('validerEcriture', $delegues);

        // Le troisième délégué gardé, ajouté le 03/09/2026 avec l'archivage
        // des référentiels. S'il sort de cette liste, c'est que son corps
        // n'appelle plus `exigerEcriture(static::MODULE)` — et chaque bouton
        // rouge de la PWA vient de perdre sa garde RBAC en silence, pendant
        // que la condition de rôle et de bascule, elle, resterait en place :
        // le refus continuerait de tomber, pour la mauvaise raison.
        $this->assertContains('exigerArchivage', $delegues);
    }

    #[Test]
    public function toute_action_d_ecriture_d_un_composant_pwa_exige_un_droit(): void
    {
        $fichiers = $this->fichiersDesComposants();

        // Mesuré le 27/08/2026 : 39 composants dans `app/Pwa/Livewire`. Le
        // plancher est posé en dessous pour tolérer une réorganisation, et
        // assez haut pour qu un répertoire perdu le franchisse.
        $this->assertGreaterThanOrEqual(
            35,
            count($fichiers),
            'Seuls '.count($fichiers).' composants PWA relus, contre 39 mesurés. '
            .'Un répertoire a été renommé : le balayage est devenu creux, donc vert.',
        );

        $ecrituresDeServices = $this->registreEcrituresDeServices();
        $motifServices = '/->\s*(?:'.implode('|', array_map('preg_quote', $ecrituresDeServices)).')\s*\(/';
        $deleguesGardes = $this->deleguesGardesDuMotif();
        $motifDelegues = '/\$this->\s*(?:'.implode('|', array_map('preg_quote', $deleguesGardes)).')\s*\(/';
        $modulesConnus = array_keys(RolePermissionSeeder::MATRICE['administrateur']);

        $defauts = [];
        $methodesRelues = 0;

        foreach ($fichiers as $fichier) {
            $classe = $this->classeDe($fichier);
            if (! class_exists($classe)) {
                // Les traits (`Livewire/Concerns/`) ne sont pas des composants :
                // leurs méthodes sont relues à travers chaque classe qui les
                // utilise, ce qui est la seule lecture qui compte — c'est là
                // que `static::MODULE` se résout.
                continue;
            }
            $reflet = new ReflectionClass($classe);
            if ($reflet->isAbstract() && $reflet->getMethods(ReflectionMethod::IS_PUBLIC) === []) {
                continue;
            }

            $porteLeTrait = in_array(
                AutoriseEcriture::class,
                $this->traitsDe($reflet),
                true,
            );

            foreach ($reflet->getMethods(ReflectionMethod::IS_PUBLIC) as $methode) {
                // Seules les méthodes écrites DANS la PWA nous concernent :
                // celles du cadre Livewire viennent d ailleurs.
                $ficMethode = $methode->getFileName();
                if ($ficMethode === false || ! str_contains(
                    str_replace('\\', '/', $ficMethode),
                    '/app/Pwa/',
                )) {
                    continue;
                }
                if ($methode->isConstructor() || $methode->isStatic()) {
                    continue;
                }

                $methodesRelues++;
                $source = $this->sourceDe($methode);
                $nom = $reflet->getShortName().'::'.$methode->getName();

                // Est autorisée : la méthode qui appelle `exigerEcriture()`
                // elle-même, OU qui délègue à un geste gardé du motif de
                // formulaire — le corps du délégué a été vérifié plus haut.
                //
                // La forme d'APPEL est exigée (`$this->exigerEcriture(`), pas
                // la simple mention : `Achats::render` cite la garde dans un
                // commentaire, et la première exécution de ce contrôle l'a
                // prise pour un appel.
                $appelleDirectement = str_contains($source, '$this->exigerEcriture(');
                $autorise = $appelleDirectement
                    || preg_match($motifDelegues, $source) === 1;

                // (0) Un appel direct doit recevoir `self::MODULE`, jamais un
                //     littéral : `exigerEcriture('M1')` dans un composant M7
                //     exigerait le droit du MAUVAIS module — un rôle sans M7
                //     écrirait sur M7 avec son seul droit M1.
                if ($appelleDirectement) {
                    // Registre multi-modules : le litteral attendu est declare
                    // ICI, methode par methode, et verifie tel quel.
                    if (array_key_exists($nom, self::ECRITURES_MULTI_MODULES)) {
                        $attendu = self::ECRITURES_MULTI_MODULES[$nom];
                        if (! str_contains($source, "\$this->exigerEcriture('".$attendu."')")) {
                            $defauts[] = "$nom est declaree multi-modules sur `$attendu` "
                                .'mais sa source n appelle pas exigerEcriture avec ce module.';
                        }
                        // Le registre etant une constante a valeurs connues,
                        // l'appartenance a la matrice est deja garantie par
                        // l'analyse statique — pas de re-verification morte.
                        continue;
                    }

                    if (preg_match('/\$this->exigerEcriture\(\s*(?:self|static)::MODULE\s*\)/', $source) !== 1) {
                        $defauts[] = "$nom appelle `exigerEcriture()` avec autre chose "
                            .'que `self::MODULE` : un module en littéral peut désigner '
                            .'le mauvais écran, et personne ne le relira.';
                    } else {
                        $module = $reflet->getConstant('MODULE');
                        if (! in_array($module, $modulesConnus, true)) {
                            $defauts[] = "$nom exige un droit sur `MODULE` mais la "
                                .'constante de sa classe est absente ou hors de la '
                                .'matrice RBAC ('.var_export($module, true).').';
                        }
                    }
                }

                // (1) Une méthode qui PERSISTE doit autoriser — même si son nom
                //     figure parmi les méthodes de lecture. C est ce qui empêche
                //     d écrire dans `render()` pour échapper au contrat.
                //     « Persister », c est l Eloquent nu OU l appel d une
                //     écriture de Service (28/08/2026).
                $persiste = null;
                foreach ($this->motifsDePersistance() as $etiquette => $motif) {
                    if (preg_match($motif, $source) === 1) {
                        $persiste = $etiquette;
                        break;
                    }
                }
                if ($persiste === null
                    && preg_match($motifServices, $source, $capture) === 1
                    && ! in_array($nom, $this->appelsHomonymesRelus(), true)) {
                    $persiste = 'appel de Service : '.trim($capture[0], '-> (');
                }

                $exempte = in_array($nom, self::ECRITURES_HORS_MODULE, true);

                if ($persiste !== null && ! $autorise && ! $exempte) {
                    $defauts[] = "$nom persiste ($persiste) sans appeler "
                        .'`exigerEcriture()`. Une écriture du canal web sans '
                        .'contrôle RBAC donne à un rôle par le navigateur ce '
                        .'que l API lui refuse.';

                    continue;
                }

                // (2) Une méthode publique INCONNUE est présumée une écriture.
                if (! in_array($methode->getName(), self::METHODES_DE_LECTURE, true)
                    && ! str_starts_with($methode->getName(), 'updated')
                    && ! $autorise) {
                    $defauts[] = "$nom est une action publique qui n appelle pas "
                        .'`exigerEcriture()`. Si elle n écrit rien, inscrivez-la '
                        .'dans `METHODES_DE_LECTURE` — pour qu elle soit relue, '
                        .'et non tolérée par omission.';

                    continue;
                }

                if ($autorise && ! $porteLeTrait) {
                    $defauts[] = "$nom appelle `exigerEcriture()` mais sa "
                        .'classe ne porte pas le trait `AutoriseEcriture` : '
                        .'le code ne compilerait pas, ou l appel vise une '
                        .'autre méthode du même nom.';
                }
            }
        }

        $this->assertSame([], $defauts, implode("\n", $defauts));

        // Plancher de méthodes réellement soumises aux contrôles. Sans lui, une
        // exclusion trop large viderait le balayage en silence.
        $this->assertGreaterThanOrEqual(
            40,
            $methodesRelues,
            "Seules $methodesRelues méthodes publiques relues sur l ensemble des "
            .'composants PWA. Le filtre de fichier ou de déclaration s est '
            .'élargi au point de vider le balayage.',
        );
    }

    /**
     * Les traits d'une classe ET de tous ses ancêtres.
     *
     * Remonter la chaîne d'héritage n'est pas un détail : `PageMetier` porte
     * `use AutoriseEcriture` pour ses descendantes, et ne regarder que la
     * classe elle-même rapporterait « trait absent » sur un composant qui le
     * possède réellement — le contrôle crierait à tort, et un contrôle qui
     * crie à tort finit désactivé.
     *
     * @param  ReflectionClass<object>  $reflet
     * @return list<class-string>
     */
    private function traitsDe(ReflectionClass $reflet): array
    {
        $traits = [];
        for ($c = $reflet; $c !== false; $c = $c->getParentClass()) {
            foreach ($c->getTraitNames() as $trait) {
                $traits[] = $trait;
                foreach (class_uses($trait) ?: [] as $imbrique) {
                    $traits[] = $imbrique;
                }
            }
        }

        return $traits;
    }
}
