<?php

declare(strict_types=1);

namespace App\Domain\Stocks\Http\Resources;

use App\Domain\Stocks\ReadModels\LigneStockArticle;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Un article et son stock calculé, tel que le lit l'écran Stocks.
 *
 * ## Tout ce qui est calculé sort en LECTURE SEULE, et le dit
 *
 * `stock`, `valeur_stock`, `sous_seuil` et `rupture` sont des agrégats de
 * `mouvements_stock`. Aucun d'eux n'est accepté en entrée — ni ici, ni par
 * `EnregistrerArticleRequest`, qui les refuse explicitement. C'est le
 * correctif de PA-24 : le champ « Stock disponible » du prototype était
 * éditable, si bien qu'une vente ne l'aurait jamais décrémenté et que le stock
 * affiché serait resté faux indéfiniment.
 *
 * `stock_lecture_seule` est envoyé au client pour qu'il n'ait pas à le
 * redécouvrir : un formulaire Flutter qui rendrait ce champ saisissable
 * enverrait une valeur que le serveur ignorerait en silence.
 *
 * ## Les montants et quantités sortent en CHAÎNE, jamais en float
 *
 * Un `DECIMAL(10,2)` converti en float ici puis réarrondi côté client ferait
 * diverger l'affichage du chiffre réellement stocké. Même règle que le tarif
 * figé d'une réservation (PA-55) et que le parc d'hébergement.
 *
 * @property-read LigneStockArticle $resource
 */
class ArticleStockResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        $article = $this->resource->article;

        return [
            'id' => $article->id,
            'libelle' => $article->libelle,
            'categorie' => $article->categorie,
            'unite_mesure' => $article->unite_mesure,
            'seuil_alerte' => (string) $article->seuil_alerte,
            'seuil_reappro' => $article->seuil_reappro === null ? null : (string) $article->seuil_reappro,
            'cout_moyen_pondere' => (string) $article->cout_moyen_pondere,

            // --- PA-161 (a) : les trois colonnes du tableau du maître -------
            // `point_stockage_id` est le rattachement PRINCIPAL, jamais la
            // portée du stock — celle-ci est `portee`/`point_id` plus bas. Un
            // client qui les confondrait servirait au comptoir une bouteille
            // qui dort au magasin.
            'point_stockage_id' => $article->point_stockage_id,
            'suivi' => $article->suivi,
            // `null` quand l'article n'a jamais été réceptionné : « 0 » se
            // lirait « acheté gratuitement ».
            'prix_achat' => $article->prix_achat === null ? null : (string) $article->prix_achat,
            // La dérive du CMP par rapport au dernier prix d'achat, en points
            // de pourcentage — `null` quand elle n'est pas mesurable, jamais 0.
            'derive_cout_moyen' => $article->deriveCoutMoyenPondere(),

            // --- Valeurs CALCULÉES depuis mouvements_stock, en lecture seule ---
            'stock' => $this->resource->stock,
            'valeur_stock' => $this->resource->valeur,
            // La portée accompagne toujours le chiffre : « 12 » ne veut rien
            // dire tant qu'on ne sait pas si c'est au bar ou tous points
            // confondus. Un client qui l'ignorerait servirait au comptoir une
            // bouteille qui se trouve au magasin.
            'portee' => $this->resource->portee,
            'point_id' => $this->resource->pointId,
            'sous_seuil' => $this->resource->sousSeuil,
            'rupture' => $this->resource->rupture,
            'stock_lecture_seule' => true,
        ];
    }
}
