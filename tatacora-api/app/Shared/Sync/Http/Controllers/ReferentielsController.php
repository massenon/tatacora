<?php

declare(strict_types=1);

namespace App\Shared\Sync\Http\Controllers;

use App\Models\User;
use App\Shared\Sync\Http\Requests\TelechargerReferentielsRequest;
use App\Shared\Sync\Services\CatalogueDescendantService;
use App\Shared\Sync\Services\SuiviPostesService;
use App\Shared\Sync\Support\PosteDuJeton;
use Illuminate\Http\JsonResponse;
use InvalidArgumentException;

/**
 * Téléchargement du catalogue par les postes — `GET /api/v1/referentiels`.
 *
 * Décision du Product Owner du 15/10/2026 : le serveur est MAÎTRE du
 * catalogue, les postes le téléchargent (mêmes identifiants partout) ; un
 * poste qui crée hors connexion pousse par `POST /api/v1/sync`, où le serveur
 * fusionne sur la clé naturelle. Toute la logique est dans
 * `CatalogueDescendantService` ; ce contrôleur vérifie l'identité du poste
 * et met en forme.
 *
 * ## Requête
 *
 * `GET /api/v1/referentiels?poste_id={poste}&depuis={curseur}&limite={n}`
 * - `poste_id` (obligatoire) : le nom du poste porté par le jeton — sinon 403
 *   `sync.poste_non_reconnu` (même règle que `/sync`, `PosteDuJeton`) ;
 * - `depuis` (facultatif) : le curseur OPAQUE rendu par la réponse
 *   précédente. Absent : depuis le début. Illisible : 422 ;
 * - `limite` (facultatif) : taille de page, 200 par défaut, 500 au plus.
 *
 * ## Réponse 200
 *
 * ```json
 * {
 *   "data": {
 *     "elements": [
 *       {
 *         "table": "articles",
 *         "id": "uuid serveur",
 *         "actif": true,
 *         "modifie_le": "2026-10-15 08:00:00",
 *         "donnees": { "libelle": "Riz", "unite_mesure": "kg", "seuil_alerte": "10.00", ... }
 *       }
 *     ],
 *     "correspondances": [
 *       { "table": "fournisseurs", "id_poste": "uuid du poste", "id_serveur": "uuid serveur" }
 *     ]
 *   },
 *   "meta": { "curseur": "…", "complet": true, "limite": 200 }
 * }
 * ```
 *
 * - `elements` : dans l'ordre des tables `points_stockage`, `articles`,
 *   `cartes_boisson`, `menus`, `recettes` (avec `donnees.lignes`, la
 *   composition), `plats`, `categories_hebergement`, `unites_hebergement`,
 *   `fournisseurs`, `centres_cout` — un élément cité avant celui qui le cite —,
 *   puis, dans chaque table, par (`modifie_le`, `id`). Seules les tables dont
 *   l'utilisateur LIT le module descendent. Les colonnes sont celles de
 *   `CatalogueDescendantService::COLONNES` : des définitions, jamais un stock,
 *   un coût moyen ou un coût matière (calculés). Montants et quantités en
 *   chaînes décimales.
 * - `actif: false` : élément ARCHIVÉ (article, fournisseur, unité
 *   `hors_service`) — il descend quand même, rien ne disparaît du flux.
 * - `correspondances` : les fusions de CE poste (UUID local → UUID serveur),
 *   pour remapper ce qu'un `fusionne_avec` perdu n'a pas remappé.
 * - `meta.complet` : `false` → rappeler aussitôt avec `depuis = meta.curseur` ;
 *   `true` → le poste est à jour, il CONSERVE `meta.curseur` pour la
 *   prochaine fois. Un élément modifié depuis repassera (upsert par `id`).
 *
 * ## Refus
 *
 * 401 sans jeton ou compte inactif, 403 poste non reconnu, 422 paramètre ou
 * curseur invalide.
 */
class ReferentielsController
{
    public function __construct(
        private readonly CatalogueDescendantService $catalogue,
        private readonly SuiviPostesService $suivi,
    ) {
    }

    public function __invoke(TelechargerReferentielsRequest $request): JsonResponse
    {
        $valide = $request->validated();

        /** @var User $utilisateur */
        $utilisateur = $request->user();

        if (! $utilisateur->estActif()) {
            return response()->json(['message' => __('sync.referentiels.compte_inactif')], 401);
        }

        if (! PosteDuJeton::concorde($request, $valide['poste_id'])) {
            return response()->json(['message' => __('sync.poste_non_reconnu')], 403);
        }

        $limite = (int) ($valide['limite'] ?? CatalogueDescendantService::TAILLE_PAGE_DEFAUT);

        try {
            $page = $this->catalogue->page($utilisateur, $valide['poste_id'], $valide['depuis'] ?? null, $limite);
        } catch (InvalidArgumentException $e) {
            return response()->json([
                'message' => $e->getMessage(),
                'errors' => ['depuis' => [$e->getMessage()]],
            ], 422);
        }

        // Bouton « Synchroniser » (18/10/2026) : la PWA montre la dernière
        // descente de chaque poste et la file qu'il déclare.
        $this->suivi->noterDescente(
            $valide['poste_id'],
            $utilisateur,
            isset($valide['en_attente']) ? (int) $valide['en_attente'] : null,
        );

        return response()->json([
            'data' => [
                'elements' => $page['elements'],
                'correspondances' => $page['correspondances'],
            ],
            'meta' => [
                'curseur' => $page['curseur'],
                'complet' => $page['complet'],
                'limite' => $limite,
            ],
        ]);
    }
}
