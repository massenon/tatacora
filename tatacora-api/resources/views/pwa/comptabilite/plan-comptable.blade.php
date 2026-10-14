{{--
    Plan Comptable — maître : `prototype_v2/pages/m10-plan-comptable.html`.

    Conteneur `max-w-[1100px] mx-auto p-5 lg:p-8` (l.18), en-tête de page
    (l.20-30), barre de huit boutons de classe (l.32), puis le tableau à quatre
    colonnes sur fond `var(--navy)` (l.34-42).

    Écarts, tous motivés dans `App\Pwa\Livewire\Comptabilite\PlanComptable` :
    le décompte de comptes est réel et non écrit en dur, la nature nulle rend
    « — », et les classes 8 et 9 — que le maître n'a aucun bouton pour
    atteindre — sont comptées sous le tableau au lieu d'être tues.

    Aucun bouton « + Créer un compte » : le maître le pose sur le HUB
    (`m10-syscohada.js` l.348), pas sur cette page, et c'est de toute façon une
    écriture.
--}}
@php
    use App\Domain\Comptabilite\Models\CompteComptable;

    // Les sept libellés de classe du maître, l.62-63, au mot près.
    $classesLibelle = [
        '1' => 'Classe 1 — Capitaux',
        '2' => 'Classe 2 — Immobilisations',
        '3' => 'Classe 3 — Stocks',
        '4' => 'Classe 4 — Tiers',
        '5' => 'Classe 5 — Trésorerie',
        '6' => 'Classe 6 — Charges',
        '7' => 'Classe 7 — Produits',
    ];

    // Les quatre pastilles du maître, l.64-65 — mêmes couleurs.
    $natureBadge = [
        'actif' => ['#E8EEFD', '#1D4ED8'],
        'passif' => ['#FDF3E0', '#B8891E'],
        'charge' => ['#FDECEC', '#C62828'],
        'produit' => ['#E8F5E9', '#2E7D32'],
    ];
@endphp
<div class="contents">

  @include('pwa.partials.barre-superieure')
  

  <div class="flex flex-1 overflow-hidden">
    @include('pwa.partials.menu-lateral')
    <main class="flex-1 overflow-y-auto">
      <div class="max-w-[1100px] mx-auto p-5 lg:p-8">

        @include('pwa.comptabilite.partials.en-tete', [
            'tailleRetour' => 'text-[15px]',
            'icone' => '<path stroke-linecap="round" stroke-linejoin="round" d="M12 7v14"/><path stroke-linecap="round" stroke-linejoin="round" d="M3 18a1 1 0 01-1-1V4a1 1 0 011-1h5a4 4 0 014 4 4 4 0 014-4h5a1 1 0 011 1v13a1 1 0 01-1 1h-6a3 3 0 00-3 3 3 3 0 00-3-3z"/>',
            'titre' => 'Plan Comptable',
            'sousTitre' => 'Comptes SYSCOHADA révisé (Classes 1 à 7) — <span class="font-mono-tatacora">' . e((string) $plan->total) . '</span> comptes',
        ])

        {{-- Les huit boutons du maître (l.57-61) : « Toutes les classes », puis les sept classes. --}}
        <div class="flex flex-wrap gap-2 mb-4">
          <a href="{{ route('pwa.comptabilite.plan-comptable') }}" wire:navigate
             class="px-3 py-2 rounded-lg text-[15px] font-semibold border {{ $classeActive === null ? 'bg-[var(--navy)] text-white border-slate-200' : 'border-slate-200 bg-white text-slate-500' }}">
            Toutes les classes
          </a>
          @foreach (CompteComptable::CLASSES_ECRAN as $classe)
            <a href="{{ route('pwa.comptabilite.plan-comptable', ['classe' => $classe]) }}" wire:navigate
               class="px-3 py-2 rounded-lg text-[15px] font-semibold border {{ $classeActive === $classe ? 'bg-[var(--navy)] text-white border-slate-200' : 'border-slate-200 bg-white text-slate-500' }}">
              {{ $classesLibelle[$classe] }}
            </a>
          @endforeach
        </div>

        {{-- Recherche par table (décision du Product Owner, 01/09/2026) —
             numéro de compte ou libellé, filtrage SERVEUR réel
             (`PlanComptableService::consulter()`). Sûre sur cet écran, à la
             différence des quatre autres états M10 : voir le docblock de
             tête pour pourquoi.
             Bloc AJOUTÉ, absent du maître (page statique, sans moteur CRUD) :
             structure-ajout:m10-plan-comptable.html#div-07898828 --}}
        <div class="relative mb-4 max-w-md">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#9CA3AF" stroke-width="2" class="absolute left-3.5 top-1/2 -translate-y-1/2"><circle cx="11" cy="11" r="8"/><path stroke-linecap="round" d="M21 21l-4.35-4.35"/></svg>
          <input type="search" wire:model.live.debounce.300ms="recherche"
                 placeholder="{{ __('comptabilite_pwa.plan_recherche') }}"
                 class="champ w-full border border-slate-200 rounded-lg pl-10 pr-4 py-2.5 text-sm bg-white">
        </div>

        <div class="bg-white rounded-xl border border-slate-200 overflow-hidden">
          <div class="overflow-x-auto">
            <table class="w-full text-sm">
              <thead class="bg-[var(--navy)]"><tr class="text-left text-[11px] font-semibold text-white/90 uppercase tracking-wide">
                <th class="px-4 py-3">N° Compte</th><th class="px-4 py-3">Libellé</th><th class="px-4 py-3">Classe</th><th class="px-4 py-3">Nature</th>
              </tr></thead>
              <tbody>
                @forelse ($plan->comptes as $compte)
                  <tr class="border-t border-slate-100 hover:bg-slate-50">
                    <td class="px-4 py-2.5 font-mono-tatacora text-[15px] text-slate-700">{{ $compte->numero_compte }}</td>
                    <td class="px-4 py-2.5 text-slate-700">{{ $compte->libelle }}</td>
                    <td class="px-4 py-2.5 text-slate-500">{{ $compte->classe }}</td>
                    <td class="px-4 py-2.5">
                      @php($badge = $natureBadge[$compte->nature] ?? null)
                      @if ($compte->nature === null)
                        {{-- Article 7 : « — » quand la donnée n'existe pas. Le maître
                             indexe un badge de couleur sur cette valeur (l.80) : une
                             nature nulle n'y produit rien du tout, donc une case vide
                             indiscernable d'une colonne mal alignée. --}}
                        <span class="text-slate-300">—</span>
                      @elseif ($badge !== null)
                        <span class="text-[15px] font-semibold px-2.5 py-1 rounded" style="background:{{ $badge[0] }};color:{{ $badge[1] }}">{{ $compte->nature }}</span>
                      @else
                        {{-- Nature hors des quatre du maître : rendue en clair plutôt
                             qu'en badge muet — une valeur inattendue doit se voir. --}}
                        <span class="text-[15px] font-semibold px-2.5 py-1 rounded bg-slate-100 text-slate-600">{{ $compte->nature }}</span>
                      @endif
                    </td>
                  </tr>
                @empty
                  <tr><td colspan="4" class="py-14 text-center text-slate-400 text-sm">Aucun compte ne correspond.</td></tr>
                @endforelse
              </tbody>
            </table>
          </div>
        </div>

        @if ($plan->comptesParClasseHorsEcran !== [])
          <div class="rounded-xl p-3.5 mt-4" style="background:#FFFBEB;border:1px solid #FDE68A">
            <p class="text-[13px] font-bold" style="color:#78350F">{{ __('pwa.comptabilite.hors_ecran_titre') }}</p>
            <p class="text-[13px] mt-1" style="color:#78350F">{{ __('pwa.comptabilite.hors_ecran_detail') }}</p>
            <ul class="list-disc pl-5 mt-1.5">
              @foreach ($plan->comptesParClasseHorsEcran as $classeHorsEcran => $nombre)
                <li class="text-[13px]" style="color:#78350F">Classe {{ $classeHorsEcran }} — {{ $nombre }} compte(s)</li>
              @endforeach
            </ul>
          </div>
        @endif

        @if ($plan->sansNature > 0)
          <p class="text-[13px] text-slate-400 mt-4">{{ __('pwa.comptabilite.sans_nature', ['nombre' => $plan->sansNature]) }}</p>
        @endif

      </div>
    </main>
  </div>

</div>
