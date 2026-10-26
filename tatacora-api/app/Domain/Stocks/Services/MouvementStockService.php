<?php

declare(strict_types=1);

namespace App\Domain\Stocks\Services;

use App\Domain\Stocks\Exceptions\RuptureStockException;
use App\Domain\Stocks\Models\Article;
use App\Domain\Stocks\Models\MouvementStock;
use App\Shared\Audit\Models\JournalAudit;
use App\Shared\Sync\Support\OrigineDocuments;
use Carbon\CarbonInterface;
use Illuminate\Support\Facades\DB;

/**
 * Enregistrement des mouvements de stock (M6).
 *
 * **Unique point d'entrée d'écriture sur `mouvements_stock`.** Une insertion
 * directe contournerait à la fois le contrôle de disponibilité (RG-06) et la
 * vérification de seuil synchrone (RG-07), sans lever d'erreur.
 *
 * @see RG-05 Sortie de stock automatique — M4/M5 appellent `sortie()`
 * @see RG-06 Blocage au-delà du disponible, avec échappatoire contrôlée
 * @see RG-07 Alerte de seuil
 */
class MouvementStockService
{
    /**
     * Précision réellement conservée par `mouvements_stock.quantite`
     * (DECIMAL(10,2)) — voir PA-38.
     */
    public const PRECISION_QUANTITE = 2;

    public function __construct(
        private readonly StockTheoriqueService $stock,
        private readonly VerificationSeuilService $seuils,
        private readonly ValorisationStockService $valorisation,
    ) {
    }

    /**
     * Entrée de stock (réception fournisseur, retour, transfert entrant).
     *
     * ## Le coût unitaire est optionnel, et c'est un choix
     *
     * Une entrée **valorisée** (réception fournisseur) recalcule le coût moyen
     * pondéré de l'article. Une entrée **non valorisée** (transfert entre deux
     * points de stockage, retour cuisine) ne le touche pas : déplacer une
     * marchandise ne change pas son coût d'acquisition, et lui réappliquer un
     * CMP la revaloriserait sans qu'aucun achat n'ait eu lieu.
     *
     * Le CMP est recalculé **avant** l'écriture du mouvement : le service de
     * valorisation lit le stock antérieur, qui doit donc encore exclure cette
     * entrée.
     *
     * ## `articles.prix_achat` est posé ICI, et NULLE PART ailleurs
     *
     * C'est le DERNIER prix d'achat connu — celui de cette entrée-ci. Une
     * réception M7 passe par ce même service, donc par ce même point : deux
     * chemins d'écriture auraient fini par diverger, et un article aurait
     * affiché le prix d'une commande que personne n'a reçue.
     *
     * ⚠ Il ne reçoit JAMAIS le coût moyen pondéré. L'écart entre les deux est
     * exactement ce que la colonne « Valeur d'achat » du maître montre : elle
     * affiche la dérive en pourcentage à côté du CMP (`m6-stocks.html`
     * l.219-220), un signal d'inflation fournisseur. Y recopier le CMP rendrait
     * cette dérive nulle par construction — un indicateur qui annonce « aucune
     * hausse » sans jamais avoir rien mesuré.
     *
     * Un transfert entre points (`$coutUnitaire === null`) ne le touche pas :
     * déplacer une marchandise ne l'achète pas.
     *
     * @param  string|null  $coutUnitaire  prix d'achat unitaire, ou `null` pour un transfert
     * @param  CarbonInterface|null  $dateMouvement  date MÉTIER du document source — voir {@see enregistrer()}
     */
    public function entree(
        string $articleId,
        string $pointId,
        string $quantite,
        string $motif = 'Entrée de stock',
        ?string $coutUnitaire = null,
        ?CarbonInterface $dateMouvement = null,
        ?string $id = null,
    ): MouvementStock {
        return DB::transaction(function () use ($articleId, $pointId, $quantite, $motif, $coutUnitaire, $dateMouvement, $id): MouvementStock {
            if ($coutUnitaire !== null) {
                $article = Article::findOrFail($articleId);

                $this->valorisation->integrerEntree($article, $quantite, $coutUnitaire);

                // APRÈS la valorisation : `integrerEntree()` verrouille et
                // relit l'article, et écrirait par-dessus une affectation
                // posée avant lui. `forceFill` parce que `prix_achat` n'est
                // délibérément pas `fillable` — il n'y a pas de second chemin.
                $article->forceFill(['prix_achat' => $coutUnitaire])->save();
            }

            return $this->enregistrer($articleId, $pointId, 'entree', $quantite, $motif, $dateMouvement, $id);
        });
    }

    /**
     * Sortie de stock — RG-06.
     *
     * Refusée si elle dépasse le disponible, SAUF `$validationRupture = true`,
     * qui matérialise la décision explicite d'un utilisateur habilité. Ce
     * forçage laisse systématiquement une trace dans `journal_audit` : une
     * rupture assumée est une décision de gestion, elle doit être imputable à
     * quelqu'un.
     *
     * @throws RuptureStockException
     */
    public function sortie(
        string $articleId,
        string $pointId,
        string $quantite,
        string $motif = 'Sortie de stock',
        bool $validationRupture = false,
        string $type = 'sortie',
        ?CarbonInterface $dateMouvement = null,
        ?string $id = null,
    ): MouvementStock {
        return DB::transaction(function () use ($articleId, $pointId, $quantite, $motif, $validationRupture, $type, $dateMouvement, $id) {
            // Verrou sur l'article : sans lui, deux ventes simultanées lisent
            // toutes les deux un stock suffisant et le font passer négatif.
            // Même famille de condition de course que RG-01.
            DB::table('articles')->where('id', $articleId)->lockForUpdate()->first();

            $disponible = $this->stock->stock($articleId, $pointId);
            $suffisant = bccomp($disponible, $quantite, 2) >= 0;

            if (! $suffisant && ! $validationRupture) {
                throw new RuptureStockException($articleId, $pointId, $disponible, $quantite);
            }

            $mouvement = $this->enregistrer($articleId, $pointId, $type, $quantite, $motif, $dateMouvement, $id);

            if (! $suffisant) {
                $this->tracerRuptureForcee($mouvement, $disponible, $quantite);
            }

            return $mouvement;
        });
    }

    /**
     * Perte (casse, péremption) — soumise au même contrôle que la sortie :
     * on ne peut pas perdre plus que ce qu'on détient.
     *
     * @throws RuptureStockException
     */
    public function perte(
        string $articleId,
        string $pointId,
        string $quantite,
        string $motif,
        bool $validationRupture = false,
        ?CarbonInterface $dateMouvement = null,
        ?string $id = null,
    ): MouvementStock {
        return $this->sortie($articleId, $pointId, $quantite, $motif, $validationRupture, 'perte', $dateMouvement, $id);
    }

    /**
     * Écart d'inventaire — quantité SIGNÉE (positive si l'on a retrouvé du
     * stock, négative si l'on en a perdu). Aucun contrôle de disponibilité :
     * un inventaire constate le réel, il ne le discute pas.
     */
    public function ecartInventaire(
        string $articleId,
        string $pointId,
        string $ecart,
        string $motif = 'Écart d\'inventaire',
        ?CarbonInterface $dateMouvement = null,
        ?string $id = null,
    ): MouvementStock {
        // `$dateMouvement` et `$id` (21/10/2026) : la régularisation d'un
        // inventaire clôturé sur un POSTE naît avec son UUID et à la date du
        // geste (synchronisation) ; les appels en ligne ne les passent pas.
        return $this->enregistrer($articleId, $pointId, 'inventaire', $ecart, $motif, $dateMouvement, $id);
    }

    /**
     * `$dateMouvement` (15/10/2026, lot S3 de synchronisation) : la date
     * MÉTIER du document qui produit le mouvement — la vente ou la réception
     * faite hors connexion lundi et reçue jeudi est un mouvement de LUNDI
     * (D246). `null` — tous les chemins en ligne — garde `now()`, inchangé.
     */
    private function enregistrer(
        string $articleId,
        string $pointId,
        string $type,
        string $quantite,
        string $motif,
        ?CarbonInterface $dateMouvement = null,
        ?string $id = null,
    ): MouvementStock {
        $mouvement = MouvementStock::create([
            // L'UUID du poste quand le mouvement y est né (synchronisation).
            ...($id !== null ? ['id' => $id] : []),
            'article_id' => $articleId,
            'point_id' => $pointId,
            'type_mouvement' => $type,
            'quantite' => $quantite,
            'motif' => $motif,
            'utilisateur_id' => auth()->id(),
            'date_mouvement' => $dateMouvement ?? now(),
        ]);

        // Lot F4 : un mouvement écrit pendant l'application d'une opération de
        // synchronisation (réception, vente d'un poste) porte ce poste
        // d'origine — hors synchronisation, rien n'est retenu.
        app(OrigineDocuments::class)->retenir('mouvements_stock', (string) $mouvement->id);

        // RG-07 — vérification synchrone, jamais différée en file d'attente :
        // l'utilisateur qui vient de vider le stock doit être averti tout de
        // suite, pas au prochain passage du job planifié.
        $this->seuils->verifierApresMouvement($articleId, $pointId);

        return $mouvement;
    }

    private function tracerRuptureForcee(MouvementStock $mouvement, string $disponible, string $demande): void
    {
        JournalAudit::create([
            'utilisateur_id' => auth()->id(),
            'action' => 'rupture_stock_forcee',
            'entite_concernee' => 'mouvements_stock',
            'entite_id' => $mouvement->id,
            'valeur_avant' => ['stock_disponible' => $disponible],
            'valeur_apres' => [
                'quantite_sortie' => $demande,
                'article_id' => $mouvement->article_id,
                'point_id' => $mouvement->point_id,
            ],
            'adresse_poste' => request()->ip(),
        ]);
    }

    /**
     * Arrondi commercial à la précision que `mouvements_stock` sait conserver.
     *
     * **Point unique.** Une recette s'exprime au millième (PA-38), un
     * conditionnement de carte au dix-millième (1/24 = 0,0417) : les deux
     * arrivent ici avec plus de décimales que la colonne n'en garde. L'arrondi
     * est fait EXPLICITEMENT, une seule fois, plutôt que laissé à la
     * troncature silencieuse de MySQL — au moins il est visible et testable.
     * Le recopier dans chaque appelant les ferait diverger au premier
     * changement de précision du schéma.
     */
    public function arrondirQuantite(string $quantite): string
    {
        return bcadd(
            $quantite,
            bccomp($quantite, '0', 4) >= 0 ? '0.005' : '-0.005',
            self::PRECISION_QUANTITE,
        );
    }

    /**
     * Sécurité de conception : ce service refuse de travailler sur un article
     * inconnu plutôt que de créer un mouvement orphelin que la clé étrangère
     * rejetterait avec un message SQL illisible.
     */
    public function articleExiste(string $articleId): bool
    {
        return Article::whereKey($articleId)->exists();
    }
}
