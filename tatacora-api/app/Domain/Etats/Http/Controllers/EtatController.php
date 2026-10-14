<?php

declare(strict_types=1);

namespace App\Domain\Etats\Http\Controllers;

use App\Domain\Etats\Http\Requests\GenererEtatRequest;
use App\Domain\Etats\Services\CatalogueEtatsService;
use App\Shared\ReportEngine\Models\EtatGenere;
use App\Shared\ReportEngine\Services\GenerateurEtatService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use RuntimeException;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * Hub États & Rapports — M14.
 *
 * @see EF-M14-02 Bibliothèque d'états standards
 * @see EF-M14-03 Génération à la demande avec filtres dynamiques
 * @see EF-M14-04 Export multi-format
 * @see EF-M14-06 Archivage horodaté
 *
 * Simple orchestrateur (`06_DEVELOPMENT_STANDARDS.md` §2.2). Il ne construit
 * **aucune** en-tête et ne rend **aucun** document : `RESPECT_TABLEAU_RAPPORT.md`
 * §4 identifie précisément le contrôleur comme le lieu où la duplication
 * d'en-tête s'introduit.
 */
class EtatController
{
    public function __construct(
        private readonly CatalogueEtatsService $catalogue,
        private readonly GenerateurEtatService $generateur,
    ) {
    }

    /**
     * Catalogue filtré par les droits réels du rôle connecté — EF-M14-02.
     */
    public function index(Request $request): JsonResponse
    {
        return response()->json([
            'data' => $this->catalogue->pourUtilisateur($request->user()),
        ]);
    }

    /**
     * Édite un état et le renvoie en téléchargement — EF-M14-03/04.
     *
     * Le document part en flux plutôt qu'en JSON encodé : un grand livre
     * annuel en base64 dans une réponse JSON doublerait sa taille en mémoire,
     * sur un hébergement mutualisé déjà signalé comme contraint
     * (`CPANEL_DEPLOYMENT.md` §8).
     */
    public function generer(GenererEtatRequest $request): StreamedResponse|JsonResponse
    {
        $valide = $request->validated();

        try {
            $document = $this->generateur->generer(
                etat: $this->catalogue->resoudre($valide['etat']),
                filtres: $valide['filtres'] ?? [],
                format: $valide['format'] ?? 'pdf',
                auteur: $request->user(),
            );
        } catch (RuntimeException $e) {
            // Refus RBAC ou format invalide : 403 plutôt qu'un 500. Le message
            // est déjà traduit et destiné à l'utilisateur.
            return response()->json(['message' => $e->getMessage()], 403);
        }

        return $document->telecharger();
    }

    /**
     * Journal des états édités — EF-M14-06.
     *
     * Consultation restreinte au module M14 par la route : savoir qui a édité
     * quel état, et avec quels filtres, est une information d'audit.
     */
    public function archives(Request $request): JsonResponse
    {
        $archives = EtatGenere::query()
            ->when($request->filled('module'), fn ($q) => $q->where('module', $request->string('module')))
            ->with('utilisateur:id,login')
            ->orderByDesc('date_edition')
            ->paginate(50);

        return response()->json([
            'data' => $archives->through(fn (EtatGenere $etat): array => [
                'id' => $etat->id,
                'module' => $etat->module,
                'nom_etat' => $etat->nom_etat,
                'filtres_appliques' => $etat->filtres_appliques,
                'format' => $etat->format,
                'date_edition' => $etat->date_edition->toIso8601String(),
                'utilisateur' => $etat->utilisateur?->login,
                // Toujours null à ce jour — l'archivage physique n'est pas
                // implémenté (PA-48). Exposé tel quel plutôt que masqué : un
                // auditeur doit voir que le fichier n'est pas conservé.
                'fichier_archive' => $etat->chemin_fichier_archive,
            ])->items(),
            'meta' => [
                'total' => $archives->total(),
                'par_page' => $archives->perPage(),
                'page' => $archives->currentPage(),
            ],
        ]);
    }
}
