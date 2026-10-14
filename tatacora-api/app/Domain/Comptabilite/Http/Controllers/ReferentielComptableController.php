<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Http\Controllers;

use App\Domain\Comptabilite\Http\Requests\ConsulterEtatComptableRequest;
use App\Domain\Comptabilite\Http\Requests\FiltrerPlanComptableRequest;
use App\Domain\Comptabilite\Http\Resources\CentreCoutResource;
use App\Domain\Comptabilite\Http\Resources\CompteComptableResource;
use App\Domain\Comptabilite\Http\Resources\ExerciceComptableResource;
use App\Domain\Comptabilite\Http\Resources\JournalComptableResource;
use App\Domain\Comptabilite\Http\Resources\PlanComptableResource;
use App\Domain\Comptabilite\Models\CentreCout;
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Domain\Comptabilite\Models\JournalComptable;
use App\Domain\Comptabilite\Services\GrandLivreService;
use App\Domain\Comptabilite\Services\PlanComptableService;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

/**
 * Referentiels de M10 — ce que les quatre ecrans fondateurs ont besoin de LIRE
 * avant de pouvoir afficher quoi que ce soit.
 *
 * @see EF-M10-01 Plan comptable conforme SYSCOHADA revise
 * @see EF-M10-06 Edition des etats reglementaires SYSCOHADA
 * @see RG-16 RBAC de 2e niveau
 *
 * ## Simple orchestrateur (06_DEVELOPMENT_STANDARDS.md §2.2)
 *
 * Aucune regle de gestion n'est ecrite ici.
 *
 * ## Trois de ces quatre routes n'ont AUCUN controle a l'ecran, et sont
 * pourtant indispensables
 *
 * `exercices`, `journaux` et `comptes-mouvementes` ne correspondent a aucun
 * bouton du maitre : elles remplissent des selecteurs, ou repondent a une regle
 * de calcul de la documentation. Les omettre reproduirait PA-128 — une donnee
 * absente de l'API est une donnee absente du client, et le manque ne se voit
 * d'aucun des deux cotes :
 *
 * - **`exercices`** : `MODULE_COMPTABILITE_COMPLET.md` §1 impose a tout ecran de
 *   M10 de filtrer par `exercice_id`. Sans cette route, aucun client ne
 *   connaitrait un seul identifiant d'exercice, et les trois etats seraient
 *   inatteignables.
 * - **`journaux`** : `m10-journal.html` l.73 ecrit ses trois codes EN DUR, la
 *   ou le schema en prevoit cinq. Recopier cette liste dans le client en ferait
 *   une seconde source de verite (Article 10).
 * - **`comptes-mouvementes`** : le `<select>` du Grand Livre ne liste que les
 *   comptes reellement mouvementes (§3, et le maitre le cite l.52-55). Le
 *   deriver du plan comptable complet proposerait des comptes vides ; le deriver
 *   cote client exigerait de telecharger toutes les ecritures de l'exercice
 *   pour en extraire une liste de comptes.
 *
 * ## Aucune ecriture dans ce controleur, ni ailleurs dans ce lot
 *
 * Les quatre pages fondatrices de M10 sont en CONSULTATION PURE : aucun bouton
 * d'ajout, aucune action de ligne, aucune modale. Router une creation que rien
 * n'appelle serait le defaut PA-63, et l'exposer ouvrirait une porte d'ecriture
 * sur `ecritures_comptables` sans que le moindre ecran l'ait demandee.
 */
class ReferentielComptableController
{
    public function __construct(
        private readonly PlanComptableService $plan,
        private readonly GrandLivreService $grandLivre,
    ) {
    }

    /**
     * Les exercices comptables, du plus recent au plus ancien.
     *
     * Non paginee : le referentiel compte une ligne par annee d'exploitation.
     * Une page manquante ferait disparaitre un exercice du selecteur, donc
     * rendrait ses etats inatteignables sans que rien ne le signale.
     *
     * Les exercices CLOTURES sont servis comme les autres : les etats d'un
     * exercice clos restent consultables, c'est meme leur raison d'etre.
     */
    public function exercices(): AnonymousResourceCollection
    {
        return ExerciceComptableResource::collection(
            ExerciceComptable::query()->orderByDesc('annee')->get(),
        );
    }

    /**
     * Le referentiel des journaux — VTE, ACH, BQ, CAI, OD.
     *
     * Non paginee, meme raison que `GET /stocks/points` : un referentiel qui
     * remplit un filtre se sert entier.
     */
    public function journaux(): AnonymousResourceCollection
    {
        return JournalComptableResource::collection(
            JournalComptable::query()->orderBy('code')->get(),
        );
    }

    /**
     * Les centres de cout — le selecteur « Tous les centres » de la barre de
     * filtres du hub (`m10-syscohada.html` l.77) et l'axe de EF-M10-03.
     *
     * Meme raison d'etre que `journaux` : le maitre ecrit ses six centres EN DUR
     * (`plan-comptable-syscohada.js` l.76-83) la ou `ATELIER_PLAN_COMPTABLE.md`
     * en pose SEPT — « RH » manque a sa liste, et c'est precisement ce qu'un
     * referentiel recopie a la main finit par produire (Article 10).
     *
     * Non paginee : un referentiel qui remplit un selecteur se sert entier, une
     * page manquante ferait disparaitre un centre du filtre sans que rien ne le
     * signale.
     */
    public function centresCout(): AnonymousResourceCollection
    {
        return CentreCoutResource::collection(
            CentreCout::query()->orderBy('libelle')->get(),
        );
    }

    /**
     * Le plan comptable ENTIER, avec ses decomptes — `m10-plan-comptable.html`.
     */
    public function planComptable(FiltrerPlanComptableRequest $request): PlanComptableResource
    {
        return new PlanComptableResource($this->plan->consulter($request->classe()));
    }

    /**
     * Les comptes reellement mouvementes sur l'exercice — le `<select>` du
     * Grand Livre.
     *
     * Le filtre de statut s'y applique aussi : consulter le Grand Livre des
     * seules ecritures validees et se voir proposer un compte qui n'a que des
     * brouillons ouvrirait un ecran vide sans explication.
     */
    public function comptesMouvementes(ConsulterEtatComptableRequest $request): AnonymousResourceCollection
    {
        return CompteComptableResource::collection(
            $this->grandLivre->comptesMouvementes($request->exerciceId(), $request->statuts()),
        );
    }
}
