<?php

declare(strict_types=1);

namespace App\Shared\ReportEngine\Data;

use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * Document produit par `GenerateurEtatService` — contenu binaire, plus ce qui
 * a servi à le produire.
 *
 * L'en-tête et le résultat sont conservés dans l'objet pour que les tests
 * puissent vérifier RG-19 sans réouvrir un PDF : la grille
 * `RESPECT_TABLEAU_RAPPORT.md` (point 13) exige « au moins un test vérifiant
 * que l'en-tête est identique à celle d'un autre état déjà conforme », ce qui
 * suppose de pouvoir la comparer autrement qu'en lisant des octets compressés.
 */
final readonly class DocumentGenere
{
    public function __construct(
        public string $contenu,
        public string $nomFichier,
        public string $typeMime,
        public EnTeteRapport $entete,
        public EtatResultat $resultat,
        public string $archiveId,
    ) {
    }

    public function telecharger(): StreamedResponse
    {
        return response()->streamDownload(
            function (): void {
                echo $this->contenu;
            },
            $this->nomFichier,
            ['Content-Type' => $this->typeMime],
        );
    }
}
