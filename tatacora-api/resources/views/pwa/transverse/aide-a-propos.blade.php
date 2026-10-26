<div class="contents">

  @include('pwa.partials.barre-superieure')
  

  <div class="flex flex-1 overflow-hidden">
    @include('pwa.partials.menu-lateral')
    <main class="flex-1 overflow-y-auto">
      <div class="max-w-[1200px] mx-auto p-5 lg:p-8">

        <div class="mb-6">
          <div class="flex items-center gap-2.5">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--navy)" stroke-width="2"><circle cx="12" cy="12" r="10"/><path stroke-linecap="round" stroke-linejoin="round" d="M9.09 9a3 3 0 015.83 1c0 2-3 3-3 3M12 17h.01"/></svg>
            <h1 class="text-lg lg:text-xl font-bold" style="color:var(--navy)">{{ __('pwa.aide.titre') }}</h1>
          </div>
          <p class="text-[15px] text-slate-500 mt-1.5">{{ __('pwa.aide.sous_titre') }}</p>
        </div>

        {{-- ===================== Présentation du logiciel ===================== --}}
        <section class="rounded-xl overflow-hidden mb-6" style="background:var(--navy)">
          <div class="p-6 lg:p-8 grid grid-cols-1 lg:grid-cols-3 gap-6 items-center">
            <div class="lg:col-span-2">
              <div class="flex items-center gap-3 mb-3">
                {{-- Logo PNG paysage (decision du PO du 14/10/2026, D392) : cadre
                     garde, `object-contain` au lieu d'`object-cover` (qui rognait). PA-210. --}}
                <img src="{{ asset('assets/img/logo.png') }}" alt="{{ __('pwa.alt_logo') }}" class="w-12 h-12 rounded-lg object-contain ring-2 ring-[var(--gold)]">
                <div>
                  <h2 class="text-white text-base font-bold">{{ __('pwa.marque') }}</h2>
                  <p class="text-[13px]" style="color:var(--gold)">{{ __('pwa.aide.enseigne') }}</p>
                </div>
              </div>
              <p class="text-white/70 text-[15px] leading-relaxed">{{ __('pwa.aide.presentation_1') }}</p>
              <p class="text-white/70 text-[15px] leading-relaxed mt-2.5">{{ __('pwa.aide.presentation_2_avant') }}<strong class="text-white">{{ __('pwa.aide.presentation_2_fort') }}</strong>{{ __('pwa.aide.presentation_2_apres') }}</p>
            </div>
            <div class="space-y-2.5">
              <div class="rounded-lg px-4 py-3" style="background:rgba(255,255,255,.07)">
                <p class="text-[12px] text-white/50">{{ __('pwa.aide.moe_titre') }}</p>
                <p class="text-white text-sm font-bold">{{ __('pwa.aide.moe_valeur') }}</p>
              </div>
              <div class="rounded-lg px-4 py-3" style="background:rgba(255,255,255,.07)">
                <p class="text-[12px] text-white/50">{{ __('pwa.aide.po_titre') }}</p>
                <p class="text-white text-sm font-bold">{{ __('pwa.aide.po_valeur') }}</p>
              </div>
              <div class="rounded-lg px-4 py-3" style="background:rgba(255,255,255,.07)">
                <p class="text-[12px] text-white/50">{{ __('pwa.aide.referentiel_titre') }}</p>
                <p class="text-white text-sm font-bold">{{ __('pwa.aide.referentiel_valeur') }}</p>
              </div>
            </div>
          </div>
        </section>

        {{-- ========================= Modules du logiciel ====================== --}}
        <section class="mb-8">
          <div class="flex items-end justify-between mb-3.5">
            <div>
              <h2 class="text-base font-bold" style="color:var(--navy)">{{ __('pwa.aide.modules_titre') }}</h2>
              <p class="text-[13px] text-slate-500 mt-0.5">{{ __('pwa.aide.modules_sous_titre') }}</p>
            </div>
            <span id="compteur-modules-accessibles" class="text-[13px] text-slate-400 shrink-0">{{ __('pwa.aide.modules_compteur', ['accessibles' => $accessibles, 'total' => count($cartes)]) }}</span>
          </div>
          <div id="grille-modules" class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-3.5">
            @foreach ($cartes as $carte)
              @php($ouvert = $carte['niveau'] !== '-')
              {{--
                  Le maître rend un `<a>` quand le module est ouvert, un `<div
                  cursor-not-allowed>` sinon (l.283-285). La PWA ajoute une
                  troisième branche, et elle est visible : un module ouvert dont
                  la consultation web n'existe pas encore reste un `<span>`
                  inerte portant sa raison (Article 3.3 — au backlog, pas un
                  état final). Les classes ne changent dans aucune branche.
              --}}
              @if ($ouvert && $carte['url'] !== null)
                <a href="{{ $carte['url'] }}" wire:navigate class="carte-hover bg-white rounded-xl border border-slate-200 p-4 block">
                  @include('pwa.transverse.partials.carte-module', ['carte' => $carte, 'ouvert' => true])
                </a>
              @elseif ($ouvert)
                <span aria-disabled="true" title="{{ __('pwa.aide.module_ecran_a_venir') }}" class="carte-hover bg-white rounded-xl border border-slate-200 p-4 block">
                  @include('pwa.transverse.partials.carte-module', ['carte' => $carte, 'ouvert' => true])
                </span>
              @else
                <div class="bg-white/60 rounded-xl border border-slate-100 p-4 cursor-not-allowed" title="{{ __('pwa.aide.sans_acces_titre') }}">
                  @include('pwa.transverse.partials.carte-module', ['carte' => $carte, 'ouvert' => false])
                </div>
              @endif
            @endforeach
          </div>
          <p class="text-[12px] text-slate-400 mt-3">{{ __('pwa.aide.modules_note') }}</p>
        </section>

        {{-- ============================ Foire aux questions =================== --}}
        <section class="mb-8">
          <div class="flex flex-col sm:flex-row sm:items-end sm:justify-between gap-3 mb-3.5">
            <div>
              <h2 class="text-base font-bold" style="color:var(--navy)">{{ __('pwa.aide.faq_titre') }}</h2>
              <p class="text-[13px] text-slate-500 mt-0.5">{{ __('pwa.aide.faq_sous_titre') }}</p>
            </div>
            <div class="relative sm:w-72 shrink-0">
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="#9CA3AF" stroke-width="2" class="absolute left-3 top-1/2 -translate-y-1/2"><circle cx="11" cy="11" r="8"/><path stroke-linecap="round" d="M21 21l-4.35-4.35"/></svg>
              {{--
                  Filtre en PROPRIÉTÉ Livewire (`wire:model.live`), jamais une
                  méthode : une méthode publique sur un composant PWA serait une
                  action, et l'action Livewire est le seul chemin par lequel
                  cette interface pourrait écrire (PA-67).
              --}}
              <input id="recherche-faq" type="text" wire:model.live.debounce.300ms="recherche" placeholder="{{ __('pwa.aide.faq_recherche') }}"
                     class="champ w-full border border-slate-200 rounded-lg pl-9 pr-3 py-2.5 text-[15px] bg-white">
            </div>
          </div>

          <div id="zone-faq" class="space-y-2.5">
            @foreach ($faq as $categorie => $entrees)
              <div>
                <p class="text-[12px] font-bold tracking-wider text-slate-400 mt-4 mb-1.5">{{ mb_strtoupper($categorie) }}</p>
                @foreach ($entrees as $entree)
                  <details class="bg-white rounded-xl border border-slate-200 overflow-hidden mb-2" @if ($recherche !== '') open @endif>
                    <summary class="w-full flex items-center gap-3 px-4 py-3.5 text-left hover:bg-slate-50 cursor-pointer list-none">
                      <span class="flex-1 text-[15px] font-semibold text-slate-700">{{ $entree['question'] }}</span>
                      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#9CA3AF" stroke-width="2.2" class="shrink-0 transition-transform">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M6 9l6 6 6-6"/>
                      </svg>
                    </summary>
                    <div class="px-4 pb-4 pt-0">
                      <p class="text-[15px] text-slate-600 leading-relaxed border-t border-slate-100 pt-3">{{ $entree['reponse'] }}</p>
                    </div>
                  </details>
                @endforeach
              </div>
            @endforeach
          </div>
          @if ($faq === [])
            <p id="faq-vide" class="text-center text-[15px] text-slate-400 py-10">{{ __('pwa.aide.faq_vide') }}</p>
          @endif
        </section>

        {{-- ============================== Ressources ========================== --}}
        <section class="mb-8">
          <h2 class="text-base font-bold mb-3.5" style="color:var(--navy)">{{ __('pwa.aide.ressources_titre') }}</h2>
          <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3.5">
            {{-- « Modèles d'import » : refusé et nommé — l'import est une écriture. --}}
            <span aria-disabled="true" title="{{ __('pwa.coquille.hors_perimetre') }}" class="carte-hover bg-white rounded-xl border border-slate-200 p-4 block">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="var(--gold)" stroke-width="2" class="mb-2"><path stroke-linecap="round" stroke-linejoin="round" d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4M7 10l5 5 5-5M12 15V3"/></svg>
              <p class="text-[15px] font-bold text-slate-700">{{ __('pwa.aide.modeles_import_titre') }}</p>
              <p class="text-[13px] text-slate-500 mt-0.5">{{ __('pwa.aide.modeles_import_detail') }}</p>
            </span>
            <a href="{{ route('pwa.journal-audit') }}" wire:navigate class="carte-hover bg-white rounded-xl border border-slate-200 p-4 block">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="var(--gold)" stroke-width="2" class="mb-2"><path stroke-linecap="round" stroke-linejoin="round" d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/><path stroke-linecap="round" stroke-linejoin="round" d="M14 2v6h6"/></svg>
              <p class="text-[15px] font-bold text-slate-700">{{ __('pwa.aide.journal_audit_titre') }}</p>
              <p class="text-[13px] text-slate-500 mt-0.5">{{ __('pwa.aide.journal_audit_detail') }}</p>
            </a>
            <a href="{{ route('pwa.roles-permissions') }}" wire:navigate class="carte-hover bg-white rounded-xl border border-slate-200 p-4 block">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="var(--gold)" stroke-width="2" class="mb-2"><path stroke-linecap="round" stroke-linejoin="round" d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg>
              <p class="text-[15px] font-bold text-slate-700">{{ __('pwa.aide.roles_titre') }}</p>
              <p class="text-[13px] text-slate-500 mt-0.5">{{ __('pwa.aide.roles_detail') }}</p>
            </a>
            {{--
                « Revoir mes alertes » : le maître pose ici un `<button>` qui
                rejoue les alertes du jour. Il n'est PAS rendu, et rien ne le
                dit à l'écran — le refus est déclaré dans `AideAPropos`, sous
                le jeton que `t-trois-sources.js` relit (directive du
                31/08/2026). Ni bouton inerte, ni ligne d'explication.
            --}}
          </div>
        </section>

        {{-- ============================ Bandeau de contact ==================== --}}
        <section class="bg-white rounded-xl border border-slate-200 p-6 flex flex-col sm:flex-row sm:items-center gap-4">
          <div class="w-12 h-12 rounded-full flex items-center justify-center shrink-0" style="background:#FDF3E0">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--gold)" stroke-width="2">
              <path stroke-linecap="round" stroke-linejoin="round" d="M4 14v-3a8 8 0 0116 0v3"/>
              <path stroke-linecap="round" stroke-linejoin="round" d="M4 14a2 2 0 002 2h1v-5H6a2 2 0 00-2 2zM20 14a2 2 0 01-2 2h-1v-5h1a2 2 0 012 2z"/>
              <path stroke-linecap="round" stroke-linejoin="round" d="M18 16v1a3 3 0 01-3 3h-3"/>
            </svg>
          </div>
          <div class="min-w-0">
            <p class="text-sm font-bold" style="color:var(--navy)">{{ __('pwa.aide.contact_titre') }}</p>
            <p class="text-[15px] text-slate-500 mt-0.5">{{ __('pwa.aide.contact_detail') }}</p>
          </div>
          <a href="{{ route('pwa.contact-editeur') }}" wire:navigate class="btn sm:ml-auto shrink-0 flex items-center justify-center gap-2 px-5 py-2.5 rounded-lg text-white text-sm font-semibold" style="background:var(--navy)">
            <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M4 4h16a2 2 0 012 2v12a2 2 0 01-2 2H4a2 2 0 01-2-2V6a2 2 0 012-2z"/><path stroke-linecap="round" stroke-linejoin="round" d="M22 6l-10 7L2 6"/></svg>
            {{ __('pwa.aide.contact_bouton') }}
          </a>
        </section>

      </div>
    </main>
  </div>

</div>
