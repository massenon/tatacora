<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use PHPUnit\Framework\Attributes\Test;
use ReflectionClass;
use Tests\TestCase;

/**
 * TOUT MESSAGE DE SUCCES FLASHE ATTEINT REELLEMENT UN ECRAN.
 *
 * ## Le defaut que cette garde ferme (03/09/2026)
 *
 * `session()->flash('pwa-succes', ...)` depose un message ; c'est la VUE qui
 * le rend. Les deux moities etaient ecrites separement, sans que rien ne les
 * confronte — et TROIS ecrans flashaient dans le vide :
 *
 *   - `Comptabilite\Hub::cloturerExercice()` — « Exercice cloture » ;
 *   - `Transverse\ContactEditeur` — « Message envoye », « Bug signale » ;
 *   - `Transverse\MonProfil` — « Mot de passe mis a jour ».
 *
 * Le geste s'executait, la base etait ecrite, l'ecran restait muet. Le plus
 * grave est la cloture d'exercice : une operation comptable IRREVERSIBLE dont
 * la confirmation se perdait, ce qui invite a la refaire.
 *
 * ## Pourquoi aucun test existant ne pouvait le voir
 *
 * Un test qui appelle l'action et lit `session('pwa-succes')` passe au VERT :
 * le flash a bien eu lieu. Le manque etait au RENDU, c'est-a-dire dans le seul
 * endroit qu'aucun de ces tests ne regardait. C'est la famille PA-59/60/61
 * prise dans son sens inverse — non pas un indicateur qui affirme sans
 * verifier, mais une verite qui n'atteint jamais l'ecran.
 *
 * ## Ce que cette garde compare, et ce qu'elle ne pretend pas
 *
 * Elle confronte deux ensembles : les composants dont le CODE flashe
 * `pwa-succes` (directement, ou via `terminerFormulaire()` du trait
 * `FormulaireModal`, qui le fait pour eux), et les vues qui le RENDENT. Elle
 * ne verifie pas qu'un message donne s'affiche dans un cas donne : elle
 * verifie que le chemin existe. C'est le prix du contrat, et il est ecrit ici
 * plutot que suppose.
 *
 * Elle accepte les DEUX formes de rendu en place — le bandeau et le toast
 * flottant — parce que la forme est un choix d'ecran (un comptoir de vente ne
 * lit pas comme un formulaire), jamais un contrat. Ce qui compte est qu'un
 * chemin existe.
 *
 * @see resources/views/pwa/partials/toast-succes.blade.php
 * @see LARAVEL_PWA.md §5
 */
final class ToastDeSuccesRenduTest extends TestCase
{
    private const CLE = 'pwa-succes';

    /**
     * Les composants dont la vue n'est PAS une page a elle seule.
     *
     * `ComposePanier` est une classe de base partagee par les deux points de
     * vente : elle n'a pas de vue propre, ses descendants en ont une. Une
     * entree ici se justifie par la structure, jamais par un rendu manquant.
     *
     * @var list<string>
     */
    private const SANS_VUE_PROPRE = [
        'ComposePanier',
        'PageMetier',
        'PageTransverse',
        'PageComptabilite',
    ];

    #[Test]
    public function tout_composant_qui_flashe_un_succes_a_une_vue_qui_le_rend(): void
    {
        $vuesQuiRendent = $this->vuesQuiRendent();

        // Plancher : sans lui, un repertoire renomme viderait le balayage,
        // qui passerait au vert sans avoir rien mesure — le defaut meme que
        // cette garde protege.
        $this->assertGreaterThanOrEqual(
            15,
            count($vuesQuiRendent),
            'Seules '.count($vuesQuiRendent).' vues PWA rendent `'.self::CLE.'`, contre 22 mesurees '
            .'le 03/09/2026. Le balayage des vues est devenu creux, donc vert.',
        );

        $defauts = [];
        $composantsRelus = 0;

        foreach ($this->composantsQuiFlashent() as $classe => $chemin) {
            $composantsRelus++;

            $court = (new ReflectionClass($classe))->getShortName();

            if (in_array($court, self::SANS_VUE_PROPRE, true)) {
                continue;
            }

            $vues = $this->vuesDe($classe);

            if ($vues === []) {
                $defauts[] = "$court flashe `".self::CLE."` mais aucune vue `pwa.*` n'a pu "
                    .'etre determinee depuis son `render()` : la garde ne peut rien prouver, '
                    .'ce qui est pire qu un echec.';

                continue;
            }

            // UNE SEULE suffit : un composant peut rendre plusieurs vues (un
            // onglet, un ecran de repli), et le message n'a de sens que la ou
            // le geste se fait. Exiger les deux reprocherait a un ecran
            // correct de ne pas confirmer sur une page ou rien n'est ecrit.
            $rendues = array_values(array_intersect($vues, $vuesQuiRendent));

            if ($rendues === []) {
                $defauts[] = "$court flashe `".self::CLE."` et AUCUNE de ses vues ne le rend ("
                    .implode(', ', $vues).') : le geste a lieu, la base est ecrite, et '
                    ."l utilisateur ne voit rien. Ajoutez `@include('pwa.partials.toast-succes')`.";
            }
        }

        $this->assertSame([], $defauts, implode("\n", $defauts));

        $this->assertGreaterThanOrEqual(
            15,
            $composantsRelus,
            "Seuls $composantsRelus composants PWA relus. Le filtre s est elargi au point "
            .'de vider le balayage.',
        );
    }

    /**
     * Les composants dont le code flashe la cle — directement, ou par le
     * delegue `terminerFormulaire()` du trait `FormulaireModal`.
     *
     * Le delegue est derive PAR REFLEXION, jamais liste : si son corps cessait
     * de flasher, tous ses appelants sortiraient de cet ensemble d eux-memes,
     * et cette garde cesserait de les exiger — ce qui est exactement ce qu il
     * faudrait.
     *
     * @return array<class-string, string>
     */
    private function composantsQuiFlashent(): array
    {
        $delegueFlashe = str_contains(
            (string) file_get_contents(app_path('Pwa/Livewire/Concerns/FormulaireModal.php')),
            "session()->flash('".self::CLE."'",
        );

        $trouves = [];

        foreach ($this->fichiersDeComposants() as $chemin) {
            $source = (string) file_get_contents($chemin);

            $flasheDirect = str_contains($source, "flash('".self::CLE."'");
            $flasheParDelegue = $delegueFlashe && str_contains($source, '$this->terminerFormulaire(');

            if (! $flasheDirect && ! $flasheParDelegue) {
                continue;
            }

            $classe = $this->classeDe($chemin);

            if (class_exists($classe)) {
                $trouves[$classe] = $chemin;
            }
        }

        return $trouves;
    }

    /**
     * Les vues `pwa.*` que le composant rend.
     *
     * ⚠ TOUTES les occurrences, et SEULEMENT celles du prefixe `pwa.` — la
     * premiere version de cette methode retenait le premier `view('...')`
     * rencontre, et attrapait le gabarit PDF d'un export (`pdf.stocks-etat`,
     * `pdf.facture-ticket`...) declare plus haut dans le fichier. Elle
     * reprochait alors a onze ecrans corrects de ne pas rendre le message
     * dans un document imprime, ou il n'a evidemment rien a faire. Un
     * controle qui crie a tort finit desactive : il est corrige, pas relache.
     *
     * @param  class-string  $classe
     * @return list<string>
     */
    private function vuesDe(string $classe): array
    {
        $reflet = new ReflectionClass($classe);
        $fichier = $reflet->getFileName();

        if ($fichier === false) {
            return [];
        }

        $source = (string) file_get_contents($fichier);

        preg_match_all("/view\(\s*'(pwa\.[a-z0-9_.\-]+)'/i", $source, $captures);

        /** @var list<string> $vues */
        $vues = array_values(array_unique($captures[1]));

        return $vues;
    }

    /**
     * Les vues PWA dont le code rend la cle — sous n importe quelle forme
     * (bandeau, toast flottant, ou l inclusion du partiel partage).
     *
     * @return list<string>
     */
    private function vuesQuiRendent(): array
    {
        $racine = resource_path('views');
        $rendues = [];

        foreach ($this->fichiersDeVues() as $chemin) {
            $source = (string) file_get_contents($chemin);

            $rendDirect = str_contains($source, "session('".self::CLE."')");
            $inclutLePartiel = str_contains($source, 'pwa.partials.toast-succes');

            if (! $rendDirect && ! $inclutLePartiel) {
                continue;
            }

            $relatif = str_replace(
                ['\\', '/', '.blade.php'],
                ['.', '.', ''],
                substr($chemin, strlen($racine) + 1),
            );

            $rendues[] = $relatif;
        }

        return $this->fermetureParInclusion($rendues);
    }

    /**
     * Etend l'ensemble aux vues qui INCLUENT une vue qui rend.
     *
     * Sans cela, `pwa.restaurant.carte` serait signalee a tort : elle ne rend
     * pas le message elle-meme, elle inclut `pwa.carte.corps` qui le rend
     * pour les deux ecrans de carte. Une garde qui ignore les inclusions
     * reproche a un ecran correct un manque qui n'existe pas — et un controle
     * qui crie a tort finit desactive.
     *
     * La cloture est iterative plutot que recursive : une inclusion circulaire
     * ferait boucler indefiniment une descente naive, et Blade en accepte
     * parfaitement (un partiel qui s'inclut sous condition).
     *
     * @param  list<string>  $rendues
     * @return list<string>
     */
    private function fermetureParInclusion(array $rendues): array
    {
        $sources = [];
        $racine = resource_path('views');

        foreach ($this->fichiersDeVues() as $chemin) {
            $nom = str_replace(
                [DIRECTORY_SEPARATOR, '/', '.blade.php'],
                ['.', '.', ''],
                substr($chemin, strlen($racine) + 1),
            );
            $sources[$nom] = (string) file_get_contents($chemin);
        }

        $ensemble = array_fill_keys($rendues, true);

        do {
            $ajoutees = 0;

            foreach ($sources as $nom => $source) {
                if (isset($ensemble[$nom])) {
                    continue;
                }

                preg_match_all("/@include\(\s*'([a-z0-9_.\-]+)'/i", $source, $captures);

                foreach ($captures[1] as $incluse) {
                    if (isset($ensemble[$incluse])) {
                        $ensemble[$nom] = true;
                        $ajoutees++;
                        break;
                    }
                }
            }
        } while ($ajoutees > 0);

        /** @var list<string> $resultat */
        $resultat = array_keys($ensemble);

        return $resultat;
    }

    /**
     * @return list<string>
     */
    private function fichiersDeComposants(): array
    {
        return $this->fichiersSous(app_path('Pwa/Livewire'), '.php');
    }

    /**
     * @return list<string>
     */
    private function fichiersDeVues(): array
    {
        return $this->fichiersSous(resource_path('views/pwa'), '.blade.php');
    }

    /**
     * @return list<string>
     */
    private function fichiersSous(string $racine, string $suffixe): array
    {
        if (! is_dir($racine)) {
            return [];
        }

        $trouves = [];
        $iterateur = new \RecursiveIteratorIterator(new \RecursiveDirectoryIterator($racine));

        foreach ($iterateur as $fichier) {
            if ($fichier instanceof \SplFileInfo
                && $fichier->isFile()
                && str_ends_with($fichier->getPathname(), $suffixe)) {
                $trouves[] = $fichier->getPathname();
            }
        }

        sort($trouves);

        return $trouves;
    }

    private function classeDe(string $chemin): string
    {
        $relatif = substr($chemin, strlen(app_path()) + 1);

        return 'App\\'.str_replace(['/', '\\', '.php'], ['\\', '\\', ''], $relatif);
    }
}
