<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Transverse;

use App\Shared\Audit\Models\JournalAudit as EntreeJournalAudit;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Support\Facades\DB;
use Illuminate\View\View;
use Livewire\Attributes\Title;
use Livewire\Attributes\Url;

/**
 * Journal d'Audit — maitre : `prototype_v2/pages/journal-audit.html`.
 *
 * Six colonnes dans l'ordre du maitre (l.49-54) : « Utilisateur », « Action »,
 * « Détail », « Date », « Heure », « Poste ». Deux filtres au-dessus (l.29-38) :
 * une recherche libre et une liste d'actions.
 *
 * ## POURQUOI CET ECRAN N'APPELLE AUCUN `Service` DE DOMAINE
 *
 * `LARAVEL_PWA.md` §3 interdit de RECALCULER une regle de gestion dans un
 * composant Livewire — « calcul de disponibilite, calcul de stock
 * theorique... » — et impose d'appeler le `Service` qui la porte. Ici il n'y
 * a aucune regle a porter : `journal_audit` est un registre en append-only,
 * alimente EXCLUSIVEMENT par le trait `Auditable`, par `AuthController::tracer`
 * et par `MouvementStockService::tracerRuptureForcee`. Aucun Service ne le lit
 * nulle part dans le depot, et aucune route d'API ne l'expose — verifie le
 * 27/08/2026 par balayage de `app/` et `routes/api.php`. Un Service cree pour
 * l'occasion ne partagerait donc rien avec personne : ce serait une couche de
 * plus, pas une source unique.
 *
 * Ce qui est REELLEMENT en jeu dans §3 — deux implementations d'une meme
 * regle qui divergent — n'a pas de prise ici, et la question est posee dans le
 * rapport plutot que tranchee en silence.
 *
 * ## Ce qui n'est PAS porte — Article 8
 *
 * ÉCART DÉLIBÉRÉ — `journal-audit.html` l.34-37
 * Le maitre : un bouton « Réinitialiser les données de démo », qui efface
 * `localStorage` et resseme douze entrees fictives (l.86-99, l.156-161).
 * Ici : le bouton n'est pas rendu ; il est nomme au bloc de refus.
 * Raison : Article 6 — « les OUTILS DE DEMONSTRATION de la maquette : ...
 * jeux de donnees figes » ne se portent jamais. Et il est destructeur : le
 * journal d'audit est le registre que le chap. 11.4 du CdCF rend
 * inalterable, y compris pour l'Administrateur — c'est la phrase que le
 * maitre affiche lui-meme en pied de page (l.59).
 *
 * ÉCART DÉLIBÉRÉ — `journal-audit.html` l.51 (colonne « Détail »)
 * Le maitre : une phrase libre par entree, ecrite a la main dans son jeu de
 * demonstration — « Réservation créée — Bungalow Boukari (BNG-01) ».
 * Ici (corrige le 02/09/2026) : le libelle FRANCAIS de la table concernee
 * (registre {@see \App\Pwa\Livewire\Transverse\JournalAudit} lang
 * `pwa.journal_audit.tables`), suivi du libelle REEL de l'enregistrement
 * quand il est encore lisible ({@see self::COLONNES_LIBELLE} /
 * {@see self::libellesEnregistrements()}) — jamais une phrase fabriquee au
 * passe compose, et jamais un nom de table brut ni un UUID seul.
 * Raison du reste de l'ecart : `journal_audit` n'a AUCUNE colonne de phrase,
 * seulement `entite_concernee`, `entite_id`, et deux instantanes
 * `valeur_avant` / `valeur_apres`. Fabriquer la phrase du maitre au passe
 * compose («… créée », «… modifié »…) exigerait de savoir, table par table,
 * CE QUI S'EST PASSE en plus de QUI est concerne — une regle metier reecrite
 * ici, ce que §3 interdit. Les instantanes, eux, restent non rendus :
 * afficher leur CONTENU exposerait un numero de telephone client, un
 * montant, une adresse — exactement ce que `Auditable::masquerChampsSensibles`
 * cherche a eviter. Le journal ne doit pas devenir une seconde surface
 * d'exposition, et c'est dit a l'ecran.
 * Un enregistrement disparu (archive, supprime) ou une table hors du
 * registre de resolution garde son IDENTIFIANT, en second — jamais un
 * libelle invente pour ce qui n'existe plus (Article 7).
 *
 * ÉCART DÉLIBÉRÉ — `journal-audit.html` l.62-70 (les pastilles de couleur)
 * Le maitre : sept actions colorees — Connexion, Déconnexion, Création,
 * Modification, Suppression, Import, Export.
 * Ici : les memes couleurs sur les actions que le depot ecrit reellement, et
 * une action inconnue rendue EN CLAIR plutot qu'en pastille muette.
 * Raison : le maitre indexe une table de couleurs sur son libelle (l.144) ;
 * une action absente de la table n'y produit rien de distinctif. « Import » et
 * « Export » n'ont aucun ecrivain dans ce depot (constat du 27/08/2026), et
 * `rupture_stock_forcee` en a un que le maitre ne connait pas. Une valeur
 * inattendue doit se voir.
 *
 * ## Le nom affiche est le LOGIN, pas un nom
 *
 * Le schema ne porte aucun nom sur `utilisateurs`
 * (`03_DATABASE_ENGINEERING.md` §2). Le maitre affiche « Marceline HOUNSOU » ;
 * la PWA affiche le login reel. Une valeur vraie plutot qu'un nom fabrique —
 * meme choix que la barre superieure. Une entree sans utilisateur (job
 * planifie, tache console) rend « — », jamais un compte invente : Article 7.
 *
 *
 * ## PLUS AUCUNE SECTION DE REFUS N'EST AFFICHEE (directive du 31/08/2026)
 *
 * Cet ecran portait un panneau qui enumerait, pour l'utilisateur, ce qu'il ne
 * fait pas. Le Product Owner l'a retire : un ecran ne catalogue pas ses
 * absences. Les motifs eux-memes n'ont pas bouge de place ; les jetons
 * ci-dessous les rendent MESURABLES par `t-trois-sources.js`, ce qui est la
 * seule chose qui distingue une decision d'un oubli.
 *
 * ⚠ Rien n'est rendu inerte a la place : ce qui n'est pas porte est ABSENT,
 * pas grise (Article 3.3).
 *
 * Refus declares :
 *   maitre-refuse:journal-audit.html#reinitialiser
 *   maitre-refuse:journal-audit.html#detail-entree
 *   maitre-refuse:journal-audit.html#import-export
 * @see RG-15 Traçabilité des actions sensibles
 * @see LARAVEL_PWA.md §1, §3
 */
#[Title("Journal d'Audit — TATACORA AFRIQUE")]
class JournalAudit extends PageTransverse
{
    /**
     * Les actions ECRITES par ce depot, avec le libelle et les couleurs du
     * maitre quand il les connait (l.62-70).
     *
     * Registre FERME, et volontairement adosse au code qui l'alimente plutot
     * qu'a la liste du maitre : `Auditable` ecrit `creation`, `modification`
     * et `suppression` ; `AuthController::tracer` ecrit `connexion` et
     * `deconnexion` ; `MouvementStockService` ecrit `rupture_stock_forcee`.
     * Une action ajoutee demain sans entree ici sera rendue en clair, pas
     * avalee.
     *
     * @var array<string, array{libelle: string, fond: string, texte: string}>
     */
    public const ACTIONS = [
        'connexion' => ['libelle' => 'Connexion', 'fond' => '#E8F5E9', 'texte' => '#2E7D32'],
        'deconnexion' => ['libelle' => 'Déconnexion', 'fond' => '#F3F4F6', 'texte' => '#6B7280'],
        'creation' => ['libelle' => 'Création', 'fond' => '#E8EEFD', 'texte' => '#1D4ED8'],
        'modification' => ['libelle' => 'Modification', 'fond' => '#FDF3E0', 'texte' => '#B8891E'],
        'suppression' => ['libelle' => 'Suppression', 'fond' => '#FDECEC', 'texte' => '#C62828'],
        'rupture_stock_forcee' => ['libelle' => 'Rupture de stock forcée', 'fond' => '#FDECEC', 'texte' => '#C62828'],
    ];

    /**
     * Plafond de lignes rendues.
     *
     * Le maitre n'en a aucun : son jeu de demonstration compte douze entrees.
     * `journal_audit` grossit d'une ligne par ecriture de `Reservation` ou de
     * `Facture` — une page qui les rendrait toutes finirait par ne plus
     * s'afficher du tout, sur un canal dont le cas d'usage est justement un
     * poste tiers a la liaison faible (`LARAVEL_PWA.md` §1). Le decompte reel
     * est affiche a cote, pour que la troncature se VOIE.
     */
    public const PLAFOND = 200;

    /**
     * Les tables pour lesquelles on sait résoudre un libellé LISIBLE
     * d'enregistrement, et la ou les colonnes qui le portent.
     *
     * Registre FERMÉ, technique (pas de texte utilisateur ici — les colonnes
     * ne s'affichent jamais telles quelles) : une table absente reste
     * affichée par son seul identifiant, jamais une requête devinée sur une
     * colonne qui n'existe pas. Corrige le défaut relevé par l'audit
     * navigateur du 01/09/2026 : la colonne « Détail » ne rendait que le nom
     * de table brut et l'UUID.
     *
     * @var array<string, list<string>>
     */
    private const COLONNES_LIBELLE = [
        'clients' => ['nom', 'prenom'],
        'employes' => ['nom', 'prenom'],
        'factures' => ['numero_mecef'],
        'cartes_boisson' => ['libelle'],
        'plats' => ['libelle'],
        'menus' => ['libelle'],
        'recettes' => ['libelle'],
        'articles' => ['libelle'],
        'points_stockage' => ['libelle'],
        'circuits' => ['nom'],
        'guides' => ['nom'],
        'vehicules' => ['immatriculation'],
        'fournisseurs' => ['raison_sociale'],
        'depenses' => ['numero'],
        'lignes_depense' => ['libelle'],
        'ecritures_comptables' => ['libelle'],
        'ventes' => ['numero'],
        'bulletins_paie' => ['numero'],
        'parametres_systeme' => ['cle'],
    ];

    /**
     * Recherche libre — PROPRIETE Livewire, jamais une methode (PA-67).
     */
    #[Url(as: 'q')]
    public string $recherche = '';

    /**
     * Filtre d'action. Une valeur inconnue vient de l'URL, donc de
     * l'exterieur : elle retombe sur « toutes », plutot que de produire un
     * `where` qui ne rend rien sous un bandeau affirmant le contraire.
     */
    #[Url(as: 'action')]
    public string $filtreAction = '';

    public function render(): View
    {
        $action = $this->filtreActionValide();

        $requete = EntreeJournalAudit::query()->with('utilisateur');

        if ($action !== '') {
            $requete->where('action', $action);
        }

        $terme = trim($this->recherche);

        if ($terme !== '') {
            // Meme portee que le maitre (l.126) : utilisateur, action, detail.
            // Le « detail » du serveur est l'entite concernee et son id.
            $requete->where(function ($sous) use ($terme): void {
                $sous->where('action', 'like', '%'.$terme.'%')
                    ->orWhere('entite_concernee', 'like', '%'.$terme.'%')
                    ->orWhere('entite_id', 'like', '%'.$terme.'%')
                    ->orWhereHas('utilisateur', static function ($u) use ($terme): void {
                        $u->where('login', 'like', '%'.$terme.'%');
                    });
            });
        }

        $total = (clone $requete)->count();

        /** @var Collection<int, EntreeJournalAudit> $entrees */
        $entrees = $requete->orderByDesc('date_heure')->limit(self::PLAFOND)->get();

        return view('pwa.transverse.journal-audit', array_merge($this->socle(), [
            'entrees' => $entrees,
            'total' => $total,
            'tronque' => $total > self::PLAFOND,
            // Les actions REELLEMENT presentes, comme le maitre (l.155) : un
            // filtre qui propose une valeur inatteignable passe pour casse.
            'actions' => $this->actionsPresentes(),
            'actionActive' => $action,
            // Un SEUL appel `__()`, a cle litterale : la vue indexe le
            // tableau rendu, elle ne concatene jamais de cle dynamique.
            'libellesTables' => __('pwa.journal_audit.tables'),
            'libellesEnregistrements' => $this->libellesEnregistrements($entrees),
        ]))->layout('layouts.pwa', ['title' => __('pwa.journal_audit.titre_page')]);
    }

    /**
     * Le libellé RÉEL de chaque enregistrement encore lisible, groupé par
     * table puis par identifiant.
     *
     * UNE requête PAR TABLE présente sur la page, jamais une par ligne : le
     * journal peut porter jusqu'à `self::PLAFOND` entrées, et une résolution
     * ligne à ligne en ferait autant d'allers-retours. Un enregistrement
     * absent du résultat (supprimé au sens SQL, ou table hors du registre
     * {@see self::COLONNES_LIBELLE}) n'apparaît simplement pas dans le
     * tableau rendu : la vue garde alors l'identifiant technique, en second
     * — jamais une valeur inventée pour ce qui n'existe plus.
     *
     * @param  Collection<int, EntreeJournalAudit>  $entrees
     * Éprouvé par mutation le 02/09/2026 : `return [];` en tête de la
     * méthode fait rougir `TransversePwaTest::le_detail_resout_le_libelle_reel_de_l_enregistrement_encore_lisible`
     * sur « HOUNKPATIN Estelle » absent — restauré ensuite.
     *
     * @return array<string, array<string, string>>
     */
    private function libellesEnregistrements(Collection $entrees): array
    {
        $idsParTable = [];

        foreach ($entrees as $entree) {
            if (! array_key_exists($entree->entite_concernee, self::COLONNES_LIBELLE)) {
                continue;
            }

            $idsParTable[$entree->entite_concernee][] = $entree->entite_id;
        }

        $resultat = [];

        foreach ($idsParTable as $table => $ids) {
            $colonnes = self::COLONNES_LIBELLE[$table];

            $lignes = DB::table($table)
                ->whereIn('id', array_unique($ids))
                ->get(array_merge(['id'], $colonnes));

            foreach ($lignes as $ligne) {
                $morceaux = [];
                foreach ($colonnes as $colonne) {
                    $valeur = trim((string) ($ligne->{$colonne} ?? ''));

                    if ($valeur !== '') {
                        $morceaux[] = $valeur;
                    }
                }

                if ($morceaux !== []) {
                    $resultat[$table][(string) $ligne->id] = implode(' ', $morceaux);
                }
            }
        }

        return $resultat;
    }

    /**
     * La valeur de filtre reellement appliquee — un etat DIT son filtre
     * (PA-119).
     */
    protected function filtreActionValide(): string
    {
        return in_array($this->filtreAction, $this->actionsPresentes(), true)
            ? $this->filtreAction
            : '';
    }

    /**
     * Les actions distinctes du registre, triees.
     *
     * @return list<string>
     */
    protected function actionsPresentes(): array
    {
        /** @var list<string> $actions */
        $actions = EntreeJournalAudit::query()
            ->select('action')
            ->distinct()
            ->orderBy('action')
            ->pluck('action')
            ->all();

        return $actions;
    }
}
