<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa\Concerns;

use App\Models\User;
use App\Shared\Rbac\Models\JournalSecurite;
use Livewire\Livewire;

/**
 * « Cette modale s'ouvre pour qui a le droit, rend exactement ses champs, et
 * refuse les autres en le traçant » — le pendant POSITIF de `RefuseLaSaisie`.
 *
 * ## Les deux moitiés du même contrat
 *
 * `RefuseLaSaisie` tient la règle du premier rendu : *un formulaire
 * d'écriture ne se rend jamais au premier GET*. Ce trait tient ce qui se
 * passe APRÈS le geste d'ouverture, et chaque vague du plan CRUD l'utilise
 * plutôt que de réécrire ses assertions — deux définitions de « la modale
 * rend ses champs » auraient fini par diverger (Article 10).
 *
 * ## « Exactement les champs », mesuré par différence de rendus
 *
 * Le rendu AVANT l'ouverture est comparé au rendu APRÈS : les liaisons
 * `wire:model` qui apparaissent sont, à l'ensemble près, les propriétés
 * déclarées du formulaire. La différence est ce qui rend le contrôle honnête
 * sur une page qui porte déjà des filtres liés (`recherche`, `filtre`…) :
 * comparer le rendu ouvert seul les compterait, et il faudrait les exempter —
 * une liste d'exemptions de plus à faire vieillir.
 *
 * - un champ ATTENDU qui n'apparaît pas → échec (le formulaire est amputé) ;
 * - un champ NON déclaré qui apparaît → échec (une propriété non relue
 *   devient saisissable, le trou exact que la liste fermée ferme) ;
 * - AUCUN champ n'apparaît → échec explicite, jamais un vert à vide.
 *
 * ## Ce que ce trait ne couvre PAS, et c'est écrit
 *
 * - Il compare des LIAISONS (`wire:model="propriete"`), pas des étiquettes ni
 *   des invites : la conformité au maître (libellés, ordre, invites) reste
 *   l'affaire des tests de page et de `t-trois-sources.js`.
 * - Un `<select>` ou `<input>` sans `wire:model` dans la modale lui est
 *   invisible — mais un tel champ ne soumettrait rien à Livewire, et
 *   `RefuseLaSaisie` le refuse au premier GET sur les pages de consultation.
 * - Il suppose la propriété d'état du motif `FormulaireModal`
 *   (`etatFormulaire`) ; un écran qui s'en écarterait passe le nom de sa
 *   propriété — et devrait surtout dire pourquoi il s'écarte du motif.
 *
 * @see tests/Feature/Pwa/Concerns/RefuseLaSaisie.php
 * @see App\Pwa\Livewire\Concerns\FormulaireModal
 * @see LARAVEL_PWA.md §5 (RBAC identique a Flutter)
 */
trait OuvreLaSaisie
{
    /**
     * Pour un rôle autorisé : la modale s'ouvre et rend EXACTEMENT les champs
     * liés aux propriétés déclarées.
     *
     * @param  User  $utilisateurAutorise  un compte dont le rôle porte `C` sur le module de l'écran
     * @param  class-string  $composant  le composant Livewire de la page
     * @param  string  $actionOuverture  l'action publique qui ouvre la modale
     * @param  list<string>  $proprietesDeclarees  les propriétés Livewire des champs du formulaire
     * @param  string  $proprieteEtat  la propriété d'état du motif `FormulaireModal`
     */
    protected function assertLaModaleSOuvreEtRendExactementSesChamps(
        User $utilisateurAutorise,
        string $composant,
        string $actionOuverture,
        array $proprietesDeclarees,
        string $proprieteEtat = 'etatFormulaire',
    ): void {
        // Plancher : une liste vide rendrait la comparaison finale vraie sur
        // une modale qui ne rend rien — le balayage vide qui est vert.
        $this->assertNotEmpty(
            $proprietesDeclarees,
            'Aucune propriete declaree : ce controle ne verifierait rien.',
        );

        $this->actingAs($utilisateurAutorise);

        $testable = Livewire::test($composant);
        $avant = $this->liaisonsWireModel($testable->html());

        $testable->call($actionOuverture)
            ->assertSet(
                $proprieteEtat,
                static fn (mixed $etat): bool => $etat !== null && $etat !== false && $etat !== '',
            );

        $apres = $this->liaisonsWireModel($testable->html());

        // Les liaisons APPARUES avec l'ouverture — en comptant les
        // occurrences : une liaison de filtre déjà présente avant ne masque
        // pas un champ homonyme ajouté par la modale.
        $nouvelles = [];
        foreach ($apres as $propriete => $occurrences) {
            if ($occurrences > ($avant[$propriete] ?? 0)) {
                $nouvelles[] = $propriete;
            }
        }

        $this->assertNotEmpty(
            $nouvelles,
            "L'action {$actionOuverture} de {$composant} n'a fait apparaitre aucun "
            .'champ : la modale ne rend rien, ou son rendu n est pas derriere l etat.',
        );

        $attendues = array_values(array_unique($proprietesDeclarees));
        sort($attendues);
        sort($nouvelles);

        $this->assertSame(
            $attendues,
            $nouvelles,
            "La modale ouverte par {$actionOuverture} de {$composant} ne rend pas "
            .'exactement les champs declares. Un champ manquant ampute le '
            .'formulaire ; un champ en trop lie une propriete que personne n a relue.',
        );
    }

    /**
     * Pour un rôle SANS le niveau `C` : la modale ne s'ouvre pas, et le refus
     * est tracé au `journal_securite`.
     *
     * @param  User  $utilisateurSansEcriture  un compte dont le rôle porte `L` ou `-` sur le module
     * @param  class-string  $composant
     * @param  string  $actionOuverture
     * @param  string  $module  le module attendu dans la trace (`module_concerne`)
     * @param  string  $proprieteEtat
     */
    protected function assertLOuvertureEstRefuseeEtTracee(
        User $utilisateurSansEcriture,
        string $composant,
        string $actionOuverture,
        string $module,
        string $proprieteEtat = 'etatFormulaire',
    ): void {
        // Le DELTA du journal, pas sa simple présence : une trace laissée par
        // un autre cas du même test rendrait `assertDatabaseHas` vert sans
        // que CE refus ait rien écrit.
        $refusAvant = JournalSecurite::where('type_evenement', 'acces_refuse_rbac')->count();

        $this->actingAs($utilisateurSansEcriture);

        // `assertSet` avant `assertForbidden` : le second rend le
        // `TestResponse` du cadre, sur lequel l'etat du composant n'est plus
        // interrogeable.
        Livewire::test($composant)
            ->call($actionOuverture)
            ->assertSet(
                $proprieteEtat,
                static fn (mixed $etat): bool => $etat === null || $etat === false || $etat === '',
            )
            ->assertForbidden();

        $this->assertSame(
            $refusAvant + 1,
            JournalSecurite::where('type_evenement', 'acces_refuse_rbac')->count(),
            "Le refus d'ouverture de {$actionOuverture} sur {$composant} n'a pas ete "
            .'trace au journal_securite : une tentative repetee serait invisible.',
        );

        $this->assertDatabaseHas('journal_securite', [
            'type_evenement' => 'acces_refuse_rbac',
            'utilisateur_id' => $utilisateurSansEcriture->id,
            'module_concerne' => $module,
        ]);
    }

    /**
     * Les liaisons `wire:model` d'un rendu, quel que soit le modificateur
     * (`.live`, `.live.debounce.300ms`, `.blur`…) — le modificateur ne change
     * pas ce qui est écrit, seulement quand.
     *
     * @return array<string, int> propriété => nombre d'occurrences
     */
    private function liaisonsWireModel(string $html): array
    {
        preg_match_all('/wire:model(?:\.[a-z0-9.]+)?="([A-Za-z0-9_.]+)"/', $html, $captures);

        // Le motif ci-dessus doit mordre quelque part dans la suite : un motif
        // corrompu (le `\b` devenu 0x08 est arrivé trois fois dans ce dépôt)
        // rendrait toutes les listes vides, et « avant » comme « après »
        // seraient égaux — vert. Le plancher vit dans les assertions des
        // appelants (`assertNotEmpty($nouvelles)`), qui échouent dans ce cas.
        return array_count_values($captures[1]);
    }
}
