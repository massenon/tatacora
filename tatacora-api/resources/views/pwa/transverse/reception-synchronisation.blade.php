@php
    $t = static fn (string $cle, array $p = []): string => __('synchronisation_journal.ecran.' . $cle, $p);
    $classeIssue = static fn (string $issue): string => match ($issue) {
        'acceptee', 'fusionnee' => 'bg-emerald-50 text-emerald-700',
        'dupliquee', 'conservee' => 'bg-slate-100 text-slate-600',
        'signalee' => 'bg-amber-50 text-amber-700',
        default => 'bg-red-50 text-red-700',
    };
    $texteValeur = static fn (mixed $v): string => match (true) {
        $v === null || $v === '' => '—',
        is_bool($v) => $v ? 'Oui' : 'Non',
        default => (string) $v,
    };
@endphp
<div class="space-y-4" wire:poll.20s>
  @if (! $autorise)
    <div id="reception-acces-refuse" class="rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-800">{{ $t('acces_refuse') }}</div>
  @else
    <div>
      <h2 class="text-base font-bold" style="color:var(--navy)">{{ $t('reception_titre') }}</h2>
      <p class="text-[14px] text-slate-500 mt-1">{{ $t('reception_intro') }}</p>
    </div>

    @if ($refus)
      <div id="reception-refus" class="rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">{{ $refus }}</div>
    @endif
    @if ($confirmation)
      <div id="reception-confirmation" class="rounded-lg border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm text-emerald-800">{{ $confirmation }}</div>
    @endif

    <div id="reception-compteurs" class="grid grid-cols-2 lg:grid-cols-6 gap-3">
      @foreach ([
          'total' => 'compteur_total', 'acceptees' => 'compteur_acceptees', 'a_traiter' => 'compteur_a_traiter',
          'rejetees' => 'compteur_rejetees', 'rejeux' => 'compteur_rejeux', 'signalees' => 'compteur_signalees',
      ] as $cle => $libelle)
        <div class="bg-white rounded-xl border border-slate-200 px-4 py-3" id="compteur-{{ $cle }}">
          <div class="text-[12px] text-slate-500">{{ $t($libelle) }}</div>
          <div class="text-xl font-bold {{ $cle === 'a_traiter' && $compteurs[$cle] > 0 ? 'text-red-700' : '' }}" style="{{ $cle === 'a_traiter' && $compteurs[$cle] > 0 ? '' : 'color:var(--navy)' }}">{{ number_format($compteurs[$cle], 0, ',', ' ') }}</div>
        </div>
      @endforeach
    </div>

    <div class="flex flex-col lg:flex-row flex-wrap gap-3 lg:items-center">
      <select id="filtre-reception-poste" wire:model.live="filtrePoste" class="champ text-[15px] border border-slate-200 rounded-lg px-3 py-2.5 bg-white" aria-label="{{ $t('filtre_poste') }}">
        <option value="">{{ $t('tous_postes') }}</option>
        @foreach ($postes as $unPoste)
          <option value="{{ $unPoste }}">{{ $unPoste }}</option>
        @endforeach
      </select>
      <select id="filtre-reception-table" wire:model.live="filtreTable" class="champ text-[15px] border border-slate-200 rounded-lg px-3 py-2.5 bg-white" aria-label="{{ $t('filtre_table') }}">
        <option value="">{{ $t('toutes_donnees') }}</option>
        @foreach ($tables as $uneTable)
          <option value="{{ $uneTable }}">{{ $journal->libelleTable($uneTable) }}</option>
        @endforeach
      </select>
      <select id="filtre-reception-issue" wire:model.live="filtreIssue" class="champ text-[15px] border border-slate-200 rounded-lg px-3 py-2.5 bg-white" aria-label="{{ $t('filtre_issue') }}">
        <option value="">{{ $t('toutes_issues') }}</option>
        @foreach ($issues as $uneIssue)
          <option value="{{ $uneIssue }}">{{ __('synchronisation_journal.issues.' . $uneIssue) }}</option>
        @endforeach
      </select>
      <select id="filtre-reception-periode" wire:model.live="filtrePeriode" class="champ text-[15px] border border-slate-200 rounded-lg px-3 py-2.5 bg-white" aria-label="{{ $t('filtre_periode') }}">
        <option value="aujourdhui">{{ $t('periode_aujourdhui') }}</option>
        <option value="7j">{{ $t('periode_7j') }}</option>
        <option value="30j">{{ $t('periode_30j') }}</option>
        <option value="toutes">{{ $t('periode_toutes') }}</option>
      </select>
      <label class="flex items-center gap-2 text-sm text-slate-700">
        <input id="filtre-reception-a-traiter" type="checkbox" wire:model.live="filtreATraiter" class="rounded border-slate-300">
        {{ $t('filtre_a_traiter') }}
      </label>
      <button id="bouton-actualiser-reception" type="button" wire:click="actualiser" wire:loading.attr="disabled"
              class="rounded-lg px-4 py-2.5 text-sm font-semibold border border-slate-300 text-slate-700 hover:bg-white lg:ml-auto">{{ $t('actualiser') }}</button>
    </div>

    <div class="bg-white rounded-xl border border-slate-200 overflow-hidden">
      <div class="overflow-x-auto">
        <table class="w-full text-sm">
          <thead class="bg-[var(--navy)]">
            <tr class="text-left text-[11px] font-semibold text-white/90 uppercase tracking-wide">
              <th class="px-4 py-3">{{ $t('col_recu_le') }}</th>
              <th class="px-4 py-3">{{ $t('col_poste') }}</th>
              <th class="px-4 py-3">{{ $t('col_utilisateur') }}</th>
              <th class="px-4 py-3">{{ $t('col_donnee') }}</th>
              <th class="px-4 py-3">{{ $t('col_type') }}</th>
              <th class="px-4 py-3">{{ $t('col_issue') }}</th>
              <th class="px-4 py-3">{{ $t('col_motif') }}</th>
              <th class="px-4 py-3 text-right">{{ $t('col_tentatives') }}</th>
              <th class="px-4 py-3 text-right">{{ $t('col_actions') }}</th>
            </tr>
          </thead>
          <tbody id="corps-reception">
            @forelse ($lignes as $l)
              @php
                  $refusModule = $corrections->moduleRefuse($l, $auteurCourant);
                  $peutAgir = $refusModule === null;
              @endphp
              <tr class="border-t border-slate-100 align-top" wire:key="reception-{{ $l->id }}">
                <td class="px-4 py-3 text-slate-600 whitespace-nowrap">{{ $l->recu_le->format('d/m/Y H:i:s') }}</td>
                <td class="px-4 py-3 font-medium text-slate-700">{{ $l->poste_id }}</td>
                <td class="px-4 py-3 text-slate-600">{{ $l->utilisateur?->login ?? '—' }}</td>
                <td class="px-4 py-3 text-slate-700">{{ $journal->libelleTable($l->table_concernee) }}</td>
                <td class="px-4 py-3 text-slate-600">{{ __('synchronisation_journal.types.' . $l->type_operation) }}</td>
                <td class="px-4 py-3">
                  <span class="text-[11px] px-1.5 py-0.5 rounded font-semibold {{ $classeIssue($l->issue) }}">{{ __('synchronisation_journal.issues.' . $l->issue) }}</span>
                  @if ($l->traitement)
                    <div class="text-[12px] text-slate-500 mt-1">{{ __('synchronisation_journal.traitements.' . $l->traitement) }}</div>
                  @endif
                </td>
                <td class="px-4 py-3 text-slate-600 max-w-[320px]">{{ $l->motif ?? '—' }}</td>
                <td class="px-4 py-3 text-right text-slate-600">{{ $l->tentatives }}</td>
                <td class="px-4 py-3 text-right whitespace-nowrap">
                  <button type="button" wire:click="ouvrirOperation(@js($l->id))" class="text-[13px] px-3 py-1.5 rounded-lg border border-slate-300 text-slate-700 hover:bg-slate-50">{{ $t('detail') }}</button>
                  @if ($peutAgir && $corrections->peutCorriger($l))
                    <button type="button" wire:click="ouvrirCorrection(@js($l->id))" class="text-[13px] px-3 py-1.5 rounded-lg border border-slate-300 text-slate-700 hover:bg-slate-50">{{ $t('corriger') }}</button>
                    <button type="button" wire:click="relancer(@js($l->id))" wire:loading.attr="disabled" class="text-[13px] px-3 py-1.5 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ $t('relancer') }}</button>
                  @endif
                  @if ($peutAgir && $corrections->peutIgnorer($l))
                    <button type="button" wire:click="ouvrirIgnorer(@js($l->id))" class="text-[13px] px-3 py-1.5 rounded-lg border border-slate-300 text-slate-700 hover:bg-slate-50">{{ $t('ignorer') }}</button>
                  @endif
                </td>
              </tr>
            @empty
              <tr><td colspan="9" class="px-5 py-6 text-center text-slate-500">{{ $t('aucune_operation') }}</td></tr>
            @endforelse
          </tbody>
        </table>
      </div>
    </div>

    @if ($total > $lignes->count())
      <div class="text-center">
        <button type="button" wire:click="$set('limite', {{ $limite + 25 }})" class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-white">
          {{ $lignes->count() }} / {{ $total }}
        </button>
      </div>
    @endif

    {{-- Détail d'une opération : la cause, la charge reçue, la prise en charge. --}}
    @if ($detail)
      <x-pwa.modale :titre="$t('detail_titre', ['poste' => $detail->poste_id])" largeur="860px" fermer="fermerOperation">
        <div id="detail-reception" class="space-y-4 text-sm">
          <div class="flex flex-wrap items-center gap-2">
            <span class="text-[11px] px-1.5 py-0.5 rounded font-semibold {{ $classeIssue($detail->issue) }}">{{ __('synchronisation_journal.issues.' . $detail->issue) }}</span>
            <span class="font-semibold text-slate-800">{{ $journal->libelleTable($detail->table_concernee) }}</span>
            <span class="text-slate-500">· {{ __('synchronisation_journal.types.' . $detail->type_operation) }}</span>
          </div>
          <p class="text-slate-500 text-[13px]">{{ $t('detail_recu', ['date' => $detail->recu_le->format('d/m/Y H:i:s'), 'envoyee' => $detail->horodatage_poste?->format('d/m/Y H:i:s') ?? '—']) }}
            @if ($detail->tentatives > 1)
              · {{ $t('detail_envois', ['n' => $detail->tentatives, 'date' => $detail->derniere_tentative_le->format('d/m/Y H:i:s')]) }}
            @endif
          </p>

          @if ($detail->cause)
            <div id="detail-cause" class="rounded-lg border {{ in_array($detail->issue, ['rejetee', 'erreur', 'conflit'], true) ? 'border-red-200 bg-red-50 text-red-800' : 'border-slate-200 bg-slate-50 text-slate-700' }} px-4 py-3">
              <div class="font-semibold mb-1">{{ $t('detail_cause') }}</div>
              <div>{{ $detail->cause }}</div>
            </div>
          @endif

          @if ($detail->motif && $detail->motif !== $detail->cause)
            <div class="text-[13px] text-slate-600"><span class="font-semibold">{{ $t('detail_motif_poste') }}</span> : {{ $detail->motif }}</div>
          @endif

          @if (! empty($detail->details['erreurs']))
            <div>
              <div class="font-semibold text-slate-700 mb-1">{{ $t('detail_erreurs') }}</div>
              <ul class="list-disc pl-5 text-slate-600">
                @foreach ($detail->details['erreurs'] as $champ => $messages)
                  <li>{{ $journal->libelleChamp((string) $champ) }} : {{ implode(' ', (array) $messages) }}</li>
                @endforeach
              </ul>
            </div>
          @endif

          @if (! empty($detail->details['anomalies']))
            <div>
              <div class="font-semibold text-slate-700 mb-1">{{ $t('detail_signalements') }}</div>
              <ul class="list-disc pl-5 text-slate-600">
                @foreach ($detail->details['anomalies'] as $code)
                  <li>{{ $journal->libelleAnomalie((string) $code) }}</li>
                @endforeach
              </ul>
            </div>
          @endif

          @if (! empty($detail->details['entites_en_conflit']))
            <div class="text-[13px] text-slate-600"><span class="font-semibold">{{ $t('detail_conflits') }}</span> : {{ implode(', ', (array) $detail->details['entites_en_conflit']) }}</div>
          @endif

          @if ($detail->traitement && $detail->traite_par)
            <div class="rounded-lg border border-slate-200 bg-slate-50 px-4 py-3 text-[13px] text-slate-700">
              <div class="font-semibold">{{ $t('detail_traitement') }} : {{ __('synchronisation_journal.traitements.' . $detail->traitement) }}</div>
              <div>{{ $t('detail_traite_par', ['nom' => $detail->traitePar?->login ?? '—', 'date' => $detail->traite_le?->format('d/m/Y H:i:s') ?? '—']) }}</div>
              @if ($detail->motif_traitement)
                <div>{{ $t('detail_motif_traitement', ['motif' => $detail->motif_traitement]) }}</div>
              @endif
            </div>
          @endif

          @if ($champsDetail !== [])
            <div>
              <div class="font-semibold text-slate-700 mb-1">{{ $detail->payload_corrige ? $t('detail_corrigee') : $t('detail_charge') }}</div>
              <div class="rounded-lg border border-slate-200 overflow-hidden">
                <table class="w-full text-[13px]">
                  <tbody>
                    @foreach ($champsDetail as $champ)
                      <tr class="border-t border-slate-100 first:border-t-0">
                        <td class="px-3 py-1.5 text-slate-500 w-1/3">{{ $champ['libelle'] }}</td>
                        <td class="px-3 py-1.5 text-slate-800 break-words">{{ $texteValeur($champ['valeur']) }}</td>
                      </tr>
                    @endforeach
                  </tbody>
                </table>
              </div>
            </div>
          @endif

          @if ($auteurCourant->estAdministrateur() && ! empty($detail->details['message']))
            <div class="text-[12px] text-slate-500 break-words">{{ $detail->details['message'] }}</div>
          @endif
        </div>
        <x-slot:pied>
          <button type="button" wire:click="fermerOperation" class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ $t('fermer') }}</button>
        </x-slot:pied>
      </x-pwa.modale>
    @endif

    {{-- Corriger : formulaire pré-rempli par la charge reçue. --}}
    @if ($correction)
      <x-pwa.modale :titre="$t('corriger_titre')" :sousTitre="$journal->libelleTable($correction->table_concernee)" largeur="760px" fermer="fermerCorrection">
        <div id="formulaire-correction" class="space-y-3">
          <p class="text-[13px] text-slate-500">{{ $t('corriger_aide') }}</p>
          @if ($correction->cause)
            <div class="rounded-lg border border-red-200 bg-red-50 px-4 py-2.5 text-[13px] text-red-800">{{ $correction->cause }}</div>
          @endif
          @if ($retourCorrection)
            <div id="retour-correction" class="rounded-lg border border-red-200 bg-red-50 px-4 py-2.5 text-sm text-red-700">{{ $retourCorrection }}</div>
          @endif
          <div class="space-y-2">
            @foreach ($champs as $indice => $champ)
              <label class="flex flex-col lg:flex-row lg:items-center gap-1 lg:gap-3" wire:key="champ-{{ $indice }}">
                <span class="lg:w-1/3 text-[13px] text-slate-600">{{ $champ['libelle'] }}</span>
                @if ($champ['modifiable'])
                  <input type="text" wire:model="saisie.{{ $indice }}" class="champ flex-1 border border-slate-200 rounded-lg px-3 py-2 text-sm bg-white">
                @else
                  <span class="flex-1 text-sm text-slate-500 break-words">{{ $texteValeur($champ['valeur']) }} <span class="text-[11px] text-slate-400">({{ $t('champ_lecture_seule') }})</span></span>
                @endif
              </label>
            @endforeach
          </div>
        </div>
        <x-slot:pied>
          <button type="button" wire:click="fermerCorrection" class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ $t('corriger_annuler') }}</button>
          <button id="enregistrer-correction" type="button" wire:click="enregistrerCorrection" wire:loading.attr="disabled" class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ $t('corriger_enregistrer') }}</button>
        </x-slot:pied>
      </x-pwa.modale>
    @endif

    {{-- Marquer comme traité : motif exigé et tracé. --}}
    @if ($ignorer)
      <x-pwa.modale :titre="$t('ignorer_titre')" largeur="520px" fermer="fermerIgnorer">
        <div id="formulaire-ignorer" class="space-y-3">
          <p class="text-[13px] text-slate-500">{{ $t('ignorer_aide') }}</p>
          @if ($retourIgnorer)
            <div id="retour-ignorer" class="rounded-lg border border-red-200 bg-red-50 px-4 py-2.5 text-sm text-red-700">{{ $retourIgnorer }}</div>
          @endif
          <label class="block text-[13px] text-slate-600">{{ $t('ignorer_motif') }}
            <textarea wire:model="motifIgnorer" rows="3" class="champ mt-1 w-full border border-slate-200 rounded-lg px-3 py-2 text-sm bg-white"></textarea>
          </label>
        </div>
        <x-slot:pied>
          <button type="button" wire:click="fermerIgnorer" class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ $t('corriger_annuler') }}</button>
          <button id="confirmer-ignorer" type="button" wire:click="ignorer" class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ $t('ignorer_confirmer') }}</button>
        </x-slot:pied>
      </x-pwa.modale>
    @endif
  @endif
</div>
