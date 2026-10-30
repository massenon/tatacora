<?php

declare(strict_types=1);

namespace App\Shared\ImportExport\Services;

use App\Shared\ImportExport\Data\ColonneImport;
use PhpOffice\PhpSpreadsheet\Cell\DataType;
use PhpOffice\PhpSpreadsheet\Reader\Xlsx as LecteurXlsx;
use PhpOffice\PhpSpreadsheet\Spreadsheet;
use PhpOffice\PhpSpreadsheet\Style\Alignment;
use PhpOffice\PhpSpreadsheet\Style\Fill;
use PhpOffice\PhpSpreadsheet\Style\NumberFormat;
use PhpOffice\PhpSpreadsheet\Worksheet\Worksheet;
use PhpOffice\PhpSpreadsheet\Writer\Xlsx as EcrivainXlsx;
use RuntimeException;
use Throwable;

/**
 * Le tableur d'import — UN lecteur et UN écrivain pour tous les modules à
 * import (Import & Export, Stocks), demande du PO du 30/10/2026.
 *
 * ## Pourquoi ce service existe : « toutes les colonnes dans une seule colonne »
 *
 * Les anciens modèles étaient des CSV au point-virgule. Un Excel dont le
 * séparateur de liste est la virgule (réglage régional anglais, très courant)
 * ouvre un `.csv` au point-virgule dans UNE colonne, et rien dans le fichier
 * ne permet de s'en défendre. Le modèle est donc désormais un VRAI classeur
 * `.xlsx` — une colonne = une cellule, quel que soit le réglage régional.
 *
 * ## Écriture : deux feuilles
 *
 *  - « Modèle » : en-têtes en gras (figés), largeurs, ligne(s) d'exemple ;
 *    nombres et montants en cellules NUMÉRIQUES, le reste en TEXTE (un
 *    téléphone garde son zéro de tête) ; listes fermées en menu déroulant.
 *  - « Aide » : une ligne par colonne — obligatoire ou facultative, format,
 *    valeurs admises, exemple.
 *
 * ## Lecture : par le contenu, jamais par l'extension
 *
 * Un `.xlsx` se reconnaît à sa signature ZIP (`PK`), un ancien `.xls` à sa
 * signature OLE ; tout le reste est lu comme du CSV : BOM UTF-8, UTF-16 ou
 * Windows-1252 (l'encodage d'Excel « CSV (séparateur : point-virgule) »),
 * séparateur `;` `,` ou tabulation choisi sur la première ligne, ligne
 * `sep=;` d'Excel respectée. Les en-têtes sont ensuite rapprochés PAR NOM
 * par `ControleImportService`, jamais par position.
 */
class TableurService
{
    public const FEUILLE_MODELE = 'Modèle';

    public const FEUILLE_AIDE = 'Aide';

    /** Marque de la ligne d'exemple du modèle : elle n'est jamais importée. */
    public const PREFIXE_EXEMPLE = '(exemple) ';

    /** Au-delà, le fichier n'est pas un fichier d'import : on refuse plutôt que d'attendre. */
    public const LIGNES_MAXIMUM = 5000;

    /** Hauteur de la zone de saisie couverte par la mise en forme et les listes. */
    private const ZONE_SAISIE = 1000;

    private const COULEUR_ENTETE = 'FF1B2A41';

    private const COULEUR_EXEMPLE = 'FF6B7280';

    // =====================================================================
    // Lecture
    // =====================================================================

    /**
     * @return list<list<string>> lignes brutes, la première étant l'en-tête
     *
     * @throws RuntimeException fichier illisible — le message est destiné à l'utilisateur
     */
    public function lire(string $chemin, string $nomOriginal = ''): array
    {
        $contenu = @file_get_contents($chemin);

        if ($contenu === false || $contenu === '') {
            throw new RuntimeException(__('imports.fichier.vide'));
        }

        return $this->lireContenu($contenu, $chemin, $nomOriginal);
    }

    /**
     * @return list<list<string>>
     */
    public function lireContenu(string $contenu, ?string $chemin = null, string $nomOriginal = ''): array
    {
        if (str_starts_with($contenu, "PK\x03\x04")) {
            return $this->lireXlsx($contenu, $chemin);
        }

        if (str_starts_with($contenu, "\xD0\xCF\x11\xE0")) {
            throw new RuntimeException(__('imports.fichier.xls_ancien'));
        }

        return $this->lireCsv($contenu);
    }

    /**
     * Le CSV : encodage, séparateur et guillemets, dans les tolérances d'Excel.
     *
     * @return list<list<string>>
     */
    public function lireCsv(string $contenu): array
    {
        $contenu = $this->enUtf8($contenu);
        $separateur = null;

        // `sep=;` : la première ligne qu'Excel lui-même écrit pour fixer le séparateur.
        if (preg_match('/^sep=(.)\r?\n/i', $contenu, $m) === 1) {
            $separateur = $m[1];
            $contenu = (string) substr($contenu, strlen($m[0]));
        }

        $separateur ??= $this->separateurDe($contenu);

        $flux = fopen('php://temp', 'r+');

        if ($flux === false) {
            throw new RuntimeException(__('imports.fichier.illisible'));
        }

        fwrite($flux, $contenu);
        rewind($flux);

        $tableau = [];

        while (($ligne = fgetcsv($flux, 0, $separateur, '"', '\\')) !== false) {
            // Une ligne vide n'est pas une erreur, c'est un blanc — mais sa
            // POSITION est conservée : les numéros restent ceux qu'Excel affiche.
            $tableau[] = $ligne === [null] ? [''] : array_map(static fn ($v): string => (string) $v, $ligne);
        }

        fclose($flux);

        return $tableau;
    }

    /**
     * Le séparateur d'un CSV — celui des trois (`;` `,` tabulation) que la
     * première ligne non vide emploie le plus, hors guillemets. À égalité, le
     * point-virgule : la convention francophone du dépôt (RG-19).
     */
    public function separateurDe(string $contenu): string
    {
        $contenu = ltrim($contenu, "\u{FEFF}");

        foreach (preg_split('/\r\n|\r|\n/', $contenu) ?: [] as $ligne) {
            if (trim($ligne) === '') {
                continue;
            }

            $hors = (string) preg_replace('/"[^"]*"/', '', $ligne);
            $nombres = [';' => substr_count($hors, ';'), ',' => substr_count($hors, ','), "\t" => substr_count($hors, "\t")];
            arsort($nombres);

            // `arsort` est stable depuis PHP 8 : à égalité, l'ordre de déclaration (`;` d'abord).
            return (string) array_key_first($nombres);
        }

        return ';';
    }

    /** UTF-8 sans BOM, quel que soit l'encodage d'origine d'Excel. */
    private function enUtf8(string $contenu): string
    {
        if (str_starts_with($contenu, "\xEF\xBB\xBF")) {
            return substr($contenu, 3);
        }

        if (str_starts_with($contenu, "\xFF\xFE") || str_starts_with($contenu, "\xFE\xFF")) {
            return (string) mb_convert_encoding($contenu, 'UTF-8', 'UTF-16');
        }

        if (! mb_check_encoding($contenu, 'UTF-8')) {
            // « CSV (séparateur : point-virgule) » d'Excel Windows écrit en Windows-1252.
            return (string) mb_convert_encoding($contenu, 'UTF-8', 'Windows-1252');
        }

        return $contenu;
    }

    /**
     * @return list<list<string>>
     */
    private function lireXlsx(string $contenu, ?string $chemin): array
    {
        $temporaire = null;

        try {
            if ($chemin === null || ! is_file($chemin)) {
                $temporaire = tempnam(sys_get_temp_dir(), 'imp');
                file_put_contents((string) $temporaire, $contenu);
                $chemin = (string) $temporaire;
            }

            $lecteur = new LecteurXlsx();
            $lecteur->setReadDataOnly(true);
            $lecteur->setReadEmptyCells(false);
            $classeur = $lecteur->load($chemin);

            $feuille = $classeur->getSheetByName(self::FEUILLE_MODELE) ?? $classeur->getSheet(0);

            if ($feuille->getHighestDataRow() > self::LIGNES_MAXIMUM) {
                throw new RuntimeException(__('imports.fichier.trop_long', ['maximum' => (string) self::LIGNES_MAXIMUM]));
            }

            $tableau = [];

            foreach ($feuille->toArray(null, false, false, false) as $ligne) {
                $tableau[] = array_map(fn ($v): string => $this->texteDeCellule($v), $ligne);
            }
        } catch (RuntimeException $refus) {
            throw $refus;
        } catch (Throwable) {
            throw new RuntimeException(__('imports.fichier.xlsx_illisible'));
        } finally {
            if ($temporaire !== null) {
                @unlink((string) $temporaire);
            }
        }

        // Les lignes vides de queue (mise en forme sans donnée) ne comptent pas.
        while ($tableau !== [] && array_filter(end($tableau), static fn (string $v): bool => trim($v) !== '') === []) {
            array_pop($tableau);
        }

        return array_values($tableau);
    }

    /** Un nombre de cellule redevient le texte qu'Excel affiche : « 1500 », jamais « 1500.0 ». */
    private function texteDeCellule(mixed $valeur): string
    {
        if ($valeur === null) {
            return '';
        }

        if (is_bool($valeur)) {
            return $valeur ? '1' : '0';
        }

        if (is_int($valeur)) {
            return (string) $valeur;
        }

        if (is_float($valeur)) {
            if (floor($valeur) === $valeur && abs($valeur) < 1e15) {
                return (string) (int) $valeur;
            }

            return rtrim(rtrim(sprintf('%.10F', $valeur), '0'), '.');
        }

        return is_scalar($valeur) ? trim((string) $valeur) : '';
    }

    /**
     * Rapproche les en-têtes d'un fichier des colonnes attendues PAR NOM
     * (libellé ou champ), casse, accents et espaces neutralisés — jamais par
     * position : un classeur dont l'utilisateur a déplacé ou ajouté une
     * colonne reste lisible.
     *
     * @param  list<string>  $entetes
     * @param  list<ColonneImport>  $colonnes
     * @return array<string, int> champ => index de colonne
     */
    public function indexerEntetes(array $entetes, array $colonnes): array
    {
        $carte = [];

        foreach ($entetes as $index => $entete) {
            $normalise = $this->normaliser($entete);

            if ($normalise === '') {
                continue;
            }

            foreach ($colonnes as $colonne) {
                if (! isset($carte[$colonne->champ])
                    && ($this->normaliser($colonne->libelle) === $normalise || $this->normaliser($colonne->champ) === $normalise)) {
                    $carte[$colonne->champ] = (int) $index;

                    break;
                }
            }
        }

        return $carte;
    }

    /** La ligne d'exemple du modèle : sa première cellule porte la marque « (exemple) ». */
    public function estLigneExemple(array $ligne): bool
    {
        return str_starts_with($this->normaliser((string) ($ligne[0] ?? '')), $this->normaliser(trim(self::PREFIXE_EXEMPLE)));
    }

    /** Casse, accents, espaces et signes de ponctuation neutralisés — le SENS, jamais. */
    public function normaliser(string $texte): string
    {
        $texte = mb_strtolower(trim($texte));
        $translit = transliterator_transliterate('NFD; [:Nonspacing Mark:] Remove; NFC', $texte);
        $texte = is_string($translit) ? $translit : $texte;

        return trim((string) preg_replace('/\s+/u', ' ', str_replace(["\u{00A0}", "\u{202F}"], ' ', $texte)));
    }

    // =====================================================================
    // Écriture
    // =====================================================================

    /**
     * Le classeur d'un module : feuille « Modèle » + feuille « Aide ».
     *
     * @param  list<ColonneImport>  $colonnes
     * @param  list<array<string, string|int|null>>|null  $lignes  lignes de données par `champ` ;
     *                                                              `null` : le modèle vide, avec UNE ligne d'exemple
     * @return string les octets du `.xlsx`
     */
    public function ecrireClasseur(string $nomModule, string $description, array $colonnes, ?array $lignes = null): string
    {
        $classeur = new Spreadsheet();
        $classeur->getProperties()->setCreator('LogiReStock — TATACORA AFRIQUE')->setTitle('Import — '.$nomModule);

        $modele = $classeur->getActiveSheet();
        $modele->setTitle(self::FEUILLE_MODELE);
        $this->ecrireModele($modele, $colonnes, $lignes);

        $aide = $classeur->createSheet();
        $aide->setTitle(self::FEUILLE_AIDE);
        $this->ecrireAide($aide, $nomModule, $description, $colonnes, $lignes === null);

        $classeur->setActiveSheetIndex(0);

        $chemin = (string) tempnam(sys_get_temp_dir(), 'xls');

        try {
            $ecrivain = new EcrivainXlsx($classeur);
            $ecrivain->setPreCalculateFormulas(false);
            $ecrivain->save($chemin);
            $octets = (string) file_get_contents($chemin);
        } finally {
            @unlink($chemin);
            $classeur->disconnectWorksheets();
        }

        return $octets;
    }

    /**
     * @param  list<ColonneImport>  $colonnes
     * @param  list<array<string, string|int|null>>|null  $lignes
     */
    private function ecrireModele(Worksheet $feuille, array $colonnes, ?array $lignes): void
    {
        $exemple = $lignes === null;
        $lignes ??= [array_combine(
            array_map(static fn (ColonneImport $c): string => $c->champ, $colonnes),
            array_map(
                static fn (ColonneImport $c, int $i): string => ($i === 0 ? self::PREFIXE_EXEMPLE : '').$c->exemple,
                $colonnes,
                array_keys($colonnes),
            ),
        )];

        foreach ($colonnes as $i => $colonne) {
            $indice = $i + 1;
            $lettre = \PhpOffice\PhpSpreadsheet\Cell\Coordinate::stringFromColumnIndex($indice);

            $feuille->setCellValueExplicit([$indice, 1], $colonne->libelle, DataType::TYPE_STRING);

            $largeur = max(
                mb_strlen($colonne->libelle) + 4,
                $this->largeurDesDonnees($colonne, $lignes) + 2,
                14,
            );
            $feuille->getColumnDimension($lettre)->setWidth(min(60, (float) $largeur));

            // Texte par défaut sur la zone de saisie : un téléphone ou un
            // numéro d'unité garde ses zéros de tête, une graphie « 1/2 » ne
            // devient pas une date.
            $zone = $lettre.'2:'.$lettre.self::ZONE_SAISIE;
            $numerique = $this->estNumerique($colonne);
            $feuille->getStyle($zone)->getNumberFormat()->setFormatCode(
                $numerique ? ($colonne->type === 'montant' ? '#,##0' : '0') : NumberFormat::FORMAT_TEXT,
            );

            if ($numerique) {
                $feuille->getStyle($zone)->getAlignment()->setHorizontal(Alignment::HORIZONTAL_RIGHT);
            }

            $this->poserListe($feuille, $colonne, $zone);

            foreach ($lignes as $r => $ligne) {
                $valeur = $ligne[$colonne->champ] ?? null;

                if ($valeur === null || $valeur === '') {
                    continue;
                }

                $cellule = [$indice, $r + 2];

                if ($numerique && is_numeric($valeur)) {
                    $feuille->setCellValueExplicit($cellule, $valeur + 0, DataType::TYPE_NUMERIC);
                } else {
                    $feuille->setCellValueExplicit($cellule, (string) $valeur, DataType::TYPE_STRING);
                }
            }
        }

        $derniere = \PhpOffice\PhpSpreadsheet\Cell\Coordinate::stringFromColumnIndex(max(1, count($colonnes)));
        $entete = $feuille->getStyle('A1:'.$derniere.'1');
        $entete->getFont()->setBold(true)->getColor()->setARGB('FFFFFFFF');
        $entete->getFill()->setFillType(Fill::FILL_SOLID)->getStartColor()->setARGB(self::COULEUR_ENTETE);
        $entete->getAlignment()->setVertical(Alignment::VERTICAL_CENTER)->setWrapText(true);
        $feuille->getRowDimension(1)->setRowHeight(24);
        $feuille->freezePane('A2');

        if ($exemple) {
            $style = $feuille->getStyle('A2:'.$derniere.'2');
            $style->getFont()->setItalic(true)->getColor()->setARGB(self::COULEUR_EXEMPLE);
        }
    }

    /**
     * @param  list<ColonneImport>  $colonnes
     */
    private function ecrireAide(Worksheet $feuille, string $nomModule, string $description, array $colonnes, bool $avecExemple): void
    {
        $feuille->setCellValueExplicit('A1', __('imports.xlsx.aide_titre', ['module' => $nomModule]), DataType::TYPE_STRING);
        $feuille->getStyle('A1')->getFont()->setBold(true)->setSize(14);
        $feuille->setCellValueExplicit('A2', $description, DataType::TYPE_STRING);
        $feuille->setCellValueExplicit('A3', __('imports.xlsx.aide_consigne'), DataType::TYPE_STRING);

        if ($avecExemple) {
            $feuille->setCellValueExplicit('A4', __('imports.xlsx.aide_exemple'), DataType::TYPE_STRING);
        }

        $titres = ['colonne', 'obligatoire', 'format', 'valeurs', 'exemple'];

        foreach ($titres as $i => $cle) {
            $feuille->setCellValueExplicit([$i + 1, 6], __('imports.xlsx.aide_'.($cle === 'exemple' ? 'exemple_colonne' : $cle)), DataType::TYPE_STRING);
        }

        $entete = $feuille->getStyle('A6:E6');
        $entete->getFont()->setBold(true)->getColor()->setARGB('FFFFFFFF');
        $entete->getFill()->setFillType(Fill::FILL_SOLID)->getStartColor()->setARGB(self::COULEUR_ENTETE);

        foreach ($colonnes as $i => $colonne) {
            $r = 7 + $i;
            $feuille->setCellValueExplicit([1, $r], $colonne->libelle, DataType::TYPE_STRING);
            $feuille->setCellValueExplicit([2, $r], $colonne->requis ? __('imports.xlsx.oui') : __('imports.xlsx.non'), DataType::TYPE_STRING);
            $feuille->setCellValueExplicit([3, $r], $this->formatDe($colonne), DataType::TYPE_STRING);
            $feuille->setCellValueExplicit([4, $r], $colonne->valeurs !== null ? implode(' ; ', $colonne->valeurs) : '', DataType::TYPE_STRING);
            $feuille->setCellValueExplicit([5, $r], $colonne->exemple, DataType::TYPE_STRING);
        }

        foreach (['A' => 34, 'B' => 14, 'C' => 44, 'D' => 60, 'E' => 34] as $lettre => $largeur) {
            $feuille->getColumnDimension($lettre)->setWidth($largeur);
        }

        $feuille->getStyle('A7:E'.(6 + max(1, count($colonnes))))->getAlignment()->setVertical(Alignment::VERTICAL_TOP)->setWrapText(true);
    }

    private function formatDe(ColonneImport $colonne): string
    {
        $base = $colonne->type === 'liste'
            ? __('imports.xlsx.format_liste')
            : __('imports.types.'.$colonne->type);

        return $base;
    }

    private function estNumerique(ColonneImport $colonne): bool
    {
        return $colonne->type === 'nombre' || $colonne->type === 'montant';
    }

    /**
     * @param  list<array<string, string|int|null>>  $lignes
     */
    private function largeurDesDonnees(ColonneImport $colonne, array $lignes): int
    {
        $max = 0;

        foreach ($lignes as $ligne) {
            $max = max($max, mb_strlen((string) ($ligne[$colonne->champ] ?? '')));
        }

        return $max;
    }

    /** Menu déroulant d'une liste fermée — seulement si Excel peut la porter (255 signes). */
    private function poserListe(Worksheet $feuille, ColonneImport $colonne, string $zone): void
    {
        if ($colonne->type !== 'liste' || $colonne->valeurs === null || $colonne->valeurs === []) {
            return;
        }

        $formule = '"'.str_replace('"', '""', implode(',', $colonne->valeurs)).'"';

        if (mb_strlen($formule) > 255 || in_array(true, array_map(static fn (string $v): bool => str_contains($v, ','), $colonne->valeurs), true)) {
            return;
        }

        $validation = $feuille->getCell(explode(':', $zone)[0])->getDataValidation();
        $validation->setType(\PhpOffice\PhpSpreadsheet\Cell\DataValidation::TYPE_LIST);
        $validation->setErrorStyle(\PhpOffice\PhpSpreadsheet\Cell\DataValidation::STYLE_WARNING);
        $validation->setAllowBlank(true);
        $validation->setShowDropDown(true);
        $validation->setShowErrorMessage(true);
        $validation->setErrorTitle(__('imports.xlsx.liste_titre'));
        $validation->setError(__('imports.xlsx.liste_erreur', ['valeurs' => implode(', ', $colonne->valeurs)]));
        $validation->setFormula1($formule);
        $validation->setSqref($zone);
    }
}
