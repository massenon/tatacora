<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Http\Controllers;

use App\Domain\Comptabilite\Http\Requests\ConsulterEtatComptableRequest;
use App\Domain\Comptabilite\Http\Resources\AnalytiqueResource;
use App\Domain\Comptabilite\Http\Resources\BilanResource;
use App\Domain\Comptabilite\Http\Resources\CompteResultatResource;
use App\Domain\Comptabilite\Http\Resources\EtatClotureResource;
use App\Domain\Comptabilite\Http\Resources\EtatsFinanciersResource;
use App\Domain\Comptabilite\Http\Resources\IndicateursComptablesResource;
use App\Domain\Comptabilite\Http\Resources\NotesAnnexesResource;
use App\Domain\Comptabilite\Http\Resources\TafireResource;
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Domain\Comptabilite\ReadModels\EtatsFinanciers;
use App\Domain\Comptabilite\Services\AnalytiqueService;
use App\Domain\Comptabilite\Services\BilanService;
use App\Domain\Comptabilite\Services\CompteResultatService;
use App\Domain\Comptabilite\Services\EtatClotureService;
use App\Domain\Comptabilite\Services\IndicateursComptablesService;
use App\Domain\Comptabilite\Services\NotesAnnexesService;
use App\Domain\Comptabilite\Services\TafireService;
use App\Http\Controllers\Controller;

/**
 * Les etats financiers DERIVES de la Balance — Bilan, Compte de Resultat,
 * TAFIRE, Notes Annexes, Analytique, etat de cloture, indicateurs du hub.
 *
 * @see EF-M10-03 Comptabilite analytique par centre de cout
 * @see EF-M10-06 Edition des etats reglementaires SYSCOHADA
 * @see EF-M10-07 Cloture comptable periodique
 *
 * ## Un orchestrateur, rien d'autre
 *
 * Aucune regle de calcul ne vit ici : chaque methode resout un exercice, appelle
 * un service de domaine et enveloppe le read model. Toute la comptabilite est
 * dans `Services/`, ou elle est testable sans HTTP.
 *
 * ## TOUTES ces routes sont en LECTURE, et aucune n'ecrit
 *
 * C'est un constat, pas un raccourci : de ces sept ecrans du maitre, un seul
 * porte un bouton (« Exporter les 4 documents »), et son gestionnaire n'ecrit
 * rien — le maitre le dit lui-meme. `m10-cloture.html` n'a pas un seul
 * `addEventListener`. Voir `EtatClotureResource` pour les raisons pour
 * lesquelles la cloture n'est pas exposee en ecriture.
 *
 * ## Aucun PDF n'est genere ici
 *
 * `RESPECT_TABLEAU_RAPPORT.md` §4 recense l'en-tete recopiee localement comme
 * non-conformite n°1, et RG-19 impose que tout export passe par
 * `GenerateurEtatService`. Un controleur qui produirait un PDF court-circuiterait
 * l'en-tete, le format et l'archivage d'un coup.
 */
class EtatsFinanciersController extends Controller
{
    public function __construct(
        private readonly CompteResultatService $compteResultat,
        private readonly BilanService $bilan,
        private readonly TafireService $tafire,
        private readonly NotesAnnexesService $notesAnnexes,
        private readonly AnalytiqueService $analytique,
        private readonly EtatClotureService $etatCloture,
        private readonly IndicateursComptablesService $indicateurs,
    ) {
    }

    public function compteResultat(ConsulterEtatComptableRequest $request): CompteResultatResource
    {
        return new CompteResultatResource($this->compteResultat->genererPourExercice(
            $request->exerciceId(),
            $request->statuts(),
            $request->filtreStatut(),
        ));
    }

    public function bilan(ConsulterEtatComptableRequest $request): BilanResource
    {
        return new BilanResource($this->bilan->genererPourExercice(
            $request->exerciceId(),
            $request->statuts(),
            $request->filtreStatut(),
        ));
    }

    public function tafire(ConsulterEtatComptableRequest $request): TafireResource
    {
        return new TafireResource($this->tafire->genererPourExercice(
            $request->exerciceId(),
            $request->statuts(),
            $request->filtreStatut(),
        ));
    }

    public function notesAnnexes(ConsulterEtatComptableRequest $request): NotesAnnexesResource
    {
        return new NotesAnnexesResource($this->notesAnnexes->genererPourExercice(
            $this->exercice($request),
            $request->statuts(),
            $request->filtreStatut(),
        ));
    }

    public function analytique(ConsulterEtatComptableRequest $request): AnalytiqueResource
    {
        return new AnalytiqueResource($this->analytique->genererPourExercice(
            $request->exerciceId(),
            $request->statuts(),
            $request->filtreStatut(),
        ));
    }

    public function cloture(ConsulterEtatComptableRequest $request): EtatClotureResource
    {
        return new EtatClotureResource($this->etatCloture->genererPourExercice(
            $this->exercice($request),
            $request->statuts(),
            $request->filtreStatut(),
        ));
    }

    public function indicateurs(ConsulterEtatComptableRequest $request): IndicateursComptablesResource
    {
        return new IndicateursComptablesResource($this->indicateurs->genererPourExercice(
            $this->exercice($request),
            $request->statuts(),
            $request->filtreStatut(),
        ));
    }

    /**
     * Les QUATRE etats financiers en une seule lecture.
     *
     * Ils ne sont pas recalcules : ce sont les memes services que les routes
     * individuelles (`m10-etats-financiers.html` l.42 l'exige explicitement).
     * Ce que la route apporte, c'est que les quatre documents proviennent de la
     * MEME lecture — quatre appels successifs pourraient encadrer une ecriture
     * et produire un jeu incoherent, sur des etats destines a etre signes.
     */
    public function etatsFinanciers(ConsulterEtatComptableRequest $request): EtatsFinanciersResource
    {
        $exercice = $this->exercice($request);
        $statuts = $request->statuts();
        $filtre = $request->filtreStatut();

        return new EtatsFinanciersResource(new EtatsFinanciers(
            exerciceId: $exercice->id,
            bilan: $this->bilan->genererPourExercice($exercice->id, $statuts, $filtre),
            compteResultat: $this->compteResultat->genererPourExercice($exercice->id, $statuts, $filtre),
            tafire: $this->tafire->genererPourExercice($exercice->id, $statuts, $filtre),
            notesAnnexes: $this->notesAnnexes->genererPourExercice($exercice, $statuts, $filtre),
        ));
    }

    /**
     * L'exercice, en modele.
     *
     * `exercice_id` est deja valide `exists:` par le `FormRequest` ; ce
     * `findOrFail` n'est donc pas une seconde validation mais la resolution du
     * modele, pour les etats qui lisent ses colonnes propres — l'annee, le
     * statut, la note d'evenements posterieurs.
     */
    private function exercice(ConsulterEtatComptableRequest $request): ExerciceComptable
    {
        return ExerciceComptable::findOrFail($request->exerciceId());
    }
}
