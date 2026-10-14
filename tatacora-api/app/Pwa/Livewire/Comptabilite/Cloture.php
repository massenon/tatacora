<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Comptabilite;

use App\Domain\Comptabilite\Services\EtatClotureService;
use Illuminate\View\View;
use Livewire\Attributes\Title;

/**
 * Clôture Périodique — `prototype_v2/pages/m10-cloture.html`.
 *
 * Six groupes d'etapes, dans l'ordre et avec les intitules du maitre
 * (l.44-100). `EtatClotureService::etapes()` les transcrit deja — « Les six
 * blocs de `m10-cloture.html`, dans son ordre », dit son propre bloc de
 * documentation. La vue ne fait que les rendre.
 *
 * ## CET ECRAN NE DECLENCHE RIEN, ET LE MAITRE NON PLUS
 *
 * Verifie le 27/08/2026 : `m10-cloture.html` ne porte AUCUN bouton — ni
 * « Clôturer », ni « Ouvrir un exercice ». C'est un tableau de bord d'etat.
 * `EtatCloture::actionExposee` vaut `false` cote serveur, et le champ est
 * rendu a l'ecran plutot que tu : sans lui, un ecran qui ne propose rien
 * serait indiscernable d'un ecran casse.
 *
 * Les actions de cloture existent en revanche sur l'ONGLET « Clôtures » du hub
 * (`m10-syscohada-etats.js` l.446, l.469, l.489 : « Ouvrir un exercice »,
 * « Clôturer » une periode, « Clôturer l'exercice »). Elles ne sont PAS
 * rendues — ni ici, ni sur l'onglet.
 *
 * ⚠ LE MOTIF A CHANGE, ET L'ANCIEN NE DOIT PAS ETRE REMIS. Il invoquait
 * `LARAVEL_PWA.md` §6, qui exclut la « validation d'écriture comptable » de la
 * PWA : cette exclusion est LEVEE depuis le 28/08/2026 (PA-159). Le motif
 * REEL, verifie le 31/08/2026, est en aval : aucun Service de domaine ne
 * cloture — `EtatClotureService` ne publie que l'ETAT, et PA-151 note qu'aucune
 * route serveur ne l'expose non plus. Un bouton « Clôturer » n'aurait rien a
 * appeler, ce qui est le premier interdit de l'Article 6.
 *
 * ⚠ Ces deux phrases etaient, jusqu'au 31/08/2026, un panneau « Ce que cet
 * ecran ne fait pas » rendu sous le selecteur d'exercice, ici et sur l'onglet
 * du hub. La directive du Product Owner du 31/08/2026 supprime ces sections :
 * le refus se declare en jeton code. Ce qui RESTE a l'ecran est d'une autre
 * nature et doit y rester — « Ce que ce controle ne peut pas verifier »
 * (`limitesNonVerifiables`) est un ETAT calcule par le Service, pas une
 * declaration de portage.
 * Refus declares :
 *   maitre-refuse:m10-cloture.html#page
 *   maitre-refuse:m10-syscohada.html#clotures
 *
 * ## QUATRE ETATS D'ETAPE, ET LES MELANGER SERAIT LE DEFAUT
 *
 * `conforme`, `bloque`, `non_verifiable`, `non_atteint`. Les deux derniers ne
 * sont pas des echecs : `non_verifiable` couvre une limite reelle du domaine
 * (l'inventaire physique appartient a M6), `non_atteint` une etape qui depend
 * d'une precedente. Les rendre en rouge ferait chercher une anomalie qui
 * n'existe pas ; les rendre en vert affirmerait un controle qui n'a pas eu
 * lieu (PA-59/60/61). Quatre traitements visuels distincts, donc.
 *
 * ## Ce qui n'est PAS porte — Article 8
 *
 * ECART DELIBERE — `m10-cloture.html` l.75
 * Le maitre : l'etape 3c est marquee « BLOQUÉ par PA-19 — taux d'Impôt sur les
 * Sociétés non configuré. Le service refuse explicitement de clore tant que ce
 * paramètre est absent ».
 * Ici : l'etat rendu par `EtatClotureService`, ou l'impot non comptabilise est
 * un AVERTISSEMENT non bloquant.
 * Raison : PA-151 point (4) constate que deux pages du maitre se contredisent
 * — `m10-cloture.html` en fait un blocage, le moteur du hub un avertissement —
 * et que le hub a ete retenu, sans effet operationnel. La raison de fond est
 * la meme qu'au Compte de resultat : il n'existe aucun taux d'IS a configurer,
 * `CompteResultatService` lisant la classe 89 reellement comptabilisee. Une
 * incoherence entre deux pages du maitre se signale au commanditaire et ne se
 * tranche pas seul (Article 8) — elle est ouverte en PA-151, l'ecran suit le
 * serveur, et le dit.
 *
 * ECART DELIBERE — `m10-cloture.html` l.34
 * Le maitre : les notes des etapes citent « ce jeu de démonstration » et
 * « ce démonstrateur statique ».
 * Ici : les motifs a code ferme du serveur, traduits dans `lang/fr/pwa.php`.
 * Raison : `EtatClotureService` VERIFIE reellement ce que le maitre affirmait
 * (journal AN, comptes 131/139, centre de cloture) — PA-151 : « Les blocages
 * de cloture etaient AFFIRMES, pas detectes ». Recopier les notes du maitre
 * reintroduirait exactement ce que ce correctif a retire.
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
 *   maitre-refuse:m10-cloture.html#modale-formulaire
 *   maitre-refuse:m10-cloture.html#modale-detail
 *   maitre-refuse:m10-cloture.html#modale-suppression
 *   maitre-refuse:m10-cloture.html#modale-export
 *   maitre-refuse:m10-cloture.html#modale-import
 *
 * @see EF-M10-07 Cloture comptable periodique
 * @see PA-28 « Clôture périodique » et « Clôture d'exercice » restent deux
 *      concepts distincts non tranches — la note du maitre (l.32) est
 *      conservee a ce titre : verifiee le 27/08/2026, PA-28 est toujours
 *      ouvert.
 */
#[Title('Clôture Périodique — TATACORA AFRIQUE')]
class Cloture extends PageComptabilite
{
    public function render(): View
    {
        $socle = $this->socle();
        $exercice = $socle['exercice'];

        return view('pwa.comptabilite.cloture', array_merge($socle, [
            'cloture' => $exercice === null ? null : app(EtatClotureService::class)
                ->genererPourExercice($exercice, $this->statuts(), $this->filtreStatutValide()),
        ]))->layout('layouts.pwa');
    }
}
