<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Http\Controllers;

use App\Domain\Comptabilite\Exceptions\EtatTropVolumineuxException;
use App\Domain\Comptabilite\Http\Requests\ConsulterEtatComptableRequest;
use App\Domain\Comptabilite\Http\Requests\ConsulterGrandLivreRequest;
use App\Domain\Comptabilite\Http\Requests\ConsulterJournalRequest;
use App\Domain\Comptabilite\Http\Resources\BalanceGeneraleResource;
use App\Domain\Comptabilite\Http\Resources\GrandLivreResource;
use App\Domain\Comptabilite\Http\Resources\JournalGeneralResource;
use App\Domain\Comptabilite\Models\CompteComptable;
use App\Domain\Comptabilite\Services\BalanceGeneraleService;
use App\Domain\Comptabilite\Services\GrandLivreService;
use App\Domain\Comptabilite\Services\JournalGeneralService;
use Illuminate\Http\JsonResponse;

/**
 * Les trois etats fondateurs de M10 — Journal General, Grand Livre, Balance
 * Generale.
 *
 * @see EF-M10-06 Edition des etats reglementaires SYSCOHADA
 * @see RG-11 Immutabilite — ces routes LISENT, elles n'ecrivent jamais
 * @see RG-16 RBAC de 2e niveau
 *
 * ## Simple orchestrateur (06_DEVELOPMENT_STANDARDS.md §2.2)
 *
 * Aucun calcul n'est ecrit ici : les trois etats vivent dans leurs `Service`,
 * et les trois passent par la meme portee (`PorteeEcrituresService`). Un
 * agregat recalcule dans un controleur finirait par contredire l'etat qu'il
 * pretend resumer — PA-121.
 *
 * ## AUCUNE route d'ecriture, et aucune route DELETE
 *
 * Les quatre pages fondatrices de M10 sont en consultation pure. RG-11 rend une
 * ecriture validee immuable et l'`EcritureComptableObserver` refuse TOUTE
 * suppression, meme en brouillon : router un `DELETE` reviendrait a exposer un
 * verbe dont la seule issue possible est une exception. Le verbe non route
 * (405) est la preuve la plus solide qu'il n'existe pas.
 *
 * La correction d'une ecriture passe exclusivement par la contre-passation
 * (`EcritureComptableService::contrepasser()`), qui n'a pas d'ecran dans ce lot
 * et n'est donc pas routee : un bouton qui n'ouvre rien empeche de savoir si la
 * fonction manque ou si l'ecran est casse.
 *
 * ## Le refus de volume rend 422, jamais un 500 ni une page tronquee
 *
 * Voir `EtatTropVolumineuxException` : ni troncature — qui rendrait des totaux
 * faux sous un bandeau d'anomalie —, ni pagination — qui poserait un total
 * juste au-dessus de lignes qui ne le font pas.
 */
class EtatsComptablesController
{
    public function __construct(
        private readonly JournalGeneralService $journalGeneral,
        private readonly GrandLivreService $grandLivre,
        private readonly BalanceGeneraleService $balance,
    ) {
    }

    /**
     * Journal General — `m10-journal.html`, EF-M10-06.
     */
    public function journal(ConsulterJournalRequest $request): JournalGeneralResource|JsonResponse
    {
        try {
            $etat = $this->journalGeneral->genererPourExercice(
                exerciceId: $request->exerciceId(),
                statuts: $request->statuts(),
                journalId: $request->journalId(),
                filtreStatut: $request->filtreStatut(),
            );
        } catch (EtatTropVolumineuxException $e) {
            return $this->refusDeVolume($e);
        }

        return new JournalGeneralResource($etat);
    }

    /**
     * Grand Livre d'un compte — `m10-grand-livre.html`, EF-M10-06.
     *
     * Un compte sans aucun mouvement rend 200 avec une liste vide, jamais 404 :
     * le compte existe, c'est son activite qui est nulle, et le maitre a un
     * message pour ce cas precis (l.29).
     */
    public function grandLivre(ConsulterGrandLivreRequest $request): GrandLivreResource|JsonResponse
    {
        $compte = CompteComptable::findOrFail($request->compteId());

        try {
            $etat = $this->grandLivre->genererPourCompte(
                exerciceId: $request->exerciceId(),
                compte: $compte,
                statuts: $request->statuts(),
                filtreStatut: $request->filtreStatut(),
            );
        } catch (EtatTropVolumineuxException $e) {
            return $this->refusDeVolume($e);
        }

        return new GrandLivreResource($etat);
    }

    /**
     * Balance Generale — `m10-balance.html`, EF-M10-06.
     *
     * Non plafonnee : elle rend une ligne par compte MOUVEMENTE, donc au plus
     * la taille du plan comptable, quel que soit le nombre d'ecritures.
     * L'agregation se fait en base.
     */
    public function balance(ConsulterEtatComptableRequest $request): BalanceGeneraleResource
    {
        return new BalanceGeneraleResource($this->balance->genererPourExercice(
            exerciceId: $request->exerciceId(),
            statuts: $request->statuts(),
            filtreStatut: $request->filtreStatut(),
        ));
    }

    /**
     * 422 avec le decompte reel : un refus qui ne dit pas de combien on depasse
     * ne permet pas de decider quoi filtrer.
     */
    private function refusDeVolume(EtatTropVolumineuxException $e): JsonResponse
    {
        return response()->json([
            'message' => $e->getMessage(),
            'lignes' => $e->lignes,
            'maximum' => $e->maximum,
        ], 422);
    }
}
