{{--
    Onglet « Plan comptable » du hub — maître :
    `prototype_v2/pages/m10-syscohada.js` `vuePlan()` l.343-375.

    Un tableau PAR CLASSE, titré « Classe N — <libellé> » (l.371). Six colonnes
    du maître (l.354) : « Compte », « Intitulé », « Type », « Centre requis »,
    « Mouvementé », « Solde ». L'encadré ambre (l.373) est repris mot pour mot :
    il porte l'avertissement le plus important de l'écran — les numéros doivent
    être confrontés à l'AUDCIF officiel, « un numéro faux produit une liasse
    rejetée, et la balance s'équilibre quand même ».

    ## Trois colonnes du maître sont REFUSÉES — Article 8

    ÉCART DÉLIBÉRÉ — `m10-syscohada.js` l.354, colonnes « Centre requis »,
    « Mouvementé » et « Solde »
    Le maître : « oui (RG-12) » si le compte exige un centre analytique ; « oui »
    s'il est mouvementé ; son solde signé.
    Ici : ces trois colonnes ne sont pas rendues.
    Raison, colonne par colonne :
      — « Centre requis » : `plan_comptable` n'a AUCUNE colonne
        `analytique_requis`. RG-12 vit dans le schéma sous une autre forme —
        `ecritures_comptables.centre_id` est NOT NULL pour TOUTES les lignes, pas
        seulement les classes 6/7/8. Répondre « oui » aux seules classes 6, 7 et
        8 réécrirait la règle ici, ce que `LARAVEL_PWA.md` §3 interdit, et
        répondre « oui » partout ferait une colonne constante.
      — « Mouvementé » et « Solde » : ils exigent une balance, donc un
        EXERCICE, que cet onglet ne demande pas — `PlanComptableService::
        consulter()` ne prend qu'une classe. Les afficher pour l'exercice
        courant présenterait le référentiel entier sous les soldes d'une seule
        année sans le dire ; ils se lisent sur l'onglet Balance, qui porte
        l'exercice dans son titre.
    Refus déclaré : maitre-refuse:m10-syscohada.html#plan

    ~~ÉCART DÉLIBÉRÉ — bouton « + Créer un compte » ABSENT (« PWA en lecture
    seule stricte »)~~ PORTÉ le 01/09/2026 (Vague E) : le motif était déjà
    caduc au 28/08/2026 (PA-159 lève la lecture seule), et
    `PlanComptableService::creerCompte()` n'existait simplement pas encore —
    voir son propre docblock pour la levée datée du refus. Le bouton appelle
    `Hub::ouvrirNouveauCompte()` / `enregistrerCompte()`, modale rendue dans
    `pwa.comptabilite.hub` derrière `@if($etatFormulaire === 'compte')`
    (doctrine `RefuseLaSaisie`).

    La colonne « Type » du maître porte, elle, `plan_comptable.nature`, qui
    existe bien — et qui est NULLABLE : « — » quand elle manque (Article 7).
--}}
@php
    // Les colonnes de l'onglet, écrites UNE fois (voir `_entetes`) — le même
    // entête se répète sur chaque tableau de classe.
    $colonnesEntete = [
        ['Compte', 'left'],
        ['Intitulé', 'left'],
        ['Type', 'right'],
    ];
@endphp
@if ($squelette ?? false)
  @include('pwa.comptabilite.onglets._squelette_tableau', ['colonnes' => $colonnesEntete, 'message' => $messageSquelette])
@else
@php
    $classesLibelle = [
        '1' => 'Capitaux', '2' => 'Immobilisations', '3' => 'Stocks', '4' => 'Tiers',
        '5' => 'Trésorerie', '6' => 'Charges', '7' => 'Produits',
        '8' => 'Hors activités ordinaires', '9' => 'Analytique',
    ];
    $parClasse = $plan->comptes->groupBy('classe');
@endphp
{{-- Recherche par table (décision du Product Owner, 01/09/2026) — numéro de
     compte ou libellé, filtrage SERVEUR réel. Sûre ici (voir le docblock de
     `App\Pwa\Livewire\Comptabilite\Hub::$planRecherche`), à la différence des
     autres onglets du hub. --}}
<div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 mb-3">
  <div class="relative flex-1 max-w-md">
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#9CA3AF" stroke-width="2" class="absolute left-3.5 top-1/2 -translate-y-1/2"><circle cx="11" cy="11" r="8"/><path stroke-linecap="round" d="M21 21l-4.35-4.35"/></svg>
    <input type="search" wire:model.live.debounce.300ms="planRecherche"
           placeholder="{{ __('comptabilite_pwa.plan_recherche') }}"
           class="champ w-full border border-slate-200 rounded-lg pl-10 pr-4 py-2.5 text-sm bg-white">
  </div>

  {{-- « + Créer un compte » (maître l.396) — porté le 01/09/2026. --}}
  <button type="button" wire:click="ouvrirNouveauCompte"
          class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold hover:opacity-90 shrink-0">
    + {{ __('comptabilite_pwa.creer_compte') }}
  </button>
</div>

@forelse ($parClasse as $classe => $comptes)
  <div class="bg-white rounded-xl border border-slate-200 overflow-hidden mb-3">
    <div class="px-4 py-3 border-b border-slate-200 flex items-center justify-between">
      <h3 class="text-[14px] font-bold" style="color:var(--navy)">Classe {{ $classe }} — {{ $classesLibelle[$classe] ?? '' }}</h3>
    </div>
    <div class="overflow-x-auto">
      <table class="w-full text-[13px] compta" style="white-space: nowrap">
        @include('pwa.comptabilite.onglets._entetes', ['colonnes' => $colonnesEntete])
        <tbody>
          @foreach ($comptes as $compte)
            <tr class="border-t border-slate-100 hover:bg-slate-50">
              <td class="px-3 py-2 font-mono font-semibold" style="color:var(--navy)">{{ $compte->numero_compte }}</td>
              <td class="px-3 py-2 text-left text-slate-700">{{ $compte->libelle }}</td>
              <td class="px-3 py-2 text-right text-[12px] text-slate-500">{{ $compte->nature ?? '—' }}</td>
            </tr>
          @endforeach
        </tbody>
      </table>
    </div>
  </div>
@empty
  <div class="bg-white rounded-xl border border-slate-200 py-14 text-center text-slate-400 text-[13px]">Aucun compte ne correspond.</div>
@endforelse

{{--
    ⚠ AUCUN encadré « classes hors écran » ici, contrairement à la page
    autonome `pwa/comptabilite/plan-comptable.blade.php`, et la différence est
    voulue : cet onglet n'applique AUCUN filtre de classe, donc les classes 8
    et 9 apparaissent dans la boucle ci-dessus comme les autres. Y afficher
    « ces comptes ne sont pas atteignables » serait faux — exactement le motif
    périmé que PA-144 traque, cinq fois rencontré dans ce dépôt.
--}}
@endif
