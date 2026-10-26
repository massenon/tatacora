{{--
    TABLEAU DE BORD (M11) — PWA.

    Maître : `prototype_v2/pages/tableau-de-bord.html`.
    Composant : `app/Pwa/Livewire/Accueil.php`.

    ⚠ CETTE CITATION EST CE QUI REND L'ÉCRAN MESURABLE.
    `prototype_v2/tests/t-trois-sources.js` n'entretient AUCUNE table de
    correspondance : il ancre chaque page sur le commentaire qui la cite. Une
    page portée sans citer son maître apparaît comme non portée, et rien n'est
    alors comparé — ni son titre, ni ses onglets, ni ses modales.

    ## LA REPRISE DU 02/09/2026 — CE QUE LE PRODUCT OWNER A VU

    Le Product Owner a ouvert `/pwa` et `tableau-de-bord.html` côte à côte :
    « les sections, les widgets, les onglets sont différents ». Les gardes
    étaient vertes, et elles avaient raison sur ce qu'elles mesuraient :
    `t-structure.js` compare le squelette de l'onglet OUVERT, `t-trois-sources`
    des libellés — aucune ne voyait qu'un tiers de la page manquait derrière
    un `@if` d'onglet jamais rendu.

    Cinq manques ont été repris, dans l'ordre du maître :

    1. LES ONGLETS BASCULAIENT PAR LE SERVEUR (`?panel=`). Chaque clic était un
       aller-retour Livewire, et le panneau non affiché n'existait pas dans le
       DOM. Les trois panneaux sont désormais MONTÉS et la bascule est locale —
       exactement le motif du maître, dont le commentaire donne la raison
       (`tableau-de-bord.html` l.464-468) : « Chart.js a besoin d'un canvas
       attaché au document pour mesurer, et un graphe construit dans un
       conteneur `display:none` sort à zéro pixel. » Le paramètre d'URL reste
       une ENTRÉE (lien profond, favori) ; `history.replaceState` le tient à
       jour sans requête.
    2. Le récapitulatif de la journée et le bandeau d'alertes de stock
       n'existaient pas.
    3. Deux des trois graphiques de l'exploitation manquaient, et les deux du
       pilotage aussi.
    4. Les tableaux avaient 5 et 4 colonnes là où le maître en pose 7 et 5.
    5. Le tableau croisé n'avait AUCUN sélecteur : il rendait deux lignes fixes.

    ## LES GRAPHIQUES DU MAÎTRE SONT DES GRAPHIQUES — Chart.js local

    `public/assets/js/vendor/chart.umd.min.js` est vendorisé (copié à
    l'identique du maître le 31/08/2026), chargé par cette vue, jamais depuis
    un CDN : `ConformiteMaquettePwaTest` refuse toute ressource distante, la
    PWA doit rester servable sans Internet. `wire:ignore` sur chaque conteneur
    de canvas — Livewire détruirait le graphique au re-rendu, en silence.

    ## AUCUN FORMULAIRE NE SE REND AU PREMIER GET

    Les six modales vivent derrière `@if ($etatFormulaire === …)`, et l'état ne
    s'ouvre qu'après une action gardée par `exigerEcriture()`. C'est la règle qui
    rend `RefuseLaSaisie` compatible avec un écran qui écrit.

    ## LES ÉCARTS QUI SUBSISTENT, DÉCLARÉS PLUTÔT QUE DÉCOUVERTS

    ECART DELIBERE — `tableau-de-bord.html` l.9-10 (`jspdf`, `xlsx`)
    Le maître : deux bibliothèques chargées dans la page pour produire le PDF
    et le classeur DANS le navigateur.
    Ici : aucune des deux.
    Raison : la PWA exporte côté SERVEUR — DomPDF (PA-47, pur PHP, cPanel
    mutualisé interdit les binaires) et Maatwebsite/Excel. Embarquer 1,2 Mo de
    bibliothèques qu'aucune ligne n'appellerait serait du code mort servi à
    chaque chargement de page.
    Refus déclaré : maitre-refuse:tableau-de-bord.html#exports-client

    REFUS LEVÉ le 01/09/2026 (PA-163) — colonnes « Services » et « Canal »,
    champ « Canal de réservation » de la modale rapide.
    Le refus antérieur (jeton `maitre-refuse:tableau-de-bord.html#services-canal`)
    tenait à un schéma qui ne portait ni service ni canal (PA-110/PA-29).
    Décision du Product Owner : `reservations.canal_id`, la fiche complète et
    `lignes_reservation` existent depuis les migrations `2026_09_03_*`. Les
    pastilles de services se DÉRIVENT (`unite_id` = Hébergement, plus les
    lignes) et le canal est une vraie clé étrangère — le tiret n'a plus lieu.

    ECART DELIBERE — colonne « Unité » (`tableau-de-bord.html` l.145)
    Le maître : un code court et un nom d'unité (« Chambre Baobab »).
    Ici : la colonne est rendue avec un tiret.
    Raison : `unites_hebergement` porte UN seul identifiant, `numero`, déjà
    rendu en « Code » (schéma relu le 02/09/2026). Répéter le numéro sous deux
    en-têtes différents laisserait croire à deux données.
    Refus déclaré : maitre-refuse:tableau-de-bord.html#unite-libelle

    ECART DELIBERE — badge « Réseau Synchronisé »
    La PWA n'a AUCUNE pile hors ligne, elle lit le serveur en direct. Afficher
    « synchronisé » serait affirmer un état que personne ne vérifie (PA-61).
    Refus déclaré : maitre-refuse:tableau-de-bord.html#reseau-synchronise

    ECART DELIBERE — les cinq autres rapports du maître
    « Liste des réservations », « État des stocks », « État de créances »,
    « État de recettes », « État de ventes » : le moteur d'états applique le
    RBAC du module SOURCE (RG-19) ; les produire ici donnerait à un rôle ce
    que son module lui refuse. Ils vivent au Studio des états (M14).
    Refus déclaré : maitre-refuse:tableau-de-bord.html#rapports-m14

    ECART DELIBERE — `m11-pilotage.html` l.51-59 (bandeau de compatibilité)
    Le maître garde son ancienne page pour qu'un favori ne tombe pas dans le
    vide. La PWA n'a jamais eu de seconde URL de pilotage : un bandeau
    annonçant une redirection vers la page où l'on se trouve déjà serait un
    contrôle inerte (Article 6).
    Refus déclaré : maitre-refuse:m11-pilotage.html#page

    REFUS LEVÉ le 02/09/2026 — `m11-pilotage.js` l.128 (« Masse salariale »)
    Le motif confondait deux grandeurs distinctes : la MASSE SALARIALE
    (somme des salaires de base des bulletins réellement établis — un fait)
    et le COÛT EMPLOYEUR TOTAL, que `CalculPaieService` refuse à raison tant
    que le taux CNSS « risques professionnels » n'est pas confirmé pour
    l'hôtellerie (PA-53). `LivreDePaieService::totaux()` porte déjà les deux
    séparément — `brut` (un chiffre) et `cout_min`/`cout_max` (une
    fourchette, jamais sommée). La sixième carte affiche `brut`, jamais le
    coût employeur. Sans bulletin établi pour le mois en cours, la carte
    affiche l'absence réelle — jamais « 0 F », qui se lirait comme une masse
    salariale nulle plutôt que comme une paie non encore établie.
--}}
@php
    use App\Pwa\Livewire\Accueil;
    use App\Pwa\Support\MontantFcfa;

    $classeOnglet = static fn (bool $actif): string => \App\Pwa\Support\Onglets::classes($actif);

    $classeMois = static fn (bool $actif): string =>
        'px-2.5 py-1 rounded text-[12px] font-semibold '
        . ($actif ? 'bg-[var(--navy)] text-white' : 'border border-slate-200 text-slate-500');

    // Les trois gravités du panneau « À traiter », avec les couleurs du maître
    // (`m11-pilotage.js` l.203-207) : fond, pastille, texte.
    $couleursAlerte = [
        'rouge' => ['#FEF2F2', '#DC2626', '#7F1D1D'],
        'amber' => ['#FFFBEB', '#B8891E', '#78350F'],
        'info' => ['#F8FAFC', '#64748B', '#334155'],
    ];

    // Les cinq accès rapides du maître (`tableau-de-bord.js` l.119-125) —
    // icône, couleur et libellé au caractère près. `couleur15` est la teinte de
    // fond de la pastille : le maître écrit `${a.couleur}15`, ce qui produit
    // `var(--navy)15` — une valeur CSS invalide, donc une pastille sans fond.
    // La couleur résolue est écrite ici, le fond est réellement peint.
    $iconesAccesRapide = [
        'reservation' => ['#14213D', '<path stroke-linecap="round" d="M12 5v14M5 12h14"/>'],
        'client' => ['#1D4ED8', '<circle cx="9" cy="7" r="4"/><path stroke-linecap="round" stroke-linejoin="round" d="M17 21v-2a4 4 0 00-4-4H5a4 4 0 00-4 4v2M20 8v6M23 11h-6"/>'],
        'stocks' => ['#ED6C02', '<path stroke-linecap="round" stroke-linejoin="round" d="M12 9v4m0 4h.01M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z"/>'],
        'rapport' => ['#6B7280', '<path stroke-linecap="round" stroke-linejoin="round" d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/><path stroke-linecap="round" stroke-linejoin="round" d="M14 2v6h6"/>'],
        'depense' => ['#B8891E', '<circle cx="9" cy="21" r="1"/><circle cx="20" cy="21" r="1"/><path stroke-linecap="round" stroke-linejoin="round" d="M1 1h4l2.68 13.39a2 2 0 002 1.61h9.72a2 2 0 002-1.61L23 6H6"/>'],
    ];

    // Les huit pastilles d'indicateur, DANS L'ORDRE DE
    // `TableauDeBordService::indicateurs()` — qui est aussi celui du maître
    // (`tableau-de-bord.html` l.404-411). La clé est celle du service : elle
    // n'est pas recopiée, elle est LUE, et un indicateur renommé côté domaine
    // perdrait son icône plutôt que d'en recevoir une fausse.
    $iconesKpi = [
        'chiffre_affaires_encaisse' => ['var(--succes)', '#E8F5E9', '<path stroke-linecap="round" stroke-linejoin="round" d="M23 6l-9.5 9.5-5-5L1 18"/><path stroke-linecap="round" stroke-linejoin="round" d="M17 6h6v6"/>'],
        'taux_occupation' => ['var(--navy)', '#E8EEFD', '<path stroke-linecap="round" stroke-linejoin="round" d="M2 4v16M2 8h18a2 2 0 012 2v10M2 17h20"/>'],
        'tresorerie_caisse' => ['var(--gold)', '#FDF3E0', '<rect x="2" y="7" width="20" height="14" rx="2"/><path stroke-linecap="round" stroke-linejoin="round" d="M16 3H8v4h8V3z"/>'],
        'depenses_cumulees' => ['var(--erreur)', '#FDECEC', '<path stroke-linecap="round" stroke-linejoin="round" d="M12 2v20M17 5H9.5a3.5 3.5 0 000 7h5a3.5 3.5 0 010 7H6"/>'],
        'reservations_en_attente' => ['var(--gold)', '#FDF3E0', '<rect x="3" y="4" width="18" height="18" rx="2"/><path stroke-linecap="round" stroke-linejoin="round" d="M16 2v4M8 2v4M3 10h18"/>'],
        'factures_impayees' => ['var(--erreur)', '#FDECEC', '<path stroke-linecap="round" stroke-linejoin="round" d="M6 2h9l5 5v13a2 2 0 01-2 2H6a2 2 0 01-2-2V4a2 2 0 012-2z"/>'],
        'valeur_stock' => ['#1D4ED8', '#E8EEFD', '<path stroke-linecap="round" stroke-linejoin="round" d="M21 8l-9-5-9 5 9 5 9-5zM3 8v8l9 5 9-5V8"/>'],
        'employes_actifs' => ['var(--succes)', '#E8F5E9', '<rect x="2" y="4" width="20" height="16" rx="2"/><circle cx="9" cy="10" r="2"/><path stroke-linecap="round" stroke-linejoin="round" d="M15 8h4M15 12h4M6 16h6"/>'],
    ];

    // Rend la valeur d'un indicateur selon son UNITÉ — le service la déclare,
    // l'écran ne la devine pas.
    $valeurKpi = static function (array $kpi): string {
        if ($kpi['unite'] === 'montant') {
            return MontantFcfa::format($kpi['valeur']);
        }

        return $kpi['unite'] === 'pourcentage' ? $kpi['valeur'] . ' %' : $kpi['valeur'];
    };
@endphp

<div class="contents">

  {{-- `.carte-kpi` vient du `<style>` DE PAGE du maître (`tableau-de-bord.html`
       l.15-16) et n'existe pas dans `public/assets/css/app.css`. Il est
       transcrit ici, à la ligne près, plutôt que posé comme une classe que
       rien ne lit — une fidélité apparente, sans effet, est pire qu'un écart
       déclaré. Il vit dans CETTE vue et non dans la feuille commune : c'est le
       seul écran du maître qui le porte. --}}
  <style>
    .carte-kpi { transition: transform .12s ease, box-shadow .12s ease; }
    .carte-kpi:hover { transform: translateY(-1px); box-shadow: 0 4px 12px rgba(20,33,61,.08); }

    /* ⚠ LA VISIBILITÉ DES DEUX BANDES D'INDICATEURS EST EN CSS, PAS EN JS,
       ET LES DEUX RAISONS COMPTENT.

       1. Pas de scintillement. Une bascule pilotée par Alpine ne s'applique
          qu'APRÈS le premier rendu : sur un écran large, les seize cartes
          (huit par conteneur) s'afficheraient un instant avant que la moitié
          disparaisse. C'est exactement le genre de défaut qui ne se voit que
          sur la machine du client, sur une connexion lente.
       2. Pas de classe de disposition. `lg:hidden` et `lg:grid` sont des
          classes de SIGNATURE pour `t-structure.js` (l.500) : les poser sur
          ces conteneurs changerait le squelette comparé au maître, et la page
          cesserait d'être « identique » pour une raison qui n'a rien de
          structurel. Le sélecteur d'attribut porte donc la règle, et la
          spécificité `div[data-…]` passe devant `.grid` de Tailwind. */
    div[data-bande-kpi="accordeon"] { display: none; }
    div[data-bande-kpi="accordeon"][data-ouvert="1"] { display: grid; }

    @media (min-width: 1024px) {
      /* Au-delà de `lg`, c'est la grille du maître qui porte les huit cartes ;
         l'accordéon reste replié quoi qu'il arrive — son bouton est d'ailleurs
         en `lg:hidden`, comme au maître. */
      div[data-bande-kpi="accordeon"] { display: none; }
      div[data-bande-kpi="large"] { display: grid; }
    }

    @media (max-width: 1023.98px) {
      div[data-bande-kpi="large"] { display: none; }
    }
  </style>

  @include('pwa.partials.barre-superieure')

  <div class="flex flex-1 overflow-hidden">
    @include('pwa.partials.menu-lateral')

    <main class="flex-1 overflow-y-auto">
      <div class="max-w-[1440px] mx-auto p-5 lg:p-8">

        {{-- En-tête d'impression : `<h2>`, jamais un second `<h1>`. --}}
        <div class="hidden print:block mb-6 border-b-2 border-[var(--navy)] pb-4">
          <h2 class="text-xl font-bold" style="color:var(--navy)">TATACORA AFRIQUE — GÎTE CHEZ NOËL</h2>
          <p class="text-xs text-slate-600 mt-1">{{ $tableauDeBordAutorise ? __('accueil_pwa.titre').' — '.$periode->libelle() : __('pwa.accueil.titre') }}</p>
        </div>

        @if (session('pwa-succes'))
          <div class="rounded-xl px-4 py-3 mb-4 text-[13px] font-semibold"
               style="background:#E8F5E9;border:1px solid #A5D6A7;color:#1B5E20">
            {{ session('pwa-succes') }}
          </div>
        @endif

        {{-- ================= EN-TÊTE + PÉRIODE + EXPORTS ================= --}}
        <div class="flex flex-col lg:flex-row lg:items-center gap-3 mb-5">
          <div>
            {{-- ⚠ LE TITRE DIT CE QUE LA PAGE EST, POUR CE ROLE (31/08/2026).

                 `/pwa` est la page d'atterrissage de TOUS les rôles : sa route
                 ne porte pas de `module:M11`, sans quoi un `guide` n'aurait
                 plus aucune page où arriver après sa connexion. Elle rendait
                 pourtant le tableau de bord M11 — titre, onglets, période,
                 exports et quatorze indicateurs consolidés — à qui la matrice
                 RBAC refuse M11. --}}
            <div class="flex items-center gap-2.5">
              <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--navy)" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M3 3v18h18M18 17V9M13 17V5M8 17v-3"/></svg>
              <h1 class="text-lg lg:text-xl font-bold" style="color:var(--navy)">{{ $tableauDeBordAutorise ? __('accueil_pwa.titre') : __('pwa.accueil.titre') }}</h1>
            </div>
            <p class="text-[15px] text-slate-500 mt-1">{{ $tableauDeBordAutorise ? __('accueil_pwa.sous_titre') : __('pwa.accueil.sous_titre') }}</p>

            @if ($tableauDeBordAutorise)
              {{-- ⚠ AUCUN `wire:click` ICI, ET C'EST LA CORRECTION DU 02/09/2026.
                   La bascule est LOCALE : les trois panneaux sont montés, on ne
                   masque que les conteneurs. Un `wire:click="$set('onglet', …)"`
                   faisait un aller-retour serveur par clic et ne montait qu'un
                   panneau — donc un canvas Chart.js construit dans un conteneur
                   masqué, qui sort à zéro pixel (le maître le dit lui-même,
                   `tableau-de-bord.html` l.464-468). --}}
              <div class="flex gap-2 mt-3">
                <button type="button" data-onglet-tb="exploitation" class="{{ $classeOnglet($ongletAffiche === 'exploitation') }}">{{ __('accueil_pwa.onglets.exploitation') }}</button>
                <button type="button" data-onglet-tb="pilotage" class="{{ $classeOnglet($ongletAffiche === 'pilotage') }}">{{ __('accueil_pwa.onglets.pilotage') }}</button>
                <button type="button" data-onglet-tb="croise" class="{{ $classeOnglet($ongletAffiche === 'croise') }}">{{ __('accueil_pwa.onglets.croise') }}</button>
              </div>
            @endif
          </div>

          {{-- Période et exports : ce sont les commandes du tableau de bord
               M11. Sans droit sur M11, il n'y a rien à borner ni à exporter. --}}
          @if ($tableauDeBordAutorise)
          <p class="text-[12px] text-slate-400 w-full lg:w-auto lg:self-end lg:mr-3">{{ $periode->libelle() }}</p>

          <div class="lg:ml-auto flex flex-wrap gap-2">
            <select wire:model.live="filtrePeriode" class="champ text-[15px] border border-slate-200 rounded-lg px-3 py-2.5 bg-white">
              @foreach (__('accueil_pwa.periodes') as $code => $libelle)
                <option value="{{ $code }}">{{ $libelle }}</option>
              @endforeach
            </select>

            @if ($filtrePeriode === 'personnalisee')
              <div class="flex items-center gap-2">
                <input type="date" wire:model.live="du" class="text-[13px] border border-slate-300 rounded-lg px-2.5 py-2" title="{{ __('accueil_pwa.periode_du') }}">
                <span class="text-[13px] text-slate-400">{{ __('accueil_pwa.periode_au') }}</span>
                <input type="date" wire:model.live="au" class="text-[13px] border border-slate-300 rounded-lg px-2.5 py-2" title="{{ __('accueil_pwa.periode_au') }}">
              </div>
            @endif

            {{-- « Actualiser » est un rafraîchissement du CADRE : aucune méthode
                 publique n'est nécessaire, et une méthode qui se contenterait
                 d'afficher « Tableau de bord actualisé » affirmerait une
                 relecture qu'elle n'aurait pas faite (PA-59/60/61). --}}
            <button type="button" wire:click="$refresh" class="btn flex items-center gap-1.5 px-3 py-2.5 rounded-lg border border-slate-200 bg-white text-slate-500" title="{{ __('accueil_pwa.actualiser') }}">
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M23 4v6h-6M1 20v-6h6"/><path stroke-linecap="round" stroke-linejoin="round" d="M3.51 9a9 9 0 0114.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0020.49 15"/></svg>
            </button>

            {{-- ⚠ DÉROGATION PO du 01/09/2026 — les deux boutons du maître
                 (`tableau-de-bord.html` l.55-63, « PDF » / « Excel ») sont
                 remplacés par UN bouton « Exporter » qui ouvre la même
                 modale d'export ; le format s'y choisit, sans présélection
                 imposée. Registre : `App\Pwa\Support\DerogationsMaquette`
                 (export_bouton_unique). Jeton :
                 maitre-refuse:tableau-de-bord.html#page --}}
            <button type="button" wire:click="ouvrirExport" class="btn flex items-center gap-1.5 px-3 py-2.5 rounded-lg border border-slate-200 bg-white text-slate-600 text-[15px] font-semibold">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/><path stroke-linecap="round" stroke-linejoin="round" d="M14 2v6h6"/></svg>
              {{ __('pwa.export.bouton') }}
            </button>
          </div>
          @endif
        </div>

        {{-- A3 — LE REPLI DE PÉRIODE SE DIT. --}}
        @if ($periodeRefusee !== null)
          <div class="rounded-xl px-4 py-3 mb-5 text-[13px]" style="background:#FFFBEB;border:1px solid #FDE68A;color:#78350F">
            {{ __('accueil_pwa.periode_inconnue', ['code' => $periodeRefusee, 'defaut' => __('accueil_pwa.periodes.mois')]) }}
          </div>
        @endif

        {{-- ================= PANNEAU 1 : VUE D'EXPLOITATION =================
             Le conteneur ne porte AUCUNE classe, exactement comme le maître
             (`tableau-de-bord.html` l.68) : c'est le panneau ouvert par
             défaut, et une classe `hidden` posée puis retirée en JavaScript
             ferait clignoter la page au chargement. --}}
        <div data-panneau-tb="exploitation">

          {{-- ACCÈS RAPIDES — masqués par droit RÉEL (RG-16, 1ᵉʳ niveau).
               Anatomie du maître (`tableau-de-bord.js` l.126-132) : pastille
               ronde `w-9 h-9`, icône 16 px teintée, libellé `text-[13px]`. --}}
          <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-2.5 mb-5">
            @if ($peutEcrireHebergement)
              <button type="button" wire:click="ouvrirReservationRapide" class="carte-hover flex flex-col items-center gap-2 bg-white border border-slate-200 rounded-xl py-4 px-2 text-center">
                <span class="w-9 h-9 rounded-full flex items-center justify-center" style="background:{{ $iconesAccesRapide['reservation'][0] }}15">
                  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="{{ $iconesAccesRapide['reservation'][0] }}" stroke-width="2">{!! $iconesAccesRapide['reservation'][1] !!}</svg>
                </span>
                <span class="text-[13px] font-semibold text-slate-700">{{ __('accueil_pwa.acces_rapide.reservation') }}</span>
              </button>
            @endif

            @if ($peutEcrireClient)
              <button type="button" wire:click="ouvrirClientRapide" class="carte-hover flex flex-col items-center gap-2 bg-white border border-slate-200 rounded-xl py-4 px-2 text-center">
                <span class="w-9 h-9 rounded-full flex items-center justify-center" style="background:{{ $iconesAccesRapide['client'][0] }}15">
                  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="{{ $iconesAccesRapide['client'][0] }}" stroke-width="2">{!! $iconesAccesRapide['client'][1] !!}</svg>
                </span>
                <span class="text-[13px] font-semibold text-slate-700">{{ __('accueil_pwa.acces_rapide.client') }}</span>
              </button>
            @endif

            {{-- Ces trois raccourcis lisent d'AUTRES modules que M11 : la
                 modale « Stocks critiques » liste des articles sous seuil
                 (M6), le rapport passe par le moteur d'états (M14), et la
                 dépense courante ouvre M10. --}}
            @if ($peutLireStocks)
              <button type="button" wire:click="$set('etatFormulaire', 'stocks-critiques')" class="carte-hover flex flex-col items-center gap-2 bg-white border border-slate-200 rounded-xl py-4 px-2 text-center">
                <span class="w-9 h-9 rounded-full flex items-center justify-center" style="background:{{ $iconesAccesRapide['stocks'][0] }}15">
                  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="{{ $iconesAccesRapide['stocks'][0] }}" stroke-width="2">{!! $iconesAccesRapide['stocks'][1] !!}</svg>
                </span>
                <span class="text-[13px] font-semibold text-slate-700">{{ __('accueil_pwa.acces_rapide.stocks') }}</span>
              </button>
            @endif

            @if ($peutLireEtats)
              <button type="button" wire:click="$set('etatFormulaire', 'rapport')" class="carte-hover flex flex-col items-center gap-2 bg-white border border-slate-200 rounded-xl py-4 px-2 text-center">
                <span class="w-9 h-9 rounded-full flex items-center justify-center" style="background:{{ $iconesAccesRapide['rapport'][0] }}15">
                  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="{{ $iconesAccesRapide['rapport'][0] }}" stroke-width="2">{!! $iconesAccesRapide['rapport'][1] !!}</svg>
                </span>
                <span class="text-[13px] font-semibold text-slate-700">{{ __('accueil_pwa.acces_rapide.rapport') }}</span>
              </button>
            @endif

            @if (\App\Pwa\Support\MenuLateral::peutVoirRoute(Auth::user(), 'pwa.depenses'))
              <a href="{{ route('pwa.depenses') }}" wire:navigate class="carte-hover flex flex-col items-center gap-2 bg-white border border-slate-200 rounded-xl py-4 px-2 text-center">
                <span class="w-9 h-9 rounded-full flex items-center justify-center" style="background:{{ $iconesAccesRapide['depense'][0] }}15">
                  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="{{ $iconesAccesRapide['depense'][0] }}" stroke-width="2">{!! $iconesAccesRapide['depense'][1] !!}</svg>
                </span>
                <span class="text-[13px] font-semibold text-slate-700">{{ __('accueil_pwa.acces_rapide.depense') }}</span>
              </a>
            @endif
          </div>

          {{-- ⚠ M11 — LA BANDE D'INDICATEURS EST LE PILOTAGE FINANCIER.
               Chiffre d'affaires encaissé, dépenses, trésorerie, créances,
               marge : la matrice RBAC les réserve à M11. --}}
          @if ($tableauDeBordAutorise)

          {{-- ============ LES HUIT INDICATEURS, DEUX CONTENEURS ============

               Le maître pose DEUX grilles pour les mêmes huit indicateurs :
               `#conteneur-kpi`, replié sous `lg` derrière « Indicateurs clés
               (8) », et `#grille-kpi`, toujours visible. Son propre JavaScript
               remplit les deux (`tableau-de-bord.js` l.88 pour la première,
               le script en ligne de la page l.413 pour la seconde), si bien
               qu'un écran large affiche SEIZE cartes — les huit vraies, puis
               les huit de démonstration.

               ECART DELIBERE — `tableau-de-bord.html` l.72-81
               Les deux conteneurs sont rendus, avec leurs classes exactes,
               mais ils s'excluent : l'accordéon sous `lg`, la grille au-delà.
               Raison : afficher deux fois les mêmes huit chiffres ferait
               chercher au lecteur ce qui distingue les deux bandes — il n'y a
               rien à trouver. C'est une duplication du prototype, pas une
               intention de lecture ; le prototype est une spécification
               exécutable, pas une référence infaillible (PA-99).
               La visibilité passe par `style`, jamais par une classe : une
               classe de disposition changerait la signature que
               `t-structure.js` compare, et le squelette du maître serait perdu
               pour de bon. --}}
          <div class="bg-white rounded-xl border border-slate-200 mb-5 lg:bg-transparent lg:border-0 lg:p-0"
               x-data="{ ouvert: false }">
            <button type="button" x-on:click="ouvert = !ouvert" class="w-full flex items-center justify-between px-4 py-3 lg:hidden">
              <span class="text-sm font-bold text-slate-700">{{ __('accueil_pwa.kpis_accordeon') }}</span>
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="transition-transform" x-bind:style="ouvert ? 'transform:rotate(180deg)' : ''"><path stroke-linecap="round" stroke-linejoin="round" d="M6 9l6 6 6-6"/></svg>
            </button>

            <div class="grid grid-cols-2 lg:grid-cols-4 gap-3 lg:gap-4 px-3 pb-3 lg:p-0"
                 data-bande-kpi="accordeon" x-bind:data-ouvert="ouvert ? '1' : '0'">
              @include('pwa.livewire.accueil-cartes-kpi', [
                  'indicateurs' => $indicateurs,
                  'iconesKpi' => $iconesKpi,
                  'valeurKpi' => $valeurKpi,
              ])
            </div>
          </div>

          <div class="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6" data-bande-kpi="large">
            @include('pwa.livewire.accueil-cartes-kpi', [
                'indicateurs' => $indicateurs,
                'iconesKpi' => $iconesKpi,
                'valeurKpi' => $valeurKpi,
            ])
          </div>
          @endif

          {{-- ⚠ M1 — LES DEUX TABLEAUX QUI SUIVENT SONT DES DONNEES
               D'HEBERGEMENT : arrivées du jour avec le nom des clients, et
               disponibilité du parc. Un `guide` (M1 = '-') les recevait. --}}
          @if ($peutLireHebergement)
          {{-- RÉSERVATIONS DU JOUR — les SEPT colonnes du maître (l.93). --}}
          {{-- EXCLU de la barre de recherche par table (PO, 01/09/2026) : ce
               tableau est un WIDGET du tableau de bord, borné à la journée
               (« Réservations du jour ») — la liste complète, filtrable, vit
               sur l'écran dédié « Réservations » (lien « Voir tout »). --}}
          <div class="bg-white rounded-xl border border-slate-200 overflow-hidden mb-5">
            <div class="px-5 py-4 border-b border-slate-100 flex items-center justify-between">
              <h2 class="text-sm font-bold text-slate-700">{{ __('accueil_pwa.reservations_jour.titre') }}</h2>
              <a href="{{ route('pwa.reservations') }}" wire:navigate class="text-[15px] font-semibold" style="color:var(--gold)">{{ __('accueil_pwa.reservations_jour.voir_tout') }}</a>
            </div>
            <div class="overflow-x-auto">
              <table class="w-full text-sm">
                <thead class="bg-[var(--navy)]">
                  <tr class="text-left text-[11px] font-semibold text-white/90 uppercase tracking-wide">
                    <th class="px-5 py-2.5">{{ __('accueil_pwa.reservations_jour.col_client') }}</th>
                    <th class="px-5 py-2.5">{{ __('accueil_pwa.reservations_jour.col_services') }}</th>
                    <th class="px-5 py-2.5">{{ __('accueil_pwa.reservations_jour.col_arrivee') }}</th>
                    <th class="px-5 py-2.5">{{ __('accueil_pwa.reservations_jour.col_depart') }}</th>
                    <th class="px-5 py-2.5">{{ __('accueil_pwa.reservations_jour.col_canal') }}</th>
                    <th class="px-5 py-2.5">{{ __('accueil_pwa.reservations_jour.col_acompte') }}</th>
                    <th class="px-5 py-2.5 text-right">{{ __('accueil_pwa.reservations_jour.col_actions') }}</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-slate-100">
                  @forelse ($reservationsDuJour as $reservation)
                    <tr wire:key="resa-{{ $reservation->id }}">
                      <td class="px-5 py-3 font-medium text-slate-700">{{ $reservation->client?->nom }} {{ $reservation->client?->prenom }}</td>
                      {{-- Pastilles DÉRIVÉES, jamais stockées : « Hébergement »
                           vient d'`unite_id` (NOT NULL — toute fiche en a un),
                           les autres des lignes de services (PA-163). Couleurs
                           et classes du maître (`tableau-de-bord.js` l.30-31
                           et l.336). --}}
                      <td class="px-5 py-3">
                        <div class="flex flex-wrap gap-1">
                          @foreach (array_unique(array_merge(['hebergement'], $reservation->lignes->pluck('service')->all())) as $service)
                            {{-- Clés LITTÉRALES via `match`, jamais concaténées :
                                 une clé dynamique est invisible aux gardes i18n. --}}
                            <span class="text-[12px] font-semibold px-2 py-0.5 rounded" style="background:{{ \App\Pwa\Support\CouleursServices::fond($service) }};color:{{ \App\Pwa\Support\CouleursServices::texte($service) }}">{{ __(match ($service) {
                                'restauration' => 'accueil_pwa.services.restauration',
                                'bar' => 'accueil_pwa.services.bar',
                                'tourisme' => 'accueil_pwa.services.tourisme',
                                'vehicule' => 'accueil_pwa.services.vehicule',
                                default => 'accueil_pwa.services.hebergement',
                            }) }}</span>
                          @endforeach
                        </div>
                      </td>
                      <td class="px-5 py-3 text-slate-500">{{ $reservation->date_arrivee->format('d/m/Y') }}</td>
                      <td class="px-5 py-3 text-slate-500">{{ $reservation->date_depart->format('d/m/Y') }}</td>
                      {{-- Le canal SAISI ou un tiret — jamais « Physique »
                           d'office, le défaut que le maître dit avoir corrigé
                           le 24/08/2026. Les fiches d'avant PA-163 n'en ont
                           pas : le tiret dit ce fait, il n'invente rien. --}}
                      <td class="px-5 py-3 text-slate-500">{{ $reservation->canal?->nom ?? __('accueil_pwa.tiret') }}</td>
                      <td class="px-5 py-3 font-semibold" style="color:var(--gold)">{{ MontantFcfa::format((string) $reservation->acompte) }}</td>
                      {{--
                          ⚠ « PAYER » EST DÉSORMAIS RENDU (02/09/2026, PA-165) —
                          le jeton `maitre-refuse:tableau-de-bord.html#bouton-payer`
                          est RETIRÉ : `EncaissementFactureService`, premier
                          writer de `paiements`, lève la prémisse PA-21 qui
                          motivait ce refus. Rendu conditionnel, jamais le
                          geste du maître (qui solde `reste_a_payer` en local
                          sans aucune écriture) : le bouton n'apparaît QUE si
                          une facture FIGÉE et NON SOLDÉE couvre RÉELLEMENT
                          cette réservation (`facturesAPayer`, lignes source
                          M1), et ouvre la modale de recouvrement de CETTE
                          facture — mêmes règles que `ClientsCreances`
                          (M11 + M2, PA-65).

                          ⚠ UN SECOND BOUTON EST RENDU ICI, ET LE MAÎTRE NE LE
                          PORTE PAS — déclaré, pas caché :
                            structure-ajout:tableau-de-bord.html#bouton-checkin-jour
                          Le maître ne montre jamais de Check-in dans CE
                          tableau : `services.includes('hebergement')` y est
                          TOUJOURS vrai (une fiche a toujours un hébergement),
                          donc son bouton unique est Check-out, cliqué même sur
                          une arrivée qui n'a pas encore pointé. Le geste réel
                          (`SejourService::checkin()`) refuserait ce clic sans
                          rien accomplir. Plutôt qu'un bouton qui échoue en
                          silence côté serveur, une réservation du jour PAS
                          ENCORE arrivée reçoit son propre Check-in — même
                          service, même garde, que celui de « Chambres
                          disponibles ». Retiré, une arrivée du jour resterait
                          sans aucune action tant qu'elle n'a pas été pointée
                          depuis un autre écran.
                      --}}
                      <td class="px-5 py-3 text-right whitespace-nowrap">
                        @if ($peutEncaisser && isset($facturesAPayer[$reservation->id]))
                          <button type="button" wire:click="ouvrirRecouvrementDuJour('{{ $reservation->id }}')" class="text-[12px] font-semibold px-2.5 py-1 rounded border border-green-200 text-green-700 hover:bg-green-50 mr-1.5">{{ __('accueil_pwa.reservations_jour.payer') }}</button>
                        @endif
                        @if ($peutEcrireHebergement)
                          @if ($sejoursEnCours->contains($reservation->id))
                            <button type="button" wire:click="ouvrirCheckoutRapide('{{ $reservation->id }}')" class="text-[12px] font-semibold px-2.5 py-1 rounded border border-slate-200 text-slate-600">{{ __('accueil_pwa.reservations_jour.checkout') }}</button>
                          @else
                            <button type="button" wire:click="ouvrirCheckinRapide('{{ $reservation->id }}')" class="text-[12px] font-semibold px-2.5 py-1 rounded border border-emerald-200 text-emerald-700">{{ __('accueil_pwa.reservations_jour.checkin') }}</button>
                          @endif
                        @elseif (! ($peutEncaisser && isset($facturesAPayer[$reservation->id])))
                          <span class="text-[12px] text-slate-400">{{ __('accueil_pwa.tiret') }}</span>
                        @endif
                      </td>
                    </tr>
                  @empty
                    <tr><td colspan="7" class="py-10 text-center text-slate-400 text-sm">{{ __('accueil_pwa.reservations_jour.vide') }}</td></tr>
                  @endforelse
                </tbody>
              </table>
            </div>
          </div>
          @endif

          {{-- ================= ALERTES STOCKS CRITIQUES =================
               Maître : `zone-alertes-stock` (l.103), rempli par
               `rendreAlertesStock()` (`tableau-de-bord.js` l.222-235).

               ⚠ LA ZONE RESTE VIDE QUAND IL N'Y A RIEN — c'est le maître qui
               le décide (`if (critiques.length === 0) { zone.innerHTML = ''; }`),
               et c'est juste : une bande verte « stock sain » affirmerait un
               état sur des articles que le calcul n'a peut-être pas couverts.
               Le compte vient de la MÊME collection que la modale et que le
               panneau « À traiter » — une seule requête, jamais trois.

               ⚠ BLOC AJOUTÉ AU SQUELETTE, ET DÉCLARÉ :
                 structure-ajout:tableau-de-bord.html#div-c8b50866
               Ce n'est pas un ajout d'écran mais un ajout de MESURE : le
               maître pose ici un conteneur VIDE (`<div id="zone-alertes-stock"
               class="mb-5">`, l.103) que son JavaScript remplit au
               chargement. `t-structure.js` lit la source statique — un
               conteneur vide sans classe de disposition disparaît de son
               squelette —, si bien que la bande rouge du maître n'a aucun
               équivalent à comparer. La structure rendue est celle de
               `rendreAlertesStock()` (`tableau-de-bord.js` l.226-234), au
               caractère près. --}}
          @if ($peutLireStocks && $articlesCritiques->isNotEmpty())
            <div class="mb-5">
              <div class="bg-red-50 border border-red-200 rounded-xl px-5 py-3.5 flex items-start gap-3">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="var(--erreur)" stroke-width="2" class="shrink-0 mt-0.5"><path stroke-linecap="round" stroke-linejoin="round" d="M12 9v4m0 4h.01M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z"/></svg>
                <div class="flex-1 min-w-0">
                  <p class="text-[15px] font-bold text-red-800">{{ __('accueil_pwa.alerte_stock.titre', ['nombre' => $articlesCritiques->count()]) }}</p>
                  <p class="text-[13px] text-red-700 mt-0.5">{{ $articlesCritiques->pluck('libelle')->implode(', ') }}</p>
                </div>
                <button type="button" wire:click="$set('etatFormulaire', 'stocks-critiques')" class="text-[13px] font-bold text-red-800 underline shrink-0">{{ __('accueil_pwa.alerte_stock.voir') }}</button>
              </div>
            </div>
          @endif

          {{-- ================= RÉCAPITULATIF DE LA JOURNÉE =================
               Maître : `zone-recap-jour` (l.106), rempli par `rendreRecapJour()`
               (`tableau-de-bord.js` l.392-410). Bandeau navy, quatre compteurs,
               le montant en doré.

               ⚠ BLOC AJOUTÉ AU SQUELETTE, ET DÉCLARÉ :
                 structure-ajout:tableau-de-bord.html#div-2ab3d027
               Même raison que la bande d'alertes ci-dessus : le maître pose un
               conteneur VIDE (`<div id="zone-recap-jour" class="mb-5">`,
               l.106) rempli par son JavaScript, que le comparateur statique ne
               voit pas. La grille rendue est la sienne — `grid grid-cols-2
               sm:grid-cols-4 gap-4`. --}}
          @if ($recapJour !== null)
            <div class="mb-5">
              <div class="bg-[var(--navy)] rounded-xl p-5 text-white">
                <h2 class="text-sm font-bold mb-3">{{ __('accueil_pwa.recap.titre', ['jour' => \Carbon\CarbonImmutable::today()->translatedFormat('l j F')]) }}</h2>
                <div class="grid grid-cols-2 sm:grid-cols-4 gap-4">
                  <div>
                    <p class="text-2xl font-bold">{{ $recapJour['arrivees'] }}</p>
                    <p class="text-[13px] text-white/60">{{ __('accueil_pwa.recap.arrivees') }}</p>
                  </div>
                  <div>
                    <p class="text-2xl font-bold">{{ $recapJour['departs'] }}</p>
                    <p class="text-[13px] text-white/60">{{ __('accueil_pwa.recap.departs') }}</p>
                  </div>
                  <div>
                    <p class="text-2xl font-bold">{{ $recapJour['nouvelles'] }}</p>
                    <p class="text-[13px] text-white/60">{{ __('accueil_pwa.recap.nouvelles') }}</p>
                  </div>
                  <div>
                    <p class="text-2xl font-bold" style="color:var(--gold)">{{ MontantFcfa::format($recapJour['encaisse']) }}</p>
                    <p class="text-[13px] text-white/60">{{ __('accueil_pwa.recap.encaisse') }}</p>
                  </div>
                </div>
              </div>
            </div>
          @endif

          {{-- ================= LA LIGNE DE GRAPHIQUES (maître l.109-127) =====

              La grille est celle du maître, au caractère près :
              `grid grid-cols-1 xl:grid-cols-3 gap-5 mb-5`, la carte du chiffre
              d'affaires occupant deux colonnes sur trois (`xl:col-span-2`).
          --}}
          @if ($tableauDeBordAutorise)
          <div class="grid grid-cols-1 xl:grid-cols-3 gap-5 mb-5">
            <div class="xl:col-span-2 bg-white rounded-xl border border-slate-200 p-5">
              <div class="flex items-center justify-between mb-1 flex-wrap gap-2">
                <h2 class="text-sm font-bold text-slate-700">{{ __('accueil_pwa.serie.titre') }}</h2>
                <div class="flex gap-1">
                  <button type="button" wire:click="$set('moisSerie', 3)" class="{{ $classeMois($moisSerie === 3) }}">{{ __('accueil_pwa.serie.mois_3') }}</button>
                  <button type="button" wire:click="$set('moisSerie', 6)" class="{{ $classeMois($moisSerie === 6) }}">{{ __('accueil_pwa.serie.mois_6') }}</button>
                  <button type="button" wire:click="$set('moisSerie', 12)" class="{{ $classeMois($moisSerie === 12) }}">{{ __('accueil_pwa.serie.mois_12') }}</button>
                </div>
              </div>
              <p class="text-[13px] text-slate-400 mb-4">{{ __('accueil_pwa.serie.sous_titre') }}</p>

              {{--
                  ⚠ TROIS ÉTATS, PAS DEUX (Article 7 / PA-59-60-61).

                  `null`  : la lecture a échoué — la phrase le dit, et AUCUN
                            canevas n'est posé. Un graphique vide se lit comme
                            une activité nulle, pas comme une absence de mesure.
                  `[]`    : la période n'a rien produit — la phrase du maître.
                  sinon   : le graphique du maître.

                  L'ordre des branches n'est pas indifférent : `t-structure.js`
                  lit la PREMIÈRE, et c'est l'état NOMINAL qu'il doit voir.
              --}}
              @if (is_array($series) && $series !== [])
                {{-- Les données voyagent par un `<script type="application/json">`
                     qui, LUI, est re-rendu par Livewire à chaque changement de
                     période. Le canevas, à côté, est en `wire:ignore` : Chart.js
                     y attache un contexte 2D et un observateur de taille, que
                     Livewire détruirait en remplaçant le nœud. --}}
                <script type="application/json" id="donnees-graphique-ca">@json($series)</script>
                <div wire:ignore style="position:relative;height:280px">
                  <canvas id="graphique-ca"></canvas>
                </div>
              @elseif ($series === [])
                <p class="text-[13px] text-slate-500">{{ __('accueil_pwa.serie.vide') }}</p>
              @else
                <p class="text-[13px] text-slate-500">{{ __('accueil_pwa.lecture_impossible') }}</p>
              @endif
            </div>

            {{-- ⚠ LE TITRE EST CELUI DU MAÎTRE, LE SOUS-TITRE DIT LA MESURE
                 RÉELLE — PA-49 appliqué à la lettre.

                 Le maître compte « le nombre de réservations incluant chaque
                 service ». Cette mesure n'existe pas côté serveur : les cinq
                 services d'une fiche sont une table du client hors ligne
                 (PA-110), et `reservations` n'en porte aucun. Ce qui est
                 ventilé ici, ce sont les montants FACTURÉS par module d'origine
                 (`lignes_facture.source_module`, RG-04) — la même source que le
                 tableau « Par module » du pilotage, jamais un second agrégat
                 (PA-121). L'ancien refus, qui disait « aucun des quatre n'est
                 rendu », est LEVÉ et daté plutôt que recopié (PA-144). --}}
            <div class="bg-white rounded-xl border border-slate-200 p-5">
              <h2 class="text-sm font-bold text-slate-700">{{ __('accueil_pwa.repartition.titre') }}</h2>
              <p class="text-[13px] text-slate-400 mb-2">{{ __('accueil_pwa.repartition.sous_titre') }}</p>
              <p class="text-[12px] text-slate-400 mb-2">{{ __('accueil_pwa.repartition.mesure_reelle') }}</p>

              @if (is_array($ventilation) && $ventilation !== [])
                <script type="application/json" id="donnees-graphique-repartition">@json($ventilation)</script>
                {{-- Codes RG-04 vers noms d'activite : cles LITTERALES, un
                     seul auteur pour les deux graphiques et leur legende. --}}
                <script type="application/json" id="noms-activites">{
                  "M1": "{{ __('accueil_pwa.services.hebergement') }}",
                  "M4": "{{ __('accueil_pwa.services.restauration') }}",
                  "M5": "{{ __('accueil_pwa.services.bar') }}",
                  "M8": "{{ __('accueil_pwa.services.vehicule') }}",
                  "M9": "{{ __('accueil_pwa.services.tourisme') }}"
                }</script>
                <div wire:ignore style="position:relative;height:220px">
                  <canvas id="graphique-repartition"></canvas>
                </div>
              @elseif ($ventilation === [])
                <p class="text-[13px] text-slate-500">{{ __('accueil_pwa.repartition.vide') }}</p>
              @else
                <p class="text-[13px] text-slate-500">{{ __('accueil_pwa.lecture_impossible') }}</p>
              @endif
            </div>
          </div>

          {{-- « 📊 Statistiques de ventes par activité » — barres horizontales,
               `canvas height=90` au maître (l.129-133). Même mesure et même
               source que l'anneau ci-dessus : deux TRACÉS d'une seule mesure,
               jamais deux agrégats parallèles (PA-121). --}}
          <div class="bg-white rounded-xl border border-slate-200 p-5 mb-5">
            <h2 class="text-sm font-bold text-slate-700 mb-1">{{ __('accueil_pwa.ventes_activite.titre') }}</h2>
            <p class="text-[13px] text-slate-400 mb-1">{{ __('accueil_pwa.ventes_activite.sous_titre') }}</p>
            <p class="text-[12px] text-slate-400 mb-4">{{ __('accueil_pwa.ventes_activite.mesure_reelle') }}</p>

            @if (is_array($ventilation) && $ventilation !== [])
              <div wire:ignore style="position:relative;height:220px">
                <canvas id="graphique-ventes"></canvas>
              </div>
            @elseif ($ventilation === [])
              <p class="text-[13px] text-slate-500">{{ __('accueil_pwa.ventes_activite.vide') }}</p>
            @else
              <p class="text-[13px] text-slate-500">{{ __('accueil_pwa.lecture_impossible') }}</p>
            @endif
          </div>
          @endif

          @if ($peutLireHebergement)
          {{-- CHAMBRES DISPONIBLES — calculées (RG-02), jamais `statut`.
               Les CINQ colonnes du maître (l.145).
               EXCLU de la barre de recherche par table (PO, 01/09/2026) :
               widget du tableau de bord, la liste complète et filtrable vit
               sur l'écran « Plan d'Hébergement » (lien « Voir tout »). --}}
          <div class="bg-white rounded-xl border border-slate-200 overflow-hidden mb-5">
            <div class="px-5 py-4 border-b border-slate-100 flex items-center justify-between">
              <h2 class="text-sm font-bold text-slate-700">{{ __('accueil_pwa.chambres.titre') }}</h2>
              <a href="{{ route('pwa.hebergement') }}" wire:navigate class="text-[15px] font-semibold" style="color:var(--gold)">{{ __('accueil_pwa.chambres.voir_tout') }}</a>
            </div>
            <div class="overflow-x-auto">
              <table class="w-full text-sm">
                <thead class="bg-[var(--navy)]">
                  <tr class="text-left text-[11px] font-semibold text-white/90 uppercase tracking-wide">
                    <th class="px-5 py-2.5">{{ __('accueil_pwa.chambres.col_code') }}</th>
                    <th class="px-5 py-2.5">{{ __('accueil_pwa.chambres.col_unite') }}</th>
                    <th class="px-5 py-2.5">{{ __('accueil_pwa.chambres.col_categorie') }}</th>
                    <th class="px-5 py-2.5">{{ __('accueil_pwa.chambres.col_tarif') }}</th>
                    <th class="px-5 py-2.5 text-right">{{ __('accueil_pwa.chambres.col_actions') }}</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-slate-100">
                  @forelse ($chambresDisponibles as $unite)
                    <tr wire:key="unite-{{ $unite->id }}">
                      <td class="px-5 py-3"><span class="text-[13px] bg-slate-100 px-2 py-0.5 rounded">{{ $unite->numero }}</span></td>
                      {{-- « Unité » : un tiret. `unites_hebergement` porte UN
                           seul identifiant, déjà rendu en « Code » — le
                           répéter laisserait croire à deux données. --}}
                      <td class="px-5 py-3 text-slate-400">{{ __('accueil_pwa.tiret') }}</td>
                      <td class="px-5 py-3 font-medium text-slate-700">{{ $unite->categorie?->libelle }}</td>
                      <td class="px-5 py-3 font-semibold" style="color:var(--gold)">{{ MontantFcfa::format((string) ($unite->categorie?->tarif_base ?? '0')) }}</td>
                      {{-- Bouton VERT « Effectuer Check-in », comme le maître
                           (`tableau-de-bord.js` l.385 : `style="background:
                           var(--succes);color:white"`). REFUS LEVÉ le
                           02/09/2026 — la version précédente rendait un bouton
                           « Réserver » (navy) qui n'existe pas ici au maître :
                           le geste réel est `SejourService::checkin()`, porté
                           par `ouvrirCheckinDepuisChambre()`. --}}
                      <td class="px-5 py-3 text-right">
                        @if ($peutEcrireHebergement)
                          <button type="button" wire:click="ouvrirCheckinDepuisChambre('{{ $unite->id }}')" class="text-[12px] font-semibold px-3 py-1.5 rounded" style="background:var(--succes);color:white">{{ __('accueil_pwa.chambres.checkin') }}</button>
                        @else
                          <span class="text-[12px] text-slate-400">{{ __('accueil_pwa.tiret') }}</span>
                        @endif
                      </td>
                    </tr>
                  @empty
                    <tr><td colspan="5" class="py-10 text-center text-slate-400 text-sm">{{ __('accueil_pwa.chambres.vide') }}</td></tr>
                  @endforelse
                </tbody>
              </table>
            </div>
          </div>
          @endif

          {{--
              ⚠ UN BLOC AJOUTÉ PAR LA PWA, DÉCLARÉ :
                structure-ajout:tableau-de-bord.html#h2-a853a7b5

              La « Consultation de secours » n'existe pas au maître, et elle
              n'est pas un ornement : `/pwa` est la page d'atterrissage de TOUS
              les rôles — sa route ne porte pas de `module:M11`, sans quoi un
              `guide` n'aurait plus aucune page où arriver après sa connexion.
              Pour ces rôles, la liste des écrans accessibles EST la page. Elle
              reste rendue pour tous plutôt que dupliquée derrière une
              condition : `ComptabilitePwaTest` vérifie qu'un administrateur
              trouve bien la carte M10 sur `/pwa`, et deux versions de la même
              liste finiraient par diverger.
          --}}
          <div class="bg-white rounded-xl border border-slate-200 p-5 mb-5">
            <h2 class="text-sm font-bold text-slate-700">{{ __('accueil_pwa.ecrans_titre') }}</h2>
            <p class="text-[13px] text-slate-400 mb-4">{{ __('accueil_pwa.ecrans_sous_titre') }}</p>
            @if ($ecrans === [])
              <p class="text-[13px] text-slate-500">{{ __('pwa.accueil.aucun_ecran') }}</p>
            @else
              <div class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3">
                @foreach ($ecrans as $ecran)
                  <div class="rounded-xl border border-slate-200 p-3.5">
                    <p class="text-[13px] font-bold text-slate-700">{{ $ecran['libelle'] }}</p>
                    <p class="text-[12px] text-slate-400 mt-0.5">{{ $ecran['description'] }}</p>
                    <p class="text-[11px] text-slate-400 mt-1">{{ $ecran['niveau'] === 'C' ? __('pwa.accueil.acces_complet') : __('pwa.accueil.lecture_seule') }}</p>
                    @if ($ecran['url'] === null)
                      <p class="text-[12px] text-slate-400 mt-1.5">{{ __('pwa.accueil.ecran_a_venir') }}</p>
                    @else
                      <a href="{{ $ecran['url'] }}" wire:navigate class="text-[12px] font-semibold mt-1.5 inline-block" style="color:var(--gold)">{{ __('pwa.accueil.ouvrir_ecran') }}</a>
                    @endif
                  </div>
                @endforeach
              </div>
            @endif
          </div>

        </div>{{-- /panneau exploitation --}}

        @if ($tableauDeBordAutorise)
        {{-- ================= PANNEAU 2 : PILOTAGE CONSOLIDÉ =================

             Respiration latérale du maître (`tableau-de-bord.html` l.157-162) :
             le panneau consolidé porte plus de blocs que la vue d'exploitation,
             et les cartes touchaient le bord du conteneur. La marge s'ANNULE
             sous 1024 px — 66 px prélevés sur une largeur de téléphone
             écraseraient les cartes plus sûrement que le débordement corrigé.

             ⚠ L'onglet « Pilotage consolidé » est le portage de la page
             maître `m11-pilotage.html`. Ce n'est pas une
             interprétation : le maître l'écrit dans son propre bandeau
             (l.51-59) — « Le pilotage consolidé est désormais un onglet du
             Tableau de bord. Cette page reste accessible par son URL — un
             favori ne doit pas tomber dans le vide — mais elle n'est plus au
             menu. »

             ⚠ ET LA CITATION EST ÉCRITE SANS SON CHEMIN, DÉLIBÉRÉMENT.
             `t-structure.js` (l.996) rattache une page maître à une vue en
             cherchant `prototype_v2/pages/<page>.html` dans la SOURCE de la
             vue, puis confronte le `<main>` de la page au `<main>` de la vue.
             Écrire le chemin ici lui ferait comparer une page ENTIÈRE du
             maître à une vue qui en porte TROIS, panneau par panneau — 27
             écarts qui ne décrivent aucun défaut, seulement la limite du
             rattachement un-pour-un. La citation complète vit dans
             `app/Pwa/Livewire/Accueil.php`, que `t-trois-sources.js` lit :
             la page y est donc bien reconnue comme SERVIE, et ses libellés
             sont confrontés. Le jour où le comparateur saura rattacher une
             page à UN panneau, remettre le chemin ici sera la bonne action. --}}
        {{-- Sans marge latérale : la `lg:mx-[33px]` posée à la reprise du
             design a été retirée à la demande du Product Owner (01/09/2026) —
             le panneau occupe la même largeur que l'onglet Exploitation. --}}
        <div data-panneau-tb="pilotage" class="hidden">

          {{-- La barre de filtres du maître : du / au / Exercice entier / PDF.
               Les deux dates écrivent `du` et `au` ET basculent la période sur
               « personnalisée » — sans quoi elles seraient deux champs inertes
               (Article 3.3), puisque `Periode::resoudre()` ignore les bornes
               tant que le code n'est pas `personnalisee`. Le `$wire.set` évite
               une méthode publique de plus : chacune est une action à relire
               (`PwaActionsReluesTest`). --}}
          <div class="flex flex-wrap gap-3 items-center mb-4">
            <label class="text-[12px] text-slate-500">{{ __('accueil_pwa.periode_du') }}</label>
            <input type="date" wire:model.live="du" x-on:change="$wire.set('filtrePeriode', 'personnalisee')" class="text-[13px] border border-slate-300 rounded-lg px-2.5 py-2">
            <label class="text-[12px] text-slate-500">{{ __('accueil_pwa.periode_au') }}</label>
            <input type="date" wire:model.live="au" x-on:change="$wire.set('filtrePeriode', 'personnalisee')" class="text-[13px] border border-slate-300 rounded-lg px-2.5 py-2">
            <button type="button" wire:click="$set('filtrePeriode', 'annee')" class="text-[12px] px-3 py-2 rounded-lg border border-slate-300 bg-white hover:bg-slate-50">{{ __('accueil_pwa.exercice_entier') }}</button>
            {{-- ⚠ DÉROGATION PO du 01/09/2026, rappelée le 02/09/2026
                 (export unifié) : le bouton « PDF » du maître M11 devient
                 « Exporter » — il ouvrait déjà la modale partagée, qui offre
                 les deux formats, et son libellé promettait un seul. Écart
                 couvert par le jeton m11-pilotage déclaré en tête de vue ;
                 registre : `DerogationsMaquette` (export_bouton_unique). --}}
            <button type="button" wire:click="ouvrirExport('pdf')" class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('pwa.export.bouton') }}</button>
          </div>

          {{--
              LES KPI CONSOLIDÉS — `m11-pilotage.js` l.110-135, rendus dans
              `<div id="kpis" class="grid grid-cols-2 sm:grid-cols-3
              xl:grid-cols-6 gap-3 mb-5">` (`tableau-de-bord.html` l.176).

              Six colonnes seulement à partir de `xl` : à `lg` (1024 px), six
              colonnes laissaient 122 px de contenu utile par carte —
              insuffisant pour « 12 345 678 F » à 17 px gras.

              Le maître en pose SIX ; les SIX sont servies depuis le
              02/09/2026 — « Masse salariale » (`LivreDePaieService::totaux()`)
              complète les cinq déjà rendues.
          --}}
          @php
              // `texteVide` : le texte affiché quand `valeur` est `null`. Par
              // défaut « Non consulté » (droit absent, rien n'a été lu) — la
              // carte « Masse salariale » le remplace par une absence RÉELLE
              // (aucun bulletin établi ce mois-ci), qui n'est pas un défaut de
              // droit : le confondre ferait chercher une permission manquante
              // là où il n'y a qu'une paie non encore établie.
              $carteKpi = static fn (string $libelle, ?string $valeur, string $accent, string $detail, ?string $texteVide = null): array
                  => ['libelle' => $libelle, 'valeur' => $valeur, 'accent' => $accent, 'detail' => $detail, 'texteVide' => $texteVide];

              $kpisPilotage = [
                  $carteKpi(
                      __('accueil_pwa.kpi.chiffre_affaires_encaisse.libelle'),
                      $indicateurs === null ? null : MontantFcfa::format($indicateurs['chiffre_affaires_encaisse']['valeur']),
                      '',
                      $periode->libelle(),
                  ),
                  $carteKpi(
                      __('accueil_pwa.pilotage.resultat_net'),
                      $comptables === null ? null : MontantFcfa::format($comptables->resultatNet),
                      $comptables !== null && MontantFcfa::estNegatif($comptables->resultatNet) ? 'text-red-600' : 'text-emerald-600',
                      $comptables === null
                          ? __('accueil_pwa.pilotage.resultat_net_source')
                          : ($comptables->impotNonComptabilise
                              ? __('accueil_pwa.pilotage.avant_impot', ['annee' => $comptables->annee])
                              : __('accueil_pwa.pilotage.exercice', ['annee' => $comptables->annee])),
                  ),
                  $carteKpi(
                      __('accueil_pwa.kpi.tresorerie_caisse.libelle'),
                      $indicateurs === null ? null : MontantFcfa::format($indicateurs['tresorerie_caisse']['valeur']),
                      $indicateurs !== null && MontantFcfa::estNegatif($indicateurs['tresorerie_caisse']['valeur']) ? 'text-red-600' : '',
                      __('accueil_pwa.kpi.tresorerie_caisse.note'),
                  ),
                  $carteKpi(
                      __('accueil_pwa.pilotage.creances_clients'),
                      MontantFcfa::format($creances['total_du']),
                      '',
                      __('accueil_pwa.creances.pieces', ['nombre' => $creances['nb_pieces'], 'clients' => $creances['nb_clients']]),
                  ),
                  $carteKpi(
                      __('accueil_pwa.kpi.valeur_stock.libelle'),
                      $indicateurs === null ? null : MontantFcfa::format($indicateurs['valeur_stock']['valeur']),
                      '',
                      __('accueil_pwa.kpi.valeur_stock.note'),
                  ),
                  // « Masse salariale » — 6e carte du maître (`m11-pilotage.js`
                  // l.129-131), REFUS LEVÉ le 02/09/2026 (voir tête de fichier).
                  // `$paie` est `null` pour deux raisons distinctes : droit M13
                  // absent (« Non consulté », comme les cinq autres cartes), ou
                  // droit présent mais AUCUN bulletin établi ce mois-ci — ce
                  // n'est jamais la même phrase (Article 7).
                  $carteKpi(
                      __('accueil_pwa.pilotage.masse_salariale'),
                      $paie === null || $paie['effectif'] === 0 ? null : MontantFcfa::format($paie['brut']),
                      '',
                      __('accueil_pwa.pilotage.masse_salariale_note', ['effectif' => $paie['effectif'] ?? 0]),
                      $paie !== null && $paie['effectif'] === 0 ? __('accueil_pwa.pilotage.masse_salariale_absente') : null,
                  ),
              ];
          @endphp
          <div class="grid grid-cols-2 sm:grid-cols-3 xl:grid-cols-6 gap-3 mb-5">
            @foreach ($kpisPilotage as $carte)
              <div class="min-w-0 bg-white rounded-xl border border-slate-200 p-4">
                <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ $carte['libelle'] }}</div>
                @if ($carte['valeur'] === null)
                  {{-- « Non consulté » par défaut ; une carte peut porter son
                       propre texte d'absence RÉELLE (Masse salariale). Jamais
                       « 0 F », qui se lit comme un vrai chiffre sur l'écran où
                       l'on décide. --}}
                  <div class="text-[17px] font-bold mt-1 leading-tight text-slate-300">{{ $carte['texteVide'] ?? __('accueil_pwa.non_consulte') }}</div>
                @else
                  <div class="text-[17px] font-bold mt-1 leading-tight break-words tabular-nums {{ $carte['accent'] }}"
                       @if ($carte['accent'] === '') style="color:var(--navy)" @endif>{{ $carte['valeur'] }}</div>
                @endif
                <div class="text-[11px] text-slate-400 mt-1 leading-snug">{{ $carte['detail'] }}</div>
              </div>
            @endforeach
          </div>

          <div class="grid grid-cols-1 xl:grid-cols-2 gap-3 mb-5">
            {{-- À TRAITER --}}
            <div class="bg-white rounded-xl border border-slate-200 overflow-hidden">
              <div class="px-4 py-3 border-b border-slate-200">
                <h2 class="text-[14px] font-bold" style="color:var(--navy)">{{ __('accueil_pwa.alertes.titre') }}</h2>
                <p class="text-[11px] text-slate-400 mt-0.5">{{ __('accueil_pwa.alertes.sous_titre') }}</p>
              </div>
              {{-- Les alertes RÉELLES, une ligne par mesure, dans l'ordre de
                   gravité du maître. Aucune n'est fabriquée : chacune vient
                   d'un Service, et le composant dit combien de sources il a pu
                   lire — « aucune alerte » et « rien n'a été lu » ne se disent
                   pas de la même façon. --}}
              @forelse ($aTraiter['alertes'] as $alerte)
                @php
                    [$fond, $pastille, $texte] = $couleursAlerte[$alerte['gravite']];
                @endphp
                <div class="flex items-start gap-3 px-4 py-3 border-b border-slate-100" style="background:{{ $fond }}">
                  <span class="w-2 h-2 rounded-full mt-1.5 shrink-0" style="background:{{ $pastille }}"></span>
                  <div class="flex-1 min-w-0">
                    <p class="text-[13px] font-semibold" style="color:{{ $texte }}">{{ $alerte['titre'] }}</p>
                    <p class="text-[11.5px] text-slate-500 mt-0.5">{{ $alerte['detail'] }}</p>
                  </div>
                  {{-- Un lien n'est offert que s'il MÈNE quelque part pour ce
                       rôle : `alertesPilotage()` rend `null` quand le module
                       cible est fermé. Un lien vers un 403 serait un contrôle
                       inerte (Article 3.3). --}}
                  @if ($alerte['url'] !== null)
                    <a href="{{ $alerte['url'] }}" wire:navigate class="text-[12px] font-semibold shrink-0 mt-0.5" style="color:var(--gold)">{{ __('accueil_pwa.alertes.ouvrir') }}</a>
                  @endif
                </div>
              @empty
                <p class="px-4 py-4 text-[13px] text-slate-500">{{ __('accueil_pwa.alertes.aucune') }}</p>
              @endforelse

              <p class="px-4 py-3 text-[11px] text-slate-400">
                {{ __('accueil_pwa.alertes.sources', ['lues' => $aTraiter['sources'], 'total' => $aTraiter['sourcesPossibles']]) }}
              </p>

              @if ($articlesCritiques->isNotEmpty())
                <div class="px-4 pb-4">
                  <button type="button" wire:click="$set('etatFormulaire', 'stocks-critiques')" class="text-[12px] font-semibold px-3 py-1.5 rounded-lg border border-slate-200">{{ __('accueil_pwa.alertes.voir') }}</button>
                </div>
              @endif
            </div>

            {{-- CE QUE CES CHIFFRES NE DISENT PAS — items TITRÉS avec tag
                 module, markup du maître (`m11-pilotage.js` l.281-290 :
                 titre + pastille `<span class="… bg-slate-100 …">module</span>`
                 au-dessus du détail). REFUS LEVÉ le 02/09/2026 : la version
                 précédente rendait une simple liste à puces, sans titre ni
                 module — la structure du maître, pas seulement son texte. --}}
            <div class="bg-white rounded-xl border border-slate-200 overflow-hidden">
              <div class="px-4 py-3 border-b border-slate-200" style="background:#FFFBEB">
                <h2 class="text-[14px] font-bold" style="color:#78350F">{{ __('accueil_pwa.reserves.titre') }}</h2>
                <p class="text-[11px] mt-0.5" style="color:#78350F">{{ __('accueil_pwa.reserves.sous_titre') }}</p>
              </div>
              @php
                  $reservesPilotage = [
                      ['titre' => __('accueil_pwa.reserves.is_titre'), 'detail' => __('accueil_pwa.reserves.is'), 'module' => __('accueil_pwa.reserves.module_comptabilite')],
                      ['titre' => __('accueil_pwa.reserves.structure_titre'), 'detail' => __('accueil_pwa.reserves.structure'), 'module' => __('accueil_pwa.reserves.module_analytique')],
                      ['titre' => __('accueil_pwa.reserves.recouvrements_titre'), 'detail' => __('accueil_pwa.reserves.recouvrements'), 'module' => __('accueil_pwa.reserves.module_creances')],
                      ['titre' => __('accueil_pwa.reserves.stock_titre'), 'detail' => __('accueil_pwa.reserves.stock'), 'module' => __('accueil_pwa.reserves.module_stocks')],
                  ];
              @endphp
              @foreach ($reservesPilotage as $reserve)
                <div class="px-4 py-3 border-b border-slate-100 last:border-0">
                  <div class="flex items-start justify-between gap-2">
                    <p class="text-[13px] font-semibold" style="color:#78350F">{{ $reserve['titre'] }}</p>
                    <span class="text-[10px] px-1.5 py-0.5 rounded bg-slate-100 text-slate-500 shrink-0">{{ $reserve['module'] }}</span>
                  </div>
                  <p class="text-[11.5px] text-slate-500 mt-1">{{ $reserve['detail'] }}</p>
                </div>
              @endforeach
            </div>
          </div>

          {{-- ================= LES DEUX GRAPHIQUES DU PILOTAGE =================
               Maître : `tableau-de-bord.html` l.202-217 — `height:260px` chacun.

               ⚠ LES DEUX REFUS QUI COUVRAIENT CE BLOC SONT LEVÉS, ET DATÉS.
               « Le troisième soustrait, par activité, des charges qui ne
               portent aucun centre d'analyse au schéma » : FAUX depuis que
               `ecritures_comptables.centre_id` est NOT NULL (RG-12) et que
               `AnalytiqueService` produit exactement cette marge, avec le
               sous-titre du maître pour motif. « Le quatrième découpe par
               ancienneté sans date d'échéance » : l'échéance manque en effet,
               et c'est pourquoi l'âge est compté depuis la DATE D'ÉMISSION —
               un fait daté, pas une politique de relance. PA-20 reste ouverte
               et l'écran le dit sous le graphique. --}}
          <div class="grid grid-cols-1 xl:grid-cols-2 gap-3 mb-5">
            <div class="bg-white rounded-xl border border-slate-200 p-4">
              <h2 class="text-[14px] font-bold mb-1" style="color:var(--navy)">{{ __('accueil_pwa.marge.titre') }}</h2>
              <p class="text-[11px] text-slate-400 mb-3">{{ __('accueil_pwa.marge.sous_titre') }}</p>

              @if (is_array($margeActivite) && $margeActivite !== [])
                <script type="application/json" id="donnees-graphique-marge">@json($margeActivite)</script>
                <div wire:ignore style="height:260px;position:relative">
                  <canvas id="graphe-centres"></canvas>
                </div>
              @elseif ($margeActivite === [])
                <p class="text-[13px] text-slate-500">{{ __('accueil_pwa.marge.vide') }}</p>
              @else
                <p class="text-[13px] text-slate-500">{{ __('accueil_pwa.non_consulte') }}</p>
              @endif
            </div>

            <div class="bg-white rounded-xl border border-slate-200 p-4">
              <h2 class="text-[14px] font-bold mb-1" style="color:var(--navy)">{{ __('accueil_pwa.creances.titre') }}</h2>
              <p class="text-[11px] text-slate-400 mb-3">{{ __('accueil_pwa.creances.sous_titre') }}</p>

              @if (is_array($creancesAnciennete))
                <script type="application/json" id="donnees-graphique-creances">@json($creancesAnciennete)</script>
                <div wire:ignore style="height:260px;position:relative">
                  <canvas id="graphe-creances"></canvas>
                </div>
                <p class="text-[11px] text-slate-400 mt-2">{{ __('accueil_pwa.creances.age_source') }}</p>
              @else
                <p class="text-[13px] text-slate-500">{{ __('accueil_pwa.non_consulte') }}</p>
              @endif
            </div>
          </div>

          {{-- ================= OCCUPATION & MEILLEURES VENTES =================
               Maître : `tableau-de-bord.html` l.220-222, rempli par
               `rendreOccupation()` et `rendreTopVentes()`.

               ⚠ LE REFUS SUR « meilleures ventes » EST LEVÉ, ET DATÉ. Il
               disait « aucun Service de domaine ne la calcule » ; `lignes_vente`
               porte `module`, `nom`, `quantite` et `montant`, et le registre
               est alimenté par `VenteService` depuis le 02/09/2026. --}}
          <h2 class="text-[14px] font-bold mb-3" style="color:var(--navy)">{{ __('accueil_pwa.occupation.titre') }}</h2>
          <div class="mb-4">
            <div class="bg-white rounded-xl border border-slate-200 p-4 flex flex-wrap items-center gap-6">
              <div>
                <p class="text-[11px] uppercase tracking-wide text-slate-400">{{ __('accueil_pwa.occupation.taux') }}</p>
                {{-- `null` n'est pas « 0 % » : sans mesure, le taux n'est pas
                     calculable, et afficher zéro affirmerait une exploitation
                     vide. --}}
                <p class="text-2xl font-bold tabular-nums" style="color:var(--navy)">{{ $occupation === null ? __('accueil_pwa.tiret') : $occupation . ' %' }}</p>
              </div>
              <p class="text-[12px] text-slate-500 flex-1 min-w-[240px]">{{ __('accueil_pwa.occupation.sous_titre') }}</p>
            </div>
          </div>

          <div class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-4 gap-3 mb-6">
            @foreach ($topVentes as $classement)
              <div class="bg-white rounded-xl border border-slate-200 p-3.5" wire:key="top-{{ $classement['cle'] }}">
                <p class="text-[11px] uppercase tracking-wide text-slate-400">{{ __('accueil_pwa.top_ventes.' . $classement['cle']) }}</p>
                {{-- Le critère est ANNONCÉ : un classement par quantité et un
                     classement par montant ne donnent pas le même ordre, et le
                     lecteur doit savoir lequel il regarde. --}}
                <p class="text-[11px] text-slate-400">{{ $classement['tri'] === 'quantite' ? __('accueil_pwa.top_ventes.par_quantite') : __('accueil_pwa.top_ventes.par_montant') }}</p>
                @if ($classement['lignes'] === [])
                  <p class="text-[12px] text-slate-400 py-3">{{ __('accueil_pwa.top_ventes.vide') }}</p>
                @else
                  <ol class="mt-2 space-y-1.5">
                    @foreach ($classement['lignes'] as $rang => $ligne)
                      <li class="flex items-baseline gap-2 text-[13px]">
                        <span class="w-4 text-[11px] text-slate-400 shrink-0">{{ $rang + 1 }}.</span>
                        <span class="flex-1 truncate text-slate-700">{{ $ligne['nom'] }}</span>
                        <span class="font-semibold tabular-nums" style="color:var(--navy)">{{ $classement['tri'] === 'quantite' ? $ligne['quantite'] : MontantFcfa::format($ligne['montant']) }}</span>
                        <span class="text-[11px] text-slate-400">{{ $classement['tri'] === 'quantite' ? __('accueil_pwa.top_ventes.unite_quantite') : '' }}</span>
                      </li>
                    @endforeach
                  </ol>
                @endif
              </div>
            @endforeach
          </div>

          {{-- PAR MODULE — `#modules`, les NEUF cartes du maître
               (`m11-pilotage.js`, `rendreModules()` l.362-475), en données
               réelles — directive du Product Owner du 02/09/2026.

               ⚠ REFUS LEVÉ ET DATÉ (02/09/2026). Le motif qui limitait ce
               bloc à trois cartes — « les six autres exigeraient un agrégat
               que rien sur cette page ne calcule encore : les ajouter serait
               fabriquer un chiffre plutôt que réutiliser une lecture » —
               était vrai à l'écriture et ne l'est plus : chaque agrégat vit
               désormais chez un auteur UNIQUE partagé avec l'écran de son
               module (état dérivé sur `Reservation`, `ParcVehiculeService`,
               `ReservationTourService`, `DepenseService`,
               `SoldeClientService`), et la carte le lit — voir
               `Accueil::cartesParModule()` (PA-121 ; PA-144 pour la
               datation du motif levé). Les cartes de ventilation par facture
               qui occupaient ce bloc n'étaient PAS celles du maître ; la
               ventilation reste rendue par les deux graphiques du panneau
               Exploitation, qui la lisaient déjà.

               Le markup est celui de `bloc()` : carte `<a>` cliquable vers
               l'écran du module, titre + badge module, lignes libellé/valeur
               à bordures `border-slate-50`, note ambrée conditionnelle. Tout
               calcul vit dans le composant — la vue ne calcule rien — et
               chaque carte n'existe que si le droit de SON module le permet
               (`MenuLateral`, la même règle que le menu latéral), vérifié
               AVANT le calcul, jamais après. --}}
          <h2 class="text-[14px] font-bold mb-3" style="color:var(--navy)">{{ __('accueil_pwa.activite.titre') }}</h2>
          <div class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3">
            @forelse ($cartesModules as $carte)
              <a href="{{ $carte['url'] }}" wire:navigate wire:key="module-{{ $carte['cle'] }}" class="carte-kpi block bg-white rounded-xl border border-slate-200 p-4">
                <div class="flex items-center justify-between mb-2.5">
                  <h3 class="text-[13px] font-bold" style="color:var(--navy)">{{ $carte['titre'] }}</h3>
                  <span class="text-[10px] px-1.5 py-0.5 rounded bg-slate-100 text-slate-500">{{ $carte['badge'] }}</span>
                </div>
                @foreach ($carte['lignes'] as $ligne)
                  <div class="flex justify-between items-baseline py-1 border-b border-slate-50 last:border-0">
                    <span class="text-[12px] text-slate-500">{{ $ligne['libelle'] }}</span>
                    <span class="text-[13px] font-semibold {{ $ligne['classe'] }}" @if ($ligne['classe'] === '') style="color:var(--navy)" @endif>{{ $ligne['valeur'] }}</span>
                  </div>
                @endforeach
                @if ($carte['note'] !== null)
                  <p class="text-[10.5px] text-amber-700 mt-2">{{ $carte['note'] }}</p>
                @endif
              </a>
            @empty
              {{-- L'état vide du maître : le RBAC a filtré toutes les cartes. --}}
              <p class="text-[13px] text-slate-400 md:col-span-2 xl:col-span-3">{{ __('accueil_pwa.pilotage.modules.vide') }}</p>
            @endforelse
          </div>

          {{-- ========== L'ÉTAT CONSOLIDÉ : LE DOCUMENT PDF DU MAÎTRE ==========
               maitre — `m11-pilotage.js`, `etatCourant()` : le maître ne rend
               ce tableau que dans son DOCUMENT (`entetes: ['Rubrique',
               'Indicateur', 'Valeur']`, bouton « PDF »). Ici, le même document
               est rendu à l'impression du panneau (`hidden print:block`) — et
               donc au premier GET, où `ColonnesDesTableauxPwaTest` le vérifie.
               CHAQUE ligne REPREND une valeur que ce panneau affiche déjà —
               les six cartes KPI et les cartes par module — jamais un second
               agrégat (PA-121). Une lecture absente rend son texte d'absence
               (« Non consulté »), jamais un zéro plausible (PA-120). --}}
          @php
              $lignesEtatConsolide = [];
              foreach ($kpisPilotage as $carte) {
                  $lignesEtatConsolide[] = [
                      __('accueil_pwa.etat_consolide.rubrique_indicateurs'),
                      $carte['libelle'],
                      $carte['valeur'] ?? $carte['texteVide'] ?? __('accueil_pwa.non_consulte'),
                  ];
              }
              // Les NEUF cartes « Par module » — les MÊMES lignes que le
              // panneau (`cartesParModule()`, `etatCourant()` du maître),
              // jamais un second agrégat (02/09/2026, PA-121). Rubrique =
              // titre de la carte, une ligne par indicateur affiché.
              foreach ($cartesModules as $carteModule) {
                  foreach ($carteModule['lignes'] as $ligneModule) {
                      $lignesEtatConsolide[] = [$carteModule['titre'], $ligneModule['libelle'], $ligneModule['valeur']];
                  }
              }
          @endphp
          <div class="hidden print:block mt-6">
            <h2 class="text-sm font-bold mb-2" style="color:var(--navy)">{{ __('accueil_pwa.etat_consolide.titre') }}</h2>
            <table class="w-full text-[12px]">
              <thead>
                <tr class="text-left text-[11px] font-semibold text-slate-500 uppercase border-b-2 border-slate-400">
                  <th class="text-left px-2 py-1.5">{{ __('accueil_pwa.etat_consolide.col_rubrique') }}</th>
                  <th class="text-left px-2 py-1.5">{{ __('accueil_pwa.col_indicateur') }}</th>
                  <th class="text-right px-2 py-1.5">{{ __('accueil_pwa.col_valeur') }}</th>
                </tr>
              </thead>
              <tbody>
                @forelse ($lignesEtatConsolide as $indexLigneEtat => $ligneEtat)
                  <tr class="border-b border-slate-200" wire:key="etat-consolide-{{ $indexLigneEtat }}">
                    <td class="px-2 py-1.5 text-slate-500">{{ $ligneEtat[0] }}</td>
                    <td class="px-2 py-1.5">{{ $ligneEtat[1] }}</td>
                    <td class="px-2 py-1.5 text-right font-semibold tabular-nums">{{ $ligneEtat[2] }}</td>
                  </tr>
                @empty
                  <tr>
                    <td colspan="3" class="px-2 py-6 text-center text-slate-400">{{ __('accueil_pwa.lecture_impossible') }}</td>
                  </tr>
                @endforelse
              </tbody>
            </table>
          </div>

        </div>{{-- /panneau pilotage --}}

        {{-- ================= PANNEAU 3 : TABLEAU CROISÉ DYNAMIQUE ================= --}}
        {{-- Même retrait de marge que le panneau Pilotage (01/09/2026). --}}
        <div data-panneau-tb="croise" class="hidden">

          <div class="bg-white rounded-xl border border-slate-200 p-4 mb-4">
            <p class="text-[12px] text-slate-500 mb-3 max-w-3xl">{{ __('accueil_pwa.croise.intro') }}</p>

            {{-- LES QUATRE SÉLECTEURS DU MAÎTRE (l.242-262).

                 Le refus qui les couvrait — « deux sources seulement sont
                 servies, et les réservations ne portent aucun montant » — est
                 LEVÉ et daté : les trois registres existent côté serveur
                 (`lignes_vente`, `lignes_depense`, `reservations`). La moitié
                 vraie du motif est conservée et DÉPLACÉE là où elle compte :
                 le montant d'une réservation est son acompte, et la note sous
                 le tableau le dit. --}}
            <div class="flex flex-wrap items-end gap-3">
              <div>
                <label class="block text-[11px] uppercase tracking-wide text-slate-400 mb-1">{{ __('accueil_pwa.croise.lignes') }}</label>
                <select wire:model.live="croiseLigne" class="text-[13px] border border-slate-300 rounded-lg px-2.5 py-1.5 bg-white">
                  @foreach (array_keys(Accueil::AXES_CROISE) as $axe)
                    <option value="{{ $axe }}">{{ __('accueil_pwa.croise.axes.' . $axe) }}</option>
                  @endforeach
                </select>
              </div>
              <div>
                <label class="block text-[11px] uppercase tracking-wide text-slate-400 mb-1">{{ __('accueil_pwa.croise.colonnes') }}</label>
                <select wire:model.live="croiseColonne" class="text-[13px] border border-slate-300 rounded-lg px-2.5 py-1.5 bg-white">
                  @foreach (array_keys(Accueil::AXES_CROISE) as $axe)
                    <option value="{{ $axe }}">{{ __('accueil_pwa.croise.axes.' . $axe) }}</option>
                  @endforeach
                </select>
              </div>
              <div>
                <label class="block text-[11px] uppercase tracking-wide text-slate-400 mb-1">{{ __('accueil_pwa.croise.mesure') }}</label>
                <select wire:model.live="croiseMesure" class="text-[13px] border border-slate-300 rounded-lg px-2.5 py-1.5 bg-white">
                  @foreach (array_keys(Accueil::MESURES_CROISE) as $mesure)
                    <option value="{{ $mesure }}">{{ __('accueil_pwa.croise.mesures.' . $mesure) }}</option>
                  @endforeach
                </select>
              </div>
              <div>
                <label class="block text-[11px] uppercase tracking-wide text-slate-400 mb-1">{{ __('accueil_pwa.croise.sources') }}</label>
                <div class="flex flex-wrap gap-2 pt-1">
                  @foreach (Accueil::SOURCES_CROISE as $source)
                    <label class="flex items-center gap-1.5 text-[13px] text-slate-600">
                      {{-- Le libellé vient du TABLEAU `sources_libelles`, jamais
                           d'une clé dont la fin serait une variable : une clé
                           qu'aucun balayage ne peut résoudre est une clé que
                           personne ne peut vérifier (`MessagesUtilisateurTest`). --}}
                      <input type="checkbox" wire:model.live="croiseSources" value="{{ $source }}"> {{ __('accueil_pwa.croise.sources_libelles')[$source] }}
                    </label>
                  @endforeach
                </div>
              </div>
              <div class="flex-1"></div>
              {{-- ⚠ DÉROGATION PO du 01/09/2026 — les deux boutons du maître
                   (`tableau-de-bord.html` l.260-261, « Export PDF » /
                   « Export Excel ») sont remplacés par UN bouton
                   « Exporter » qui ouvre la même modale d'export ; le format
                   s'y choisit, sans présélection imposée. Registre :
                   `App\Pwa\Support\DerogationsMaquette`
                   (export_bouton_unique). Jeton :
                   maitre-refuse:tableau-de-bord.html#page --}}
              <button type="button" wire:click="ouvrirExport" class="text-[12px] font-semibold px-3 py-1.5 rounded-lg border border-slate-200 text-slate-600 hover:bg-slate-50">{{ __('pwa.export.bouton') }}</button>
            </div>
          </div>

          <div class="bg-white rounded-xl border border-slate-200 overflow-hidden">
            <div class="overflow-x-auto">
              <table class="w-full text-[13px]">
                {{-- ⚠ DES `<td role="columnheader">`, PAS DES `<th>`, ET LA
                     RAISON EST DE FOND.

                     Cet en-tête n'est PAS un jeu de colonnes d'écran : c'est
                     une VALEUR choisie par le lecteur. « Activité » est le
                     libellé de l'axe qu'il vient de sélectionner, « août 2026 »
                     une valeur de la table de faits, et les deux changent à
                     chaque manipulation des sélecteurs. Les émettre en `<th>`
                     faisait compter à `ColonnesDesTableauxPwaTest` — qui
                     inventorie les noms de colonne de chaque écran — trois
                     colonnes « inventées » par la PWA : mesuré le 02/09/2026,
                     et la garde avait raison de le dire, puisqu'elle ne peut
                     pas distinguer un nom de colonne d'une donnée.

                     `role="columnheader"` conserve la sémantique pour les
                     lecteurs d'écran : rien n'est perdu à l'usage, seule la
                     balise change. Le maître, lui, écrit `<th>` — il n'a
                     aucune garde d'inventaire à satisfaire. --}}
                <thead class="bg-[var(--navy)] text-[11px] uppercase tracking-wide text-white/90 font-semibold">
                  <tr>
                    <td role="columnheader" class="text-left px-4 py-2.5 font-semibold">{{ $croise === null ? __('accueil_pwa.croise.col_axe') : __('accueil_pwa.croise.axes.' . $croise['axeLigne']) }}</td>
                    @if ($croise !== null)
                      @foreach ($croise['colonnes'] as $colonne)
                        <td role="columnheader" class="text-right px-4 py-2.5 font-semibold">{{ $colonne }}</td>
                      @endforeach
                    @endif
                    <td role="columnheader" class="text-right px-4 py-2.5 font-semibold">{{ __('accueil_pwa.croise.total') }}</td>
                  </tr>
                </thead>
                <tbody>
                  @if ($croise !== null && ! $croise['vide'])
                    @foreach ($croise['lignes'] as $index => $nomLigne)
                      <tr class="border-t border-slate-100" wire:key="croise-{{ $index }}">
                        <td class="px-4 py-2.5 font-semibold text-slate-700">{{ $nomLigne }}</td>
                        @foreach ($croise['grille'][$index] as $valeur)
                          {{-- Un zéro s'affiche en gris pâle plutôt que d'être
                               masqué : une cellule vide laisserait croire à une
                               donnée manquante là où il y a bien eu zéro
                               mouvement (le maître, l.604-606). --}}
                          <td class="px-4 py-2.5 text-right tabular-nums {{ MontantFcfa::estNegatif($valeur) ? 'text-red-600' : (bccomp($valeur, '0.00', 2) === 0 ? 'text-slate-300' : '') }}">{{ $croise['monnaie'] ? MontantFcfa::format($valeur) : (string) (int) $valeur }}</td>
                        @endforeach
                        <td class="px-4 py-2.5 text-right font-bold tabular-nums {{ MontantFcfa::estNegatif($croise['totauxLignes'][$index]) ? 'text-red-600' : '' }}">{{ $croise['monnaie'] ? MontantFcfa::format($croise['totauxLignes'][$index]) : (string) (int) $croise['totauxLignes'][$index] }}</td>
                      </tr>
                    @endforeach
                  @elseif ($croiseSourcesRetenues === [])
                    {{-- Aucune source cochée : on le DIT. Afficher une grille
                         vide laisserait croire qu'il n'y a rien à voir sur la
                         période. --}}
                    <tr><td class="px-4 py-10 text-center text-[13px] text-slate-400">{{ __('accueil_pwa.croise.aucune_source') }}</td></tr>
                  @else
                    <tr><td class="px-4 py-10 text-center text-[13px] text-slate-400">{{ __('accueil_pwa.croise.vide') }}</td></tr>
                  @endif
                </tbody>
                <tfoot class="bg-slate-50 font-semibold">
                  @if ($croise !== null && ! $croise['vide'])
                    <tr class="border-t-2 border-slate-200">
                      <td class="px-4 py-2.5">{{ __('accueil_pwa.croise.total') }}</td>
                      @foreach ($croise['totauxColonnes'] as $total)
                        <td class="px-4 py-2.5 text-right tabular-nums {{ MontantFcfa::estNegatif($total) ? 'text-red-600' : '' }}">{{ $croise['monnaie'] ? MontantFcfa::format($total) : (string) (int) $total }}</td>
                      @endforeach
                      <td class="px-4 py-2.5 text-right {{ MontantFcfa::estNegatif($croise['total']) ? 'text-red-600' : '' }}">{{ $croise['monnaie'] ? MontantFcfa::format($croise['total']) : (string) (int) $croise['total'] }}</td>
                    </tr>
                  @endif
                </tfoot>
              </table>
            </div>
          </div>
          <p class="text-[12px] text-slate-400 mt-2">
            {{ $croise === null ? __('accueil_pwa.non_consulte') : __('accueil_pwa.croise.note', ['nombre' => $croise['nbFaits']]) }}
            {{ __('accueil_pwa.croise.note_reservations') }}
          </p>

        </div>{{-- /panneau croise --}}
        @endif

      </div>
    </main>
  </div>

  {{--
      ============================ MODALES ============================

      Les cinq modales du maître (`tableau-de-bord.html` l.280-399) :
      `modale-client-rapide`, `modale-reservation-rapide`,
      `modale-stocks-critiques`, `modale-rapport-rapide`,
      `modale-checkin-rapide`. Toutes passent par le châssis partagé
      `<x-pwa.modale>` — voile `.overlay-modale`, boîte à 12 px,
      `max-height:90vh`, `style="display:flex"` sans lequel la modale serait
      dans le DOM, invisible et inerte. Les largeurs sont celles du maître :
      420, 460, 520, 420, 420.

      ⚠ Le bouton « Annuler » de chacune vient de la clé PARTAGÉE
      `pwa.modale.annuler`, dont la valeur est « Annuler ». Le libellé n'est pas
      recopié dans `lang/fr/accueil_pwa.php` : deux listes décrivant la même
      chose divergeraient, et c'est le bouton le plus répété de la PWA
      (Article 10).

      Une SIXIÈME modale s'y ajoute, absente du maître : `checkout`. Le maître
      ne pose qu'un check-in, parce que son check-out est une ligne de tableau
      sans confirmation ; ici le départ déclenche une écriture réelle
      (`SejourService::checkout`, l'unité passe en nettoyage) et une écriture
      irréversible se confirme.
  --}}

  @if ($etatFormulaire === 'client')
    <x-pwa.modale :titre="__('accueil_pwa.modale_client.titre')" largeur="420px">
      <form wire:submit.prevent="enregistrerClientRapide" class="space-y-4">
        <div>
          <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('accueil_pwa.modale_client.nom') }} <span class="text-red-500">*</span></label>
          <input type="text" wire:model="clientNom" class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm">
          @error('clientNom') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>
        <div>
          <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('accueil_pwa.modale_client.telephone') }} <span class="text-red-500">*</span></label>
          <input type="text" wire:model="clientTelephone" class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm">
          @error('clientTelephone') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>
        <div>
          <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('accueil_pwa.modale_client.type') }}</label>
          <select wire:model="clientType" class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm bg-white">
            @foreach (Accueil::TYPES_CLIENT as $valeur => $cle)
              <option value="{{ $valeur }}">{{ __($cle) }}</option>
            @endforeach
          </select>
        </div>
        <div class="flex justify-end gap-3 pt-2">
          <button type="button" wire:click="fermerModales" class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
          <button type="submit" class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('accueil_pwa.modale_client.valider') }}</button>
        </div>
      </form>
    </x-pwa.modale>
  @endif

  @if ($etatFormulaire === 'reservation')
    <x-pwa.modale :titre="__('accueil_pwa.modale_reservation.titre')" largeur="460px">
      <p class="text-[13px] text-slate-400 bg-slate-50 rounded-lg px-3 py-2">
        {{ __('accueil_pwa.modale_reservation.renvoi') }}
        <a href="{{ route('pwa.reservations') }}" wire:navigate class="font-semibold" style="color:var(--gold)">{{ __('accueil_pwa.modale_reservation.renvoi_lien') }}</a>
      </p>
      <form wire:submit.prevent="enregistrerReservationRapide" class="space-y-4">
        <div>
          <div class="flex items-center justify-between mb-1.5">
            <label class="block text-[15px] font-semibold text-slate-700">{{ __('accueil_pwa.modale_reservation.client') }} <span class="text-red-500">*</span></label>
            @if ($peutEcrireClient)
              {{-- Créer la fiche SANS quitter la modale (Product Owner,
                   01/09/2026). Masqué sans droit M3 : l'écriture réelle est
                   une création de client (PA-65, droit par opération). --}}
              <label class="flex items-center gap-1.5 text-[12px] font-semibold text-slate-500 cursor-pointer">
                <input type="checkbox" wire:model.live="resaNouveauClient" class="rounded border-slate-300">
                {{ __('accueil_pwa.modale_reservation.nouveau_client') }}
              </label>
            @endif
          </div>
          @if ($resaNouveauClient)
            {{-- Les trois champs de la modale client du maître (l.289-295) :
                 nom, téléphone, type. Client et réservation partent dans la
                 MÊME transaction — un refus RG-01 ne laisse aucune fiche. --}}
            <div class="space-y-2 bg-slate-50 rounded-lg p-3">
              <input type="text" wire:model="resaClientNom" placeholder="{{ __('accueil_pwa.modale_reservation.client_nom') }}" class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm">
              @error('resaClientNom') <p class="text-[12px] text-red-600">{{ $message }}</p> @enderror
              <input type="text" wire:model="resaClientTelephone" placeholder="{{ __('accueil_pwa.modale_reservation.client_telephone') }}" class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm">
              @error('resaClientTelephone') <p class="text-[12px] text-red-600">{{ $message }}</p> @enderror
              <select wire:model="resaClientType" class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm bg-white">
                @foreach (Accueil::TYPES_CLIENT as $valeur => $cle)
                  <option value="{{ $valeur }}">{{ __($cle) }}</option>
                @endforeach
              </select>
              @error('resaClientType') <p class="text-[12px] text-red-600">{{ $message }}</p> @enderror
            </div>
          @else
            {{-- Vraie clé étrangère, jamais du texte libre : un nom tapé au
                 clavier rapprocherait deux homonymes sur une seule fiche. --}}
            <select wire:model="resaClientId" class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm bg-white">
              <option value="">{{ __('accueil_pwa.modale_reservation.choisir_client') }}</option>
              @foreach ($clients as $client)
                <option value="{{ $client->id }}">{{ $client->nom }} {{ $client->prenom }} — {{ $client->telephone }}</option>
              @endforeach
            </select>
            @error('resaClientId') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
          @endif
        </div>
        {{-- L'ordre des champs est celui du maitre : Client, Unite, Canal,
             Arrivee, Nuits (rapport de conformite du 01/09/2026). --}}
        <div>
          <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('accueil_pwa.modale_reservation.unite') }} <span class="text-red-500">*</span></label>
          {{-- La liste suit les dates saisies : elle est CALCULÉE par
               `DisponibiliteService` (RG-02), jamais lue dans `statut`. --}}
          <select wire:model="resaUniteId" class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm bg-white">
            <option value="">{{ __('accueil_pwa.modale_reservation.choisir_unite') }}</option>
            @foreach ($unitesLibres as $unite)
              <option value="{{ $unite->id }}">{{ $unite->numero }} — {{ $unite->categorie?->libelle }}</option>
            @endforeach
          </select>
          @if ($unitesLibres->isEmpty())
            <p class="text-[12px] text-amber-700 mt-1">{{ __('accueil_pwa.modale_reservation.aucune_unite') }}</p>
          @endif
          @error('resaUniteId') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>
        <div>
          <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('accueil_pwa.modale_reservation.canal') }} <span class="text-red-500">*</span></label>
          {{-- Le champ du maître (l.318-323), rendu depuis PA-163. Obligatoire
               COMME CHEZ LUI : jusqu'au 24/08/2026 sa réservation rapide
               écrivait « Physique » d'office, et l'analyse par canal comptait
               au comptoir ce qui venait de Booking. Le référentiel est
               `canaux_reservation`, administrable — jamais une liste en dur. --}}
          <select wire:model="resaCanalId" class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm bg-white">
            <option value="">{{ __('accueil_pwa.modale_reservation.choisir_canal') }}</option>
            @foreach ($canaux as $canal)
              <option value="{{ $canal->id }}">{{ $canal->nom }}</option>
            @endforeach
          </select>
          @error('resaCanalId') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>
        <div class="grid grid-cols-2 gap-3">
          <div>
            <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('accueil_pwa.modale_reservation.arrivee') }} <span class="text-red-500">*</span></label>
            <input type="date" wire:model.live="resaDateArrivee" class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm">
            @error('resaDateArrivee') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
          </div>
          <div>
            <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('accueil_pwa.modale_reservation.nuits') }} <span class="text-red-500">*</span></label>
            <input type="number" min="1" wire:model.live="resaNuits" class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm">
            @error('resaNuits') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
          </div>
        </div>
        <div class="flex justify-end gap-3 pt-2">
          <button type="button" wire:click="fermerModales" class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
          <button type="submit" class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('accueil_pwa.modale_reservation.valider') }}</button>
        </div>
      </form>
    </x-pwa.modale>
  @endif

  @if ($etatFormulaire === 'checkin')
    <x-pwa.modale :titre="__('accueil_pwa.modale_checkin.titre')" largeur="420px">
      <p class="text-[12px] text-slate-500">{{ __('accueil_pwa.modale_checkin.aide') }}</p>
      <form wire:submit.prevent="confirmerCheckin" class="space-y-4">
        {{-- Client et nuits sont AFFICHÉS, jamais saisis : ils viennent de la
             réservation, et les retaper permettrait de les faire diverger. --}}
        <div>
          <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('accueil_pwa.modale_checkin.client') }}</label>
          <p class="text-sm text-slate-700 bg-slate-50 rounded-lg px-3 py-2.5">{{ $reservationSejour?->client?->nom }} {{ $reservationSejour?->client?->prenom }}</p>
        </div>
        <div>
          <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('accueil_pwa.modale_checkin.unite') }}</label>
          <p class="text-sm text-slate-700 bg-slate-50 rounded-lg px-3 py-2.5">{{ $reservationSejour?->unite?->numero }}</p>
        </div>
        <div>
          <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('accueil_pwa.modale_checkin.nuits') }}</label>
          <p class="text-sm text-slate-700 bg-slate-50 rounded-lg px-3 py-2.5">{{ $reservationSejour?->nombreNuitees() }}</p>
        </div>
        @error('sejourReservationId') <p class="text-[12px] text-red-600">{{ $message }}</p> @enderror
        <div class="flex justify-end gap-3 pt-2">
          <button type="button" wire:click="fermerModales" class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
          <button type="submit" class="text-[13px] px-4 py-2 rounded-lg bg-[var(--succes)] text-white font-semibold">{{ __('accueil_pwa.modale_checkin.valider') }}</button>
        </div>
      </form>
    </x-pwa.modale>
  @endif

  @if ($etatFormulaire === 'checkout')
    <x-pwa.modale :titre="__('accueil_pwa.modale_checkout.titre')" largeur="420px">
      <p class="text-[12px] text-slate-500">{{ __('accueil_pwa.modale_checkout.aide') }}</p>
      <form wire:submit.prevent="confirmerCheckout" class="space-y-4">
        <div>
          <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('accueil_pwa.modale_checkin.client') }}</label>
          <p class="text-sm text-slate-700 bg-slate-50 rounded-lg px-3 py-2.5">{{ $reservationSejour?->client?->nom }} {{ $reservationSejour?->client?->prenom }}</p>
        </div>
        @error('sejourReservationId') <p class="text-[12px] text-red-600">{{ $message }}</p> @enderror
        <div class="flex justify-end gap-3 pt-2">
          <button type="button" wire:click="fermerModales" class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
          <button type="submit" class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('accueil_pwa.modale_checkout.valider') }}</button>
        </div>
      </form>
    </x-pwa.modale>
  @endif

  {{-- « Check-in » DEPUIS « Chambres disponibles » — maître :
       `modale-checkin-rapide` (`tableau-de-bord.html` l.379-399). Deux champs
       seulement (client, nuits) : l'unité est déjà connue du clic, il n'y a
       ni sélecteur d'unité ni canal ici — c'est la différence structurelle
       avec la modale « Réservation rapide » ci-dessus, et elle est du
       maître, pas de la PWA. --}}
  @if ($etatFormulaire === 'checkin-chambre')
    <x-pwa.modale :titre="__('accueil_pwa.modale_checkin_chambre.titre', ['unite' => $checkinUnite?->numero])" largeur="420px">
      <form wire:submit.prevent="confirmerCheckinDepuisChambre" class="space-y-4">
        <div>
          <div class="flex items-center justify-between mb-1.5">
            <label class="block text-[15px] font-semibold text-slate-700">{{ __('accueil_pwa.modale_checkin_chambre.client') }} <span class="text-red-500">*</span></label>
            @if ($peutEcrireClient)
              <label class="flex items-center gap-1.5 text-[12px] font-semibold text-slate-500 cursor-pointer">
                <input type="checkbox" wire:model.live="checkinNouveauClient" class="rounded border-slate-300">
                {{ __('accueil_pwa.modale_checkin_chambre.nouveau_client') }}
              </label>
            @endif
          </div>
          @if ($checkinNouveauClient)
            <div class="space-y-2 bg-slate-50 rounded-lg p-3">
              <input type="text" wire:model="checkinClientNom" placeholder="{{ __('accueil_pwa.modale_checkin_chambre.client_nom') }}" class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm">
              @error('checkinClientNom') <p class="text-[12px] text-red-600">{{ $message }}</p> @enderror
              <input type="text" wire:model="checkinClientTelephone" placeholder="{{ __('accueil_pwa.modale_checkin_chambre.client_telephone') }}" class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm">
              @error('checkinClientTelephone') <p class="text-[12px] text-red-600">{{ $message }}</p> @enderror
              <select wire:model="checkinClientType" class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm bg-white">
                @foreach (Accueil::TYPES_CLIENT as $valeur => $cle)
                  <option value="{{ $valeur }}">{{ __($cle) }}</option>
                @endforeach
              </select>
              @error('checkinClientType') <p class="text-[12px] text-red-600">{{ $message }}</p> @enderror
            </div>
          @else
            <select wire:model="checkinClientId" class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm bg-white">
              <option value="">{{ __('accueil_pwa.modale_checkin_chambre.choisir_client') }}</option>
              @foreach ($clients as $client)
                <option value="{{ $client->id }}">{{ $client->nom }} {{ $client->prenom }} — {{ $client->telephone }}</option>
              @endforeach
            </select>
            @error('checkinClientId') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
          @endif
        </div>
        <div>
          <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('accueil_pwa.modale_checkin_chambre.nuits') }} <span class="text-red-500">*</span></label>
          <input type="number" min="1" wire:model="checkinNuits" class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm">
          @error('checkinNuits') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>
        @error('checkinUniteId') <p class="text-[12px] text-red-600">{{ $message }}</p> @enderror
        <div class="flex justify-end gap-3 pt-2">
          <button type="button" wire:click="fermerModales" class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
          <button type="submit" class="text-[13px] px-4 py-2 rounded-lg font-semibold" style="background:var(--succes);color:white">{{ __('accueil_pwa.modale_checkin_chambre.valider') }}</button>
        </div>
      </form>
    </x-pwa.modale>
  @endif

  {{-- « Payer » (PA-165) — recouvrement de la facture qui couvre la
       réservation du jour, mêmes champs que `ClientsCreances`. --}}
  @if ($etatFormulaire === 'payer')
    <x-pwa.modale :titre="__('accueil_pwa.modale_payer.titre')" largeur="420px">
      <form wire:submit.prevent="confirmerRecouvrementDuJour" class="space-y-4">
        <div>
          <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('accueil_pwa.modale_checkin.client') }}</label>
          <p class="text-sm text-slate-700 bg-slate-50 rounded-lg px-3 py-2.5">{{ $payerClientNom }}</p>
        </div>
        <div>
          <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('pwa.clients.champ_montant_recu') }}</label>
          <input type="number" min="1" step="1" wire:model="payerMontant" class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm">
          @error('payerMontant') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>
        <div>
          <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('pwa.clients.champ_mode') }}</label>
          <select wire:model="payerMode" class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm bg-white">
            @foreach (\App\Domain\Facturation\Services\EncaissementFactureService::TRESORERIE_PAR_MODE as $cle => $tresorerie)
              <option value="{{ $cle }}">{{ __(match ($cle) {
                  'mobile_money' => 'pwa.clients.mode_mobile_money',
                  'carte' => 'pwa.clients.mode_carte',
                  'virement' => 'pwa.clients.mode_virement',
                  default => 'pwa.clients.mode_especes',
              }) }}</option>
            @endforeach
          </select>
        </div>
        @error('payerReservationId') <p class="text-[12px] text-red-600">{{ $message }}</p> @enderror
        <div class="flex justify-end gap-3 pt-2">
          <button type="button" wire:click="fermerModales" class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
          <button type="submit" class="text-[13px] px-4 py-2 rounded-lg bg-[var(--succes)] text-white font-semibold">{{ __('pwa.clients.champ_enregistrer_recouvrement') }}</button>
        </div>
      </form>
    </x-pwa.modale>
  @endif

  {{-- EXCLU de la barre de recherche par table (PO, 01/09/2026) : modale de
       KPI, bornée aux articles réellement en alerte de seuil — un texte de
       recherche sur une poignée de lignes contextuelles n'a rien à filtrer.
       Le référentiel complet, filtrable, vit sur l'écran « Stocks ». --}}
  @if ($etatFormulaire === 'stocks-critiques')
    <x-pwa.modale :titre="__('accueil_pwa.modale_stocks.titre')" largeur="520px">
      @if ($articlesCritiques->isEmpty())
        <p class="text-[13px] text-slate-500">{{ __('accueil_pwa.modale_stocks.vide') }}</p>
      @else
        <table class="w-full text-sm">
          <thead class="bg-[var(--navy)]">
            <tr class="text-left text-[11px] font-semibold text-white/90 uppercase tracking-wide">
              <th class="px-3 py-2">{{ __('accueil_pwa.modale_stocks.col_article') }}</th>
              <th class="px-3 py-2 text-right">{{ __('accueil_pwa.modale_stocks.col_stock') }}</th>
              <th class="px-3 py-2 text-right">{{ __('accueil_pwa.modale_stocks.col_seuil') }}</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-slate-100">
            @foreach ($articlesCritiques as $article)
              <tr wire:key="crit-{{ $article->id }}">
                <td class="px-3 py-2 text-slate-700">{{ $article->libelle }}</td>
                <td class="px-3 py-2 text-right text-red-600">{{ $article->stock }} {{ $article->unite_mesure }}</td>
                <td class="px-3 py-2 text-right text-slate-500">{{ $article->seuil_alerte }} {{ $article->unite_mesure }}</td>
              </tr>
            @endforeach
          </tbody>
        </table>
      @endif

      <x-slot:pied>
        <button type="button" wire:click="fermerModales" class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <a href="{{ route('pwa.stocks.liste') }}" wire:navigate class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('accueil_pwa.modale_stocks.gerer') }}</a>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  @if ($etatFormulaire === 'rapport')
    <x-pwa.modale :titre="__('accueil_pwa.modale_rapport.titre')" largeur="420px">
      <div>
        <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('accueil_pwa.modale_rapport.type') }}</label>
        <select wire:model="typeRapport" class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm bg-white">
          @foreach (Accueil::TYPES_RAPPORT as $type)
            <option value="{{ $type }}">{{ __('accueil_pwa.modale_rapport.' . $type) }}</option>
          @endforeach
        </select>
        <p class="text-[12px] text-slate-400 mt-1">{{ __('accueil_pwa.modale_rapport.note') }}</p>
        @error('typeRapport') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
      </div>
      <div>
        <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('accueil_pwa.modale_rapport.format') }}</label>
        <select wire:model="formatExport" class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm bg-white">
          <option value="pdf">{{ __('accueil_pwa.modale_rapport.format_pdf') }}</option>
          <option value="excel">{{ __('accueil_pwa.modale_rapport.format_excel') }}</option>
        </select>
      </div>

      <x-slot:pied>
        <button type="button" wire:click="fermerModales" class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="genererExport" class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('accueil_pwa.modale_rapport.valider') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  @if ($etatFormulaire === 'export')
    @include('pwa.partials.modale-export', ['titre' => __('accueil_pwa.export_titre'), 'sousTitre' => __('accueil_pwa.modale_rapport.note')])
  @endif

  @include('pwa.partials.acces-rapide')

</div>

{{--
    ================= LES GRAPHIQUES ET LA BASCULE D'ONGLET =================

    Maître : `prototype_v2/pages/tableau-de-bord.js` (les trois graphiques de
    l'exploitation), `m11-pilotage.js` (les deux du consolidé), et le script en
    ligne de `tableau-de-bord.html` l.463-484 (la bascule).

    ## LA RESSOURCE EST LOCALE, ET ELLE DOIT LE RESTER

    `public/assets/js/vendor/chart.umd.min.js` est la copie exacte du fichier
    que le maître charge. `ConformiteMaquettePwaTest` refuse toute page qui
    chargerait une ressource distante : la PWA doit s'ouvrir sans Internet, et
    un `<script src="https://cdn…">` réintroduit ici ne serait signalé par
    personne — la page fonctionnerait parfaitement au bureau du développeur.

    ## `@assets` PLUTÔT QU'UNE BALISE NUE

    Livewire ré-exécute le contenu d'un composant à chaque navigation
    `wire:navigate`. Une balise `<script src>` nue rechargerait donc Chart.js à
    chaque passage, et redéfinirait `window.Chart` sous les graphiques déjà
    posés. `@assets` garantit un chargement unique par session de page ;
    `@script` fait de même pour le code d'initialisation.

    ## DEUX MOMENTS, ET LE SECOND EST CELUI QU'ON OUBLIE

    Un graphique posé au premier rendu et jamais remis à jour affiche les
    chiffres de la période initiale sous les boutons « 3 mois / 6 mois / 1 an »
    — c'est-à-dire un chiffre faux mais plausible. `Livewire.hook('morphed')`
    redessine après CHAQUE mise à jour du composant.

    ## ET UN TROISIÈME : LA BASCULE D'ONGLET

    Un graphique construit dans un conteneur `display:none` sort à ZÉRO PIXEL —
    c'est le commentaire du maître, et c'est la raison pour laquelle les trois
    panneaux sont montés et seuls leurs conteneurs sont masqués. Chart.js ne
    remesure pas de lui-même quand un ancêtre redevient visible : le
    `window.dispatchEvent(new Event('resize'))` du maître est repris tel quel
    après chaque bascule.

    ## POURQUOI `Number()` ICI, ALORS QUE LES MONTANTS SONT DES CHAÎNES

    Chart.js trace des nombres : la conversion est inévitable, et elle est
    circonscrite au DESSIN. Aucun total, aucune comparaison, aucune décision
    n'en dépend — les montants exacts partent en chaîne dans les exports PDF et
    Excel, et la règle projet (`bccomp()`, jamais une égalité flottante) porte
    sur les calculs, pas sur les pixels d'un axe.
--}}
@assets
<script src="{{ asset('assets/js/vendor/chart.umd.min.js') }}"></script>
@endassets

@script
<script>
(() => {
    'use strict';

    // Les couleurs d'activité du maître (`tableau-de-bord.js` l.31), portées
    // aux codes MODULE que le serveur ventile. Un module inconnu prend le gris
    // ardoise plutôt qu'une couleur au hasard : deux modules de la même
    // couleur se liraient comme une seule activité.
    const COULEURS_MODULE = {
        M1: '#14213D', M4: '#ED6C02', M5: '#B8891E',
        M9: '#2E7D32', M8: '#1D4ED8', M2: '#6B7280', M10: '#C62828',
    };
    const COULEUR_PAR_DEFAUT = '#64748B';

    const graphes = {};

    function lireSocle(id) {
        const socle = document.getElementById(id);

        if (socle === null) { return null; }

        try {
            return JSON.parse(socle.textContent);
        } catch (erreur) {
            // Un JSON illisible n'est pas une série vide : on ne dessine rien
            // plutôt qu'un graphique plat, qui se lirait comme une activité
            // nulle.
            console.warn('[tableau-de-bord] données illisibles (' + id + ') :', erreur.message);
            return null;
        }
    }

    /**
     * Pose ou met à jour un graphique.
     *
     * ⚠ LE CANEVAS PEUT AVOIR ÉTÉ REMPLACÉ (navigation `wire:navigate`).
     * Mettre à jour un graphique attaché à un nœud détaché ne lève AUCUNE
     * erreur et ne dessine nulle part : c'est exactement le défaut
     * « l'indicateur dit que tout va bien pendant que rien n'a lieu ».
     */
    function dessiner(cle, idToile, type, donnees, options) {
        const toile = document.getElementById(idToile);

        if (toile === null || donnees === null || typeof Chart === 'undefined') {
            if (graphes[cle]) { graphes[cle].destroy(); graphes[cle] = null; }
            return;
        }

        if (graphes[cle] && graphes[cle].canvas === toile) {
            graphes[cle].data = donnees;
            graphes[cle].update();
            return;
        }

        if (graphes[cle]) { graphes[cle].destroy(); }

        graphes[cle] = new Chart(toile, { type: type, data: donnees, options: options });
    }

    function couleurs(modules) {
        return modules.map((m) => COULEURS_MODULE[m] || COULEUR_PAR_DEFAUT);
    }

    function tout() {
        if (typeof Chart === 'undefined') { return; }

        Chart.defaults.font.family = 'Inter, sans-serif';
        Chart.defaults.font.size = 11;
        Chart.defaults.color = '#6B7280';

        // ---- Chiffre d'affaires vs Dépenses (maître l.436-447) -------------
        const serie = lireSocle('donnees-graphique-ca');
        dessiner('ca', 'graphique-ca', 'bar',
            (Array.isArray(serie) && serie.length > 0) ? {
                // « juil. / aout / sept. » comme au maitre, jamais « 2026-07 » :
                // la donnee reste la cle ISO, seul l'AFFICHAGE est traduit.
                labels: serie.map((p) => new Date(p.mois + '-01T00:00:00')
                    .toLocaleDateString('fr-FR', { month: 'short', year: '2-digit' })),
                datasets: [
                    {
                        label: @js(__('accueil_pwa.serie.col_ca')),
                        data: serie.map((p) => Number(p.chiffre_affaires_encaisse)),
                        backgroundColor: '#14213D',
                        borderRadius: 5,
                    },
                    {
                        label: @js(__('accueil_pwa.serie.col_depenses')),
                        data: serie.map((p) => Number(p.depenses)),
                        backgroundColor: '#C62828',
                        borderRadius: 5,
                    },
                ],
            } : null,
            {
                responsive: true,
                maintainAspectRatio: false,
                plugins: { legend: { position: 'bottom', labels: { boxWidth: 10 } } },
                scales: { y: { ticks: { callback: (v) => (v / 1000) + 'k' } } },
            });

        // ---- Ventilation par activité : anneau, puis barres horizontales ---
        //
        // UNE SEULE lecture pour DEUX tracés. Le maître recalcule ses
        // compteurs dans chacune de ses deux fonctions ; deux agrégats
        // parallèles finissent par diverger, et c'est le graphique qu'on
        // croirait juste (PA-121).
        const ventilation = lireSocle('donnees-graphique-repartition');
        // Le serveur ventile par code de module (RG-04) ; l'ecran dit le
        // NOM de l'activite — « M1 » ne parle qu'aux developpeurs (rapport
        // de conformite du 01/09/2026). Un code inconnu reste affiche tel
        // quel : le masquer cacherait une activite entiere du graphique.
        // L'element n'existe que si la ventilation a des lignes : sans la
        // garde, un tableau vide casserait TOUT le script de graphiques.
        const elNoms = document.getElementById('noms-activites');
        const NOMS_ACTIVITES = elNoms ? JSON.parse(elNoms.textContent) : {};
        const modules = Array.isArray(ventilation) ? ventilation.map((l) => NOMS_ACTIVITES[l.module] || l.module) : [];
        const montants = Array.isArray(ventilation) ? ventilation.map((l) => Number(l.montant)) : [];

        dessiner('repartition', 'graphique-repartition', 'doughnut',
            modules.length > 0 ? {
                labels: modules,
                datasets: [{ data: montants, backgroundColor: couleurs(modules) }],
            } : null,
            {
                responsive: true,
                maintainAspectRatio: false,
                plugins: { legend: { position: 'bottom', labels: { boxWidth: 10, padding: 10 } } },
            });

        dessiner('ventes', 'graphique-ventes', 'bar',
            modules.length > 0 ? {
                labels: modules,
                datasets: [{
                    label: @js(__('accueil_pwa.activite.col_montant')),
                    data: montants,
                    backgroundColor: couleurs(modules),
                    borderRadius: 6,
                }],
            } : null,
            {
                indexAxis: 'y',
                responsive: true,
                maintainAspectRatio: false,
                plugins: { legend: { display: false } },
            });

        // ---- Marge sur coûts directs par activité (m11-pilotage) -----------
        const marge = lireSocle('donnees-graphique-marge');
        dessiner('marge', 'graphe-centres', 'bar',
            (Array.isArray(marge) && marge.length > 0) ? {
                labels: marge.map((l) => l.libelle),
                datasets: [{
                    label: @js(__('accueil_pwa.marge.titre')),
                    data: marge.map((l) => Number(l.resultat)),
                    // Une marge négative se voit : la peindre de la couleur des
                    // marges positives ferait lire une contribution là où il y
                    // a une perte.
                    backgroundColor: marge.map((l) => Number(l.resultat) < 0 ? '#C62828' : '#14213D'),
                    borderRadius: 5,
                }],
            } : null,
            {
                responsive: true,
                maintainAspectRatio: false,
                plugins: { legend: { display: false } },
            });

        // ---- Créances par ancienneté --------------------------------------
        const creances = lireSocle('donnees-graphique-creances');
        const libellesTranches = @js(__('accueil_pwa.creances.tranches'));
        dessiner('creances', 'graphe-creances', 'bar',
            Array.isArray(creances) ? {
                labels: creances.map((t) => libellesTranches[t.cle] || t.cle),
                datasets: [{
                    label: @js(__('accueil_pwa.creances.titre')),
                    // La teinte s'assombrit avec l'âge, comme au maître : la
                    // tranche « plus de 90 jours » est celle qu'on doit voir en
                    // premier.
                    data: creances.map((t) => Number(t.montant)),
                    backgroundColor: ['#B8891E', '#ED6C02', '#DC2626', '#7F1D1D'],
                    borderRadius: 5,
                }],
            } : null,
            {
                responsive: true,
                maintainAspectRatio: false,
                plugins: { legend: { display: false } },
                scales: { y: { ticks: { callback: (v) => (v / 1000) + 'k' } } },
            });
    }

    // ================================================ BASCULE DES ONGLETS
    //
    // Portage du script en ligne du maître (`tableau-de-bord.html` l.469-484).
    // La classe active et les classes inactives sont EXACTEMENT les siennes.
    // Les classes d'état de `App\Pwa\Support\Onglets` (directive PO du
    // 01/09/2026) — la partie COMMUNE aux deux états n'est pas basculée ici.
    const CLASSES_ACTIVES = ['bg-[var(--navy)]', 'text-white', 'shadow-sm'];
    const CLASSES_INACTIVES = ['bg-white', 'text-slate-500', 'border', 'border-slate-200', 'hover:bg-slate-50'];

    function basculer(onglet, ecrireUrl) {
        const boutons = document.querySelectorAll('[data-onglet-tb]');

        if (boutons.length === 0) { return; }

        boutons.forEach((b) => {
            const actif = b.dataset.ongletTb === onglet;
            CLASSES_ACTIVES.forEach((c) => b.classList.toggle(c, actif));
            CLASSES_INACTIVES.forEach((c) => b.classList.toggle(c, !actif));
        });

        document.querySelectorAll('[data-panneau-tb]').forEach((p) => {
            p.classList.toggle('hidden', p.dataset.panneauTb !== onglet);
        });

        // Le paramètre d'URL reste une ENTRÉE : un lien profond ou un favori
        // ouvre le bon onglet. `replaceState` le tient à jour SANS requête —
        // c'est ce qui distingue cette bascule de l'ancienne, qui repassait
        // par le serveur à chaque clic.
        if (ecrireUrl) {
            const url = new URL(window.location.href);
            url.searchParams.set('panel', onglet);
            window.history.replaceState({}, '', url);
        }

        // Chart.js ne remesure pas quand un ancêtre redevient visible : un
        // graphique monté sous `display:none` reste à zéro pixel jusqu'à ce
        // qu'on le lui dise.
        window.dispatchEvent(new Event('resize'));
    }

    function brancherOnglets() {
        document.querySelectorAll('[data-onglet-tb]').forEach((bouton) => {
            if (bouton.dataset.ongletBranche === '1') { return; }

            bouton.dataset.ongletBranche = '1';
            bouton.addEventListener('click', () => basculer(bouton.dataset.ongletTb, true));
        });
    }

    /** L'onglet ouvert, LU DU DOM — jamais une seconde mémoire côté script. */
    function ongletCourant() {
        const ouvert = Array.from(document.querySelectorAll('[data-panneau-tb]'))
            .find((p) => ! p.classList.contains('hidden'));

        return ouvert ? ouvert.dataset.panneauTb : 'exploitation';
    }

    /**
     * L'onglet courant lu de l'URL, que `basculer` tient a jour par
     * `replaceState`. C'est la SEULE memoire qui survit a un morph : les
     * classes `hidden` des panneaux sont ecrites en dur dans le Blade
     * (exploitation visible, pilotage et croise caches), et Livewire les
     * RESTAURE a chaque aller-retour — relire le DOM apres un morph rendait
     * donc toujours « exploitation ».
     */
    function panneauDepuisUrl() {
        const p = new URL(window.location.href).searchParams.get('panel');

        return (p && document.querySelector('[data-panneau-tb="' + p + '"]')) ? p : null;
    }

    function initialiser(premierPassage) {
        brancherOnglets();

        // Au premier passage, l'onglet vient du serveur (`?panel=`). Apres un
        // morph, il vient de l'URL — JAMAIS du DOM : le morph vient de
        // remettre les classes du Blade, et relire ce DOM renvoyait
        // l'utilisateur sur Exploitation des qu'un controle des onglets
        // Pilotage ou Rapport croise declenchait un aller-retour Livewire
        // (defaut constate par le PO le 02/09/2026 sur le rapport croise).
        basculer(premierPassage ? @js($ongletAffiche) : (panneauDepuisUrl() || ongletCourant()), false);
        tout();
    }

    initialiser(true);
    Livewire.hook('morphed', () => initialiser(false));
})();
</script>
@endscript
