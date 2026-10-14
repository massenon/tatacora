<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Comptabilite;

use App\Domain\Comptabilite\Exceptions\EtatTropVolumineuxException;
use App\Domain\Comptabilite\Services\JournalGeneralService;
use Illuminate\View\View;
use Livewire\Attributes\Title;
use Livewire\Attributes\Url;

/**
 * Journal Comptable — `prototype_v2/pages/m10-journal.html`.
 *
 * Six colonnes dans l'ordre du maitre (l.40-42) : « Date », « Journal »,
 * « Compte », « Libellé », « Débit », « Crédit ». Les deux montants sont
 * alignes a droite, comme au maitre. Pied « TOTAUX » et bandeau d'equilibre.
 *
 * ## Le bandeau d'equilibre du maitre ne s'affiche PAS quand un journal est
 * filtre, et c'est juste
 *
 * `m10-journal.html` l.90 : `journalActif ? '' : ...`. Un journal isole n'a
 * aucune raison d'etre equilibre — seule la comptabilite entiere l'est. La
 * condition est reprise telle quelle : l'afficher sur un filtre annoncerait
 * une anomalie a chaque consultation d'un journal de ventes.
 *
 * ## Ce qui n'est PAS porte — Article 8
 *
 * ECART DELIBERE — `m10-journal.html` l.71
 * Le maitre : trois boutons de journal ecrits en dur (`VTE`, `ACH`, `OD`).
 * Ici : un bouton par journal REELLEMENT present au referentiel.
 * Raison : voir `PageComptabilite::journaux()`. Le referentiel en porte cinq ;
 * recopier les trois du maitre rendrait les journaux de banque et de caisse
 * inatteignables sur l'ecran fait pour les retrouver.
 *
 * ECART DELIBERE — `m10-journal.html` l.29
 * Le maitre : « Toutes les écritures, tous journaux confondus, par ordre
 * chronologique » — un sous-titre exact, mais qui suppose un seul exercice.
 * Ici : la meme phrase, sous un exercice explicitement choisi.
 * Raison : `MODULE_COMPTABILITE_COMPLET.md` §1 interdit un etat « toutes
 * annees confondues ».
 *
 * @see EF-M10-06
 */
#[Title('Journal Comptable — TATACORA AFRIQUE')]
class Journal extends PageComptabilite
{
    #[Url(as: 'journal')]
    public string $journalId = '';

    public function render(): View
    {
        $socle = $this->socle();
        $exercice = $socle['exercice'];

        $journal = null;
        $refusDeVolume = null;

        if ($exercice !== null) {
            try {
                $journal = app(JournalGeneralService::class)->genererPourExercice(
                    $exercice->id,
                    $this->statuts(),
                    $this->journalId === '' ? null : $this->journalId,
                    $this->filtreStatutValide(),
                );
            } catch (EtatTropVolumineuxException $exception) {
                // Article 7 : le message du refus, jamais une exception
                // technique. Il porte le decompte reel et le plafond, donc de
                // quoi decider quoi filtrer.
                $refusDeVolume = $exception->getMessage();
            }
        }

        return view('pwa.comptabilite.journal', array_merge($socle, [
            'journalId' => $this->journalId,
            'journaux' => $exercice === null ? collect() : $this->journaux(),
            'journal' => $journal,
            'refusDeVolume' => $refusDeVolume,
        ]))->layout('layouts.pwa');
    }
}
