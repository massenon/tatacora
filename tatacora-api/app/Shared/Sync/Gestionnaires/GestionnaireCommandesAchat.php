<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Domain\Achats\Http\Requests\CreerCommandeAchatRequest;
use App\Domain\Achats\Models\CommandeAchat;
use App\Domain\Achats\Services\CommandeAchatService;
use App\Domain\Achats\Services\ReceptionService;
use App\Shared\Sync\Services\ResolveurCorrespondances;
use App\Shared\Sync\Services\SignalementAnomalies;
use App\Shared\Sync\Support\ContexteSynchronisation;
use App\Shared\Sync\Support\EcritureSynchronisee;
use RuntimeException;

/**
 * Commandes d'achat émises hors connexion (M7, niveau C — celui de
 * `POST /achats/commandes`) — lot S3, décision du Product Owner du
 * 15/10/2026 (les commandes d'achat SONT dans le périmètre).
 *
 * ## Le payload : `commandes_achat_local` + `lignes_commande_achat_local`
 *
 * `fournisseur_id`, `date_commande`, `statut`, et `lignes[]` : `article_id`,
 * `quantite_centiemes` (entier : 1250 = 12,50) et `prix_unitaire_centimes`.
 * Convertis en décimaux à deux chiffres, puis validés par les RÈGLES ET
 * PHRASES de `CreerCommandeAchatRequest` — aucune troisième liste. Les
 * identifiants cités (fournisseur, articles) passent d'abord par les
 * correspondances : un fournisseur créé hors connexion et fusionné côté
 * serveur est retrouvé sous son UUID serveur.
 *
 * ## Le statut : seuls les statuts SAISISSABLES montent
 *
 * Sur le poste, une commande devient « receptionnee » quand le poste y
 * enregistre un bon. Au serveur, ce statut n'est PAS saisissable : il est
 * produit par `ReceptionService` quand le bon synchronisé (poussé APRÈS la
 * commande) génère ses entrées de stock. Un statut dérivé du poste
 * (`receptionnee_partiellement`, `receptionnee`, `cloturee`) monte donc comme
 * `envoyee` — une commande reçue a forcément été envoyée — et le bon fera le
 * reste. L'accepter tel quel afficherait « reçue » une commande dont aucune
 * marchandise n'est entrée au stock serveur (PA-59/60/61).
 *
 * ## Auteur : l'utilisateur du JETON
 *
 * `CommandeAchatService` pose `utilisateur_id` depuis `auth()` — la session
 * de synchronisation est authentifiée par le jeton du poste. Un
 * `utilisateur_id` du payload est ignoré (la route le refuse : RG-15).
 *
 * ## Modification : refusée
 *
 * `CommandeAchatService` n'offre ni modification (le rapprochement à trois
 * voies deviendrait faux rétroactivement) ni annulation (l'enum de
 * `commandes_achat.statut` ne porte pas `annulee`). La synchronisation
 * n'offre pas plus que l'API.
 */
final class GestionnaireCommandesAchat extends GestionnaireDocumentAbstrait
{
    /** Les statuts que le poste dérive de ses propres réceptions. */
    private const STATUTS_DERIVES = ['receptionnee_partiellement', 'receptionnee', 'cloturee'];

    public function __construct(
        private readonly CommandeAchatService $commandes,
        ResolveurCorrespondances $correspondances,
        SignalementAnomalies $anomalies,
    ) {
        parent::__construct($correspondances, $anomalies);
    }

    public function table(): string
    {
        return 'commandes_achat';
    }

    public function module(): string
    {
        return 'M7';
    }

    public function serviceDomaine(): string
    {
        return CommandeAchatService::class;
    }

    public function champDateDocument(): ?string
    {
        return 'date_commande';
    }

    /**
     * Lot F6 (17/10/2026) : le STATUT seul, par son service — `envoyee`
     * (`CommandeAchatService::envoyer`, depuis le brouillon) et `cloturee`
     * (`ReceptionService::cloturer`, RG-10 : réception dans la tolérance).
     * Un statut déjà atteint (rejeu, ou geste d'un autre poste) est rendu tel
     * quel ; la réception, elle, passe par `bons_reception`.
     */
    public function accepteModification(): bool
    {
        return true;
    }

    public function modifier(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $statut = $payload['statut'] ?? null;
        unset($payload['statut']);

        if (! in_array($statut, ['envoyee', 'cloturee'], true) || $payload !== []) {
            throw new RuntimeException(__('sync.commandes.statut_inconnu'));
        }

        $commande = CommandeAchat::query()->findOrFail($entiteId);

        if ($commande->statut !== $statut) {
            match ($statut) {
                'envoyee' => $commande->statut === 'brouillon'
                    ? $this->commandes->envoyer($commande)
                    : null,
                'cloturee' => app(ReceptionService::class)->cloturer($commande),
            };
        }

        return $this->resultat($entiteId);
    }

    public function creer(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $forme = $this->validerForme($payload, [
            'lignes' => ['required', 'array', 'min:1'],
            'lignes.*.quantite_centiemes' => ['required', 'integer'],
            'lignes.*.prix_unitaire_centimes' => ['required', 'integer'],
        ], [
            'lignes.required' => __('achats.validation.lignes_obligatoires'),
            'lignes.min' => __('achats.validation.lignes_obligatoires'),
        ]);

        // L'auteur vient du jeton ; l'identifiant, de l'opération.
        unset($payload['utilisateur_id'], $payload['id']);

        $lignes = [];

        foreach (array_values($forme['lignes']) as $rang => $ligne) {
            $brute = (array) array_values($payload['lignes'])[$rang];
            unset($brute['quantite_centiemes'], $brute['prix_unitaire_centimes'], $brute['article_libelle'], $brute['unite_mesure'], $brute['rang']);

            $lignes[] = [
                ...$brute,
                'article_id' => $this->resoudre('articles', $brute['article_id'] ?? null),
                'quantite_commandee' => $this->centiemes((int) $ligne['quantite_centiemes']),
                'prix_unitaire' => $this->centiemes((int) $ligne['prix_unitaire_centimes']),
            ];
        }

        $statut = $payload['statut'] ?? null;

        $donnees = $this->valider([
            ...$payload,
            'fournisseur_id' => $this->resoudre('fournisseurs', $payload['fournisseur_id'] ?? null),
            ...(in_array($statut, self::STATUTS_DERIVES, true) ? ['statut' => 'envoyee'] : []),
            'lignes' => $lignes,
        ], $this->reglesDeLApi(CreerCommandeAchatRequest::class), CreerCommandeAchatRequest::class);

        $this->commandes->creer([
            'id' => $entiteId,
            'fournisseur_id' => (string) $donnees['fournisseur_id'],
            'date_commande' => $this->dateDuDocument($donnees['date_commande'], $contexte)->toDateString(),
            ...(isset($donnees['statut']) ? ['statut' => (string) $donnees['statut']] : []),
            'lignes' => array_map(static fn (array $l): array => [
                'article_id' => (string) $l['article_id'],
                'quantite_commandee' => (string) $l['quantite_commandee'],
                'prix_unitaire' => (string) $l['prix_unitaire'],
            ], array_values($donnees['lignes'])),
        ]);

        return $this->resultat($entiteId);
    }

    protected function resultat(string $entiteId): EcritureSynchronisee
    {
        $commande = CommandeAchat::query()->findOrFail($entiteId);

        return new EcritureSynchronisee($entiteId, complements: [
            'statut_commande' => $commande->statut,
            'montant_total' => (string) $commande->montant_total,
        ]);
    }
}
