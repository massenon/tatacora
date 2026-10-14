<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa\Concerns;

/**
 * « Cette page ne porte aucun champ d'ecriture » — UNE seule implementation.
 *
 * ## Pourquoi un trait plutot qu'un second test
 *
 * Le controle est ne dans `TransversePwaTest` le 27/08/2026, sur les sept
 * pages transverses. Les pages METIER livrees le meme jour en ont exactement
 * le meme besoin, et pour une raison plus forte encore : `m6-inventaires`,
 * `m7-achats` et les points de vente sont des ecrans de SAISIE au maitre. Les
 * transformer en consultations, c'est precisement ce que ce controle verifie.
 *
 * En ecrire un second aurait produit deux definitions de « champ tolere » qui
 * auraient fini par diverger — Article 10, et c'est le defaut que ce depot
 * poursuit depuis PA-121. Une seule methode, deux appelants.
 *
 * ## Ce qu'il refuse, et pourquoi chaque ligne
 *
 * - `<form>` : le seul conteneur qui soumette quoi que ce soit sans
 *   JavaScript. Sa presence sur une page de consultation est un defaut,
 *   meme si aucune route ne l'accepte.
 * - `<textarea>`, `type="password"`, `type="file"`, `type="submit"` : les
 *   quatre formes de saisie que le maitre porte sur ses ecrans d'ecriture.
 * - Tout `<input>` qui n'est PAS lie, par `wire:model`, a une propriete
 *   NOMMEMENT autorisee sur cette page. La liste est FERMEE, comme celle de
 *   `PwaActionsReluesTest` : un filtre ajoute demain doit y etre inscrit, donc
 *   relu. Tolerer tout `wire:model` aurait suffi a laisser passer un champ
 *   lie a une propriete qui, elle, servirait a autre chose qu'a filtrer.
 *
 * Une page absente de la liste, ou dont la liste est vide, ne doit porter
 * AUCUN champ.
 *
 * ## LA RÈGLE QUI FAIT TENIR CE CONTRÔLE SOUS LE RÉGIME CRUD (28/08/2026)
 *
 * La lecture seule de la PWA est levée, et ce trait reste pourtant vrai sur
 * chacun de ses appelants — y compris les écrans qui écrivent. La règle qui
 * rend les deux compatibles est celle-ci, et elle est CONTRAIGNANTE :
 *
 * > **Un formulaire d'écriture ne se rend JAMAIS au premier GET.**
 *
 * Le formulaire vit dans une modale rendue derrière `@if` (le motif
 * `FormulaireModal` + le châssis `components/pwa/modale.blade.php` la fige),
 * et la modale ne s'ouvre qu'après une action gardée par
 * `exigerEcriture(self::MODULE)`. Au premier rendu, la page ne porte donc ni
 * `<form>`, ni champ hors des filtres relus — exactement ce que ce trait
 * vérifie. Trois conséquences :
 *
 * 1. ce contrôle continue de s'appliquer à TOUTE page, écrans d'écriture
 *    compris — il n'y a pas d'exemption « page CRUD » à inventer ;
 * 2. un formulaire rendu masqué par du CSS (`display:none`) fait rougir ce
 *    trait, et c'est voulu : il servirait des champs d'écriture à des rôles
 *    qui n'ont pas le droit d'écrire, avant toute garde ;
 * 3. le pendant positif — la modale s'ouvre, rend exactement ses champs, et
 *    refuse un rôle `L` en le traçant — est `OuvreLaSaisie`, dans ce même
 *    dossier. Les deux traits sont les deux moitiés du même contrat.
 *
 * @see LARAVEL_PWA.md §5 (RBAC identique a Flutter)
 * @see DIRECTIVE_CONFORMITE_100.md Article 6
 * @see tests/Feature/Pwa/Concerns/OuvreLaSaisie.php
 */
trait RefuseLaSaisie
{
    /**
     * @param  string  $html  la reponse HTTP complete
     * @param  string  $nom  le nom de la page, pour le message d'echec
     * @param  list<string>  $proprietesAutorisees  les proprietes Livewire qu'un champ peut lier ici
     */
    protected function assertAucunChampDEcriture(string $html, string $nom, array $proprietesAutorisees = []): void
    {
        $corps = $this->corpsPrincipalPwa($html, $nom);

        $this->assertStringNotContainsString('<form', $corps, "La page {$nom} porte un formulaire.");
        $this->assertStringNotContainsString('<textarea', $corps, "La page {$nom} porte une zone de saisie.");
        $this->assertStringNotContainsString('type="password"', $corps, "La page {$nom} porte un champ de mot de passe.");
        $this->assertStringNotContainsString('type="file"', $corps, "La page {$nom} porte un depot de fichier.");
        $this->assertStringNotContainsString('type="submit"', $corps, "La page {$nom} porte un bouton de soumission.");

        preg_match_all('/<input[^>]*>/i', $corps, $champs);

        foreach ($champs[0] as $champ) {
            $this->assertNotEmpty(
                $proprietesAutorisees,
                "La page {$nom} porte un champ de saisie alors qu'aucun filtre n'y est declare : {$champ}",
            );

            // La propriete REELLEMENT liee, quel que soit le modificateur
            // (`.live`, `.live.debounce.300ms`, `.blur`...). Le modificateur ne
            // change pas ce qui est ecrit, seulement quand.
            $lie = preg_match('/wire:model(?:\.[a-z0-9.]+)?="([a-zA-Z0-9_]+)"/', $champ, $capture) === 1;

            $this->assertTrue(
                $lie,
                "La page {$nom} porte un champ de saisie non lie a une propriete Livewire : {$champ}",
            );

            $this->assertContains(
                $capture[1],
                $proprietesAutorisees,
                "La page {$nom} lie un champ a la propriete « {$capture[1]} », qui n'est pas un filtre relu.",
            );
        }
    }

    /**
     * Le `<main>` seul.
     *
     * La coquille porte des boutons (cloche, menu, deconnexion) qui ne sont
     * pas l'objet de ces cas : les inclure ferait rougir un controle sur du
     * code partage et deja relu ailleurs.
     */
    protected function corpsPrincipalPwa(string $html, string $nom): string
    {
        $debut = strpos($html, '<main');
        $fin = strrpos($html, '</main>');

        $this->assertNotFalse($debut, "La page {$nom} ne rend aucun <main>.");
        $this->assertNotFalse($fin, "La page {$nom} ne ferme aucun <main>.");

        return substr($html, (int) $debut, (int) $fin - (int) $debut);
    }
}
