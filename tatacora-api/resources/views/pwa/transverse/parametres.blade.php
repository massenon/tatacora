{{--
    PARAMÈTRES — maître : `prototype_v2/pages/parametres.html`.
    Composant : `app/Pwa/Livewire/Transverse/Parametres.php`.

    ## LES SEPT ONGLETS SONT RÉELS DEPUIS LE 02/09/2026 (directive PO)

    Chaque onglet rend les champs du maître, à sa place dans SA grille
    (`grid grid-cols-1 sm:grid-cols-2 gap-4`), avec ses sections et ses
    aides. Un champ du registre s'affiche en LECTURE (bloc `groupe-champ` du
    maître, valeur au lieu du champ de saisie — `_parametre_ligne`), et
    « Modifier » ouvre la modale gardée : `RefuseLaSaisie` (Article 6) impose
    qu'aucun formulaire ne se rende au premier GET — la route n'exige que
    `PARAM = L`, un champ posé ici serait servi AVANT toute garde. C'est un
    écart de MÉCANISME assumé (brief du 01/09/2026), pas de visuel.

    ## LES LIBELLÉS DES CHAMPS VIENNENT DU SERVEUR — DÉCLARATION

    libelles-du-serveur:parametres.html

    Les étiquettes des champs ne sont écrites nulle part dans la PWA : elles
    sont celles de `RegistreParametres` (`app/Shared/Parametres/Data/`),
    source unique partagée avec l'API. « Raison sociale », « Nom du
    promoteur », « IFU (Identifiant Fiscal Unique) », « Régime fiscal »,
    « Serveur SMTP », « Numéro WhatsApp Business », les titres des bascules
    d'activation… sont donc rendus, mais par le registre. Sans cette
    déclaration, la garde des trois sources exigerait que la vue les RECOPIE —
    deux listes qui divergeraient au premier renommage (Article 10).

    ## CE QUI RESTE REFUSÉ, ET POURQUOI (motifs datés du 02/09/2026)

    maitre-refuse:parametres.html#communication — l'invite « •••••••••••••••• »
      de la « Clé API WhatsApp Business » : un secret n'entre JAMAIS dans
      `parametres_systeme`, lisible par tout profil ayant l'écran — il vit en
      `.env`. Le champ du maître est rendu en ligne, avec sa mention réelle.
    (Levé le 19/10/2026 : le champ « Mot de passe SMTP » de l'onglet
      #email est SAISI — décision du Product Owner, « chiffré en base » :
      `secrets_configuration`, jamais `parametres_systeme` ; le bouton
      « Envoyer un email de test » est RÉEL depuis le 02/09/2026.)
    maitre-refuse:parametres.html#activation — le pied de formulaire unique du
      maître (« Annuler » / « Enregistrer les paramètres ») : cet écran
      enregistre une clé à la fois, par modale (`enregistrerParametre()`) —
      un enregistrement groupé écraserait en silence le changement d'un autre
      Administrateur, et un pied rendu sans formulaire serait un bouton
      inerte (Article 3.3). Les bascules, elles, s'appliquent AU CLIC, comme
      le maître le documente. Trois bascules du maître ne sont pas rendues,
      leurs motifs datés au bloc « Activation » ci-dessous.
    maitre-refuse:parametres.html#identite — les invites d'exemple
      (« Ex. 3202612345678 », « Ex. RB/NAT/23 B 0456 ») : l'écran affiche des
      valeurs, pas des champs de saisie — rien où poser une invite.
--}}
@php
    use App\Pwa\Livewire\Transverse\Parametres;
    use App\Shared\Parametres\Data\RegistreParametres;
    use App\Shared\ReportEngine\Services\ReportHeaderService;

    // Classes d'onglets : directive PO du 01/09/2026, UN SEUL AUTEUR —
    // voir le docblock de `App\Pwa\Support\Onglets`.
    $classeOnglet = static fn (bool $actif): string => \App\Pwa\Support\Onglets::classes($actif);

    // Les pastilles de risque du maître (`parametres.html`, const RISQUES).
    $risques = [
        'faible' => ['libelle' => __('pwa.parametres.risque_faible'), 'fond' => '#E8F5E9', 'texte' => '#1B5E20'],
        'moyen' => ['libelle' => __('pwa.parametres.risque_modere'), 'fond' => '#FFFBEB', 'texte' => '#7C5E12'],
        'eleve' => ['libelle' => __('pwa.parametres.risque_eleve'), 'fond' => '#FDECEC', 'texte' => '#8C1D1D'],
    ];

    // Les clés que le maître loge sous « Informations légales & fiscales »
    // (seconde section de l'onglet Identité) — le reste du groupe
    // `entreprise` vit sous « Identité de l'entreprise ».
    $clesLegales = [ReportHeaderService::CLE_IFU, ReportHeaderService::CLE_RCCM, RegistreParametres::CLE_NUMERO_MECEF];

    $ligneDe = static function (array $lignes, string $cle): ?array {
        foreach ($lignes as $ligne) {
            if ($ligne['definition']->cle === $cle) {
                return $ligne;
            }
        }

        return null;
    };
@endphp

<div class="contents">

  @include('pwa.partials.barre-superieure')

  <div class="flex flex-1 overflow-hidden">
    @include('pwa.partials.menu-lateral')

    <main class="flex-1 overflow-y-auto">
      {{-- maquette l.18 — 1100 px, la largeur du maître. --}}
      <div class="max-w-[1440px] mx-auto p-5 lg:p-8">

        {{-- maquette l.20-26 — l'engrenage et le titre sur une même ligne. --}}
        <div class="mb-6">
          <div class="flex items-center gap-2.5">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--navy)" stroke-width="2"><circle cx="12" cy="12" r="3"/><path stroke-linecap="round" stroke-linejoin="round" d="M19.4 15a1.65 1.65 0 00.33 1.82l.06.06a2 2 0 11-2.83 2.83l-.06-.06a1.65 1.65 0 00-1.82-.33 1.65 1.65 0 00-1 1.51V21a2 2 0 01-4 0v-.09A1.65 1.65 0 009 19.4a1.65 1.65 0 00-1.82.33l-.06.06a2 2 0 11-2.83-2.83l.06-.06A1.65 1.65 0 004.6 15a1.65 1.65 0 00-1.51-1H3a2 2 0 010-4h.09A1.65 1.65 0 004.6 9a1.65 1.65 0 00-.33-1.82l-.06-.06a2 2 0 112.83-2.83l.06.06A1.65 1.65 0 009 4.6a1.65 1.65 0 001-1.51V3a2 2 0 014 0v.09a1.65 1.65 0 001 1.51 1.65 1.65 0 001.82-.33l.06-.06a2 2 0 112.83 2.83l-.06.06A1.65 1.65 0 0019.4 9c.14.31.22.65.22 1V10c.66 0 1 .34 1 1v2c0 .66-.34 1-1 1z"/></svg>
            <h1 class="text-lg lg:text-xl font-bold" style="color:var(--navy)">{{ __('pwa.parametres.titre') }}</h1>
          </div>
          <p class="text-[15px] text-slate-500 mt-1.5">{{ __('pwa.parametres.sous_titre') }}</p>
        </div>

        @if (session('pwa-succes'))
          <div class="rounded-xl px-4 py-3 mb-4 text-[13px] font-semibold"
               style="background:#E8F5E9;border:1px solid #A5D6A7;color:#1B5E20">{{ session('pwa-succes') }}</div>
        @endif

        {{-- Le REFUS d'un geste immédiat (désactiver une table au panier
             ouvert, rétablir le jeu pendant un service) : aucun formulaire
             n'est ouvert à ce moment, le bandeau porte le message — le
             pendant rouge du bandeau de succès. --}}
        @if (session('pwa-erreur'))
          <div class="rounded-xl px-4 py-3 mb-4 text-[13px] font-semibold"
               style="background:#FDECEC;border:1px solid #F5C6C6;color:#8C1D1D">{{ session('pwa-erreur') }}</div>
        @endif

        {{-- LES SEPT ONGLETS DU MAÎTRE, DANS SON ORDRE (l.29-37).
             Des liens, jamais des boutons de formulaire : changer d'onglet est
             une navigation, et un `<form>` ici ferait rougir `RefuseLaSaisie`. --}}
        <div class="flex flex-wrap gap-2 mb-5">
          @foreach (Parametres::ONGLETS as $cle => $libelle)
            <a href="{{ route('pwa.parametres', ['onglet' => $cle]) }}" wire:navigate class="{{ $classeOnglet($onglet === $cle) }}">{{ $libelle }}</a>
          @endforeach
        </div>

        {{-- LES ÉTATS DÉRIVÉS — jamais les commutateurs bruts (PA-61). Bloc
             PROPRE à la PWA, assumé : le maître n'a aucun endroit qui dise
             l'état RÉEL de la TVA et de MECeF, et c'est ce silence qui a
             produit PA-61/PA-62.
             structure-ajout:parametres.html#h2-8e3c2531
             structure-ajout:parametres.html#div-078d40f6 --}}
        <div class="bg-white rounded-xl border border-slate-200 p-5 mb-5">
          <h2 class="text-sm font-bold text-slate-700 mb-3">{{ __('pwa.parametres.etats_titre') }}</h2>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
            <div class="rounded-lg border border-slate-200 p-3">
              <p class="text-[11px] uppercase tracking-wide text-slate-400">{{ __('pwa.parametres.etat_tva') }}</p>
              <p class="text-[13px] text-slate-700 mt-1">{{ __('parametres.etats.tva.' . $etatTva) }}</p>
            </div>
            <div class="rounded-lg border border-slate-200 p-3">
              <p class="text-[11px] uppercase tracking-wide text-slate-400">{{ __('pwa.parametres.etat_mecef') }}</p>
              <p class="text-[13px] text-slate-700 mt-1">{{ __('parametres.etats.mecef.' . $etatMecef) }}</p>
            </div>
          </div>
        </div>

        {{-- Le conteneur du formulaire du maître (l.39) — même carte blanche,
             en `div` : `<form>` est interdit au premier GET (`RefuseLaSaisie`),
             chaque écriture passe par sa modale gardée.
             structure-refuse:parametres.html#formulaire-parametres

             Conséquence mesurée par `t-structure.js` : le `form` étant déclaré
             omis, la grille du panneau (les classes EXACTES du maître, l.42)
             n'a plus de parent à qui s'apparier — elle est déclarée en ajout,
             pas simulée : structure-ajout:parametres.html#div-c002a0e6 --}}
        <div class="bg-white rounded-xl border border-slate-200 p-6">

        @if ($onglet === 'identite')
            {{-- maquette l.42-66 — la grille à deux colonnes du maître. --}}
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div class="sm:col-span-2"><h3 class="text-sm font-bold text-slate-700 mb-1">{{ __('pwa.parametres.section_identite') }}</h3></div>
              @foreach (($groupesOnglet['entreprise'] ?? []) as $ligne)
                @if (! in_array($ligne['definition']->cle, $clesLegales, true))
                  @include('pwa.transverse._parametre_ligne', [
                      'ligne' => $ligne,
                      'colspan' => $ligne['definition']->cle === ReportHeaderService::CLE_ADRESSE,
                  ])
                @endif
              @endforeach

              <div class="sm:col-span-2 pt-3 mt-1 border-t border-slate-100"><h3 class="text-sm font-bold text-slate-700 mb-1">{{ __('pwa.parametres.section_legal') }}</h3></div>
              @foreach (($groupesOnglet['entreprise'] ?? []) as $ligne)
                @if (in_array($ligne['definition']->cle, $clesLegales, true))
                  @include('pwa.transverse._parametre_ligne', ['ligne' => $ligne, 'colspan' => false])
                @endif
              @endforeach
              {{-- Le groupe `fiscalite` du registre prolonge la section : le
                   « Régime fiscal » du maître, puis les trois clés TVA que le
                   serveur porte en plus (aucun groupe réel ne disparaît —
                   décision n° 2 de DIRECTIVE_CONFORMITE_100.md). --}}
              @foreach (($groupesOnglet['fiscalite'] ?? []) as $ligne)
                @include('pwa.transverse._parametre_ligne', ['ligne' => $ligne, 'colspan' => false])
              @endforeach
            </div>

        @elseif ($onglet === 'communication')
            {{-- maquette l.69-79. --}}
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div class="sm:col-span-2"><h3 class="text-sm font-bold text-slate-700 mb-1">{{ __('pwa.parametres.section_communication') }}</h3></div>

              @php($whatsapp = $ligneDe($groupesOnglet['entreprise'] ?? [], ReportHeaderService::CLE_WHATSAPP))
              @if ($whatsapp !== null)
                @include('pwa.transverse._parametre_ligne', ['ligne' => $whatsapp, 'colspan' => false])
              @endif

              @php($siteWeb = $ligneDe($groupesOnglet['entreprise'] ?? [], ReportHeaderService::CLE_SITE_WEB))
              @if ($siteWeb !== null)
                @include('pwa.transverse._parametre_ligne', ['ligne' => $siteWeb, 'colspan' => true])
              @endif
            </div>

        @elseif ($onglet === 'email')
            {{-- maquette l.82-99. --}}
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div class="sm:col-span-2"><h3 class="text-sm font-bold text-slate-700 mb-1">{{ __('pwa.parametres.section_email') }}</h3></div>

              @foreach (($groupesOnglet['email'] ?? []) as $ligne)
                @include('pwa.transverse._parametre_ligne', [
                    'ligne' => $ligne,
                    'colspan' => $ligne['definition']->cle === \App\Shared\Mail\Services\ConfigurationMailService::CLE_SMTP_HOTE,
                ])
              @endforeach

              {{-- « Mot de passe SMTP » (maquette l.92-93) — SAISI depuis le
                   19/10/2026 (décision du Product Owner, « chiffré en base ») :
                   champ en écriture seule, rangé chiffré dans
                   `secrets_configuration`, jamais réaffiché ; l'écran ne
                   montre que son ÉTAT. Saisie réservée aux Administrateurs. --}}
              <div class="groupe-champ">
                <label for="mot-de-passe-smtp" class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('pwa.parametres.email_motdepasse_libelle') }}</label>
                @if ($peutSaisirSecret)
                  <div class="flex flex-wrap items-center gap-2">
                    <input id="mot-de-passe-smtp" type="password" autocomplete="new-password" wire:model="motDePasseSmtp"
                           placeholder="{{ __('pwa.parametres.email_motdepasse_invite') }}"
                           class="champ flex-1 min-w-0 border border-slate-200 rounded-lg px-3 py-2.5 text-sm">
                    <button type="button" wire:click="enregistrerMotDePasseSmtp" wire:loading.attr="disabled"
                            class="btn px-3 py-2.5 rounded-lg bg-[var(--navy)] text-white text-[13px] font-semibold">{{ __('pwa.parametres.email_motdepasse_enregistrer') }}</button>
                    @if ($etatMotDePasseSmtp['renseigne'])
                      <button type="button" wire:click="effacerMotDePasseSmtp" wire:loading.attr="disabled"
                              class="btn px-3 py-2.5 rounded-lg border border-slate-200 text-[13px] font-semibold text-slate-600">{{ __('pwa.parametres.email_motdepasse_effacer') }}</button>
                    @endif
                  </div>
                  @error('motDePasseSmtp') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
                @endif
                <p class="text-[13px] text-slate-600 mt-1.5">
                  @if ($etatMotDePasseSmtp['renseigne'])
                    {{ __('pwa.parametres.email_motdepasse_renseigne', ['date' => $etatMotDePasseSmtp['modifie_le']?->format('d/m/Y H:i') ?? '—', 'par' => $etatMotDePasseSmtp['par'] ?? '—']) }}
                  @else
                    {{ __('pwa.parametres.email_motdepasse_absent') }}
                  @endif
                </p>
                @unless ($peutSaisirSecret)
                  <p class="text-[12px] text-slate-400 mt-1">{{ __('pwa.parametres.email_motdepasse_reserve') }}</p>
                @endunless
                <p class="text-[12px] text-slate-400 mt-1.5">{{ __('pwa.parametres.email_motdepasse_mention') }}</p>
              </div>

              {{-- maquette l.94-99 — le bouton d'envoi de test, RÉEL depuis le
                   02/09/2026 : il envoie par la configuration effective
                   (paramètres SMTP superposés au .env) et rapporte ce que le
                   transport a répondu — jamais un succès simulé (PA-59/60/61). --}}
              <div class="sm:col-span-2">
                @if ($peutEcrire)
                  <button type="button" wire:click="envoyerEmailTest" wire:loading.attr="disabled"
                          class="btn px-4 py-2.5 rounded-lg border border-slate-200 text-[15px] font-semibold text-slate-600 flex items-center gap-2">
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M22 2L11 13M22 2l-7 20-4-9-9-4 20-7z"/></svg>
                    {{ __('pwa.parametres.email_test_bouton') }}
                  </button>
                @endif

                @if ($resultatTestEmail !== null)
                  <p class="text-[13px] mt-2 font-semibold" style="color:{{ $resultatTestEmail['succes'] ? '#1B5E20' : '#8C1D1D' }}">
                    {{ $resultatTestEmail['detail'] }}
                  </p>
                @endif
              </div>
            </div>

        @elseif ($onglet === 'apparence')
            {{-- maquette l.103-131. --}}
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-6">
              <div>
                <p class="block text-[15px] font-semibold text-slate-700 mb-2">{{ __('pwa.parametres.apparence_logo_titre') }}</p>
                <div class="flex items-center gap-4">
                  {{-- Apercus : `object-contain` depuis le logo PNG paysage livre
                       (decision du PO du 14/10/2026, D392) — `object-cover` le
                       rognait, ici comme dans la barre. PA-210. --}}
                  <img src="{{ $urlLogo }}" class="w-20 h-20 rounded-xl object-contain ring-2 ring-slate-100" alt="{{ __('pwa.parametres.apparence_logo_alt') }}">
                  <div>
                    @if ($peutEcrire)
                      <button type="button" wire:click="ouvrirChangementLogo"
                              class="btn px-3.5 py-2 rounded-lg border border-slate-200 text-[15px] font-semibold">{{ __('pwa.parametres.apparence_logo_bouton') }}</button>
                    @endif
                    <p class="text-[13px] text-slate-400 mt-1.5">{{ __('pwa.parametres.apparence_logo_aide') }}</p>
                  </div>
                </div>
              </div>
              <div>
                <p class="block text-[15px] font-semibold text-slate-700 mb-2">{{ __('pwa.parametres.apparence_favicon_titre') }}</p>
                <div class="flex items-center gap-4">
                  <img src="{{ $urlFavicon }}" class="w-10 h-10 rounded-lg object-contain ring-2 ring-slate-100" alt="{{ __('pwa.parametres.apparence_favicon_alt') }}">
                  @if ($peutEcrire)
                    <button type="button" wire:click="ouvrirChangementFavicon"
                            class="btn px-3.5 py-2 rounded-lg border border-slate-200 text-[15px] font-semibold">{{ __('pwa.parametres.apparence_favicon_bouton') }}</button>
                  @endif
                </div>
              </div>
              {{-- maquette l.121-130 — la charte, DÉJÀ en lecture seule au
                   maître, couleurs en dur comme chez lui (chap. 9.3.1). --}}
              <div class="sm:col-span-2 pt-2">
                <p class="block text-[15px] font-semibold text-slate-700 mb-2">{{ __('pwa.parametres.charte_titre') }}</p>
                <div class="flex flex-wrap gap-3">
                  <div class="text-center"><div class="w-12 h-12 rounded-lg mb-1" style="background:#14213D"></div><span class="text-[12px] text-slate-500 font-mono-tatacora">{{ __('pwa.parametres.charte_navy') }}</span></div>
                  <div class="text-center"><div class="w-12 h-12 rounded-lg mb-1" style="background:#B8891E"></div><span class="text-[12px] text-slate-500 font-mono-tatacora">{{ __('pwa.parametres.charte_gold') }}</span></div>
                  <div class="text-center"><div class="w-12 h-12 rounded-lg mb-1" style="background:#2E7D32"></div><span class="text-[12px] text-slate-500 font-mono-tatacora">{{ __('pwa.parametres.charte_succes') }}</span></div>
                  <div class="text-center"><div class="w-12 h-12 rounded-lg mb-1" style="background:#ED6C02"></div><span class="text-[12px] text-slate-500 font-mono-tatacora">{{ __('pwa.parametres.charte_alerte') }}</span></div>
                  <div class="text-center"><div class="w-12 h-12 rounded-lg mb-1" style="background:#C62828"></div><span class="text-[12px] text-slate-500 font-mono-tatacora">{{ __('pwa.parametres.charte_erreur') }}</span></div>
                </div>
              </div>
            </div>

        @elseif ($onglet === 'canaux')
            {{-- maquette l.134-153 : la mention du maître à gauche (les mots
                 exacts, strong compris), le bouton d'ajout à droite — rendu
                 seulement si le rôle écrit.
                 EXCLU de la barre de recherche par table (PO, 01/09/2026) :
                 le référentiel compte quelques lignes — rien à filtrer. --}}
            <div class="flex items-start justify-between gap-4 mb-4">
              <p class="text-[13px] text-slate-500 max-w-2xl">
                {{ __('pwa.parametres.canaux_intro_a') }}
                <strong>{{ __('pwa.parametres.canaux_intro_fort') }}</strong> {{ __('pwa.parametres.canaux_intro_b') }}
              </p>
              @if ($peutEcrire)
                <button type="button" wire:click="ouvrirAjoutCanal"
                        class="btn shrink-0 px-4 py-2.5 rounded-lg bg-[var(--navy)] text-white text-sm font-semibold">{{ __('pwa.parametres.canaux_bouton_ajouter') }}</button>
              @endif
            </div>
            @include('pwa.transverse.partials.tableau-canaux')

        @elseif ($onglet === 'tables')
            {{-- maquette l.156-172 — la mention du maître, les deux boutons,
                 puis la salle telle que `rendreTables()` la fabrique. --}}
            <div class="flex items-start justify-between gap-4 mb-4">
              <p class="text-[13px] text-slate-500 max-w-2xl">
                {{ __('pwa.parametres.tables_intro_a') }}
                <strong>{{ __('pwa.parametres.tables_intro_fort_numeros') }}</strong>{{ __('pwa.parametres.tables_intro_b') }}
                <strong>{{ __('pwa.parametres.tables_intro_fort_comptoir') }}</strong>{{ __('pwa.parametres.tables_intro_c') }}
                <br>
                <strong>{{ __('pwa.parametres.tables_intro_fort_panier') }}</strong>{{ __('pwa.parametres.tables_intro_d') }}
              </p>
              @if ($peutEcrire)
                <div class="flex flex-col gap-2 shrink-0">
                  <button type="button" wire:click="ouvrirAjoutTable"
                          class="btn px-4 py-2.5 rounded-lg bg-[var(--navy)] text-white text-sm font-semibold">{{ __('pwa.parametres.tables_bouton_ajouter') }}</button>
                  <button type="button" wire:click="ouvrirRetablirTables"
                          class="btn px-4 py-2 rounded-lg border border-slate-200 bg-white text-[13px] font-semibold text-slate-600">{{ __('pwa.parametres.tables_bouton_reinit') }}</button>
                </div>
              @endif
            </div>

            {{-- Le markup que `rendreTables()` génère (maquette l.241-280) —
                 chaque espace, TOUTES ses tables (désactivées comprises : une
                 table absente laisserait croire qu'elle n'existe pas), et le
                 Comptoir affiché quand même, avec la raison de son vide. --}}
            <div class="space-y-4">
              @foreach ($espacesTables as $espace)
                @if (! $espace['avecTables'])
                  <div class="border border-slate-200 rounded-lg p-3.5 bg-slate-50">
                    <p class="text-[13px] font-bold text-slate-700">{{ $espace['libelle'] }}</p>
                    <p class="text-[12px] text-slate-500 mt-1">{{ __('pwa.parametres.tables_comptoir_sans_table') }}</p>
                  </div>
                @else
                  <div>
                    <p class="text-[13px] font-bold mb-2" style="color:var(--navy)">{{ $espace['libelle'] }}
                      <span class="text-[11px] font-normal text-slate-400">{{ __('pwa.parametres.tables_prefixe', ['prefixe' => $espace['prefixe']]) }}</span></p>
                    <div class="space-y-1.5">
                      @forelse ($espace['tables'] as $entree)
                        <div class="flex items-center gap-2 border border-slate-200 rounded-lg px-3 py-2">
                          <span class="font-bold text-[14px]" style="color:var(--navy)">{{ $entree['table']->libelle }}</span>
                          <span class="text-[12px] text-slate-400">{{ __('pwa.parametres.tables_places', ['places' => $entree['table']->places]) }}</span>
                          @if ($entree['occupee'])
                            <span class="text-[11px] font-semibold px-2 py-0.5 rounded bg-amber-50 text-amber-700">{{ __('pwa.parametres.tables_badge_panier_ouvert') }}</span>
                          @elseif ($entree['table']->actif)
                            <span class="text-[11px] font-semibold px-2 py-0.5 rounded bg-emerald-50 text-emerald-700">{{ __('pwa.parametres.tables_badge_libre') }}</span>
                          @else
                            <span class="text-[11px] font-semibold px-2 py-0.5 rounded bg-slate-100 text-slate-600">{{ __('pwa.parametres.tables_badge_desactivee') }}</span>
                          @endif
                          <span class="flex-1"></span>
                          @if ($peutEcrire)
                            <button type="button" wire:click="ouvrirRenumerotationTable('{{ $entree['table']->id }}')"
                                    class="text-[12px] font-semibold" style="color:var(--navy)">{{ __('pwa.parametres.tables_bouton_renumeroter') }}</button>
                            <button type="button" wire:click="basculerTable('{{ $entree['table']->id }}')"
                                    class="text-[12px] font-semibold" style="color:var(--gold)">{{ $entree['table']->actif ? __('pwa.parametres.canaux_bouton_desactiver') : __('pwa.parametres.canaux_bouton_reactiver') }}</button>
                          @endif
                        </div>
                      @empty
                        <p class="text-[12px] text-slate-400">{{ __('pwa.parametres.tables_espace_vide') }}</p>
                      @endforelse
                    </div>
                  </div>
                @endif
              @endforeach
            </div>

        @elseif ($onglet === 'activation')
            {{-- maquette l.174-202. --}}
            <div class="mb-4">
              <h3 class="text-sm font-bold text-slate-700 mb-1">{{ __('pwa.parametres.section_activation_actions') }}</h3>
              <p class="text-[15px] text-slate-500">
                {{ __('pwa.parametres.activation_intro_a') }}
                <strong>{{ __('pwa.parametres.activation_intro_fort_profils') }}</strong>{{ __('pwa.parametres.activation_intro_b') }}
                <strong>{{ __('pwa.parametres.activation_intro_fort_modules') }}</strong>{{ __('pwa.parametres.activation_intro_c') }}
              </p>
            </div>

            <div class="rounded-lg px-3.5 py-3 mb-4 flex items-start gap-2.5" style="background:#E8EEFD">
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="var(--info)" stroke-width="2.2" class="shrink-0 mt-0.5"><circle cx="12" cy="12" r="10"/><path stroke-linecap="round" d="M12 16v-4M12 8h.01"/></svg>
              <p class="text-[13px]" style="color:#1E3A8A">
                {{ __('pwa.parametres.activation_info_a') }}
                <strong>{{ __('pwa.parametres.activation_info_fort') }}</strong>{{ __('pwa.parametres.activation_info_b') }}
              </p>
            </div>

            {{-- Le markup de `rendreBascules()` (maquette l.467-505) —
                 appliquées AU CLIC, jamais au bouton Enregistrer : « un
                 réglage de sécurité laissé en attente d'un enregistrement
                 qu'on oublie donne l'illusion d'une protection qui n'est pas
                 posée ». Chaque bascule a un CONSOMMATEUR serveur réel —
                 archivage du parc M1, onglet Seeders d'Import & Export,
                 alertes de la cloche.

                 ⚠ TROIS bascules du maître NE SONT PAS rendues, motifs datés
                 du 02/09/2026 (une bascule que rien ne lit est PA-59/60/61) :
                 - « Duplication d'un enregistrement » : aucun geste Dupliquer
                   n'existe dans la PWA — rien à afficher ni à retirer ;
                 - « Suppression groupée » : aucune sélection multiple
                   n'existe — et le maître lui-même la verrouille derrière la
                   suppression simple ;
                 - « Sauvegarde automatique hebdomadaire » : la sauvegarde
                   réelle est QUOTIDIENNE (`SauvegardeBaseQuotidienneJob`,
                   02h00) — une bascule « hebdomadaire » qui ne commanderait
                   pas ce job affirmerait un réglage sans effet ; le rappel de
                   téléchargement du maître n'a pas de consommateur.
                 Le jour où l'un de ces gestes existera, la bascule se pose au
                 registre AVEC son consommateur, jamais avant. --}}
            <div class="space-y-2.5">
              @foreach ($bascules as $bascule)
                @php($risque = $risques[$bascule['risque']])
                <div class="flex items-start gap-3 rounded-lg border border-slate-200 p-3.5">
                  <button type="button" role="switch" aria-checked="{{ $bascule['actif'] ? 'true' : 'false' }}"
                          @if ($peutEcrire) wire:click="basculerOption('{{ $bascule['cle'] }}')" @else disabled @endif
                          class="btn shrink-0 mt-0.5 w-11 h-6 rounded-full relative transition-colors"
                          style="background:{{ $bascule['actif'] ? 'var(--succes)' : '#CBD5E1' }}">
                    <span class="absolute top-0.5 w-5 h-5 rounded-full bg-white shadow transition-all" style="left:{{ $bascule['actif'] ? '22px' : '2px' }}"></span>
                  </button>
                  <div class="min-w-0 flex-1">
                    <div class="flex flex-wrap items-center gap-2">
                      <p class="text-[15px] font-semibold text-slate-700">{{ $bascule['titre'] }}</p>
                      <span class="text-[11px] font-bold rounded px-1.5 py-0.5" style="background:{{ $risque['fond'] }};color:{{ $risque['texte'] }}">{{ $risque['libelle'] }}</span>
                    </div>
                    <p class="text-[13px] text-slate-500 mt-0.5 leading-relaxed">{{ $bascule['detail'] }}</p>
                  </div>
                </div>
              @endforeach
            </div>

            {{-- Les deux groupes du registre sans onglet dédié au maître
                 (`social`, `exploitation`) — logés ici depuis le 01/09/2026
                 (décision n° 2 de DIRECTIVE_CONFORMITE_100.md : aucun groupe
                 réel ne disparaît). --}}
            <div class="mt-5 pt-4 border-t border-slate-100">
              <h3 class="text-sm font-bold text-slate-700 mb-1">{{ __('pwa.parametres.section_social') }}</h3>
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                @foreach (($groupesOnglet['social'] ?? []) as $ligne)
                  @include('pwa.transverse._parametre_ligne', ['ligne' => $ligne, 'colspan' => false])
                @endforeach
              </div>
            </div>
            <div class="mt-5 pt-4 border-t border-slate-100">
              <h3 class="text-sm font-bold text-slate-700 mb-1">{{ __('pwa.parametres.section_exploitation') }}</h3>
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                @foreach (($groupesOnglet['exploitation'] ?? []) as $ligne)
                  @include('pwa.transverse._parametre_ligne', ['ligne' => $ligne, 'colspan' => false])
                @endforeach
              </div>
            </div>

            {{-- maquette l.194-202 — le rappel du maître, avec son lien réel. --}}
            <div class="mt-5 pt-4 border-t border-slate-100">
              <h3 class="text-sm font-bold text-slate-700 mb-1">{{ __('pwa.parametres.section_activation_suppression') }}</h3>
              <p class="text-[15px] text-slate-500">
                {{ __('pwa.parametres.suppression_rappel_a') }}
                <strong>{{ __('pwa.parametres.suppression_rappel_fort') }}</strong>{{ __('pwa.parametres.suppression_rappel_b') }}
                <a href="{{ route('pwa.import-export', ['onglet' => 'restaurer']) }}" wire:navigate class="underline font-semibold" style="color:var(--navy)">{{ __('pwa.parametres.suppression_rappel_lien') }}</a>{{ __('pwa.parametres.suppression_rappel_c') }}
              </p>
            </div>
        @endif

        </div>

        {{--
            L'OMBRE du tableau des canaux (G5, 02/09/2026) : sur les six
            onglets qui ne sont pas « Canaux de réservation », le tableau du
            maître est rendu `hidden` — même partiel que l'onglet réel, donc
            jamais deux copies qui divergent — pour que ses entêtes existent
            dans le HTML de chaque GET (`ColonnesDesTableauxPwaTest` mesure
            le premier GET, servi sur l'onglet « Identité & Légal »).

            La branche PREMIÈRE du `@if` est volontairement vide : le
            comparateur de structure (`t-structure.js`) lit la source Blade
            en coupant les branches alternatives — l'ombre vit dans le
            `@else` précisément pour ne pas compter comme un bloc de l'onglet
            ouvert, qu'elle ne modifie en rien à l'écran.
        --}}
        @if ($onglet === 'canaux')
        @else
          <div hidden>
            @include('pwa.transverse.partials.tableau-canaux')
          </div>
        @endif

      </div>
    </main>
  </div>

  {{-- MODALE D'ÉDITION — derrière `@if`, jamais rendue au premier GET. --}}
  @if ($etatFormulaire === 'parametre' && $definitionEditee !== null)
    <x-pwa.modale :titre="$definitionEditee->libelle" :sousTitre="$definitionEditee->aide" largeur="480px">
      <form wire:submit.prevent="enregistrerParametre" class="space-y-4">
        <div>
          <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ $definitionEditee->libelle }}</label>

          {{-- LE TYPE EST UN REGISTRE FERMÉ, ET L'INCONNU REFUSE D'OFFRIR UN
               CHAMP : le rendre en texte libre laisserait saisir n'importe quoi
               dans un booléen, et le refus ne tomberait qu'à l'enregistrement
               (PA-125). --}}
          @if ($definitionEditee->type === 'booleen')
            <select wire:model="valeurEditee" class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm bg-white">
              <option value="true">{{ __('parametres_pwa.oui') }}</option>
              <option value="false">{{ __('parametres_pwa.non') }}</option>
            </select>
          @elseif ($definitionEditee->type === 'choix')
            <select wire:model="valeurEditee" class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm bg-white">
              @foreach ($definitionEditee->choix as $choix)
                <option value="{{ $choix }}">{{ $definitionEditee->libelleDuChoix($choix) }}</option>
              @endforeach
            </select>
          @elseif (in_array($definitionEditee->type, ['entier', 'decimal'], true))
            <input type="number" step="{{ $definitionEditee->type === 'entier' ? '1' : 'any' }}" wire:model="valeurEditee"
                   class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm">
          @elseif ($definitionEditee->type === 'texte')
            <input type="text" wire:model="valeurEditee" class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm">
          @else
            <p class="text-[12px] text-amber-700">{{ __('pwa.parametres.type_inconnu') }}</p>
          @endif

          @error('valeurEditee') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>

        <div class="flex justify-end gap-3 pt-2">
          <button type="button" wire:click="fermerModales" class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
          <button type="submit" class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('parametres_pwa.enregistrer') }}</button>
        </div>
      </form>
    </x-pwa.modale>
  @endif

  {{-- MODALE CANAL — ajout (clé vide, avec l'aide du maître :
       `Dialogue.saisir`, canaux-engine.js) ou renommage. --}}
  @if ($etatFormulaire === 'canal')
    <x-pwa.modale
        :titre="$canalCleEditee === '' ? __('pwa.parametres.canaux_modale_titre_ajout') : __('pwa.parametres.canaux_modale_titre_renommage')"
        :sousTitre="$canalCleEditee === '' ? __('pwa.parametres.canaux_aide_ajout') : __('pwa.parametres.canaux_aide_renommage')"
        largeur="420px">
      <form wire:submit.prevent="enregistrerCanal" class="space-y-4">
        <div>
          <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('pwa.parametres.canaux_champ_nom') }}</label>
          <input type="text" wire:model="canalNom" class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm">
          @error('canalNom') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>

        <div class="flex justify-end gap-3 pt-2">
          <button type="button" wire:click="fermerModales" class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
          <button type="submit" class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('parametres_pwa.enregistrer') }}</button>
        </div>
      </form>
    </x-pwa.modale>
  @endif

  {{-- CONFIRMATION de désactivation d'un canal EMPLOYÉ — la modale du dépôt,
       jamais `wire:confirm` (boîte native hors charte, MotifsInterditsPwaTest).
       Les mots du maître (`canaux-engine.js`, Dialogue.confirmer), avec le
       compte réel de réservations. --}}
  @php($canalConfirme = $canalADesactiver === null ? null : $canaux?->firstWhere('id', $canalADesactiver))
  @if ($canalConfirme !== null)
    <x-pwa.modale :titre="__('pwa.parametres.canaux_bouton_desactiver')" largeur="420px">
      <p class="text-sm text-slate-600">
        {{ __('pwa.parametres.canaux_confirmation_desactivation', ['nom' => $canalConfirme->nom, 'n' => $canalConfirme->reservations_count]) }}
      </p>
      <div class="flex justify-end gap-3 pt-4">
        <button type="button" wire:click="$set('canalADesactiver', null)"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="basculerCanal('{{ $canalConfirme->id }}')"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('pwa.parametres.canaux_bouton_desactiver') }}</button>
      </div>
    </x-pwa.modale>
  @endif

  {{-- MODALE LOGO / FAVICON — le téléversement RÉEL (02/09/2026). Le champ
       `type="file"` ne vit QUE derrière ce `@if` (`RefuseLaSaisie`). --}}
  @if ($etatFormulaire === 'logo' || $etatFormulaire === 'favicon')
    @php($estLogo = $etatFormulaire === 'logo')
    <x-pwa.modale
        :titre="$estLogo ? __('pwa.parametres.apparence_logo_bouton') : __('pwa.parametres.apparence_favicon_bouton')"
        :sousTitre="$estLogo ? __('pwa.parametres.apparence_champ_logo') : __('pwa.parametres.apparence_champ_favicon')"
        largeur="440px">
      <form wire:submit.prevent="{{ $estLogo ? 'enregistrerLogo' : 'enregistrerFavicon' }}" class="space-y-4">
        <div>
          <input type="file" wire:model="{{ $estLogo ? 'logoTeleverse' : 'faviconTeleverse' }}"
                 accept="{{ $estLogo ? 'image/png,image/jpeg' : 'image/png,image/jpeg,image/x-icon,.ico' }}"
                 class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm">
          <div wire:loading wire:target="{{ $estLogo ? 'logoTeleverse' : 'faviconTeleverse' }}"
               class="text-[12px] text-slate-400 mt-1">{{ __('pwa.parametres.apparence_televersement') }}</div>
          @error($estLogo ? 'logoTeleverse' : 'faviconTeleverse') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>

        <div class="flex justify-end gap-3 pt-2">
          <button type="button" wire:click="fermerModales" class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
          <button type="submit" class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('parametres_pwa.enregistrer') }}</button>
        </div>
      </form>
    </x-pwa.modale>
  @endif

  {{-- MODALE TABLE — création (id vide : espace + numéro + places, la
       transposition du `Dialogue.saisir` « espace numero » du maître en
       champs distincts — un texte libre à découper serait le motif que le
       CdCF interdit) ou renumérotation (numéro seul, comme le maître). --}}
  @if ($etatFormulaire === 'table')
    @php($creationTable = $tableIdEditee === '')
    <x-pwa.modale
        :titre="$creationTable ? __('pwa.parametres.table_modale_titre_ajout') : __('pwa.parametres.table_modale_titre_renumerotation', ['libelle' => $tableEditee?->libelle ?? ''])"
        :sousTitre="$creationTable ? null : __('pwa.parametres.table_aide_renumerotation')"
        largeur="440px">
      <form wire:submit.prevent="enregistrerTable" class="space-y-4">
        @if ($creationTable)
          <div>
            <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('pwa.parametres.table_champ_espace') }}</label>
            <select wire:model="tableEspace" class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm bg-white">
              <option value="">{{ __('pwa.parametres.table_espace_choisir') }}</option>
              @foreach (\App\Domain\Ventes\Services\TableSalleService::ESPACES as $espaceChoix)
                @if ($espaceChoix['avecTables'])
                  <option value="{{ $espaceChoix['cle'] }}">{{ $espaceChoix['libelle'] }}</option>
                @endif
              @endforeach
            </select>
            @error('tableEspace') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
          </div>
        @endif
        <div>
          <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('pwa.parametres.table_champ_numero') }}</label>
          <input type="number" step="1" min="1" wire:model="tableNumero" class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm">
          @error('tableNumero') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>
        @if ($creationTable)
          <div>
            <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('pwa.parametres.table_champ_places') }}</label>
            <input type="number" step="1" min="1" wire:model="tablePlaces" class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm" placeholder="4">
            @error('tablePlaces') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
          </div>
        @endif

        <div class="flex justify-end gap-3 pt-2">
          <button type="button" wire:click="fermerModales" class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
          <button type="submit" class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('parametres_pwa.enregistrer') }}</button>
        </div>
      </form>
    </x-pwa.modale>
  @endif

  {{-- CONFIRMATION « Rétablir le jeu initial ? » — les mots du maître
       (`Dialogue.confirmer`, parametres.html l.312-320), par la modale du
       dépôt, jamais `wire:confirm`. --}}
  @if ($confirmationRetablirTables)
    <x-pwa.modale :titre="__('pwa.parametres.tables_retablir_titre')" largeur="420px">
      <p class="text-sm text-slate-600">{{ __('pwa.parametres.tables_retablir_message') }}</p>
      <div class="flex justify-end gap-3 pt-4">
        <button type="button" wire:click="$set('confirmationRetablirTables', false)"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="retablirTables"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('pwa.parametres.tables_retablir_confirmer') }}</button>
      </div>
    </x-pwa.modale>
  @endif

  @include('pwa.partials.acces-rapide')

</div>
