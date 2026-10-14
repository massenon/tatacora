<?php

declare(strict_types=1);

namespace App\Shared\ReportEngine\Renderers;

use App\Shared\ReportEngine\Data\EnTeteRapport;
use App\Shared\ReportEngine\Data\EtatResultat;
use Barryvdh\DomPDF\Facade\Pdf;

/**
 * Rendu PDF — EF-M14-04.
 *
 * ## Choix de dompdf, et pourquoi ce n'était pas un choix libre
 *
 * **Aucune bibliothèque PDF PHP n'est spécifiée dans la collection** : le
 * prototype utilise jsPDF, qui est du JavaScript côté navigateur et n'a pas
 * d'équivalent serveur. La décision revenait donc à l'implémentation, sous une
 * contrainte de déploiement documentée.
 *
 * `CPANEL_DEPLOYMENT.md` §8 signale la génération PDF comme point de vigilance
 * mémoire sur hébergement mutualisé. Or l'hébergement mutualisé cPanel
 * n'autorise pas l'exécution de binaires externes : cela élimine
 * `wkhtmltopdf`/snappy, qui en dépendent. **dompdf est du PHP pur** et
 * fonctionne sans binaire — c'est la seule famille de solutions compatible avec
 * la cible de déploiement retenue (ADR-000).
 *
 * Décision tracée en PA-47 pour arbitrage de l'Architecte : elle est
 * réversible sans toucher aux états, puisque tout passe par `RenduDocument`.
 *
 * ## Le HTML est le format pivot
 *
 * Le gabarit Blade `rapports.document` est partagé avec l'affichage écran.
 * Changer de moteur PDF ne demanderait donc que de remplacer cette classe,
 * pas de réécrire la mise en page de chaque état.
 */
class RenduPdf implements RenduDocument
{
    public function format(): string
    {
        return 'pdf';
    }

    public function extension(): string
    {
        return 'pdf';
    }

    public function typeMime(): string
    {
        return 'application/pdf';
    }

    public function rendre(EnTeteRapport $entete, EtatResultat $etat): string
    {
        return Pdf::loadView('rapports.document', [
            'entete' => $entete,
            'etat' => $etat,
        ])
            // Portrait par défaut ; au-delà de 6 colonnes un état devient
            // illisible en A4 portrait, la bascule est automatique plutôt que
            // laissée à chaque état (qui l'oublierait).
            ->setPaper('a4', count($etat->entetes) > 6 ? 'landscape' : 'portrait')
            ->output();
    }
}
