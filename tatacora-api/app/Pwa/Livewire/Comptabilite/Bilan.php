<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Comptabilite;

use App\Domain\Comptabilite\Services\BilanService;
use Illuminate\View\View;
use Livewire\Attributes\Title;

/**
 * Bilan de l'Entreprise — `prototype_v2/pages/m10-bilan.html`.
 *
 * Deux cartes cote a cote, « ACTIF » a gauche et « PASSIF » a droite, dans
 * l'ordre et avec les intitules de section du maitre (l.55-70) : « Actif
 * immobilisé », « Actif circulant », « Trésorerie-Actif », « TOTAL ACTIF » ;
 * « Capitaux propres », « Passif circulant », « TOTAL PASSIF ». Les libelles
 * descriptifs de ligne sont eux aussi ceux du maitre.
 *
 * ## UN POSTE EST AJOUTE AU PASSIF, et c'est ce qui empeche le total de mentir
 *
 * ECART DELIBERE — `m10-bilan.html` l.68-70
 * Le maitre : le passif ne porte que deux postes — capitaux propres et passif
 * circulant.
 * Ici : un troisieme, « Trésorerie-Passif », rendu entre les deux et le total.
 * Raison : `BilanService` en calcule trois (l.113-137). Un compte 521
 * crediteur est un DECOUVERT bancaire, donc une tresorerie-passif, et
 * `totalPassif` l'inclut. L'omettre laisserait « TOTAL PASSIF » superieur a la
 * somme des lignes affichees le jour du premier decouvert, sans qu'aucune
 * ligne ne l'explique — le lecteur conclurait a une erreur de calcul sur le
 * seul etat ou l'equilibre est la garantie. L'ajout est le moindre des deux
 * ecarts. Motif recevable : element decoratif au sens de l'Article 8 motif 1 —
 * la maquette simule un passif a deux postes, on implemente le vrai.
 *
 * ## Les comptes HORS RUBRIQUE sont nommes, jamais tus
 *
 * `Bilan::comptesHorsRubrique` liste les comptes MOUVEMENTES dont le solde
 * n'apparait ni au Bilan ni au Compte de Resultat. Sans eux, un compte ouvert
 * hors nomenclature ne produirait qu'un desequilibre inexplicable ; avec eux,
 * l'ecran nomme le compte fautif et son solde. Le maitre n'a pas ce bloc parce
 * que son jeu de demonstration n'a pas ce cas.
 *
 * ## Ce qui n'est PAS porte — Article 8
 *
 * ECART DELIBERE — `m10-bilan.html` l.48-50
 * Le maitre : sous les deux cartes, « Aucune immobilisation ni amortissement
 * dans les données de démonstration actuelles — reflet honnête du jeu de
 * données, pas une omission de calcul. »
 * Ici : absente.
 * Raison : affirmation sur le jeu de demonstration, fausse des la premiere
 * immobilisation reelle. Le poste « Actif immobilisé » affiche son montant
 * reel, zero compris — ce que la note demandait de garantir.
 *
 * Aucune reference de liasse (AD, AI, BB, CA, DR...) n'est affichee : PA-151
 * point (6) etablit qu'elles supposent une colonne `plan_comptable.type` a 19
 * valeurs QUI N'EXISTE PAS au schema. Un faux repere reglementaire sur un etat
 * financier est interdit.
 *
 * @see EF-M10-06
 */
#[Title("Bilan de l'Entreprise — TATACORA AFRIQUE")]
class Bilan extends PageComptabilite
{
    public function render(): View
    {
        $socle = $this->socle();
        $exercice = $socle['exercice'];

        return view('pwa.comptabilite.bilan', array_merge($socle, [
            'bilan' => $exercice === null ? null : app(BilanService::class)
                ->genererPourExercice($exercice->id, $this->statuts(), $this->filtreStatutValide()),
        ]))->layout('layouts.pwa');
    }
}
