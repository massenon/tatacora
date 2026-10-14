{{--
    La cloche et son panneau — maître : `shell.js` l.128-146 (markup du
    bouton, du badge et du menu) et l.330-352 (markup d'une ligne, rendu par
    `initialiserNotifications`). Transcription littérale : mêmes ids, mêmes
    classes — le JS de coquille (`layouts/pwa.blade.php`) ouvre et ferme ce
    panneau par délégation sur ces ids, il n'a pas changé.

    Contenu RÉEL : les alertes d'ouverture dérivées (`AlertesOuverture` —
    stock sous seuil, rupture, caisse non clôturée, arrivées du jour,
    créances anciennes), jamais une liste stockée. Voir le docblock du
    composant pour la levée du refus antérieur.
--}}
<div class="relative">
  <button id="bouton-cloche-notifications" type="button" class="relative text-white/70 hover:text-white p-2" aria-label="{{ __('pwa.coquille.notifications') }}">
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M18 8a6 6 0 00-12 0c0 7-3 9-3 9h18s-3-2-3-9"/><path stroke-linecap="round" stroke-linejoin="round" d="M13.73 21a2 2 0 01-3.46 0"/></svg>
    {{-- Badge des non-lues (shell.js l.334) : masqué à zéro, EXACTEMENT
         comme le maître (`badge.classList.add('hidden')`). Le nombre est
         dérivé à chaque rendu — jamais un chiffre posé (PA-59/60/61). --}}
    <span id="badge-notifications-non-lues"
          class="{{ $nonLuesCompte === 0 ? 'hidden ' : '' }}absolute top-1 right-1 min-w-[14px] h-3.5 px-1 bg-[var(--erreur)] rounded-full text-[8px] flex items-center justify-center text-white font-bold">{{ $nonLuesCompte === 0 ? '' : $nonLuesCompte }}</span>
  </button>
  <div id="menu-notifications" class="hidden absolute right-0 top-12 w-80 bg-white rounded-xl shadow-2xl border border-slate-100 z-50 overflow-hidden">
    <div class="flex items-center justify-between px-4 py-3 border-b border-slate-100">
      <span class="text-sm font-bold text-slate-700">{{ __('pwa.coquille.notifications') }}</span>
      {{-- « Tout marquer comme lu » (shell.js l.40) — le refus du 31/08/2026
           est LEVÉ : les alertes dérivées sont une source réelle. Rendu EN
           PERMANENCE, comme le maître (markup statique de son panneau) : à
           zéro non-lue, le clic ne marque rien — un non-geste, pas un
           contrôle inerte au sens de l'Article 3.3 (il agit dès qu'une
           alerte existe, et la garde du châssis exige le libellé du bloc). --}}
      <button type="button" wire:click="marquerToutLu" class="text-[11px] font-semibold" style="color:var(--gold)">{{ __('pwa.cloche.tout_marquer_lu') }}</button>
    </div>
    {{-- Les deux filtres du maître (shell.js l.139-140). Deux branches
         ENTIÈREMENT statiques plutôt qu'une classe interpolée : la garde de
         châssis compare les chaînes de classes au maître à l'égalité stricte,
         et une interpolation Blade dans l'attribut rendrait cette comparaison
         impossible. La première branche est l'état du maître (« Toutes »
         actif). --}}
    @if ($filtre === 'toutes')
      <div class="flex gap-1 px-3 pt-2.5">
        <button type="button" wire:click="$set('filtre', 'toutes')" data-filtre-notif="toutes" class="filtre-notif px-3 py-1.5 rounded-md text-[11px] font-semibold bg-[var(--navy)] text-white">{{ __('pwa.coquille.filtre_toutes') }}</button>
        <button type="button" wire:click="$set('filtre', 'non-lues')" data-filtre-notif="non-lues" class="filtre-notif px-3 py-1.5 rounded-md text-[11px] font-semibold text-slate-500">{{ __('pwa.coquille.filtre_non_lues') }}</button>
      </div>
    @else
      <div class="flex gap-1 px-3 pt-2.5">
        <button type="button" wire:click="$set('filtre', 'toutes')" data-filtre-notif="toutes" class="filtre-notif px-3 py-1.5 rounded-md text-[11px] font-semibold text-slate-500">{{ __('pwa.coquille.filtre_toutes') }}</button>
        <button type="button" wire:click="$set('filtre', 'non-lues')" data-filtre-notif="non-lues" class="filtre-notif px-3 py-1.5 rounded-md text-[11px] font-semibold bg-[var(--navy)] text-white">{{ __('pwa.coquille.filtre_non_lues') }}</button>
      </div>
    @endif
    <div id="liste-notifications" class="max-h-80 overflow-y-auto py-2">
      @forelse ($alertes as $alerte)
        {{-- Ligne du maître (shell.js l.343-351) : pastille dorée quand non
             lue, fond ambré. Le clic marque vue PUIS navigue — deux gestes,
             le lien reste un vrai lien. --}}
        <a href="{{ route($alerte['route']) }}" wire:navigate
           @unless ($alerte['vue']) wire:click="marquerLu('{{ $alerte['cle'] }}')" @endunless
           class="flex items-start gap-2.5 px-4 py-2.5 hover:bg-slate-50 {{ $alerte['vue'] ? '' : 'bg-amber-50/40' }}">
          <span class="w-1.5 h-1.5 rounded-full mt-1.5 shrink-0" style="background:{{ $alerte['vue'] ? 'transparent' : 'var(--gold)' }}"></span>
          <span class="min-w-0">
            <span class="block text-xs font-semibold text-slate-700 truncate">{{ $alerte['titre'] }}</span>
            <span class="block text-[11px] text-slate-500 leading-snug">{{ $alerte['detail'] }}</span>
          </span>
        </a>
      @empty
        {{-- État vide du maître (shell.js l.339), déclinaison par filtre. --}}
        <p class="text-center text-xs text-slate-400 py-8">{{ $filtre === 'non-lues' ? __('pwa.cloche.aucune_non_lue') : __('pwa.coquille.aucune_notification') }}</p>
      @endforelse
    </div>
    @if ($liensChassis['journal_audit']['url'] !== null)
      <div class="px-4 py-2.5 border-t border-slate-100 text-center">
        @include('pwa.partials.lien-chassis', [
          'url' => $liensChassis['journal_audit']['url'],
          'titre' => $liensChassis['journal_audit']['raison'],
          'libelle' => __('pwa.coquille.voir_notifications'),
          'icone' => null,
          'taille' => 14,
          'classes' => 'text-[11px] font-semibold',
          'attributStyle' => ' style="color:var(--navy)"',
        ])
      </div>
    @endif
  </div>
</div>
