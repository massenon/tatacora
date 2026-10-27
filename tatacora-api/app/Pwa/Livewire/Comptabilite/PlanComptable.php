<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Comptabilite;

use App\Domain\Comptabilite\Models\CompteComptable;
use App\Domain\Comptabilite\Services\PlanComptableService;
use Illuminate\View\View;
use Livewire\Attributes\Title;
use Livewire\Attributes\Url;

/**
 * Plan Comptable — `prototype_v2/pages/m10-plan-comptable.html`.
 *
 * Quatre colonnes dans l'ordre du maitre (l.36) : « N° Compte », « Libellé »,
 * « Classe », « Nature ». Huit boutons de filtre : « Toutes les classes » puis
 * les sept classes que l'ecran presente.
 *
 * ## Deux choses que cet ecran doit dire, et que le maitre ne dit pas
 *
 * 1. **Les classes 8 et 9 existent au schema et n'ont aucun bouton.**
 *    `CompteComptable::CLASSES_ECRAN` s'arrete a 7 quand
 *    `CLASSES_SYSCOHADA` va jusqu'a 9. Un compte de classe 8 (HAO) serait
 *    invisible sans que rien ne le signale — un plan ampute qui a l'air
 *    complet. `PlanComptable::comptesParClasseHorsEcran` les compte, et
 *    l'ecran les affiche sous le tableau.
 * 2. **`plan_comptable.nature` est NULLABLE.** Article 7 : « — » quand la
 *    donnee n'existe pas. Le maitre, lui, lit une pastille de couleur dans un
 *    jeu de demonstration ou la nature est toujours renseignee ; sa table de
 *    correspondance rendrait `undefined` sur un compte reel sans nature.
 *    `PlanComptable::sansNature` en donne le compte.
 *
 * ## Ce qui n'est PAS porte — Article 8
 *
 * ECART DELIBERE — `m10-plan-comptable.html` l.29
 * Le maitre : le sous-titre annonce le nombre de comptes du jeu de
 * demonstration (`PLAN_COMPTABLE.length`).
 * Ici : le nombre reel rendu par `PlanComptableService::consulter()`.
 * Raison : c'est la meme phrase avec la vraie mesure — un total ecrit en dur
 * est le deuxieme interdit de l'Article 6.
 *
 * ECART DELIBERE — `m10-plan-comptable.html`, bouton « + Créer un compte »
 * Le maitre : `m10-syscohada.js` l.348 pose ce bouton sur le HUB, et sa modale
 * `modale-compte` porte le formulaire de compte.
 * Ici : ni le bouton, ni la modale.
 * Raison, VERIFIEE le 31/08/2026 : `PlanComptableService` n'expose AUCUNE
 * ecriture — son propre bloc de documentation le motive (« Router une creation
 * de compte que rien n'appelle serait le defaut PA-63 dans l'autre sens »), et
 * `app/Domain/**` est hors du perimetre de ce lot. Un bouton qui n'ouvre rien
 * est le premier interdit de l'Article 6 : il n'est donc pas rendu.
 *
 * ⚠ Cette declaration etait, jusqu'au 31/08/2026, un panneau « Ce que cet
 * ecran ne fait pas » affiche sous l'en-tete. La directive du Product Owner du
 * 31/08/2026 supprime ces sections : le refus se declare en jeton code, il ne
 * se rend plus a l'ecran.
 * Refus declare : maitre-refuse:m10-plan-comptable.html#page
 *
 * ## AUCUN BOUTON « SUPPRIMER » ICI, ET C'EST UN REFUS, PAS UN OUBLI
 *
 * La demande du Product Owner du 03/09/2026 — « mettre le bouton Supprimer sur
 * chaque table, ou la suppression en bulk » — a ete portee sur les
 * referentiels d'EXPLOITATION (clients M3, articles M6, fournisseurs M7) :
 * « supprimer = archiver », `actif = false`, verrou d'engagement, restauration.
 * Le plan comptable en est EXCLU, pour deux raisons qui ne sont pas
 * techniques :
 *
 * 1. **C'est un referentiel REGLEMENTAIRE.** Les comptes viennent du plan
 *    SYSCOHADA revise, pas d'une decision du Gite. Les retirer un a un
 *    fabriquerait un plan local qui ne serait plus celui qu'un commissaire aux
 *    comptes attend — et l'ecart ne se verrait qu'a la premiere liasse.
 * 2. **Un compte est cite par des ECRITURES, et les ecritures sont
 *    immuables** (RG-11 : la correction passe exclusivement par
 *    contre-passation). Un compte « archive » que le grand livre continue de
 *    citer produirait un etat financier dont une ligne renvoie a un compte que
 *    l'ecran presente comme retire.
 *
 * Ce qui manque reellement ici n'est pas la suppression, c'est la CREATION —
 * declaree juste au-dessus, et bloquee par l'absence d'ecriture dans
 * `PlanComptableService`. La question du retrait ne se posera qu'apres.
 *
 * @see EF-M10-01 Plan comptable parametrable
 * @see LARAVEL_PWA.md §3
 */
#[Title('Plan Comptable — LogiReStock — TATACORA AFRIQUE')]
class PlanComptable extends PageComptabilite
{
    #[Url(as: 'classe')]
    public string $classe = '';

    /**
     * Barre de recherche par table (décision du Product Owner, 01/09/2026) —
     * numéro de compte ou libellé. Filtrage SERVEUR réel
     * (`PlanComptableService::consulter()`), jamais du JS client. Sûre ici,
     * contrairement aux quatre autres écrans M10 (Journal, Balance, Grand
     * Livre, Analytique) : un plan comptable n'a ni total ni équilibre à
     * préserver, `comptesParClasse`/`total`/`sansNature` portent déjà sur le
     * référentiel ENTIER, jamais sur le filtre.
     */
    #[Url(as: 'q')]
    public string $recherche = '';

    public function render(): View
    {
        // Une classe inconnue vient de l'URL, donc de l'exterieur : elle
        // retombe sur « toutes les classes » plutot que de lever.
        $classe = in_array($this->classe, CompteComptable::CLASSES_ECRAN, true)
            ? $this->classe
            : null;

        return view('pwa.comptabilite.plan-comptable', array_merge($this->socle(), [
            'plan' => app(PlanComptableService::class)->consulter($classe, $this->recherche),
            'classeActive' => $classe,
        ]))->layout('layouts.pwa');
    }
}
