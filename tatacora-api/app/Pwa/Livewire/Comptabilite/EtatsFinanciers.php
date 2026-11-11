<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Comptabilite;

use App\Domain\Comptabilite\ReadModels\EtatsFinanciers as EtatsFinanciersLus;
use App\Domain\Comptabilite\Services\BilanService;
use App\Domain\Comptabilite\Services\CompteResultatService;
use App\Domain\Comptabilite\Services\NotesAnnexesService;
use App\Domain\Comptabilite\Services\TafireService;
use Illuminate\View\View;
use Livewire\Attributes\Title;
use Livewire\Attributes\Url;

/**
 * États Financiers — `prototype_v2/pages/m10-etats-financiers.html`.
 *
 * Quatre onglets, dans l'ordre du maitre (l.53-112) et avec ses libelles :
 * « Bilan », « Compte de Résultat », « Flux de Trésorerie », « Notes
 * Annexes ». Onglet actif par defaut : « Bilan » (l.114), comme au maitre.
 *
 * ## Les quatre documents viennent d'UNE SEULE lecture
 *
 * Le maitre l'exige lui-meme (l.42) : « Réutilise exactement les mêmes
 * fonctions que les 4 écrans individuels — aucun recalcul indépendant ».
 * `EtatsFinanciersController::etatsFinanciers()` ajoute la raison qui compte :
 * quatre appels successifs pourraient encadrer une ecriture et produire un jeu
 * incoherent, sur des etats destines a etre signes. La composition est reprise
 * ici a l'identique, avec les memes Services.
 *
 * ## Ce qui n'est PAS porte — Article 8
 *
 * ECART DELIBERE — `m10-etats-financiers.html` l.36
 * Le maitre : un bouton « Exporter les 4 documents (PDF) ».
 * Ici : absent. Le panneau qui le nommait a l'ecran est supprime depuis le
 * 31/08/2026 (directive du Product Owner : plus aucune section « ce que cet
 * ecran ne fait pas ») ; la declaration vit en jeton code.
 * Raison : le maitre lui-meme n'exporte rien — son gestionnaire (l.129)
 * affiche « Export PDF consolidé — non implémenté dans ce démonstrateur
 * statique ». C'est le premier interdit de l'Article 6 : un bouton dont le
 * gestionnaire affiche une confirmation sans rien produire.
 *
 * ⚠ LA SECONDE MOITIE DE L'ANCIEN MOTIF ETAIT FAUSSE, et l'ecrire ici evite
 * qu'elle revienne : il affirmait que « tout export passe par
 * `GenerateurEtatService` (RG-19) ». Mesure du 31/08/2026 : quatorze classes
 * d'`app/Exports/` exportent DIRECTEMENT par `Excel::download()` et
 * `Pdf::loadView()`, dont `Depenses` qui est un ecran M10. RG-19 gouverne le
 * CATALOGUE d'etats de M14, pas les exports d'ecran.
 * Ce qui bloque REELLEMENT : exporter demande deux actions publiques
 * (`ouvrirExport`, `genererExport`) sur un composant dont la surface d'actions
 * est une liste fermee tenue par `tests/Feature/Pwa/PwaActionsReluesTest`,
 * hors du perimetre de ce lot. Remonte au rapport, pas tranche seul.
 * Refus declare : maitre-refuse:m10-etats-financiers.html#export
 *
 * ECART DELIBERE — `m10-etats-financiers.html` l.117
 * Le maitre : l'onglet « Notes Annexes » renvoie « voir m10-notes-annexes.html »
 * pour le detail des sept rubriques.
 * Ici : un lien vers la page Notes Annexes de la PWA.
 * Raison : Article 3.3 — une reference qui ne navigue pas est un defaut, et
 * l'ecran cible existe.
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
 *   maitre-refuse:m10-etats-financiers.html#modale-formulaire
 *   maitre-refuse:m10-etats-financiers.html#modale-detail
 *   maitre-refuse:m10-etats-financiers.html#modale-suppression
 *   maitre-refuse:m10-etats-financiers.html#modale-export
 *   maitre-refuse:m10-etats-financiers.html#modale-import
 *
 * @see EF-M10-06
 */
#[Title('États Financiers — LogiReStock — TATACORA AFRIQUE')]
class EtatsFinanciers extends PageComptabilite
{
    /**
     * Les quatre onglets, dans l'ordre du maitre.
     *
     * @var array<string, string>
     */
    public const ONGLETS = [
        'bilan' => 'Bilan',
        'resultat' => 'Compte de Résultat',
        'flux' => 'Flux de Trésorerie',
        'notes' => 'Notes Annexes',
    ];

    public const ONGLET_DEFAUT = 'bilan';

    #[Url(as: 'onglet')]
    public string $onglet = self::ONGLET_DEFAUT;

    public function render(): View
    {
        $socle = $this->socle();
        $exercice = $socle['exercice'];

        $ongletActif = array_key_exists($this->onglet, self::ONGLETS)
            ? $this->onglet
            : self::ONGLET_DEFAUT;

        $etats = null;

        if ($exercice !== null) {
            $statuts = $this->statuts();
            $filtre = $this->filtreStatutValide();

            $etats = new EtatsFinanciersLus(
                exerciceId: $exercice->id,
                bilan: app(BilanService::class)->genererPourExercice($exercice->id, $statuts, $filtre),
                compteResultat: app(CompteResultatService::class)->genererPourExercice($exercice->id, $statuts, $filtre),
                tafire: app(TafireService::class)->genererPourExercice($exercice->id, $statuts, $filtre),
                notesAnnexes: app(NotesAnnexesService::class)->genererPourExercice($exercice, $statuts, $filtre),
            );
        }

        return view('pwa.comptabilite.etats-financiers', array_merge($socle, [
            'ongletActif' => $ongletActif,
            'etats' => $etats,
        ]))->layout('layouts.pwa');
    }
}
