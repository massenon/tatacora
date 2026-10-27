<?php

declare(strict_types=1);

namespace App\Shared\Sync\Http\Controllers;

use App\Domain\Depenses\Exceptions\RefusRecuDepense;
use App\Domain\Depenses\Models\Depense;
use App\Domain\Depenses\Services\RecuDepenseService;
use App\Models\User;
use App\Shared\Rbac\Models\JournalSecurite;
use App\Shared\Sync\Services\JournalReceptionService;
use App\Shared\Sync\Support\PosteDuJeton;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Ramsey\Uuid\Uuid;
use Symfony\Component\HttpFoundation\Response;
use Throwable;

/**
 * Le REÇU en image d'une dépense, par la synchronisation (lot L4, décision du
 * PO du 27/10/2026 : « on accepte un transport de fichier dans la
 * synchronisation pour le reçu de dépense »).
 *
 * `POST /api/v1/sync` est du JSON borné en lots : un fichier n'y a pas sa
 * place. Le reçu a donc sa propre porte, rattachée à l'UUID de la dépense que
 * le poste a créé :
 *
 *  * `PUT /api/v1/sync/depenses/{depense}/recu?poste_id=…` — le CORPS est le
 *    fichier brut (`Content-Type: image/*`), `X-Recu-Sha256` son empreinte ;
 *  * `GET /api/v1/sync/depenses/{depense}/recu?poste_id=…` — le fichier, à la
 *    demande d'un poste (jamais en masse : la descente du catalogue ne porte
 *    que la RÉFÉRENCE, `donnees.recu`).
 *
 * ## Dépôt
 *
 * Les mêmes droits que la dépense (écriture sur M10 — le niveau que
 * `GestionnaireDepenses` exige) ET le même poste : la dépense doit avoir été
 * poussée par CE poste (`origines_synchronisation`), ou, quand cette trace a
 * été purgée, par ce compte. Contrôles dans l'ordre : compte actif, poste du
 * jeton, droit, taille annoncée (413 avant de lire le corps), dépense connue
 * (404 `depense_inconnue` : le poste réessaiera après elle), origine, puis le
 * contenu (`RecuDepenseService`, règles et phrases de l'écran web).
 *
 * Réponses : 200 `{data: {depense_id, sha256, taille, type, rejeu}}` — `rejeu`
 * vrai quand le même fichier était déjà là (réponse perdue) — ; 401, 403, 404,
 * 409 (autre reçu déjà rattaché), 413, 422. Chaque dépôt abouti ou refusé pour
 * un motif de fond est consigné au journal de réception (table
 * `recus_depenses`), avec sa cause en français ; il n'y a rien à « corriger »
 * côté serveur — le poste renvoie un fichier valable.
 */
final class RecuDepenseController
{
    private const MODULE = 'M10';

    public function __construct(
        private readonly RecuDepenseService $recus,
        private readonly JournalReceptionService $journal,
    ) {
    }

    public function deposer(Request $request, string $depense): JsonResponse
    {
        $utilisateur = $this->utilisateurActif($request);

        if ($utilisateur === null) {
            return response()->json(['message' => __('sync.referentiels.compte_inactif')], 401);
        }

        $poste = (string) $request->query('poste_id', '');

        if ($poste === '' || strlen($poste) > 255) {
            return response()->json([
                'message' => 'Le poste est obligatoire.',
                'errors' => ['poste_id' => ['Le champ poste id est obligatoire.']],
            ], 422);
        }

        if (! PosteDuJeton::concorde($request, $poste)) {
            return response()->json(['message' => __('sync.poste_non_reconnu')], 403);
        }

        if ($utilisateur->niveauSurModule(self::MODULE) !== 'C') {
            JournalSecurite::create([
                'type_evenement' => 'acces_refuse_rbac',
                'utilisateur_id' => $utilisateur->id,
                'adresse_ip' => $request->ip(),
                'module_concerne' => self::MODULE,
            ]);

            return $this->refus($depense, $poste, $utilisateur, null, new RefusRecuDepense(
                'droit_manquant',
                __('auth.module_refuse'),
                403,
            ));
        }

        // La taille ANNONCÉE d'abord : un fichier démesuré n'est même pas lu.
        $annoncee = (int) $request->header('Content-Length', '0');

        if ($annoncee > RecuDepenseService::TAILLE_MAX_KO * 1024) {
            return $this->refus($depense, $poste, $utilisateur, hash('sha256', $depense.'|'.$annoncee), new RefusRecuDepense(
                'recu_trop_lourd',
                __('validation.max.file', ['attribute' => 'photo recu', 'max' => RecuDepenseService::TAILLE_MAX_KO]),
                413,
            ));
        }

        $octets = (string) $request->getContent();
        $sha256 = hash('sha256', $octets);

        $document = Depense::query()->find($depense);

        if ($document === null) {
            // Pas encore arrivée par `POST /sync` : ce n'est pas un échec, le
            // poste réessaiera à son prochain passage. Rien à consigner.
            return response()->json([
                'code' => 'depense_inconnue',
                'message' => __('depenses.recu_depense_inconnue'),
            ], 404);
        }

        $origine = DB::table('origines_synchronisation')
            ->where('table_concernee', 'depenses')
            ->where('entite_id', $depense)
            ->value('poste_id');

        $dumemePoste = $origine !== null
            ? (string) $origine === $poste
            : (string) $document->utilisateur_id === (string) $utilisateur->id;

        if (! $dumemePoste) {
            return $this->refus($depense, $poste, $utilisateur, $sha256, new RefusRecuDepense(
                'recu_autre_poste',
                __('depenses.recu_autre_poste'),
                403,
            ));
        }

        try {
            $depot = $this->recus->deposer($depense, $octets, $request->header('X-Recu-Sha256'));
        } catch (RefusRecuDepense $refus) {
            if ($refus->codeMotif === 'depense_inconnue') {
                return response()->json(['code' => 'depense_inconnue', 'message' => $refus->getMessage()], 404);
            }

            return $this->refus($depense, $poste, $utilisateur, $sha256, $refus);
        }

        $this->consigner($depense, $poste, $utilisateur, $sha256, strlen($octets), [
            'statut' => 'synchronise',
            ...($depot['rejeu'] ? ['rejeu_idempotent' => true] : []),
        ]);

        return response()->json(['data' => [
            'depense_id' => $depense,
            'sha256' => (string) $depot['depense']->recu_sha256,
            'taille' => (int) $depot['depense']->recu_taille,
            'type' => (string) $depot['depense']->recu_type,
            'rejeu' => $depot['rejeu'],
        ]]);
    }

    public function telecharger(Request $request, string $depense): Response
    {
        $utilisateur = $this->utilisateurActif($request);

        if ($utilisateur === null) {
            return response()->json(['message' => __('sync.referentiels.compte_inactif')], 401);
        }

        $poste = (string) $request->query('poste_id', '');

        if ($poste === '') {
            return response()->json([
                'message' => 'Le poste est obligatoire.',
                'errors' => ['poste_id' => ['Le champ poste id est obligatoire.']],
            ], 422);
        }

        if (! PosteDuJeton::concorde($request, $poste)) {
            return response()->json(['message' => __('sync.poste_non_reconnu')], 403);
        }

        // Lire une dépense, c'est lire M10 — le droit que la descente exige.
        if ($utilisateur->niveauSurModule(self::MODULE) === '-') {
            return response()->json(['message' => __('auth.module_refuse')], 403);
        }

        $document = Depense::query()->find($depense);
        $fichier = $document === null ? null : $this->recus->lire($document);

        if ($fichier === null) {
            return response()->json(['code' => 'recu_introuvable', 'message' => __('depenses.recu_introuvable')], 404);
        }

        return response($fichier['octets'], 200, [
            'Content-Type' => $fichier['type'],
            'Content-Length' => (string) strlen($fichier['octets']),
            'X-Recu-Sha256' => $fichier['sha256'],
            'X-Content-Type-Options' => 'nosniff',
            'Cache-Control' => 'private, no-store',
        ]);
    }

    private function utilisateurActif(Request $request): ?User
    {
        $utilisateur = $request->user();

        return $utilisateur instanceof User && $utilisateur->estActif() ? $utilisateur : null;
    }

    private function refus(string $depense, string $poste, User $utilisateur, ?string $sha256, RefusRecuDepense $refus): JsonResponse
    {
        $this->consigner($depense, $poste, $utilisateur, $sha256 ?? hash('sha256', $depense), null, [
            'statut' => 'rejete',
            'code_motif' => $refus->codeMotif,
            'motif' => $refus->getMessage(),
        ]);

        return response()->json([
            'code' => $refus->codeMotif,
            'message' => $refus->getMessage(),
            'errors' => ['photoRecu' => [$refus->getMessage()]],
        ], $refus->statutHttp);
    }

    /**
     * La ligne du journal de réception : une par (dépense, empreinte reçue) ;
     * le même fichier renvoyé incrémente ses tentatives. Un échec d'écriture du
     * journal ne fait jamais échouer le dépôt (`JournalReceptionService`).
     *
     * @param  array<string, mixed>  $resultat
     */
    private function consigner(string $depense, string $poste, User $utilisateur, string $sha256, ?int $taille, array $resultat): void
    {
        try {
            $this->journal->enregistrer([
                // Déterministe : le même fichier renvoyé retombe sur la même ligne.
                'uuid_operation' => Uuid::uuid5(Uuid::NAMESPACE_URL, 'recu-depense:'.$depense.':'.$sha256)->toString(),
                'table' => JournalReceptionService::TABLE_RECUS_DEPENSES,
                'type' => 'creation',
                'entite_id' => $depense,
                'horodatage_client' => now()->toIso8601String(),
                'payload' => ['sha256' => $sha256, ...($taille !== null ? ['taille' => $taille] : [])],
            ], $poste, (string) $utilisateur->id, null, $resultat);
        } catch (Throwable) {
            // Voir la doc de la méthode.
        }
    }
}
