<?php

declare(strict_types=1);

namespace App\Pwa\Support;

use App\Models\User;
use App\Shared\Rbac\Services\DroitArchivageService;

/**
 * QUI PEUT ARCHIVER dans la PWA — la règle, écrite UNE fois.
 *
 * Directive du Product Owner du 03/09/2026 (« mettre le bouton Supprimer sur
 * chaque table, ou la suppression en bulk, pour administrateur et
 * super_admin ») :
 *
 * - `administrateur` et `super_admin` : oui, **sans la bascule**. C'est le
 *   défaut d'une installation neuve qui a motivé la demande — la bascule
 *   `activation_suppression` naît FERMÉE (`OptionsSystemeService::DEFAUTS`),
 *   donc l'Administrateur n'avait ni bouton de ligne, ni case, ni bouton de
 *   lot, et rien à l'écran ne lui disait où l'ouvrir.
 * - Tout autre rôle en `C` sur le module de l'écran : oui, **seulement** quand
 *   la bascule est ouverte en Paramètres. La lever pour tout le monde
 *   retirerait une protection que le PO n'a pas demandé de lever — un `barman`
 *   ou un `magasinier` en `C` retrouverait un bouton rouge permanent.
 * - Un rôle en `L` ou sans accès : jamais. `exigerEcriture()` le tranche
 *   d'abord, par le même `niveauSurModule()` que `VerifierAccesModule`.
 *
 * ## Un seul auteur, deux lecteurs
 *
 * La vue ne rejoue JAMAIS ce calcul : elle reçoit `peutArchiver` depuis
 * `render()`. Le geste l'exige par `exigerArchivage()`. Écrire la règle une
 * seconde fois dans un `@if` de Blade la ferait diverger au premier
 * changement — c'est le défaut du référentiel à double auteur (PA-160/161),
 * transposé à une garde.
 *
 * ## Toutes les méthodes sont `protected`, et ce n'est pas un détail
 *
 * La réflexion rapporte une méthode de trait comme DÉCLARÉE par la classe
 * utilisatrice : une méthode publique posée ici apparaîtrait comme action
 * Livewire sur chaque écran qui l'emploie, et ferait rougir la liste fermée
 * de `PwaActionsReluesTest` sur chacun d'eux (même raisonnement que
 * `FormulaireModal`).
 *
 * ⚠ Cette ligne signalait un double auteur CONNU : `App\Pwa\Livewire\Rh\Paie`
 * portait une copie privée de la règle, écrite le même jour dans une
 * livraison parallèle. **Elle a été repliée ici le 03/09/2026** — `Paie`
 * emploie désormais ce trait, et son ancien commentaire renvoie à ce fichier.
 * La note est conservée corrigée plutôt que supprimée : un motif qui a cessé
 * d'être vrai transforme une décision en oubli (PA-144), et c'est justement
 * le repli qui l'a fait cesser.
 *
 * ## `static::MODULE`, jamais un littéral
 *
 * La classe utilisatrice doit porter `public const MODULE` (le module RBAC de
 * l'écran), comme pour `FormulaireModal` : `exigerEcriture('M1')` posé dans un
 * composant M7 exigerait le droit du MAUVAIS module. `exigerArchivage()` est
 * reconnu comme délégué gardé par `PwaEcritureAutoriseeTest`, qui dérive cette
 * liste des traits PAR RÉFLEXION — retirer la garde d'ici la retire aussitôt à
 * tous ses appelants, et le test le voit.
 *
 * @see DIRECTIVE_CONFORMITE_100.md Article 3.3 (une action indisponible est retirée, pas grisée)
 * @see LARAVEL_PWA.md §5
 */
trait AutoriseArchivage
{
    use AutoriseEcriture;

    /**
     * Les rôles qui archivent SANS la bascule des Paramètres.
     *
     * ⚠ `super_admin` est aussi porté par `User::estSuperAdmin()`. Ce prédicat
     * ne s'en sert pas : la décision nomme DEUX rôles, et n'en lire qu'un
     * retirerait le geste à l'administrateur.
     *
     * ⚠ La liste elle-même vit sur `User::ROLES_ADMINISTRATION` depuis le
     * 06/09/2026 : un second geste réservé aux mêmes rôles est arrivé
     * (l'entrée de stock depuis la fiche article), et la recopier en aurait
     * fait deux. Le nom local est conservé — il dit ce que la règle fait ICI,
     * archiver sans la bascule.
     *
     * ⚠ Depuis le 15/10/2026, le prédicat lui-même vit sur
     * `DroitArchivageService` (la synchronisation archive aussi), qui lit
     * `User::ROLES_ADMINISTRATION` directement : cette constante n'est plus
     * qu'un alias documentaire, conservé pour les tests qui la nomment.
     *
     * @var list<string>
     */
    protected const ROLES_ARCHIVAGE_HORS_BASCULE = User::ROLES_ADMINISTRATION;

    /**
     * Vrai quand l'utilisateur courant peut archiver sur le module donné.
     *
     * Ne lève jamais : c'est le prédicat que `render()` passe à la vue pour
     * décider si le bouton est RENDU. Le refus serveur, lui, est
     * `exigerArchivage()`.
     */
    protected function peutArchiver(): bool
    {
        $utilisateur = auth()->user();

        // La règle vit dans `DroitArchivageService` depuis le 15/10/2026 : la
        // synchronisation hors connexion archive aussi (fournisseurs), et la
        // recopier là-bas en aurait fait deux auteurs.
        return app(DroitArchivageService::class)->peutArchiver(
            $utilisateur instanceof User ? $utilisateur : null,
            static::MODULE,
        );
    }

    /**
     * Le refus serveur du geste d'archivage.
     *
     * Appelé À L'OUVERTURE de la modale ET à l'exécution : l'ouverture ne
     * protège rien par elle-même — `$etatFormulaire` est une propriété
     * Livewire, forgeable depuis le navigateur (`FormulaireModal`).
     *
     * `exigerEcriture()` passe d'abord : il trace le refus RBAC au journal de
     * sécurité et distingue 401 (session absente) de 403 (droit manquant). Ce
     * qui reste ici est le seul supplément d'archivage — la bascule.
     */
    protected function exigerArchivage(): void
    {
        $this->exigerEcriture(static::MODULE);

        if (! $this->peutArchiver()) {
            abort(403, __('pwa.archivage.refus_bascule'));
        }
    }

    /**
     * COMPOSE LE LOT à confirmer — les trois états de la modale du maître,
     * calculés une fois pour les trois écrans qui l'emploient.
     *
     * `crud-engine.js` l.523-551 pose trois états, et le premier est celui qui
     * compte : BLOQUÉ (tout le lot est engagé — le bouton de confirmation
     * DISPARAÎT), PARTIEL (une partie part, et l'écran annonce AVANT le clic
     * combien resteront), NOMINAL. Un décompte affiché après coup serait une
     * surprise ; un bouton visible et inerte laisserait croire à une panne.
     *
     * ⚠ Les motifs affichés datent de l'OUVERTURE. Ils ne protègent rien : le
     * verrou qui tranche est celui que le Service recontrôle au moment d'agir
     * (`ReferentielClientService::archiver()` et ses deux jumeaux). Ce qui est
     * calculé ici sert à MONTRER pourquoi, pas à autoriser.
     *
     * @template TModele of \Illuminate\Database\Eloquent\Model
     *
     * @param  iterable<int, TModele>  $elements
     * @param  callable(TModele): list<string>  $verrous
     * @param  callable(TModele): string  $libelle
     * @return array{ids: list<string>, motifs: list<string>, conserves: int, bloque: bool, libelle: string}
     */
    protected function composerLotArchivage(iterable $elements, callable $verrous, callable $libelle): array
    {
        $ids = [];
        $motifs = [];
        $conserves = 0;
        $libelles = [];

        foreach ($elements as $element) {
            $raisons = $verrous($element);
            $nom = $libelle($element);
            $libelles[] = $nom;

            if ($raisons === []) {
                $ids[] = (string) $element->getKey();

                continue;
            }

            $conserves++;
            // Le nom de l'élément accompagne son motif : sur un lot de vingt
            // lignes, « engagé dans 2 séjours » sans dire QUI oblige à rouvrir
            // les vingt fiches pour trouver laquelle.
            $motifs[] = $nom.' — '.implode(' ', $raisons);
        }

        return [
            'ids' => $ids,
            'motifs' => $motifs,
            'conserves' => $conserves,
            'bloque' => $ids === [],
            'libelle' => count($libelles) === 1 ? $libelles[0] : '',
        ];
    }
}
