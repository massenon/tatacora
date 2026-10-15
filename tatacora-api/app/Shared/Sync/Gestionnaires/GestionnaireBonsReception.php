<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Domain\Achats\Http\Requests\EnregistrerReceptionRequest;
use App\Domain\Achats\Models\BonReception;
use App\Domain\Achats\Models\CommandeAchat;
use App\Domain\Achats\Services\ReceptionService;
use App\Shared\Sync\Models\AnomalieSynchronisation;
use App\Shared\Sync\Services\ResolveurCorrespondances;
use App\Shared\Sync\Services\SignalementAnomalies;
use App\Shared\Sync\Support\ContexteSynchronisation;
use App\Shared\Sync\Support\EcritureSynchronisee;
use RuntimeException;

/**
 * Bons de réception enregistrés hors connexion (M7, niveau C — celui de
 * `POST /achats/commandes/{commande}/receptions`) — lot S3, décision du
 * Product Owner du 15/10/2026.
 *
 * ## Le payload : `bons_reception_local` + `lignes_bon_reception_local`
 *
 * `commande_id`, `date_reception`, `point_stockage_id`, `conformite` (le
 * verdict du POSTE, informatif) et `lignes[]` : `article_id`,
 * `quantite_centiemes` (entier : 1250 = 12,50). Identifiants traduits par les
 * correspondances (commande, point, articles), quantités converties en
 * décimaux, puis RÈGLES ET PHRASES d'`EnregistrerReceptionRequest`.
 *
 * ## Par `ReceptionService::receptionner()`, et lui seul
 *
 * Avec l'UUID du poste (idempotence vérifiée avant tout contrôle, puis dans
 * la transaction), la date de réception du document, et les entrées de stock
 * datées de cette date MÉTIER. Comme en ligne, les entrées ne sont PAS
 * valorisées (le service ne passe aucun coût — le CMP n'est pas touché par ce
 * chemin, aujourd'hui pas plus qu'en ligne).
 *
 * ## La conformité est RECALCULÉE par le serveur (RG-10)
 *
 * Sur SA tolérance (`tolerance_reception_pct`) et les quantités commandées
 * de SA commande. Tolérance non paramétrée → refus explicite du service
 * (`achats.tolerance_absente`) : une tolérance devinée accepterait ou
 * refuserait des livraisons sur un critère arbitraire. Le verdict du poste
 * n'est jamais écrit : s'il diffère, l'écart est SIGNALÉ
 * (`ecart_conformite_reception`) et les deux verdicts sont rendus.
 *
 * ## Ordre : la commande avant son bon
 *
 * Une commande inconnue du serveur (pas encore poussée, ou refusée) refuse le
 * bon avec un motif explicite — il n'existe aucun bon sans commande au schéma.
 *
 * ## Modification : refusée — un bon se corrige par un autre mouvement.
 */
final class GestionnaireBonsReception extends GestionnaireDocumentAbstrait
{
    public function __construct(
        private readonly ReceptionService $receptions,
        ResolveurCorrespondances $correspondances,
        SignalementAnomalies $anomalies,
    ) {
        parent::__construct($correspondances, $anomalies);
    }

    public function table(): string
    {
        return 'bons_reception';
    }

    public function module(): string
    {
        return 'M7';
    }

    public function serviceDomaine(): string
    {
        return ReceptionService::class;
    }

    public function champDateDocument(): ?string
    {
        return 'date_reception';
    }

    public function creer(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $forme = $this->validerForme($payload, [
            'commande_id' => ['required', 'string'],
            'conformite' => ['nullable', 'in:totale,partielle,non_conforme'],
            'lignes' => ['required', 'array', 'min:1'],
            'lignes.*.quantite_centiemes' => ['required', 'integer'],
        ], [
            'lignes.required' => __('achats.validation.reception_lignes_obligatoires'),
            'lignes.min' => __('achats.validation.reception_lignes_obligatoires'),
        ]);

        $commande = CommandeAchat::query()->find($this->resoudre('commandes_achat', (string) $forme['commande_id']));

        if ($commande === null) {
            throw new RuntimeException(__('sync.receptions.commande_inconnue'));
        }

        $lignes = [];

        foreach (array_values($forme['lignes']) as $rang => $ligne) {
            $brute = (array) array_values($payload['lignes'])[$rang];

            $lignes[] = [
                'article_id' => $this->resoudre('articles', $brute['article_id'] ?? null),
                'quantite_recue' => $this->centiemes((int) $ligne['quantite_centiemes']),
            ];
        }

        // Le verdict et l'identifiant du poste ne sont pas des champs de la
        // route (`conformite` y est INTERDITE) : ils sont lus à part.
        unset($payload['conformite'], $payload['commande_id'], $payload['utilisateur_id'], $payload['id']);

        $donnees = $this->valider([
            ...$payload,
            'point_stockage_id' => $this->resoudre('points_stockage', $payload['point_stockage_id'] ?? null),
            'lignes' => $lignes,
        ], $this->reglesDeLApi(EnregistrerReceptionRequest::class), EnregistrerReceptionRequest::class);

        $quantites = [];

        foreach ($donnees['lignes'] as $ligne) {
            $quantites[(string) $ligne['article_id']] = (string) $ligne['quantite_recue'];
        }

        $date = $this->dateDuDocument($donnees['date_reception'] ?? null, $contexte);

        $bon = $this->receptions->receptionner(
            $commande,
            $quantites,
            (string) $donnees['point_stockage_id'],
            $date->toDateString(),
            $entiteId,
            $date,
        );

        $verdictPoste = $forme['conformite'] ?? null;

        if ($verdictPoste !== null && $verdictPoste !== $bon->conformite) {
            $this->anomalies->signaler(
                $contexte,
                $this->table(),
                $entiteId,
                AnomalieSynchronisation::ECART_CONFORMITE_RECEPTION,
                details: ['conformite_poste' => $verdictPoste, 'conformite_serveur' => $bon->conformite],
            );
        }

        return $this->resultat($entiteId);
    }

    protected function resultat(string $entiteId): EcritureSynchronisee
    {
        $bon = BonReception::query()->findOrFail($entiteId);
        $ecart = AnomalieSynchronisation::query()
            ->where('table_concernee', $this->table())
            ->where('entite_id', $entiteId)
            ->where('type', AnomalieSynchronisation::ECART_CONFORMITE_RECEPTION)
            ->first();

        return new EcritureSynchronisee($entiteId, complements: [
            'conformite' => $bon->conformite,
            ...($ecart !== null ? ['conformite_poste' => $ecart->details['conformite_poste'] ?? null] : []),
            'statut_commande' => (string) CommandeAchat::query()->whereKey($bon->commande_id)->value('statut'),
        ]);
    }
}
