<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Domain\Caisse\Models\SessionCaisse;
use App\Domain\Caisse\Services\SessionCaisseService;
use App\Shared\Sync\Models\AnomalieSynchronisation;
use App\Shared\Sync\Services\ResolveurCorrespondances;
use App\Shared\Sync\Services\SignalementAnomalies;
use App\Shared\Sync\Support\ContexteSynchronisation;
use App\Shared\Sync\Support\EcritureSynchronisee;
use Carbon\Exceptions\InvalidFormatException;
use Illuminate\Support\Carbon;
use Illuminate\Validation\Rule;
use RuntimeException;

/**
 * Sessions de caisse ouvertes et clôturées hors connexion (M5, niveau C —
 * celui de `PosComptant::ouvrirCaisse/cloturerCaisse`) — lot S3, décision du
 * Product Owner du 15/10/2026.
 *
 * ## Deux gestes sur la même entité
 *
 * - **Ouverture** = `creation` : `point_vente`, `date_ouverture`,
 *   `montant_fond_centimes` (le poste compte en centimes entiers). L'auteur
 *   est l'utilisateur du JETON (RG-15) — un `utilisateur_ouverture_id` du
 *   payload est ignoré, comme la route ignore un auteur fourni.
 * - **Clôture** = `modification`, et SEULE modification admise : champs
 *   `date_cloture`, `montant_constate_centimes` et, facultatif,
 *   `montant_theorique_centimes` (le théorique calculé par le poste). Tout
 *   autre champ est refusé : le fond ou la date d'ouverture d'un tiroir ne se
 *   réécrivent pas.
 *
 * Les deux passent par `SessionCaisseService`, l'auteur unique que la PWA
 * appelle aussi. Les dates sont des dates MÉTIER (D246).
 *
 * ## Le théorique : recalculé par le serveur, l'écart SIGNALÉ
 *
 * Le serveur recalcule le théorique sur SES ventes en espèces de la session
 * (celles que le poste a poussées avant la clôture — d'où l'ordre : ouverture
 * → ventes → clôture, dans l'ordre de la file du poste). Le théorique du
 * poste n'est PAS écrit (aucune colonne ne le porte, et en créer une ferait
 * deux vérités sur la même pièce) : s'il diffère, l'écart est enregistré
 * (`anomalies_synchronisation`, type `ecart_theorique_caisse`) et rendu au
 * poste avec les deux montants. Rien n'est corrigé en silence.
 *
 * ## Ouverture et clôture dans le même lot — pas un conflit
 *
 * La clôture est saisie (22 h) AVANT que l'ouverture ne soit écrite sur le
 * serveur (à la réception du lot) : la comparaison d'horodatages y voyait une
 * « modification concurrente sur une donnée financière ». Le moteur reconnaît
 * désormais que la dernière écriture est celle du MÊME poste
 * (`SynchronisationService::derniereEcritureEstDuPoste`) : la clôture passe.
 *
 * ## Clôture d'une session inconnue : jamais bloquée (décision PO du 15/10/2026)
 *
 * Ouverture refusée par le serveur (caisse déjà ouverte sur ce point) ou
 * jamais reçue : le poste a quand même tenu et fermé son tiroir. Sa clôture
 * est ACCEPTÉE en `cloture_sans_session_serveur` — rien n'est écrit qu'une
 * anomalie `cloture_session_inconnue` portant ses chiffres
 * (`modificationSurInconnu()`). Les ventes de cette session ont été
 * enregistrées et signalées (`vente_session_inconnue`, `GestionnaireVentes`).
 *
 * ## Rejeu
 *
 * Ouverture rejouée → la session existante (`reprendreExistant`). Clôture
 * rejouée à l'identique (même date, même constaté) → résultat d'origine ;
 * clôture DIFFÉRENTE d'une session déjà close → refus (`caisse.deja_cloturee`).
 */
final class GestionnaireSessionsCaisse extends GestionnaireDocumentAbstrait
{
    /** Les seuls champs qu'une clôture transmet. */
    public const CHAMPS_CLOTURE = ['date_cloture', 'montant_constate_centimes', 'montant_theorique_centimes'];

    /**
     * Champs d'OUVERTURE qu'une clôture peut rappeler, à titre d'information
     * (décision PO du 15/10/2026) : le poste ne sait pas toujours si le
     * serveur connaît sa session, il les joint donc à sa clôture. Session
     * inconnue → ils vont dans l'anomalie `cloture_session_inconnue` ;
     * session connue → acceptés s'ils sont CEUX du serveur, refusés sinon
     * (le fond ou l'ouverture d'un tiroir ne se réécrivent pas).
     */
    public const CHAMPS_RAPPEL_OUVERTURE = ['point_vente', 'date_ouverture', 'montant_fond_centimes'];

    public function __construct(
        private readonly SessionCaisseService $caisses,
        ResolveurCorrespondances $correspondances,
        SignalementAnomalies $anomalies,
    ) {
        parent::__construct($correspondances, $anomalies);
    }

    public function table(): string
    {
        return 'sessions_caisse';
    }

    public function module(): string
    {
        return 'M5';
    }

    public function serviceDomaine(): string
    {
        return SessionCaisseService::class;
    }

    public function accepteModification(): bool
    {
        return true;
    }

    public function champDateDocument(): ?string
    {
        return 'date_ouverture';
    }

    public function creer(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $donnees = $this->validerForme($payload, [
            'point_vente' => ['required', Rule::in(SessionCaisseService::POINTS)],
            'date_ouverture' => ['required', 'date'],
            'montant_fond_centimes' => ['required', 'integer', 'min:0'],
        ], [
            'point_vente.in' => __('caisse.point_inconnu', ['point' => (string) ($payload['point_vente'] ?? '')]),
        ]);

        $this->caisses->ouvrir(
            (string) $donnees['point_vente'],
            $this->centiemes((int) $donnees['montant_fond_centimes']),
            $contexte->utilisateur->id,
            $this->dateDuDocument($donnees['date_ouverture'], $contexte),
            $entiteId,
        );

        return $this->resultat($entiteId);
    }

    /**
     * Clôture d'une session que le serveur ne connaît pas — décision du
     * Product Owner du 15/10/2026 : une clôture n'est JAMAIS bloquée.
     *
     * Le serveur a refusé l'ouverture du poste (une caisse était déjà
     * ouverte sur ce point) ou ne l'a jamais reçue ; le poste, lui, a ouvert,
     * vendu et clôturé son tiroir. Rien n'est écrit — aucune session, aucune
     * pièce : le serveur n'a pas de tiroir à fermer — sauf l'anomalie
     * `cloture_session_inconnue`, qui porte les chiffres du poste (fond,
     * théorique, constaté, dates) pour la reprise à la main. Le poste reçoit
     * `cloture_sans_session_serveur` : ce n'est PAS une erreur, il retire
     * l'opération de sa file. Rejouée, elle rend le même résultat sans
     * second signalement (anomalie unique par session).
     */
    public function modificationSurInconnu(string $entiteId, array $payload, ContexteSynchronisation $contexte): ?EcritureSynchronisee
    {
        $donnees = $this->validerForme($payload, [
            'date_cloture' => ['required', 'date'],
            'montant_constate_centimes' => ['required', 'integer', 'min:0'],
            'montant_theorique_centimes' => ['nullable', 'integer', 'min:0'],
            'montant_fond_centimes' => ['nullable', 'integer', 'min:0'],
            'date_ouverture' => ['nullable', 'date'],
            'point_vente' => ['nullable', 'string', 'max:50'],
        ]);

        $centiemes = fn (string $champ): ?string => isset($donnees[$champ]) ? $this->centiemes((int) $donnees[$champ]) : null;
        $date = static fn (string $champ): ?string => isset($donnees[$champ])
            ? Carbon::parse((string) $donnees[$champ])->format('Y-m-d H:i:s')
            : null;

        $this->anomalies->signaler(
            $contexte,
            $this->table(),
            $entiteId,
            AnomalieSynchronisation::CLOTURE_SESSION_INCONNUE,
            valeurPoste: $centiemes('montant_constate_centimes'),
            details: [
                'point_vente' => $donnees['point_vente'] ?? null,
                'date_ouverture' => $date('date_ouverture'),
                'date_cloture' => $date('date_cloture'),
                'montant_fond' => $centiemes('montant_fond_centimes'),
                'montant_theorique_poste' => $centiemes('montant_theorique_centimes'),
                'montant_constate' => $centiemes('montant_constate_centimes'),
            ],
        );

        return new EcritureSynchronisee(
            $entiteId,
            complements: [
                'statut_caisse' => 'cloturee_sur_le_poste',
                'anomalies' => [AnomalieSynchronisation::CLOTURE_SESSION_INCONNUE],
            ],
            statut: EcritureSynchronisee::CLOTURE_SANS_SESSION_SERVEUR,
        );
    }

    public function modifier(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $session = SessionCaisse::query()->findOrFail($entiteId);
        $payload = $this->sansRappelsConformes($session, $payload);

        $etrangers = array_diff(array_keys($payload), self::CHAMPS_CLOTURE);

        if ($etrangers !== []) {
            throw new RuntimeException(__('sync.caisse.champ_non_modifiable', [
                'champs' => implode(', ', $etrangers),
            ]));
        }

        $donnees = $this->validerForme($payload, [
            'date_cloture' => ['required', 'date'],
            'montant_constate_centimes' => ['required', 'integer', 'min:0'],
            'montant_theorique_centimes' => ['nullable', 'integer', 'min:0'],
        ]);

        $date = $this->dateDuDocument($donnees['date_cloture'], $contexte);
        $constate = $this->centiemes((int) $donnees['montant_constate_centimes']);

        if ($session->date_cloture !== null) {
            // Rejeu de la MÊME clôture : le résultat d'origine. Toute autre
            // clôture d'une session close est un refus — une clôture ne se
            // refait pas.
            if ($session->date_cloture->equalTo($date)
                && bccomp((string) $session->montant_constate, $constate, 2) === 0) {
                return $this->resultat($entiteId);
            }

            throw new RuntimeException(__('caisse.deja_cloturee'));
        }

        $session = $this->caisses->cloturer($session, $constate, $date);

        if (isset($donnees['montant_theorique_centimes'])) {
            $theoriquePoste = $this->centiemes((int) $donnees['montant_theorique_centimes']);

            if (bccomp($theoriquePoste, (string) $session->montant_theorique, 2) !== 0) {
                $this->anomalies->signaler(
                    $contexte,
                    $this->table(),
                    $entiteId,
                    AnomalieSynchronisation::ECART_THEORIQUE_CAISSE,
                    valeurPoste: $theoriquePoste,
                    valeurServeur: (string) $session->montant_theorique,
                );
            }
        }

        return $this->resultat($entiteId);
    }

    /**
     * Retire les rappels d'ouverture qui disent ce que le serveur sait déjà ;
     * un rappel DIFFÉRENT reste, et sera refusé comme champ non modifiable.
     *
     * @param  array<string, mixed>  $payload
     * @return array<string, mixed>
     */
    private function sansRappelsConformes(SessionCaisse $session, array $payload): array
    {
        $conformes = [
            'point_vente' => static fn (mixed $v): bool => $v === $session->point_vente,
            'date_ouverture' => static function (mixed $v) use ($session): bool {
                try {
                    return is_string($v) && Carbon::parse($v)->equalTo($session->date_ouverture);
                } catch (InvalidFormatException) {
                    return false;
                }
            },
            'montant_fond_centimes' => fn (mixed $v): bool => is_int($v)
                && bccomp($this->centiemes($v), (string) $session->montant_fond, 2) === 0,
        ];

        foreach ($conformes as $champ => $estConforme) {
            if (array_key_exists($champ, $payload) && $estConforme($payload[$champ])) {
                unset($payload[$champ]);
            }
        }

        return $payload;
    }

    protected function resultat(string $entiteId): EcritureSynchronisee
    {
        $session = SessionCaisse::query()->findOrFail($entiteId);

        if ($session->date_cloture === null) {
            return new EcritureSynchronisee($entiteId, complements: ['statut_caisse' => 'ouverte']);
        }

        $complements = [
            'statut_caisse' => 'cloturee',
            'montant_theorique' => (string) $session->montant_theorique,
            'montant_constate' => (string) $session->montant_constate,
            'ecart' => SessionCaisseService::ecart((string) $session->montant_constate, (string) $session->montant_theorique),
        ];

        $ecart = AnomalieSynchronisation::query()
            ->where('table_concernee', $this->table())
            ->where('entite_id', $entiteId)
            ->where('type', AnomalieSynchronisation::ECART_THEORIQUE_CAISSE)
            ->first();

        if ($ecart !== null) {
            $complements['montant_theorique_poste'] = (string) $ecart->valeur_poste;
            $complements['ecart_theorique'] = bcsub((string) $ecart->valeur_poste, (string) $ecart->valeur_serveur, 2);
        }

        return new EcritureSynchronisee($entiteId, complements: $complements);
    }
}
