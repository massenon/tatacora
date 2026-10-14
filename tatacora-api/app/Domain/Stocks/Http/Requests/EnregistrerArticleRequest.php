<?php

declare(strict_types=1);

namespace App\Domain\Stocks\Http\Requests;

use App\Domain\Stocks\Models\Article;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Valide la création et la modification d'un article — EF-M6-01.
 *
 * ## Aucun champ de stock, aucun coût moyen : ils se CALCULENT
 *
 * Le formulaire du prototype porte « Stock d'ouverture » et « Prix d'achat »
 * (`m6-stocks.html`), et son moteur les enregistre comme des valeurs saisies.
 * Ni l'un ni l'autre n'a d'équivalent ici, et c'est délibéré :
 *
 * - un **stock d'ouverture** est une entrée de stock. La seule façon honnête
 *   de le poser est un mouvement `entree` daté, motivé et imputable, qui laisse
 *   une trace dans la fiche de stock. Une colonne saisie ne serait
 *   rapprochable de rien (`FicheStockService`) ;
 * - le **coût moyen pondéré** est recalculé à chaque entrée valorisée par
 *   `ValorisationStockService`. Le saisir à la création figerait une valeur qui
 *   alimente le poste de stocks au bilan, la variation de stock au résultat, et
 *   l'impôt qui va avec. Un stock faux se lit exactement comme un stock juste.
 *
 * Ces champs sont donc **interdits**, pas ignorés (PA-24). Un champ ignoré
 * laisse le client croire qu'il a compté.
 *
 * `prix_achat` rejoint cette liste, et pour la même raison : ce n'est pas une
 * saisie de référentiel, c'est le DERNIER prix d'achat connu, posé par
 * `MouvementStockService::entree()` depuis le coût unitaire de l'entrée —
 * point d'écriture unique, réception M7 comprise. L'accepter ici ouvrirait un
 * second chemin, qui divergerait du premier au premier réapprovisionnement.
 *
 * ## Le mode de suivi et le point de rattachement sont désormais ACCEPTÉS
 *
 * ⚠ La note précédente disait que `articles` ne portait aucune colonne
 * `suivi`, et que l'arbitrage n'était pas du ressort du lot. C'était vrai à
 * l'écriture et c'est faux depuis le 02/09/2026 : PA-161 (a) a tranché, les
 * deux colonnes existent. Un motif de refus qui a cessé d'être vrai transforme
 * une décision en oubli (PA-144) — il est donc retiré, pas laissé à vieillir.
 *
 * `suivi` est un registre FERMÉ (`Article::SUIVIS`) ; `point_stockage_id` est
 * une vraie clé étrangère, jamais du texte libre, et il ne désigne PAS la
 * portée du stock (voir le modèle).
 *
 * @see EF-M6-01 Référentiel articles multi-catégories
 * @see EF-M6-03 Valorisation au coût moyen pondéré
 * @see PA-161 (a) Les trois colonnes M6
 */
final class EnregistrerArticleRequest extends FormRequest
{
    /**
     * Champs que le référentiel ne stocke pas parce qu'il les calcule.
     *
     * @var list<string>
     */
    public const CHAMPS_CALCULES = [
        'stock',
        'stock_initial',
        'stock_disponible',
        'quantite_stock',
        'cout_moyen_pondere',
        'valeur_stock',
        // Posé par `MouvementStockService::entree()`, jamais saisi ici.
        'prix_achat',
    ];

    public function authorize(): bool
    {
        $article = $this->route('article');

        return $article instanceof Article
            ? ($this->user()?->can('update', $article) ?? false)
            : ($this->user()?->can('create', Article::class) ?? false);
    }

    /**
     * @return array<string, array<int, mixed>>
     */
    public function rules(): array
    {
        $article = $this->route('article');
        $modification = $article instanceof Article;

        $regles = [
            'libelle' => ['required', 'string', 'max:255'],
            'categorie' => ['required', 'string', 'max:255'],
            'unite_mesure' => ['required', 'string', 'max:255'],

            // Le seuil est un PARAMÈTRE, pas un état : il commande l'alerte
            // RG-07, il ne décrit pas le stock. À ce titre il se saisit.
            'seuil_alerte' => ['required', 'numeric', 'min:0', 'decimal:0,2'],

            // Distinct du seuil d'alerte, et généralement supérieur : il
            // absorbe le délai de livraison fournisseur (usage M7).
            'seuil_reappro' => ['sometimes', 'nullable', 'numeric', 'min:0', 'decimal:0,2'],

            // Vraie clé étrangère, jamais du texte libre. Nullable : un
            // article jamais réceptionné n'a pas de point de rattachement, et
            // lui en poser un par défaut affirmerait un lieu que personne n'a
            // décidé.
            'point_stockage_id' => ['sometimes', 'nullable', 'uuid', Rule::exists('points_stockage', 'id')],

            // Registre FERMÉ : un « journaliere » au pluriel ferait disparaître
            // l'article de tous les filtres sans qu'aucun message ne l'annonce.
            'suivi' => ['sometimes', Rule::in(Article::SUIVIS)],

            // UUID fourni par le client à la création — convention offline-first
            // du projet (02_SOFTWARE_ARCHITECTURE.md §5). `unique` et non un
            // écrasement silencieux : un second POST sur le même identifiant
            // est une anomalie qui doit se voir, pas une mise à jour déguisée.
            'id' => $modification
                ? ['prohibited']
                : ['sometimes', 'uuid', Rule::unique('articles', 'id')],
        ];

        foreach (self::CHAMPS_CALCULES as $champ) {
            $regles[$champ] = ['prohibited'];
        }

        return $regles;
    }

    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        $messages = [
            'libelle.required' => __('stocks.validation.libelle_obligatoire'),
            'unite_mesure.required' => __('stocks.validation.unite_obligatoire'),
            'seuil_alerte.required' => __('stocks.validation.seuil_obligatoire'),
            'id.unique' => __('stocks.validation.identifiant_deja_pris'),
            'id.prohibited' => __('stocks.validation.identifiant_non_modifiable'),
            'point_stockage_id.exists' => __('stocks.validation.point_inexistant'),
            'suivi.in' => __('stocks.validation.suivi_inconnu'),
        ];

        foreach (self::CHAMPS_CALCULES as $champ) {
            $messages[$champ . '.prohibited'] = __('stocks.validation.valeur_calculee');
        }

        return $messages;
    }
}
