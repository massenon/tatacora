<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Comptabilite;

use App\Domain\Comptabilite\Services\NotesAnnexesService;
use Illuminate\View\View;
use Livewire\Attributes\Title;

/**
 * Notes Annexes — `prototype_v2/pages/m10-notes-annexes.html`.
 *
 * Sept cartes numerotees, dans l'ordre du maitre (l.42-77) : « 1. Règles et
 * méthodes comptables », « 2. Tableau des immobilisations », « 3. Tableau des
 * amortissements », « 4. État des créances et dettes », « 5. État des
 * stocks », « 6. Effectif du personnel », « 7. Événements postérieurs à la
 * clôture ».
 *
 * `NotesAnnexesService` produit exactement ces sept notes, avec leur numero et
 * leur titre — la liste n'est donc PAS reecrite ici (`LARAVEL_PWA.md` §3).
 *
 * ## Trois etats de note, et il faut les distinguer
 *
 * `NotesAnnexes::ETAT_DISPONIBLE` / `ETAT_INDISPONIBLE` / `ETAT_NON_SAISIE`.
 * Le maitre rend chaque absence par une phrase en italique nommant le jeu de
 * demonstration. Ici, l'etat vient du Service et son motif est un code ferme
 * (`detail_physique_hors_domaine_m10`, `effectif_hors_domaine_m10`,
 * `non_saisi_par_le_comptable`, `report_a_nouveau_absent`,
 * `lettrage_par_anciennete_non_arbitre`), traduit dans `lang/fr/pwa.php`.
 * Une note vide DIT pourquoi elle est vide (Article 7) — mais elle le dit en
 * nommant la limite reelle, pas le jeu de donnees.
 *
 * ## Ce qui n'est PAS porte — Article 8
 *
 * ECART DELIBERE — `m10-notes-annexes.html` l.47, l.51, l.62, l.66, l.70
 * Le maitre : cinq phrases qui commencent par « Aucune ... dans ce jeu de
 * démonstration ».
 * Ici : le motif rendu par le Service.
 * Raison : ces cinq phrases decrivent le DEMONSTRATEUR, pas l'entite. Sur des
 * donnees reelles elles deviendraient fausses sans que personne ne les
 * rouvre — trois occurrences de ce defaut sont deja documentees dans ce depot
 * (PA-107, PA-120, PA-144). La note 4 conserve en revanche la mention de
 * PA-20, qui reste vraie : le lettrage par anciennete n'est toujours pas
 * arbitre, et `NotesAnnexesService::MOTIF_ANCIENNETE_NON_ARBITREE` le porte.
 * Verifie le 27/08/2026 contre `PLAN_ACTION_SEQUENCE_POST_AUDIT.md`.
 *
 * ## LES CINQ MODALES DU MOTEUR CRUD SONT REFUSEES — Article 8
 *
 * ECART DELIBERE — `prototype_v2/assets/js/crud-ui.js` l.87, 108, 125, 144, 164
 * Le maitre : cette page charge `crud-ui.js`, qui pose cinq modales
 * generiques — « Nouveau » (`modale-formulaire`), « Detail » (`modale-detail`),
 * « Confirmer la suppression » (`modale-suppression`), un export CSV
 * (`modale-export`) et un import (`modale-import`).
 * Ici : aucune des cinq n'est portee.
 * Raison, VERIFIEE le 27/08/2026 et non supposee : cette page ne les utilise
 * PAS. Elle ne contient aucune reference a `CrudUI`, `CrudEngine` ni a une
 * configuration CRUD — `grep -c` rend zero sur les six pages M10 concernees —
 * et son contenu est produit par son propre script en ligne. Les cinq modales
 * sont du code mort herite d'une balise `<script>` commune. Quatre d'entre
 * elles sont de surcroit des ECRITURES, que `LARAVEL_PWA.md` §6 exclut du
 * perimetre de la PWA ; la cinquieme est un export, et le catalogue d'etats
 * (RG-19) ne contient aucun etat de M10.
 * ⚠ A signaler au commanditaire : charger un moteur CRUD sur un etat financier
 * en lecture donne a la maquette des boutons de creation et de suppression que
 * rien n'appelle. C'est une observation sur le maitre, pas un arbitrage.
 *
 * Refus declares :
 *   maitre-refuse:m10-notes-annexes.html#modale-formulaire
 *   maitre-refuse:m10-notes-annexes.html#modale-detail
 *   maitre-refuse:m10-notes-annexes.html#modale-suppression
 *   maitre-refuse:m10-notes-annexes.html#modale-export
 *   maitre-refuse:m10-notes-annexes.html#modale-import
 *
 * @see EF-M10-06
 */
#[Title('Notes Annexes — LogiReStock — TATACORA AFRIQUE')]
class NotesAnnexes extends PageComptabilite
{
    public function render(): View
    {
        $socle = $this->socle();
        $exercice = $socle['exercice'];

        return view('pwa.comptabilite.notes-annexes', array_merge($socle, [
            'notes' => $exercice === null ? null : app(NotesAnnexesService::class)
                ->genererPourExercice($exercice, $this->statuts(), $this->filtreStatutValide()),
        ]))->layout('layouts.pwa');
    }
}
