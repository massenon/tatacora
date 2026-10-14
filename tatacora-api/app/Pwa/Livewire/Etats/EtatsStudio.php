<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Etats;

use App\Domain\Etats\Services\CatalogueEtatsService;
use App\Pwa\Livewire\PageMetier;
use App\Shared\ReportEngine\Contracts\EtatInterface;
use App\Shared\ReportEngine\Data\EtatResultat;
use Illuminate\Support\Facades\Auth;
use Illuminate\View\View;
use Livewire\Attributes\Title;
use Livewire\Attributes\Url;

/**
 * Etats & Rapports — maitre : `prototype_v2/pages/m14-etats-studio.html`.
 *
 * Barre d'outils (l.40-60), catalogue en colonne de gauche (l.65-77 : recherche,
 * pastilles de module, liste, compteur) et zone d'apercu (l.80-83). Le corps
 * reel est produit par `m14-etats-studio.js` — `rendreFiltresModule()` l.44-57,
 * `rendreCatalogue()` l.66-101, `accueil()` l.112-133, `enteteHtml()` l.181-205
 * et `tableauHtml()` l.207-225.
 *
 * ## LA DECISION DE CE LOT : L'APERCU EST PORTE, L'EXPORT NE L'EST PAS
 *
 * `LARAVEL_PWA.md` §2 fait du Hub M14 « la SEULE exception a la lecture
 * stricte », au motif que « generer/exporter un etat est une operation de
 * lecture agregee, pas une ecriture transactionnelle ». **Cette justification
 * a ete verifiee contre le code, et elle est fausse pour la GENERATION.**
 *
 * `GenerateurEtatService::generer()` l.78-92 execute
 * `DB::transaction(fn (): EtatGenere => EtatGenere::create([...]))` : il INSERE
 * une ligne dans `etats_generes` (EF-M14-06, archivage horodate). Son propre
 * commentaire le dit — « Archivage et remise du document sont solidaires : un
 * document remis sans trace serait inverifiable a posteriori ». Generer ECRIT,
 * quelle que soit la lecture qu'on fait du §2.
 *
 * Mais la coupure ne passe pas entre « le Hub » et « le reste » : elle passe
 * A L'INTERIEUR du moteur, et l'architecture l'a deja tracee.
 *
 *   - `CatalogueEtatsService::pourUtilisateur()` — lecture pure, filtree par
 *     le RBAC du module SOURCE de chaque etat.
 *   - `EtatInterface::calculer()` — rend un `EtatResultat` et rien d'autre. Il
 *     est STRUCTURELLEMENT incapable d'ecrire : son contrat le prive de
 *     l'en-tete, du format ET de l'archivage, « ces trois responsabilites
 *     appartiennent a `GenerateurEtatService` » (docblock d'`EtatInterface`).
 *   - `GenerateurEtatService::generer()` — la seule ecriture.
 *
 * Cette page appelle donc les DEUX premiers et jamais le troisieme. L'apercu
 * — c'est-a-dire ce que le maitre appelle lui-meme « vous n'imprimez que ce
 * que vous avez deja vu » (l.128) — est reellement rendu, avec ses KPI, ses
 * colonnes et ses lignes. Les trois boutons d'export sont refuses et NOMMES.
 *
 * Aucune methode publique n'est ajoutee au composant : la selection d'un etat
 * est une PROPRIETE `#[Url]`, pas une action. La liste fermee de
 * `PwaActionsReluesTest` n'est donc pas elargie — ce qui est le controle a
 * regarder, `ForcerLectureSeule` ne couvrant pas les actions Livewire (PA-67).
 *
 * ## Ce qui n'est PAS porte — Article 8, chaque motif verifie le 27/08/2026
 *
 * ECART DELIBERE — `m14-etats-studio.html` l.57-59 (« Periode », les deux
 * champs de date et le bouton « Exercice »)
 * Le maitre : une periode qui borne l'etat affiche.
 * Ici : aucun des trois controles n'est rendu, et rien ne le dit a l'ecran.
 * Raison : AUCUN des trois etats du registre n'accepte de plage de dates —
 * verifie un par un. `EtatStocks` lit `sous_seuil` et `point_id`,
 * `EtatParcVehicules` lit `categorie` et `statut`, et `EtatTableauDeBord` lit
 * `periode`, qui est un CODE (`Periode::depuisCode`), pas deux dates. Rendre
 * les champs les ferait ignorer en silence : « un champ ignore laisse le
 * client croire que sa saisie a ete prise en compte » — le defaut exact que
 * PA-153 a trouve sur `CreerContratLocationRequest`. Substituer un selecteur
 * de code de periode aux deux champs serait l'interdit n. 06 (« substituer un
 * composant par defaut a un composant maquette »). L'arbitrage est au rapport.
 *
 * ECART DELIBERE — `m14-etats-studio.html` l.62-64 (« Imprimer », « Excel »,
 * « PDF »), `m14-etats-studio.js` l.178 (leur activation apres selection)
 * Le maitre : trois exports du document affiche.
 * Ici : aucun des trois.
 * Raison : les trois passent par `GenerateurEtatService::generer()`, qui ECRIT
 * dans `etats_generes` (l.80, ci-dessus). Ne pas archiver serait pire encore —
 * ce serait remettre un document sans trace, ce que EF-M14-06 interdit
 * precisement. Il n'y a donc pas de version « lecture seule » de l'export : le
 * porter suppose une decision du Product Owner sur le §2, pas une decision
 * d'agent (`INSTRUCTIONS_AGENTS_PORTAGE.md` §9).
 *
 * ECART DELIBERE — `m14-etats-studio.js` l.85-87 (la ligne « N ligne(s) » /
 * le motif d'indisponibilite sous chaque etat du catalogue), l.97-98 (la part
 * « · N sans donnees » du compteur), l.115 et l.126 (le decompte d'etats
 * « qui ont des donnees a ce jour » de l'ecran d'accueil)
 * Le maitre : chaque entree du catalogue annonce combien de lignes elle
 * contient, et les etats vides sont grises avec leur motif.
 * Ici : ni la ligne, ni la part de compteur, ni le decompte d'accueil.
 * Raison : obtenir ces chiffres exige d'executer `calculer()` sur CHAQUE etat
 * du catalogue. Le maitre le fait sur des donnees en memoire ; ici chaque
 * appel est un jeu de requetes SQL — `EtatTableauDeBord` en fait a lui seul
 * une par KPI et par periode comparee. A chaque frappe dans le champ de
 * recherche, la page rejouerait le calcul de tous les etats. Le refus est un
 * refus de COUT, pas d'absence de donnee, et c'est pourquoi il est ecrit ici :
 * il devient portable le jour ou un decompte bon marche existera.
 *
 * ECART DELIBERE — `m14-etats-studio.html` l.28-33 (le bloc `@media print`)
 * Le maitre : une feuille d'impression qui masque la coquille.
 * Ici : non portee.
 * Raison : elle n'existe que pour le bouton « Imprimer », qui n'est pas rendu.
 * La porter seule laisserait une regle CSS sans declencheur — un mecanisme
 * dont personne ne saurait s'il fonctionne.
 *
 * ## PLUS AUCUNE SECTION DE REFUS N'EST AFFICHEE (directive du 31/08/2026)
 *
 * L'ecran rendait DEUX fois un panneau « Ce que cet ecran ne fait pas, et
 * pourquoi » — sous l'accueil et sous l'apercu. Le Product Owner l'a retire :
 * un ecran ne catalogue pas ses absences pour l'utilisateur. Les quatre
 * motifs ci-dessus n'ont pas bouge ; les jetons ci-dessous les rendent
 * MESURABLES par `t-trois-sources.js`, ce qui est la seule chose qui
 * distingue une decision d'un oubli.
 *
 * ⚠ Rien n'est rendu inerte a la place : les controles refuses sont ABSENTS,
 * pas grises (Article 3.3).
 *
 * Refus declares :
 *   maitre-refuse:m14-etats-studio.html#periode
 *   maitre-refuse:m14-etats-studio.html#exports
 *   maitre-refuse:m14-etats-studio.html#decompte
 *   maitre-refuse:m14-etats-studio.html#impression
 *
 * @see EF-M14-02 Bibliotheque d'etats standards par module
 * @see EF-M14-03 Generation a la demande avec filtres dynamiques
 * @see EF-M14-06 Archivage horodate
 * @see RG-19 Moteur d'etats
 * @see LARAVEL_PWA.md §1, §2, §3
 */
#[Title('États & Rapports — TATACORA AFRIQUE')]
class EtatsStudio extends PageMetier
{
    /** Recherche libre — PROPRIETE Livewire, jamais une methode (PA-67). */
    #[Url(as: 'q')]
    public string $recherche = '';

    /** Pastille de module active, ou vide pour « Tous » (l.54). */
    #[Url(as: 'module')]
    public string $module = '';

    /**
     * Code de l'etat selectionne — PROPRIETE, pas une action.
     *
     * C'est ce qui permet de rendre l'apercu sans elargir d'un cran la liste
     * fermee de `PwaActionsReluesTest` : la selection passe par `$set`, action
     * du CADRE Livewire, jamais par une methode de ce composant.
     */
    #[Url(as: 'etat')]
    public string $etat = '';

    /**
     * Le catalogue REELLEMENT accessible a l'utilisateur connecte.
     *
     * ⚠ Le RBAC d'un etat porte sur son MODULE SOURCE, pas sur M14 : editer
     * l'etat des stocks exige un droit sur M6. C'est `CatalogueEtatsService`
     * qui l'applique, jamais un filtre recopie ici — le maitre l'ecrit
     * lui-meme a l'ecran (l.130-132 : « un magasinier ne lit pas le livre de
     * paie parce qu'il a acces aux "Etats" »).
     *
     * @return list<array{code: string, module: string, libelle: string, niveau: string}>
     */
    protected function accessibles(CatalogueEtatsService $catalogue): array
    {
        return $catalogue->pourUtilisateur(Auth::user());
    }

    /**
     * @param  list<array{code: string, module: string, libelle: string, niveau: string}>  $etats
     * @return list<array{code: string, module: string, libelle: string, niveau: string}>
     */
    protected function filtrer(array $etats, string $module, string $terme): array
    {
        return array_values(array_filter($etats, static function (array $etat) use ($module, $terme): bool {
            if ($module !== '' && $etat['module'] !== $module) {
                return false;
            }

            if ($terme === '') {
                return true;
            }

            // Meme portee que le maitre (l.63) : libelle et module. Il y
            // ajoute la description, que le catalogue serveur ne porte pas.
            return mb_stripos($etat['libelle'] . ' ' . $etat['module'], $terme) !== false;
        }));
    }

    public function render(CatalogueEtatsService $catalogue): View
    {
        $accessibles = $this->accessibles($catalogue);
        $modules = array_values(array_unique(array_column($accessibles, 'module')));
        sort($modules);

        // La pastille vient de l'URL, donc de l'exterieur : un module inconnu
        // produirait un catalogue vide sous une pastille « active » qui
        // n'existe pas (PA-119).
        $module = in_array($this->module, $modules, true) ? $this->module : '';
        $liste = $this->filtrer($accessibles, $module, trim($this->recherche));

        // La selection ne vaut que si l'etat est REELLEMENT accessible : un
        // code tape dans l'URL ne doit pas contourner le filtrage RBAC du
        // catalogue. C'est le 2e niveau, sur la donnee et non sur l'affichage.
        $codesAccessibles = array_column($accessibles, 'code');
        $selection = in_array($this->etat, $codesAccessibles, true) ? $this->etat : '';

        $resultat = null;
        $titre = null;
        $periode = null;
        $moduleSource = null;

        if ($selection !== '') {
            /** @var EtatInterface $etat */
            $etat = $catalogue->resoudre($selection);

            // ⚠ `calculer()` et RIEN D'AUTRE. `GenerateurEtatService::generer()`
            // archiverait dans `etats_generes` (l.80) : c'est une ecriture, et
            // elle n'a aucun chemin depuis cette page.
            /** @var EtatResultat $resultat */
            $resultat = $etat->calculer([]);
            $titre = $etat->libelle([]);
            $periode = $etat->periode([]);
            $moduleSource = $etat->module();
        }

        return view('pwa.etats.studio', array_merge($this->socle(), [
            'liste' => $liste,
            'modules' => $modules,
            'moduleApplique' => $module,
            'selection' => $selection,
            'resultat' => $resultat,
            'titreEtat' => $titre,
            'periodeEtat' => $periode,
            'moduleSource' => $moduleSource,
            'totalAccessibles' => count($accessibles),
            // `data-module="M14"` — celui du `<body>` du maitre (l.32).
        ]))->layout('layouts.pwa', ['module' => 'M14']);
    }
}
