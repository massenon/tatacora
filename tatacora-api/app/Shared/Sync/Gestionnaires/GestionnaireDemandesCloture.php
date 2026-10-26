<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Domain\Comptabilite\Models\ClotureExercice;
use App\Domain\Comptabilite\Models\DemandeClotureExercice;
use App\Domain\Comptabilite\Models\ExerciceComptable;
use App\Domain\Comptabilite\Services\ArchiveClotureService;
use App\Domain\Comptabilite\Services\ClotureExerciceService;
use App\Models\User;
use App\Shared\Sync\Services\ResolveurCorrespondances;
use App\Shared\Sync\Services\SignalementAnomalies;
use App\Shared\Sync\Support\ContexteSynchronisation;
use App\Shared\Sync\Support\EcritureSynchronisee;
use RuntimeException;
use Throwable;

/**
 * Les DEMANDES de clôture d'exercice d'un poste (M10) — 26/10/2026, décision
 * du Product Owner : « la clôture annuelle SYSCOHADA DOIT ÊTRE IMPLÉMENTÉE EN
 * POSTE ET WEB ».
 *
 * ## Un document SOURCE, jamais une écriture (D246)
 *
 * Le poste clôture son exercice sur SES pièces (`MoteurComptable`), mais le
 * serveur reste le seul comptable : il ne reçoit AUCUNE pièce de clôture ni
 * d'à-nouveaux du poste. Il reçoit une DEMANDE — `annee` et `action` — et
 * REJOUE ses règles par `ClotureExerciceService`, exactement comme l'onglet
 * « Clôtures » de la PWA : ordre des exercices, liste de contrôle, brouillons,
 * rôle du comptable pour la réouverture, motif de dix caractères. Les pièces CL
 * et AN sont celles du serveur (tous les postes confondus) ; elles descendent
 * ensuite vers les postes avec le statut de l'exercice.
 *
 * Quatre actions, les quatre gestes du service : `demarrer`, `reprendre_saisie`,
 * `cloturer` (l'archive légale suit, hors de la clôture : un PDF qui échoue ne
 * la défait pas), `rouvrir` (`motif`).
 *
 * ## Une demande déjà satisfaite est ACCEPTÉE, sans rien réécrire
 *
 * Si l'exercice est déjà là où la demande l'amène (démarrer un exercice déjà
 * en clôture ou clôturé, clôturer un exercice déjà clôturé, reprendre la saisie
 * d'un exercice ouvert, rouvrir un exercice qui n'est pas clôturé), la demande
 * est enregistrée `deja_dans_cet_etat` : la rejeter ferait croire au poste que
 * le serveur est en désaccord alors qu'il est d'accord. C'est la seule
 * tolérance ; tout le reste est un refus aux phrases du service.
 *
 * Création seule : une demande ne se corrige pas, elle se renvoie (nouvel
 * identifiant) depuis « À traiter ».
 */
final class GestionnaireDemandesCloture extends GestionnaireDocumentAbstrait
{
    public const ACTIONS = ['demarrer', 'reprendre_saisie', 'cloturer', 'rouvrir'];

    public function __construct(
        private readonly ClotureExerciceService $clotures,
        private readonly ArchiveClotureService $archives,
        ResolveurCorrespondances $correspondances,
        SignalementAnomalies $anomalies,
    ) {
        parent::__construct($correspondances, $anomalies);
    }

    public function table(): string
    {
        return 'demandes_cloture_exercice';
    }

    public function module(): string
    {
        return 'M10';
    }

    public function serviceDomaine(): string
    {
        return ClotureExerciceService::class;
    }

    protected function resultat(string $entiteId): EcritureSynchronisee
    {
        $demande = DemandeClotureExercice::query()->findOrFail($entiteId);

        return new EcritureSynchronisee($entiteId, complements: array_filter([
            'issue' => $demande->issue,
            'statut_exercice' => $demande->statut_exercice,
            'piece_cloture' => $demande->piece_cloture,
            'piece_a_nouveaux' => $demande->piece_a_nouveaux,
            'archive_empreinte' => $demande->archive_empreinte,
        ], static fn (mixed $v): bool => $v !== null));
    }

    public function reprendreExistant(string $entiteId, ContexteSynchronisation $contexte): ?EcritureSynchronisee
    {
        return DemandeClotureExercice::query()->whereKey($entiteId)->exists() ? $this->resultat($entiteId) : null;
    }

    public function creer(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $donnees = $this->validerForme($payload, [
            'annee' => ['required', 'integer', 'between:2000,2100'],
            'action' => ['required', 'string'],
            'motif' => ['nullable', 'string'],
        ], [
            'annee.between' => __('comptabilite.exercice_annee_invalide'),
        ]);

        $action = (string) $donnees['action'];

        if (! in_array($action, self::ACTIONS, true)) {
            throw new RuntimeException(__('comptabilite.demande_cloture_action_inconnue', [
                'action' => $action,
                'admises' => implode(', ', self::ACTIONS),
            ]));
        }

        $annee = (int) $donnees['annee'];
        $exercice = ExerciceComptable::query()->where('annee', $annee)->lockForUpdate()->first();

        if ($exercice === null) {
            throw new RuntimeException(__('comptabilite.demande_cloture_exercice_inconnu', ['annee' => (string) $annee]));
        }

        $auteur = $contexte->utilisateur;
        $motif = isset($donnees['motif']) ? (string) $donnees['motif'] : '';
        $issue = DemandeClotureExercice::ISSUE_EXECUTEE;
        $cloture = null;
        $empreinte = null;

        if ($this->dejaSatisfaite($action, $exercice->statut)) {
            $issue = DemandeClotureExercice::ISSUE_DEJA_DANS_CET_ETAT;
        } else {
            switch ($action) {
                case 'demarrer':
                    $this->clotures->demarrer($exercice, $auteur);
                    break;
                case 'reprendre_saisie':
                    $this->clotures->reprendreSaisie($exercice, $auteur);
                    break;
                case 'cloturer':
                    $cloture = $this->clotures->cloturer($exercice, $auteur);
                    $empreinte = $this->archiver($cloture, $auteur);
                    break;
                case 'rouvrir':
                    $this->clotures->rouvrir($exercice, $auteur, $motif);
                    break;
            }
        }

        $exercice->refresh();

        DemandeClotureExercice::query()->create([
            'id' => $entiteId,
            'exercice_id' => $exercice->id,
            'annee' => $annee,
            'action' => $action,
            'motif' => $motif === '' ? null : $motif,
            'issue' => $issue,
            'statut_exercice' => $exercice->statut,
            'piece_cloture' => $cloture?->piece_cloture,
            'piece_a_nouveaux' => $cloture?->piece_a_nouveaux,
            'resultat' => $cloture?->resultat,
            'archive_empreinte' => $empreinte,
            'poste_id' => $contexte->posteId,
            'demandeur_id' => $auteur->id,
            'demandee_le' => $contexte->horodatageClient,
        ]);

        return $this->resultat($entiteId);
    }

    /** La demande amène-t-elle l'exercice là où il est déjà ? */
    private function dejaSatisfaite(string $action, string $statut): bool
    {
        return match ($action) {
            'demarrer' => in_array($statut, ['en_cloture', 'cloture'], true),
            'reprendre_saisie' => $statut === 'ouvert',
            'cloturer' => $statut === 'cloture',
            'rouvrir' => $statut !== 'cloture',
            default => false,
        };
    }

    /**
     * L'archive légale suit la clôture ; son échec ne la défait pas (la PWA
     * propose alors « Générer l'archive »).
     */
    private function archiver(ClotureExercice $cloture, User $auteur): ?string
    {
        try {
            return $this->archives->archiver($cloture, $auteur)->archive_empreinte;
        } catch (Throwable $echec) {
            report($echec);

            return null;
        }
    }
}
