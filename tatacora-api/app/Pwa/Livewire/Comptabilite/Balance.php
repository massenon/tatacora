<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Comptabilite;

use App\Domain\Comptabilite\Services\BalanceGeneraleService;
use Illuminate\View\View;
use Livewire\Attributes\Title;

/**
 * Balance Générale — `prototype_v2/pages/m10-balance.html`.
 *
 * Six colonnes dans l'ordre du maitre (l.34-38) : « N° Compte », « Libellé »,
 * « Total Débit », « Total Crédit », « Solde Débiteur », « Solde Créditeur ».
 * Les quatre montants sont alignes a droite. Pied « TOTAUX » et bandeau
 * d'equilibre, dont les deux phrases sont celles du maitre (l.60-62).
 *
 * ## Le maitre n'a AUCUN filtre sur cette page, et c'est respecte
 *
 * `ConsulterEtatComptableRequest` le note : « Sert la Balance Generale
 * (`m10-balance.html`, qui n'a AUCUN controle de filtre) ». Seul le socle
 * commun a M10 — l'exercice, obligatoire — figure ici.
 *
 * ## Une cellule vide n'est pas un zero
 *
 * Le maitre ecrit `${l.soldeDebiteur ? fmtFcfa(...) : ''}` (l.71-72) : la
 * colonne du sens inverse reste VIDE, elle n'affiche pas « 0 F ». Repris tel
 * quel — un compte crediteur qui afficherait « 0 F » en solde debiteur ferait
 * lire deux soldes la ou il n'y en a qu'un.
 *
 * @see EF-M10-06
 */
#[Title('Balance Générale — LogiReStock — TATACORA AFRIQUE')]
class Balance extends PageComptabilite
{
    public function render(): View
    {
        $socle = $this->socle();
        $exercice = $socle['exercice'];

        return view('pwa.comptabilite.balance', array_merge($socle, [
            'balance' => $exercice === null ? null : app(BalanceGeneraleService::class)
                ->genererPourExercice($exercice->id, $this->statuts(), $this->filtreStatutValide()),
        ]))->layout('layouts.pwa');
    }
}
