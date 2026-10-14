<?php

declare(strict_types=1);

namespace App\Shared\ReportEngine\Renderers;

use App\Shared\ReportEngine\Data\EnTeteRapport;
use App\Shared\ReportEngine\Data\EtatResultat;

/**
 * Rendu tableur — EF-M14-04 (« Export multi-format (PDF, Excel/CSV) »).
 *
 * ## CSV et non `.xlsx`, délibérément
 *
 * L'EF admet les deux. `CPANEL_DEPLOYMENT.md` §8 alerte sur la mémoire en
 * hébergement mutualisé : PhpSpreadsheet charge le classeur entier en mémoire
 * et dépasse couramment les limites d'un mutualisé sur quelques milliers de
 * lignes — exactement le volume d'un grand livre annuel. Le CSV s'écrit en
 * flux, à mémoire constante.
 *
 * Le format `etats_generes.format` reste `excel` : c'est l'`enum` du schéma
 * (`FULL_MIGRATIONS_DATABASE_PART3.md` §19), qui décrit l'intention d'usage,
 * pas l'extension du fichier.
 *
 * ## Le BOM n'est pas un détail
 *
 * Sans marque d'ordre d'octets, Excel sous Windows lit un CSV en codage ANSI :
 * « Réception » devient « RÃ©ception » sur toutes les lignes. Les libellés du
 * système sont en français accentué — le BOM est donc obligatoire ici, pas une
 * précaution optionnelle.
 *
 * Le séparateur est le **point-virgule** : en locale française, Excel attend
 * celui-là, et la virgule est déjà le séparateur décimal.
 */
class RenduCsv implements RenduDocument
{
    private const BOM_UTF8 = "\u{FEFF}";

    private const SEPARATEUR = ';';

    public function format(): string
    {
        return 'excel';
    }

    public function extension(): string
    {
        return 'csv';
    }

    public function typeMime(): string
    {
        return 'text/csv; charset=UTF-8';
    }

    public function rendre(EnTeteRapport $entete, EtatResultat $etat): string
    {
        $flux = fopen('php://temp', 'r+');

        if ($flux === false) {
            throw new \RuntimeException(__('rapports.flux_indisponible'));
        }

        // RG-19 s'applique aussi au tableur : un export Excel sans en-tête
        // normalisée circulerait sans identifier son émetteur ni sa période.
        foreach ($this->lignesEnTete($entete) as $ligne) {
            fputcsv($flux, $ligne, self::SEPARATEUR);
        }

        fputcsv($flux, [], self::SEPARATEUR);

        foreach ($etat->kpis as $libelle => $valeur) {
            fputcsv($flux, [$libelle, $valeur], self::SEPARATEUR);
        }

        if ($etat->kpis !== []) {
            fputcsv($flux, [], self::SEPARATEUR);
        }

        fputcsv($flux, $etat->entetes, self::SEPARATEUR);

        foreach ($etat->lignes as $ligne) {
            fputcsv($flux, $ligne, self::SEPARATEUR);
        }

        if ($etat->estVide()) {
            fputcsv($flux, [__('rapports.aucune_donnee')], self::SEPARATEUR);
        }

        rewind($flux);
        $contenu = (string) stream_get_contents($flux);
        fclose($flux);

        return self::BOM_UTF8 . $contenu;
    }

    /**
     * @return list<list<string>>
     */
    private function lignesEnTete(EnTeteRapport $entete): array
    {
        $lignes = [
            [$entete->raisonSociale],
            [str_replace("\n", ' — ', $entete->sousTitre)],
            [$entete->adresse],
            [$entete->telephone . ' — ' . $entete->email],
            [$entete->siteWeb],
        ];

        foreach ($entete->mentionsLegales() as $intitule => $valeur) {
            $lignes[] = [$intitule . ' : ' . $valeur];
        }

        return [
            ...$lignes,
            [$entete->typeRapport, $entete->periode],
            [__('rapports.entete.genere_par', ['auteur' => $entete->auteur])],
            [__('rapports.entete.edite_le', ['date' => $entete->dateEdition])],
            [$entete->mentionInstitutionnelle],
        ];
    }
}
