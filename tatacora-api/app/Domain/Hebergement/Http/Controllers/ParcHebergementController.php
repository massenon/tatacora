<?php

declare(strict_types=1);

namespace App\Domain\Hebergement\Http\Controllers;

use App\Domain\Hebergement\Models\CategorieHebergement;
use App\Domain\Hebergement\Models\UniteHebergement;
use Illuminate\Http\JsonResponse;

/**
 * Le PARC d'hébergement — `GET /api/v1/hebergement/parc`.
 *
 * ## Pourquoi cette route n'existait pas, et pourquoi il la fallait (PA-128)
 *
 * `GET /hebergement/disponibilites` ne rend que les unités **libres sur une
 * période**, et seulement `{id, numero, categorie_id}` : ni tarif, ni capacité,
 * ni les unités indisponibles. C'est une réponse à une question de vente, pas
 * un référentiel.
 *
 * Le client Flutter, lui, calcule la disponibilité **en local** : il lui faut
 * le parc entier, catégories comprises. Faute de cette route, ses tables
 * `categories_hebergement_local` et `unites_hebergement_local` n'étaient
 * **jamais écrites** — lues partout, alimentées nulle part. Un poste neuf
 * affichait donc « Aucune unité au parc » et ne pouvait prendre aucune
 * réservation, ce qui est tout M1.
 *
 * C'est la même racine que PA-65 : **une donnée absente de l'API est une donnée
 * absente du client**, et le manque ne se voit ni côté serveur (la route
 * existe pour la vente) ni côté client (l'écran dit poliment que le parc n'est
 * pas renseigné).
 *
 * ## Le parc DESCEND, il ne remonte jamais
 *
 * `unites_hebergement` n'est pas au registre `TABLES_SYNCHRONISABLES` : une
 * unité créée au comptoir ne partirait nulle part. C'est ce qui a fait refuser
 * le « Plan d'Hébergement » du prototype (PA-118), et cette route ne change
 * rien à cette décision — elle est en lecture seule, par construction.
 *
 * ## Aucune pagination
 *
 * Le parc du Gîte se compte en dizaines d'unités, et le client en a besoin
 * **entier** pour calculer une disponibilité : une page manquante ferait
 * apparaître libre une chambre déjà prise. Paginer ici transformerait une
 * omission en défaut silencieux.
 *
 * @see EF-M1-01 consultation des disponibilités
 */
class ParcHebergementController
{
    public function __invoke(): JsonResponse
    {
        $categories = CategorieHebergement::query()
            ->orderBy('libelle')
            ->get()
            ->map(fn (CategorieHebergement $c): array => [
                'id' => $c->id,
                'libelle' => $c->libelle,
                'capacite_max' => (int) $c->capacite_max,
                // Chaîne, comme partout : un `DECIMAL(15,2)` converti en float
                // ici puis réarrondi côté client ferait diverger le tarif
                // affiché du tarif figé sur la réservation (PA-55).
                'tarif_base' => (string) $c->tarif_base,
            ])
            ->all();

        $unites = UniteHebergement::query()
            ->orderBy('numero')
            ->get()
            ->map(fn (UniteHebergement $u): array => [
                'id' => $u->id,
                'categorie_id' => $u->categorie_id,
                'numero' => $u->numero,
                // Le statut descend TEL QUEL, y compris `hors_service`. Le
                // filtrer ici ferait disparaître l'unité du parc local, et le
                // client ne pourrait plus dire POURQUOI elle n'est pas
                // proposée — il la présenterait comme inexistante.
                'statut' => $u->statut,
            ])
            ->all();

        return response()->json([
            'data' => [
                'categories' => $categories,
                'unites' => $unites,
            ],
        ]);
    }
}
