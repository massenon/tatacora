<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Comptabilite;

use App\Domain\Comptabilite\Services\TafireService;
use Illuminate\View\View;
use Livewire\Attributes\Title;

/**
 * Tableau des Flux de Trésorerie — `prototype_v2/pages/m10-flux-tresorerie.html`.
 *
 * Quatre blocs dans l'ordre du maitre : « RESSOURCES » et « EMPLOIS » cote a
 * cote (l.36-46), puis « Variation du Besoin en Fonds de Roulement (BFR) »
 * (l.49) et « Variation de trésorerie nette » (l.54). Bandeau de coherence en
 * tete, avec les deux phrases du maitre (l.65-67).
 *
 * ## Le controle de coherence est le livrable de cet ecran
 *
 * `Tafire::coherent` compare la variation CALCULEE (ressources − emplois −
 * BFR) a la variation REELLE des comptes de tresorerie. Un ecart n'est pas
 * une « différence normale » : c'est un mouvement mal classe. Le maitre l'ecrit
 * ainsi, et la phrase est reprise mot pour mot.
 *
 * ## ⚠ LA FORMULE DE REFERENCE DU BFR EST FAUSSE AU DOCUMENT, ET LE CODE A RAISON
 *
 * PA-151 : `MODULE_COMPTABILITE_COMPLET_PART3.md` §2.3 OMET les comptes 421
 * (personnel), 431 (organismes sociaux) et 447 (Etat) des dettes du BFR.
 * L'ecart a ete mesure — 40 000 F, exactement la dette omise. Le document est
 * annote, pas reecrit, et l'arbitrage revient a l'Architecte. Cet ecran affiche
 * ce que `TafireService` calcule, c'est-a-dire la version corrigee : ne pas
 * « corriger » vers le document.
 *
 * ## Ce qui n'est PAS porte — Article 8
 *
 * ECART DELIBERE — `m10-flux-tresorerie.html` l.86
 * Le maitre : sous les emplois, « Aucune immobilisation dans les données de
 * démonstration actuelles — reflet honnête du jeu de données. »
 * Ici : absente.
 * Raison : affirmation sur le jeu de demonstration, fausse a la premiere
 * acquisition reelle. La ligne « Acquisitions d'immobilisations » affiche son
 * montant reel, zero compris.
 *
 * ECART DELIBERE — `m10-flux-tresorerie.html` l.99
 * Le maitre : la ligne « − Variation des dettes fournisseurs ».
 * Ici : « − Variation des dettes ».
 * Raison : le Service ne calcule pas les seules dettes FOURNISSEURS —
 * `Tafire::variationDettes` couvre aussi le personnel, les organismes sociaux
 * et l'Etat (voir ci-dessus). Conserver le libelle du maitre nommerait une
 * grandeur plus etroite que celle affichee, sur la ligne meme dont PA-151
 * vient de montrer qu'elle etait mal specifiee. Motif recevable : bug de
 * maquette (Article 8, motif 2).
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
 *   maitre-refuse:m10-flux-tresorerie.html#modale-formulaire
 *   maitre-refuse:m10-flux-tresorerie.html#modale-detail
 *   maitre-refuse:m10-flux-tresorerie.html#modale-suppression
 *   maitre-refuse:m10-flux-tresorerie.html#modale-export
 *   maitre-refuse:m10-flux-tresorerie.html#modale-import
 *
 * @see EF-M10-06
 */
#[Title('Tableau des Flux de Trésorerie — TATACORA AFRIQUE')]
class FluxTresorerie extends PageComptabilite
{
    public function render(): View
    {
        $socle = $this->socle();
        $exercice = $socle['exercice'];

        return view('pwa.comptabilite.flux-tresorerie', array_merge($socle, [
            'tafire' => $exercice === null ? null : app(TafireService::class)
                ->genererPourExercice($exercice->id, $this->statuts(), $this->filtreStatutValide()),
        ]))->layout('layouts.pwa');
    }
}
