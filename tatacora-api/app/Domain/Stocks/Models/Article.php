<?php

declare(strict_types=1);

namespace App\Domain\Stocks\Models;

use App\Shared\Audit\Traits\Auditable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Référentiel unique de tous les articles : denrées, boissons, fournitures,
 * pièces détachées (M6, transverse).
 *
 * **Aucune colonne de stock n'existe sur cette table, et il ne faut jamais en
 * ajouter.** Le stock est calculé depuis `mouvements_stock` par
 * `StockTheoriqueService`. C'est l'anti-pattern le plus coûteux du prototype :
 * son champ « Stock disponible » était éditable, si bien qu'une vente ne
 * l'aurait jamais décrémenté et que le stock affiché serait resté faux
 * indéfiniment, sans que rien ne le signale (A1_MASTER_PROMPT.md §2.2).
 *
 * Les deux seuils portés ici sont des paramètres, pas des états :
 * - `seuil_alerte` déclenche la notification Magasinier/Gérant (RG-07, M6) ;
 * - `seuil_reappro` sert à M7 pour suggérer une commande, et lui est
 *   généralement supérieur pour absorber le délai de livraison fournisseur.
 *
 * ## `point_stockage_id` N'EST PAS la portée du stock
 *
 * C'est le point PRINCIPAL de l'article — celui que le maître affiche en
 * colonne « Point » (`m6-stocks.html` l.227) et repropose par défaut à la
 * saisie d'un mouvement (l.396). Le stock, lui, reste calculé par couple
 * (article, point) : un même article existe simultanément au magasin et au
 * bar, et lire cette colonne pour répondre à « combien en ai-je ? » donnerait
 * une réponse fausse sans que rien ne le signale. `null` veut dire « jamais
 * réceptionné », un état légitime qui se rend « — » avec sa raison.
 *
 * ## `suivi` commande cinq comportements, et le journalier n'a PAS de stock
 *
 * Un article en `journalier` (petit stock acheté au jour le jour) n'entre ni
 * dans les mouvements, ni dans l'inventaire, ni dans la valorisation : son
 * stock n'est pas suivi. Le refuser explicitement (`estSuiviEnStock()`) plutôt
 * que de le laisser passer évite un solde théorique qui ne correspondrait à
 * rien de compté.
 *
 * ## `prix_achat` n'est PAS le coût moyen pondéré, et ne doit jamais le devenir
 *
 * C'est le DERNIER prix d'achat connu, posé par `MouvementStockService::entree()`
 * — point d'écriture unique, réception M7 comprise. L'écart entre les deux est
 * exactement ce que la colonne « Valeur d'achat » du maître sert à montrer :
 * il affiche la dérive en pourcentage à côté du CMP (l.219-220), un signal
 * d'inflation fournisseur. Y recopier le CMP rendrait cette dérive nulle par
 * construction.
 *
 * @property string $id
 * @property string $libelle
 * @property string|null $categorie
 * @property string $unite_mesure
 * @property string|null $point_stockage_id rattachement principal, JAMAIS la portée du stock
 * @property string $suivi self::SUIVIS
 * @property bool $actif l'ARCHIVE du referentiel (03/09/2026) — hors `$fillable` : seul `ReferentielArticleService` la bascule
 * @property string $seuil_alerte
 * @property string|null $seuil_reappro nullable au schema, contrairement au seuil d'alerte
 * @property string|null $prix_achat dernier prix d'achat connu, distinct du CMP
 * @property string $cout_moyen_pondere
 *
 * ⚠ `$pointStockage` est NULLABLE — un article jamais réceptionné n'a pas de
 * point. L'annotation le dit pour le LECTEUR ; elle ne suffit pas à l'analyse
 * statique, qui déduit du type de la relation que le point est toujours là et
 * signale comme inutile le `?->` qui protège précisément ce cas. Les appelants
 * testent donc explicitement (`instanceof`, `!== null`) plutôt que de
 * contredire l'analyseur.
 *
 * @property-read PointStockage|null $pointStockage
 */
class Article extends Model
{
    use Auditable;
    use HasUuids;

    protected $table = 'articles';

    /**
     * Le registre FERMÉ des modes de suivi — celui de l'`enum` au schéma, et
     * celui du maître (`m6-stocks.html` l.312-314).
     *
     * `permanent` : gros stock (sacs, cartons, viandes) suivi en mouvements.
     * `journalier` : petit stock acheté au jour le jour, dont le stock n'est
     * pas tenu.
     *
     * @var list<string>
     */
    public const SUIVIS = ['permanent', 'journalier'];

    protected $fillable = [
        'id',
        'libelle',
        'categorie',
        'unite_mesure',
        'point_stockage_id',
        'suivi',
        'seuil_alerte',
        'seuil_reappro',
        'cout_moyen_pondere',
        // `prix_achat` est ABSENT de cette liste, et c'est délibéré : il n'est
        // pas saisi, il est posé par `MouvementStockService::entree()` depuis
        // le coût unitaire de l'entrée. Le rendre `fillable` ouvrirait un
        // second chemin d'écriture, qui divergerait du premier.
    ];

    protected function casts(): array
    {
        return [
            'seuil_alerte' => 'decimal:2',
            'seuil_reappro' => 'decimal:2',
            'prix_achat' => 'decimal:2',
            'cout_moyen_pondere' => 'decimal:4',
            // L'ARCHIVE du référentiel (03/09/2026). Absente de `$fillable`
            // volontairement : `ReferentielArticleService` est le seul chemin
            // qui la bascule, et il porte les quatre verrous d'engagement.
            'actif' => 'boolean',
        ];
    }

    /**
     * Vrai quand le stock de cet article est réellement tenu.
     *
     * Ce n'est PAS un indicateur dérivé d'une absence : il lit une colonne que
     * le formulaire écrit, avec un défaut qui décrit le comportement en
     * vigueur (`permanent`). Un article journalier refuse le mouvement de
     * stock — le maître le dit à l'écran, « son stock n'est pas suivi »
     * (`m6-stocks.html` l.380-383).
     */
    public function estSuiviEnStock(): bool
    {
        return $this->suivi !== 'journalier';
    }

    /**
     * La dérive du coût moyen pondéré par rapport au dernier prix d'achat, en
     * pourcentage entier — `null` quand elle n'est pas mesurable.
     *
     * ⚠ `null` et non `0` : sans prix d'achat connu, il n'y a pas de dérive
     * NULLE, il n'y a pas de dérive du tout. Rendre `0` afficherait « aucune
     * hausse » sur un article qu'on n'a jamais réceptionné — un indicateur qui
     * affirme un état qu'il n'a pas vérifié (PA-59/60/61).
     *
     * `bccomp`/`bcsub`/`bcdiv`, jamais une arithmétique flottante sur des
     * montants (règle projet).
     */
    public function deriveCoutMoyenPondere(): ?int
    {
        $achat = $this->prix_achat === null ? null : (string) $this->prix_achat;

        if ($achat === null || bccomp($achat, '0.00', 2) <= 0) {
            return null;
        }

        $ecart = bcsub((string) $this->cout_moyen_pondere, $achat, 4);

        return (int) round((float) bcmul(bcdiv($ecart, $achat, 6), '100', 4));
    }

    /**
     * @return BelongsTo<PointStockage, $this>
     */
    public function pointStockage(): BelongsTo
    {
        return $this->belongsTo(PointStockage::class, 'point_stockage_id');
    }

    /**
     * @return HasMany<MouvementStock, $this>
     */
    public function mouvements(): HasMany
    {
        return $this->hasMany(MouvementStock::class, 'article_id');
    }
}
