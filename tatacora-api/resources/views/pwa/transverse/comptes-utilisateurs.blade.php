{{--
    COMPTES UTILISATEURS — AJOUT du Product Owner du 29/10/2026 (option A du
    « mot de passe perdu » : pas d'e-mail automatique). La liste des comptes et
    l'action « Réinitialiser le mot de passe » ; le poste Windows a le même écran
    (comptes locaux distincts : rien ne se synchronise).

    Ni création ni désactivation de compte ici : le geste de ce lot est la
    réinitialisation par un administrateur (voir `MotDePassePerduService`).
--}}
<div class="contents">

  @include('pwa.partials.barre-superieure')

  <div class="flex flex-1 overflow-hidden">
    @include('pwa.partials.menu-lateral')
    <main class="flex-1 overflow-y-auto">
      <div class="max-w-[1440px] mx-auto p-5 lg:p-8">

        <div class="mb-6">
          <h1 class="text-lg lg:text-xl font-bold" style="color:var(--navy)">{{ __('pwa.comptes.titre') }}</h1>
          <p class="text-[15px] text-slate-500 mt-1.5">{{ __('pwa.comptes.sous_titre') }}</p>
        </div>

        @if ($refus)
          <div id="refus-comptes" role="alert" class="mb-4 rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">{{ $refus }}</div>
        @endif

        <div class="bg-white rounded-xl border border-slate-200 overflow-hidden">
          <div class="overflow-x-auto">
            <table id="table-comptes" class="w-full text-sm">
              <thead class="bg-[var(--navy)]">
                <tr class="text-left text-[11px] font-semibold text-white/90 uppercase tracking-wide">
                  <th class="px-5 py-3">{{ __('pwa.comptes.col_identifiant') }}</th>
                  <th class="px-5 py-3">{{ __('pwa.comptes.col_nom') }}</th>
                  <th class="px-5 py-3">{{ __('pwa.comptes.col_role') }}</th>
                  <th class="px-5 py-3">{{ __('pwa.comptes.col_statut') }}</th>
                  <th class="px-5 py-3">{{ __('pwa.comptes.col_mot_de_passe') }}</th>
                  <th class="px-5 py-3 text-right">{{ __('pwa.comptes.col_actions') }}</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-slate-100">
                @forelse ($comptes as $compte)
                  @php
                    $employe = $compte->employe;
                    $nom = $employe === null ? null : trim($employe->prenom.' '.$employe->nom);
                    $statut = $statuts[$compte->statut] ?? null;
                    $role = (string) $compte->role?->libelle;
                  @endphp
                  <tr data-compte="{{ $compte->login }}">
                    <td class="px-5 py-3 font-semibold text-slate-800">{{ $compte->login }}</td>
                    <td class="px-5 py-3 text-slate-600">{{ $nom ?: '—' }}</td>
                    <td class="px-5 py-3 text-slate-600">{{ $roles[$role] ?? \Illuminate\Support\Str::of($role)->replace('_', ' ')->title() }}</td>
                    <td class="px-5 py-3">
                      @if ($statut)
                        <span class="font-semibold" style="color:{{ $statut['couleur'] }}">{{ $statut['libelle'] }}</span>
                      @else
                        {{ $compte->statut }}
                      @endif
                    </td>
                    <td class="px-5 py-3 text-slate-600">
                      @if ($compte->must_change_password)
                        <span class="font-semibold" style="color:var(--gold)">{{ $compte->motDePasseTemporaireExpire() ? __('pwa.comptes.temporaire_expire') : __('pwa.comptes.changement_requis') }}</span>
                      @else
                        —
                      @endif
                    </td>
                    <td class="px-5 py-3 text-right">
                      @if ($peutReinitialiser && $compte->id !== $compteCourantId)
                        <button type="button" wire:click="ouvrirReinitialisation('{{ $compte->id }}')"
                                class="text-[13px] px-3 py-1.5 rounded-lg border border-slate-300 hover:bg-slate-50 font-semibold">{{ __('pwa.comptes.reinitialiser') }}</button>
                      @endif
                    </td>
                  </tr>
                @empty
                  <tr><td colspan="6" class="px-5 py-8 text-center text-slate-500">{{ __('pwa.comptes.vide') }}</td></tr>
                @endforelse
              </tbody>
            </table>
          </div>
        </div>

      </div>
    </main>
  </div>

  {{-- Confirmation — derrière `@if`, jamais `wire:confirm`. --}}
  @if ($cible !== null)
    <x-pwa.modale :titre="__('pwa.comptes.reinitialiser_titre', ['login' => $cible->login])" largeur="480px">
      <p class="text-sm text-slate-600">{{ __('pwa.comptes.reinitialiser_texte', ['heures' => \App\Shared\Auth\Services\MotDePassePerduService::VALIDITE_TEMPORAIRE_HEURES]) }}</p>
      <x-slot:pied>
        <button type="button" wire:click="fermerModales" class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button id="confirmer-reinitialisation" type="button" wire:click="reinitialiserMotDePasse" class="text-[13px] px-4 py-2 rounded-lg text-white font-semibold" style="background:var(--navy)">{{ __('pwa.comptes.reinitialiser_confirmer') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  {{-- Le mot de passe temporaire : montré UNE seule fois. --}}
  @if ($resultat !== null)
    <x-pwa.modale :titre="__('pwa.comptes.resultat_titre', ['login' => $resultat['login']])" largeur="520px">
      <x-pwa.secret-unique :secret="$resultat['motDePasse']" id="mot-de-passe-temporaire"
                           :consigne="__('pwa.comptes.resultat_consigne', ['date' => $resultat['expireLe']])" />
      <x-slot:pied>
        <button id="fermer-resultat" type="button" wire:click="fermerModales" class="text-[13px] px-4 py-2 rounded-lg text-white font-semibold" style="background:var(--navy)">{{ __('pwa.comptes.fermer') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif
</div>
