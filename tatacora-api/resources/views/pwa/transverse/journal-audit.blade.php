@php
    use App\Pwa\Livewire\Transverse\JournalAudit;
@endphp
<div class="contents">

  @include('pwa.partials.barre-superieure')
  

  <div class="flex flex-1 overflow-hidden">
    @include('pwa.partials.menu-lateral')
    <main class="flex-1 overflow-y-auto">
      <div class="max-w-[1440px] mx-auto p-5 lg:p-8">

        <div class="mb-5">
          <div class="flex items-center gap-2.5">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--navy)" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/><path stroke-linecap="round" stroke-linejoin="round" d="M14 2v6h6"/></svg>
            <h1 class="text-lg lg:text-xl font-bold" style="color:var(--navy)">{{ __('pwa.journal_audit.titre') }}</h1>
          </div>
          <p class="text-[15px] text-slate-500 mt-1.5">{{ __('pwa.journal_audit.sous_titre') }}</p>
        </div>

        <div class="flex flex-col lg:flex-row gap-3 mb-4">
          <div class="relative flex-1">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#9CA3AF" stroke-width="2" class="absolute left-3.5 top-1/2 -translate-y-1/2"><circle cx="11" cy="11" r="8"/><path stroke-linecap="round" d="M21 21l-4.35-4.35"/></svg>
            <input id="recherche-journal" type="text" wire:model.live.debounce.300ms="recherche" placeholder="{{ __('pwa.journal_audit.recherche') }}" class="champ w-full border border-slate-200 rounded-lg pl-10 pr-4 py-2.5 text-sm bg-white">
          </div>
          <select id="filtre-action-journal" wire:model.live="filtreAction" class="champ text-[15px] border border-slate-200 rounded-lg px-3 py-2.5 bg-white">
            <option value="">{{ __('pwa.journal_audit.toutes_actions') }}</option>
            @foreach ($actions as $uneAction)
              <option value="{{ $uneAction }}">{{ JournalAudit::ACTIONS[$uneAction]['libelle'] ?? $uneAction }}</option>
            @endforeach
          </select>
          {{--
              Le maître pose ici un bouton « Réinitialiser les données de
              démo ». Il n'est PAS rendu — voir le bloc de dérogation du
              composant, et le panneau de refus sous le tableau.
          --}}
        </div>

        <div class="bg-white rounded-xl border border-slate-200 overflow-hidden">
          <div class="overflow-x-auto">
            <table class="w-full text-sm">
              <thead class="bg-[var(--navy)]">
                <tr class="text-left text-[11px] font-semibold text-white/90 uppercase tracking-wide">
                  <th class="px-5 py-3">{{ __('pwa.journal_audit.col_utilisateur') }}</th>
                  <th class="px-5 py-3">{{ __('pwa.journal_audit.col_action') }}</th>
                  <th class="px-5 py-3">{{ __('pwa.journal_audit.col_detail') }}</th>
                  <th class="px-5 py-3">{{ __('pwa.journal_audit.col_date') }}</th>
                  <th class="px-5 py-3">{{ __('pwa.journal_audit.col_heure') }}</th>
                  <th class="px-5 py-3">{{ __('pwa.journal_audit.col_poste') }}</th>
                </tr>
              </thead>
              <tbody id="corps-journal">
                @forelse ($entrees as $entree)
                  @php($habillage = JournalAudit::ACTIONS[$entree->action] ?? null)
                  <tr class="border-t border-slate-100 hover:bg-slate-50">
                    <td class="px-5 py-3 font-medium text-slate-700">
                      {{-- Article 7 : « — » quand la donnée n'existe pas. Une
                           entrée sans utilisateur vient d'un job planifié ou
                           d'une commande console : inventer un compte serait
                           pire que de le dire. --}}
                      {{ $entree->utilisateur?->login ?? '—' }}
                    </td>
                    <td class="px-5 py-3">
                      @if ($habillage !== null)
                        <span class="text-[15px] font-semibold px-2.5 py-1 rounded" style="background:{{ $habillage['fond'] }};color:{{ $habillage['texte'] }}">{{ $habillage['libelle'] }}</span>
                      @else
                        {{-- Action hors du registre connu : rendue EN CLAIR
                             plutôt qu'en pastille muette. Une valeur
                             inattendue doit se voir. --}}
                        <span class="text-[15px] font-semibold px-2.5 py-1 rounded bg-slate-100 text-slate-600 font-mono-tatacora">{{ $entree->action }}</span>
                      @endif
                    </td>
                    <td class="px-5 py-3 text-slate-500">
                      {{-- Le libelle FRANCAIS de la table, jamais son nom
                           technique — registre `pwa.journal_audit.tables`,
                           indexe ici en PHP, pas par une cle __() concatenee.

                           ⚠ Le separateur n'est PAS un tiret cadratin : cette
                           colonne partage sa ligne avec les cellules
                           « utilisateur » et « poste », dont le tiret cadratin
                           signale une donnee ABSENTE (Article 7). Un second
                           sens pour le meme caractere rendrait le decompte de
                           donnees manquantes illisible. --}}
                      {{ $libellesTables[$entree->entite_concernee] ?? $entree->entite_concernee }} :
                      @php($libelleEnregistrement = $libellesEnregistrements[$entree->entite_concernee][$entree->entite_id] ?? null)
                      @if ($libelleEnregistrement !== null)
                        {{ $libelleEnregistrement }}
                      @else
                        {{-- Enregistrement disparu ou table hors registre de
                             resolution : l'identifiant reste, en SECOND
                             (Article 7 — jamais un libelle invente). --}}
                        <span class="font-mono-tatacora text-[13px] text-slate-400">{{ $entree->entite_id }}</span>
                      @endif
                    </td>
                    <td class="px-5 py-3 text-slate-500 font-mono-tatacora text-[15px]">{{ $entree->date_heure?->format('d/m/Y') ?? '—' }}</td>
                    <td class="px-5 py-3 text-slate-500 font-mono-tatacora text-[15px]">{{ $entree->date_heure?->format('H:i:s') ?? '—' }}</td>
                    <td class="px-5 py-3 text-slate-400 text-[15px]">{{ $entree->adresse_poste ?? '—' }}</td>
                  </tr>
                @empty
                  <tr><td colspan="6" class="py-16 text-center text-slate-400 text-sm">{{ __('pwa.journal_audit.vide') }}</td></tr>
                @endforelse
              </tbody>
            </table>
          </div>
        </div>

        <p class="text-[13px] text-slate-400 mt-3">{{ __('pwa.journal_audit.mention_lecture_seule') }}</p>

        @if ($tronque)
          <p class="text-[13px] mt-2" style="color:#78350F">{{ __('pwa.journal_audit.tronque', ['plafond' => JournalAudit::PLAFOND, 'total' => $total]) }}</p>
        @else
          <p class="text-[13px] text-slate-400 mt-2">{{ __('pwa.journal_audit.decompte', ['total' => $total]) }}</p>
        @endif

      </div>
    </main>
  </div>

</div>
