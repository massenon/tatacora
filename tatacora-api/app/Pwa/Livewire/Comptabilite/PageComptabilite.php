<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Comptabilite;

use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Domain\Comptabilite\Models\JournalComptable;
use App\Models\User;
use App\Pwa\Livewire\PageMetier;
use App\Pwa\Support\ExerciceConsulte;
use Illuminate\Database\Eloquent\Collection;
use Livewire\Attributes\Url;

/**
 * Socle des douze pages M10 de la PWA — `prototype_v2/pages/m10-syscohada.html`
 * et les onze pages qui en descendent.
 *
 * ## AUCUNE METHODE PUBLIQUE ICI, ET C'EST STRUCTUREL
 *
 * Livewire expose comme ACTION toute methode publique d'un composant, y compris
 * celles qu'il HERITE. Une methode publique posee sur cette classe deviendrait
 * donc une action sur les douze pages a la fois, par le chemin meme que
 * `ForcerLectureSeule` ne couvre pas (PA-67) : la route dediee de Livewire,
 * hors du groupe `/pwa`.
 *
 * `PwaActionsReluesTest` releve desormais les methodes publiques HERITEES d'une
 * classe de `App\Pwa\` en plus des methodes declarees — sans quoi une methode
 * ajoutee ici serait invisible a la liste fermee. Tous les auxiliaires de ce
 * fichier sont `protected`.
 *
 * ## L'exercice est CHOISI, jamais deduit
 *
 * `MODULE_COMPTABILITE_COMPLET.md` §1 : « Tout ecran de M10 filtre
 * systematiquement par `exercice_id` — jamais un etat "toutes annees
 * confondues" par defaut ». `RequeteExerciceRequest` le rend obligatoire du
 * cote API et explique pourquoi retomber sur l'exercice `ouvert` serait un
 * defaut : deux postes ouverts sur la meme page rendraient deux annees
 * differentes le jour d'une bascule, sans que rien ne le dise.
 *
 * La PWA applique la meme regle : l'exercice voyage dans l'URL (`?exercice=`),
 * et une page sans exercice affiche le selecteur au lieu de choisir a la place
 * de l'utilisateur.
 *
 * ## Le filtre de statut est un registre FERME, revalide ici
 *
 * `$filtreStatut` est une propriete Livewire : elle est ecrite par le
 * navigateur, donc par l'exterieur. Une valeur inconnue produirait
 * `whereIn('statut', ['nimporte-quoi'])`, c'est-a-dire un etat VIDE sous un
 * bandeau qui affirme le contraire. `statuts()` retombe donc sur le registre.
 *
 * @see EF-M10-06 Edition des etats reglementaires SYSCOHADA
 * @see LARAVEL_PWA.md §1 (lecture seule stricte), §3 (appeler le Service de domaine)
 */
abstract class PageComptabilite extends PageMetier
{
    /**
     * Identifiant de l'exercice consulte — vide tant que rien n'est choisi.
     */
    #[Url(as: 'exercice')]
    public string $exerciceId = '';

    /**
     * `toutes` | `brouillon` | `validee` — le meme registre que l'API
     * (`EcritureComptable::FILTRES_STATUT`), et le meme defaut, qui est celui
     * de la documentation et non une supposition (`RequeteExerciceRequest`).
     */
    #[Url(as: 'statut')]
    public string $filtreStatut = EcritureComptable::FILTRE_STATUT_TOUTES;

    /**
     * Les exercices proposes au choix, du plus recent au plus ancien.
     *
     * @return Collection<int, ExerciceComptable>
     */
    protected function exercices(): Collection
    {
        return ExerciceComptable::query()->orderByDesc('annee')->get();
    }

    /**
     * L'exercice consulte, ou `null` si aucun n'a ete choisi — ou si celui
     * demande n'existe pas.
     *
     * Un identifiant inconnu ne leve pas : il vient de l'URL, donc de
     * l'exterieur. L'ecran retombe sur son etat « aucun exercice choisi », qui
     * dit quoi faire (Article 7).
     */
    protected function exercice(): ?ExerciceComptable
    {
        // Sélecteur d'exercice global (PO, 20/10/2026) : sans `?exercice=`,
        // l'écran consulte l'exercice de la SESSION (`ExerciceConsulte`).
        if ($this->exerciceId === '') {
            return ExerciceConsulte::exercice();
        }

        $exercice = ExerciceComptable::query()->find($this->exerciceId);

        // Un exercice choisi ici (sélecteur du hub, lien N-1 / N+1, lien
        // profond) DEVIENT l'exercice consulté partout — une fois par requête.
        if ($exercice !== null && ! $this->exerciceRetenu) {
            ExerciceConsulte::choisir($exercice->id);
            $this->exerciceRetenu = true;
        }

        return $exercice;
    }

    /** Non publique : remise à `false` à chaque requête Livewire. */
    private bool $exerciceRetenu = false;

    /**
     * La valeur de filtre reellement appliquee — un etat DIT son filtre
     * (PA-119).
     */
    protected function filtreStatutValide(): string
    {
        return in_array($this->filtreStatut, EcritureComptable::FILTRES_STATUT, true)
            ? $this->filtreStatut
            : EcritureComptable::FILTRE_STATUT_TOUTES;
    }

    /**
     * Les statuts reellement inclus. Meme depliage que
     * `RequeteExerciceRequest::statuts()` : `toutes` devient la LISTE des
     * statuts, jamais une absence de clause — un troisieme statut ajoute
     * demain a l'`enum` entrerait sinon dans les etats sans que personne ne
     * l'ait decide.
     *
     * @return list<string>
     */
    protected function statuts(): array
    {
        $filtre = $this->filtreStatutValide();

        return $filtre === EcritureComptable::FILTRE_STATUT_TOUTES
            ? EcritureComptable::STATUTS
            : [$filtre];
    }

    /**
     * Les journaux REELS du referentiel.
     *
     * ECART DELIBERE — `prototype_v2/pages/m10-journal.html` l.71
     * Le maitre : trois journaux ecrits en dur, `{ VTE, ACH, OD }`.
     * Ici : les journaux lus dans `journaux_comptables`.
     * Raison : le referentiel en porte cinq (VTE, ACH, BQ, CAI, OD). Recopier
     * les trois du maitre rendrait les ecritures de banque et de caisse
     * INATTEIGNABLES par le filtre, sur un ecran dont l'objet est de les
     * retrouver — et un journal ajoute demain n'apparaitrait jamais. Date du
     * constat : 27/08/2026, verifie contre `EtatClotureService` l.128, qui
     * enumere les memes cinq codes.
     *
     * @return Collection<int, JournalComptable>
     */
    protected function journaux(): Collection
    {
        return JournalComptable::query()->orderBy('code')->get();
    }

    /**
     * Les donnees que la coquille de chaque page M10 attend.
     *
     * @return array{exercice: ExerciceComptable|null, exercices: Collection<int, ExerciceComptable>, filtreStatut: string, utilisateur: User|null, menu: array<int, array<string, mixed>>, banniere: array{etat: string, module: string|null}}
     */
    protected function socle(): array
    {
        // L'utilisateur et le menu viennent de `PageMetier`, partages avec
        // toutes les pages de la PWA (Article 10). Ce qui s'y ajoute ici est
        // propre a M10 : aucune autre page ne filtre par exercice.
        // Sélecteur d'exercice global (20/10/2026) : sans `?exercice=`, le
        // sélecteur de l'écran montre l'exercice de la SESSION plutôt que
        // « Choisir un exercice ». Posé au rendu, jamais par une méthode
        // publique (une action Livewire de plus à relire, PA-67).
        if ($this->exerciceId === '') {
            $this->exerciceId = (string) ExerciceConsulte::exercice()?->id;
        }

        return array_merge(parent::socle(), [
            'exercice' => $this->exercice(),
            'exercices' => $this->exercices(),
            'filtreStatut' => $this->filtreStatutValide(),
        ]);
    }
}
