{{--
    M12 — NOTIFICATIONS.

    Maitre : `prototype_v2/pages/m12-notifications-hub.html` et son moteur
    `prototype_v2/assets/js/notifications-engine.js`.

    ## Ce que cet ecran sert reellement

    Le REFERENTIEL : modeles de message (CRUD complet), registre ferme des
    evenements declencheurs, registre ferme des canaux avec ce qui bloque
    chacun, et journal des envois lu sur `notifications_envoyees`.

    Depuis le 01/09/2026, la FILE D'ATTENTE est reelle : « Detecter
    maintenant » compose de vrais messages a partir de cinq declencheurs sur
    neuf (voir le docblock de `App\Pwa\Livewire\Notifications\Hub`), et
    « Transmis a la main » / « Abandonner » les en sortent reellement.

    ## « Envoyer » est REEL par e-mail depuis le 01/09/2026 (directive du PO)

    Le bouton n'apparait QUE sur une entree du canal e-mail dont l'adresse
    du destinataire est connue ET qu'un mailer reellement configure existe
    (`ConfigurationMailService` — voir le docblock du composant). Sans l'une
    des deux conditions, la RAISON est affichee a la place du bouton, jamais
    un bouton grise (Article 3.3).

    WhatsApp, Android et SMS restent SANS ce geste : l'API WhatsApp Business
    n'est pas contractee, l'application Flutter qui porterait le canal
    Android n'enregistre aucun appareil, et aucun agregateur SMS n'est
    retenu. Leur ligne porte l'etiquette « a parametrer au deploiement » a
    la place. RG-20 (diffusion automatique) reste non implementee pour ces
    trois canaux — une dependance externe, pas un oubli de developpement. Le
    maitre ecrit lui-meme la consequence d'un faux « envoye » : « pire que
    pas de module du tout : le Gerant croirait son client prevenu » — c'est
    pourquoi un echec d'envoi laisse le message EN FILE, jamais un statut
    qui affirme un depart que rien n'a verifie.

    ## La casse et la ponctuation sont celles du MAITRE

    Apostrophe typographique comprise. `Canal`, pas `CANAL` : `uppercase` est
    une regle CSS, elle ne s'applique ni au CSV ni au PDF.
--}}
@php
    use App\Domain\Notifications\Services\RegistreCanaux;

    // Classes d'onglets : directive PO du 01/09/2026, UN SEUL AUTEUR —
    // voir le docblock de `App\Pwa\Support\Onglets`.
    $classeOnglet = static fn (bool $actif): string => \App\Pwa\Support\Onglets::classes($actif);

    $entete = static fn (string $libelle, bool $gauche = false): string => '<th class="px-3 py-2.5 '
        . ($gauche ? 'text-left' : 'text-right')
        . ' text-[11px] uppercase tracking-wide text-white/90 font-semibold">'
        . e($libelle) . '</th>';

    $classeBulle = static fn (string $canal): string => match ($canal) {
        RegistreCanaux::EMAIL => 'bg-blue-50 border-blue-200 text-blue-900',
        RegistreCanaux::ANDROID, RegistreCanaux::SMS => 'bg-slate-50 border-slate-200 text-slate-700',
        default => 'bg-emerald-50 border-emerald-200 text-emerald-900',
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

  {{-- « Envoyer » (01/09/2026) : la raison d'un envoi non abouti EST affichée,
       jamais un échec silencieux (PA-59/60/61). Aucun canal de toast rouge
       n'existait encore sur cet écran — celui-ci reprend le motif visuel du
       toast vert ci-dessus, en rouge. --}}
  @if (session('pwa-erreur'))
    <div class="fixed top-5 right-5 z-50 flex items-center gap-3 px-4 py-3 rounded-xl shadow-xl text-white text-[13px] font-medium no-print"
         style="background:var(--erreur)"
         x-data="{ visible: true }" x-show="visible" x-init="setTimeout(() => visible = false, 6000)">
      <span>{{ session('pwa-erreur') }}</span>
      <button type="button" @click="visible = false" class="ml-2 text-white/80 hover:text-white">✕</button>
    </div>
  @endif

  <div class="flex flex-1 overflow-hidden">
    @include('pwa.partials.menu-lateral')

    <main class="flex-1 overflow-y-auto">
      <div class="max-w-[1440px] mx-auto p-5 lg:p-8">

        {{-- EN-TETE — maitre l.36-49 --}}
        <div class="mb-4 flex flex-wrap items-start justify-between gap-3">
          <div>
            <div class="flex items-center gap-2.5">
              <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--navy)" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M18 8a6 6 0 00-12 0c0 7-3 9-3 9h18s-3-2-3-9M13.73 21a2 2 0 01-3.46 0"/></svg>
              <h1 class="text-lg lg:text-xl font-bold" style="color:var(--navy)">{{ __('notifications_pwa.titre') }}</h1>
            </div>
            <p class="text-[15px] text-slate-500 mt-1.5">{{ __('notifications_pwa.sous_titre') }}</p>
          </div>

          <div class="flex flex-wrap gap-2">
            {{-- « Detecter maintenant » — REEL depuis le 01/09/2026 (voir le
                 docblock du composant). --}}
            @if ($peutEcrire)
              <button type="button" wire:click="detecterMaintenant" wire:loading.attr="disabled"
                      class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold hover:opacity-90">{{ __('notifications_pwa.detecter_maintenant') }}</button>
            @endif
            {{-- Exporter est une LECTURE : offert a tout role qui peut ouvrir
                 l'ecran.

                 ⚠ DÉROGATION PO du 01/09/2026 — le maître
                 (`m12-notifications-hub.html` l.49) n'offre qu'un bouton
                 « PDF » ; la PWA élargit déjà à l'Excel via la modale
                 partagée. Les deux boutons d'entrée sont désormais UN
                 bouton « Exporter » ; le choix PDF/Excel reste dans la
                 modale. Registre : `App\Pwa\Support\DerogationsMaquette`
                 (export_bouton_unique). --}}
            <button type="button" wire:click="ouvrirExport" wire:loading.attr="disabled"
                    class="text-[13px] px-3.5 py-2 rounded-lg border border-slate-300 bg-white hover:bg-slate-50">{{ __('pwa.export.bouton') }}</button>
          </div>
        </div>

        {{-- LE BANDEAU QUI DOIT RESTER EN TETE, QUOI QU'IL ARRIVE — maitre l.52-66.
             Il est rendu MOT POUR MOT : c'est la seule phrase de la page qui
             dise au Gerant que rien ne part. --}}
        <div class="rounded-xl p-4 mb-5" style="background:#FEF2F2;border:1px solid #FECACA">
          <div class="flex items-start gap-3">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#DC2626" stroke-width="2" class="shrink-0 mt-0.5"><path stroke-linecap="round" stroke-linejoin="round" d="M12 9v4M12 17h.01M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z"/></svg>
            <div>
              <p class="text-[14px] font-bold" style="color:#7F1D1D">{{ __('notifications_pwa.bandeau_titre') }}</p>
              <p class="text-[13px] mt-1" style="color:#7F1D1D">{{ __('notifications_pwa.bandeau_texte') }}</p>
            </div>
          </div>
        </div>

        {{-- BANDE D'INDICATEURS — accordeon (derogation `DerogationsMaquette`).
             Les six cartes du maitre sont TOUTES rendues depuis le
             01/09/2026 : la file d'attente est reelle. --}}
        <div x-data="{ ouverts: localStorage.getItem('pwa_kpis_m12') !== 'false' }" class="mb-5">
          <button type="button"
                  @click="ouverts = !ouverts; localStorage.setItem('pwa_kpis_m12', ouverts)"
                  class="w-full flex items-center justify-between px-4 py-3 bg-white border border-slate-200 rounded-xl">
            <span class="text-sm font-bold text-slate-700">{{ __('notifications_pwa.kpis_accordeon') }}</span>
            <span class="text-[11px] text-slate-400 font-normal hidden sm:inline">{{ __('notifications_pwa.kpis_aide') }}</span>
          </button>

          <div x-show="ouverts" class="grid grid-cols-2 lg:grid-cols-6 gap-3 mt-3">
            <div class="bg-white rounded-xl border border-slate-200 p-3.5">
              <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('notifications_pwa.kpi_en_attente') }}</div>
              <div class="text-[17px] font-bold mt-1" style="color:var(--navy)">{{ $nombreEnAttente }}</div>
              <div class="text-[11px] text-slate-400 mt-0.5">{{ __('notifications_pwa.kpi_en_attente_detail') }}</div>
            </div>

            <div class="bg-white rounded-xl border border-slate-200 p-3.5">
              <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('notifications_pwa.kpi_envoyes') }}</div>
              {{-- COMPTE en base, jamais pose : il vaut zero tant que rien n'a
                   ete accepte par un transport reel, pas parce qu'une
                   constante le dit (PA-61). Rouge tant qu'il est nul (rien
                   n'est encore parti), vert des le premier envoi reel. --}}
              <div class="text-[17px] font-bold mt-1 {{ $nombreEnvoisReels > 0 ? 'text-emerald-600' : 'text-red-600' }}">{{ $nombreEnvoisReels }}</div>
              <div class="text-[11px] text-slate-400 mt-0.5">{{ __('notifications_pwa.kpi_envoyes_detail') }}</div>
            </div>

            <div class="bg-white rounded-xl border border-slate-200 p-3.5">
              <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('notifications_pwa.kpi_traites') }}</div>
              <div class="text-[17px] font-bold mt-1 text-emerald-600">{{ $nombreTraites }}</div>
              <div class="text-[11px] text-slate-400 mt-0.5">{{ __('notifications_pwa.kpi_traites_detail') }}</div>
            </div>

            <div class="bg-white rounded-xl border border-slate-200 p-3.5">
              <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('notifications_pwa.kpi_abandonnes') }}</div>
              <div class="text-[17px] font-bold mt-1" style="color:var(--navy)">{{ $nombreAbandonnes }}</div>
              <div class="text-[11px] text-slate-400 mt-0.5">{{ __('notifications_pwa.kpi_abandonnes_detail') }}</div>
            </div>

            <div class="bg-white rounded-xl border border-slate-200 p-3.5">
              <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('notifications_pwa.kpi_modeles') }}</div>
              <div class="text-[17px] font-bold mt-1" style="color:var(--navy)">{{ $nombreModelesActifs }} / {{ $nombreModeles }}</div>
              <div class="text-[11px] text-slate-400 mt-0.5">{{ __('notifications_pwa.kpi_modeles_detail', ['nombre' => $nombreDeclencheurs]) }}</div>
            </div>

            <div class="bg-white rounded-xl border border-slate-200 p-3.5">
              <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('notifications_pwa.kpi_canaux') }}</div>
              <div class="text-[17px] font-bold mt-1 {{ $nombreCanauxBranches > 0 ? 'text-emerald-600' : 'text-red-600' }}">{{ $nombreCanauxBranches }} / {{ $nombreCanaux }}</div>
              <div class="text-[11px] text-slate-400 mt-0.5">{{ __('notifications_pwa.kpi_canaux_detail') }}</div>
            </div>
          </div>
        </div>

        {{-- ONGLETS — maitre l.72-78, les CINQ, dans son ordre. --}}
        <div class="flex flex-wrap gap-1.5 mb-4">
          <button type="button" wire:click="$set('onglet', 'file')" class="{{ $classeOnglet($onglet === 'file') }}">{{ __('notifications_pwa.onglet_file') }}</button>
          <button type="button" wire:click="$set('onglet', 'modeles')" class="{{ $classeOnglet($onglet === 'modeles') }}">{{ __('notifications_pwa.onglet_modeles') }}</button>
          <button type="button" wire:click="$set('onglet', 'declencheurs')" class="{{ $classeOnglet($onglet === 'declencheurs') }}">{{ __('notifications_pwa.onglet_declencheurs') }}</button>
          <button type="button" wire:click="$set('onglet', 'journal')" class="{{ $classeOnglet($onglet === 'journal') }}">{{ __('notifications_pwa.onglet_journal') }}</button>
          <button type="button" wire:click="$set('onglet', 'canaux')" class="{{ $classeOnglet($onglet === 'canaux') }}">{{ __('notifications_pwa.onglet_canaux') }}</button>
        </div>

        {{-- FILTRES — maitre l.80-94 --}}
        <div class="bg-white rounded-xl border border-slate-200 p-3.5 mb-4">
          <div class="flex flex-wrap gap-2.5 items-center">
            <div class="relative flex-1 min-w-[200px]">
              <svg class="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="8"/><path d="M21 21l-4.35-4.35"/></svg>
              {{-- L'invite du maitre, reprise depuis que la file de messages
                   composés EXISTE (vague F, 01/09/2026) — l'ancien motif
                   « sa file n'existe pas ici » était devenu la phrase périmée
                   de PA-144. --}}
              <input type="search" wire:model.live.debounce.300ms="recherche" placeholder="{{ __('notifications_pwa.recherche') }}"
                class="w-full text-[13px] border border-slate-300 rounded-lg pl-9 pr-3 py-2 focus:border-[var(--gold)] focus:outline-none">
            </div>

            <select wire:model.live="filtreCanal" class="text-[13px] border border-slate-300 rounded-lg px-3 py-2">
              <option value="">{{ __('notifications_pwa.tous_canaux') }}</option>
              @foreach ($canaux as $canal)
                <option value="{{ $canal['code'] }}">{{ $canal['libelle'] }}</option>
              @endforeach
            </select>

            <select wire:model.live="filtrePublic" class="text-[13px] border border-slate-300 rounded-lg px-3 py-2">
              <option value="">{{ __('notifications_pwa.tous_publics') }}</option>
              @foreach ($publics as $public)
                <option value="{{ $public['code'] }}">{{ $public['libelle'] }}</option>
              @endforeach
            </select>

            <select wire:model.live="filtreEtat" class="text-[13px] border border-slate-300 rounded-lg px-3 py-2">
              <option value="">{{ __('notifications_pwa.tous_etats') }}</option>
              <option value="actif">{{ __('notifications_pwa.etat_actif') }}</option>
              <option value="inactif">{{ __('notifications_pwa.etat_inactif') }}</option>
            </select>

            <div class="flex-1"></div>

            @if ($peutEcrire)
              <button type="button" wire:click="ouvrirFormulaireModele"
                      class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 bg-white hover:bg-slate-50">{{ __('notifications_pwa.nouveau_modele') }}</button>
            @endif
          </div>
        </div>

        {{-- =========================================== ONGLET FILE D'ATTENTE
             Reel depuis le 01/09/2026 — maitre l.40-103. Regroupe par
             declencheur, comme le maitre (« c'est ainsi qu'on relit une
             campagne, pas message par message »). --}}
        {{-- LES CINQ PANNEAUX SONT TOUS RENDUS, l'inactif en `hidden`
             (02/09/2026, G5) : toutes les donnees de cet ecran sont deja
             calculees a chaque GET par `render()` — masquer un panneau ne
             coute rien, et les entetes des trois tableaux (declencheurs,
             journal, canaux) existent des le premier GET. --}}
        <div @if ($onglet !== 'file') hidden @endif>
          @forelse ($groupesFile as $groupe)
            <div class="bg-white rounded-xl border border-slate-200 overflow-hidden mb-3">
              <div class="px-4 py-3 border-b border-slate-200 flex flex-wrap items-center justify-between gap-2">
                <div>
                  <h3 class="text-[14px] font-bold" style="color:var(--navy)">{{ $groupe['declencheur']['libelle'] ?? $groupe['code'] }}</h3>
                  <p class="text-[11px] text-slate-400 mt-0.5">{{ $groupe['declencheur']['description'] ?? '' }}</p>
                </div>
                <span class="text-[11px] px-2 py-0.5 rounded bg-slate-100 text-slate-600">
                  {{ __('notifications_pwa.file_module', ['module' => $groupe['declencheur']['module'] ?? '']) }}
                </span>
              </div>

              @foreach ($groupe['messages'] as $message)
                <div class="px-4 py-3 border-b border-slate-100 last:border-0">
                  <div class="flex flex-wrap items-center justify-between gap-2 mb-2">
                    <div class="flex items-center gap-2">
                      <span class="text-[13px] font-semibold text-slate-800">{{ $message->destinataire }}</span>
                      <span class="text-[10px] px-1.5 py-0.5 rounded bg-slate-100 text-slate-500">{{ RegistreCanaux::existe($message->canal) ? RegistreCanaux::canal($message->canal)['libelle'] : $message->canal }}</span>
                      <span class="text-[10px] px-1.5 py-0.5 rounded" style="background:#FEF2F2;color:#7F1D1D">{{ __('notifications_pwa.file_non_envoye') }}</span>
                    </div>
                    @if ($peutEcrire)
                      <div class="flex gap-1.5 shrink-0">
                        {{-- « Envoyer » — REEL depuis le 01/09/2026, e-mail
                             seulement, et seulement si les deux conditions
                             tiennent. La raison EST affichee sinon (PA-59/60/61),
                             jamais un bouton grise (Article 3.3). --}}
                        @if ($message->canal === RegistreCanaux::EMAIL)
                          @if (blank($message->email_destinataire))
                            <span class="text-[11px] px-2 py-1 rounded bg-red-50 text-red-700">{{ __('notifications_pwa.file_sans_adresse') }}</span>
                          @elseif (! $mailConfigure)
                            <span class="text-[11px] px-2 py-1 rounded bg-red-50 text-red-700">{{ __('notifications_pwa.file_sans_configuration') }}</span>
                          @else
                            <button type="button" wire:click="envoyerMessage('{{ $message->id }}')" wire:loading.attr="disabled"
                                    class="text-[11px] px-2 py-1 rounded border border-blue-300 text-blue-700 hover:bg-blue-50">{{ __('notifications_pwa.file_envoyer') }}</button>
                          @endif
                        @else
                          <span class="text-[11px] px-2 py-1 rounded bg-slate-100 text-slate-400">{{ __('notifications_pwa.file_a_parametrer') }}</span>
                        @endif
                        <button type="button" wire:click="ouvrirTransmission('{{ $message->id }}')"
                                class="text-[11px] px-2 py-1 rounded border border-emerald-300 text-emerald-700 hover:bg-emerald-50">{{ __('notifications_pwa.file_transmis_bouton') }}</button>
                        <button type="button" wire:click="ouvrirAbandon('{{ $message->id }}')"
                                class="text-[11px] px-2 py-1 rounded border border-slate-300 hover:bg-slate-50">{{ __('notifications_pwa.file_abandonner_bouton') }}</button>
                      </div>
                    @endif
                  </div>
                  @if ($message->objet)
                    <p class="text-[12px] font-semibold text-slate-600 mb-1">{{ __('notifications_pwa.file_objet', ['objet' => $message->objet]) }}</p>
                  @endif
                  <div class="rounded-xl border px-3 py-2.5 text-[13px] leading-relaxed whitespace-pre-wrap max-w-[520px] {{ $classeBulle($message->canal) }}">{{ $message->contenu }}</div>
                  <p class="text-[10.5px] text-slate-400 mt-1.5">
                    @php($limite = RegistreCanaux::existe($message->canal) ? RegistreCanaux::canal($message->canal)['limite'] : null)
                    {{ __('notifications_pwa.file_meta', [
                        'longueur' => $message->longueur,
                        'limite' => $limite === null ? '' : __('notifications_pwa.file_meta_avec_limite', ['limite' => $limite]),
                        'date' => $message->date_creation?->format('d/m/Y H:i'),
                        'reference' => $message->reference,
                    ]) }}
                  </p>
                </div>
              @endforeach
            </div>
          @empty
            <div class="bg-white rounded-xl border border-slate-200 py-14 text-center text-slate-400 text-[13px]">{{ __('notifications_pwa.file_vide') }}</div>
          @endforelse
        </div>

        {{-- ================================================ ONGLET MODELES --}}
        <div @if ($onglet !== 'modeles') hidden @endif>
          @forelse ($modeles as $modele)
            @php($d = $declencheurDuModele[$modele->id] ?? null)
            <div class="bg-white rounded-xl border border-slate-200 p-4 mb-3">
              <div class="flex flex-wrap items-start justify-between gap-2 mb-2.5">
                <div>
                  <div class="flex items-center gap-2">
                    <h3 class="text-[14px] font-bold" style="color:var(--navy)">{{ $d['libelle'] ?? $modele->evenement }}</h3>
                    <span class="text-[10px] px-1.5 py-0.5 rounded bg-slate-100 text-slate-500">{{ RegistreCanaux::existe($modele->canal) ? RegistreCanaux::canal($modele->canal)['libelle'] : $modele->canal }}</span>
                    @if ($modele->actif)
                      <span class="text-[10px] px-1.5 py-0.5 rounded bg-emerald-50 text-emerald-700">{{ __('notifications_pwa.modele_actif') }}</span>
                    @else
                      <span class="text-[10px] px-1.5 py-0.5 rounded bg-slate-100 text-slate-400">{{ __('notifications_pwa.modele_desactive') }}</span>
                    @endif
                  </div>
                  <p class="text-[11px] text-slate-400 mt-0.5 font-mono">{{ $modele->evenement }}</p>
                </div>

                @if ($peutEcrire)
                  <div class="flex gap-1.5 shrink-0">
                    <button type="button" wire:click="basculerModele('{{ $modele->id }}')"
                            class="text-[11px] px-2.5 py-1 rounded border border-slate-300 hover:bg-slate-50">{{ $modele->actif ? __('notifications_pwa.modele_desactiver') : __('notifications_pwa.modele_activer') }}</button>
                    <button type="button" wire:click="ouvrirFormulaireModele('{{ $modele->id }}')"
                            class="text-[11px] px-2.5 py-1 rounded border border-slate-300 hover:bg-slate-50">{{ __('notifications_pwa.modele_modifier') }}</button>
                  </div>
                @endif
              </div>

              @if ($modele->objet)
                <p class="text-[12px] font-semibold text-slate-600 mb-1">{{ __('notifications_pwa.modele_objet') }} {{ $modele->objet }}</p>
              @endif

              <div class="rounded-xl border px-3 py-2.5 text-[13px] leading-relaxed whitespace-pre-wrap max-w-[520px] {{ $classeBulle($modele->canal) }}">{{ $modele->contenu_template }}</div>

              @if ($d === null)
                <p class="text-[11px] text-red-600 mt-2">{{ __('notifications_pwa.modele_declencheur_inconnu') }}</p>
              @else
                <p class="text-[10.5px] text-slate-400 mt-2">
                  {{ __('notifications_pwa.modele_variables') }}
                  @foreach ($d['variables'] as $variable)
                    <code class="px-1 rounded bg-slate-100">{{ '{' . $variable . '}' }}</code>
                  @endforeach
                </p>
              @endif

              @if (($variablesInconnues[$modele->id] ?? []) !== [])
                <p class="text-[11px] text-red-600 mt-1">{{ __('notifications_pwa.modele_variables_inconnues', ['variables' => implode(', ', array_map(fn ($v) => '{' . $v . '}', $variablesInconnues[$modele->id]))]) }}</p>
              @endif
            </div>
          @empty
            <div class="bg-white rounded-xl border border-slate-200 py-14 text-center">
              <p class="text-[13px] font-semibold text-slate-500">{{ __('notifications_pwa.aucun_resultat') }}</p>
              <p class="text-[13px] text-slate-400 mt-1">{{ __('notifications_pwa.aucun_modele') }}</p>
            </div>
          @endforelse
        </div>

        {{-- =========================================== ONGLET DECLENCHEURS --}}
        <div @if ($onglet !== 'declencheurs') hidden @endif>
          {{-- Deux colonnes du maitre sont OMISES (motifs reverifies le
               02/09/2026) : « Moteur » nomme un objet JavaScript du prototype
               (`ReservationsEngine`), qui n'existe pas cote serveur ;
               « Occurrences aujourd'hui » supposerait une detection CONTINUE,
               alors que `FileAttenteNotificationsService::detecter()` ne
               tourne qu'A LA DEMANDE (le geste de cet ecran, son seul
               appelant) — un compteur du jour afficherait « 0 » quand
               personne n'a clique, pas quand rien n'a eu lieu (PA-59/60/61).
               Ces deux libelles sont declares hors premier GET dans
               `ColonnesDesTableauxPwaTest::COLONNES_HORS_PREMIER_GET_PAR_ECRAN`. --}}
          <div class="bg-white rounded-xl border border-slate-200 overflow-hidden mb-3">
            <div class="px-4 py-3 border-b border-slate-200">
              <h3 class="text-[14px] font-bold" style="color:var(--navy)">{{ __('notifications_pwa.declencheurs_titre', ['nombre' => $nombreDeclencheurs]) }}</h3>
            </div>
            <div class="overflow-x-auto">
              <table class="w-full text-[13px]">
                <thead class="bg-[var(--navy)]"><tr>
                  {!! $entete(__('notifications_pwa.col_declencheur'), true) !!}
                  {!! $entete(__('notifications_pwa.col_public')) !!}
                  {!! $entete(__('notifications_pwa.col_module')) !!}
                  {!! $entete(__('notifications_pwa.col_modeles')) !!}
                  {!! $entete(__('notifications_pwa.col_variables')) !!}
                </tr></thead>
                <tbody>
                  @forelse ($declencheurs as $declencheur)
                    <tr class="border-t border-slate-100 hover:bg-slate-50">
                      <td class="px-3 py-2.5 text-left">
                        <div class="font-semibold text-slate-800">{{ $declencheur['libelle'] }}</div>
                        <div class="text-[11px] text-slate-400">{{ $declencheur['description'] }}</div>
                      </td>
                      <td class="px-3 py-2.5 text-right text-slate-600">{{ $declencheur['public_libelle'] }}</td>
                      <td class="px-3 py-2.5 text-right"><span class="text-[11px] px-1.5 py-0.5 rounded bg-slate-100 text-slate-600">{{ $declencheur['module'] }}</span></td>
                      <td class="px-3 py-2.5 text-right text-slate-600">{{ $declencheur['comptage']['actifs'] }} / {{ $declencheur['comptage']['total'] }}</td>
                      <td class="px-3 py-2.5 text-right text-[11px] text-slate-400">
                        @foreach ($declencheur['variables'] as $variable){{ '{' . $variable . '}' }} @endforeach
                      </td>
                    </tr>
                  @empty
                    <tr><td colspan="5" class="px-3 py-14 text-center text-[13px] font-semibold text-slate-500">{{ __('notifications_pwa.aucun_resultat') }}</td></tr>
                  @endforelse
                </tbody>
              </table>
            </div>
          </div>
        </div>

        {{-- ================================================ ONGLET JOURNAL
             Deux SOURCES, comme au maitre — sa `journal` porte a la fois les
             messages traites manuellement et les envois reellement partis.
             `notifications_envoyees` (colonne « Envoi systeme » = oui) recoit
             desormais les e-mails REELLEMENT acceptes par le transport (voir
             `EnvoiEmailNotificationService`) ; elle reste vide pour les trois
             autres canaux, non brancages. `notifications_composees` (statut
             traite/abandonne) porte le reste, avec l'auteur REEL du geste. --}}
        <div @if ($onglet !== 'journal') hidden @endif>
          <div class="bg-white rounded-xl border border-slate-200 overflow-hidden mb-3">
            <div class="px-4 py-3 border-b border-slate-200 flex flex-wrap items-center justify-between gap-2">
              <h3 class="text-[14px] font-bold" style="color:var(--navy)">{{ __('notifications_pwa.journal_titre', ['nombre' => $journal->count() + $journalTraitement->count()]) }}</h3>
              <span class="text-[11px] text-red-700">{{ __('notifications_pwa.journal_reserve') }}</span>
            </div>
            <div class="overflow-x-auto">
              <table class="w-full text-[13px]">
                <thead class="bg-[var(--navy)]"><tr>
                  {!! $entete(__('notifications_pwa.col_date'), true) !!}
                  {!! $entete(__('notifications_pwa.col_destinataire'), true) !!}
                  {!! $entete(__('notifications_pwa.col_declencheur'), true) !!}
                  {!! $entete(__('notifications_pwa.col_canal')) !!}
                  {!! $entete(__('notifications_pwa.col_statut')) !!}
                  {!! $entete(__('notifications_pwa.col_envoi_systeme')) !!}
                  {!! $entete(__('notifications_pwa.col_par')) !!}
                  {!! $entete(__('notifications_pwa.col_commentaire')) !!}
                </tr></thead>
                <tbody>
                  @foreach ($journalTraitement as $traite)
                    <tr class="border-t border-slate-100">
                      <td class="px-3 py-2.5 text-left text-slate-600 whitespace-nowrap">{{ $traite->date_modification?->format('d/m/Y H:i') }}</td>
                      <td class="px-3 py-2.5 text-left font-semibold text-slate-800">{{ $traite->destinataire }}</td>
                      <td class="px-3 py-2.5 text-left text-slate-600">{{ $traite->modele->evenement ?? '' }}</td>
                      <td class="px-3 py-2.5 text-right text-slate-600">{{ RegistreCanaux::existe($traite->canal) ? RegistreCanaux::canal($traite->canal)['libelle'] : $traite->canal }}</td>
                      <td class="px-3 py-2.5 text-right">
                        @if ($traite->statut === \App\Domain\Notifications\Models\MessageNotificationCompose::STATUT_TRAITE_MANUELLEMENT)
                          <span class="text-[11px] px-2 py-0.5 rounded bg-emerald-50 text-emerald-700">{{ __('notifications_pwa.journal_statut_traite') }}</span>
                        @else
                          <span class="text-[11px] px-2 py-0.5 rounded bg-slate-100 text-slate-500">{{ __('notifications_pwa.journal_statut_abandonne') }}</span>
                        @endif
                      </td>
                      <td class="px-3 py-2.5 text-right"><span class="text-[11px] px-2 py-0.5 rounded" style="background:#FEF2F2;color:#7F1D1D">non</span></td>
                      <td class="px-3 py-2.5 text-right text-[12px] text-slate-500">{{ $traite->traitePar?->login ?? '—' }}</td>
                      <td class="px-3 py-2.5 text-right text-[12px] text-slate-500">{{ $traite->commentaire ?? $traite->motif_abandon ?? '—' }}</td>
                    </tr>
                  @endforeach
                  @forelse ($journal as $envoi)
                    <tr class="border-t border-slate-100">
                      <td class="px-3 py-2.5 text-left text-slate-600 whitespace-nowrap">{{ $envoi->date_envoi->format('d/m/Y H:i') }}</td>
                      <td class="px-3 py-2.5 text-left font-semibold text-slate-800">{{ $envoi->destinataire }}</td>
                      <td class="px-3 py-2.5 text-left text-slate-600">{{ $envoi->modele->evenement ?? '' }}</td>
                      <td class="px-3 py-2.5 text-right text-slate-600">{{ $envoi->modele->canal ?? '' }}</td>
                      <td class="px-3 py-2.5 text-right text-slate-600">{{ $envoi->statut_remise }}</td>
                      <td class="px-3 py-2.5 text-right"><span class="text-[11px] px-2 py-0.5 rounded bg-emerald-50 text-emerald-700">oui</span></td>
                      <td class="px-3 py-2.5 text-right text-[12px] text-slate-500">—</td>
                      <td class="px-3 py-2.5 text-right text-[12px] text-slate-500">—</td>
                    </tr>
                  @empty
                    @if ($journalTraitement->isEmpty())
                      <tr><td colspan="8" class="px-3 py-14 text-center">
                        <p class="text-[13px] font-semibold text-slate-500">{{ __('notifications_pwa.aucun_resultat') }}</p>
                        <p class="text-[13px] text-slate-400 mt-1 max-w-[560px] mx-auto">{{ __('notifications_pwa.journal_vide') }}</p>
                      </td></tr>
                    @endif
                  @endforelse
                </tbody>
              </table>
            </div>
          </div>
        </div>

        {{-- ================================================= ONGLET CANAUX --}}
        <div @if ($onglet !== 'canaux') hidden @endif>
          {{-- La colonne « En file » du maitre est RENDUE depuis le
               02/09/2026 : elle compte les messages composés en attente par
               canal, mesurés sur la file réelle (`enFileParCanal`). L'ancien
               motif d'omission — « rien n'en compose » — était devenu faux
               depuis que la file existe (vague F) : le laisser aurait été la
               phrase périmée que PA-144 traque. --}}
          <div class="bg-white rounded-xl border border-slate-200 overflow-hidden mb-3">
            <div class="px-4 py-3 border-b border-slate-200">
              <h3 class="text-[14px] font-bold" style="color:var(--navy)">{{ __('notifications_pwa.canaux_titre') }}</h3>
            </div>
            <div class="overflow-x-auto">
              <table class="w-full text-[13px]">
                <thead class="bg-[var(--navy)]"><tr>
                  {!! $entete(__('notifications_pwa.col_canal'), true) !!}
                  {!! $entete(__('notifications_pwa.col_etat')) !!}
                  {!! $entete(__('notifications_pwa.col_blocage'), true) !!}
                  {!! $entete(__('notifications_pwa.col_limite')) !!}
                  {!! $entete(__('notifications_pwa.col_cible')) !!}
                  {!! $entete(__('notifications_pwa.col_enfile')) !!}
                </tr></thead>
                <tbody>
                  @foreach ($canaux as $canal)
                    <tr class="border-t border-slate-100">
                      <td class="px-3 py-3 text-left font-semibold text-slate-800">{{ $canal['libelle'] }}</td>
                      <td class="px-3 py-3 text-right">
                        @if ($canal['branche'])
                          <span class="text-[11px] px-2 py-0.5 rounded bg-emerald-50 text-emerald-700">{{ __('notifications_pwa.canal_branche') }}</span>
                        @else
                          <span class="text-[11px] px-2 py-0.5 rounded bg-red-50 text-red-700">{{ __('notifications_pwa.canal_non_branche') }}</span>
                        @endif
                      </td>
                      <td class="px-3 py-3 text-left text-[12px] text-slate-600">{{ $canal['blocage'] }}</td>
                      <td class="px-3 py-3 text-right text-slate-600">{{ $canal['limite'] === null ? '—' : __('notifications_pwa.canal_caracteres', ['limite' => $canal['limite']]) }}</td>
                      <td class="px-3 py-3 text-right text-slate-500 text-[12px]">{{ $canal['cible'] }}</td>
                      {{-- Le décompte réel des messages en attente sur ce
                           canal — zéro s'écrit « 0 » : c'est une mesure de la
                           file, pas un état affirmé sans vérification. --}}
                      <td class="px-3 py-3 text-right {{ ($enFileParCanal[$canal['code']] ?? 0) > 0 ? 'font-semibold' : 'text-slate-400' }}">{{ $enFileParCanal[$canal['code']] ?? 0 }}</td>
                    </tr>
                  @endforeach
                </tbody>
              </table>
            </div>
          </div>
        </div>

      </div>
    </main>
  </div>

  {{-- ============================================== MODALE — EDITEUR DE MODELE
       ⚠ L'« Apercu avec une occurrence reelle » du maitre n'est PAS rendu : il
       substitue les variables par les valeurs d'une occurrence detectee du
       jour, et aucune detection n'a lieu cote serveur. Un apercu a variables
       fictives laisserait passer une formulation qui ne tient pas avec un vrai
       nom ou un vrai montant — c'est le maitre lui-meme qui l'ecrit. Le rendre
       vide, ou avec des valeurs inventees, serait le faux ecran que ce lot
       refuse. --}}
  {{-- Le bouton « Annuler » du maître (modale-modele) EST rendu ci-dessous,
       par la clé partagée `pwa.modale.annuler` — nommé ici pour le
       comparateur trois-sources, qui ne lit pas les clés d'un autre
       domaine. --}}
  @if ($etatFormulaire === 'modele')
    <x-pwa.modale :titre="$modeleId === null ? __('notifications_pwa.modale_nouveau') : __('notifications_pwa.modale_modifier')" largeur="620px">
      <div class="grid grid-cols-2 gap-3">
        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('notifications_pwa.champ_declencheur') }} <span class="text-red-500">*</span></label>
          {{-- Verrouille a l'edition, comme au maitre : changer l'evenement
               d'un modele reviendrait a en creer un autre en perdant la trace
               du premier. --}}
          <select wire:model.live="declencheurSaisi" @if ($modeleId !== null) disabled @endif
                  class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5 {{ $modeleId !== null ? 'bg-slate-100' : '' }}">
            @foreach ($declencheurs as $declencheur)
              <option value="{{ $declencheur['code'] }}">{{ $declencheur['libelle'] }}</option>
            @endforeach
          </select>
        </div>
        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('notifications_pwa.champ_canal') }} <span class="text-red-500">*</span></label>
          <select wire:model.live="canalSaisi" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
            @foreach ($canaux as $canal)
              <option value="{{ $canal['code'] }}">{{ $canal['libelle'] }}</option>
            @endforeach
          </select>
        </div>
      </div>

      <div>
        <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('notifications_pwa.champ_objet') }} <span class="text-slate-400 font-normal">{{ __('notifications_pwa.champ_objet_aide') }}</span></label>
        <input type="text" wire:model="objetSaisi" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
        @error('objetSaisi') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
      </div>

      <div>
        <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('notifications_pwa.champ_message') }} <span class="text-red-500">*</span></label>
        <textarea wire:model="contenuSaisi" rows="5" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5 font-mono"></textarea>
        @error('contenuSaisi') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        <div class="text-[11px] text-slate-500 mt-1.5">
          {{ __('notifications_pwa.champ_variables') }}
          @foreach (($declencheurDuFormulaire['variables'] ?? []) as $variable)
            <code class="px-1 rounded bg-slate-100">{{ '{' . $variable . '}' }}</code>
          @endforeach
        </div>
      </div>

      <label class="flex items-center gap-2 text-[13px] text-slate-700 cursor-pointer">
        <input type="checkbox" wire:model="actifSaisi" class="rounded border-slate-400">
        {{ __('notifications_pwa.champ_actif') }}
      </label>

      <x-slot:pied>
        <button type="button" wire:click="fermerModales"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="enregistrerModele"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('notifications_pwa.enregistrer') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  {{-- ======================================================= MODALE — EXPORT --}}
  @if ($etatFormulaire === 'export')
    @include('pwa.partials.modale-export', ['titre' => $titreExport])
  @endif

  {{-- ================================== MODALE — TRANSMISSION MANUELLE
       Maitre : `notifications-engine.js` l.430-444 (`Dialogue.saisir`). --}}
  @if ($etatFormulaire === 'transmission')
    <x-pwa.modale :titre="__('notifications_pwa.transmission_titre')" :sousTitre="__('notifications_pwa.transmission_texte')" largeur="480px">
      <div>
        <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('notifications_pwa.transmission_champ') }}</label>
        <textarea wire:model="commentaireTransmission" rows="3" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5"></textarea>
        @error('commentaireTransmission') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        @error('messageId') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
      </div>

      <x-slot:pied>
        <button type="button" wire:click="fermerModales"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="enregistrerTransmission"
                class="text-[13px] px-4 py-2 rounded-lg text-white font-semibold" style="background:var(--succes)">{{ __('notifications_pwa.transmission_confirmer') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  {{-- ============================================ MODALE — ABANDON
       Maitre : `notifications-engine.js` l.446-459. --}}
  @if ($etatFormulaire === 'abandon')
    <x-pwa.modale :titre="__('notifications_pwa.abandon_titre')" :sousTitre="__('notifications_pwa.abandon_texte')" largeur="480px">
      <div>
        <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('notifications_pwa.abandon_champ') }} <span class="text-red-500">*</span></label>
        <textarea wire:model="motifAbandon" rows="3" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5"></textarea>
        @error('motifAbandon') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        @error('messageId') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
      </div>

      <x-slot:pied>
        <button type="button" wire:click="fermerModales"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="enregistrerAbandon"
                class="text-[13px] px-4 py-2 rounded-lg text-white font-semibold" style="background:var(--erreur)">{{ __('notifications_pwa.abandon_confirmer') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

</div>
