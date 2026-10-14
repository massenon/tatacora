<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Comptabilite;

use App\Domain\Comptabilite\Services\AnalytiqueService;
use Illuminate\View\View;
use Livewire\Attributes\Title;

/**
 * Comptabilité Analytique — `prototype_v2/pages/m10-analytique.html`.
 *
 * Cinq colonnes dans l'ordre du maitre (l.32-36) : « Centre de coût »,
 * « Produits », « Charges », « Marge », « Taux de marge ». Les quatre montants
 * sont alignes a droite.
 *
 * ## Le taux de marge vaut « — », jamais 0
 *
 * Article 7, et le maitre l'ecrit deja (l.62) : `m.tauxMarge === null ? '—'`.
 * `LigneAnalytique::tauxMarge` est nullable — un centre sans produits n'a pas
 * un taux de zero, il n'a pas de taux. Le maitre le motive en pied de page
 * (l.45) : « Structure » regroupe des charges transverses, « pas un centre
 * générateur de produits, taux de marge non applicable ("—") ».
 *
 * ## Ce que cet ecran doit dire, et que le maitre ne dit pas
 *
 * `Analytique::repartitionStructureEffectuee` vaut `false` : AUCUNE charge de
 * structure n'est repartie. Les colonnes sont donc des MARGES SUR COUTS
 * DIRECTS, pas des resultats nets. Une cle de repartition est une decision de
 * gestion, pas une constante technique : la choisir rendrait le bar
 * beneficiaire ou deficitaire selon une regle que personne n'aurait validee.
 * Le hub du maitre porte cet avertissement (`m10-syscohada-etats.js` l.196) ;
 * la page autonome l'a perdu. Il est rendu ici.
 *
 * ## Ce qui n'est PAS porte — Article 8
 *
 * ECART DELIBERE — `m10-analytique.html` l.31
 * Le maitre : un bandeau ambre expliquant que « Bar et Restauration affichent
 * une marge négative dans ce jeu de démonstration — reflet honnête d'un petit
 * nombre de ventes suivies (10 dossiers au total) ».
 * Ici : absent.
 * Raison : il decrit dix dossiers d'un demonstrateur. Sur des donnees reelles,
 * annoncer que deux centres precis sont deficitaires « par effet de jeu
 * d'essai » excuserait par avance un resultat qu'il faut au contraire lire.
 * A sa place, l'avertissement sur la non-repartition des charges de structure,
 * qui reste vrai quelles que soient les donnees.
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
 *   maitre-refuse:m10-analytique.html#modale-formulaire
 *   maitre-refuse:m10-analytique.html#modale-detail
 *   maitre-refuse:m10-analytique.html#modale-suppression
 *   maitre-refuse:m10-analytique.html#modale-export
 *   maitre-refuse:m10-analytique.html#modale-import
 *
 * @see EF-M10-03 Comptabilite analytique par centre
 * @see RG-12 Centre analytique obligatoire sur les classes 6, 7 et 8
 */
#[Title('Comptabilité Analytique — TATACORA AFRIQUE')]
class Analytique extends PageComptabilite
{
    public function render(): View
    {
        $socle = $this->socle();
        $exercice = $socle['exercice'];

        return view('pwa.comptabilite.analytique', array_merge($socle, [
            'analytique' => $exercice === null ? null : app(AnalytiqueService::class)
                ->genererPourExercice($exercice->id, $this->statuts(), $this->filtreStatutValide()),
        ]))->layout('layouts.pwa');
    }
}
