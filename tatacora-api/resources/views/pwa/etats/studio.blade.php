{{--
    États & Rapports — maître : `prototype_v2/pages/m14-etats-studio.html`.

    Barre d'outils `shrink-0 px-5 py-3 border-b border-slate-200 bg-white
    sans-impression` (l.41), puis la ligne `flex-1 overflow-hidden flex
    flex-col lg:flex-row` (l.66) portant l'`<aside>` du catalogue
    `w-full lg:w-[330px] shrink-0 border-r border-slate-200 bg-white flex
    flex-col` (l.69) et la `<section>` d'aperçu (l.80).

    Le catalogue et l'aperçu défilent SÉPARÉMENT — c'est écrit dans le
    `<style>` du maître (l.14-18) : « Un seul défilement ferait perdre la liste
    dès qu'on parcourt un état de 200 lignes ».

    ## Plus aucune section de refus n'est affichée (directive du 31/08/2026)

    L'écran rendait un panneau de cinq lignes « Ce que cet écran ne fait pas,
    et pourquoi », et il le rendait DEUX fois — sous l'accueil et sous
    l'aperçu — pour qu'on le lise avant d'aller chercher un état. Le Product
    Owner l'a retiré : un écran ne catalogue pas ses absences pour
    l'utilisateur. Les dérogations restent motivées dans
    `App\Pwa\Livewire\Etats\EtatsStudio`, sous le jeton `maitre-refuse:`
    que `t-trois-sources.js` relit à chaque exécution.

    ⚠ Rien n'est rendu inerte à la place : « Période », « Exercice »,
    « Imprimer », « Excel » et « PDF » sont ABSENTS, pas grisés (Article 3.3).
--}}
@php
    use App\Pwa\Support\MontantFcfa;
@endphp
<div class="contents">

  @include('pwa.partials.barre-superieure')
  

  <div class="flex flex-1 overflow-hidden">
    @include('pwa.partials.menu-lateral')

    <main class="flex-1 overflow-hidden flex flex-col">

      {{-- ======================= BARRE D'OUTILS (l.41) ====================== --}}
      <div class="shrink-0 px-5 py-3 border-b border-slate-200 bg-white sans-impression">
        <div class="flex flex-wrap items-center gap-2.5">
          <div class="flex items-center gap-2.5 mr-2">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="var(--navy)" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/><path stroke-linecap="round" stroke-linejoin="round" d="M14 2v6h6M9 13h6M9 17h6"/></svg>
            <h1 class="text-[15px] font-bold" style="color:var(--navy)">{{ __('pwa.etats.titre') }}</h1>
          </div>

          <div class="h-5 w-px bg-slate-200"></div>

          {{-- Le maître pose ici « Période », deux champs de date et le bouton
               « Exercice », puis « Imprimer », « Excel » et « PDF ». AUCUN
               n'est rendu, et chacun a sa raison déclarée dans le
               composant. Un champ de
               période ici serait ignoré en silence par les trois états du
               registre ; les trois exports écrivent dans `etats_generes`. --}}
          <div class="flex-1"></div>
        </div>
      </div>

      <div class="flex-1 overflow-hidden flex flex-col lg:flex-row">

        {{-- ======================== CATALOGUE (l.69) ======================== --}}
        <aside class="w-full lg:w-[330px] shrink-0 border-r border-slate-200 bg-white flex flex-col sans-impression">
          <div class="shrink-0 px-3.5 pt-3.5 pb-2.5 border-b border-slate-100">
            <div class="relative mb-2.5">
              <svg class="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="8"/><path d="M21 21l-4.35-4.35"/></svg>
              <input type="search" wire:model.live.debounce.300ms="recherche" placeholder="{{ __('pwa.etats.recherche') }}" autocomplete="off"
                class="w-full text-[13px] border border-slate-300 rounded-lg pl-9 pr-3 py-2 focus:border-[var(--gold)] focus:outline-none">
            </div>
            <div class="flex gap-1.5 flex-wrap" id="filtres-module">
              {{-- Pastille « Tous » d'abord, puis les modules RÉELLEMENT
                   présents au catalogue — comme le maître (l.46, l.54-55), qui
                   ne propose que les modules dont un état existe. --}}
              <button wire:click="$set('module', '')"
                class="filtre-module text-[11px] px-2 py-1 rounded-lg border transition-colors {{ $moduleApplique === '' ? 'bg-[var(--navy)] text-white border-[var(--navy)]' : 'bg-white text-slate-500 border-slate-200 hover:border-slate-400' }}">{{ __('pwa.etats.tous') }}</button>
              @foreach ($modules as $moduleOption)
                <button wire:click="$set('module', '{{ $moduleOption }}')"
                  class="filtre-module text-[11px] px-2 py-1 rounded-lg border transition-colors {{ $moduleApplique === $moduleOption ? 'bg-[var(--navy)] text-white border-[var(--navy)]' : 'bg-white text-slate-500 border-slate-200 hover:border-slate-400' }}">{{ $moduleOption }}</button>
              @endforeach
            </div>
          </div>

          <div id="catalogue" class="flex-1 overflow-y-auto">
            @if ($liste === [])
              <p class="px-4 py-12 text-center text-[13px] text-slate-400">{{ __('pwa.etats.aucun') }}</p>
            @else
              @php($parModule = collect($liste)->groupBy('module'))
              @foreach ($parModule as $codeModule => $etatsDuModule)
                <p class="px-3.5 pt-3 pb-1 text-[10px] font-bold tracking-wider text-slate-400">{{ $codeModule }}</p>
                @foreach ($etatsDuModule as $entree)
                  {{-- `aria-selected` porte l'état sélectionné, comme au maître
                       (l.77) : c'est lui que son `<style>` habille en navy. --}}
                  <button wire:click="$set('etat', '{{ $entree['code'] }}')" role="option"
                    aria-selected="{{ $selection === $entree['code'] ? 'true' : 'false' }}"
                    wire:key="etat-{{ $entree['code'] }}"
                    class="item-etat w-full text-left px-3.5 py-2.5 border-l-2 border-transparent {{ $selection === $entree['code'] ? 'bg-[var(--navy)] text-white' : 'hover:bg-slate-100' }}">
                    <div class="flex items-start justify-between gap-2">
                      <span class="text-[13px] font-semibold leading-snug">{{ $entree['libelle'] }}</span>
                      <span class="item-module text-[9px] px-1.5 py-0.5 rounded shrink-0 mt-0.5 {{ $selection === $entree['code'] ? 'bg-white/15 text-white' : 'bg-slate-100 text-slate-500' }}">{{ $entree['module'] }}</span>
                    </div>
                    {{-- Le maître affiche ici une description et un décompte de
                         lignes. Le catalogue serveur ne porte pas de
                         description, et le décompte exigerait de calculer tous
                         les états à chaque frappe. Refus déclaré dans
                         `EtatsStudio`, jamais écrit à l'écran. --}}
                  </button>
                @endforeach
              @endforeach
            @endif
          </div>

          <div class="shrink-0 px-3.5 py-2 border-t border-slate-100">
            <p id="compteur-catalogue" class="text-[11px] text-slate-400">{{ __('pwa.etats.compteur', ['nombre' => count($liste)]) }}</p>
          </div>
        </aside>

        {{-- ========================= APERÇU (l.80) ========================== --}}
        <section class="flex-1 overflow-hidden flex flex-col">
          @if ($resultat === null)
            {{-- L'écran d'accueil du maître (l.116-133). --}}
            <div id="entete-apercu" class="shrink-0"></div>
            <div id="zone-apercu" class="flex-1 overflow-auto">
              <div class="h-full flex items-center justify-center p-8">
                <div class="max-w-lg text-center">
                  <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="#CBD5E1" stroke-width="1.5" class="mx-auto mb-4"><path stroke-linecap="round" stroke-linejoin="round" d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/><path stroke-linecap="round" stroke-linejoin="round" d="M14 2v6h6M9 13h6M9 17h6"/></svg>
                  <p class="text-[15px] font-semibold" style="color:var(--navy)">{{ __('pwa.etats.accueil_titre') }}</p>
                  <p class="text-[13px] text-slate-500 mt-2">{{ __('pwa.etats.accueil_detail', ['total' => $totalAccessibles]) }}</p>
                </div>
              </div>
            </div>
          @else
            {{-- En-tête d'aperçu du maître (l.181-205) : titre, période, module
                 source, décompte de lignes, puis les KPI en pastilles. --}}
            <div id="entete-apercu" class="shrink-0">
              <div class="px-5 py-3.5 border-b border-slate-200 bg-white">
                <div class="flex flex-wrap items-start justify-between gap-3">
                  <div>
                    <h2 class="text-[15px] font-bold" style="color:var(--navy)">{{ $titreEtat }}</h2>
                    <p class="text-[12px] text-slate-500 mt-0.5">
                      {{ $periodeEtat }}
                      <span class="text-slate-300">·</span> {{ __('pwa.etats.module_source', ['module' => $moduleSource]) }}
                      <span class="text-slate-300">·</span> {{ __('pwa.etats.lignes', ['nombre' => $resultat->nombreLignes()]) }}
                    </p>
                  </div>
                  {{-- État « Locations » seulement : la case décochée par
                       défaut. Un contrat annulé coché n'est JAMAIS compté
                       (voir `EtatLocations`). Propriété, pas action. --}}
                  @if ($offreCaseAnnules)
                    <label class="flex items-center gap-2 text-[12px] text-slate-600 cursor-pointer sans-impression">
                      <input type="checkbox" wire:model.live="inclureAnnules" class="rounded border-slate-300">
                      {{ __('pwa.etats.inclure_annules') }}
                    </label>
                  @endif
                </div>
                @if ($resultat->kpis !== [])
                  <div class="flex flex-wrap gap-2 mt-3">
                    @foreach ($resultat->kpis as $libelle => $valeur)
                      <div class="px-3 py-1.5 rounded-lg bg-slate-50 border border-slate-200">
                        <div class="text-[10px] uppercase tracking-wide text-slate-400 font-semibold">{{ $libelle }}</div>
                        <div class="text-[13px] font-bold" style="color:var(--navy)">{{ $valeur }}</div>
                      </div>
                    @endforeach
                  </div>
                @endif
              </div>
            </div>

            {{-- EXCLU de la barre de recherche par table (PO, 01/09/2026) :
                 les indicateurs affichés au-dessus (`$resultat->kpis`) sont
                 calculés par `EtatInterface::calculer()` sur la TOTALITÉ des
                 lignes de l'état généré — même famille de refus que
                 `App\Pwa\Livewire\Comptabilite\Balance` : un filtre texte
                 masquerait des lignes sans recalculer ces indicateurs. Le
                 module (sélecteur ci-dessus) et la période restent le filtre
                 pertinent, appliqués AVANT génération, pas après. --}}
            <div id="zone-apercu" class="flex-1 overflow-auto">
              @if ($resultat->estVide())
                <p class="p-10 text-center text-[13px] text-slate-400">{{ __('pwa.etats.aucune_ligne') }}</p>
              @else
                <table class="w-full text-[12.5px] apercu">
                  <thead class="bg-[var(--navy)]">
                    <tr>
                      @foreach ($resultat->entetes as $entete)
                        {{-- ÉCART DÉLIBÉRÉ — `m14-etats-studio.js` l.214
                             Le maître : les colonnes de `colonnesNumeriques`
                             sont alignées à droite.
                             Ici : toutes les colonnes sont à gauche.
                             Raison : `EtatResultat` ne porte AUCUNE indication
                             de colonne numérique — ses quatre champs sont
                             `kpis`, `entetes`, `lignes` et `filtresAppliques`.
                             Deviner d'après le contenu ferait aligner à droite
                             une référence de pièce faite de chiffres, et
                             changerait l'alignement d'une colonne d'un état à
                             l'autre selon les données du jour. --}}
                        <th class="px-3 py-2.5 text-left text-[11px] uppercase tracking-wide text-white/90 font-semibold">{{ $entete }}</th>
                      @endforeach
                    </tr>
                  </thead>
                  <tbody>
                    @foreach ($resultat->lignes as $index => $ligne)
                      <tr class="{{ $index % 2 ? 'bg-slate-50/40' : '' }} hover:bg-amber-50/40" wire:key="ligne-{{ $index }}">
                        @foreach ($ligne as $cellule)
                          <td class="px-3 py-1.5 border-b border-slate-50">{{ $cellule !== '' ? $cellule : MontantFcfa::TIRET }}</td>
                        @endforeach
                      </tr>
                    @endforeach
                  </tbody>
                </table>
              @endif
            </div>
          @endif
        </section>
      </div>
    </main>
  </div>

</div>
