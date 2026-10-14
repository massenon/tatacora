<?php

declare(strict_types=1);

namespace App\Domain\Bar\Http\Resources;

use App\Domain\Carte\Models\IndisponibiliteCarte;
use App\Domain\Carte\Services\StockDeCarteService;
use App\Domain\Stocks\Models\Article;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Représentation API d'une boisson de la carte.
 *
 * ## Le stock vient de l'auteur UNIQUE de la carte (PA-199)
 *
 * `StockDeCarteService`, le même que l'écran PWA. Jusqu'au 11/09/2026 cette
 * ressource écrivait son propre calcul, qui rendait des casiers là où la carte
 * rend des bouteilles, lisait un point de bar au hasard (`first()` sans
 * `ORDER BY`) et levait sur une lecture impossible.
 *
 * @property-read \App\Domain\Bar\Models\CarteBoisson $resource
 */
class BoissonResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        $stocks = app(StockDeCarteService::class);
        $point = $stocks->pointDuBar();
        $article = $this->resource->article;
        // Un modèle tout juste créé ne porte pas le défaut de la colonne
        // (`1.0000`, posé par MySQL, jamais relu) : sans ce repli, la chaîne
        // vide atteignait `bcdiv()` de `conversionLisible()` — division par zéro
        // à la réponse de `POST /bar/boissons`.
        $conversion = (string) ($this->resource->unites_vendables_par_unite_stock ?? '1.0000');
        ['stock' => $stock, 'reserve' => $reserve] = $stocks->etat(
            $article instanceof Article ? $article : null,
            $conversion,
            $point,
        );
        $chiffre = is_array($stock) && ($stock['non_consulte'] ?? true) === false;

        return [
            'id' => $this->resource->id,
            'libelle' => $this->resource->libelle,
            'categorie' => $this->resource->categorie,
            'prix_vente' => $this->resource->prix_vente,
            // PA-161 (b) — la marque « prix provisoire » : un tarif posé faute
            // de relevé, à confronter à la carte. Rendue le 11/09/2026 : le
            // bandeau d'indicateurs de la carte la compte (PA-199).
            'prix_provisoire' => $this->resource->prix_provisoire === true,
            // La seconde marque de la vue : un prix posé à la main (PA-200).
            'prix_corrige_main' => $this->resource->prix_corrige_main === true,
            'article_id' => $this->resource->article_id,
            // La colonne « Article de stock » de la carte : le libellé de
            // l'article et son conditionnement en clair — la phrase de
            // `StockDeCarteService::conversionLisible()`, la même que la PWA
            // (PA-200). `null` sans article.
            'lien_stock' => $article instanceof Article ? [
                'libelle' => (string) $article->libelle,
                'detail' => StockDeCarteService::conversionLisible(
                    $conversion,
                    (string) ($article->unite_mesure ?? __('carte_pwa.commun.unite_defaut')),
                ),
            ] : null,
            // Le conditionnement du lien — unités VENDABLES par unité de stock
            // (24 pour un casier de 24). Exposé le 11/09/2026 : sans lui, un
            // client ne peut pas rouvrir « Lier au stock » sur la valeur
            // enregistrée, et repartir de 1 diviserait la déduction par
            // vingt-quatre (`EcranDeCarte::ouvrirLienAuStock()`). En chaîne,
            // `decimal:4`, comme tout nombre de ce dépôt. NOT NULL au bar,
            // défaut `1.0000` (migration `ajouter_conversion_stock_carte`).
            'unites_vendables_par_unite_stock' => $conversion,

            // L'indisponibilité EN COURS, ou `null` : la boisson est à la
            // carte. Exposée le 11/09/2026 — sans elle, un client ne pouvait
            // ni savoir qu'une boisson était retirée, ni offrir « Remettre ».
            // `temporaire` est rendu parce que c'est une propriété du MOTIF
            // (`IndisponibiliteCarte::MOTIFS`) : le client ne doit pas avoir
            // à la redéduire d'une seconde liste.
            'indisponibilite' => $this->indisponibilite(),

            // Stock CALCULÉ, exposé en lecture seule. Il n'est jamais accepté
            // en entrée (voir EnregistrerBoissonRequest) : le client Flutter
            // l'affiche, il ne le soumet pas (PA-24).
            //
            // `stock_disponible` garde son sens historique — le solde BRUT au
            // point de vente, en unités de STOCK — pour ne rien casser chez
            // un client qui le lit ; `null` si le point manque ou si la
            // lecture a échoué, jamais `0`.
            'stock_disponible' => $chiffre ? $stock['solde'] : null,
            // Les chiffres DE LA CARTE, ceux que la PWA affiche (PA-199) :
            // `stock_vendable` en unités VENDABLES (bouteilles), `reserve`
            // hors point de vente, les deux drapeaux, et les deux raisons
            // d'une absence de chiffre — distinctes, parce que « aucun point
            // de bar déclaré » et « lecture impossible » ne se corrigent pas
            // de la même façon.
            'stock_vendable' => $chiffre ? $stock['unites_vendables'] : null,
            'reserve' => $reserve,
            'sous_seuil' => $chiffre ? $stock['sous_seuil'] : null,
            'rupture' => $chiffre ? $stock['rupture'] : null,
            'stock_non_consulte' => is_array($stock) && ($stock['non_consulte'] ?? false) === true,
            'point_de_vente_absent' => $point === null,
            'stock_lecture_seule' => true,
        ];
    }

    /**
     * @return array{motif: string, libelle: string, temporaire: bool, commentaire: string|null, depuis: string}|null
     */
    private function indisponibilite(): ?array
    {
        $enCours = $this->resource->indisponibiliteEnCours;

        if (! $enCours instanceof IndisponibiliteCarte) {
            return null;
        }

        return [
            'motif' => $enCours->motif,
            'libelle' => $enCours->libelleMotif(),
            'temporaire' => $enCours->estTemporaire(),
            'commentaire' => $enCours->commentaire,
            'depuis' => $enCours->date_indisponibilite->toIso8601String(),
        ];
    }
}
