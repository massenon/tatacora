{{--
    LE MESSAGE DE SUCCES DE LA PWA — un seul auteur, un seul rendu.

    `FormulaireModal::terminerFormulaire()` et les gestes qui appellent
    directement `session()->flash('pwa-succes', ...)` deposent TOUS leur
    message sous cette meme cle. Ce partiel est ce qui le rend.

    ## Pourquoi il existe (03/09/2026)

    Le bloc etait recopie a la main dans 21 vues, et TROIS ecrans qui flashent
    ne le portaient pas du tout :

      - `Comptabilite\Hub::cloturerExercice()` — « Exercice cloture » ;
      - `Transverse\ContactEditeur` — « Message envoye », « Bug signale » ;
      - `Transverse\MonProfil` — « Mot de passe mis a jour ».

    Le geste avait lieu, la base etait ecrite, et l'utilisateur ne voyait
    RIEN. Le plus grave des trois est la cloture d'exercice : une operation
    comptable irreversible dont la confirmation se perdait, ce qui invite a
    la refaire. C'est la famille PA-59/60/61 dans son sens inverse — non pas
    un indicateur qui affirme sans verifier, mais une verite qui n'atteint
    jamais l'ecran.

    ⚠ Le defaut n'etait visible d'AUCUN test : les composants flashaient bien,
    et un test qui appelle l'action et lit la session voit le message. Seul le
    RENDU manquait. La garde qui empeche la reapparition est
    `tests/Feature/Pwa/ToastDeSuccesRenduTest.php` : elle confronte, par
    reflexion, les composants qui flashent et les vues qui rendent.

    ## Ce partiel ne remplace PAS les 21 blocs existants

    Deliberement : trois d'entre eux vivent dans des zones en cours de
    livraison par d'autres agents (`carte/`, `bar/`, `restaurant/`,
    `rh/paie`), et reecrire une vue qu'un autre modifie au meme moment
    produit un conflit sans rien corriger. Les blocs en place fonctionnent ;
    la garde les reconnait, quelle que soit leur forme. Ce partiel est le
    chemin des vues qui n'en avaient pas, et de toute vue future.

    Mise en page : celle de `transverse/parametres.blade.php`, qui portait
    deja la forme « bandeau » (les ecrans de type formulaire), par opposition
    a la forme « toast flottant » des ecrans de vente.
--}}
@if (session('pwa-succes'))
  <div class="rounded-xl px-4 py-3 mb-4 text-[13px] font-semibold"
       style="background:#E8F5E9;border:1px solid #A5D6A7;color:#1B5E20">{{ session('pwa-succes') }}</div>
@endif
