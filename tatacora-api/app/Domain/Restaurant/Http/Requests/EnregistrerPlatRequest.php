<?php

declare(strict_types=1);

namespace App\Domain\Restaurant\Http\Requests;

use App\Domain\Restaurant\Models\Plat;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Création et modification d'un plat — EF-M4-01.
 *
 * ## Le champ « Ingrédients principaux » du maître est REFUSÉ
 *
 * `m4-restauration.html` l.161-167 le rend en `textarea` libre (« Poulet,
 * plantain mûr, poivron, tomate »). C'est nommément l'anti-pattern de
 * démonstration listé dans `CLAUDE.md` et détaillé en PA-23 /
 * `SPEC_ECRAN_M4_RESTAURANT.md` §6 : une chaîne de caractères ne se rattache à
 * aucun article, donc ne décrémente aucun stock, et la fiche technique ne sert
 * à rien. La vraie composition passe par
 * `PUT /restaurant/recettes/{recette}/composition`, avec de vraies clés
 * étrangères vers `articles` et leurs quantités.
 *
 * Le champ est `prohibited` et non ignoré : un champ ignoré laisse le client
 * croire qu'il a été enregistré (leçon de PA-24), et le serveur découvrirait
 * l'absence de recette au comptoir, à la transmission en cuisine.
 *
 * ## `categorie` ne se saisit pas non plus
 *
 * Le maître la porte sur le plat ; le schéma la porte sur le menu
 * (`menus.type`). Un plat appartient à un menu, et sa catégorie EST celle de
 * son menu. L'accepter ici créerait une seconde vérité qui divergerait au
 * premier reclassement de menu — « une seule source de vérité par donnée »
 * (Article 10 de la directive de conformité).
 *
 * ## `disponible` : refusé, et c'est une question ouverte
 *
 * Le maître et `SPEC_ECRAN_M4_RESTAURANT.md` §4-5 exigent tous deux un badge
 * et un sélecteur « Disponible Oui/Non ». **Aucune colonne du schéma ne le
 * porte** — ni sur `plats`, ni sur `cartes_boisson` qui a le même écran côté
 * M5. Ajouter la colonne serait diverger d'un schéma vérifié conforme au CdCF
 * page 15 (`SPEC_ECRAN_M4_RESTAURANT.md`, note d'en-tête) : cela relève de
 * l'Architecte, pas de cette couche. En attendant, refuser est le seul
 * comportement honnête — accepter un `disponible: false` que rien ne stocke
 * laisserait un plat en rupture à la carte, et personne ne saurait pourquoi.
 *
 * ## `prix_provisoire` n'est PLUS refusé — le motif a cessé d'être vrai
 *
 * Il partageait jusqu'ici la liste et le message de `disponible` : « aucune
 * colonne du schéma ne le porte ». C'était exact à l'écriture, et faux depuis
 * le 02/09/2026 — PA-161 (b) a tranché, `plats.prix_provisoire` et
 * `plats.prix_corrige_main` existent. Un motif de refus périmé transforme une
 * décision en oubli (PA-144) : les deux champs sont donc acceptés, et le
 * refus retiré plutôt que laissé à vieillir sous un message faux.
 *
 * @see PA-161 (b) Marques de prix
 */
final class EnregistrerPlatRequest extends FormRequest
{
    /**
     * Champs du formulaire du maître que la table ne porte pas, ou qui se
     * déduisent d'ailleurs. Refusés un par un, avec leur message.
     *
     * @var list<string>
     */
    public const CHAMPS_REFUSES = [
        'ingredients_principaux',
        'categorie',
        'disponible',
        'stock',
        'stock_disponible',
        'portions_vendables',
        'cout_matiere',
        'marge',
    ];

    public function authorize(): bool
    {
        $plat = $this->route('plat');

        return $plat instanceof Plat
            ? ($this->user()?->can('update', $plat) ?? false)
            : ($this->user()?->can('create', Plat::class) ?? false);
    }

    /**
     * @return array<string, array<int, mixed>>
     */
    public function rules(): array
    {
        $modification = $this->route('plat') instanceof Plat;

        $regles = [
            'libelle' => ['required', 'string', 'max:255'],

            // De VRAIES clés étrangères, jamais du texte libre (règle projet).
            // `menu_id` porte aussi la catégorie affichée : sans lui, un plat
            // n'aurait pas de catégorie du tout.
            'menu_id' => ['required', 'uuid', 'exists:menus,id'],
            'recette_id' => ['required', 'uuid', 'exists:recettes,id'],

            // DECIMAL(15,2). `min:0` et non `gt:0` : le maître autorise 0
            // (`"min": 0`), et un plat offert existe réellement.
            'prix_vente' => ['required', 'numeric', 'min:0', 'max:99999999999999'],

            // PA-161 (b) — les deux marques de prix. `boolean` et non
            // `in:0,1` : Laravel accepte alors « true », « 1 » et 1, les trois
            // formes qu'un formulaire et un client JSON envoient reellement.
            // `sometimes` : une modification qui ne les soumet pas les laisse
            // en place, elle ne les efface pas.
            'prix_provisoire' => ['sometimes', 'boolean'],
            'prix_corrige_main' => ['sometimes', 'boolean'],

            'id' => $modification
                ? ['prohibited']
                : ['sometimes', 'uuid', Rule::unique('plats', 'id')],
        ];

        foreach (self::CHAMPS_REFUSES as $champ) {
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
            'libelle.required' => __('restaurant.validation.libelle_obligatoire'),
            'menu_id.required' => __('restaurant.validation.menu_obligatoire'),
            'menu_id.exists' => __('restaurant.validation.menu_inexistant'),
            'recette_id.required' => __('restaurant.validation.recette_obligatoire'),
            'recette_id.exists' => __('restaurant.validation.recette_inexistante'),
            'prix_vente.required' => __('restaurant.validation.prix_obligatoire'),
            'prix_vente.min' => __('restaurant.validation.prix_negatif'),
            'id.prohibited' => __('restaurant.validation.identifiant_non_modifiable'),
        ];

        $messages['ingredients_principaux.prohibited'] = __('restaurant.validation.ingredients_texte_libre');
        $messages['categorie.prohibited'] = __('restaurant.validation.categorie_du_menu');
        $messages['disponible.prohibited'] = __('restaurant.validation.disponibilite_sans_schema');

        foreach (['stock', 'stock_disponible', 'portions_vendables', 'cout_matiere', 'marge'] as $champ) {
            $messages[$champ . '.prohibited'] = __('restaurant.validation.valeur_calculee');
        }

        return $messages;
    }
}
