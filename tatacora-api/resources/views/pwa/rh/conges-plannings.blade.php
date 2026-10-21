{{--
    CONGÉS & PLANNINGS (M13) — EF-M13-02 / EF-M13-04, RG-13 / RG-14.

    Écran créé le 21/10/2026 (décision du Product Owner : « écrans PWA + poste +
    synchronisation »). Les services de domaine existaient ; aucune vue ne les
    portait, et la page `Personnel & Paie` refuse ces onglets (elle le dit dans
    son en-tête). Il n'y a donc PAS de maître à copier : l'écran reprend le
    châssis et les classes de `Personnel & Paie`, et chaque libellé vit dans
    `lang/fr/rh_conges_pwa.php`.

    Aucune suppression : une erreur de planning se corrige par un nouveau
    créneau, un congé refusé se conserve avec sa trace.
--}}
@php
    use Illuminate\Support\Carbon;

    $classeOnglet = static fn (bool $actif): string => \App\Pwa\Support\Onglets::classes($actif);

    $entete = static fn (string $libelle, bool $gauche = false): string => '<th class="px-3 py-2.5 '
        . ($gauche ? 'text-left' : 'text-right')
        . ' text-[11px] uppercase tracking-wide text-white/90 font-semibold">'
        . e($libelle) . '</th>';

    $classeStatut = static fn (string $statut): string => match ($statut) {
        'valide' => 'bg-emerald-50 text-emerald-700',
        'refuse' => 'bg-red-50 text-red-700',
        default => 'bg-amber-50 text-amber-700',
    };
@endphp

<div class="contents">

  @include('pwa.partials.barre-superieure')

  @if (session('pwa-succes'))
    <div class="fixed top-5 right-5 z-50 flex items-center gap-3 px-4 py-3 rounded-xl shadow-xl bg-emerald-600 text-white text-[13px] font-medium no-print"
         x-data="{ visible: true }" x-show="visible" x-init="setTimeout(() => visible = false, 5000)">
      <span>{{ session('pwa-succes') }}</span>
      <button type="button" @click="visible = false" class="ml-2 text-white/80 hover:text-white">✕</button>
    </div>
  @endif

  <div class="flex flex-1 overflow-hidden">
    @include('pwa.partials.menu-lateral')

    <main class="flex-1 overflow-y-auto">
      <div class="max-w-[1600px] mx-auto p-5 lg:p-8">

        <div class="mb-5 flex flex-wrap items-start justify-between gap-3">
          <div>
            <div class="flex items-center gap-2.5">
              <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--navy)" stroke-width="2"><rect x="3" y="4" width="18" height="18" rx="2"/><path stroke-linecap="round" stroke-linejoin="round" d="M16 2v4M8 2v4M3 10h18"/></svg>
              <h1 class="text-lg lg:text-xl font-bold" style="color:var(--navy)">{{ __('rh_conges_pwa.titre') }}</h1>
            </div>
            <p class="text-[15px] text-slate-500 mt-1.5">{{ __('rh_conges_pwa.sous_titre') }}</p>
          </div>

          @if ($peutEcrire)
            <div class="flex flex-wrap gap-2 items-center">
              @if ($onglet === 'plannings')
                <button type="button" wire:click="ouvrirPlanification"
                        class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white hover:opacity-90 font-semibold">{{ __('rh_conges_pwa.bouton_planifier') }}</button>
              @else
                <button type="button" wire:click="ouvrirDemandeConge"
                        class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white hover:opacity-90 font-semibold">{{ __('rh_conges_pwa.bouton_demander') }}</button>
              @endif
            </div>
          @endif
        </div>

        <div class="grid grid-cols-2 lg:grid-cols-3 gap-3 mb-5">
          <div class="bg-white rounded-xl border border-slate-200 p-3.5">
            <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('rh_conges_pwa.kpi_plannings') }}</div>
            <div class="text-[17px] font-bold mt-1" style="color:var(--navy)" id="kpi-plannings">{{ $plannings->count() }}</div>
            <div class="text-[11px] text-slate-400 mt-0.5">{{ $jourAffiche->format('d/m/Y') }}</div>
          </div>
          <div class="bg-white rounded-xl border border-slate-200 p-3.5">
            <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('rh_conges_pwa.kpi_en_attente') }}</div>
            <div class="text-[17px] font-bold mt-1 {{ $enAttente > 0 ? 'text-amber-600' : 'text-slate-400' }}" id="kpi-en-attente">{{ $enAttente }}</div>
          </div>
          <div class="bg-white rounded-xl border border-slate-200 p-3.5">
            <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('rh_conges_pwa.kpi_en_conge') }}</div>
            <div class="text-[17px] font-bold mt-1" style="color:var(--navy)" id="kpi-en-conge">{{ $enCongeAujourdhui }}</div>
          </div>
        </div>

        <div class="flex flex-wrap gap-1.5 mb-4">
          <button type="button" wire:click="$set('onglet', 'plannings')" class="{{ $classeOnglet($onglet === 'plannings') }}">{{ __('rh_conges_pwa.onglet_plannings') }}</button>
          <button type="button" wire:click="$set('onglet', 'conges')" class="{{ $classeOnglet($onglet === 'conges') }}">{{ __('rh_conges_pwa.onglet_conges') }}</button>
        </div>

        {{-- ================================================ PLANNINGS --}}
        <div id="panneau-plannings" class="{{ $onglet === 'plannings' ? '' : 'hidden' }}">
          <div class="bg-white rounded-xl border border-slate-200 p-3.5 mb-4">
            <div class="flex flex-wrap gap-2.5 items-center">
              <label class="text-[12px] text-slate-500" for="filtre-jour">{{ __('rh_conges_pwa.jour') }}</label>
              <input id="filtre-jour" type="date" wire:model.live="jour" class="text-[13px] border border-slate-300 rounded-lg px-2.5 py-2">
              <select wire:model.live="service" class="text-[13px] border border-slate-300 rounded-lg px-3 py-2">
                <option value="">{{ __('rh_conges_pwa.tous_les_services') }}</option>
                @foreach ($services as $s)
                  <option value="{{ $s->id }}">{{ $s->libelle }}</option>
                @endforeach
              </select>
            </div>
          </div>

          <div class="bg-white rounded-xl border border-slate-200 overflow-hidden mb-3">
            <div class="overflow-x-auto">
              <table class="w-full text-[13px]">
                <thead class="bg-[var(--navy)]">
                  <tr>
                    {!! $entete(__('rh_conges_pwa.col_employe'), true) !!}
                    {!! $entete(__('rh_conges_pwa.col_service')) !!}
                    {!! $entete(__('rh_conges_pwa.col_date')) !!}
                    {!! $entete(__('rh_conges_pwa.col_debut')) !!}
                    {!! $entete(__('rh_conges_pwa.col_fin')) !!}
                  </tr>
                </thead>
                <tbody>
                  @forelse ($plannings as $p)
                    <tr class="border-t border-slate-100 hover:bg-slate-50" wire:key="planning-{{ $p->id }}">
                      <td class="px-3 py-2.5 text-left font-semibold text-slate-800">{{ $p->employe->nomComplet() }}</td>
                      <td class="px-3 py-2.5 text-right text-slate-600">{{ $p->service->libelle }}</td>
                      <td class="px-3 py-2.5 text-right text-slate-600">{{ $p->date->format('d/m/Y') }}</td>
                      <td class="px-3 py-2.5 text-right text-slate-600">{{ substr((string) $p->heure_debut, 0, 5) }}</td>
                      <td class="px-3 py-2.5 text-right text-slate-600">{{ substr((string) $p->heure_fin, 0, 5) }}</td>
                    </tr>
                  @empty
                    <tr>
                      <td colspan="5" class="py-14 text-center text-slate-400 text-[13px]">{{ __('rh_conges_pwa.planning_vide') }}</td>
                    </tr>
                  @endforelse
                </tbody>
              </table>
            </div>
          </div>
        </div>

        {{-- ==================================================== CONGÉS --}}
        <div id="panneau-conges" class="{{ $onglet === 'conges' ? '' : 'hidden' }}">
          <div class="bg-white rounded-xl border border-slate-200 p-3.5 mb-4">
            <div class="flex flex-wrap gap-2.5 items-center">
              <select wire:model.live="statutConge" class="text-[13px] border border-slate-300 rounded-lg px-3 py-2">
                <option value="">{{ __('rh_conges_pwa.tous_les_statuts') }}</option>
                @foreach (['en_attente', 'valide', 'refuse'] as $st)
                  <option value="{{ $st }}">{{ __('rh_conges_pwa.statut_'.$st) }}</option>
                @endforeach
              </select>
            </div>
          </div>

          <div class="bg-white rounded-xl border border-slate-200 overflow-hidden mb-3">
            <div class="overflow-x-auto">
              <table class="w-full text-[13px]">
                <thead class="bg-[var(--navy)]">
                  <tr>
                    {!! $entete(__('rh_conges_pwa.col_employe'), true) !!}
                    {!! $entete(__('rh_conges_pwa.col_type')) !!}
                    {!! $entete(__('rh_conges_pwa.col_du')) !!}
                    {!! $entete(__('rh_conges_pwa.col_au')) !!}
                    {!! $entete(__('rh_conges_pwa.col_jours')) !!}
                    {!! $entete(__('rh_conges_pwa.col_statut')) !!}
                    {!! $entete(__('rh_conges_pwa.col_validateur')) !!}
                    <th class="px-3 py-2.5"></th>
                  </tr>
                </thead>
                <tbody>
                  @forelse ($conges as $c)
                    <tr class="border-t border-slate-100 hover:bg-slate-50" wire:key="conge-{{ $c->id }}">
                      <td class="px-3 py-2.5 text-left font-semibold text-slate-800">
                        {{ $c->employe->nomComplet() }}
                        @error('conge-'.$c->id)
                          <div class="text-[11px] text-red-600 font-normal mt-0.5">{{ $message }}</div>
                        @enderror
                      </td>
                      <td class="px-3 py-2.5 text-right text-slate-600">{{ __('rh_conges_pwa.type_'.$c->type) }}</td>
                      <td class="px-3 py-2.5 text-right text-slate-600">{{ $c->date_debut->format('d/m/Y') }}</td>
                      <td class="px-3 py-2.5 text-right text-slate-600">{{ $c->date_fin->format('d/m/Y') }}</td>
                      <td class="px-3 py-2.5 text-right text-slate-600">{{ $c->nombreJours() }}</td>
                      <td class="px-3 py-2.5 text-right">
                        <span class="text-[11px] px-1.5 py-0.5 rounded font-semibold {{ $classeStatut($c->statut_validation) }}">{{ __('rh_conges_pwa.statut_'.$c->statut_validation) }}</span>
                      </td>
                      <td class="px-3 py-2.5 text-right text-slate-500 text-[12px]">{{ $c->validateur?->login ?? '—' }}</td>
                      <td class="px-3 py-2.5 text-right whitespace-nowrap">
                        @if ($peutEcrire && $c->statut_validation === 'en_attente')
                          <button type="button" wire:click="validerConge('{{ $c->id }}')"
                                  class="text-[11px] px-2 py-0.5 rounded border border-emerald-300 text-emerald-700 hover:bg-emerald-50">{{ __('rh_conges_pwa.bouton_valider') }}</button>
                          <button type="button" wire:click="refuserConge('{{ $c->id }}')"
                                  class="text-[11px] px-2 py-0.5 rounded border border-slate-300 hover:bg-white ml-1">{{ __('rh_conges_pwa.bouton_refuser') }}</button>
                        @endif
                      </td>
                    </tr>
                  @empty
                    <tr>
                      <td colspan="8" class="py-14 text-center text-slate-400 text-[13px]">{{ __('rh_conges_pwa.conge_vide') }}</td>
                    </tr>
                  @endforelse
                </tbody>
              </table>
            </div>
          </div>
        </div>

      </div>
    </main>
  </div>

  {{-- ====================================================== MODALE — PLANNING --}}
  @if ($etatFormulaire === 'planning')
    <x-pwa.modale :titre="__('rh_conges_pwa.modale_planning')" largeur="520px">
      <div>
        <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('rh_conges_pwa.champ_employe') }} <span class="text-red-500">*</span></label>
        <select wire:model="employePlanning" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          <option value="">{{ __('rh_conges_pwa.choisir') }}</option>
          @foreach ($employesEnPoste as $e)
            <option value="{{ $e->id }}">{{ $e->nomComplet() }}</option>
          @endforeach
        </select>
        @error('employePlanning') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
      </div>

      <div>
        <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('rh_conges_pwa.champ_service') }} <span class="text-red-500">*</span></label>
        <select wire:model="servicePlanning" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          <option value="">{{ __('rh_conges_pwa.choisir') }}</option>
          @foreach ($services as $s)
            <option value="{{ $s->id }}">{{ $s->libelle }}</option>
          @endforeach
        </select>
        @error('servicePlanning') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
      </div>

      <div class="grid grid-cols-3 gap-3">
        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('rh_conges_pwa.champ_date') }} <span class="text-red-500">*</span></label>
          <input type="date" wire:model="datePlanning" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          @error('datePlanning') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>
        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('rh_conges_pwa.champ_heure_debut') }}</label>
          <input type="time" wire:model="heureDebutPlanning" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          @error('heureDebutPlanning') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>
        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('rh_conges_pwa.champ_heure_fin') }}</label>
          <input type="time" wire:model="heureFinPlanning" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          @error('heureFinPlanning') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>
      </div>

      <x-slot:pied>
        <button type="button" wire:click="fermerModales"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('rh_conges_pwa.bouton_annuler') }}</button>
        <button type="button" wire:click="enregistrerPlanning"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('rh_conges_pwa.bouton_enregistrer') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  {{-- ======================================================== MODALE — CONGÉ --}}
  @if ($etatFormulaire === 'conge')
    <x-pwa.modale :titre="__('rh_conges_pwa.modale_conge')" largeur="520px">
      <div>
        <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('rh_conges_pwa.champ_employe') }} <span class="text-red-500">*</span></label>
        <select wire:model="employeConge" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          <option value="">{{ __('rh_conges_pwa.choisir') }}</option>
          @foreach ($employesEnPoste as $e)
            <option value="{{ $e->id }}">{{ $e->nomComplet() }}</option>
          @endforeach
        </select>
        @error('employeConge') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
      </div>

      <div>
        <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('rh_conges_pwa.champ_type') }} <span class="text-red-500">*</span></label>
        <select wire:model="typeConge" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          @foreach ($typesConge as $t)
            <option value="{{ $t }}">{{ __('rh_conges_pwa.type_'.$t) }}</option>
          @endforeach
        </select>
        @error('typeConge') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
      </div>

      <div class="grid grid-cols-2 gap-3">
        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('rh_conges_pwa.champ_du') }} <span class="text-red-500">*</span></label>
          <input type="date" wire:model="debutConge" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          @error('debutConge') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>
        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('rh_conges_pwa.champ_au') }} <span class="text-red-500">*</span></label>
          <input type="date" wire:model="finConge" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          @error('finConge') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>
      </div>

      <x-slot:pied>
        <button type="button" wire:click="fermerModales"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('rh_conges_pwa.bouton_annuler') }}</button>
        <button type="button" wire:click="enregistrerConge"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('rh_conges_pwa.bouton_enregistrer') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

</div>
