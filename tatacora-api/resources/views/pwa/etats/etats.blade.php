{{--
    États, Rapports & Exports — maître : `prototype_v2/pages/m14-etats.html`.

    Bandeau « Écran remplacé » (l.15-21), conteneur
    `max-w-[1440px] mx-auto p-5 lg:p-8` (l.25), en-tête
    `flex flex-col lg:flex-row lg:items-center gap-3 mb-6` (l.27), grille des
    états `grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4 mb-8` (l.44),
    puis la carte « Historique des éditions » (l.46-63).

    ## Plus aucune section de refus n'est affichée (directive du 31/08/2026)

    Cet écran portait, sous son en-tête, un panneau « Ce que cet écran ne fait
    pas, et pourquoi » de cinq lignes. Le Product Owner l'a retiré : un écran
    ne catalogue pas ses absences pour l'utilisateur. Les dérogations restent
    motivées dans `App\Pwa\Livewire\Etats\Etats`, sous le jeton
    `maitre-refuse:` que `t-trois-sources.js` relit à chaque exécution — la
    déclaration a changé d'endroit, elle n'a pas disparu.

    ⚠ Retirer l'explication n'autorise pas à simuler la fonction : « Du »,
    « Au », « Actualiser », « Générer » et « Retélécharger » ne sont pas rendus
    du tout, et surtout pas rendus inertes (Article 3.3).
--}}
@php
    use App\Pwa\Support\MontantFcfa;
    use App\Pwa\Livewire\Etats\Etats;
@endphp
<div class="contents">

  @include('pwa.partials.barre-superieure')
  

  <div class="flex flex-1 overflow-hidden">
    @include('pwa.partials.menu-lateral')
    <main class="flex-1 overflow-y-auto">
      <div class="max-w-[1440px] mx-auto p-5 lg:p-8">

        <div class="flex flex-col lg:flex-row lg:items-center gap-3 mb-6">
          <div>
            <div class="flex items-center gap-2.5">
              <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--navy)" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/><path stroke-linecap="round" stroke-linejoin="round" d="M14 2v6h6M9 13h6M9 17h6M9 9h1"/></svg>
              <h1 class="text-lg lg:text-xl font-bold" style="color:var(--navy)">{{ __('pwa.etats_legacy.titre') }}</h1>
            </div>
            <p class="text-[15px] text-slate-500 mt-1.5">{{ __('pwa.etats_legacy.sous_titre') }}</p>
          </div>
          {{-- Le maître pose ici « Du », « Au » et « Actualiser ». Aucun n'est
               rendu — ni offert, ni expliqué à l'écran : le refus est déclaré
               dans `Etats`. Aucun contrôle inerte. --}}
        </div>

        {{-- ==================== GRILLE DES ÉTATS (l.44) ===================== --}}
        @if ($catalogue === [])
          <div class="bg-white rounded-xl border border-slate-200 py-14 px-6 text-center mb-8">
            <p class="text-[13px] font-semibold text-slate-500">{{ __('pwa.etats_legacy.catalogue_vide_titre') }}</p>
            <p class="text-[12px] text-slate-400 mt-1.5 max-w-2xl mx-auto">{{ __('pwa.etats_legacy.catalogue_vide_detail') }}</p>
          </div>
        @else
          <div class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4 mb-8" id="grille-etats">
            @foreach ($catalogue as $entree)
              <div class="bg-white rounded-xl border border-slate-200 p-5 carte-hover flex flex-col" wire:key="carte-{{ $entree['code'] }}">
                <span class="text-[12px] font-bold text-[var(--gold)] mb-1.5">{{ __('pwa.etats_legacy.module', ['module' => $entree['module']]) }}</span>
                <h3 class="font-bold text-sm text-slate-800 mb-1.5">{{ $entree['libelle'] }}</h3>
                {{-- Le maître affiche ici une description par état. Le catalogue
                     serveur n'en porte aucune : en inventer une serait écrire
                     ce que fait un état sans l'avoir lu. --}}
                <p class="text-[15px] text-slate-500 flex-1 leading-relaxed">{{ MontantFcfa::TIRET }}</p>
                {{-- Le maître pose ici le bouton « Générer », qui ouvre la
                     modale. Il n'est pas rendu — générer ÉCRIT dans
                     `etats_generes`. Un lien vers l'aperçu le remplacerait
                     mal : ce n'est pas la même fonction, et l'annoncer comme
                     telle serait pire qu'une absence. Refus déclaré dans `Etats`. --}}
              </div>
            @endforeach
          </div>
        @endif

        {{-- ================ HISTORIQUE DES ÉDITIONS (l.46-63) ===============
             La ligne d'en-tête de cette carte est RESTRUCTURÉE le 01/09/2026
             (recherche + filtre par table, décision du Product Owner) : elle
             passe d'une seule ligne à deux rangées empilables sur mobile.
             Trois jetons pour la garde de structure (`t-structure.js`, qui ne
             compare que la mise en page, jamais les libellés) :
               structure-ajout:m14-etats.html#div-3dd2be62
               structure-refuse:m14-etats.html#div-2c658867 (le bloc « Du/Au/
                 Actualiser » du maître — déjà refusé et motivé plus haut dans
                 ce fichier, jeton dédié pour cette garde-ci)
               structure-ajout:m14-etats.html#div-4c1a6291 --}}
        <div class="bg-white rounded-xl border border-slate-200 overflow-hidden">
          <div class="px-5 py-4 border-b border-slate-100 flex flex-col lg:flex-row lg:items-center lg:justify-between gap-3">
            <div class="flex items-center gap-3">
              <h2 class="text-sm font-bold text-slate-700">{{ __('pwa.etats_legacy.historique_titre') }}</h2>
              <span class="text-[13px] text-slate-400">{{ __('pwa.etats_legacy.historique_mention') }}</span>
            </div>
            {{-- Recherche + filtre par table (décision du Product Owner,
                 01/09/2026) — pas le refus « Du/Au/Actualiser » du docblock
                 de tête, qui vise une plage de dates calquée sur le maître :
                 voir `App\Pwa\Livewire\Etats\Etats::$recherche`. --}}
            <div class="flex flex-col sm:flex-row gap-2">
              <div class="relative">
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#9CA3AF" stroke-width="2" class="absolute left-3 top-1/2 -translate-y-1/2"><circle cx="11" cy="11" r="8"/><path stroke-linecap="round" d="M21 21l-4.35-4.35"/></svg>
                <input type="search" wire:model.live.debounce.300ms="recherche"
                       placeholder="{{ __('pwa.etats_legacy.historique_recherche') }}"
                       class="champ border border-slate-200 rounded-lg pl-9 pr-3 py-2 text-[13px] bg-white w-full sm:w-56">
              </div>
              <select wire:model.live="moduleFiltre" class="champ border border-slate-200 rounded-lg px-3 py-2 text-[13px] bg-white">
                <option value="">{{ __('pwa.etats_legacy.historique_tous_modules') }}</option>
                @foreach ($modulesHistorique as $unModule)
                  <option value="{{ $unModule }}">{{ $unModule }}</option>
                @endforeach
              </select>
            </div>
          </div>
          <table class="w-full text-sm">
            <thead class="bg-[var(--navy)]">
              <tr class="text-left text-[11px] font-semibold text-white/90 uppercase tracking-wide">
                <th class="px-5 py-2.5">{{ __('pwa.etats_legacy.col_etat') }}</th>
                <th class="px-5 py-2.5">{{ __('pwa.etats_legacy.col_module') }}</th>
                <th class="px-5 py-2.5">{{ __('pwa.etats_legacy.col_emetteur') }}</th>
                <th class="px-5 py-2.5">{{ __('pwa.etats_legacy.col_date') }}</th>
                <th class="px-5 py-2.5">{{ __('pwa.etats_legacy.col_format') }}</th>
                <th class="px-5 py-2.5 text-right">{{ __('pwa.etats_legacy.col_actions') }}</th>
              </tr>
            </thead>
            <tbody id="corps-historique" class="divide-y divide-slate-100">
              @forelse ($editions as $edition)
                <tr class="hover:bg-slate-50" wire:key="edition-{{ $edition->id }}">
                  <td class="px-5 py-3 font-medium text-slate-700">{{ $edition->nom_etat }}</td>
                  <td class="px-5 py-3"><span class="text-[13px] font-mono-tatacora bg-slate-100 px-2 py-0.5 rounded">{{ $edition->module }}</span></td>
                  {{-- AUCUN repli « — » ici, et c'est mesuré :
                       `etats_generes.utilisateur_id` est `constrained()` SANS
                       `nullable()` (`2026_08_01_001300_create_etats.php` l.20),
                       et `GenerateurEtatService::verifierAcces()` l.113 refuse
                       un auteur nul avant toute écriture. Une édition sans
                       émetteur ne peut pas exister ; un repli serait du code
                       que rien n'exerce (même défaut que PA-150). --}}
                  <td class="px-5 py-3 text-slate-500">{{ $edition->utilisateur->login }}</td>
                  <td class="px-5 py-3 text-slate-500">{{ $edition->date_edition->format('d/m/Y H:i') }}</td>
                  <td class="px-5 py-3 text-slate-500">{{ strtoupper($edition->format) }}</td>
                  {{-- L'action « Retélécharger » du maître n'est pas rendue :
                       `chemin_fichier_archive` vaut TOUJOURS `null` (PA-48), il
                       n'y a aucun fichier à retélécharger. Refus déclaré dans `Etats`. --}}
                  <td class="px-5 py-3 text-right text-slate-300">{{ MontantFcfa::TIRET }}</td>
                </tr>
              @empty
                <tr><td colspan="6" class="px-5 py-10 text-center text-slate-400 text-sm">{{ __('pwa.etats_legacy.historique_vide') }}</td></tr>
              @endforelse
            </tbody>
          </table>
          @if ($tronque)
            <div class="flex items-center justify-between px-5 py-3 border-t border-slate-100">
              <p class="text-xs text-slate-500">{{ __('pwa.etats_legacy.decompte', ['affiches' => $editions->count(), 'total' => $total]) }}</p>
              <p class="text-xs" style="color:#78350F">{{ __('pwa.etats_legacy.tronque', ['plafond' => Etats::PLAFOND]) }}</p>
            </div>
          @endif
        </div>

      </div>
    </main>
  </div>

</div>
