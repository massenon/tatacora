<?php

declare(strict_types=1);

namespace App\Domain\Achats\Http\Controllers;

use App\Domain\Achats\Http\Requests\CreerCommandeAchatRequest;
use App\Domain\Achats\Http\Requests\EnregistrerReceptionRequest;
use App\Domain\Achats\Http\Requests\FiltrerCommandesRequest;
use App\Domain\Achats\Http\Requests\FiltrerReceptionsRequest;
use App\Domain\Achats\Http\Resources\BonReceptionResource;
use App\Domain\Achats\Http\Resources\CommandeAchatDetailResource;
use App\Domain\Achats\Http\Resources\CommandeAchatResource;
use App\Domain\Achats\Http\Resources\RapprochementResource;
use App\Domain\Achats\Models\BonReception;
use App\Domain\Achats\Models\CommandeAchat;
use App\Domain\Achats\Services\CommandeAchatService;
use App\Domain\Achats\Services\ControleTroisVoiesService;
use App\Domain\Achats\Services\ReceptionService;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use RuntimeException;

/**
 * Cycle d'approvisionnement — M7 : commandes, réceptions, rapprochement.
 *
 * @see EF-M7-02 Émission de commandes d'achat rattachées à un ou plusieurs articles
 * @see EF-M7-03 Réception avec bon de réception et contrôle de conformité
 * @see EF-M7-04 Rapprochement commande / réception / facture (trois voies)
 * @see RG-10 Clôture sous tolérance paramétrable
 *
 * Alimente `prototype_v2/pages/m7-approvisionnement.html`.
 *
 * ## Simple orchestrateur (`06_DEVELOPMENT_STANDARDS.md` §2.2)
 *
 * Aucune règle de gestion n'est écrite ici. **Toute** réception passe par
 * `ReceptionService` : il est l'unique endroit où le verdict RG-10 est rendu et
 * où l'entrée de stock est générée. Une insertion directe dans `bons_reception`
 * contournerait les deux — la marchandise n'entrerait jamais en stock, et
 * quelqu'un la saisirait à la main, ce que `05_MODULE_SPECIFICATIONS.md` §M7
 * interdit explicitement (« jamais de double-saisie manuelle du stock après
 * réception »).
 *
 * ## Trois choses que l'écran demande et que ce contrôleur REFUSE de rendre
 *
 * **1. « Dettes fournisseurs » — l'onglet entier, et les deux KPI qui vont
 * avec.** Le prototype affiche « Fournisseurs à payer », « Total dû », un
 * montant réglé par commande et une ancienneté de dette. **Aucune table du
 * schéma ne porte de facture ni de règlement fournisseur** : `factures` est la
 * facturation CLIENT (M2), de nature opposée, et il n'existe ni
 * `factures_fournisseur`, ni `paiements` (PA-21). Rendre `0` afficherait
 * « aucune dette » sous un écran qui n'a jamais rien consulté — la doctrine
 * demande de dire « non consulté », jamais d'afficher zéro. Il n'y a donc
 * aucune route : la donnée manquante se voit, au lieu de se déguiser en bonne
 * nouvelle. EF-M7-06 (« Suivi des échéances de paiement fournisseurs ») est
 * **non implémentable en l'état du schéma**, et c'est signalé à l'Architecte.
 *
 * **2. Les montants facturés du rapprochement.** Voir
 * `RapprochementResource` : le service les accepte mais ne les compare à rien,
 * et les exposer laisserait un écran annoncer un contrôle à trois voies qui
 * n'a pas eu lieu.
 *
 * **3. Les délais de livraison d'EF-M7-05.** `commandes_achat` ne porte
 * aucune date de livraison prévue ni constatée — seulement `date_commande`. Un
 * « délai » calculé depuis la date du bon de réception mesurerait la date de
 * SAISIE, pas la date de livraison, et un magasinier qui enregistre ses bons le
 * lundi ferait apparaître tous ses fournisseurs en retard. Seule la moitié
 * qualitative d'EF-M7-05 est servie : la colonne `evaluation` du référentiel.
 *
 * ## Aucune suppression, aucune modification de commande
 *
 * `commandes_achat`, `lignes_commande_achat` et `bons_reception` sont des
 * tables transactionnelles. Aucun `DELETE` ni `PUT` n'est routé : le verbe
 * absent est la seule preuve solide qu'il n'existe pas.
 *
 * Manque de schéma assumé, de la même famille que PA-50 : l'enum
 * `commandes_achat.statut` **ne porte pas de valeur `annulee`**. Une commande
 * créée par erreur ne peut donc être ni supprimée, ni annulée, ni corrigée —
 * elle restera au registre en `brouillon` ou `envoyee`. Inventer un statut
 * exigerait de modifier une contrainte d'intégrité, ce qui ne se décide pas
 * seul.
 */
class AchatController
{
    public function __construct(
        private readonly CommandeAchatService $commandes,
        private readonly ReceptionService $receptions,
        private readonly ControleTroisVoiesService $rapprochement,
    ) {
    }

    /**
     * Registre des commandes d'achat — l'onglet « Commandes ».
     *
     * Les compteurs de la bande de KPI (« Commandes en attente », « Réceptions
     * partielles ») se lisent en interrogeant cette route par statut et en
     * relevant son `meta.total` — jamais en additionnant ce qu'une page montre.
     * C'est pourquoi aucun total n'est rendu au-dessus des lignes : un
     * compteur calculé sur tout, posé sur une page, afficherait deux vérités
     * sur le même écran.
     */
    public function commandes(FiltrerCommandesRequest $request): AnonymousResourceCollection
    {
        $requete = CommandeAchat::query()
            // `lignes` est chargée parce que le montant total s'en somme : sans
            // elle, la liste ferait une requête par commande pour un chiffre
            // qu'elle affiche sur chaque ligne.
            ->with(['fournisseur:id,raison_sociale', 'lignes'])
            ->when(
                $request->filtre('statut'),
                fn (Builder $q, string $statut): Builder => $q->where('statut', $statut),
            )
            ->when(
                $request->filtre('fournisseur_id'),
                fn (Builder $q, string $id): Builder => $q->where('fournisseur_id', $id),
            )
            ->when(
                $request->filtre('recherche'),
                // La recherche du prototype porte sur le fournisseur : elle
                // traverse donc la relation, elle ne lit pas un libellé recopié
                // sur la commande — il n'en existe pas, et c'est voulu.
                fn (Builder $q, string $terme): Builder => $q->whereHas(
                    'fournisseur',
                    fn (Builder $f): Builder => $f->where('raison_sociale', 'like', '%' . $terme . '%'),
                ),
            )
            // La plus récente d'abord — c'est ce qu'on vient réceptionner.
            ->orderByDesc('date_commande')
            ->orderByDesc('id');

        return CommandeAchatResource::collection($requete->paginate($request->parPage()));
    }

    /**
     * Détail d'une commande : ses lignes, ce qui en a déjà été reçu, et ses
     * bons de réception.
     *
     * C'est ce que consomme la modale « Réceptionner » — sans le « déjà reçu »,
     * une seconde réception repartirait de la quantité commandée entière et
     * ferait entrer la marchandise deux fois en stock.
     */
    public function commande(CommandeAchat $commande): CommandeAchatDetailResource
    {
        return new CommandeAchatDetailResource($this->detail($commande));
    }

    /**
     * Émission d'une commande d'achat — EF-M7-02, UC-29.
     */
    public function creerCommande(CreerCommandeAchatRequest $request): JsonResponse
    {
        $commande = $this->commandes->creer($request->donnees());

        return (new CommandeAchatDetailResource($this->detail($commande)))
            ->response()
            ->setStatusCode(201);
    }

    /**
     * Passage d'un brouillon à l'état émis — EF-M7-02.
     *
     * `PATCH` et non `PUT` : c'est une transition d'état, pas un remplacement
     * de la commande, qui reste par ailleurs immuable.
     */
    public function envoyerCommande(CommandeAchat $commande): CommandeAchatDetailResource|JsonResponse
    {
        try {
            $commande = $this->commandes->envoyer($commande);
        } catch (RuntimeException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }

        return new CommandeAchatDetailResource($this->detail($commande));
    }

    /**
     * Enregistrement d'une réception — EF-M7-03, RG-10.
     *
     * Le service génère les entrées de stock, rend le verdict de conformité et
     * fait avancer le statut de la commande, le tout dans une transaction.
     *
     * **422 quand la tolérance n'est pas configurée**, avec le message qui le
     * dit : aucune conformité ne peut être évaluée tant qu'un Administrateur
     * ne l'a pas renseignée. Un défaut plausible (« 2 %, ça ira ») deviendrait
     * la règle de production et personne ne la rouvrirait — même discipline
     * que le taux d'IS (PA-19).
     */
    public function receptionner(
        EnregistrerReceptionRequest $request,
        CommandeAchat $commande,
    ): JsonResponse {
        /** @var array<string, mixed> $valide */
        $valide = $request->validated();
        $date = isset($valide['date_reception']) && is_string($valide['date_reception'])
            ? $valide['date_reception']
            : null;

        try {
            $bon = $this->receptions->receptionner(
                commande: $commande,
                quantitesRecues: $request->quantitesRecues(),
                pointStockageId: (string) $valide['point_stockage_id'],
                dateReception: $date,
            );
        } catch (RuntimeException $e) {
            // 422 et non 500 : commande déjà clôturée, tolérance absente,
            // point inconnu — trois refus métier que le client doit pouvoir
            // afficher tels quels, pas une panne du serveur.
            return response()->json(['message' => $e->getMessage()], 422);
        }

        return (new BonReceptionResource($bon->load('commande.fournisseur')))
            ->response()
            ->setStatusCode(201);
    }

    /**
     * Clôture d'une commande — RG-10.
     *
     * Le refus est le livrable : une commande dont la réception n'est pas
     * conforme à la tolérance ne se clôture pas. La forcer ferait perdre la
     * créance sur le fournisseur, sans trace.
     */
    public function cloturerCommande(CommandeAchat $commande): CommandeAchatDetailResource|JsonResponse
    {
        try {
            $commande = $this->receptions->cloturer($commande);
        } catch (RuntimeException $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        }

        return new CommandeAchatDetailResource($this->detail($commande));
    }

    /**
     * Registre des bons de réception — l'onglet « Réceptions ».
     */
    public function receptions(FiltrerReceptionsRequest $request): AnonymousResourceCollection
    {
        $requete = BonReception::query()
            ->with(['commande.fournisseur:id,raison_sociale'])
            ->when(
                $request->filtre('commande_id'),
                fn (Builder $q, string $id): Builder => $q->where('commande_id', $id),
            )
            ->when(
                $request->filtre('conformite'),
                fn (Builder $q, string $conformite): Builder => $q->where('conformite', $conformite),
            )
            ->orderByDesc('date_reception')
            ->orderByDesc('id');

        return BonReceptionResource::collection($requete->paginate($request->parPage()));
    }

    /**
     * Rapprochement à trois voies — EF-M7-04.
     *
     * Lecture pure : ce contrôle ne modifie rien, il constate. Il rend
     * toujours `facture_verifiable: false` et l'avertissement qui l'explique —
     * voir `RapprochementResource` pour la raison, qui n'est pas un manque
     * d'implémentation mais un manque de schéma.
     */
    public function rapprocher(CommandeAchat $commande): RapprochementResource
    {
        return new RapprochementResource($this->rapprochement->rapprocher($commande));
    }

    /**
     * @return array{commande: CommandeAchat, quantites_recues: array<string, string>}
     */
    private function detail(CommandeAchat $commande): array
    {
        $commande->load(['fournisseur', 'lignes.article', 'receptions.commande.fournisseur']);

        return [
            'commande' => $commande,
            // Reconstitué depuis les mouvements de stock, faute de lignes de
            // bon de réception (PA-39). Le drapeau `recu_reconstitue` de la
            // ressource porte cet aveu jusqu'à l'écran.
            'quantites_recues' => $this->rapprochement->quantitesRecues($commande),
        ];
    }
}
