<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Comptabilite;

use App\Domain\Comptabilite\Services\CompteResultatService;
use Illuminate\View\View;
use Livewire\Attributes\Title;

/**
 * Compte de Résultat — `prototype_v2/pages/m10-resultat.html`.
 *
 * ## LE POINT LE PLUS DELICAT DE CE LOT : le bandeau « avant impôt »
 *
 * ECART DELIBERE — `m10-resultat.html` l.44
 * Le maitre : un bandeau ambre, TOUJOURS affiche, qui ecrit « taux IS non
 * encore fixé (PA-19) [...] le service refuse explicitement de calculer un
 * résultat net final tant que ce paramètre n'est pas configuré ».
 * Ici : le bandeau garde sa place, sa couleur et sa premiere affirmation —
 * « Résultat affiché avant Impôt sur les Sociétés » —, mais il n'apparait que
 * lorsque le serveur signale `impot_non_comptabilise`, et il ne parle plus
 * d'un taux.
 * Raison : cette phrase du maitre est FAUSSE contre le code livre, et PA-151
 * l'a etabli en toutes lettres — « PA-19 n'a jamais eu d'objet sur ces etats,
 * et le commentaire qui l'affirmait etait faux ». `CompteResultatService`
 * n'a AUCUNE dependance vers `ParametreSystemeService` : il n'additionne pas
 * `RAO × taux`, il lit ce qui est reellement comptabilise en classe 89. Il
 * n'existe donc aucun chemin par lequel un taux pourrait entrer, et rien a
 * « configurer ». Laisser la phrase enverrait un Comptable chercher un
 * parametre qui n'existe nulle part — c'est le defaut PA-144, un motif perime
 * qui transforme une decision en oubli. Et l'afficher quand l'impot EST
 * comptabilise annoncerait un resultat avant impot sur un resultat net reel.
 * Motif recevable : bug de maquette (Article 8, motif 2). Date du constat :
 * 27/08/2026, verifie contre `CompteResultatService` (aucun `use` de
 * `ParametreSystemeService`) et `routes/api.php` §M10.
 *
 * ## La cascade rendue est celle du SERVEUR, pas les onze lignes du maitre
 *
 * ECART DELIBERE — `m10-resultat.html` l.60-84
 * Le maitre : onze lignes bricolees a la main (« Produits d'exploitation »,
 * « Charges d'exploitation », « Résultat d'exploitation », « Produits
 * financiers », « Charges financières », « Résultat financier », « Résultat
 * des activités ordinaires (RAO) », « Produits HAO », « Charges HAO »,
 * « Résultat HAO », « RÉSULTAT AVANT IMPÔT SUR LES SOCIÉTÉS »).
 * Ici : la cascade complete des Soldes Intermediaires de Gestion telle que
 * `SoldesIntermediairesGestion::CASCADE` la definit, avec ses codes de liasse
 * (TA, RA, XA, XB, XC, XD, XE, XF, XG, XH, XI).
 * Raison : les onze libelles du maitre ne correspondent a AUCUNE grandeur que
 * le Service calcule — il n'existe ni « Produits d'exploitation » ni « Charges
 * d'exploitation » comme totaux dans le referentiel SYSCOHADA revise, qui
 * procede par soldes successifs. Les fabriquer ici serait recalculer une
 * regle de gestion dans un composant Livewire, ce que `LARAVEL_PWA.md` §3
 * interdit, et produirait des totaux que la Balance ne recouperait pas
 * (PA-121). Les codes affiches sont ceux de la cascade du Service, jamais des
 * references de liasse inventees : PA-151 point (6) rappelle qu'aucune colonne
 * `plan_comptable.type` n'existe et qu'aucun repere reglementaire ne doit
 * etre invente.
 * Refus declare : maitre-refuse:m10-resultat.html#page
 *
 * ## Les deux notes en italique du maitre ne sont pas portees
 *
 * ECART DELIBERE — `m10-resultat.html` l.68 et l.77
 * Le maitre : « Aucun compte financier défini pour TATACORA à ce stade (aucun
 * emprunt) — à 0 honnêtement, pas masqué. » et « Aucune opération HAO
 * identifiée dans le profil TATACORA actuel [...] — à 0 honnêtement. »
 * Ici : absentes.
 * Raison : ce sont deux affirmations sur le JEU DE DEMONSTRATION, vraies le
 * jour ou il a ete ecrit. Sur des donnees reelles elles deviendraient fausses
 * au premier emprunt et au premier produit de cession, sans que personne ne
 * les rouvre. Les lignes concernees restent affichees avec leur montant reel,
 * zero compris — ce que ces notes demandaient.
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
 *   maitre-refuse:m10-resultat.html#modale-formulaire
 *   maitre-refuse:m10-resultat.html#modale-detail
 *   maitre-refuse:m10-resultat.html#modale-suppression
 *   maitre-refuse:m10-resultat.html#modale-export
 *   maitre-refuse:m10-resultat.html#modale-import
 *
 * @see EF-M10-06
 */
#[Title('Compte de Résultat — TATACORA AFRIQUE')]
class CompteResultat extends PageComptabilite
{
    public function render(): View
    {
        $socle = $this->socle();
        $exercice = $socle['exercice'];

        return view('pwa.comptabilite.compte-resultat', array_merge($socle, [
            'resultat' => $exercice === null ? null : app(CompteResultatService::class)
                ->genererPourExercice($exercice->id, $this->statuts(), $this->filtreStatutValide()),
        ]))->layout('layouts.pwa');
    }
}
