<?php

declare(strict_types=1);

namespace App\Domain\Achats\Http\Requests;

use App\Domain\Achats\Models\CommandeAchat;
use App\Domain\Achats\Services\CommandeAchatService;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

/**
 * Création d'une commande d'achat et de ses lignes — EF-M7-02, UC-29.
 *
 * ## Le montant total est CALCULÉ, jamais soumis
 *
 * Le formulaire du prototype porte « Montant estimé (FCFA) » en saisie libre
 * (`m7-achats.html`). Aucune colonne de montant n'existe au schéma, et le
 * total se somme depuis les lignes (`CommandeAchat::montantTotal()`).
 * L'accepter en entrée ne servirait à rien — sinon à laisser croire au client
 * qu'il a été pris en compte, jusqu'au jour où l'écran afficherait un montant
 * différent de celui qu'il a tapé, sans que personne comprenne lequel est le
 * bon. Il est donc **interdit**, pas ignoré (PA-24).
 *
 * ## Le même article ne peut pas figurer deux fois
 *
 * `ReceptionService::evaluerConformite()` relit les quantités commandées par
 * `pluck('quantite_commandee', 'article_id')` : un article présent sur deux
 * lignes verrait la seconde **écraser** la première. La commande porterait
 * 30 + 20 sacs, le contrôle RG-10 n'en verrait que 20, et une livraison de 50
 * serait déclarée en excédent hors tolérance — donc `non_conforme`. Le refus
 * est en amont, là où l'utilisateur peut encore corriger sa saisie.
 *
 * ## `fournisseur_id` et `article_id` sont de VRAIES clés étrangères
 *
 * L'anti-pattern « Fournisseur en texte libre » du prototype casse
 * silencieusement le rapprochement à trois voies (EF-M7-04), qui suppose une
 * relation exacte. `exists` refuse ici, en clair, ce que la base refuserait
 * plus loin avec un message SQL.
 */
final class CreerCommandeAchatRequest extends FormRequest
{
    /**
     * Champs que la commande calcule ou dérive, et qui ne se saisissent donc
     * pas.
     *
     * @var list<string>
     */
    public const CHAMPS_CALCULES = [
        'montant_total',
        'montant_estime',
        'montant_regle',
        'reste_du',
        'nombre_lignes',
    ];

    public function authorize(): bool
    {
        return $this->user()?->can('create', CommandeAchat::class) ?? false;
    }

    /**
     * @return array<string, array<int, mixed>>
     */
    public function rules(): array
    {
        $regles = [
            'fournisseur_id' => ['required', 'uuid', 'exists:fournisseurs,id'],
            'date_commande' => ['required', 'date'],

            // Registre fermé et COURT : les trois autres statuts de l'enum
            // sont produits par une réception réelle, jamais choisis.
            'statut' => ['sometimes', Rule::in(CommandeAchatService::STATUTS_SAISISSABLES)],

            'lignes' => ['required', 'array', 'min:1'],
            'lignes.*.article_id' => [
                'required',
                'uuid',
                'exists:articles,id',
                'distinct',
            ],
            // `gt:0` et non `min:0` : une ligne à zéro n'est pas une commande,
            // c'est une saisie inachevée. Elle produirait une ligne que la
            // réception ne pourrait jamais satisfaire.
            'lignes.*.quantite_commandee' => ['required', 'numeric', 'gt:0', 'decimal:0,2'],

            // Obligatoire : c'est ce prix qui valorise l'entrée de stock à la
            // réception, donc qui recalcule le coût moyen pondéré. Sans lui,
            // la marchandise entrerait à zéro et écraserait le CMP.
            'lignes.*.prix_unitaire' => ['required', 'numeric', 'min:0', 'decimal:0,2'],

            // L'auteur vient du jeton (RG-15). L'accepter permettrait
            // d'attribuer une commande à quelqu'un d'autre.
            'utilisateur_id' => ['prohibited'],

            // Aucun mécanisme de rejeu n'existe : `commandes_achat` n'est pas
            // au registre `TABLES_SYNCHRONISABLES`.
            'id' => ['prohibited'],
        ];

        foreach (self::CHAMPS_CALCULES as $champ) {
            $regles[$champ] = ['prohibited'];
            $regles['lignes.*.' . $champ] = ['prohibited'];
        }

        return $regles;
    }

    /**
     * @return array<string, string>
     */
    public function messages(): array
    {
        $messages = [
            'fournisseur_id.exists' => __('achats.validation.fournisseur_inexistant'),
            'lignes.required' => __('achats.validation.lignes_obligatoires'),
            'lignes.min' => __('achats.validation.lignes_obligatoires'),
            'lignes.*.article_id.exists' => __('achats.validation.article_inexistant'),
            'lignes.*.article_id.distinct' => __('achats.validation.article_en_double'),
            'lignes.*.quantite_commandee.gt' => __('achats.validation.quantite_positive'),
            'lignes.*.prix_unitaire.required' => __('achats.validation.prix_obligatoire'),
            'statut.in' => __('achats.validation.statut_non_saisissable'),
            'id.prohibited' => __('achats.validation.identifiant_non_accepte'),
            'utilisateur_id.prohibited' => __('achats.validation.valeur_calculee'),
        ];

        foreach (self::CHAMPS_CALCULES as $champ) {
            $messages[$champ . '.prohibited'] = __('achats.validation.valeur_calculee');
            $messages['lignes.*.' . $champ . '.prohibited'] = __('achats.validation.valeur_calculee');
        }

        return $messages;
    }

    /**
     * Les données du service, dans la forme qu'il attend — les montants sont
     * normalisés en CHAÎNE ici, jamais laissés flotter jusqu'au calcul.
     *
     * @return array{
     *     fournisseur_id: string,
     *     date_commande: string,
     *     statut?: string,
     *     lignes: list<array{article_id: string, quantite_commandee: string, prix_unitaire: string}>
     * }
     */
    public function donnees(): array
    {
        /** @var array<string, mixed> $valide */
        $valide = $this->validated();

        $lignes = [];

        /** @var list<array<string, mixed>> $brutes */
        $brutes = is_array($valide['lignes']) ? array_values($valide['lignes']) : [];

        foreach ($brutes as $ligne) {
            $lignes[] = [
                'article_id' => (string) $ligne['article_id'],
                'quantite_commandee' => (string) $ligne['quantite_commandee'],
                'prix_unitaire' => (string) $ligne['prix_unitaire'],
            ];
        }

        $donnees = [
            'fournisseur_id' => (string) $valide['fournisseur_id'],
            'date_commande' => (string) $valide['date_commande'],
            'lignes' => $lignes,
        ];

        if (isset($valide['statut'])) {
            $donnees['statut'] = (string) $valide['statut'];
        }

        return $donnees;
    }
}
