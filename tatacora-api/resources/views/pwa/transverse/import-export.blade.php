{{--
    IMPORT & EXPORT — maître : `prototype_v2/pages/import-export.html`.

    Transcription littérale des QUATRE onglets du maître (directive du
    Product Owner, 02/09/2026), avec un fonctionnement réel derrière chaque
    geste — voir le docblock de `App\Pwa\Livewire\Transverse\ImportExport`
    pour les services en jeu. Les blocs que le maître remplit en JavaScript
    (fiche de module, rapport de contrôle, historique, lignes de tableaux,
    pastilles) reproduisent le MARKUP que ses fonctions de rendu génèrent.

    Visibilité des panneaux : comme le maître, les quatre panneaux vivent
    dans le même document et l'inactif porte `hidden` — la classe est posée
    par une branche conditionnelle écrite pour que la source neutralisée du
    comparateur `t-structure.js` voie le panneau par défaut OUVERT et les
    trois autres FERMÉS, exactement comme il lit le maître.
--}}
<div class="contents">

@include('pwa.partials.barre-superieure')

  @if (session('pwa-succes'))
    <div class="fixed top-5 right-5 z-50 flex items-center gap-3 px-4 py-3 rounded-xl shadow-xl bg-emerald-600 text-white text-[13px] font-medium no-print"
         x-data="{ visible: true }" x-show="visible" x-init="setTimeout(() => visible = false, 5000)">
      <span>{{ session('pwa-succes') }}</span>
      <button type="button" x-on:click="visible = false" class="ml-2 text-white/80 hover:text-white">✕</button>
    </div>
  @endif

  <div class="flex flex-1 overflow-hidden">
    @include('pwa.partials.menu-lateral')
    <main class="flex-1 overflow-y-auto">
      <div class="max-w-[1200px] mx-auto p-5 lg:p-8">

        <div class="mb-6">
          <div class="flex items-center gap-2.5">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--navy)" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4M7 10l5 5 5-5M12 15V3"/></svg>
            <h1 class="text-lg lg:text-xl font-bold" style="color:var(--navy)">{{ __('pwa.import_export.titre') }}</h1>
          </div>
          <p class="text-[15px] text-slate-500 mt-1.5">{{ __('pwa.import_export.sous_titre') }}</p>
        </div>

        <div class="flex flex-wrap gap-2 mb-5">
          <button type="button" wire:click="$set('onglet', 'importer')"
                  class="{{ \App\Pwa\Support\Onglets::classes($onglet === 'importer') }}">{{ __('pwa.import_export.onglet_importer') }}</button>
          <button type="button" wire:click="$set('onglet', 'sauvegardes')"
                  class="{{ \App\Pwa\Support\Onglets::classes($onglet === 'sauvegardes') }}">{{ __('pwa.import_export.onglet_sauvegardes') }}</button>
          <button type="button" wire:click="$set('onglet', 'restaurer')"
                  class="{{ \App\Pwa\Support\Onglets::classes($onglet === 'restaurer') }}">
            {{ __('pwa.import_export.onglet_restaurer') }}
            @if ($nombreRestaurables > 0)
              <span class="ml-1 text-[10px] font-bold text-white rounded-full px-1.5 py-0.5" style="background:var(--gold)">{{ $nombreRestaurables }}</span>
            @endif
          </button>
          <button type="button" wire:click="$set('onglet', 'seeders')"
                  class="{{ \App\Pwa\Support\Onglets::classes($onglet === 'seeders') }}">{{ __('pwa.import_export.onglet_seeders') }}</button>
        </div>

        {{-- ============================================ ONGLET 1 : IMPORTER --}}
        <section data-panneau-ie="importer" class="@if ($onglet === 'importer')@else hidden @endif">
          <div class="grid grid-cols-1 lg:grid-cols-3 gap-5">

            <div class="lg:col-span-2 space-y-5">
              <div class="bg-white rounded-xl border border-slate-200 p-5">
                <h2 class="text-sm font-bold text-slate-700 mb-1">{{ __('pwa.import_export.importer_module_label') }}</h2>
                <p class="text-[13px] text-slate-500 mb-3.5">{{ __('pwa.import_export.importer_module_aide') }}</p>
                <select wire:model.live="moduleImport" class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm bg-white">
                  <option value="">{{ __('pwa.import_export.importer_module_invite') }}</option>
                  @foreach ($modulesImportables as $definition)
                    <option value="{{ $definition->cle }}">{{ $definition->module }} — {{ $definition->nom }}</option>
                  @endforeach
                </select>

                {{-- La fiche du module (maquette l.51-66), remplie côté
                     serveur depuis `ReferentielsImport` — la MÊME déclaration
                     que le modèle et le contrôle. Le markup des lignes est
                     celui de `rendreFicheModule()` (maquette l.410-438).
                     Comme chez le maître (`#fiche-module` porte `hidden` au
                     chargement, l.51), la fiche vit dans le DOM avec son
                     entête et se cache tant qu'aucun module n'est choisi —
                     c'est aussi ce qui rend ses colonnes mesurables au
                     premier GET (`ColonnesDesTableauxPwaTest`). --}}
                <div @if ($moduleChoisi === null) hidden @endif class="mt-4 pt-4 border-t border-slate-100">
                    <p class="text-[13px] text-slate-500 mb-3">{{ $moduleChoisi?->description }}</p>
                    <h3 class="text-[13px] font-bold text-slate-700 mb-2">{{ __('pwa.import_export.colonnes_attendues') }}</h3>
                    <div class="overflow-x-auto">
                      <table class="w-full">
                        <thead class="bg-slate-50">
                          <tr>
                            <th class="text-left px-3 py-2 text-[12px] font-bold text-slate-500">{{ __('pwa.import_export.col_colonne') }}</th>
                            <th class="text-left px-3 py-2 text-[12px] font-bold text-slate-500">{{ __('pwa.import_export.col_obligatoire') }}</th>
                            <th class="text-left px-3 py-2 text-[12px] font-bold text-slate-500">{{ __('pwa.import_export.col_valeurs_attendues') }}</th>
                          </tr>
                        </thead>
                        <tbody>
                          @foreach ($moduleChoisi?->colonnes ?? [] as $colonne)
                            <tr class="border-b border-slate-100">
                              <td class="px-3 py-2 text-[13px]">
                                <span class="font-semibold text-slate-700">{{ $colonne->libelle }}</span>
                                <span class="block text-[12px] font-mono-tatacora text-slate-400">{{ $colonne->champ }}</span>
                              </td>
                              <td class="px-3 py-2">
                                @if ($colonne->requis)
                                  <span class="text-[11px] font-bold rounded px-1.5 py-0.5" style="background:#FDECEC;color:var(--erreur)">{{ __('pwa.import_export.badge_obligatoire') }}</span>
                                @else
                                  <span class="text-[11px] font-bold rounded px-1.5 py-0.5 bg-slate-100 text-slate-400">{{ __('pwa.import_export.badge_facultatif') }}</span>
                                @endif
                              </td>
                              <td class="px-3 py-2 text-[13px] text-slate-500">
                                @if ($colonne->valeurs !== null)
                                  @foreach ($colonne->valeurs as $valeur)
                                    <span class="inline-block text-[12px] border border-slate-200 rounded px-1.5 py-0.5 mr-1 mb-1">{{ $valeur }}</span>
                                  @endforeach
                                @else
                                  {{ match ($colonne->type) {
                                      'montant' => __('imports.types.montant'),
                                      'nombre' => __('imports.types.nombre'),
                                      'reference' => __('imports.types.reference'),
                                      default => __('imports.types.texte'),
                                  } }}
                                @endif
                                <span class="block text-[12px] text-slate-400 mt-0.5">{{ __('imports.exemple_prefixe', ['exemple' => $colonne->exemple]) }}</span>
                              </td>
                            </tr>
                          @endforeach
                        </tbody>
                      </table>
                    </div>
                </div>
              </div>

              <div class="bg-white rounded-xl border border-slate-200 p-5">
                <div class="flex items-start justify-between gap-3 mb-1">
                  <h2 class="text-sm font-bold text-slate-700">{{ __('pwa.import_export.importer_modele_titre') }}</h2>
                  @if ($peutEcrire)
                    <button type="button" wire:click="telechargerModeleCsv" @if ($moduleChoisi === null) disabled @endif
                            class="btn shrink-0 flex items-center gap-2 px-3.5 py-2 rounded-lg text-white text-[13px] font-semibold disabled:opacity-50" style="background:var(--gold)">
                      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><path stroke-linecap="round" stroke-linejoin="round" d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4M7 10l5 5 5-5M12 15V3"/></svg>
                      {{ __('pwa.import_export.importer_modele_bouton') }}
                    </button>
                  @endif
                </div>
                <p class="text-[13px] text-slate-500">
                  {{ __('pwa.import_export.importer_modele_aide_1') }}
                  <strong>{{ __('pwa.import_export.importer_modele_aide_format') }}</strong>.
                </p>
              </div>

              <div class="bg-white rounded-xl border border-slate-200 p-5">
                <h2 class="text-sm font-bold text-slate-700 mb-1">{{ __('pwa.import_export.importer_depot_titre') }}</h2>
                <p class="text-[13px] text-slate-500 mb-3.5">{{ __('pwa.import_export.importer_depot_aide') }}</p>
                <div x-data="{ survol: false }">
                <div x-on:dragover.prevent="survol = true"
                     x-on:dragleave="survol = false"
                     x-on:drop.prevent="survol = false; if ($refs.fichier && $event.dataTransfer.files.length) { $refs.fichier.files = $event.dataTransfer.files; $refs.fichier.dispatchEvent(new Event('change')); }"
                     x-on:click="if ($refs.fichier) $refs.fichier.click()"
                     :class="{ 'survol': survol }"
                     class="zone-depot rounded-lg p-8 text-center cursor-pointer">
                  <svg width="30" height="30" viewBox="0 0 24 24" fill="none" stroke="#9CA3AF" stroke-width="1.6" class="mx-auto mb-2"><path stroke-linecap="round" stroke-linejoin="round" d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4M17 8l-5-5-5 5M12 3v12"/></svg>
                  <p class="text-[15px] text-slate-600 font-semibold">{{ __('pwa.import_export.importer_depot_glisser') }}</p>
                  <p class="text-[13px] text-slate-400 mt-0.5">{{ __('pwa.import_export.importer_depot_cliquer') }}</p>
                </div>
                {{-- Le champ de dépôt n'est rendu QU'après le choix d'un
                     module : la doctrine RefuseLaSaisie refuse tout champ de
                     fichier au premier GET, et le maître lui-même refuse un
                     fichier sans module (`prendreFichier`, l.777-779) — la
                     zone reste visible, le dépôt attend le module. Hors de la
                     zone cliquable, comme au maître (l.92) : un champ interne
                     ferait boucler le clic programmatique sur son parent. --}}
                @if ($moduleChoisi !== null && $peutEcrire)
                  <input type="file" accept=".csv,text/csv" x-ref="fichier" wire:model="fichierImport" class="hidden">
                @endif
                </div>
                @if ($fichierImport !== null)
                  <p class="text-[13px] text-slate-600 mt-2.5 font-semibold">
                    {{ __('pwa.import_export.importer_fichier_selectionne', [
                        'nom' => $fichierImport->getClientOriginalName(),
                        'taille' => max(1, (int) round($fichierImport->getSize() / 1024)),
                    ]) }}
                  </p>
                @endif
                @error('fichierImport') <p class="text-[12px] text-red-600 mt-2">{{ $message }}</p> @enderror
                @error('moduleImport') <p class="text-[12px] text-red-600 mt-2">{{ $message }}</p> @enderror

                @if ($peutEcrire)
                  <button type="button" wire:click="controlerFichierImport" wire:loading.attr="disabled"
                          @if ($moduleChoisi === null || $fichierImport === null) disabled @endif
                          class="btn w-full mt-4 flex items-center justify-center gap-2 px-5 py-2.5 rounded-lg text-white text-sm font-semibold disabled:opacity-50" style="background:var(--navy)">
                    <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><path stroke-linecap="round" stroke-linejoin="round" d="M9 11l3 3L22 4"/><path stroke-linecap="round" stroke-linejoin="round" d="M21 12v7a2 2 0 01-2 2H5a2 2 0 01-2-2V5a2 2 0 012-2h11"/></svg>
                    {{ __('pwa.import_export.importer_valider') }}
                  </button>
                @endif
              </div>

              {{-- Rapport de contrôle — le markup de `rendreRapport()`
                   (maquette l.455-527) : bandeau, lignes ERREUR/AVERTIS.
                   plafonnées, action selon la conformité. --}}
              @if ($rapportControle !== null && $moduleChoisi !== null && $rapportControle['cle'] === $moduleChoisi->cle)
                <div class="bg-white rounded-xl border border-slate-200 overflow-hidden">
                  <div class="px-5 py-4 flex items-start gap-3" style="background:{{ $rapportControle['ok'] ? '#E8F5E9' : '#FDECEC' }}">
                    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="{{ $rapportControle['ok'] ? 'var(--succes)' : 'var(--erreur)' }}" stroke-width="2.2" class="shrink-0 mt-0.5">
                      @if ($rapportControle['ok'])
                        <path stroke-linecap="round" stroke-linejoin="round" d="M20 6L9 17l-5-5"/>
                      @else
                        <circle cx="12" cy="12" r="10"/><path stroke-linecap="round" d="M15 9l-6 6M9 9l6 6"/>
                      @endif
                    </svg>
                    <div class="min-w-0">
                      <p class="text-sm font-bold" style="color:{{ $rapportControle['ok'] ? 'var(--succes)' : 'var(--erreur)' }}">
                        {{ $rapportControle['ok'] ? __('pwa.import_export.rapport_conforme') : __('pwa.import_export.rapport_non_conforme') }}
                      </p>
                      <p class="text-[13px] text-slate-600 mt-0.5">
                        {{ __('pwa.import_export.rapport_resume', ['total' => $rapportControle['resume']['total'] ?? 0]) }}
                        <strong>{{ $rapportControle['resume']['valides'] ?? 0 }}</strong> {{ __('pwa.import_export.rapport_resume_exploitables') }}
                        <strong>{{ $rapportControle['resume']['en_erreur'] ?? 0 }}</strong> {{ __('pwa.import_export.rapport_resume_erreurs') }}
                        {{ __('pwa.import_export.rapport_resume_avertissements', ['nombre' => count($rapportControle['avertissements'])]) }}
                      </p>
                    </div>
                  </div>
                  <div class="max-h-80 overflow-y-auto">
                    @foreach ($rapportControle['erreurs'] as $anomalie)
                      <div class="flex items-start gap-2.5 px-5 py-2 border-b border-slate-100">
                        <span class="mt-1 shrink-0 text-[10px] font-bold rounded px-1.5 py-0.5" style="background:#FDECEC;color:var(--erreur)">{{ __('pwa.import_export.rapport_badge_erreur') }}</span>
                        <div class="min-w-0">
                          <p class="text-[13px] text-slate-700">
                            <span class="font-mono-tatacora font-semibold">{{ __('pwa.import_export.rapport_ligne', ['numero' => $anomalie['ligne']]) }}</span>
                            @if ($anomalie['colonne'] !== null)
                              · <span class="font-semibold">{{ $anomalie['colonne'] }}</span>
                            @endif
                          </p>
                          <p class="text-[13px] text-slate-500">{{ $anomalie['message'] }}</p>
                        </div>
                      </div>
                    @endforeach
                    @foreach ($rapportControle['avertissements'] as $anomalie)
                      <div class="flex items-start gap-2.5 px-5 py-2 border-b border-slate-100">
                        <span class="mt-1 shrink-0 text-[10px] font-bold rounded px-1.5 py-0.5" style="background:#FFFBEB;color:#7C5E12">{{ __('pwa.import_export.rapport_badge_avertissement') }}</span>
                        <div class="min-w-0">
                          <p class="text-[13px] text-slate-700">
                            <span class="font-mono-tatacora font-semibold">{{ __('pwa.import_export.rapport_ligne', ['numero' => $anomalie['ligne']]) }}</span>
                            @if ($anomalie['colonne'] !== null)
                              · <span class="font-semibold">{{ $anomalie['colonne'] }}</span>
                            @endif
                          </p>
                          <p class="text-[13px] text-slate-500">{{ $anomalie['message'] }}</p>
                        </div>
                      </div>
                    @endforeach
                    @if ($rapportControle['total_erreurs'] > count($rapportControle['erreurs']))
                      <p class="px-5 py-2.5 text-[13px] text-slate-400">{{ __('pwa.import_export.rapport_suite_erreurs', ['nombre' => $rapportControle['total_erreurs'] - count($rapportControle['erreurs'])]) }}</p>
                    @endif
                    @if ($rapportControle['erreurs'] === [] && $rapportControle['avertissements'] === [])
                      <p class="px-5 py-4 text-[13px] text-slate-500">{{ __('pwa.import_export.rapport_aucune_anomalie') }}</p>
                    @endif
                  </div>
                  <div class="px-5 py-4 border-t border-slate-100 flex flex-col sm:flex-row gap-2.5">
                    @if ($rapportControle['ok'] && $peutEcrire)
                      <button type="button" wire:click="confirmerImport" wire:loading.attr="disabled"
                              class="btn flex-1 flex items-center justify-center gap-2 px-5 py-2.5 rounded-lg text-white text-sm font-semibold" style="background:var(--succes)">
                        {{ __('pwa.import_export.rapport_confirmer', ['nombre' => $rapportControle['resume']['valides'] ?? 0]) }}
                      </button>
                    @else
                      <div class="flex-1 rounded-lg px-3.5 py-2.5" style="background:#FFFBEB">
                        <p class="text-[13px]" style="color:#7C5E12">{{ __('pwa.import_export.rapport_corriger') }}</p>
                      </div>
                    @endif
                  </div>
                </div>
              @endif
            </div>

            {{-- Colonne latérale : démarche + historique (maquette l.110-149) --}}
            <aside class="space-y-5">
              <section class="bg-white rounded-xl border border-slate-200 p-5">
                <h2 class="text-sm font-bold text-slate-700 mb-3">{{ __('pwa.import_export.demarche_titre') }}</h2>
                <ol class="space-y-3">
                  <li class="flex gap-2.5">
                    <span class="w-5 h-5 rounded-full text-white text-[11px] font-bold flex items-center justify-center shrink-0" style="background:var(--navy)">1</span>
                    <p class="text-[13px] text-slate-600">{{ __('pwa.import_export.demarche_1') }}</p>
                  </li>
                  <li class="flex gap-2.5">
                    <span class="w-5 h-5 rounded-full text-white text-[11px] font-bold flex items-center justify-center shrink-0" style="background:var(--navy)">2</span>
                    <p class="text-[13px] text-slate-600">{{ __('pwa.import_export.demarche_2_avant') }} <strong>{{ __('pwa.import_export.demarche_2_fort') }}</strong>.</p>
                  </li>
                  <li class="flex gap-2.5">
                    <span class="w-5 h-5 rounded-full text-white text-[11px] font-bold flex items-center justify-center shrink-0" style="background:var(--navy)">3</span>
                    <p class="text-[13px] text-slate-600">{{ __('pwa.import_export.demarche_3') }}</p>
                  </li>
                  <li class="flex gap-2.5">
                    <span class="w-5 h-5 rounded-full text-white text-[11px] font-bold flex items-center justify-center shrink-0" style="background:var(--navy)">4</span>
                    <p class="text-[13px] text-slate-600">{{ __('pwa.import_export.demarche_4') }}</p>
                  </li>
                  <li class="flex gap-2.5">
                    <span class="w-5 h-5 rounded-full text-white text-[11px] font-bold flex items-center justify-center shrink-0" style="background:var(--navy)">5</span>
                    <p class="text-[13px] text-slate-600">{{ __('pwa.import_export.demarche_5') }}</p>
                  </li>
                </ol>
                <div class="mt-4 pt-3.5 border-t border-slate-100 rounded-lg px-3 py-2.5" style="background:#FFFBEB">
                  <p class="text-[13px]" style="color:#7C5E12">
                    <strong>{{ __('pwa.import_export.demarche_encadre_fort') }}</strong>
                    {{ __('pwa.import_export.demarche_encadre') }}
                  </p>
                </div>
              </section>

              <section class="bg-white rounded-xl border border-slate-200 overflow-hidden">
                <div class="px-5 py-3.5 border-b border-slate-100">
                  <h2 class="text-sm font-bold text-slate-700">{{ __('pwa.import_export.historique_titre') }}</h2>
                </div>
                <div class="divide-y divide-slate-100 max-h-72 overflow-y-auto">
                  @forelse ($historiqueImports as $entree)
                    <div class="px-5 py-3">
                      <p class="text-[15px] font-semibold text-slate-700">{{ \App\Shared\ImportExport\Data\ReferentielsImport::parCle($entree->module_cle)?->nom ?? $entree->module_cle }}</p>
                      <p class="text-[13px] text-slate-500">{{ __('pwa.import_export.historique_lignes', ['nombre' => $entree->nombre_lignes]) }}</p>
                      <p class="text-[12px] text-slate-400 mt-0.5">{{ $entree->date_heure->format('d/m/Y H:i') }} · {{ $entree->utilisateur?->login ?? '—' }}</p>
                    </div>
                  @empty
                    <p class="px-5 py-8 text-center text-[13px] text-slate-400">{{ __('pwa.import_export.historique_vide') }}</p>
                  @endforelse
                </div>
              </section>
            </aside>
          </div>
        </section>

        {{-- ========================================= ONGLET 2 : SAUVEGARDES --}}
        <section data-panneau-ie="sauvegardes" class="@if ($onglet !== 'sauvegardes') hidden @endif">
          {{-- Bandeau (maquette l.157, rendu de `rendreBandeauSauvegarde`) :
               VERT après une génération, OR quand la plus récente n'a jamais
               été téléchargée — dérivé des fichiers réels, jamais d'un
               drapeau (PA-59/60/61). --}}
          @if ($sauvegardeGeneree !== null)
            <div class="rounded-xl border p-4 mb-5 flex flex-col sm:flex-row sm:items-center gap-3" style="background:#E8F5E9;border-color:#A5D6A7">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="var(--succes)" stroke-width="2.2" class="shrink-0"><path stroke-linecap="round" stroke-linejoin="round" d="M20 6L9 17l-5-5"/></svg>
              <div class="min-w-0">
                <p class="text-[15px] font-bold" style="color:#1B5E20">{{ __('pwa.import_export.bandeau_generee_titre') }}</p>
                <p class="text-[13px]" style="color:#1B5E20">{{ __('pwa.import_export.bandeau_generee_texte', ['fichier' => $sauvegardeGeneree]) }}</p>
              </div>
              @if ($peutEcrire)
                <button type="button" wire:click="telechargerSauvegarde('{{ $sauvegardeGeneree }}')"
                        class="btn sm:ml-auto shrink-0 px-4 py-2 rounded-lg text-white text-[13px] font-semibold" style="background:var(--succes)">{{ __('pwa.import_export.action_telecharger') }}</button>
              @endif
            </div>
          @elseif ($sauvegardeEnAttente !== null)
            <div class="rounded-xl border p-4 mb-5 flex flex-col sm:flex-row sm:items-center gap-3" style="background:#FFFBEB;border-color:#FDE68A">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="var(--gold)" stroke-width="2.2" class="shrink-0"><path stroke-linecap="round" stroke-linejoin="round" d="M12 9v4m0 4h.01M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z"/></svg>
              <div class="min-w-0">
                <p class="text-[15px] font-bold" style="color:#7C5E12">{{ __('pwa.import_export.bandeau_rappel_titre') }}</p>
                <p class="text-[13px]" style="color:#7C5E12">{{ __('pwa.import_export.bandeau_rappel_texte', ['fichier' => $sauvegardeEnAttente['nom'], 'date' => $sauvegardeEnAttente['date']->format('d/m/Y')]) }}</p>
              </div>
              @if ($peutEcrire)
                <button type="button" wire:click="telechargerSauvegarde('{{ $sauvegardeEnAttente['nom'] }}')"
                        class="btn sm:ml-auto shrink-0 px-4 py-2 rounded-lg text-white text-[13px] font-semibold" style="background:var(--gold)">{{ __('pwa.import_export.action_telecharger') }}</button>
              @endif
            </div>
          @endif

          {{-- Les 4 KPI du maître (l.159-176), tous MESURÉS. La date de la
               dernière sauvegarde vient du fichier réel le plus récent — les
               dumps incomplets sont retirés par le Job avant d'être listés
               (le piège du fichier de 802 octets, documenté sur le Job). --}}
          <div class="grid grid-cols-1 sm:grid-cols-4 gap-3.5 mb-5">
            <div class="bg-white rounded-xl border border-slate-200 p-4">
              <p class="text-[12px] text-slate-500">{{ __('pwa.import_export.kpi_tables') }}</p>
              <p class="text-lg font-bold font-mono-tatacora mt-0.5" style="color:var(--navy)">{{ $nombreTables }}</p>
            </div>
            <div class="bg-white rounded-xl border border-slate-200 p-4">
              <p class="text-[12px] text-slate-500">{{ __('pwa.import_export.kpi_sauvegardes') }}</p>
              <p class="text-lg font-bold font-mono-tatacora mt-0.5" style="color:var(--navy)">{{ count($fichiersSauvegarde) }}</p>
            </div>
            <div class="bg-white rounded-xl border border-slate-200 p-4">
              <p class="text-[12px] text-slate-500">{{ __('pwa.import_export.kpi_derniere') }}</p>
              <p class="text-lg font-bold font-mono-tatacora mt-0.5" style="color:var(--navy)">{{ $fichiersSauvegarde !== [] ? $fichiersSauvegarde[0]['date']->format('d/m/Y') : '—' }}</p>
            </div>
            <div class="bg-white rounded-xl border border-slate-200 p-4">
              <p class="text-[12px] text-slate-500">{{ __('pwa.import_export.kpi_rythme') }}</p>
              <p class="text-lg font-bold mt-0.5" style="color:var(--succes)">{{ __('pwa.import_export.kpi_rythme_valeur') }}</p>
            </div>
          </div>

          <div class="flex flex-col sm:flex-row gap-2.5 mb-4">
            @if ($peutEcrire)
              <button type="button" wire:click="genererSauvegarde" wire:loading.attr="disabled"
                      class="btn flex items-center justify-center gap-2 px-5 py-2.5 rounded-lg text-white text-sm font-semibold" style="background:var(--navy)">
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><path stroke-linecap="round" stroke-linejoin="round" d="M19 21H5a2 2 0 01-2-2V5a2 2 0 012-2h11l5 5v11a2 2 0 01-2 2z"/><path stroke-linecap="round" stroke-linejoin="round" d="M17 21v-8H7v8M7 3v5h8"/></svg>
                {{ __('pwa.import_export.sauvegardes_generer') }}
              </button>
            @endif
            <button type="button" wire:click="ouvrirExport"
                    class="btn flex items-center justify-center gap-2 px-5 py-2.5 rounded-lg border border-slate-200 bg-white text-sm font-semibold text-slate-600">
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4M7 10l5 5 5-5M12 15V3"/></svg>
              {{ __('pwa.import_export.exporter_table_bouton') }}
            </button>
          </div>
          @error('sauvegarde') <p class="text-[12px] text-red-600 mb-3">{{ $message }}</p> @enderror
          <p class="text-[13px] text-slate-500 mb-4 max-w-[720px]">{{ __('pwa.import_export.sauvegardes_rythme') }}</p>

          {{-- EXCLU de la barre de recherche par table (PO, 01/09/2026) : la
               liste est bornée à trente jours de rétention — au plus une
               trentaine de fichiers, rien à filtrer. Entête navy : dérogation
               d'uniformisation du 01/09/2026 (`DerogationsMaquette`). --}}
          <div class="bg-white rounded-xl border border-slate-200 overflow-hidden">
            <div class="overflow-x-auto">
              <table class="w-full">
                <thead class="bg-[var(--navy)]">
                  <tr>
                    <th class="text-left px-5 py-2.5 text-[11px] font-semibold text-white/90 tracking-wide">{{ __('pwa.import_export.col_fichier') }}</th>
                    <th class="text-left px-5 py-2.5 text-[11px] font-semibold text-white/90 tracking-wide">{{ __('pwa.import_export.col_date') }}</th>
                    <th class="text-left px-5 py-2.5 text-[11px] font-semibold text-white/90 tracking-wide">{{ __('pwa.import_export.col_table') }}</th>
                    <th class="text-right px-5 py-2.5 text-[11px] font-semibold text-white/90 tracking-wide">{{ __('pwa.import_export.col_action') }}</th>
                  </tr>
                </thead>
                <tbody>
                  @forelse ($fichiersSauvegarde as $fichier)
                    <tr class="border-t border-slate-100 hover:bg-slate-50">
                      <td class="px-5 py-3">
                        <span class="text-[13px] font-mono-tatacora font-semibold text-slate-700">{{ $fichier['nom'] }}</span>
                        <span class="block text-[12px] text-slate-400">{{ number_format($fichier['taille'] / 1024, 0, ',', ' ') }} Ko{{ $fichier['telechargee'] ? '' : ' · '.__('pwa.import_export.sauvegarde_non_telechargee') }}</span>
                      </td>
                      <td class="px-5 py-3 text-[13px] text-slate-600 whitespace-nowrap">{{ $fichier['date']->format('d/m/Y') }}<span class="block text-[12px] text-slate-400">{{ $fichier['date']->format('H:i') }}</span></td>
                      <td class="px-5 py-3 text-[13px] text-slate-600">{{ __('pwa.import_export.sauvegarde_contenu') }}</td>
                      <td class="px-5 py-3 text-right whitespace-nowrap">
                        @if ($peutEcrire)
                          <button type="button" wire:click="telechargerSauvegarde('{{ $fichier['nom'] }}')"
                                  class="btn inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-white text-[13px] font-semibold" style="background:var(--navy)">
                            <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><path stroke-linecap="round" stroke-linejoin="round" d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4M7 10l5 5 5-5M12 15V3"/></svg>
                            {{ __('pwa.import_export.action_telecharger') }}
                          </button>
                          <button type="button" wire:click="retirerSauvegarde('{{ $fichier['nom'] }}')"
                                  class="btn p-1.5 rounded text-slate-400 hover:text-red-500 hover:bg-red-50 ml-1" title="{{ __('pwa.import_export.action_retirer') }}">
                            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M3 6h18M8 6V4a2 2 0 012-2h4a2 2 0 012 2v2m3 0v14a2 2 0 01-2 2H7a2 2 0 01-2-2V6h14z"/></svg>
                          </button>
                        @endif
                      </td>
                    </tr>
                  @empty
                    <tr><td colspan="4" class="px-5 py-10 text-center text-[13px] text-slate-400">{{ __('pwa.import_export.sauvegardes_vide') }}</td></tr>
                  @endforelse
                </tbody>
              </table>
            </div>
          </div>
          <p class="text-[12px] text-slate-400 mt-3">{{ __('pwa.import_export.sauvegardes_retention') }}</p>
        </section>

        {{-- =========================================== ONGLET 3 : RESTAURER --}}
        <section data-panneau-ie="restaurer" class="@if ($onglet !== 'restaurer') hidden @endif">
          {{-- L'encadré bleu du maître (l.214-224). Corps ADAPTÉ à la réalité
               serveur — voir le commentaire de `restaurer_texte` dans
               `lang/fr/pwa.php` (02/09/2026). --}}
          <div class="rounded-xl border p-4 mb-5 flex items-start gap-3" style="background:#E8EEFD;border-color:#BFD3FD">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="var(--info)" stroke-width="2.2" class="shrink-0 mt-0.5"><path stroke-linecap="round" stroke-linejoin="round" d="M3 12a9 9 0 109-9 9 9 0 00-6.36 2.64L3 8"/><path stroke-linecap="round" stroke-linejoin="round" d="M3 3v5h5"/></svg>
            <div class="min-w-0">
              <p class="text-[15px] font-bold" style="color:#1E3A8A">{{ __('pwa.import_export.restaurer_titre') }}</p>
              <p class="text-[13px] mt-1 leading-relaxed" style="color:#1E3A8A">{{ __('pwa.import_export.restaurer_texte') }}</p>
            </div>
          </div>

          <div class="flex flex-col sm:flex-row gap-3 mb-4">
            <div class="relative flex-1">
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="#9CA3AF" stroke-width="2" class="absolute left-3 top-1/2 -translate-y-1/2"><circle cx="11" cy="11" r="8"/><path stroke-linecap="round" d="M21 21l-4.35-4.35"/></svg>
              <input type="text" wire:model.live.debounce.300ms="rechercheArchives" placeholder="{{ __('pwa.import_export.recherche_archives') }}"
                     class="champ w-full border border-slate-200 rounded-lg pl-9 pr-3 py-2.5 text-[15px] bg-white">
            </div>
            <select wire:model.live="filtreArchives" class="champ border border-slate-200 rounded-lg px-3 py-2.5 text-[15px] bg-white sm:w-56">
              <option value="restaurables">{{ __('pwa.import_export.filtre_restaurables') }}</option>
              <option value="toutes">{{ __('pwa.import_export.filtre_toutes') }}</option>
              <option value="restaurees">{{ __('pwa.import_export.filtre_restaurees') }}</option>
            </select>
          </div>
          @error('archives') <p class="text-[12px] text-red-600 mb-3">{{ $message }}</p> @enderror

          <div class="bg-white rounded-xl border border-slate-200 overflow-hidden">
            <div class="overflow-x-auto">
              <table class="w-full">
                <thead class="bg-[var(--navy)]">
                  <tr>
                    <th class="text-left px-5 py-2.5 text-[11px] font-semibold text-white/90 tracking-wide">{{ __('pwa.import_export.col_element') }}</th>
                    <th class="text-left px-5 py-2.5 text-[11px] font-semibold text-white/90 tracking-wide">{{ __('pwa.import_export.col_module') }}</th>
                    <th class="text-left px-5 py-2.5 text-[11px] font-semibold text-white/90 tracking-wide">{{ __('pwa.import_export.col_archive_le') }}</th>
                    <th class="text-left px-5 py-2.5 text-[11px] font-semibold text-white/90 tracking-wide">{{ __('pwa.import_export.col_par') }}</th>
                    <th class="text-right px-5 py-2.5 text-[11px] font-semibold text-white/90 tracking-wide">{{ __('pwa.import_export.col_action') }}</th>
                  </tr>
                </thead>
                <tbody>
                  @forelse ($archives as $entree)
                    <tr class="border-t border-slate-100 hover:bg-slate-50 {{ $entree['restaure'] ? 'opacity-60' : '' }}">
                      <td class="px-5 py-3">
                        <span class="text-[15px] font-semibold text-slate-700">{{ $entree['libelle'] }}</span>
                      </td>
                      <td class="px-5 py-3 text-[13px] text-slate-600">{{ \App\Pwa\Livewire\Transverse\RolesPermissions::MODULES[$entree['module']] ?? $entree['module'] }}</td>
                      <td class="px-5 py-3 text-[13px] text-slate-600 whitespace-nowrap">
                        {{ $entree['archive_le']?->format('d/m/Y') ?? '—' }}
                        <span class="block text-[12px] text-slate-400">{{ $entree['archive_le']?->format('H:i') ?? '' }}</span>
                      </td>
                      <td class="px-5 py-3 text-[13px] text-slate-600">{{ $entree['archive_par'] ?? '—' }}</td>
                      <td class="px-5 py-3 text-right whitespace-nowrap">
                        @if ($entree['restaure'])
                          <span class="text-[12px] font-bold rounded px-2 py-1" style="background:#E8F5E9;color:var(--succes)">{{ __('pwa.import_export.badge_restaure') }}</span>
                        @elseif ($peutEcrire)
                          <button type="button" wire:click="restaurerArchive('{{ $entree['type'] }}', '{{ $entree['id'] }}')"
                                  class="btn inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-white text-[13px] font-semibold" style="background:var(--succes)">
                            <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><path stroke-linecap="round" stroke-linejoin="round" d="M3 12a9 9 0 109-9 9 9 0 00-6.36 2.64L3 8"/><path stroke-linecap="round" stroke-linejoin="round" d="M3 3v5h5"/></svg>
                            {{ __('pwa.import_export.action_restaurer') }}
                          </button>
                        @endif
                        @if (! $entree['restaure'] && $estSuperAdmin)
                          <button type="button" wire:click="ouvrirPurge('{{ $entree['type'] }}', '{{ $entree['id'] }}')"
                                  class="btn p-1.5 rounded text-slate-400 hover:text-red-500 hover:bg-red-50 ml-1" title="{{ __('pwa.import_export.action_purger') }}">
                            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M3 6h18M8 6V4a2 2 0 012-2h4a2 2 0 012 2v2m3 0v14a2 2 0 01-2 2H7a2 2 0 01-2-2V6h14z"/></svg>
                          </button>
                        @endif
                      </td>
                    </tr>
                  @empty
                    <tr><td colspan="5" class="px-5 py-10 text-center text-[13px] text-slate-400">{{ __('pwa.import_export.archives_vide') }}</td></tr>
                  @endforelse
                </tbody>
              </table>
            </div>
          </div>
        </section>

        {{-- ====================================== ONGLET 4 : RÉINITIALISER --}}
        <section data-panneau-ie="seeders" class="@if ($onglet !== 'seeders') hidden @endif">
          @unless ($reinitialisationAutorisee)
            <div class="rounded-xl p-4 mb-5" style="background:#FEF2F2;border:1px solid #FECACA">
              <p class="text-[13px]" style="color:#7F1D1D">{{ __('pwa.import_export.reset_environnement_production') }}</p>
            </div>
          @endunless

          {{-- Phase d'essais en production (19/10/2026, décision du PO) :
               `TATACORA_PHASE_ESSAIS=true` au `.env`. Dit tant qu'elle dure. --}}
          @if ($reinitialisationPhaseEssais)
            <div id="phase-essais" class="rounded-xl p-4 mb-5" style="background:#FFFBEB;border:1px solid #FDE68A">
              <p class="text-[13px]" style="color:#78350F">{{ __('pwa.import_export.reset_phase_essais') }}</p>
            </div>
          @endif

          @if (! $reinitialisationOuverte)
            {{-- L'état VERROUILLÉ du maître (l.261-273) — la bascule
                 `reinitialisation_seeders` est fermée. --}}
            <div class="bg-white rounded-xl border border-slate-200 p-8 text-center">
              <div class="w-12 h-12 rounded-full mx-auto mb-3 flex items-center justify-center" style="background:#F3F4F6">
                <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="#9CA3AF" stroke-width="2"><rect x="3" y="11" width="18" height="11" rx="2"/><path stroke-linecap="round" d="M7 11V7a5 5 0 0110 0v4"/></svg>
              </div>
              <p class="text-sm font-bold text-slate-700">{{ __('pwa.import_export.seeders_verrouille_titre') }}</p>
              <p class="text-[15px] text-slate-500 mt-1.5 max-w-lg mx-auto">{{ __('pwa.import_export.seeders_verrouille_texte') }}</p>
              <p class="text-[13px] text-slate-400 mt-2.5">
                {{ __('pwa.import_export.seeders_verrouille_ouvrir_avant') }}
                <a href="{{ route('pwa.parametres') }}" class="underline font-semibold" wire:navigate>{{ __('pwa.import_export.seeders_verrouille_ouvrir_lien') }}</a>.
              </p>
            </div>
          @else
            <div class="rounded-xl border p-4 mb-5 flex items-start gap-3" style="background:#FDECEC;border-color:#F5B5B5">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="var(--erreur)" stroke-width="2.2" class="shrink-0 mt-0.5"><path stroke-linecap="round" stroke-linejoin="round" d="M12 9v4m0 4h.01M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z"/></svg>
              <div class="min-w-0">
                <p class="text-[15px] font-bold" style="color:#8C1D1D">{{ __('pwa.import_export.seeders_bandeau_titre') }}</p>
                <p class="text-[13px] mt-1 leading-relaxed" style="color:#8C1D1D">{{ __('pwa.import_export.seeders_bandeau_texte') }}</p>
              </div>
            </div>

            {{-- Les deux listes du maître (l.287-299), pastilles comprises
                 (rendu de `rendreSeeders`, l.730-742) — DÉRIVÉES du réel :
                 `ReinitialisationDonneesTestService::tablesEffacables()` et
                 `tablesPreservees()`, mesurées sur la base. --}}
            <div class="grid grid-cols-1 lg:grid-cols-2 gap-5">
              <section class="bg-white rounded-xl border border-slate-200 p-5">
                <h2 class="text-sm font-bold mb-1" style="color:var(--erreur)">{{ __('pwa.import_export.seeders_vide_titre') }}</h2>
                <p class="text-[13px] text-slate-500 mb-3">{{ __('pwa.import_export.seeders_vide_texte') }}</p>
                <div class="space-y-1 max-h-72 overflow-y-auto">
                  @forelse ($tablesEffacables as $table)
                    <div class="flex items-center gap-2 px-3 py-1.5 rounded-lg" style="background:#FDECEC">
                      <span class="w-1.5 h-1.5 rounded-full shrink-0" style="background:#8C1D1D"></span>
                      <span class="text-[13px] font-mono-tatacora" style="color:#8C1D1D">{{ $table }}</span>
                    </div>
                  @empty
                    <p class="text-[13px] text-slate-400">{{ __('pwa.import_export.seeders_rien_a_vider') }}</p>
                  @endforelse
                </div>
              </section>

              <section class="bg-white rounded-xl border border-slate-200 p-5">
                <h2 class="text-sm font-bold mb-1" style="color:var(--succes)">{{ __('pwa.import_export.seeders_conserve_titre') }}</h2>
                <p class="text-[13px] text-slate-500 mb-3">{{ __('pwa.import_export.seeders_conserve_texte') }}</p>
                <div class="space-y-1 max-h-72 overflow-y-auto">
                  @foreach ($tablesPreservees as $table)
                    <div class="flex items-center gap-2 px-3 py-1.5 rounded-lg" style="background:#E8F5E9">
                      <span class="w-1.5 h-1.5 rounded-full shrink-0" style="background:#1B5E20"></span>
                      <span class="text-[13px] font-mono-tatacora" style="color:#1B5E20">{{ $table }}</span>
                    </div>
                  @endforeach
                </div>
              </section>
            </div>

            @if ($peutEcrire && $reinitialisationAutorisee && $reinitialisationPermise)
              <button type="button" wire:click="ouvrirReinitialisation"
                      class="btn w-full mt-5 flex items-center justify-center gap-2 px-5 py-3 rounded-lg text-white text-sm font-bold" style="background:var(--erreur)">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><path stroke-linecap="round" stroke-linejoin="round" d="M3 6h18M8 6V4a2 2 0 012-2h4a2 2 0 012 2v2m3 0v14a2 2 0 01-2 2H7a2 2 0 01-2-2V6h14z"/></svg>
                {{ __('pwa.import_export.seeders_bouton') }}
              </button>
            @endif
          @endif
        </section>

      </div>
    </main>
  </div>

  {{-- ============== MODALE — RÉINITIALISATION (markup du maître, l.313-339).
       Rendue derrière la condition d'état : un formulaire d'écriture ne se
       rend jamais au premier GET (doctrine RefuseLaSaisie). Le bouton reste
       inerte tant que la phrase n'est pas tapée — la garde d'interface du
       maître (l.864-866) ; le serveur revalide la phrase ET les deux verrous. --}}
  @if ($etatFormulaire === 'reinitialisation')
    <div class="overlay-modale no-print" style="display:flex" wire:keydown.escape.window="fermerModales"
         x-data="{ saisie: '' }">
      <div class="absolute inset-0" wire:click="fermerModales"></div>
      <div class="boite-modale relative max-w-lg">
        <div class="flex items-start gap-3 px-6 pt-6 pb-4">
          <div class="w-10 h-10 rounded-full flex items-center justify-center shrink-0" style="background:#FDECEC">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="var(--erreur)" stroke-width="2.2"><path stroke-linecap="round" stroke-linejoin="round" d="M12 9v4m0 4h.01M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z"/></svg>
          </div>
          <div class="min-w-0">
            <h2 class="text-base font-bold" style="color:var(--erreur)">{{ __('pwa.import_export.seeders_modale_titre') }}</h2>
            <p class="text-[15px] text-slate-600 mt-1.5 leading-relaxed">
              <strong>{{ __('pwa.import_export.seeders_modale_texte_avant', ['nombre' => count($tablesEffacables)]) }}</strong>
              {{ __('pwa.import_export.seeders_modale_texte_1') }}<br><br>
              {{ __('pwa.import_export.seeders_modale_texte_2') }}
              <strong>{{ __('pwa.import_export.seeders_modale_texte_2_fort') }}</strong>{{ __('pwa.import_export.seeders_modale_texte_2_fin') }}
            </p>
          </div>
        </div>
        <div class="px-6 pb-2">
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">
            {{ __('pwa.import_export.seeders_confirmation_avant') }}
            <span class="font-mono-tatacora px-1.5 py-0.5 rounded bg-slate-100" style="color:var(--erreur)">{{ __('pwa.import_export.seeders_phrase_confirmation') }}</span>
          </label>
          <input type="text" autocomplete="off" placeholder="{{ __('pwa.import_export.seeders_phrase_confirmation') }}"
                 wire:model="phraseConfirmationReset" x-on:input="saisie = $event.target.value"
                 class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm font-mono-tatacora">
          <p class="text-[12px] text-slate-400 mt-1.5">{{ __('pwa.import_export.seeders_confirmation_aide') }}</p>
          @error('phraseConfirmationReset') <p class="text-[12px] text-red-600 mt-1.5">{{ $message }}</p> @enderror
        </div>
        <div class="flex justify-end gap-3 px-6 py-5">
          <button type="button" wire:click="fermerModales"
                  class="btn px-5 py-2.5 rounded-lg border border-slate-200 bg-white text-sm font-semibold text-slate-600">{{ __('pwa.modale.annuler') }}</button>
          <button type="button" wire:click="reinitialiserDonneesTest" wire:loading.attr="disabled"
                  :disabled="saisie.trim().toUpperCase() !== '{{ __('pwa.import_export.seeders_phrase_confirmation') }}'"
                  class="btn px-5 py-2.5 rounded-lg text-white text-sm font-semibold disabled:opacity-50" style="background:var(--erreur)">{{ __('pwa.import_export.seeders_confirmer') }}</button>
        </div>
      </div>
    </div>
  @endif

  {{-- ================= MODALE — EXPORT D'UNE TABLE (markup du maître, l.342-358).
       Portée le 02/09/2026 sur directive du Product Owner — le refus antérieur
       est levé, pas contourné. Liste FERMÉE : `ExportTableService` exclut
       nommément `utilisateurs` et les jetons. --}}
  @if ($etatFormulaire === 'export_table')
    <div class="overlay-modale no-print" style="display:flex" wire:keydown.escape.window="fermerModales">
      <div class="absolute inset-0" wire:click="fermerModales"></div>
      <div class="boite-modale relative max-w-md">
        <div class="px-6 pt-6 pb-3">
          <h2 class="text-base font-bold" style="color:var(--navy)">{{ __('pwa.import_export.export_table_titre') }}</h2>
          <p class="text-[13px] text-slate-500 mt-1">{{ __('pwa.import_export.export_table_aide') }}</p>
        </div>
        <div class="px-6 pb-4">
          <select wire:model="tableExport" class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm bg-white">
            <option value="">{{ __('pwa.import_export.export_table_invite') }}</option>
            @foreach (app(\App\Shared\Backup\Services\ExportTableService::class)->tablesExportables() as $table)
              <option value="{{ $table }}">{{ $table }}</option>
            @endforeach
          </select>
          @error('tableExport') <p class="text-[12px] text-red-600 mt-1.5">{{ $message }}</p> @enderror
        </div>
        <div class="flex justify-end gap-3 px-6 pb-5">
          <button type="button" wire:click="fermerModales"
                  class="btn px-5 py-2.5 rounded-lg border border-slate-200 bg-white text-sm font-semibold text-slate-600">{{ __('pwa.modale.annuler') }}</button>
          <button type="button" wire:click="exporterTable"
                  class="btn px-5 py-2.5 rounded-lg text-white text-sm font-semibold" style="background:var(--navy)">{{ __('pwa.import_export.action_telecharger') }}</button>
        </div>
      </div>
    </div>
  @endif

  {{-- ====== MODALE — RETRAIT D'UNE SAUVEGARDE JAMAIS TÉLÉCHARGÉE (maquette
       l.592-600, `Dialogue.confirmer`) — rendue sur le châssis partagé. --}}
  @if ($etatFormulaire === 'retrait_sauvegarde')
    <x-pwa.modale :titre="__('pwa.import_export.retrait_titre')" largeur="440px">
      <p class="text-sm text-slate-600">{{ __('pwa.import_export.retrait_message') }}</p>
      <p class="text-[13px] text-slate-500">{{ __('pwa.import_export.retrait_detail') }}</p>

      <x-slot:pied>
        <button type="button" wire:click="fermerModales"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="confirmerRetraitSauvegarde"
                class="text-[13px] px-4 py-2 rounded-lg text-white font-semibold" style="background:var(--erreur)">{{ __('pwa.import_export.retrait_confirmer') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  {{-- ============ MODALE — PURGE DÉFINITIVE (maquette l.707-720,
       `Dialogue.confirmer`) — administrateur seul ; un refus motivé du
       domaine (élément engagé ou référencé) s'affiche ICI, la modale reste
       ouverte. --}}
  @if ($etatFormulaire === 'purge')
    <x-pwa.modale :titre="__('pwa.import_export.purge_titre')" :sous-titre="$purgeLibelle" largeur="440px">
      <p class="text-sm text-slate-600">{{ __('pwa.import_export.purge_message') }}</p>
      <p class="text-[13px] text-slate-500">{{ __('pwa.import_export.purge_detail') }}</p>
      @error('purge') <p class="text-[12px] text-red-600">{{ $message }}</p> @enderror

      <x-slot:pied>
        <button type="button" wire:click="fermerModales"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="purgerArchive"
                class="text-[13px] px-4 py-2 rounded-lg text-white font-semibold" style="background:var(--erreur)">{{ __('pwa.import_export.purge_confirmer') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

</div>
