<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa\Concerns;

use Livewire\Features\SupportTesting\Testable;

/**
 * Lire RÉELLEMENT le document qu'une action Livewire a fait télécharger.
 *
 * Extrait de `BarPwaTest` le 03/09/2026, quand `RestaurantPwaTest` a eu besoin
 * des deux mêmes outils pour ses cas d'export. Les recopier aurait fait deux
 * décompresseurs de PDF : le jour où l'un serait corrigé, l'autre déclarerait
 * « absente » une chaîne que le document porte — un contrôle vert à l'envers,
 * ce qui est pire qu'un contrôle rouge.
 *
 * C'est la règle du dépôt appliquée aux tests : « le code livré a été
 * réellement exécuté, pas seulement relu ». Un `assertFileDownloaded()` seul
 * ne dit rien du CONTENU — un PDF d'une page blanche le passe.
 */
trait LitUnDocumentTelecharge
{
    /**
     * Les octets réellement téléchargés, jamais un simple « il y a eu un
     * téléchargement ».
     *
     * @param  Testable<\Livewire\Component>  $composant
     */
    private function contenuTelecharge(Testable $composant): string
    {
        $composant->assertFileDownloaded();

        // `effects` est un attribut dynamique du testeur Livewire, invisible
        // a l'analyse statique — lu via le meme chemin, type a la main.
        /** @var array<string, mixed> $effets */
        $effets = $composant->__get('effects');

        $this->assertArrayHasKey('download', $effets, 'Aucun document produit.');

        return (string) base64_decode((string) $effets['download']['content'], true);
    }

    /**
     * Le texte lisible d'un PDF dompdf, décompressé flux par flux.
     *
     * dompdf compresse ses flux : chercher une chaîne dans les octets bruts
     * répondrait « absente » sur un document qui la porte, et le contrôle
     * serait vert à l'envers.
     *
     * ⚠ Le texte rendu porte la casse APPLIQUÉE par le gabarit : une entête en
     * `text-transform: uppercase` sort en majuscules dans le flux. Comparer un
     * entête en minuscules serait rouge sur un document correct.
     */
    private function texteDuPdf(string $pdf): string
    {
        $texte = '';

        if (preg_match_all('/stream\r?\n(.*?)endstream/s', $pdf, $flux) === false) {
            return $texte;
        }

        foreach ($flux[1] as $brut) {
            $clair = @gzuncompress($brut);
            $texte .= $clair === false ? $brut : $clair;
        }

        return $texte;
    }

    /**
     * Un montant tel qu'il est ÉCRIT dans le flux d'un PDF dompdf.
     *
     * ⚠ Le séparateur de milliers de `MontantFcfa` est U+00A0, deux octets en
     * UTF-8 (`C2 A0`) ; les polices de base d'un PDF sont encodées en WinAnsi,
     * où le même caractère tient sur UN octet (`A0`). Comparer la chaîne PHP
     * telle quelle répondrait « absent » sur un document qui porte le montant,
     * et le contrôle serait vert à l'envers — exactement le piège que
     * `texteDuPdf()` existe pour éviter sur la compression.
     *
     * C'est aussi le pendant de `SeparateurDesMontantsDansLesPdfTest` : U+202F
     * n'a AUCUN glyphe en WinAnsi et sortait « ? » sur le papier remis
     * (constat du Product Owner, 02/09/2026). U+00A0, lui, existe bien —
     * encore faut-il le chercher sous sa forme d'un seul octet.
     */
    private function montantDansUnPdf(string $montant): string
    {
        return str_replace(
            \App\Pwa\Support\MontantFcfa::SEPARATEUR,
            "\xA0",
            \App\Pwa\Support\MontantFcfa::format($montant),
        );
    }
}
