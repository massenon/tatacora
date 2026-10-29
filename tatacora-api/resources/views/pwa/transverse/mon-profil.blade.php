@php
    use App\Pwa\Livewire\Transverse\JournalAudit;
    use App\Pwa\Livewire\Transverse\MonProfil;
@endphp
<div class="contents">

  @include('pwa.partials.barre-superieure')
  

  <div class="flex flex-1 overflow-hidden">
    @include('pwa.partials.menu-lateral')
    <main class="flex-1 overflow-y-auto">
      <div class="max-w-[1440px] mx-auto p-5 lg:p-8">

        <div class="mb-6">
          <div class="flex items-center gap-2.5">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--navy)" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M20 21v-2a4 4 0 00-4-4H8a4 4 0 00-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>
            <h1 class="text-lg lg:text-xl font-bold" style="color:var(--navy)">{{ __('pwa.profil.titre') }}</h1>
          </div>
          <p class="text-[15px] text-slate-500 mt-1.5">{{ __('pwa.profil.sous_titre') }}</p>
        </div>

        @include('pwa.partials.toast-succes')

        {{-- ============================= Métadonnées de session ============= --}}
        <section class="bg-white rounded-xl border border-slate-200 p-5 mb-5">
          <div class="flex items-start gap-4 mb-4">
            <div id="avatar-profil" class="w-14 h-14 rounded-full flex items-center justify-center text-white font-bold text-lg shrink-0" style="background:var(--gold)">{{ \App\Pwa\Support\MenuLateral::initiales($utilisateur) }}</div>
            <div class="min-w-0">
              {{-- Le maître affiche `session.nom` ; le schéma n'en porte pas
                   sur `utilisateurs`. Le login réel tient la place, comme dans
                   la barre supérieure : une valeur vraie plutôt qu'un nom
                   fabriqué. --}}
              <p id="nom-profil" class="text-base font-bold" style="color:var(--navy)">{{ $utilisateur?->login ?? '—' }}</p>
              <p id="role-profil" class="text-[13px] text-slate-500">{{ \Illuminate\Support\Str::ucfirst($utilisateur?->role?->libelle ?? '—') }}</p>
            </div>
          </div>

          <h2 class="text-[13px] font-bold tracking-wider text-slate-400 mb-2.5">{{ __('pwa.profil.metadonnees') }}</h2>
          <div class="grid grid-cols-1 sm:grid-cols-3 gap-3">
            <div class="rounded-lg border border-slate-100 bg-slate-50 px-3.5 py-3">
              <p class="text-[12px] text-slate-500">{{ __('pwa.profil.derniere_connexion') }}</p>
              {{-- Article 7 : « — » quand la donnée n'existe pas. Un compte
                   jamais connecté a `derniere_connexion` à NULL ; écrire une
                   date là serait inventer une connexion. --}}
              <p id="meta-connexion" class="text-[15px] font-semibold font-mono-tatacora mt-0.5" style="color:var(--navy)">{{ $utilisateur?->derniere_connexion?->format('d/m/Y H:i') ?? '—' }}</p>
            </div>
            <div class="rounded-lg border border-slate-100 bg-slate-50 px-3.5 py-3">
              <p class="text-[12px] text-slate-500">{{ __('pwa.profil.adresse_ip') }}</p>
              <p id="meta-ip" class="text-[15px] font-semibold font-mono-tatacora mt-0.5" style="color:var(--navy)">{{ $adressePoste ?? '—' }}</p>
            </div>
            <div class="rounded-lg border border-slate-100 bg-slate-50 px-3.5 py-3">
              <p class="text-[12px] text-slate-500">{{ __('pwa.profil.statut_compte') }}</p>
              {{-- Statut RÉEL, pas « Actif » écrit en dur (Article 6). Un
                   statut hors du registre est rendu en clair. --}}
              <p class="text-[15px] font-semibold mt-0.5" style="color:{{ $statut['couleur'] ?? 'var(--navy)' }}">{{ $statut['libelle'] ?? ($utilisateur?->statut ?? '—') }}</p>
            </div>
          </div>
        </section>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-5 mb-5">

          {{-- ========================== Informations personnelles ========== --}}
          <section class="bg-white rounded-xl border border-slate-200 p-5">
            <h2 class="text-sm font-bold text-slate-700 mb-4">{{ __('pwa.profil.infos_titre') }}</h2>
            <div class="space-y-3.5">
              <div class="groupe-champ">
                <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('pwa.profil.nom_complet') }}</label>
                <p class="w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm bg-slate-100 text-slate-600">{{ $nomComplet ?? '—' }}</p>
                @if ($nomComplet === null)
                  <p class="text-[12px] text-slate-400 mt-1">{{ __('pwa.profil.sans_fiche_rh') }}</p>
                @endif
              </div>
              <div class="groupe-champ">
                <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('pwa.profil.email') }}</label>
                {{-- Éditable depuis le 28/10/2026 (décision du PO) : `utilisateurs.email`, facultatif. --}}
                <input type="email" wire:model="emailSaisi" autocomplete="email"
                       class="w-full border border-slate-300 rounded-lg px-3 py-2.5 text-sm">
                @error('emailSaisi') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
              </div>
              <div class="groupe-champ">
                <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('pwa.profil.telephone') }}</label>
                <p class="w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm bg-slate-100 text-slate-600">—</p>
              </div>
              <div class="groupe-champ">
                <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('pwa.profil.fonction') }}</label>
                {{-- Le maître rend DÉJÀ ce champ `readonly` (l.83), et il
                     l'explique dans l'encart bleu ci-dessous. Aucun écart ici. --}}
                <p class="w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm bg-slate-100 text-slate-600 cursor-not-allowed">{{ $fonction ?? '—' }}</p>
              </div>
              <div class="flex items-start gap-2 rounded-lg px-3 py-2.5" style="background:#E8EEFD">
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="var(--info)" stroke-width="2.2" class="shrink-0 mt-0.5"><circle cx="12" cy="12" r="10"/><path stroke-linecap="round" d="M12 16v-4M12 8h.01"/></svg>
                <p class="text-[13px]" style="color:#1E3A8A">
                  {{ __('pwa.profil.note_fonction_avant') }}<a href="{{ route('pwa.roles-permissions') }}" wire:navigate class="underline font-semibold">{{ __('pwa.profil.note_fonction_lien') }}</a>{{ __('pwa.profil.note_fonction_apres') }}
                </p>
              </div>
              {{-- « Enregistrer les informations » (maître) : rendu depuis le
                   28/10/2026, il n'écrit que l'e-mail du compte. --}}
              <button type="button" wire:click="enregistrerInformations"
                      class="btn w-full px-5 py-2.5 rounded-lg text-white text-sm font-semibold" style="background:var(--gold)">
                {{ __('pwa.profil.enregistrer_infos') }}
              </button>
            </div>
          </section>

          {{-- ================================ Mot de passe ================== --}}
          {{-- Écriture RÉELLE depuis le 01/09/2026 (directive du Product
               Owner). Les trois champs du maître ne sont jamais rendus au
               premier GET (`RefuseLaSaisie`) : cette carte porte le titre et
               le bouton d'ouverture, les champs vivent dans la modale
               ci-dessous. --}}
          <section class="bg-white rounded-xl border border-slate-200 p-5">
            <h2 class="text-sm font-bold text-slate-700 mb-4">{{ __('pwa.profil.mdp_titre') }}</h2>
            <p class="text-[13px] text-slate-500 mb-4">{{ __('pwa.profil.mdp_sous_titre') }}</p>
            <button type="button" wire:click="ouvrirFormulaireMotDePasse"
                    class="btn w-full px-5 py-2.5 rounded-lg text-white text-sm font-semibold" style="background:var(--gold)">
              {{ __('pwa.profil.mdp_ouvrir') }}
            </button>
          </section>

          {{-- ============================ Code de secours =================== --}}
          {{-- 29/10/2026 (PO, option A) : le recours du DERNIER administrateur.
               Seul le hash du code est stocké ; le code lui-même n'est montré
               qu'une fois, dans la modale ci-dessous. --}}
          @if ($estAdministrateur)
            <section id="section-code-secours" class="bg-white rounded-xl border border-slate-200 p-5">
              <h2 class="text-sm font-bold text-slate-700 mb-4">{{ __('pwa.profil.code_secours_titre') }}</h2>
              <p class="text-[13px] text-slate-500 mb-2">{{ __('pwa.profil.code_secours_sous_titre') }}</p>
              <p id="etat-code-secours" class="text-[13px] text-slate-700 mb-4">
                @if ($codeSecoursPoseLe)
                  {{ __('pwa.profil.code_secours_present', ['date' => $codeSecoursPoseLe->format('d/m/Y H:i')]) }}
                @else
                  {{ __('pwa.profil.code_secours_absent') }}
                @endif
              </p>
              <button type="button" wire:click="ouvrirFormulaireCodeSecours"
                      class="btn w-full px-5 py-2.5 rounded-lg text-white text-sm font-semibold" style="background:var(--gold)">
                {{ __('pwa.profil.code_secours_ouvrir') }}
              </button>
            </section>
          @endif
        </div>

        {{-- ============================== Journal d'audit =================== --}}
        <section class="bg-white rounded-xl border border-slate-200 overflow-hidden">
          <div class="flex items-center justify-between px-5 py-4 border-b border-slate-100">
            <div>
              <h2 class="text-sm font-bold text-slate-700">{{ __('pwa.profil.journal_titre', ['nombre' => MonProfil::DERNIERES_ACTIONS]) }}</h2>
              <p class="text-[12px] text-slate-500 mt-0.5">{{ __('pwa.profil.journal_sous_titre') }}</p>
            </div>
            <a href="{{ route('pwa.journal-audit') }}" wire:navigate class="text-[13px] font-semibold shrink-0" style="color:var(--navy)">{{ __('pwa.profil.journal_complet') }}</a>
          </div>
          <div class="overflow-x-auto">
            <table class="w-full">
              {{-- En-tête navy (01/09/2026). Pas de barre de recherche : ce
                   tableau est borné aux `MonProfil::DERNIERES_ACTIONS`
                   dernières actions de l'utilisateur COURANT (pas de
                   pagination) — le journal complet, filtrable, vit sur
                   l'écran dédié « Journal d'audit ». --}}
              <thead class="bg-[var(--navy)]">
                <tr>
                  <th class="text-left px-5 py-2.5 text-[11px] font-semibold text-white/90 uppercase tracking-wide">{{ __('pwa.profil.col_date_heure') }}</th>
                  <th class="text-left px-5 py-2.5 text-[11px] font-semibold text-white/90 uppercase tracking-wide">{{ __('pwa.profil.col_action') }}</th>
                  <th class="text-left px-5 py-2.5 text-[11px] font-semibold text-white/90 uppercase tracking-wide">{{ __('pwa.profil.col_module') }}</th>
                  <th class="text-left px-5 py-2.5 text-[11px] font-semibold text-white/90 uppercase tracking-wide">{{ __('pwa.profil.col_ip') }}</th>
                </tr>
              </thead>
              <tbody id="corps-journal-profil">
                @forelse ($traces as $trace)
                  <tr class="border-t border-slate-100">
                    <td class="px-5 py-2.5 text-[13px] text-slate-500 font-mono-tatacora">{{ $trace->date_heure?->format('d/m/Y H:i:s') ?? '—' }}</td>
                    <td class="px-5 py-2.5 text-[13px] text-slate-700">{{ JournalAudit::ACTIONS[$trace->action]['libelle'] ?? $trace->action }}</td>
                    <td class="px-5 py-2.5 text-[13px] text-slate-500">{{ $trace->entite_concernee }}</td>
                    <td class="px-5 py-2.5 text-[13px] text-slate-400 font-mono-tatacora">{{ $trace->adresse_poste ?? '—' }}</td>
                  </tr>
                @empty
                  <tr><td colspan="4" class="py-10 text-center text-slate-400 text-sm">{{ __('pwa.profil.journal_vide') }}</td></tr>
                @endforelse
              </tbody>
            </table>
          </div>
        </section>

      </div>
    </main>
  </div>

  {{-- ================ MODALE « CHANGER LE MOT DE PASSE » ================ --}}
  {{-- PA-185 (11/09/2026) : rendue APRÈS `</main>`, comme toutes les modales
       de la PWA (ex. `crm/clients-creances.blade.php`). Posée dans `<main>`,
       elle était la seule sur 133 à subir le remappage typographique de
       `app.css` (`main .text-[13px]` rend 12,5 px) — même modale, autres
       tailles. Contenu et comportement Livewire inchangés. --}}
  @if ($etatFormulaire === 'mot_de_passe')
    <x-pwa.modale :titre="__('pwa.profil.mdp_titre')" :sousTitre="__('pwa.profil.mdp_sous_titre')" largeur="480px">
      <div class="groupe-champ">
        <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('pwa.profil.mdp_ancien') }}</label>
        <input type="password" wire:model="ancienMotDePasse" autocomplete="current-password"
               class="w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm">
        @error('ancienMotDePasse')<p class="text-[12px] mt-1" style="color:var(--erreur)">{{ $message }}</p>@enderror
      </div>
      <div class="groupe-champ">
        <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('pwa.profil.mdp_nouveau') }}</label>
        <input type="password" wire:model="nouveauMotDePasse" autocomplete="new-password"
               class="w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm">
        @error('nouveauMotDePasse')<p class="text-[12px] mt-1" style="color:var(--erreur)">{{ $message }}</p>@enderror
        <p class="text-[12px] text-slate-400 mt-1.5">{{ __('pwa.profil.mdp_regle') }}</p>
      </div>
      <div class="groupe-champ">
        <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('pwa.profil.mdp_confirmation') }}</label>
        <input type="password" wire:model="confirmationMotDePasse" autocomplete="new-password"
               class="w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm">
        @error('confirmationMotDePasse')<p class="text-[12px] mt-1" style="color:var(--erreur)">{{ $message }}</p>@enderror
      </div>

      <x-slot:pied>
        <button type="button" wire:click="fermerModales"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="changerMotDePasse"
                class="text-[13px] px-4 py-2 rounded-lg text-white font-semibold hover:opacity-90" style="background:var(--gold)">{{ __('pwa.profil.mdp_bouton') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  {{-- ================ MODALE « CODE DE SECOURS » ================ --}}
  @if ($etatFormulaire === 'code_secours')
    @if ($codeSecoursAffiche === null)
      <x-pwa.modale :titre="__('pwa.profil.code_secours_modale_titre')" :sousTitre="__('pwa.profil.code_secours_modale_sous_titre')" largeur="480px">
        <div class="groupe-champ">
          <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('pwa.profil.code_secours_mot_de_passe') }}</label>
          <input type="password" wire:model="motDePasseCodeSecours" autocomplete="current-password"
                 class="w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm">
          @error('motDePasseCodeSecours')<p class="text-[12px] mt-1" style="color:var(--erreur)">{{ $message }}</p>@enderror
        </div>

        <x-slot:pied>
          <button type="button" wire:click="fermerModales"
                  class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
          <button id="generer-code-secours" type="button" wire:click="genererCodeSecours"
                  class="text-[13px] px-4 py-2 rounded-lg text-white font-semibold hover:opacity-90" style="background:var(--gold)">{{ __('pwa.profil.code_secours_generer') }}</button>
        </x-slot:pied>
      </x-pwa.modale>
    @else
      <x-pwa.modale :titre="__('pwa.profil.code_secours_affiche_titre')" largeur="520px">
        <x-pwa.secret-unique :secret="$codeSecoursAffiche" id="code-secours-profil" :imprimable="true"
                             :titre="__('pwa.profil.code_secours_impression_titre')"
                             :consigne="__('pwa.profil.code_secours_consigne')" />
        <x-slot:pied>
          <button id="fermer-code-secours" type="button" wire:click="fermerModales"
                  class="text-[13px] px-4 py-2 rounded-lg text-white font-semibold hover:opacity-90" style="background:var(--gold)">{{ __('pwa.profil.code_secours_fermer') }}</button>
        </x-slot:pied>
      </x-pwa.modale>
    @endif
  @endif

</div>
