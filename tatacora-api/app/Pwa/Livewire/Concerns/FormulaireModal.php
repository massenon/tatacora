<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Concerns;

use App\Pwa\Support\AutoriseEcriture;

/**
 * Le motif de FORMULAIRE MODAL d'écriture de la PWA — une seule implémentation
 * des gestes que la première écriture (« Ajouter fournisseur », EF-M7-01) a
 * établis, pour que chaque vague les obtienne en les appelant, jamais en les
 * recopiant (Article 10).
 *
 * ## Les gestes figés, et pourquoi chacun
 *
 * - **`exigerEcriture(static::MODULE)` à l'ouverture ET à l'enregistrement.**
 *   À l'ouverture : présenter un formulaire à quelqu'un qui ne pourra pas le
 *   soumettre lui fait perdre sa saisie et ne lui apprend rien. À
 *   l'enregistrement : l'ouverture ne protège rien — l'état de la modale est
 *   une propriété Livewire, modifiable depuis le navigateur.
 * - **`reset()` + `resetValidation()` à l'ouverture.** Rouvrir après un
 *   abandon ne doit ni reproposer des valeurs à moitié tapées, qu'on
 *   enregistrerait sans les relire, ni afficher les erreurs d'une saisie qui
 *   n'existe plus.
 * - **Fermeture + `session()->flash('pwa-succes', …)` à la fin.** Le flash et
 *   la fermeture vont ensemble : une modale qui reste ouverte après un succès
 *   invite à soumettre deux fois.
 *
 * Le rendu, lui, vit dans `components/pwa/modale.blade.php` — le châssis
 * partagé —, derrière `@if` : un formulaire d'écriture ne se rend JAMAIS au
 * premier GET (voir `tests/Feature/Pwa/Concerns/RefuseLaSaisie`, qui tient
 * cette règle sur chaque page).
 *
 * ⚠ Cette ligne citait `components/pwa/modale-formulaire.blade.php`, supprimé
 * le 31/08/2026 : ce composant n'avait AUCUN appelant (`<x-pwa.modale-formulaire>`
 * à zéro dans tout le dépôt) et posait son propre `<div class="fixed inset-0
 * bg-black/50">` PAR-DESSUS le voile de `.overlay-modale`, doublant l'opacité
 * à 75 % — le défaut exact que le châssis partagé documente avoir corrigé. Une
 * citation vers un fichier disparu envoie le lecteur suivant vers un gabarit
 * qui n'existe plus.
 *
 * ## `$etatFormulaire` porte le NOM du formulaire ouvert, pas un booléen
 *
 * Un écran de vague future portera plusieurs modales (fournisseur ET commande
 * sur `m7-achats.html`) : un booléen par modale multiplierait les propriétés
 * d'état et leurs remises à zéro. Une seule propriété, `null` quand tout est
 * fermé, garantit au passage qu'une seule modale est ouverte à la fois.
 *
 * ## TOUS les auxiliaires sont `protected`, et ce n'est pas un détail
 *
 * La réflexion rapporte une méthode de trait comme DÉCLARÉE par la classe
 * utilisatrice : une méthode publique posée ici apparaîtrait comme action
 * Livewire sur chaque écran d'écriture à la fois, et ferait rougir la liste
 * fermée de `PwaActionsReluesTest` sur chacun d'eux. Chaque écran déclare ses
 * propres actions publiques (`ouvrirFormulaireFournisseur`,
 * `enregistrerFournisseur`…), qui délèguent ici — c'est ce qui garde une
 * entrée nommée, donc relue, par action et par écran.
 *
 * La classe utilisatrice doit porter `public const MODULE` (le module RBAC de
 * l'écran) : `PwaEcritureAutoriseeTest` vérifie que chaque appel
 * d'`exigerEcriture()` reçoit `self::MODULE` ou `static::MODULE`, jamais un
 * littéral.
 *
 * @see LARAVEL_PWA.md §3, §5
 * @see DIRECTIVE_CONFORMITE_100.md Article 4.6 (modales), Article 10
 */
trait FormulaireModal
{
    use AutoriseEcriture;

    /**
     * Le formulaire actuellement ouvert — `null` : aucun.
     *
     * Propriété Livewire, donc modifiable depuis le navigateur : c'est assumé,
     * et c'est pour cela que l'ouverture ne protège rien (voir l'entête). La
     * vue s'en sert aussi pour fermer (`$set('etatFormulaire', null)`), ce qui
     * interdit de la verrouiller par `#[Locked]`.
     */
    public ?string $etatFormulaire = null;

    /**
     * Le registre FERMÉ des formulaires de l'écran, avec leurs propriétés.
     *
     * @return array<string, list<string>> nom du formulaire => propriétés Livewire à remettre à zéro
     */
    abstract protected function formulaires(): array;

    /**
     * Ouvre un formulaire déclaré — droit exigé, saisie et erreurs effacées.
     */
    protected function ouvrirFormulaire(string $formulaire): void
    {
        $this->exigerEcriture(static::MODULE);

        $proprietes = $this->formulaires()[$formulaire] ?? null;

        if ($proprietes === null) {
            // Un nom hors registre est une erreur d'appel du composant, jamais
            // une saisie utilisateur : il ne mérite pas mieux qu'un refus.
            abort(404);
        }

        $this->reset($proprietes);
        $this->resetValidation();
        $this->etatFormulaire = $formulaire;
    }

    /**
     * Le droit puis la validation — dans cet ordre, comme l'API : un rôle sans
     * droit n'apprend rien de la validité des données qu'il a soumises.
     *
     * @param  array<string, mixed>  $regles
     * @return array<string, mixed>
     */
    protected function validerEcriture(array $regles): array
    {
        $this->exigerEcriture(static::MODULE);

        return $this->validate($regles);
    }

    /**
     * Clôt le geste : fermeture de la modale et message de succès.
     */
    protected function terminerFormulaire(string $messageSucces): void
    {
        $this->etatFormulaire = null;
        session()->flash('pwa-succes', $messageSucces);
    }
}
