<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Comptabilite;

use App\Domain\Comptabilite\Exceptions\EtatTropVolumineuxException;
use App\Domain\Comptabilite\Models\CompteComptable;
use App\Domain\Comptabilite\Services\GrandLivreService;
use Illuminate\View\View;
use Livewire\Attributes\Title;
use Livewire\Attributes\Url;

/**
 * Grand Livre — `prototype_v2/pages/m10-grand-livre.html`.
 *
 * Six colonnes dans l'ordre du maitre (l.39-41) : « Date », « Journal »,
 * « Libellé », « Débit », « Crédit », « Solde progressif ». Un selecteur de
 * compte au-dessus, et l'etat vide du maitre mot pour mot (l.46) : « Ce compte
 * n'a aucun mouvement sur l'exercice. »
 *
 * ## Le selecteur ne propose QUE les comptes mouvementes
 *
 * `m10-grand-livre.html` l.55 le motive lui-meme, en citant
 * `MODULE_COMPTABILITE_COMPLET.md` Partie 1 §3 : « le Grand Livre restitue
 * l'activite reelle, pas le referentiel complet ». `GrandLivreService::
 * comptesMouvementes()` applique la meme regle, sur les memes statuts que
 * l'etat lui-meme.
 *
 * ## Le solde d'ouverture est INCONNU, jamais zero
 *
 * `GrandLivre::soldeOuverture` vaut `null` avec le motif
 * `report_a_nouveau_absent` : aucun mecanisme de report a nouveau n'existe.
 * Le maitre n'affiche aucune ligne d'ouverture, donc rien n'est retire — mais
 * le motif est rendu sous le tableau plutot que tu : un solde progressif qui
 * part de zero sans le dire laisserait croire a un compte neuf.
 * (PA-148, cas `article7_le_solde_d_ouverture_est_inconnu_jamais_zero`.)
 *
 * @see EF-M10-06
 */
#[Title('Grand Livre — LogiReStock — TATACORA AFRIQUE')]
class GrandLivre extends PageComptabilite
{
    #[Url(as: 'compte')]
    public string $compteId = '';

    public function render(): View
    {
        $socle = $this->socle();
        $exercice = $socle['exercice'];

        $comptes = collect();
        $grandLivre = null;
        $refusDeVolume = null;
        $compteRetenu = null;

        if ($exercice !== null) {
            $service = app(GrandLivreService::class);
            $comptes = $service->comptesMouvementes($exercice->id, $this->statuts());

            // Le compte demande vient de l'URL : s'il n'est pas mouvemente, on
            // retombe sur le premier de la liste plutot que de lever, comme le
            // maitre qui ouvre sur `comptesMouvementes[0]` (l.79).
            $compteRetenu = $this->compteId === ''
                ? $comptes->first()
                : $comptes->firstWhere('id', $this->compteId);

            if ($compteRetenu instanceof CompteComptable) {
                try {
                    $grandLivre = $service->genererPourCompte(
                        $exercice->id,
                        $compteRetenu,
                        $this->statuts(),
                        $this->filtreStatutValide(),
                    );
                } catch (EtatTropVolumineuxException $exception) {
                    $refusDeVolume = $exception->getMessage();
                }
            }
        }

        return view('pwa.comptabilite.grand-livre', array_merge($socle, [
            'comptesMouvementes' => $comptes,
            'compteRetenu' => $compteRetenu,
            'grandLivre' => $grandLivre,
            'refusDeVolume' => $refusDeVolume,
        ]))->layout('layouts.pwa');
    }
}
