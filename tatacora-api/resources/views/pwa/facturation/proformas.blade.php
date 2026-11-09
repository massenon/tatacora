{{--
    PROFORMAS (M2) — écran « Factures proforma » de Facturation (PO, 07/11/2026). Écran PROPRE à la PWA :
    le maître `m2-facturation.html` n'a pas de proforma. structure-ajout:m2-facturation.html#page
    Document NON FISCAL : aucune colonne, aucun bouton ni aucune phrase de normalisation.
--}}
@php
    use App\Pwa\Support\MontantFcfa;
    use App\Domain\Facturation\Models\Proforma;
@endphp
<div class="contents">

  @include('pwa.partials.barre-superieure')

  <div class="flex flex-1 overflow-hidden">
    @include('pwa.partials.menu-lateral')
    <main class="flex-1 overflow-y-auto">
      <div class="max-w-[1440px] mx-auto p-5 lg:p-8">

        <div class="mb-5">
          <div class="flex items-center gap-2.5">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--navy)" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M6 2h9l5 5v13a2 2 0 01-2 2H6a2 2 0 01-2-2V4a2 2 0 012-2z"/><path stroke-linecap="round" d="M9 13h6M9 17h6M9 9h1"/></svg>
            <h1 class="text-lg lg:text-xl font-bold" style="color:var(--navy)">{{ __('proforma.ui.titre') }}</h1>
          </div>
          <p class="text-[15px] text-slate-500 mt-1.5">{{ __('proforma.ui.sous_titre') }}</p>
        </div>

        @if (session('pwa-succes'))
          <div class="mb-4 rounded-xl px-4 py-3 text-[13px] font-semibold no-print"
               style="background:#E8F5E9;color:#2E7D32;border:1px solid #C8E6C9">{{ session('pwa-succes') }}</div>
        @endif
        @if (session('pwa-erreur'))
          <div class="mb-4 rounded-xl px-4 py-3 text-[13px] font-semibold no-print"
               style="background:#FDECEC;border:1px solid #F5C6C6;color:#8C1D1D">{{ session('pwa-erreur') }}</div>
        @endif

        <section id="registre-proformas" class="mb-6">
          <div class="bg-white rounded-xl border border-slate-200 overflow-hidden">
            <div class="px-4 py-3 border-b border-slate-200 flex flex-wrap items-start justify-between gap-3">
              <a href="{{ route('pwa.facturation') }}" wire:navigate class="text-[13px] font-semibold text-slate-600 hover:underline">{{ __('proforma.ui.retour') }}</a>
              <div class="flex flex-wrap items-center gap-2">
                <input type="search" id="rech-proforma" wire:model.live.debounce.300ms="recherche" placeholder="{{ __('proforma.ui.recherche') }}"
                  class="text-[13px] border border-slate-300 rounded-lg px-3 py-1.5 w-56">
                <select id="filtre-proforma-statut" wire:model.live="statut" class="text-[13px] border border-slate-300 rounded-lg px-2.5 py-1.5">
                  <option value="">{{ __('proforma.ui.tous_statuts') }}</option>
                  @foreach (Proforma::STATUTS as $s)
                    <option value="{{ $s }}">{{ __('proforma.statut.'.$s) }}</option>
                  @endforeach
                </select>
                @if ($peutEcrire)
                  <button type="button" wire:click="ouvrirCreation"
                          class="text-[13px] px-3 py-1.5 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('proforma.ui.nouvelle') }}</button>
                @endif
              </div>
            </div>

            <div class="overflow-x-auto">
              <table class="w-full text-[13px]">
                <thead>
                  <tr class="text-left text-slate-500 border-b border-slate-200 bg-slate-50">
                    <th class="px-4 py-2.5 font-semibold">{{ __('proforma.ui.col_numero') }}</th>
                    <th class="px-4 py-2.5 font-semibold">{{ __('proforma.ui.col_date') }}</th>
                    <th class="px-4 py-2.5 font-semibold">{{ __('proforma.ui.col_client') }}</th>
                    <th class="px-4 py-2.5 font-semibold">{{ __('proforma.ui.col_objet') }}</th>
                    <th class="px-4 py-2.5 font-semibold text-right">{{ __('proforma.ui.col_total') }}</th>
                    <th class="px-4 py-2.5 font-semibold">{{ __('proforma.ui.col_statut') }}</th>
                    <th class="px-4 py-2.5"></th>
                  </tr>
                </thead>
                <tbody>
                  @forelse ($proformas as $p)
                    @php($affiche = $p->statutAffiche())
                    <tr class="border-b border-slate-100">
                      <td class="px-4 py-2.5 font-mono-tatacora">{{ $p->numero ?? __('proforma.ui.brouillon_sans_numero') }}</td>
                      <td class="px-4 py-2.5">{{ $p->date_emission?->format('d/m/Y') ?? MontantFcfa::TIRET }}</td>
                      <td class="px-4 py-2.5">{{ $p->client_nom }}</td>
                      <td class="px-4 py-2.5">{{ $p->objet }}</td>
                      <td class="px-4 py-2.5 text-right">{{ MontantFcfa::format((string) $p->total) }}</td>
                      <td class="px-4 py-2.5">
                        {{ __('proforma.statut.'.$affiche) }}
                        @if ($p->valide_jusqu_au !== null && $p->statut === Proforma::EMISE)
                          <span class="block text-[11px] text-slate-400">{{ __('proforma.ui.valable', ['date' => $p->valide_jusqu_au->format('d/m/Y')]) }}</span>
                        @endif
                        @if ($p->motif_annulation)<span class="block text-[11px] text-slate-400">{{ $p->motif_annulation }}</span>@endif
                      </td>
                      <td class="px-4 py-2.5 text-right whitespace-nowrap">
                        @if ($peutEcrire)
                          <button type="button" wire:click="imprimer('{{ $p->id }}')" class="text-[12px] font-semibold px-2.5 py-1 rounded-lg border border-slate-200 hover:bg-slate-50">{{ __('proforma.ui.pdf') }}</button>
                          @if ($p->estModifiable())
                            <button type="button" wire:click="ouvrirModification('{{ $p->id }}')" class="text-[12px] font-semibold px-2.5 py-1 rounded-lg border border-slate-200 hover:bg-slate-50">{{ __('proforma.ui.modifier') }}</button>
                          @endif
                          @if ($p->statut === Proforma::BROUILLON)
                            <button type="button" wire:click="emettre('{{ $p->id }}')" class="text-[12px] font-semibold px-2.5 py-1 rounded-lg border border-slate-200 hover:bg-slate-50">{{ __('proforma.ui.emettre') }}</button>
                          @endif
                          @if ($p->statut === Proforma::EMISE)
                            <button type="button" wire:click="ouvrirConversion('{{ $p->id }}')" class="text-[12px] font-semibold px-2.5 py-1 rounded-lg bg-[var(--navy)] text-white">{{ __('proforma.ui.convertir') }}</button>
                          @endif
                          @if ($p->estModifiable())
                            <button type="button" wire:click="ouvrirAnnulation('{{ $p->id }}')" class="text-[12px] font-semibold px-2.5 py-1 rounded-lg border border-slate-200 text-red-700 hover:bg-slate-50">{{ __('proforma.ui.annuler') }}</button>
                          @endif
                        @endif
                      </td>
                    </tr>
                  @empty
                    <tr><td colspan="7" class="px-4 py-6 text-center text-slate-400">
                      {{ __('proforma.ui.vide') }}
                      @unless ($filtreApplique)
                        {{-- Écart daté du PO (09/11/2026) : une réservation ne crée ni facture ni proforma. --}}
                        <br><span id="proformas-vide-aide">{{ __('proforma.ui.vide_aide') }}</span>
                      @endunless
                    </td></tr>
                  @endforelse
                </tbody>
              </table>
            </div>

            @if ($proformas->hasPages())
              <div class="flex items-center justify-between px-4 py-3 border-t border-slate-100 no-print">
                <p class="text-xs text-slate-500">{!! __('facturation_pwa.affichage', [
                    'debut' => '<strong>' . $proformas->firstItem() . '</strong>',
                    'fin' => '<strong>' . $proformas->lastItem() . '</strong>',
                    'total' => '<strong>' . $proformas->total() . '</strong>',
                ]) !!}</p>
                {{ $proformas->onEachSide(1)->links() }}
              </div>
            @endif
          </div>
        </section>
      </div>
    </main>
  </div>

  @if ($etatFormulaire === 'proforma')
    <x-pwa.modale :titre="$proformaId === '' ? __('proforma.ui.form_titre_creation') : __('proforma.ui.form_titre_modification')" largeur="760px" fermer="fermerModales">
      <form wire:submit.prevent="enregistrer" class="space-y-4">
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <div class="sm:col-span-2">
            <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('proforma.ui.form_client') }} <span class="text-red-500">*</span></label>
            <input type="text" wire:model="clientNom" class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm">
            @error('clientNom') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
          </div>
          <div>
            <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('proforma.ui.form_telephone') }}</label>
            <input type="text" wire:model="clientTelephone" class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm">
          </div>
          <div>
            <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('proforma.ui.form_ifu') }}</label>
            <input type="text" wire:model="clientIfu" class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm">
          </div>
          <div class="sm:col-span-2">
            <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('proforma.ui.form_objet') }}</label>
            <input type="text" wire:model="objet" class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm">
          </div>
        </div>

        <div>
          <p class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('proforma.ui.form_lignes') }}</p>
          @foreach ($lignes as $i => $ligne)
            <div class="grid grid-cols-12 gap-2 mb-2" wire:key="ligne-{{ $i }}">
              <input type="text" wire:model="lignes.{{ $i }}.designation" placeholder="{{ __('proforma.ui.form_designation') }}" class="champ col-span-6 border border-slate-200 rounded-lg px-3 py-2 text-sm">
              <input type="number" min="1" step="1" wire:model="lignes.{{ $i }}.quantite" placeholder="{{ __('proforma.ui.form_quantite') }}" class="champ col-span-2 border border-slate-200 rounded-lg px-3 py-2 text-sm">
              <input type="number" min="0" step="1" wire:model="lignes.{{ $i }}.prix_unitaire" placeholder="{{ __('proforma.ui.form_prix') }}" class="champ col-span-3 border border-slate-200 rounded-lg px-3 py-2 text-sm">
              <button type="button" wire:click="retirerLigne({{ $i }})" class="col-span-1 text-[12px] text-red-700" title="{{ __('proforma.ui.form_retirer_ligne') }}">×</button>
              @error('lignes.'.$i.'.designation') <p class="col-span-12 text-[12px] text-red-600">{{ $message }}</p> @enderror
              @error('lignes.'.$i.'.quantite') <p class="col-span-12 text-[12px] text-red-600">{{ $message }}</p> @enderror
              @error('lignes.'.$i.'.prix_unitaire') <p class="col-span-12 text-[12px] text-red-600">{{ $message }}</p> @enderror
            </div>
          @endforeach
          @error('lignes') <p class="text-[12px] text-red-600">{{ $message }}</p> @enderror
          <button type="button" wire:click="ajouterLigne" class="text-[13px] font-semibold text-slate-600 hover:underline">{{ __('proforma.ui.form_ajouter_ligne') }}</button>
        </div>

        <div class="flex flex-wrap justify-end gap-2 pt-2">
          <button type="button" wire:click="fermerModales" class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
          <button type="submit" class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 font-semibold">{{ __('proforma.ui.form_enregistrer') }}</button>
          <button type="button" wire:click="enregistrer(true)" class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('proforma.ui.form_emettre') }}</button>
        </div>
      </form>
    </x-pwa.modale>
  @endif

  @if ($etatFormulaire === 'annulation')
    <x-pwa.modale :titre="__('proforma.ui.annulation_titre')" largeur="480px" fermer="fermerModales">
      <form wire:submit.prevent="confirmerAnnulation" class="space-y-4">
        <div>
          <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('proforma.ui.annulation_motif') }} <span class="text-red-500">*</span></label>
          <input type="text" wire:model="motifAnnulation" class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm">
          @error('motifAnnulation') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>
        <div class="flex justify-end gap-2 pt-2">
          <button type="button" wire:click="fermerModales" class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
          <button type="submit" class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('proforma.ui.annuler') }}</button>
        </div>
      </form>
    </x-pwa.modale>
  @endif

  @if ($etatFormulaire === 'conversion')
    <x-pwa.modale :titre="__('proforma.ui.conversion_titre')" largeur="480px" fermer="fermerModales">
      <p class="text-sm text-slate-600">{{ __('proforma.ui.conversion_message') }}</p>
      @if (optional($proformas->firstWhere('id', $cibleId))->estExpiree())
        <p class="text-sm text-amber-700 mt-2">{{ __('proforma.ui.conversion_expiree') }}</p>
      @endif
      <div class="flex justify-end gap-2 pt-4">
        <button type="button" wire:click="fermerModales" class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="confirmerConversion" class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('proforma.ui.conversion_confirmer') }}</button>
      </div>
    </x-pwa.modale>
  @endif
</div>
