<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Domain\Comptabilite\Models\CentreCout;
use App\Domain\Comptabilite\Services\ClotureExerciceService;
use App\Domain\Comptabilite\Services\EcritureComptableService;
use App\Domain\Comptabilite\Services\PasserEcritureService;
use App\Shared\Sync\Services\ResolveurCorrespondances;
use App\Shared\Sync\Services\SignalementAnomalies;
use App\Shared\Sync\Support\ContexteSynchronisation;
use App\Shared\Sync\Support\EcritureSynchronisee;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

/**
 * Les pièces SAISIES À LA MAIN sur un poste (hub comptable, « Nouvelle
 * écriture ») — D246 rouvert par décision du PO du 28/10/2026 : elles sont
 * partagées entre les postes et le web.
 *
 * ## Une pièce SOURCE, rejouée — jamais une écriture reçue
 *
 * Le poste envoie la SOURCE de sa saisie : journal, date, libellé, statut et
 * lignes (compte par son NUMÉRO, débit et crédit en CENTIMES entiers, centre
 * explicite éventuel). Le serveur la rejoue par `PasserEcritureService` —
 * exactement le chemin de `Hub::enregistrerPiece` — sous les MÊMES règles et
 * les mêmes phrases : journal connu et non réservé (CL, AN), date valide, au
 * moins deux lignes, compte du plan imputable (pas une division), un montant
 * par ligne, débit ou crédit mais pas les deux, équilibre, exercice ouvert (ou
 * en clôture, saisie du comptable), centre de coût obligatoire (RG-12). Le
 * serveur passe SA pièce (son numéro, ses lignes) : brouillon ou validée selon
 * le statut du poste, puis immuable (RG-11).
 *
 * ## Idempotence et provenance
 *
 * L'identifiant du poste est posé sur chaque ligne de la pièce du serveur
 * (`piece_origine_id`) AVANT la validation : un rejeu retrouve la pièce sans
 * second numéro, et l'écriture redescend vers les postes avec cet identifiant
 * pour que son auteur la reconnaisse dans son miroir (jamais comptée deux fois).
 *
 * Création seule : la PWA n'a aucun geste de validation différée ni de
 * correction d'un brouillon.
 */
final class GestionnairePiecesSaisie extends GestionnaireDocumentAbstrait
{
    public function __construct(
        private readonly PasserEcritureService $saisie,
        private readonly EcritureComptableService $ecritures,
        ResolveurCorrespondances $correspondances,
        SignalementAnomalies $anomalies,
    ) {
        parent::__construct($correspondances, $anomalies);
    }

    public function table(): string
    {
        return 'pieces_saisie';
    }

    public function module(): string
    {
        return 'M10';
    }

    public function serviceDomaine(): string
    {
        return PasserEcritureService::class;
    }

    public function reprendreExistant(string $entiteId, ContexteSynchronisation $contexte): ?EcritureSynchronisee
    {
        return DB::table('pieces_saisie')->where('id', $entiteId)->exists() ? $this->resultat($entiteId) : null;
    }

    protected function resultat(string $entiteId): EcritureSynchronisee
    {
        $source = DB::table('pieces_saisie')->where('id', $entiteId)->first();

        return new EcritureSynchronisee($entiteId, complements: [
            'numero_piece' => (string) $source?->numero_piece,
            'statut_piece' => (string) $source?->statut,
        ]);
    }

    public function creer(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $forme = $this->validerForme($payload, [
            'journal' => ['nullable', 'string'],
            'date' => ['nullable', 'string'],
            'libelle' => ['nullable', 'string'],
            'statut' => ['required', 'string', Rule::in(['brouillon', 'validee'])],
            'lignes' => ['nullable', 'array'],
            'lignes.*.compte' => ['nullable', 'string'],
            'lignes.*.libelle' => ['nullable', 'string'],
            'lignes.*.centre' => ['nullable', 'string'],
            'lignes.*.debit' => ['nullable', 'integer', 'min:0'],
            'lignes.*.credit' => ['nullable', 'integer', 'min:0'],
        ]);

        // Les mêmes règles de FORME que `Hub::enregistrerPiece`, aux mêmes
        // noms de champ : le refus porte donc la même phrase que l'écran web.
        $lignesBrutes = [];

        foreach ((array) ($forme['lignes'] ?? []) as $ligne) {
            // Le centre voyage par son LIBELLÉ (les identifiants de centre du poste
            // ne sont pas ceux du serveur) ; un libellé inconnu reste tel quel et
            // tombe sur la règle `exists` du web.
            $libelleCentre = trim((string) ($ligne['centre'] ?? ''));
            $centre = $libelleCentre === ''
                ? null
                : (CentreCout::query()->where('libelle', $libelleCentre)->value('id') ?? $libelleCentre);

            $lignesBrutes[] = [
                'compte' => (string) ($ligne['compte'] ?? ''),
                'libelle' => $ligne['libelle'] ?? null,
                'centre_id' => $centre === '' ? null : $centre,
                'debit' => $this->centiemes((int) ($ligne['debit'] ?? 0)),
                'credit' => $this->centiemes((int) ($ligne['credit'] ?? 0)),
            ];
        }

        $valide = $this->validerForme([
            'journalCode' => $forme['journal'] ?? null,
            'dateEcriture' => $forme['date'] ?? null,
            'libellePiece' => $forme['libelle'] ?? null,
            'lignesPiece' => $lignesBrutes,
        ], [
            'journalCode' => ['required', 'string', 'exists:journaux_comptables,code', Rule::notIn(ClotureExerciceService::JOURNAUX_RESERVES)],
            'dateEcriture' => ['required', 'date'],
            'libellePiece' => ['required', 'string', 'max:255'],
            'lignesPiece' => ['required', 'array', 'min:2'],
            'lignesPiece.*.compte' => ['required', 'string', 'exists:plan_comptable,numero_compte'],
            'lignesPiece.*.libelle' => ['nullable', 'string', 'max:255'],
            'lignesPiece.*.centre_id' => ['nullable', 'string', 'exists:centres_cout,id'],
            'lignesPiece.*.debit' => ['nullable', 'numeric', 'min:0'],
            'lignesPiece.*.credit' => ['nullable', 'numeric', 'min:0'],
        ]);

        $lignes = [];

        foreach ($valide['lignesPiece'] as $position => $ligne) {
            $debit = bcadd((string) ($ligne['debit'] ?? '0'), '0', 2);
            $credit = bcadd((string) ($ligne['credit'] ?? '0'), '0', 2);

            if (bccomp($debit, '0', 2) > 0 && bccomp($credit, '0', 2) > 0) {
                throw new \RuntimeException(__('comptabilite_pwa.ligne_debit_et_credit', ['position' => $position + 1]));
            }

            if (bccomp($debit, '0', 2) <= 0 && bccomp($credit, '0', 2) <= 0) {
                throw new \RuntimeException(__('comptabilite_pwa.ligne_montant_requis', ['position' => $position + 1]));
            }

            $libelleLigne = isset($ligne['libelle']) ? trim((string) $ligne['libelle']) : '';

            $lignes[] = [
                'compte' => (string) $ligne['compte'],
                'libelle' => $libelleLigne === '' ? null : $libelleLigne,
                'centre_id' => isset($ligne['centre_id']) && $ligne['centre_id'] !== '' ? (string) $ligne['centre_id'] : null,
                'debit' => $debit,
                'credit' => $credit,
            ];
        }

        $donnees = [
            'journal' => (string) $valide['journalCode'],
            'date' => (string) $valide['dateEcriture'],
            'libelle' => trim((string) $valide['libellePiece']),
            'lignes' => $lignes,
            // La saisie du hub est celle du COMPTABLE : elle passe aussi dans un
            // exercice EN CLÔTURE (ses écritures d'inventaire).
            'statuts_exercice_admis' => ['ouvert', 'en_cloture'],
        ];

        DB::transaction(function () use ($donnees, $forme, $entiteId, $contexte): void {
            $piece = $this->saisie->passer($donnees);

            // Avant la validation : une validée ne se modifie plus (RG-11).
            DB::table('ecritures_comptables')
                ->whereIn('id', $piece->pluck('id')->all())
                ->update(['piece_origine_id' => $entiteId]);

            if ($forme['statut'] === 'validee') {
                $this->ecritures->valider($piece);
            }

            DB::table('pieces_saisie')->insert([
                'id' => $entiteId,
                'journal' => $donnees['journal'],
                'date_piece' => $donnees['date'],
                'libelle' => $donnees['libelle'],
                'statut' => $forme['statut'],
                'numero_piece' => $piece->first()?->numero_piece,
                'nombre_lignes' => count($donnees['lignes']),
                'poste_id' => $contexte->posteId,
                'auteur_id' => $contexte->utilisateur->id,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        });

        return $this->resultat($entiteId);
    }
}
