<?php

declare(strict_types=1);

namespace App\Shared\ReportEngine\Services;

use App\Models\User;
use App\Shared\ReportEngine\Contracts\EtatInterface;
use App\Shared\ReportEngine\Data\DocumentGenere;
use App\Shared\ReportEngine\Models\EtatGenere;
use App\Shared\ReportEngine\Renderers\RenduCsv;
use App\Shared\ReportEngine\Renderers\RenduDocument;
use App\Shared\ReportEngine\Renderers\RenduPdf;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Orchestrateur d'édition d'état — **le seul chemin** vers un document.
 *
 * @see EF-M14-01 En-tête normalisée (RG-19)
 * @see EF-M14-03 Génération à la demande avec filtres dynamiques
 * @see EF-M14-04 Export multi-format
 * @see EF-M14-06 Archivage horodaté
 *
 * ## Ce que ce service enchaîne, et pourquoi ici plutôt qu'ailleurs
 *
 * 1. **Contrôle RBAC sur le module d'origine** — grille
 *    `RESPECT_TABLEAU_RAPPORT.md` point 8 : « les lignes retournées respectent
 *    le niveau d'accès du rôle connecté, **pas seulement l'accès à l'écran** ».
 *    Le contrôle est ici, avant `calculer()` : un état consolidé qui filtrerait
 *    après coup aurait déjà lu les données.
 * 2. **En-tête via `ReportHeaderService`** — RG-19. L'état n'y a pas accès.
 * 3. **Calcul unique**, partagé par les deux formats.
 * 4. **Rendu** dans le format demandé.
 * 5. **Archivage** dans `etats_generes` (EF-M14-06), dans la même transaction :
 *    un document remis sans trace d'archivage rendrait l'audit impossible.
 *
 * Aucun contrôleur ne compose ces étapes lui-même. C'est ce qui rend
 * inatteignable la non-conformité n°1 de `RESPECT_TABLEAU_RAPPORT.md` §4.
 */
class GenerateurEtatService
{
    /** Niveau RBAC minimal pour éditer un état : la consultation suffit. */
    private const NIVEAU_MINIMAL = ['C', 'L'];

    public function __construct(
        private readonly ReportHeaderService $entetes,
    ) {
    }

    /**
     * @param  array<string, string>  $filtres
     *
     * @throws RuntimeException si le rôle connecté n'a pas accès au module source
     */
    public function generer(
        EtatInterface $etat,
        array $filtres = [],
        string $format = 'pdf',
        ?User $auteur = null,
    ): DocumentGenere {
        $auteur ??= Auth::user();

        $this->verifierAcces($etat, $auteur);

        $resultat = $etat->calculer($filtres);

        $entete = $this->entetes->genererEnTete(
            typeRapport: $etat->libelle($filtres),
            periode: $etat->periode($filtres),
            auteur: $auteur,
        );

        $moteur = $this->moteur($format);
        $contenu = $moteur->rendre($entete, $resultat);

        // Archivage et remise du document sont solidaires : un document remis
        // sans trace serait invérifiable a posteriori (EF-M14-06).
        $archive = DB::transaction(fn (): EtatGenere => EtatGenere::create([
            'module' => $etat->module(),
            'nom_etat' => $etat->libelle($filtres),
            // Les filtres *réellement* appliqués, tels que l'état les a reçus.
            'filtres_appliques' => $resultat->filtresAppliques ?: $filtres,
            'utilisateur_id' => $auteur?->id,
            'date_edition' => now(),
            'format' => $moteur->format(),
            // Chemin d'archive physique : non implémenté (PA-48). `null` plutôt
            // qu'un chemin fictif — une colonne renseignée vers un fichier
            // inexistant est pire qu'une colonne vide.
            'chemin_fichier_archive' => null,
        ]));

        return new DocumentGenere(
            contenu: $contenu,
            nomFichier: $this->nomFichier($etat, $filtres, $moteur),
            typeMime: $moteur->typeMime(),
            entete: $entete,
            resultat: $resultat,
            archiveId: $archive->id,
        );
    }

    /**
     * Grille `RESPECT_TABLEAU_RAPPORT.md` point 8.
     *
     * Un état consolidé ne doit pas fuiter une donnée d'un module auquel
     * l'utilisateur n'a pas accès, **même agrégée** : un total de masse
     * salariale renseigne sur les salaires sans les détailler.
     */
    private function verifierAcces(EtatInterface $etat, ?User $auteur): void
    {
        if ($auteur === null || ! $auteur->estActif()) {
            throw new RuntimeException(__('auth.requise'));
        }

        if (! in_array($auteur->niveauSurModule($etat->module()), self::NIVEAU_MINIMAL, true)) {
            throw new RuntimeException(__('auth.module_refuse'));
        }
    }

    private function moteur(string $format): RenduDocument
    {
        return match ($format) {
            'pdf' => new RenduPdf(),
            'excel', 'csv' => new RenduCsv(),
            default => throw new RuntimeException(__('rapports.format_inconnu', ['format' => $format])),
        };
    }

    /**
     * @param  array<string, string>  $filtres
     */
    private function nomFichier(EtatInterface $etat, array $filtres, RenduDocument $moteur): string
    {
        $base = str($etat->libelle($filtres))->ascii()->slug('-')->value();

        return sprintf('%s-%s.%s', $base, now()->format('Ymd-His'), $moteur->extension());
    }
}
