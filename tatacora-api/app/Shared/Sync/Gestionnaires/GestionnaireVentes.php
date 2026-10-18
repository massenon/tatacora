<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Domain\Caisse\Models\SessionCaisse;
use App\Domain\Hebergement\Models\Reservation;
use App\Domain\Stocks\Exceptions\RuptureStockException;
use App\Domain\Ventes\Models\LigneVente;
use App\Domain\Ventes\Models\Vente;
use App\Domain\Ventes\Services\VenteService;
use App\Pwa\Livewire\Pos\PosComptant;
use App\Shared\Sync\Models\AnomalieSynchronisation;
use App\Shared\Sync\Services\ResolveurCorrespondances;
use App\Shared\Sync\Services\SignalementAnomalies;
use App\Shared\Sync\Support\ContexteSynchronisation;
use App\Shared\Sync\Support\DocumentsDesAutresPostes;
use App\Shared\Sync\Support\EcritureSynchronisee;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Ventes au COMPTANT encaissées hors connexion (M5, et M4 quand le ticket
 * porte des plats — comme `PosComptant::encaissementReel`) — lot S3,
 * décisions du Product Owner du 15/10/2026.
 *
 * ## Le payload : le panier clôturé du poste
 *
 * Aligné sur `PanierDao.cloturer` (`paniers_local` + `lignes_panier_local`) :
 * `type_vente`, `mode_paiement`, `session_encaissement_id`, `cloture_le`,
 * `point_vente`, `table`, `table_id`, `client_nom`, `montant_cloture`
 * (francs), et `lignes[]` — `module_source`, `code_article` (id de la carte
 * boisson ou du plat), `prix_unitaire` (francs ENTIERS, figé au poste),
 * `quantite`.
 *
 * ## Par `VenteService::enregistrer()`, et lui seul
 *
 * Avec l'UUID du poste (idempotence vérifiée dans sa transaction), la date
 * MÉTIER `cloture_le` (pièce VTE, `created_at`, sorties de stock, année du
 * numéro `V-AAAA-NNNNN`), et deux options réservées à la synchronisation :
 *
 * - **prix imposés** — le prix du POSTE fait foi (décision PO) : c'est celui
 *   annoncé et encaissé. Le prix du catalogue serveur est gardé à côté
 *   (`lignes_vente.prix_catalogue`) ; tout écart est SIGNALÉ
 *   (`anomalies_synchronisation`, `ecart_prix`) et rendu en `ecart_prix`.
 *   Jamais corrigé en silence.
 * - **sans bon de cuisine** — les lignes M4 sortent les denrées (RG-05) sans
 *   créer ni transmettre de commande de cuisine : l'assiette est servie
 *   depuis longtemps, un bon imprimé à la synchronisation n'aurait aucun sens.
 *
 * ## Rupture de stock : forcée et SIGNALÉE, jamais un rejet
 *
 * La vente a déjà eu lieu ; la rejeter ferait disparaître l'argent des livres.
 * Une première tentative normale (sous point de sauvegarde) révèle la
 * rupture ; la vente est alors réécrite avec `validation_rupture` (trace
 * `rupture_stock_forcee` par article dans `journal_audit`, RG-06) et
 * l'anomalie `vente_en_rupture` est enregistrée.
 *
 * ## Plat sans composition : vendu, non déduit, SIGNALÉ
 *
 * Décision du Product Owner du 15/10/2026 : une fiche technique vide (ou un
 * plat sans lien direct au stock) ne fait PAS rejeter une vente synchronisée
 * — elle a été servie et encaissée. `VenteService` (chemin
 * `sansBonDeCuisine`) écarte la ligne de la déduction ; l'anomalie
 * `plat_sans_composition` est enregistrée par plat et rendue au poste dans
 * `anomalies`. En ligne (PWA), la même vente reste refusée.
 *
 * ## La session de caisse : citée, jamais devinée
 *
 * `session_encaissement_id` est traduit par les correspondances. Le poste
 * pousse dans l'ordre de sa file : ouverture → ventes → clôture. Une session
 * inconnue du serveur (ouverture refusée, ou pas encore poussée) ou déjà
 * close ne fait PAS rejeter la vente — l'argent a été encaissé — : la vente
 * est écrite (sans session si elle est inconnue) et l'écart est signalé
 * (`vente_session_inconnue` / `vente_session_cloturee`), pour que le
 * théorique du tiroir soit repris à la main.
 *
 * ## Note de chambre (`sur_sejour`) — acceptée depuis le lot F5 (17/10/2026)
 *
 * Jusqu'au 17/10/2026 : refusée (`sync.ventes.note_chambre_hors_perimetre`),
 * parce qu'en ligne `PosHeberges::cloturerEtFacturer` écrit la vente ET la
 * facture du séjour dans la même transaction. Décision du PO du 17/10/2026
 * (« les deux modules POS vente et POS hébergés … en synchronisation ») :
 * sur le poste, la consommation portée en note et la facture de DÉPART sont
 * deux gestes distincts ; la vente monte seule, rattachée à SA réservation
 * (`reservation_id`, obligatoire et connue du serveur), en `note_chambre`
 * (non encaissée, aucune session) ; la créance `4111` existe au serveur dès
 * la consommation, et la facture du départ la portera (lot F5c). Le client et
 * l'unité sont ceux de la réservation, jamais ceux du payload.
 *
 * ## Modification : refusée — une vente s'ANNULE en ligne (RG-02).
 */
final class GestionnaireVentes extends GestionnaireDocumentAbstrait
{
    private const TYPE_COMPTANT = 'comptant';

    /** La vente portée sur la note de chambre (lot F5). */
    private const TYPE_SEJOUR = 'sur_sejour';

    public function __construct(
        private readonly VenteService $ventes,
        ResolveurCorrespondances $correspondances,
        SignalementAnomalies $anomalies,
        private readonly DocumentsDesAutresPostes $autresPostes,
    ) {
        parent::__construct($correspondances, $anomalies);
    }

    /**
     * Lot F6 (17/10/2026) : l'ANNULATION seulement (`statut: annulee` +
     * `motif`), par `VenteService::annuler` — contre-passation de la pièce et
     * retour des boissons au stock, comme à la PWA. Une vente d'un autre
     * poste ne s'annule que par l'administration ou le comptable (Q3). Tout
     * autre champ : refusé.
     */
    public function accepteModification(): bool
    {
        return true;
    }

    public function modifier(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $statut = $payload['statut'] ?? null;
        $motif = trim((string) ($payload['motif'] ?? ''));
        unset($payload['statut'], $payload['motif']);

        if ($statut !== 'annulee' || $payload !== []) {
            throw new RuntimeException(__('sync.modification_non_synchronisable'));
        }

        $vente = Vente::query()->findOrFail($entiteId);

        // Rejeu : déjà annulée — rendue, jamais contre-passée deux fois.
        if (! $vente->estAnnulee()) {
            $this->autresPostes->verifierAnnulation('ventes', $entiteId, $contexte);
            $this->ventes->annuler($vente, $motif === '' ? __('sync.factures.motif_absent') : $motif);
        }

        return $this->resultat($entiteId);
    }

    public function table(): string
    {
        return 'ventes';
    }

    public function module(): string
    {
        return PosComptant::MODULE;
    }

    /**
     * M5 toujours ; M4 EN PLUS dès qu'une ligne est un plat — la règle de
     * `PosComptant::encaissementReel` (PA-65) : un barman ne doit pas obtenir
     * par la synchronisation ce que l'écran M4 lui refuse.
     */
    public function modulesRequis(array $payload): array
    {
        $lignes = is_array($payload['lignes'] ?? null) ? $payload['lignes'] : [];

        foreach ($lignes as $ligne) {
            if (is_array($ligne) && ($ligne['module_source'] ?? null) === 'M4') {
                return [PosComptant::MODULE, 'M4'];
            }
        }

        return [PosComptant::MODULE];
    }

    public function serviceDomaine(): string
    {
        return VenteService::class;
    }

    public function champDateDocument(): ?string
    {
        return 'cloture_le';
    }

    public function creer(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $surSejour = ($payload['type_vente'] ?? null) === self::TYPE_SEJOUR;

        // Les deux moitiés vont ensemble : une note de chambre au comptoir,
        // ou un séjour encaissé, est un document incohérent.
        if ($surSejour !== (($payload['mode_paiement'] ?? null) === 'note_chambre')) {
            throw new RuntimeException(__('sync.ventes.note_chambre_incoherente'));
        }

        $reservation = null;

        if ($surSejour) {
            $reservationId = is_string($payload['reservation_id'] ?? null)
                ? $this->resoudre('reservations', $payload['reservation_id'])
                : null;
            $reservation = $reservationId === null ? null : Reservation::with('unite')->find($reservationId);

            if ($reservation === null) {
                throw new RuntimeException(__('sync.ventes.reservation_inconnue'));
            }
        }

        $donnees = $this->validerForme($payload, [
            'type_vente' => ['required', 'in:' . self::TYPE_COMPTANT . ',' . self::TYPE_SEJOUR],
            'mode_paiement' => ['required', 'string'],
            'session_encaissement_id' => ['nullable', 'string'],
            'cloture_le' => ['required', 'date'],
            'point_vente' => ['nullable', 'string', 'max:50'],
            'table' => ['nullable', 'string', 'max:255'],
            'table_id' => ['nullable', 'string', 'max:255'],
            'client_nom' => ['nullable', 'string', 'max:255'],
            'montant_cloture' => ['nullable', 'integer', 'min:0'],
            'lignes' => ['required', 'array', 'min:1'],
            'lignes.*.module_source' => ['required', 'string'],
            'lignes.*.code_article' => ['required', 'string'],
            'lignes.*.prix_unitaire' => ['required', 'integer', 'min:0'],
            'lignes.*.quantite' => ['required', 'integer'],
        ], [
            'lignes.required' => __('ventes.panier_vide'),
            'lignes.min' => __('ventes.panier_vide'),
        ]);

        $lignes = [];
        $total = 0;

        foreach (array_values($donnees['lignes']) as $ligne) {
            $module = (string) $ligne['module_source'];
            $lignes[] = [
                'module' => $module,
                // Une carte ou un plat créé hors connexion et FUSIONNÉ côté
                // serveur est retrouvé sous son identifiant serveur.
                'reference_id' => $this->resoudre($module === 'M4' ? 'plats' : 'cartes_boisson', (string) $ligne['code_article']),
                'quantite' => (int) $ligne['quantite'],
                'prix_unitaire' => $this->francs((int) $ligne['prix_unitaire']),
            ];
            $total += (int) $ligne['prix_unitaire'] * (int) $ligne['quantite'];
        }

        // Le total figé au poste doit être celui de ses lignes : un document
        // incohérent avec lui-même ne s'enregistre pas — on ne saurait pas
        // lequel des deux chiffres a été encaissé.
        if (isset($donnees['montant_cloture']) && (int) $donnees['montant_cloture'] !== $total) {
            throw new RuntimeException(__('sync.ventes.total_incoherent', [
                'annonce' => (string) $donnees['montant_cloture'],
                'lignes' => (string) $total,
            ]));
        }

        $date = $this->dateDuDocument($donnees['cloture_le'], $contexte);
        // Une note de chambre n'entre dans aucun tiroir : jamais de session.
        [$sessionId, $anomalieSession] = $surSejour
            ? [null, null]
            : $this->session($donnees['session_encaissement_id'] ?? null);

        $vente = [
            'id' => $entiteId,
            'session_id' => $sessionId,
            'point_vente' => blank($donnees['point_vente'] ?? null) ? PosComptant::POSTE_COMPTOIR : (string) $donnees['point_vente'],
            'client_id' => $reservation?->client_id,
            'reservation_id' => $reservation?->id,
            'client_mention' => $donnees['client_nom'] ?? null,
            'table' => $reservation !== null ? $reservation->unite?->numero : ($donnees['table'] ?? null),
            'table_id' => $donnees['table_id'] ?? null,
            'mode_paiement' => (string) $donnees['mode_paiement'],
            'utilisateur_id' => $contexte->utilisateur->id,
            'validation_rupture' => false,
            'lignes' => $lignes,
        ];

        $rupture = null;

        try {
            // Point de sauvegarde : une rupture annule cette tentative SEULE
            // (numéro, pièce, lignes), pas l'opération.
            DB::transaction(fn () => $this->ventes->enregistrer($vente, $date, prixImposes: true, sansBonDeCuisine: true));
        } catch (RuptureStockException $e) {
            $rupture = $e;
            $this->ventes->enregistrer([...$vente, 'validation_rupture' => true], $date, prixImposes: true, sansBonDeCuisine: true);
        }

        if ($rupture !== null) {
            $this->anomalies->signaler($contexte, $this->table(), $entiteId, AnomalieSynchronisation::VENTE_EN_RUPTURE, details: [
                'article_id' => $rupture->articleId,
                'stock_disponible' => $rupture->stockDisponible,
                'motif' => $rupture->getMessage(),
            ]);
        }

        if ($anomalieSession !== null) {
            $this->anomalies->signaler($contexte, $this->table(), $entiteId, $anomalieSession, details: [
                'session_citee' => $donnees['session_encaissement_id'] ?? null,
            ]);
        }

        // Plat sans composition (décision PO du 15/10/2026) : la vente est
        // écrite, la ligne n'a rien sorti du stock — `VenteService` l'a noté
        // dans `stock_non_impacte` ; on le SIGNALE, un plat par anomalie.
        foreach ($this->platsSansComposition($entiteId) as $ligne) {
            $this->anomalies->signaler(
                $contexte,
                $this->table(),
                $entiteId,
                AnomalieSynchronisation::PLAT_SANS_COMPOSITION,
                reference: (string) $ligne['plat_id'],
                details: [
                    'plat' => $ligne['ligne'] ?? null,
                    'quantite' => $ligne['quantite'] ?? null,
                    'motif' => $ligne['motif'] ?? null,
                ],
            );
        }

        foreach ($this->ecartsDePrix($entiteId) as $ecart) {
            $this->anomalies->signaler(
                $contexte,
                $this->table(),
                $entiteId,
                AnomalieSynchronisation::ECART_PRIX,
                reference: $ecart['code_article'],
                valeurPoste: $ecart['prix_poste'],
                valeurServeur: $ecart['prix_catalogue'],
            );
        }

        return $this->resultat($entiteId);
    }

    protected function resultat(string $entiteId): EcritureSynchronisee
    {
        $vente = Vente::query()->findOrFail($entiteId);
        $ecarts = $this->ecartsDePrix($entiteId);
        $anomalies = array_values(array_unique(array_column($this->anomalies->duDocument($this->table(), $entiteId), 'type')));

        return new EcritureSynchronisee($entiteId, complements: [
            'numero' => $vente->numero,
            'montant_total' => (string) $vente->montant_total,
            ...($ecarts !== [] ? ['ecart_prix' => $ecarts] : []),
            ...($anomalies !== [] ? ['anomalies' => $anomalies] : []),
        ]);
    }

    /**
     * Les lignes de plats écartées de la déduction faute de composition.
     *
     * @return list<array<string, mixed>>
     */
    private function platsSansComposition(string $venteId): array
    {
        $nonImpacte = Vente::query()->findOrFail($venteId)->stock_non_impacte ?? [];

        return array_values(array_filter(
            $nonImpacte,
            static fn (mixed $ligne): bool => is_array($ligne)
                && ($ligne['cause'] ?? null) === VenteService::CAUSE_PLAT_SANS_COMPOSITION,
        ));
    }

    /**
     * Les lignes dont le prix du poste diffère du catalogue serveur.
     *
     * @return list<array{code_article: string, libelle: string, prix_poste: string, prix_catalogue: string, ecart: string}>
     */
    private function ecartsDePrix(string $venteId): array
    {
        return LigneVente::query()
            ->where('vente_id', $venteId)
            ->whereNotNull('prix_catalogue')
            ->whereColumn('prix_catalogue', '!=', 'prix_unitaire')
            ->orderBy('code')
            ->get()
            ->map(static fn (LigneVente $l): array => [
                'code_article' => (string) $l->code,
                'libelle' => (string) $l->nom,
                'prix_poste' => (string) $l->prix_unitaire,
                'prix_catalogue' => (string) $l->prix_catalogue,
                'ecart' => bcsub((string) $l->prix_unitaire, (string) $l->prix_catalogue, 2),
            ])
            ->all();
    }

    /**
     * La session citée, traduite — et l'anomalie à signaler s'il y a lieu.
     *
     * @return array{0: string|null, 1: string|null}
     */
    private function session(mixed $citee): array
    {
        if (! is_string($citee) || $citee === '') {
            return [null, AnomalieSynchronisation::VENTE_SESSION_INCONNUE];
        }

        $session = SessionCaisse::query()->find($this->correspondances->resoudre('sessions_caisse', $citee));

        if ($session === null) {
            return [null, AnomalieSynchronisation::VENTE_SESSION_INCONNUE];
        }

        return [$session->id, $session->date_cloture !== null ? AnomalieSynchronisation::VENTE_SESSION_CLOTUREE : null];
    }
}
