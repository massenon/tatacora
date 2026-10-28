<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa\Conformite;

use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Les PDF d'EXPORT tiennent la Directive §6 — décision du Product Owner du
 * 11/09/2026 (PA-192) : en-tête institutionnel (RG-19), zone de signatures,
 * pied de rapport.
 *
 * ## Pourquoi une garde, et pourquoi sur le SOURCE
 *
 * Mesuré le 11/09/2026 : sur vingt-quatre gabarits, cinq seulement prenaient
 * l'identité de l'établissement à `ReportHeaderService` ; dix-neuf écrivaient
 * « TATACORA AFRIQUE » à la main ou n'avaient aucune identité — la
 * non-conformité n° 1 de `RESPECT_TABLEAU_RAPPORT.md` §4, à l'échelle de
 * presque tous les exports. Chaque écran a ses propres cas de rendu ; cette
 * garde vérifie la PROPRIÉTÉ commune, gabarit par gabarit, pour qu'un export
 * ajouté ou réécrit demain ne revienne pas à une en-tête recopiée.
 *
 * ## Deux registres FERMÉS
 *
 * Les exports (la directive s'y applique) et les documents REMIS À UN CLIENT
 * (facture, ticket, relevé, confirmation, bulletin, fiche des prix), qui ne
 * portent jamais de visa : un « Visa Ordonnateur » sur un papier client
 * ferait croire à une pièce d'ordonnancement interne. Un gabarit absent des
 * deux registres fait échouer la garde — il faut décider de quel côté il
 * est, pas le laisser hors mesure.
 *
 * @see RG-19 Entête normalisée obligatoire sur tout état édité
 */
final class PdfExportConformiteTest extends TestCase
{
    /** Les PDF produits par un export — la Directive §6 s'y applique. */
    private const EXPORTS = [
        'achats',
        'approvisionnement-bon',
        'carte',
        'carte-ventes',
        'clients-creances',
        'comptabilite-etats-cloture',
        'comptabilite-journal-rapport',
        'dashboard-rapport',
        'depenses-rapport',
        'facturation-registre',
        'fiche-stock',
        'fournisseurs-liste',
        'hebergement',
        'inventaire-rapport',
        'locations',
        'notifications',
        'paie',
        'stocks-etat',
        'tourisme',
        'ventes-rapport',
    ];

    /**
     * Les documents REMIS À UN CLIENT ou d'un autre régime (pièces fiscales,
     * bulletin de paie, affichage au comptoir) — hors Directive §6.
     */
    private const HORS_EXPORT = [
        'facture-mecef',
        'facture-ticket',
        'fiche-prix',
        // Reçu de location (M8) remis au client, 28/10/2026 : ni visa ni pied de rapport.
        'location-recu',
        'paie-bulletin',
        'releve-client',
    ];

    #[Test]
    public function chaque_gabarit_est_classe_d_un_cote_ou_de_l_autre(): void
    {
        $gabarits = array_map(
            static fn (string $chemin): string => basename($chemin, '.blade.php'),
            glob(resource_path('views/pdf/*.blade.php')) ?: [],
        );

        // Prouvé NON VIDE : un dossier renommé rendrait la garde verte à vide.
        $this->assertGreaterThanOrEqual(20, count($gabarits));

        $nonClasses = array_values(array_diff($gabarits, self::EXPORTS, self::HORS_EXPORT));
        $this->assertSame(
            [],
            $nonClasses,
            'Gabarit PDF non classé : décidez s\'il est un EXPORT (Directive §6) ou un document client.',
        );
    }

    #[Test]
    #[DataProvider('exports')]
    public function un_export_porte_l_en_tete_rg19_le_pied_et_les_signatures(string $gabarit): void
    {
        $source = $this->source($gabarit);

        $this->assertStringContainsString(
            "@include('pdf.partials.entete-rapport')",
            $source,
            "« {$gabarit} » : l'en-tête RG-19 (`ReportHeaderService`) manque.",
        );
        $this->assertStringContainsString(
            "@include('pdf.partials.pied-rapport')",
            $source,
            "« {$gabarit} » : le pied de rapport (mention institutionnelle, édition, pagination) manque.",
        );
        $this->assertStringContainsString(
            "@include('pdf.partials.signatures'",
            $source,
            "« {$gabarit} » : la zone de signatures de la Directive §6 manque.",
        );
    }

    /**
     * TOUS les gabarits, documents client compris : c'est sur eux que la
     * dérive a été trouvée — le relevé client imprimait un second numéro de
     * téléphone que les paramètres ne portent pas, et un pied au nom d'un
     * autre produit (PA-194).
     */
    #[Test]
    #[DataProvider('tousLesGabarits')]
    public function aucun_gabarit_n_ecrit_l_identite_a_la_main(string $gabarit): void
    {
        // L'identité vient de `ReportHeaderService` : écrite ici, elle
        // divergerait à la première correction de l'adresse ou de l'IFU.
        $rendu = $this->sansCommentaires($this->source($gabarit));

        foreach (['TATACORA AFRIQUE', 'Sountichirantikou', '01 42 27 81 66', '01 97 35 59 74', 'LogiRestock'] as $fragment) {
            $this->assertStringNotContainsString(
                $fragment,
                $rendu,
                "« {$gabarit} » écrit encore l'identité de l'établissement à la main (« {$fragment} »).",
            );
        }
    }

    #[Test]
    #[DataProvider('horsExport')]
    public function un_document_client_ne_porte_aucun_visa(string $gabarit): void
    {
        $this->assertStringNotContainsString(
            "@include('pdf.partials.signatures'",
            $this->source($gabarit),
            "« {$gabarit} » est remis à un client : un visa d'ordonnancement n'y a pas sa place.",
        );
    }

    /** @return iterable<string, array{string}> */
    public static function exports(): iterable
    {
        foreach (self::EXPORTS as $gabarit) {
            yield $gabarit => [$gabarit];
        }
    }

    /** @return iterable<string, array{string}> */
    public static function tousLesGabarits(): iterable
    {
        yield from self::exports();
        yield from self::horsExport();
    }

    /** @return iterable<string, array{string}> */
    public static function horsExport(): iterable
    {
        foreach (self::HORS_EXPORT as $gabarit) {
            yield $gabarit => [$gabarit];
        }
    }

    private function source(string $gabarit): string
    {
        $chemin = resource_path("views/pdf/{$gabarit}.blade.php");
        $this->assertFileExists($chemin);

        return (string) file_get_contents($chemin);
    }

    /** Les commentaires Blade peuvent citer l'ancienne en-tête : seul le rendu compte. */
    private function sansCommentaires(string $source): string
    {
        return (string) preg_replace('/\{\{--.*?--\}\}/s', '', $source);
    }
}
