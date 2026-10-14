{{--
    RÔLES & PERMISSIONS — maître : `prototype_v2/pages/roles-permissions.html`.

    Édition RÉELLE depuis le 01/09/2026 (directive du Product Owner) : « +
    Nouveau rôle », « Modifier les droits » et « Rétablir le socle du CdCF »
    écrivent réellement, via `RolePermissionService`. Voir le docblock du
    composant pour ce qui reste hors périmètre (compte démo, niveau dérivé).

    L'en-tête `<thead class="bg-[var(--navy)]">` (l.106) est DÉJÀ la classe
    canonique du 01/09/2026 — byte pour byte identique au maître
    (`roles-permissions.html` l.154-160), pas une conséquence du lot. EXCLU de
    la barre de recherche par table : cette MATRICE porte les QUATORZE modules
    × tous les rôles, un registre fermé et complet dont le maître lui-même ne
    propose aucun filtre — chercher « quel module a quel droit » suppose de
    voir la grille entière, pas une ligne isolée.
--}}
@php
    use App\Pwa\Livewire\Transverse\RolesPermissions;
@endphp
<div class="contents">

  @include('pwa.partials.barre-superieure')


  <div class="flex flex-1 overflow-hidden">
    @include('pwa.partials.menu-lateral')
    <main class="flex-1 overflow-y-auto">
      <div class="max-w-[1440px] mx-auto p-5 lg:p-8">

        {{-- Le SQUELETTE du maître, à l'identique : bloc de titre `mb-6`,
             PUIS une rangée de boutons `flex flex-wrap items-center gap-2
             mb-4` — le maître porte lui-même cette rangée. La version
             précédente fusionnait les deux dans un conteneur
             `justify-between` absent du maître (recul mesuré par
             t-structure, corrigé le 01/09/2026). --}}
        <div class="mb-6">
          <div class="flex items-center gap-2.5">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--navy)" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg>
            <h1 class="text-lg lg:text-xl font-bold" style="color:var(--navy)">{{ __('pwa.roles.titre') }}</h1>
          </div>
          <p class="text-[15px] text-slate-500 mt-1.5">{{ __('pwa.roles.sous_titre') }}</p>

        {{-- Les TROIS messages de cet ecran — « role cree », « droits
             enregistres », « socle retabli » — etaient flashes et jamais
             rendus (03/09/2026). Sur l'ecran RBAC, precisement, ou l'on doit
             savoir si le changement de droits a pris : sans retour, on
             reenregistre, ou l'on croit avoir echoue. Trouve par
             `ToastDeSuccesRenduTest`, que mon propre balayage manuel avait
             manque — il flashe par le delegue `terminerFormulaire()`, pas en
             direct, et un grep sur la cle ne le voyait pas. --}}
        @include('pwa.partials.toast-succes')
        </div>

        @if ($peutEcrire)
          {{-- L'ORDRE et le CONTENU du maître : + Nouveau rôle, Rétablir,
               espaceur flex-1, badge d'état de la matrice (« Conforme au
               socle » DÉRIVÉ, jamais figé). --}}
          <div class="flex flex-wrap items-center gap-2 mb-4">
            <button type="button" wire:click="ouvrirFormulaireRole"
                    class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold hover:opacity-90">{{ __('pwa.roles.bouton_nouveau_role') }}</button>
            <button type="button" wire:click="ouvrirRetablirSocle"
                    class="text-[13px] px-3.5 py-2 rounded-lg border border-slate-300 bg-white hover:bg-slate-50">{{ __('pwa.roles.bouton_retablir_socle') }}</button>
            <div class="flex-1"></div>
            <span class="text-[12px] {{ $matriceConformeAuSocle ? 'text-emerald-700' : 'text-amber-700' }}">
              {{ $matriceConformeAuSocle ? __('pwa.roles.badge_conforme') : __('pwa.roles.badge_amendee') }}
            </span>
          </div>
        @endif

        <div class="flex flex-wrap items-center gap-2 mb-4">
          <span id="etat-matrice" class="text-[12px] text-slate-400">{{ __('pwa.roles.total_comptes', ['nombre' => $comptes]) }}</span>
        </div>

        {{-- Cartes de rôles --}}
        <div class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4 mb-8" id="grille-roles">
          @forelse ($cartes as $carte)
            <div class="bg-white rounded-xl border border-slate-200 p-4">
              <div class="flex items-start gap-3 mb-3">
                <div class="w-10 h-10 rounded-full bg-[var(--navy)] text-white font-bold text-[15px] flex items-center justify-center shrink-0">{{ $carte['initiales'] }}</div>
                <div class="min-w-0 flex-1">
                  <p class="text-sm font-bold text-slate-800">{{ $carte['libelle'] }}</p>
                  {{-- Article 7 : « 0 » quand la valeur vaut zéro se dit
                       autrement ici — le maître pose déjà sa propre phrase
                       « Aucun compte rattaché » pour ce cas (l.131), en ambre.
                       On la reprend telle quelle. --}}
                  @if ($carte['comptes'] === 0)
                    <p class="text-[13px] text-slate-400 truncate"><span class="text-amber-600">{{ __('pwa.roles.carte_aucun_compte') }}</span></p>
                  @else
                    <p class="text-[13px] text-slate-400 truncate">{{ __('pwa.roles.carte_comptes', ['nombre' => $carte['comptes']]) }}</p>
                  @endif
                </div>
              </div>
              <div class="flex gap-2 text-[13px] mb-2.5">
                <span class="flex-1 text-center bg-green-50 text-green-700 font-bold rounded-lg py-1.5">{{ __('pwa.roles.carte_complet', ['nombre' => $carte['complet']]) }}</span>
                <span class="flex-1 text-center bg-blue-50 text-blue-700 font-bold rounded-lg py-1.5">{{ __('pwa.roles.carte_lecture', ['nombre' => $carte['lecture']]) }}</span>
              </div>

              {{-- Badge « conforme »/« amendée » — DÉRIVÉ, jamais posé
                   (`RolePermissionService::estConformeAuSocle()`). Absent pour
                   un rôle hors socle : « conforme » n'a pas de sens pour lui. --}}
              @if ($carte['conforme'] === true)
                <span class="inline-block text-[11px] px-2 py-0.5 rounded bg-emerald-50 text-emerald-700 mb-2.5">{{ __('pwa.roles.badge_conforme') }}</span>
              @elseif ($carte['conforme'] === false)
                <span class="inline-block text-[11px] px-2 py-0.5 rounded bg-amber-50 text-amber-700 mb-2.5">{{ __('pwa.roles.badge_amendee') }}</span>
              @endif

              @if ($peutEcrire)
                <button type="button" wire:click="ouvrirFormulaireDroits('{{ $carte['id'] }}')"
                        class="w-full text-[13px] px-3 py-2 rounded-lg border border-slate-300 hover:bg-slate-50 font-semibold text-slate-700">{{ __('pwa.roles.bouton_modifier_droits') }}</button>
              @endif
              {{-- Le maître pose ici aussi « Supprimer ». Non rendu : un rôle
                   porté par un compte ne se supprime pas (`BasePolicy::
                   delete()` rend false pour les vingt policies), et aucune
                   suppression n'existe dans ce dépôt. --}}
            </div>
          @empty
            <div class="md:col-span-2 xl:col-span-3 rounded-xl p-4" style="background:#FFFBEB;border:1px solid #FDE68A">
              <p class="text-[13px]" style="color:#78350F">{{ __('pwa.roles.referentiel_vide') }}</p>
            </div>
          @endforelse
        </div>

        {{-- Matrice complète --}}
        <div class="bg-white rounded-xl border border-slate-200 overflow-hidden">
          <div class="px-5 py-4 border-b border-slate-100 flex items-center justify-between">
            <h2 class="text-sm font-bold text-slate-700">{{ __('pwa.roles.matrice_titre') }}</h2>
            <div class="flex items-center gap-3 text-[13px] text-slate-500">
              <span class="flex items-center gap-1.5"><span class="w-3 h-3 rounded bg-green-100 border border-green-300"></span>{{ __('pwa.roles.legende_complet') }}</span>
              <span class="flex items-center gap-1.5"><span class="w-3 h-3 rounded bg-blue-100 border border-blue-300"></span>{{ __('pwa.roles.legende_lecture') }}</span>
              <span class="flex items-center gap-1.5"><span class="w-3 h-3 rounded bg-slate-100 border border-slate-300"></span>{{ __('pwa.roles.legende_aucun') }}</span>
            </div>
          </div>
          <div class="overflow-x-auto">
            <table class="w-full text-[15px]" id="table-matrice">
              <thead class="bg-[var(--navy)]">
                <tr>
                  <th class="px-4 py-3 text-left text-white sticky left-0 bg-[var(--navy)] z-10">{{ __('pwa.roles.col_module') }}</th>
                  @foreach ($cartes as $carte)
                    {{-- Le maître pose ici un `<button>` « Modifier les droits
                         de ce rôle ». L'en-tête reste un libellé : le geste
                         d'édition vit sur la carte (voir le docblock du
                         composant — un seul chemin vers la même écriture). --}}
                    <th class="px-3 py-3 text-center text-white font-semibold whitespace-nowrap">{{ $carte['libelle'] }}</th>
                  @endforeach
                </tr>
              </thead>
              <tbody>
                @foreach (RolesPermissions::MODULES as $code => $libelleModule)
                  @php($impair = $loop->index % 2 === 1)
                  <tr class="{{ $impair ? 'bg-slate-50/50' : '' }} border-t border-slate-100">
                    <td class="px-4 py-2.5 font-semibold text-slate-700 sticky left-0 {{ $impair ? 'bg-slate-50' : 'bg-white' }}">{{ $libelleModule }}</td>
                    @foreach ($cartes as $carte)
                      @php($niveau = $matrice[$carte['code']][$code] ?? '-')
                      <td class="px-3 py-2.5 text-center">
                        <span class="inline-block w-6 h-6 leading-6 rounded font-bold {{ $niveau === 'C' ? 'bg-green-50 text-green-700' : ($niveau === 'L' ? 'bg-blue-50 text-blue-700' : 'bg-slate-50 text-slate-300') }}">{{ $niveau }}</span>
                      </td>
                    @endforeach
                  </tr>
                @endforeach
              </tbody>
            </table>
          </div>
        </div>

      </div>
    </main>
  </div>

  {{-- ==================================== MODALE — NOUVEAU RÔLE --}}
  @if ($etatFormulaire === 'nouveau_role')
    <x-pwa.modale :titre="__('pwa.roles.nouveau_role_titre')" largeur="440px">
      <div class="groupe-champ">
        <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('pwa.roles.nouveau_role_libelle') }} <span class="text-red-500">*</span></label>
        <input type="text" wire:model="libelleRoleSaisi" placeholder="{{ __('pwa.roles.nouveau_role_libelle_invite') }}"
               class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
        @error('libelleRoleSaisi') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
      </div>
      <div class="groupe-champ">
        <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('pwa.roles.nouveau_role_description') }}</label>
        <input type="text" wire:model="descriptionRoleSaisi"
               class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
        @error('descriptionRoleSaisi') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
      </div>

      <x-slot:pied>
        <button type="button" wire:click="fermerModales"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="enregistrerRole"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('notifications_pwa.enregistrer') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  {{-- ==================================== MODALE — MODIFIER LES DROITS --}}
  @if ($etatFormulaire === 'droits')
    <x-pwa.modale :titre="__('pwa.roles.modifier_droits_titre', ['role' => $roleEnEditionLibelle])"
                  :sousTitre="__('pwa.roles.modifier_droits_sous_titre')" largeur="480px">
      <div class="max-h-[55vh] overflow-y-auto divide-y divide-slate-100">
        @foreach (RolesPermissions::MODULES as $code => $libelleModule)
          <div class="flex items-center justify-between py-2 gap-3">
            <span class="text-[13px] text-slate-700">{{ $libelleModule }}</span>
            @if ($code === 'ROLES' && $roleEnEditionCode === 'administrateur')
              <span class="inline-flex items-center gap-1.5 text-[12px] text-slate-400" title="{{ __('pwa.roles.verrou_administrateur') }}">
                <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="11" width="18" height="11" rx="2"/><path stroke-linecap="round" d="M7 11V7a5 5 0 0110 0v4"/></svg>
                C
              </span>
            @else
              <select wire:model="niveauxSaisis.{{ $code }}" class="text-[13px] border border-slate-300 rounded-lg px-2.5 py-1.5">
                <option value="C">C</option>
                <option value="L">L</option>
                <option value="-">—</option>
              </select>
            @endif
          </div>
        @endforeach
      </div>
      @error('niveauxSaisis') <p class="text-[12px] text-red-600 mt-2">{{ $message }}</p> @enderror

      <x-slot:pied>
        {{-- « Tout retirer » : le bouton du maître (modale-role) — pose la
             saisie à « - » partout, verrou administrateur/ROLES excepté. --}}
        <button type="button" wire:click="toutRetirer"
                class="text-[13px] px-4 py-2 rounded-lg border border-red-200 text-red-700 hover:bg-red-50 mr-auto">{{ __('pwa.roles.tout_retirer') }}</button>
        <button type="button" wire:click="fermerModales"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="enregistrerDroits"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('notifications_pwa.enregistrer') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  {{-- ==================================== MODALE — RÉTABLIR LE SOCLE --}}
  @if ($etatFormulaire === 'retablir_socle')
    <x-pwa.modale :titre="__('pwa.roles.retablir_socle_titre')" largeur="440px">
      <p class="text-sm text-slate-600">{{ __('pwa.roles.retablir_socle_texte') }}</p>

      <x-slot:pied>
        <button type="button" wire:click="fermerModales"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="retablirSocle"
                class="text-[13px] px-4 py-2 rounded-lg text-white font-semibold" style="background:var(--erreur)">{{ __('pwa.roles.retablir_socle_confirmer') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

</div>
