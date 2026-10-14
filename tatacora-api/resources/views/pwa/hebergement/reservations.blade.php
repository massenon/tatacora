{{--
    RÉSERVATIONS — créer, modifier, annuler, et l'historique (M1).

    Maître : `prototype_v2/pages/reservations.html`, et son panneau
    `prototype_v2/assets/js/historique-reservations.js` pour les colonnes, les
    filtres et les indicateurs.

    ## Deux lignes de montants, jamais un total unique (PA-112)

    « Séjour » puis « Consommations » disent ce qui s'est réellement passé ; un
    montant unique laisserait croire que la nuitée a changé de prix. Sur ce
    serveur, les deux rendent « — » : aucun montant de séjour n'est stocké
    (PA-55/PA-57) et aucune table `paniers` n'existe. Le refus est nommé à
    l'écran plutôt que masqué par un zéro plausible.

    ## L'état d'un séjour est DÉRIVÉ (PA-111)

    Quatre états, un seul stocké — l'annulation. Le composant tient la
    dérivation, et l'état FILTRÉ vient de la même : deux calculs finiraient par
    se contredire sur le même écran.

    ## REFUS LEVÉ (PA-163, complété 02/09/2026) — la fiche complète du maître
    N'EST PLUS locale au client Flutter, elle atteint le serveur

    Canal de réservation, les CINQ tuiles de services (icônes et couleurs du
    maître), les lignes par service avec leur sous-total, remise, mode de
    paiement et le récapitulatif qui les totalise sont tous portés — le
    schéma (`reservations.canal_id`, `remise_type`, `remise_valeur`,
    `mode_paiement`, la table `lignes_reservation`) les porte depuis PA-163,
    et `ReservationService::creer()`/`remplacerLignes()` les écrit dans la
    même transaction. Deux écarts SEULS restent, et ils sont DÉLIBÉRÉS :

    Declarations pour la garde des trois sources — le jeton de MODALE reprend
    l'`id` du maître (`modale-reservation`, l.107), ce que `t-trois-sources.js`
    exige pour reconnaitre un controle non rendu comme REFUSE plutot que comme
    oublie ; les trois sous-jetons NOMMENT precisement lequel de ses controles
    reste refuse, pour que la declaration reste verifiable point par point :
      maitre-refuse:reservations.html#modale-reservation
        Le champ « Client » du maître est un texte libre placeholder
        « Ex. Jean KORA ou Agence Bénin Tour » (l.125). Ici, une vraie clé
        étrangère vers `clients` (menu déroulant ou création rapide) — texte
        libre est interdit par la règle du dépôt (« tout champ relationnel
        est une vraie clé étrangère, jamais du texte libre »). Detail au
        jeton #client-texte-libre ci-dessous.
      maitre-refuse:reservations.html#client-texte-libre
        Meme motif que ci-dessus, jeton dedie pour la revue humaine du champ
        precis.
      maitre-refuse:reservations.html#historique-du-client
        Le bouton « Historique du client », dans l'en-tête de la modale du
        maître, n'a pas d'équivalent ici : il exigerait un filtre de
        l'historique par client, que cet écran ne porte pas encore.
      maitre-refuse:reservations.html#plusieurs-unites
        Le maître admet plusieurs chambres sur une même fiche (les lignes du
        service Hébergement). `reservations.unite_id` est une colonne UNIQUE
        et NOT NULL du schéma serveur : une fiche ne porte qu'UNE unité,
        sélectionnée dans le bloc Hébergement de la zone de lignes.
        Arbitrage ouvert (PA-110).
--}}
@php
    use App\Pwa\Support\MontantFcfa;
    use App\Pwa\Livewire\Hebergement\Reservations;

    $peutEcrire = ($utilisateur?->niveauSurModule(Reservations::MODULE) ?? '-') === 'C';
    $tiret = MontantFcfa::TIRET;
@endphp

<div class="contents">
  @include('pwa.partials.barre-superieure')

  <div class="flex flex-1 overflow-hidden">
    @include('pwa.partials.menu-lateral')

    <main class="flex-1 overflow-y-auto">
      <div class="max-w-[1440px] mx-auto p-5 lg:p-8">

        @if (session('pwa-succes'))
          <div class="mb-4 rounded-lg px-4 py-3 text-[13px] font-semibold"
               style="background:#E8F5E9;color:#2E7D32">{{ session('pwa-succes') }}</div>
        @endif

        @error('annulation')
          <div class="mb-4 rounded-lg px-4 py-3 text-[13px]" style="background:#FDECEC;color:#8C1D1D">{{ $message }}</div>
        @enderror
        @error('export')
          <div class="mb-4 rounded-lg px-4 py-3 text-[13px]" style="background:#FDECEC;color:#8C1D1D">{{ $message }}</div>
        @enderror

        {{-- maître — l.24-46 --}}
        <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4 mb-5">
          <div>
            <div class="flex items-center gap-2.5">
              <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--navy)" stroke-width="2"><rect x="3" y="4" width="18" height="18" rx="2"/><path stroke-linecap="round" stroke-linejoin="round" d="M16 2v4M8 2v4M3 10h18"/></svg>
              <h1 class="text-lg lg:text-xl font-bold" style="color:var(--navy)">{{ __('pwa.reservations.titre') }}</h1>
            </div>
            <p class="text-[15px] text-slate-500 mt-1.5">{{ __('pwa.reservations.sous_titre') }}</p>
          </div>

          <div class="flex items-center gap-3 shrink-0">
            <button wire:click="$set('vue', 'historique')"
                    class="btn flex items-center gap-2 px-4 py-2.5 rounded-lg border border-slate-300 text-slate-700 text-[15px] font-semibold bg-white">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><path stroke-linecap="round" d="M12 6v6l4 2"/></svg>
              {{ __('pwa.reservations.bouton_historique') }}
            </button>

            {{-- 1er niveau du RBAC — masquage. Le refus réel est côté serveur. --}}
            @if ($peutEcrire && $peutEcrireClient)
              <button wire:click="ouvrirCreationClient"
                      class="btn flex items-center gap-2 px-4 py-2.5 rounded-lg border border-[var(--navy)] text-[var(--navy)] text-[15px] font-semibold bg-white">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="9" cy="7" r="4"/><path stroke-linecap="round" stroke-linejoin="round" d="M17 21v-2a4 4 0 00-4-4H5a4 4 0 00-4 4v2M20 8v6M23 11h-6"/></svg>
                {{ __('hebergement_pwa.reservations.bouton_ajouter_client') }}
              </button>
            @endif

            @if ($peutEcrire)
              <button wire:click="ouvrirCreationReservation"
                      class="btn flex items-center gap-2 px-4 py-2.5 rounded-lg bg-[var(--navy)] text-white text-[15px] font-semibold">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path stroke-linecap="round" d="M12 5v14M5 12h14"/></svg>
                {{ __('pwa.reservations.bouton_nouvelle') }}
              </button>
            @endif
          </div>
        </div>

        {{-- Nouvel onglet Annulations — instruction du Product Owner
             (01/09/2026), EF-M1-06. N'existe pas au maître : c'est un ajout
             fonctionnel demandé en séance (§4.4/§6.3), pas un portage.
             Ajout déclaré au comparateur de squelette :
             structure-ajout:reservations.html#div-236bb21f --}}
        {{-- Classes d'onglets : directive PO du 01/09/2026, UN SEUL AUTEUR
             (`App\Pwa\Support\Onglets`) — le style souligné d'origine a été
             repris le 02/09/2026 sur rappel du PO. --}}
        <div class="flex flex-wrap items-center gap-1.5 mb-4">
          <button wire:click="$set('ongletActif', 'actives')"
                  class="{{ \App\Pwa\Support\Onglets::classes($ongletActif !== 'annulations') }}">
            {{ __('pwa.reservations.onglet_actives') }}
          </button>
          <button wire:click="$set('ongletActif', 'annulations')"
                  class="{{ \App\Pwa\Support\Onglets::classes($ongletActif === 'annulations') }}">
            {{ __('pwa.reservations.onglet_annulations') }}
          </button>
        </div>

        {{-- maître — l.48-51. Propre à l'onglet « Actives » : la recherche de
             l'onglet Annulations est distincte (elle filtre une AUTRE
             requête), voir plus bas. --}}
        @if ($ongletActif !== 'annulations')
        <div class="relative mb-4 max-w-md">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#9CA3AF" stroke-width="2" class="absolute left-3.5 top-1/2 -translate-y-1/2"><circle cx="11" cy="11" r="8"/><path stroke-linecap="round" d="M21 21l-4.35-4.35"/></svg>
          <input type="search" wire:model.live.debounce.300ms="recherche" placeholder="{{ __('pwa.reservations.recherche') }}"
                 class="champ w-full border border-slate-200 rounded-lg pl-10 pr-4 py-2.5 text-sm bg-white">
        </div>
        @endif

        {{-- La PREMIÈRE branche porte le contenu du MAÎTRE : `t-structure.js`
             ne lit que la première branche de chaque @if (limitation écrite dans
             son entête) — l'onglet Annulations, ajout PO sans équivalent maître,
             vit dans le @else (01/09/2026). --}}
        @if ($ongletActif !== 'annulations')

        {{-- maître — l.53-54 : la grille de cartes, PUIS l'état vide.

             ⚠ LA GRILLE EST TOUJOURS POSÉE, ET C'EST STRUCTUREL.
             Le maître écrit `<div id="grille-reservations" class="grid …"></div>`
             suivi de `<div id="etat-vide-reservations" class="hidden …">` : les
             deux existent en permanence, le second étant simplement masqué. La
             PWA rendait l'un OU l'autre, dans cet ordre-là — l'état vide en
             premier —, si bien que la grille du maître n'avait aucun
             équivalent au repos. `t-structure.js` le signalait comme un bloc
             absent, et il avait raison : une grille vide n'occupe aucune place
             à l'écran, un état vide affiché à sa place en occupe seize. --}}
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
            @foreach ($grille as $reservation)
              @php $etat = $etats[$reservation->id] ?? null; @endphp
              <div class="carte-hover bg-white rounded-xl border border-slate-200 p-5" wire:key="res-{{ $reservation->id }}">
                <div class="flex items-start justify-between mb-2">
                  <div>
                    <p class="font-bold text-slate-800 text-[15px]">{{ $reservation->client?->nomComplet() ?: $tiret }}</p>
                    {{-- Méta du maître — « Type de client • Canal • dates »
                         (`rendreCarteReservation()`, `reservations-services.js`
                         l.432). --}}
                    <p class="text-[13px] text-slate-400">
                      {{ $reservation->client === null ? $tiret : __(Reservations::TYPES_CLIENT[$reservation->client->type_client] ?? 'hebergement_pwa.reservations.type_particulier') }}
                      • {{ $reservation->canal?->nom ?? $tiret }}
                      • {{ $reservation->date_arrivee->format('d/m/Y') }} → {{ $reservation->date_depart->format('d/m/Y') }}
                      ({{ __('hebergement_pwa.hebergement.nuits', ['nombre' => $reservation->nombreNuitees()]) }})
                    </p>
                  </div>
                  <div class="flex items-center gap-2">
                    <span class="px-2 py-0.5 rounded text-[11px] font-semibold {{ $etat['classe'] ?? '' }}">{{ $etat['libelle'] ?? $tiret }}</span>
                    <button wire:click="$set('detailId', '{{ $reservation->id }}')"
                            class="btn p-1.5 rounded hover:bg-slate-100 text-slate-500" title="{{ __('pwa.reservations.action_modifier') }}">
                      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>
                    </button>
                    @if ($peutEcrire)
                      <button wire:click="ouvrirModificationReservation('{{ $reservation->id }}')"
                              class="btn p-1.5 rounded hover:bg-slate-100 text-slate-500" title="{{ __('pwa.reservations.action_modifier') }}">
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M11 4H4a2 2 0 00-2 2v14a2 2 0 002 2h14a2 2 0 002-2v-7"/><path stroke-linecap="round" stroke-linejoin="round" d="M18.5 2.5a2.12 2.12 0 013 3L12 15l-4 1 1-4 9.5-9.5z"/></svg>
                      </button>
                      <button wire:click="imprimerConfirmation('{{ $reservation->id }}')"
                              class="btn p-1.5 rounded hover:bg-slate-100 text-slate-500" title="{{ __('hebergement_pwa.reservations.confirmation_titre') }}">
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M6 9V2h12v7M6 18H4a2 2 0 01-2-2v-5a2 2 0 012-2h16a2 2 0 012 2v5a2 2 0 01-2 2h-2M6 14h12v8H6v-8z"/></svg>
                      </button>
                    @endif
                    {{-- EF-M1-06 : distinct de $peutEcrire — un rôle avec
                         M1 = C (créer/modifier) ne peut pas forcément
                         exécuter une annulation avec remboursement, geste
                         qui engage la caisse (RolePermissionSeeder::MATRICE). --}}
                    @if ($peutAnnuler)
                      <button wire:click="confirmerAnnulation('{{ $reservation->id }}')"
                              class="btn p-1.5 rounded hover:bg-red-50 text-red-500" title="{{ __('pwa.reservations.action_annuler') }}">
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" d="M18 6L6 18M6 6l12 12"/></svg>
                      </button>
                    @endif
                  </div>
                </div>

                {{-- Badges multi-services du maître, DÉRIVÉS des lignes —
                     jamais stockés (`rendreCarteReservation()` l.441).
                     L'hébergement est toujours présent (`unite_id` NOT NULL) ;
                     les quatre autres viennent de `lignes()`, comme sur la
                     fiche d'écriture ci-dessus (PA-163). --}}
                <div class="flex flex-wrap gap-1.5 mb-3">
                  @foreach (array_unique(array_merge(['hebergement'], $reservation->lignes->pluck('service')->all())) as $service)
                    <span class="text-[12px] font-semibold px-2 py-1 rounded" style="background:{{ \App\Pwa\Support\CouleursServices::fond($service) }};color:{{ \App\Pwa\Support\CouleursServices::texte($service) }}">{{ \App\Pwa\Support\CouleursServices::libelle($service) }}</span>
                  @endforeach
                </div>

                <div class="space-y-1 text-[13px] text-slate-500 border-t border-slate-100 pt-2.5">
                  <p>{{ __('pwa.reservations.unite') }} : <strong class="text-slate-700">{{ $reservation->unite?->numero ?? $tiret }}</strong>
                     — {{ $reservation->unite?->categorie?->libelle ?? $tiret }}</p>
                </div>

                {{-- PA-112 — DEUX lignes de montants, jamais un total unique.
                     REFUS LEVÉ (02/09/2026) pour « Séjour » et « Reste à
                     payer » : PA-163 a ajouté `tarif_nuit`, les lignes de
                     service, la remise et l'acompte au schéma, et
                     `Reservation::sousTotalHebergement()`/`resteAPayer()` les
                     combinent — jamais réécrites ici. `null` reste un tiret,
                     jamais un zéro qui se lirait comme un séjour gratuit.
                     « Consommations » reste « — » : aucune table `paniers`
                     n'existe côté serveur (PA-63). --}}
                <div class="mt-2.5 pt-2.5 border-t border-slate-100 text-[13px] space-y-1">
                  <div class="flex justify-between">
                    <span class="text-slate-400">{{ __('pwa.reservations.ligne_sejour') }}</span>
                    <span class="font-mono-tatacora text-slate-700 font-semibold">{{ $reservation->sousTotalHebergement() === null ? $tiret : MontantFcfa::format($reservation->sousTotalHebergement()) }}</span>
                  </div>
                  <div class="flex justify-between">
                    <span class="text-slate-400">{{ __('hebergement_pwa.reservations.ligne_consommations') }}</span>
                    <span class="font-mono-tatacora text-slate-700 font-semibold">{{ $tiret }}</span>
                  </div>
                  <div class="flex justify-between pt-1 border-t border-slate-100">
                    <span class="text-slate-400">{{ __('pwa.reservations.ligne_acompte') }}</span>
                    <strong class="font-mono-tatacora text-emerald-700">{{ MontantFcfa::format((string) $reservation->acompte) }}</strong>
                  </div>
                  <div class="flex justify-between pt-1 border-t border-slate-100">
                    <span class="text-slate-400">{{ __('pwa.reservations.recap_reste') }}</span>
                    <strong class="font-mono-tatacora" style="color:var(--gold)">{{ $reservation->resteAPayer() === null ? $tiret : MontantFcfa::format($reservation->resteAPayer()) }}</strong>
                  </div>
                </div>
              </div>
            @endforeach
        </div>

        @if ($grille->isEmpty())
          <div class="bg-white rounded-xl border border-slate-200 py-16 text-center text-slate-400 text-sm">
            {{ __('pwa.reservations.vide') }}
          </div>
        @endif
        @else
          {{-- ============ ONGLET ANNULATIONS (EF-M1-06) ============ --}}
          {{-- Recherche + filtre PAR TABLE (décision du Product Owner,
               01/09/2026) — barre toujours posée, comme la grille des
               réservations actives, pour rester manipulable même quand le
               filtre en cours ne rend aucune ligne. --}}
          <div class="flex flex-col sm:flex-row sm:items-center gap-3 mb-4">
            <div class="relative flex-1 max-w-md">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#9CA3AF" stroke-width="2" class="absolute left-3.5 top-1/2 -translate-y-1/2"><circle cx="11" cy="11" r="8"/><path stroke-linecap="round" d="M21 21l-4.35-4.35"/></svg>
              <input type="search" wire:model.live.debounce.300ms="annulRecherche"
                     placeholder="{{ __('pwa.reservations.recherche') }}"
                     class="champ w-full border border-slate-200 rounded-lg pl-10 pr-4 py-2.5 text-sm bg-white">
            </div>
            <select wire:model.live="annulCanal" class="champ border border-slate-200 rounded-lg px-3 py-2.5 text-sm bg-white">
              <option value="">{{ __('hebergement_pwa.reservations.annulation_tous_canaux') }}</option>
              @foreach ($canauxAnnulations as $unCanal)
                <option value="{{ $unCanal->id }}">{{ $unCanal->nom }}</option>
              @endforeach
            </select>
          </div>

          @if ($annulations->isEmpty())
            <div class="bg-white rounded-xl border border-slate-200 py-16 text-center text-slate-400 text-sm">
              {{ __('pwa.reservations.annulations_vide') }}
            </div>
          @else
            <div class="bg-white rounded-xl border border-slate-200 overflow-x-auto">
              <table class="w-full text-[13px]">
                <thead class="bg-[var(--navy)]">
                  <tr class="text-left text-[11px] font-semibold text-white/90 uppercase tracking-wide">
                    <th class="px-4 py-3">{{ __('pwa.reservations.hist_col_client') }}</th>
                    <th class="px-4 py-3">{{ __('pwa.reservations.hist_col_sejour') }}</th>
                    <th class="px-4 py-3 text-right">{{ __('hebergement_pwa.reservations.annulation_col_total') }}</th>
                    <th class="px-4 py-3 text-right">{{ __('hebergement_pwa.reservations.annulation_col_taux') }}</th>
                    <th class="px-4 py-3 text-right">{{ __('hebergement_pwa.reservations.annulation_col_commission') }}</th>
                    <th class="px-4 py-3 text-right">{{ __('hebergement_pwa.reservations.annulation_col_rembourse') }}</th>
                    <th class="px-4 py-3">{{ __('hebergement_pwa.reservations.annulation_col_date') }}</th>
                    <th class="px-4 py-3">{{ __('hebergement_pwa.reservations.annulation_col_auteur') }}</th>
                  </tr>
                </thead>
                <tbody>
                  @foreach ($annulations as $ligne)
                    <tr class="border-t border-slate-100" wire:key="annul-{{ $ligne->id }}">
                      <td class="px-4 py-2.5 font-semibold">{{ $ligne->client?->nomComplet() ?: $tiret }}</td>
                      <td class="px-4 py-2.5 whitespace-nowrap text-slate-500">{{ $ligne->date_arrivee->format('d/m/Y') }} → {{ $ligne->date_depart->format('d/m/Y') }}</td>
                      <td class="px-4 py-2.5 text-right font-mono-tatacora">{{ $ligne->montant_total_annulation === null ? $tiret : MontantFcfa::format((string) $ligne->montant_total_annulation) }}</td>
                      <td class="px-4 py-2.5 text-right font-mono-tatacora">{{ $ligne->taux_annulation === null ? $tiret : rtrim(rtrim(number_format((float) $ligne->taux_annulation, 2), '0'), '.').' %' }}</td>
                      <td class="px-4 py-2.5 text-right font-mono-tatacora" style="color:#8C1D1D">{{ $ligne->montant_commission_annulation === null ? $tiret : MontantFcfa::format((string) $ligne->montant_commission_annulation) }}</td>
                      <td class="px-4 py-2.5 text-right font-mono-tatacora text-emerald-700">{{ $ligne->montant_rembourse_annulation === null ? $tiret : MontantFcfa::format((string) $ligne->montant_rembourse_annulation) }}</td>
                      <td class="px-4 py-2.5 whitespace-nowrap text-slate-500">{{ $ligne->date_annulation?->format('d/m/Y H:i') ?? $tiret }}</td>
                      <td class="px-4 py-2.5 text-slate-500">{{ $ligne->utilisateurAnnulation?->login ?? $tiret }}</td>
                    </tr>
                  @endforeach
                </tbody>
              </table>
            </div>
          @endif
        @endif {{-- fin de la condition d'onglet ouverte plus haut --}}

        {{--
            NON PORTE, ET PLUS RENDU A L'ECRAN (02/09/2026). Directive du
            Product Owner : un ecran dit ce qu'il FAIT.
            - Les deux lignes de montants restent deux lignes (PA-112) ; le
              maitre en montre d'autres qu'aucune colonne ne porte.
            - Le bouton « Facture » n'existe que si la facture existe.
            - Supprimer une reservation est INTERDIT (RG-02) : elle s'annule.
            - Plusieurs unites sur une meme fiche : `reservations.unite_id`
              est une colonne unique et NOT NULL (arbitrage PA-110 ouvert).
        --}}


      </div>
    </main>
  </div>

  {{-- ============ PANNEAU HISTORIQUE (maitre l.60-105) ============

       IL VIT HORS DU `<main>`, COMME AU MAITRE, ET CE N'EST PAS COSMETIQUE.
       Le maitre pose `<div id="panneau-historique" class="fixed inset-0 z-50
       hidden">` APRES `</main>` (l.60). La PWA le rendait a l'interieur, au
       milieu de la grille de cartes : un voile `fixed` glisse dans le flux
       d'un conteneur `overflow-y-auto`, ou il n'a rien a faire.
       `t-structure.js` le signalait comme un bloc « en trop » au coeur du
       corps de page — il l'etait.

       ⚠ Son voile ne peut pas s'ecrire `bg-black/40` : la garde de chassis
       refuse tout voile pose a la main dans une vue. La valeur du maitre est
       reprise telle quelle, en style. --}}
      @if ($historiqueOuvert)
        <div class="fixed inset-0 z-50">
          <div class="absolute inset-0" style="background:rgba(0,0,0,.4)" wire:click="$set('vue', '')"></div>
          <div class="absolute inset-y-0 right-0 w-full max-w-5xl bg-white shadow-2xl flex flex-col">
            <header class="px-5 py-4 border-b border-slate-200 flex items-start justify-between shrink-0">
              <div>
                <h2 class="text-base font-bold" style="color:var(--navy)">{{ __('pwa.reservations.hist_titre') }}</h2>
                <p class="text-[13px] text-slate-500 mt-0.5">{{ __('pwa.reservations.hist_sous_titre') }}</p>
              </div>
              <div class="flex items-center gap-2">
                {{-- Les boutons « PDF » et « Excel » du maitre (l.70-71) ne
                     sont PAS derriere la condition d'ecriture : exporter est
                     une lecture, et l'historique des reservations est
                     precisement la piece qu'un comptable consulte. --}}
                <button wire:click="$set('etatFormulaire', 'export')"
                        class="btn text-[12px] px-3 py-1.5 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.export.generer') }}</button>
                <button wire:click="$set('vue', '')" class="btn p-1.5 rounded-lg hover:bg-slate-100 text-slate-400">
                  <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" d="M18 6L6 18M6 6l12 12"/></svg>
                </button>
              </div>
            </header>

            {{-- Indicateurs — `historique-reservations.js` l.59-66. Les deux
                 cartes monétaires rendent « — » (PA-55/PA-57). --}}
            <div class="px-5 py-3 border-b border-slate-200 grid grid-cols-2 md:grid-cols-6 gap-2.5 shrink-0">
              <div class="bg-slate-50 rounded-lg px-3 py-2"><p class="text-[10px] font-bold uppercase tracking-wider text-slate-400">{{ __('pwa.reservations.hist_kpi_total') }}</p><p class="text-[15px] font-bold text-[var(--navy)]">{{ $historique->count() }}</p></div>
              <div class="bg-slate-50 rounded-lg px-3 py-2"><p class="text-[10px] font-bold uppercase tracking-wider text-slate-400">{{ __('pwa.reservations.hist_kpi_a_venir') }}</p><p class="text-[15px] font-bold text-blue-600">{{ $repartition['a_venir'] ?? 0 }}</p></div>
              <div class="bg-slate-50 rounded-lg px-3 py-2"><p class="text-[10px] font-bold uppercase tracking-wider text-slate-400">{{ __('pwa.reservations.hist_kpi_en_cours') }}</p><p class="text-[15px] font-bold text-emerald-600">{{ $repartition['en_cours'] ?? 0 }}</p></div>
              <div class="bg-slate-50 rounded-lg px-3 py-2"><p class="text-[10px] font-bold uppercase tracking-wider text-slate-400">{{ __('pwa.reservations.hist_kpi_nuitees') }}</p><p class="text-[15px] font-bold text-[var(--navy)]">{{ $nuitees }}</p></div>
              <div class="bg-slate-50 rounded-lg px-3 py-2"><p class="text-[10px] font-bold uppercase tracking-wider text-slate-400">{{ __('pwa.reservations.hist_kpi_ca') }}</p><p class="text-[15px] font-bold text-[var(--navy)]">{{ $tiret }}</p></div>
              <div class="bg-slate-50 rounded-lg px-3 py-2"><p class="text-[10px] font-bold uppercase tracking-wider text-slate-400">{{ __('pwa.reservations.hist_kpi_reste') }}</p><p class="text-[15px] font-bold text-[var(--navy)]">{{ $tiret }}</p></div>
            </div>

            {{-- Filtres — maître l.80-101 --}}
            <div class="px-5 py-3 border-b border-slate-200 flex flex-wrap gap-2 shrink-0">
              <input type="search" wire:model.live.debounce.300ms="histTerme" placeholder="{{ __('pwa.reservations.hist_recherche') }}"
                     class="champ text-[13px] border border-slate-300 rounded-lg px-3 py-2 flex-1 min-w-[180px]">
              <select wire:model.live="histEtat" class="champ text-[13px] border border-slate-300 rounded-lg px-3 py-2">
                <option value="">{{ __('pwa.reservations.hist_tous_etats') }}</option>
                <option value="a_venir">{{ __('pwa.reservations.hist_etat_a_venir') }}</option>
                <option value="en_cours">{{ __('pwa.reservations.hist_etat_en_cours') }}</option>
                <option value="termine">{{ __('pwa.reservations.hist_etat_terminees') }}</option>
                <option value="annulee">{{ __('pwa.reservations.hist_etat_annulees') }}</option>
              </select>
              <select wire:model.live="histService" class="champ text-[13px] border border-slate-300 rounded-lg px-3 py-2">
                <option value="">Tous les services</option>
                <option value="hebergement">{{ __('hebergement_pwa.reservations.service_hebergement') }}</option>
              </select>
              <input type="date" wire:model.live="histDebut" class="champ text-[13px] border border-slate-300 rounded-lg px-3 py-2">
              <input type="date" wire:model.live="histFin" class="champ text-[13px] border border-slate-300 rounded-lg px-3 py-2">
              <button wire:click="$set('histTerme', '')" class="btn text-[12px] px-3 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.reservations.hist_reinitialiser') }}</button>
            </div>

            <div class="flex-1 overflow-y-auto">
              @if ($historique->isEmpty())
                <p class="py-16 text-center text-[13px] text-slate-400">{{ __('pwa.reservations.hist_vide') }}</p>
              @else
                <table class="w-full text-[13px]">
                  {{-- Les HUIT colonnes du maître — `historique-reservations.js`
                       l.102-109. Quatre avaient disparu : Nuits, Services,
                       Total et Reste dû. --}}
                  <thead class="bg-[var(--navy)] text-[11px] uppercase tracking-wide text-white/90 font-semibold sticky top-0">
                    <tr>
                      <th class="text-left px-5 py-2.5">{{ __('pwa.reservations.hist_col_client') }}</th>
                      <th class="text-left px-4 py-2.5">{{ __('pwa.reservations.hist_col_sejour') }}</th>
                      <th class="text-right px-4 py-2.5">{{ __('pwa.reservations.hist_col_nuits') }}</th>
                      <th class="text-left px-4 py-2.5">{{ __('pwa.reservations.hist_col_unites') }}</th>
                      <th class="text-left px-4 py-2.5">{{ __('pwa.reservations.hist_col_services') }}</th>
                      <th class="text-right px-4 py-2.5">{{ __('pwa.reservations.hist_col_total') }}</th>
                      <th class="text-right px-4 py-2.5">{{ __('pwa.reservations.hist_col_reste') }}</th>
                      <th class="text-left px-4 py-2.5">{{ __('pwa.reservations.hist_col_etat') }}</th>
                    </tr>
                  </thead>
                  <tbody>
                    @foreach ($historique as $ligne)
                      @php $etatLigne = $etats[$ligne->id] ?? null; @endphp
                      <tr class="border-t border-slate-100 hover:bg-slate-50/60 {{ ($etatLigne['cle'] ?? '') === 'annulee' ? 'opacity-60' : '' }}" wire:key="hist-{{ $ligne->id }}">
                        <td class="px-5 py-2.5"><p class="font-semibold">{{ $ligne->client?->nomComplet() ?: $tiret }}</p>
                          <p class="text-[11px] text-slate-400">{{ $ligne->client?->telephone ?? $tiret }}</p></td>
                        <td class="px-4 py-2.5 whitespace-nowrap">{{ $ligne->date_arrivee->format('d/m/Y') }} → {{ $ligne->date_depart->format('d/m/Y') }}</td>
                        <td class="px-4 py-2.5 text-right">{{ $ligne->nombreNuitees() }}</td>
                        <td class="px-4 py-2.5 text-[12px] text-slate-600">{{ $ligne->unite?->numero ?? $tiret }}</td>
                        <td class="px-4 py-2.5 text-[11px] text-slate-500">{{ __('hebergement_pwa.reservations.service_hebergement') }}</td>
                        <td class="px-4 py-2.5 text-right font-semibold">{{ $tiret }}</td>
                        <td class="px-4 py-2.5 text-right text-slate-400">{{ $tiret }}</td>
                        <td class="px-4 py-2.5"><span class="px-2 py-0.5 rounded text-[11px] font-semibold {{ $etatLigne['classe'] ?? '' }}">{{ $etatLigne['libelle'] ?? $tiret }}</span></td>
                      </tr>
                    @endforeach
                  </tbody>
                </table>
              @endif
            </div>
            {{--
                NON PORTE (02/09/2026) : le bandeau de refus qui fermait ce
                panneau est retire AVEC son conteneur — une bande bordee et
                vide serait un artefact visuel, pas une simplification. Les
                montants du maitre qu'aucune colonne ne porte et les services
                autres qu'hebergement restent non portes.
            --}}
          </div>
        </div>
      @endif

  {{-- ==================== MODALES ==================== --}}

  @if ($etatFormulaire === 'reservation')
    <x-pwa.modale :titre="$reservationId ? __('pwa.reservations.modale_titre_modification') : __('pwa.reservations.modale_titre_creation')"
                  :sousTitre="__('hebergement_pwa.reservations.modale_sous_titre')"
                  largeur="760px"
                  fermer="$set('etatFormulaire', null)">
      <form wire:submit="enregistrerReservation" class="space-y-4" id="formulaire-reservation">
        {{-- ORDRE DU MAÎTRE au caractère près (`reservations.html` l.123-141) :
             Client, Type de client, Canal, [case vide de la grille], Arrivée,
             Départ. « Unité » n'y figure PAS À CETTE PLACE — chez le maître,
             l'hébergement est une LIGNE du service « Hébergement », comme les
             quatre autres services. `reservations.unite_id` étant une colonne
             UNIQUE et NOT NULL du schéma (arbitrage PA-110 ouvert : le maître
             admet plusieurs chambres, ce serveur n'en porte qu'une), le
             sélecteur d'unité est déplacé dans le bloc « Hébergement » de la
             zone de lignes ci-dessous — sa place structurelle chez le maître —
             plutôt que laissé dans cette grille où le maître ne le pose pas. --}}
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div class="groupe-champ">
            <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('pwa.reservations.champ_client') }} <span class="text-red-500">*</span></label>
            <select wire:model="rClientId" class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm bg-white">
              <option value="">{{ __('pwa.reservations.champ_client_invite') }}</option>
              @foreach ($clients as $client)
                <option value="{{ $client->id }}">{{ $client->nomComplet() }} — {{ $client->telephone }}</option>
              @endforeach
            </select>
            @error('rClientId') <p class="message-erreur text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
          </div>

          {{-- « Type de client » du maître : ATTRIBUT de la fiche M3, rendu
               en lecture — l'éditer ici modifierait une fiche client depuis
               un formulaire M1, en silence. Il s'édite sur la fiche client. --}}
          <div class="groupe-champ">
            <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('pwa.reservations.champ_type_client') }}</label>
            @php($clientChoisi = $rClientId === null ? null : $clients->firstWhere('id', $rClientId))
            <p class="w-full border border-slate-200 bg-slate-50 rounded-lg px-3 py-2.5 text-sm text-slate-600">
              {{ $clientChoisi === null ? $tiret : __(Reservations::TYPES_CLIENT[$clientChoisi->type_client] ?? 'hebergement_pwa.reservations.type_particulier') }}
            </p>
          </div>

          <div class="groupe-champ">
            <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('pwa.reservations.champ_canal') }}</label>
            {{-- Référentiel `canaux_reservation` (PA-163), jamais une liste en
                 dur : le maître a corrigé ce défaut chez lui le 24/08/2026. --}}
            <select wire:model.live="rCanalId" class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm bg-white">
              <option value="">{{ __('pwa.reservations.champ_canal_invite') }}</option>
              @foreach ($canaux as $canal)
                <option value="{{ $canal->id }}">{{ $canal->nom }}</option>
              @endforeach
            </select>
            @error('rCanalId') <p class="message-erreur text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
          </div>

          {{-- Case vide du maître (l.136 : `<div></div>`) — la grille à deux
               colonnes du maître laisse cette case libre avant les dates. --}}
          <div></div>

          <div class="groupe-champ">
            <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('pwa.reservations.champ_arrivee') }} <span class="text-red-500">*</span></label>
            <input type="date" wire:model.live="rDateArrivee" class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm">
            @error('rDateArrivee') <p class="message-erreur text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
          </div>

          <div class="groupe-champ">
            <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('pwa.reservations.champ_depart') }} <span class="text-red-500">*</span></label>
            <input type="date" wire:model.live="rDateDepart" class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm">
            @error('rDateDepart') <p class="message-erreur text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
          </div>
        </div>

        {{--
            ⚠ AUCUN BLOC PHP MULTI-INSTRUCTIONS NE SURVIT DANS LE CORPS DE
            CETTE MODALE, ET C'EST UNE LIMITE CONSTATÉE, PAS UN CHOIX DE STYLE
            (02/09/2026). À l'intérieur du slot d'`<x-pwa.modale>`, une
            variable posée par un bloc PHP multi-instructions — même hors de
            toute boucle — se rend « Undefined variable » à sa lecture
            quelques lignes plus bas, reproduit sur une affectation aussi
            triviale que `$x = 1;`. Une expression PHP unique, elle, survit,
            tout comme un appel de méthode répété : `FicheReservationServices`
            porte donc `nuits()` et `sousTotalHebergement()`, appelées
            directement là où le nombre de nuits et le sous-total sont
            affichés, jamais stockées dans une variable de vue.

            (Note technique : n'écrivez jamais le nom littéral de la directive
            PHP de bloc, arobase suivi de « php », dans un commentaire Blade
            de ce fichier — le compilateur Livewire de ce projet la repère
            même à l'intérieur d'un commentaire et désynchronise le comptage
            de ses propres balises, ce qui casse la compilation de TOUT le
            fichier avec une erreur « endif » sans rapport apparent.)
        --}}

        {{-- ============ SERVICES INCLUS — les CINQ tuiles du maître ========
             (`reservations-services.js` l.40-119 pour l'icône et la couleur,
             `reservations.html` l.144-147 pour la grille). L'hébergement est
             TOUJOURS inclus et non décochable : `reservations.unite_id` est
             NOT NULL, une fiche sans hébergement est l'arbitrage ouvert de
             PA-110, pas un choix d'écran. --}}
        <div>
          <label class="block text-[15px] font-semibold text-slate-700 mb-2">{{ __('pwa.reservations.services_titre') }} <span class="text-red-500">*</span></label>
          @error('rLignes') <p class="message-erreur text-[12px] text-red-600 mb-2">{{ $message }}</p> @enderror
          <div class="grid grid-cols-2 sm:grid-cols-3 gap-2.5">
            <div class="border-2 rounded-lg p-3 flex flex-col items-center gap-1.5 cursor-not-allowed" style="border-color:{{ \App\Pwa\Support\CouleursServices::texte('hebergement') }};background:{{ \App\Pwa\Support\CouleursServices::texte('hebergement') }}">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="2">{!! \App\Pwa\Support\CouleursServices::icone('hebergement') !!}</svg>
              <span class="text-[13px] font-semibold text-white">{{ __('accueil_pwa.services.hebergement') }}</span>
            </div>
            @foreach (['restauration', 'bar', 'tourisme', 'vehicule'] as $service)
              @php($coche = in_array($service, $rServices, true))
              <button type="button" wire:click="basculerServiceFiche('{{ $service }}')"
                      class="border-2 rounded-lg p-3 flex flex-col items-center gap-1.5 transition-colors"
                      style="border-color:{{ $coche ? \App\Pwa\Support\CouleursServices::texte($service) : '#E2E8F0' }};background:{{ $coche ? \App\Pwa\Support\CouleursServices::texte($service) : 'white' }}">
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="{{ $coche ? 'white' : \App\Pwa\Support\CouleursServices::texte($service) }}" stroke-width="2">{!! \App\Pwa\Support\CouleursServices::icone($service) !!}</svg>
                <span class="text-[13px] font-semibold {{ $coche ? 'text-white' : 'text-slate-600' }}">{{ \App\Pwa\Support\CouleursServices::libelle($service) }}</span>
              </button>
            @endforeach
          </div>
        </div>

        {{-- ============ ZONE DE LIGNES — un bloc PAR SERVICE, markup du
             maître (`rendreZoneLignes()`, `reservations-services.js`
             l.226-273) : bordure gauche colorée, titre, bouton « + Ajouter »
             dans l'en-tête, bandeau nuits (hébergement), lignes, sous-total du
             service. Jamais une liste plate — chaque service reste un bloc,
             comme chez le maître. --}}
        <div class="space-y-3">
          {{-- Bloc HÉBERGEMENT — toujours présent, UNE seule ligne : l'unité
               choisie. `rUniteId` n'est pas une ligne de `rLignes` (le schéma
               ne porte qu'une seule unité par fiche, PA-110), mais le bloc
               reprend le markup du maître pour ce service : bandeau nuits,
               sélecteur, quantité en lecture seule, sous-total. --}}
          <div class="border border-slate-200 rounded-lg p-3.5" style="border-left:3px solid {{ \App\Pwa\Support\CouleursServices::texte('hebergement') }}">
            <div class="flex items-center justify-between mb-2.5">
              <span class="text-[15px] font-bold" style="color:{{ \App\Pwa\Support\CouleursServices::texte('hebergement') }}">{{ __('accueil_pwa.services.hebergement') }}</span>
            </div>
            <p class="text-[12px] mb-2 px-2.5 py-1.5 rounded-lg" style="background:#F1F5F9;color:#334155">
              @if (\App\Pwa\Support\FicheReservationServices::nuits($rDateArrivee, $rDateDepart) === null)
                {{ __('pwa.reservations.nuits_banner_manquant') }}
              @else
                {!! __('pwa.reservations.nuits_banner_connu', ['nombre' => \App\Pwa\Support\FicheReservationServices::nuits($rDateArrivee, $rDateDepart)]) !!}
              @endif
            </p>
            <div class="flex items-center gap-2">
              <select wire:model.live="rUniteId" class="champ flex-1 border border-slate-200 rounded-lg px-2.5 py-2 text-[15px] bg-white">
                <option value="">{{ __('pwa.reservations.champ_unite_invite') }}</option>
                @foreach ($unites as $unite)
                  <option value="{{ $unite->id }}">{{ $unite->numero }} — {{ $unite->categorie?->libelle ?? $tiret }} — {{ \App\Pwa\Support\MontantFcfa::format((string) ($unite->categorie?->tarif_base ?? '0')) }}</option>
                @endforeach
              </select>
              <input type="text" value="{{ \App\Pwa\Support\FicheReservationServices::nuits($rDateArrivee, $rDateDepart) ?? $tiret }}" title="{{ __('pwa.reservations.qte_nuits') }}" readonly tabindex="-1"
                     class="w-20 border border-slate-200 rounded-lg px-2 py-2 text-[15px] text-center bg-slate-100 text-slate-600 font-semibold cursor-not-allowed">
              <span class="font-mono-tatacora text-[15px] font-semibold w-24 text-right shrink-0" style="color:{{ \App\Pwa\Support\CouleursServices::texte('hebergement') }}">{{ \App\Pwa\Support\MontantFcfa::format(\App\Pwa\Support\FicheReservationServices::sousTotalHebergement($unites, $rUniteId, $rDateArrivee, $rDateDepart)) }}</span>
            </div>
            @error('rUniteId') <p class="message-erreur text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
            <p class="text-right text-[13px] text-slate-500 mt-2 pt-2 border-t border-slate-100">
              {{ __('pwa.reservations.sous_total_service', ['service' => __('accueil_pwa.services.hebergement')]) }}
              <span class="font-mono-tatacora font-bold" style="color:{{ \App\Pwa\Support\CouleursServices::texte('hebergement') }}">{{ \App\Pwa\Support\MontantFcfa::format(\App\Pwa\Support\FicheReservationServices::sousTotalHebergement($unites, $rUniteId, $rDateArrivee, $rDateDepart)) }}</span>
            </p>
          </div>

          {{-- Les blocs des quatre autres services, un par service COCHÉ.

               ⚠ AUCUNE VARIABLE N'EST ASSIGNÉE PAR UN BLOC PHP DANS CETTE
               BOUCLE, ET C'EST DÉLIBÉRÉ (limite constatée du compilateur
               Livewire sur ce formulaire, 02/09/2026) : la boucle sur
               `$rServices` porte plus bas des liaisons `wire:model` sur des
               index de tableau (`rLignes.INDEX.…`), et toute variable
               assignée par un bloc PHP multi-instructions à l'intérieur de
               cette boucle précise se perd avant la ligne suivante —
               « Undefined variable », reproduit sur une affectation aussi
               triviale que `$x = 1;`. Chaque libellé et chaque sous-total est
               donc un APPEL DE MÉTHODE STATIQUE répété, jamais une variable
               de vue : une méthode n'a pas de « scope de vue » à perdre. Voir
               `FicheReservationServices` et
               `CouleursServices::libelle()`/`labelLigne()`. --}}
          @foreach ($rServices as $service)
            <div class="border border-slate-200 rounded-lg p-3.5" style="border-left:3px solid {{ \App\Pwa\Support\CouleursServices::texte($service) }}">
              <div class="flex items-center justify-between mb-2.5">
                <span class="text-[15px] font-bold" style="color:{{ \App\Pwa\Support\CouleursServices::texte($service) }}">{{ \App\Pwa\Support\CouleursServices::libelle($service) }}</span>
                <button type="button" wire:click="ajouterLigneFiche('{{ $service }}')"
                        class="text-[13px] font-semibold flex items-center gap-1" style="color:var(--navy)">
                  <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3"><path stroke-linecap="round" d="M12 5v14M5 12h14"/></svg>
                  {{ __('pwa.reservations.ligne_ajouter') }} {{ \App\Pwa\Support\CouleursServices::labelLigne($service) }}
                </button>
              </div>

              @if (($cataloguesFiche[$service] ?? []) === [])
                <p class="text-[13px] text-slate-400 italic">{{ __('pwa.reservations.ligne_aucun_element', ['service' => mb_strtolower(\App\Pwa\Support\CouleursServices::libelle($service))]) }}</p>
              @endif

              <div class="space-y-2">
                @if (\App\Pwa\Support\FicheReservationServices::indexParService($rLignes, $service) === [])
                  <p class="text-[13px] text-slate-300">{{ __('pwa.reservations.ligne_aucune') }}</p>
                @endif
                @foreach (\App\Pwa\Support\FicheReservationServices::indexParService($rLignes, $service) as $index)
                  <div class="flex items-center gap-2" wire:key="ligne-fiche-{{ $index }}">
                    <select wire:model.live="rLignes.{{ $index }}.source_id" class="champ flex-1 border border-slate-200 rounded-lg px-2.5 py-2 text-[15px] bg-white">
                      <option value="">{{ __('pwa.reservations.ligne_choisir') }}</option>
                      @foreach ($cataloguesFiche[$service] ?? [] as $element)
                        <option value="{{ $element['id'] }}" @selected($element['id'] === $rLignes[$index]['source_id'])>{{ $element['libelle'] }} — {{ \App\Pwa\Support\MontantFcfa::format($element['prix']) }}</option>
                      @endforeach
                    </select>
                    <input type="number" min="1" wire:model.live="rLignes.{{ $index }}.quantite"
                           title="{{ __(Reservations::LIBELLES_QUANTITE[$service] ?? 'pwa.reservations.qte_quantite') }}"
                           class="champ w-20 border border-slate-200 rounded-lg px-2 py-2 text-[15px] text-center">
                    <span class="font-mono-tatacora text-[15px] font-semibold w-24 text-right shrink-0" style="color:{{ \App\Pwa\Support\CouleursServices::texte($service) }}">
                      {{ \App\Pwa\Support\MontantFcfa::format(\App\Pwa\Support\FicheReservationServices::sousTotalLigne($cataloguesFiche, $service, $rLignes[$index]['source_id'], $rLignes[$index]['quantite'])) }}
                    </span>
                    <button type="button" wire:click="retirerLigneFiche({{ $index }})"
                            class="text-slate-300 hover:text-red-500 shrink-0" aria-label="{{ __('pwa.reservations.ligne_retirer') }}">✕</button>
                  </div>
                  @error('rLignes.'.$index.'.source_id') <p class="message-erreur text-[12px] text-red-600">{{ $message }}</p> @enderror
                  @error('rLignes.'.$index.'.quantite') <p class="message-erreur text-[12px] text-red-600">{{ $message }}</p> @enderror
                @endforeach
              </div>

              <p class="text-right text-[13px] text-slate-500 mt-2 pt-2 border-t border-slate-100">
                {{ __('pwa.reservations.sous_total_service', ['service' => \App\Pwa\Support\CouleursServices::libelle($service)]) }}
                <span class="font-mono-tatacora font-bold" style="color:{{ \App\Pwa\Support\CouleursServices::texte($service) }}">{{ \App\Pwa\Support\MontantFcfa::format(\App\Pwa\Support\FicheReservationServices::sousTotal($rLignes, $cataloguesFiche, $service)) }}</span>
              </p>
            </div>
          @endforeach
        </div>

        {{-- ============ RÉCAPITULATIF — le bloc du maître ============ --}}
        <div class="border-t border-slate-200 pt-4">
          <h3 class="text-[15px] font-bold text-slate-700 mb-3">{{ __('pwa.reservations.recap_titre') }}</h3>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4 mb-3">
            <div class="groupe-champ">
              <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('pwa.reservations.champ_remise') }}</label>
              <div class="flex gap-2">
                <select wire:model.live="rRemiseType" class="champ border border-slate-200 rounded-lg px-2 py-2.5 text-[15px] bg-white">
                  <option value="aucune">{{ __('pwa.reservations.remise_aucune') }}</option>
                  <option value="pourcentage">%</option>
                  <option value="montant">FCFA</option>
                </select>
                <input type="number" min="0" wire:model.live="rRemiseValeur" @disabled($rRemiseType === 'aucune')
                       class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm {{ $rRemiseType === 'aucune' ? 'bg-slate-50 text-slate-400' : '' }}">
              </div>
              @error('rRemiseValeur') <p class="message-erreur text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
            </div>
            <div class="groupe-champ">
              <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('pwa.reservations.champ_acompte') }}</label>
              <input type="number" min="0" step="500" wire:model.live="rAcompte" class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm">
              @error('rAcompte') <p class="message-erreur text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
            </div>
            <div class="groupe-champ sm:col-span-2">
              <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('pwa.reservations.champ_mode_paiement') }}</label>
              {{-- Les QUATRE modes du maître — pas d'« Espèces » chez lui, et
                   on ne complète pas son registre sans décision. --}}
              <select wire:model="rModePaiement" class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm bg-white">
                <option value="">{{ __('pwa.reservations.mode_invite') }}</option>
                @foreach (Reservations::MODES_PAIEMENT as $valeur => $cle)
                  <option value="{{ $valeur }}">{{ __($cle) }}</option>
                @endforeach
              </select>
              @error('rModePaiement') <p class="message-erreur text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
            </div>
          </div>
          {{-- Totaux CALCULÉS, en lecture seule — jamais des champs (règle
               n° 3). `null` tant que la fiche est incomplète : pas de séjour
               gratuit affiché sur une fiche à moitié saisie. --}}
          @if ($recapFiche !== null)
            <div class="bg-slate-50 rounded-lg p-4 space-y-1.5 text-[15px]">
              <div class="flex justify-between text-slate-500"><span>{{ __('pwa.reservations.recap_sous_total') }}</span><span>{{ \App\Pwa\Support\MontantFcfa::format($recapFiche['sous_total']) }}</span></div>
              <div class="flex justify-between text-slate-500"><span>{{ __('pwa.reservations.champ_remise') }}</span><span>- {{ \App\Pwa\Support\MontantFcfa::format($recapFiche['remise']) }}</span></div>
              <div class="flex justify-between font-bold text-slate-800 border-t border-slate-200 pt-1.5"><span>{{ __('pwa.reservations.recap_total') }}</span><span>{{ \App\Pwa\Support\MontantFcfa::format($recapFiche['total']) }}</span></div>
              <div class="flex justify-between text-slate-500"><span>{{ __('pwa.reservations.recap_acompte') }}</span><span>- {{ \App\Pwa\Support\MontantFcfa::format($recapFiche['acompte']) }}</span></div>
              <div class="flex justify-between font-bold border-t border-slate-200 pt-1.5" style="color:var(--gold)"><span>{{ __('pwa.reservations.recap_reste') }}</span><span>{{ \App\Pwa\Support\MontantFcfa::format($recapFiche['reste']) }}</span></div>
            </div>
          @endif
        </div>
      </form>

      <x-slot:pied>
        <button type="button" wire:click="$set('etatFormulaire', null)"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="submit" form="formulaire-reservation"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('hebergement_pwa.reservations.bouton_enregistrer') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  {{-- Maître l.245-268, portée au mot près. Le type de client est le registre
       FERMÉ du schéma (`particulier|groupe|agence|structure`) : la fiche de
       réservation du maître dit « Entreprise » là où le schéma stocke
       « structure », et les confondre casse la synchronisation. --}}
  @if ($etatFormulaire === 'client')
    <x-pwa.modale :titre="__('hebergement_pwa.reservations.modale_client_titre')"
                  :sousTitre="__('hebergement_pwa.reservations.modale_client_sous_titre')"
                  largeur="420px"
                  fermer="$set('etatFormulaire', null)">
      <form wire:submit="enregistrerClient" class="space-y-4" id="formulaire-nouveau-client">
        <div class="groupe-champ">
          <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('hebergement_pwa.reservations.champ_nom') }} <span class="text-red-500">*</span></label>
          <input type="text" wire:model="clientNom" placeholder="{{ __('hebergement_pwa.reservations.champ_nom_invite') }}"
                 class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm">
          @error('clientNom') <p class="message-erreur text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>

        <div class="groupe-champ">
          <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('hebergement_pwa.reservations.champ_telephone') }} <span class="text-red-500">*</span></label>
          <input type="tel" wire:model="clientTelephone" placeholder="{{ __('hebergement_pwa.reservations.champ_telephone_invite') }}"
                 class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm">
          @error('clientTelephone') <p class="message-erreur text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>

        <div class="groupe-champ">
          <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('hebergement_pwa.reservations.champ_type_client') }}</label>
          <select wire:model="clientType" class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm bg-white">
            @foreach (Reservations::TYPES_CLIENT as $valeur => $cle)
              <option value="{{ $valeur }}">{{ __($cle) }}</option>
            @endforeach
          </select>
        </div>

        <p class="text-[12px] text-slate-500">{{ __('hebergement_pwa.reservations.client_droit_m3') }}</p>
      </form>

      <x-slot:pied>
        <button type="button" wire:click="$set('etatFormulaire', null)"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="submit" form="formulaire-nouveau-client"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('hebergement_pwa.reservations.bouton_ajouter_le_client') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  {{-- Annulation avec commission et remboursement — EF-M1-06, séance client
       du 18-20/08/2026 (§4.3, §4.4, §6.1, §6.3) précisée par instruction du
       Product Owner (01/09/2026). RG-02 reste tenue : le geste est une
       ANNULATION, rien n'est effacé. Le taux est PRÉ-REMPLI depuis le
       paramètre système et reste ÉDITABLE ici, ligne par ligne. --}}
  @if ($etatFormulaire === 'annulation' && $aAnnuler !== null)
    <x-pwa.modale :titre="__('hebergement_pwa.reservations.annulation_titre')"
                  :sousTitre="__('hebergement_pwa.reservations.annulation_element', [
                      'client' => $aAnnuler->client?->nomComplet() ?: $tiret,
                      'arrivee' => $aAnnuler->date_arrivee->format('d/m/Y'),
                      'depart' => $aAnnuler->date_depart->format('d/m/Y'),
                  ])"
                  largeur="480px"
                  fermer="$set('etatFormulaire', null)">
      <form wire:submit="annulerReservation('{{ $aAnnuler->id }}')" class="space-y-4" id="formulaire-annulation">
        @error('annulation') <p class="message-erreur text-[12px] text-red-600">{{ $message }}</p> @enderror

        {{-- Délai INFORMATIF — voir AnnulationReservationService sur
             pourquoi il n'automatise pas le taux : le compte rendu client
             ne valide qu'UN seul cas (« moins de 24h → 50 % ») et renvoie
             explicitement le reste à confirmation ultérieure (§4.4, note). --}}
        <div class="rounded-lg px-3 py-2.5 text-[12px]"
             style="background:{{ $aSousLeSeuil ? '#FDF3E0' : '#F1F5F9' }};color:{{ $aSousLeSeuil ? '#8A6412' : '#334155' }}">
          @if ($aDelaiHeures !== null && $aDelaiHeures >= 0)
            {{ __('hebergement_pwa.reservations.annulation_delai', ['heures' => number_format($aDelaiHeures, 1)]) }}
          @else
            {{ __('hebergement_pwa.reservations.annulation_delai_passe') }}
          @endif
          @if ($aSousLeSeuil)
            — {{ __('hebergement_pwa.reservations.annulation_sous_seuil') }}
          @endif
        </div>

        <div class="bg-slate-50 rounded-lg p-3 text-[13px] space-y-1">
          <div class="flex justify-between">
            <span class="text-slate-500">{{ __('hebergement_pwa.reservations.annulation_montant_total') }}</span>
            <span class="font-mono-tatacora font-semibold">{{ MontantFcfa::format($aAnnuler->montantTotal() ?? '0') }}</span>
          </div>
          <div class="flex justify-between">
            <span class="text-slate-500">{{ __('hebergement_pwa.reservations.annulation_acompte_verse') }}</span>
            <span class="font-mono-tatacora font-semibold">{{ MontantFcfa::format((string) $aAnnuler->acompte) }}</span>
          </div>
        </div>

        <div class="groupe-champ">
          <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('hebergement_pwa.reservations.annulation_champ_taux') }} <span class="text-red-500">*</span></label>
          <div class="flex items-center gap-2">
            <input type="number" min="0" max="100" step="0.01" wire:model.live="aTaux"
                   class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm">
            <span class="text-slate-400 text-sm shrink-0">%</span>
          </div>
          @error('aTaux') <p class="message-erreur text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
          <p class="text-[11px] text-slate-400 mt-1">{{ __('hebergement_pwa.reservations.annulation_taux_aide') }}</p>
        </div>

        {{-- « Si l'argent a déjà été encaissé (acompte versé), le montant
             remboursé doit pouvoir être saisi SOIT en pourcentage SOIT en
             montant numéraire » (instruction du Product Owner). Rien à
             restituer si l'acompte est nul — la section n'a pas de sens. --}}
        @if (bccomp((string) $aAnnuler->acompte, '0.00', 2) > 0)
          <div class="groupe-champ">
            <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('hebergement_pwa.reservations.annulation_champ_remboursement') }}</label>
            <div class="flex gap-2">
              <select wire:model.live="aModeRemboursement" class="champ border border-slate-200 rounded-lg px-2 py-2.5 text-[15px] bg-white">
                <option value="pourcentage">{{ __('hebergement_pwa.reservations.annulation_mode_pourcentage') }}</option>
                <option value="montant">{{ __('hebergement_pwa.reservations.annulation_mode_montant') }}</option>
              </select>
              <input type="number" min="0" step="{{ $aModeRemboursement === 'pourcentage' ? '0.01' : '1' }}" wire:model.live="aRembourseValeur"
                     class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm">
            </div>
            @error('aRembourseValeur') <p class="message-erreur text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
            <p class="text-[11px] text-slate-400 mt-1">{{ __('hebergement_pwa.reservations.annulation_remboursement_aide') }}</p>
          </div>
        @else
          <p class="text-[12px] text-slate-400 italic">{{ __('hebergement_pwa.reservations.annulation_aucun_acompte') }}</p>
        @endif

        <p class="text-[12px] rounded-lg px-3 py-2.5" style="background:#FDECEC;color:#8C1D1D">
          {{-- `{!! !!}` : la chaine porte un `<strong>` (comme 25 autres
               rappels du depot) et n'interpole AUCUNE donnee utilisateur.
               Rendue echappee, elle affichait ses balises a l'ecran
               (constate par le PO le 03/09/2026). --}}
          {!! __('hebergement_pwa.reservations.annulation_rappel') !!}
        </p>
      </form>

      <x-slot:pied>
        <button type="button" wire:click="$set('etatFormulaire', null)"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="submit" form="formulaire-annulation"
                class="text-[13px] px-4 py-2 rounded-lg bg-red-600 text-white font-semibold">{{ __('hebergement_pwa.reservations.annulation_confirmer') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  {{-- Maître l.193-210 : la modale garde ses mots. Le PAPIER, lui, s'appelle
       « CONFIRMATION DE RÉSERVATION » — imprimer « FACTURE » sur un document
       sans numéro ni cachet produirait un faux document fiscal (PA-113). --}}
  @if ($confirmee !== null)
    <x-pwa.modale :titre="__('hebergement_pwa.reservations.modale_impression_titre')"
                  largeur="420px"
                  fermer="$set('reservationConfirmee', null)">
      <p class="text-sm text-slate-500 text-center">{{ __('hebergement_pwa.reservations.modale_impression_question') }}</p>
      <p class="text-[12px] text-slate-500 rounded-lg px-3 py-2.5" style="background:#FDF3E0;color:#8A6412">
        {{ __('hebergement_pwa.reservations.modale_impression_avertissement') }}
      </p>

      <x-slot:pied>
        <button type="button" wire:click="$set('reservationConfirmee', null)"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('hebergement_pwa.reservations.modale_impression_plus_tard') }}</button>
        <button type="button" wire:click="imprimerConfirmation('{{ $confirmee->id }}')"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('hebergement_pwa.reservations.modale_impression_imprimer') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  {{-- Maître l.213-225 : « Détail — », et son bouton « Fermer ». --}}
  @if ($detail !== null)
    <x-pwa.modale :titre="__('hebergement_pwa.reservations.modale_detail_titre', ['reference' => $detail->client?->nomComplet() ?: $tiret])"
                  largeur="480px"
                  fermer="$set('detailId', null)">
      <dl class="text-[13px] space-y-2">
        <div class="flex justify-between"><dt class="text-slate-400">{{ __('pwa.reservations.champ_unite') }}</dt><dd class="font-semibold">{{ $detail->unite?->numero ?? $tiret }}</dd></div>
        <div class="flex justify-between"><dt class="text-slate-400">{{ __('pwa.reservations.champ_arrivee') }}</dt><dd class="font-semibold">{{ $detail->date_arrivee->format('d/m/Y') }}</dd></div>
        <div class="flex justify-between"><dt class="text-slate-400">{{ __('pwa.reservations.champ_depart') }}</dt><dd class="font-semibold">{{ $detail->date_depart->format('d/m/Y') }}</dd></div>
        <div class="flex justify-between"><dt class="text-slate-400">{{ __('pwa.reservations.hist_col_nuits') }}</dt><dd class="font-semibold">{{ $detail->nombreNuitees() }}</dd></div>
        <div class="flex justify-between"><dt class="text-slate-400">{{ __('pwa.reservations.champ_acompte') }}</dt><dd class="font-semibold font-mono-tatacora">{{ MontantFcfa::format((string) $detail->acompte) }}</dd></div>
        {{-- Les deux états sont montrés côte à côte, et c'est délibéré : le
             statut STOCKÉ ne vieillit pas, l'état du jour se déduit des dates
             (PA-111). Les confondre ferait lire « à venir » sur un séjour fini. --}}
        <div class="flex justify-between"><dt class="text-slate-400">{{ __('hebergement_pwa.reservations.detail_statut') }}</dt><dd class="font-semibold">{{ $detail->statut }}</dd></div>
        <div class="flex justify-between"><dt class="text-slate-400">{{ __('hebergement_pwa.reservations.detail_etat_derive') }}</dt><dd class="font-semibold">{{ $etats[$detail->id]['libelle'] ?? $tiret }}</dd></div>
      </dl>

      {{--
          NON PORTE (02/09/2026) : les montants supplementaires du maitre et le
          motif d'annulation n'ont pas de colonne serveur. Le refus n'est plus
          rendu dans la modale de detail, il se lit ici.
      --}}

      <x-slot:pied>
        {{-- « Annuler la réservation » DANS la fiche (demande PO du
             02/09/2026) : la croix de la carte reste, la fiche offre le même
             geste là où l'on relit la réservation avant de trancher. Même
             garde $peutAnnuler que la carte (EF-M1-06 : le remboursement
             engage la caisse), et jamais sur une réservation déjà annulée. --}}
        @if ($peutAnnuler && $detail->statut !== 'annulee')
          <button type="button" wire:click="confirmerAnnulation('{{ $detail->id }}')"
                  class="mr-auto text-[13px] px-4 py-2 rounded-lg border border-red-300 text-red-600 font-semibold hover:bg-red-50">{{ __('hebergement_pwa.reservations.annulation_bouton_fiche') }}</button>
        @endif
        <button type="button" wire:click="$set('detailId', null)"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('hebergement_pwa.reservations.modale_detail_fermer') }}</button>
        @if ($peutEcrire)
          <button type="button" wire:click="ouvrirModificationReservation('{{ $detail->id }}')"
                  class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('pwa.reservations.action_modifier') }}</button>
        @endif
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  @if ($etatFormulaire === 'export')
    @include('pwa.partials.modale-export', [
      'titre' => __('hebergement_pwa.reservations.export_titre'),
      'sousTitre' => __('hebergement_pwa.reservations.export_sous_titre'),
    ])
  @endif

  @include('pwa.partials.acces-rapide')
</div>
