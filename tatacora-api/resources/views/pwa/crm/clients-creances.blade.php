{{--
    CLIENTS & CREANCES (M3)
    Maitre : prototype_v2/pages/m3-clients-creances.html + m3-clients-creances.js

    Les quatre onglets du maitre sont TOUS portes depuis PA-165 (02/09/2026).
    Voir le docblock de `ClientsCreances` pour ce qui reste un ecart NOMME
    sans etre un refus de bloc (champ « Ville » de la modale Nouveau client,
    cinquieme mode de reglement).
--}}
@php
    use App\Pwa\Livewire\Crm\ClientsCreances;
    use App\Pwa\Support\MontantFcfa;
    use Illuminate\Support\Str;

    // Classes d'onglets : directive PO du 01/09/2026, UN SEUL AUTEUR —
    // voir le docblock de `App\Pwa\Support\Onglets`.
    $classeOnglet = static fn (bool $actif): string => \App\Pwa\Support\Onglets::classes($actif);

    $entete = static fn (string $libelle, bool $gauche = false): string => '<th class="px-3 py-2.5 '
        . ($gauche ? 'text-left' : 'text-right')
        . ' text-[11px] uppercase tracking-wide text-white/90 font-semibold">'
        . e($libelle) . '</th>';

    $libelleOnglet = static fn (string $cle): string => __(match ($cle) {
        'dettes' => 'pwa.clients.onglet_dettes',
        'relances' => 'pwa.clients.onglet_relances',
        'avances' => 'pwa.clients.onglet_avances',
        default => 'pwa.clients.onglet_clients',
    });

    $libelleTranche = static fn (string $cle): string => __(match ($cle) {
        '31_60' => 'pwa.clients.tranche_31_60',
        '61_90' => 'pwa.clients.tranche_61_90',
        'plus_90' => 'pwa.clients.tranche_plus_90',
        default => 'pwa.clients.tranche_0_30',
    });

    $libelleCanal = static fn (string $cle): string => __(match ($cle) {
        'whatsapp' => 'pwa.clients.canal_whatsapp',
        'email' => 'pwa.clients.canal_email',
        'courrier' => 'pwa.clients.canal_courrier',
        'visite' => 'pwa.clients.canal_visite',
        default => 'pwa.clients.canal_telephone',
    });

    $libelleMode = static fn (string $cle): string => __(match ($cle) {
        'mobile_money' => 'pwa.clients.mode_mobile_money',
        'carte' => 'pwa.clients.mode_carte',
        'virement' => 'pwa.clients.mode_virement',
        default => 'pwa.clients.mode_especes',
    });

    /*
     * G5 (ColonnesDesTableauxPwaTest, 01/09/2026) — chaque colonne du maitre
     * doit exister dans le HTML du PREMIER GET, onglets fermes compris. Les
     * entetes de chaque tableau sont donc definis UNE FOIS ici et rendus deux
     * fois : dans le tableau vivant de l'onglet actif, et dans le squelette
     * `hidden` du panneau ferme (voir la fin de la zone). Deux listes ecrites
     * a deux endroits auraient fini par diverger sans que la garde le voie —
     * le squelette serait reste vert pendant que le tableau vivant perdait
     * une colonne.
     */
    $tableaux = [
        // vueClients(), m3-clients-creances.js l.135-137.
        'clients' => [
            [__('pwa.clients.col_client'), true],
            [__('pwa.clients.col_telephone')],
            [__('pwa.clients.col_type')],
            [__('pwa.clients.col_solde')],
            [__('pwa.clients.col_pieces')],
            // « Anciennete » — colonne du maitre, donnee non disponible en
            // contexte de client isole (PA-20) : la cellule rend un tiret.
            [__('pwa.clients.col_anciennete')],
            [''],
        ],
        // vueRelances(), l.207-208 — « Anciennete max » et « Derniere
        // relance » sont rendues avec des donnees reelles depuis le
        // 01/09/2026 (voir ClientsCreances::clientsARelancer()).
        'a_relancer' => [
            [__('pwa.clients.col_client'), true],
            [__('pwa.clients.col_montant_du')],
            [__('pwa.clients.col_anciennete_max')],
            [__('pwa.clients.col_derniere_relance')],
            [''],
        ],
        // vueRelances(), l.223-224.
        'historique_relances' => [
            [__('pwa.clients.col_date'), true],
            [__('pwa.clients.col_client')],
            [__('pwa.clients.col_canal')],
            [__('pwa.clients.col_montant_reclame')],
            [__('pwa.clients.col_promesse')],
            [__('pwa.clients.col_par')],
        ],
        // vueAvances(), l.277-278.
        'avances' => [
            [__('pwa.clients.col_date'), true],
            [__('pwa.clients.col_client')],
            [__('pwa.clients.col_origine')],
            [__('pwa.clients.col_avance_versee')],
            [__('pwa.clients.col_reste_du')],
        ],
        // vueAvances(), l.295-296.
        'recouvrements' => [
            [__('pwa.clients.col_numero'), true],
            [__('pwa.clients.col_date')],
            [__('pwa.clients.col_client')],
            [__('pwa.clients.col_piece')],
            [__('pwa.clients.col_mode')],
            [__('pwa.clients.col_reference')],
            [__('pwa.clients.col_montant')],
            [__('pwa.clients.col_par')],
        ],
        // Modale « Historique d'un client » (ouvrirHistorique(), l.564-569)
        // et son etat PDF (l.597). Le maitre imbrique le detail SOUS le
        // libelle a l'ecran (l.577) mais nomme « Detail » comme colonne a
        // part entiere dans son etat PDF : la colonne est promue a l'ecran
        // (meme donnee, decision du 01/09/2026) pour que les cinq entetes de
        // l'etat se retrouvent au premier GET (G5, groupe « entetes #2 »).
        'historique_client' => [
            [__('pwa.clients.col_date'), true],
            [__('pwa.clients.col_type')],
            [__('pwa.clients.col_libelle')],
            [__('pwa.clients.col_detail')],
            [__('pwa.clients.col_montant')],
        ],
    ];

    $thead = static function (string $cle) use ($tableaux, $entete): string {
        $cellules = '';
        foreach ($tableaux[$cle] as $colonne) {
            $cellules .= $entete($colonne[0], $colonne[1] ?? false);
        }

        return '<thead class="bg-[var(--navy)]"><tr>' . $cellules . '</tr></thead>';
    };

    // « Tableau vide = thead quand meme » : la ligne d'etat vide remplace le
    // panneau vide() du maitre A L'INTERIEUR du tableau, pour que les
    // colonnes restent visibles (et verifiables) meme sans donnees.
    $ligneVide = static fn (string $cle, string $message): string => '<tr><td colspan="'
        . count($tableaux[$cle])
        . '" class="py-14 text-center text-slate-400 text-[13px]">' . e($message) . '</td></tr>';
@endphp
<div class="contents">

  @include('pwa.partials.barre-superieure')

  <div class="flex flex-1 overflow-hidden">
    @include('pwa.partials.menu-lateral')
    <main class="flex-1 overflow-y-auto">
      <div class="max-w-[1440px] mx-auto p-5 lg:p-8">

        <div class="mb-5 flex flex-wrap items-start justify-between gap-3">
          <div>
            <div class="flex items-center gap-2.5">
              <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--navy)" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M17 21v-2a4 4 0 00-4-4H5a4 4 0 00-4 4v2M9 11a4 4 0 100-8 4 4 0 000 8zM23 21v-2a4 4 0 00-3-3.87M16 3.13a4 4 0 010 7.75"/></svg>
              <h1 class="text-lg lg:text-xl font-bold" style="color:var(--navy)">{{ __('pwa.clients.titre') }}</h1>
            </div>
            <p class="text-[15px] text-slate-500 mt-1.5">{!! __('pwa.clients.sous_titre') !!}</p>
          </div>
          <div class="flex flex-wrap gap-2">
            <a href="{{ route('pwa.reservations') }}" wire:navigate class="text-[13px] px-3.5 py-2 rounded-lg border border-slate-300 bg-white hover:bg-slate-50">{{ __('pwa.clients.lien_reservations') }}</a>
            @if ($peutEcrireClient)
              <button type="button" wire:click="ouvrirFormulaireClient"
                      class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white hover:opacity-90 font-semibold">{{ __('pwa.clients.nouveau_client') }}</button>
            @endif
            {{-- ⚠ DÉROGATION PO du 01/09/2026, rappelée le 02/09/2026 — la
                 paire de boutons du maître (« Excel » / « PDF »,
                 `m3-clients-creances.html` l.64-65) est remplacée par UN
                 bouton « Exporter » qui ouvre la modale d'export partagée ;
                 le format PDF A4 / Excel s'y choisit. Le PDF est un état
                 RÉEL de la liste affichée (dompdf, en-tête établissement
                 partagée), ajouté le 02/09/2026 — jusque-là seul « Excel »
                 était porté. Registre : `App\Pwa\Support\DerogationsMaquette`
                 (export_bouton_unique).
                 Jeton : maitre-refuse:m3-clients-creances.html#page --}}
            <button type="button" wire:click="ouvrirExport"
                    class="text-[13px] px-3.5 py-2 rounded-lg border border-slate-300 bg-white hover:bg-slate-50">{{ __('pwa.export.bouton') }}</button>
          </div>
        </div>

        @if (session('pwa-succes'))
          <div class="mb-4 rounded-xl px-4 py-3 text-[13px] font-semibold"
               style="background:#E8F5E9;color:#2E7D32;border:1px solid #C8E6C9">{{ session('pwa-succes') }}</div>
        @endif

        @error('export')
          <div class="mb-4 rounded-xl px-4 py-3 text-[13px]"
               style="background:#FFFBEB;color:#78350F;border:1px solid #FDE68A">{{ $message }}</div>
        @enderror

        {{-- ================ BANDE DE CINQ INDICATEURS (l.41) ================ --}}
        <div id="kpis" class="grid grid-cols-2 lg:grid-cols-5 gap-3 mb-5">
          <div class="bg-white rounded-xl border border-slate-200 p-3.5">
            <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('pwa.clients.kpi_creances') }}</div>
            <div class="text-lg font-bold mt-1" style="color:var(--navy)">{{ MontantFcfa::format($totaux['total_du']) }}</div>
            <div class="text-[11px] text-slate-400 mt-0.5">{{ __('pwa.clients.kpi_creances_detail', ['pieces' => $totaux['nb_pieces'], 'clients' => $totaux['nb_clients']]) }}</div>
          </div>
          <div class="bg-white rounded-xl border border-slate-200 p-3.5">
            <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('pwa.clients.kpi_douteux') }}</div>
            <div class="text-lg font-bold mt-1 {{ MontantFcfa::format($kpiDettesDouteuses) !== MontantFcfa::TIRET && $kpiDettesDouteuses !== '0.00' ? 'text-red-600' : '' }}">{{ MontantFcfa::formatOuTiret($kpiDettesDouteuses) }}</div>
            <div class="text-[11px] text-slate-400 mt-0.5">{{ __('pwa.clients.kpi_tranches_detail') }}</div>
          </div>
          <div class="bg-white rounded-xl border border-slate-200 p-3.5">
            <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('pwa.clients.kpi_recentes') }}</div>
            <div class="text-lg font-bold mt-1 text-emerald-600">{{ MontantFcfa::formatOuTiret($kpiRecent) }}</div>
            <div class="text-[11px] text-slate-400 mt-0.5">{{ __('pwa.clients.kpi_recentes_detail') }}</div>
          </div>
          <div class="bg-white rounded-xl border border-slate-200 p-3.5">
            <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('pwa.clients.kpi_encaisse') }}</div>
            <div class="text-lg font-bold mt-1 text-emerald-600">{{ MontantFcfa::formatOuTiret($kpiEncaisse30j) }}</div>
            <div class="text-[11px] text-slate-400 mt-0.5">{{ __('pwa.clients.kpi_encaisse_detail_reel') }}</div>
          </div>
          <div class="bg-white rounded-xl border border-slate-200 p-3.5">
            <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('pwa.clients.kpi_relancer') }}</div>
            <div class="text-lg font-bold mt-1 {{ $kpiARelancer > 0 ? 'text-amber-600' : 'text-slate-400' }}">{{ $kpiARelancer }}</div>
            <div class="text-[11px] text-slate-400 mt-0.5">{{ __('pwa.clients.kpi_relancer_detail_reel') }}</div>
          </div>
        </div>

        {{-- ================= LES QUATRE ONGLETS (l.43-48) ================= --}}
        <div class="flex flex-wrap gap-2 mb-4">
          @foreach (\App\Pwa\Livewire\Crm\ClientsCreances::ONGLETS as $cle)
            <button wire:click="$set('onglet', '{{ $cle }}')" class="{{ $classeOnglet($onglet === $cle) }}">{{ $libelleOnglet($cle) }}</button>
          @endforeach
        </div>

        {{-- ================= RECHERCHE ET FILTRES (l.52-70) ================== --}}
        <div class="bg-white rounded-xl border border-slate-200 p-3.5 mb-4">
          <div class="flex flex-wrap gap-2.5 items-center">
            <div class="relative flex-1 min-w-[220px]">
              <svg class="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="8"/><path d="M21 21l-4.35-4.35"/></svg>
              <input type="search" id="rech" wire:model.live.debounce.300ms="recherche" placeholder="{{ __('pwa.clients.recherche') }}"
                class="w-full text-[13px] border border-slate-300 rounded-lg pl-9 pr-3 py-2 focus:border-[var(--gold)] focus:outline-none">
            </div>
            @if ($onglet === 'clients')
              <select id="f-etat" wire:model.live="etat" class="text-[13px] border border-slate-300 rounded-lg px-3 py-2">
                <option value="">{{ __('pwa.clients.tous_clients') }}</option>
                <option value="debiteur">{{ __('pwa.clients.etat_debiteur') }}</option>
                <option value="solde">{{ __('pwa.clients.etat_solde') }}</option>
              </select>
            @endif
            <div class="flex-1"></div>
          </div>
        </div>

        {{-- Un SEUL point de montage, comme le maître (l.69) : les quatre
             onglets partagent `#zone`, dont le contenu change avec l'onglet
             actif — jamais quatre conteneurs distincts.

             Le comparateur de structure lit le maître SANS exécuter son
             JavaScript : `#zone` y est vide, et la carte de tableau que la
             PWA rend dessous lui paraît « en trop ». Elle ne l'est pas —
             c'est la carte même que le maître fabrique dans `#zone`
             (m3-clients-creances.js, tableau(), l.326-336). Déclaré le
             02/09/2026, quand le tableau des clients est devenu visible dans
             l'état nominal (avant, la branche « état vide » venait en
             premier, contre la convention du comparateur lui-même) :
             structure-ajout:m3-clients-creances.html#div-f1c8b22c --}}
        <div id="zone">

        {{-- =============================== ONGLET 1 — CLIENTS =============================== --}}
        @if ($onglet === 'clients')
              {{-- Barre de selection groupee du maitre (crud-ui.js l.36-46),
                   rendue depuis le 03/09/2026 : « la suppression en bulk »
                   demandee par le Product Owner. Elle ARCHIVE —
                   `ReferentielClientService` pose `actif = false`.
                   structure-ajout:m3-clients-creances.html#barre-selection
                   structure-ajout:m3-clients-creances.html#div-20a2b0c8 --}}
              @if ($peutArchiver && $selection !== [])
                <div class="flex items-center gap-3 bg-[var(--navy)] text-white rounded-lg px-4 py-2.5 mb-3 text-xs no-print">
                  <span>{!! __('crm.archivage.selectionnes', ['nombre' => '<strong>' . count($selection) . '</strong>']) !!}</span>
                  <div class="flex-1"></div>
                  <button type="button" wire:click="confirmerArchivageClient"
                          class="underline decoration-white/40 hover:decoration-white">{{ __('crm.archivage.bouton_lot') }}</button>
                  <button type="button" wire:click="$set('selection', [])" class="text-white/60 hover:text-white"
                          aria-label="{{ __('pwa.modale.annuler') }}">✕</button>
                </div>
              @endif
              <div class="bg-white rounded-xl border border-slate-200 overflow-hidden mb-2">
                <div class="overflow-x-auto">
                  <table class="w-full text-[13px]">
                    {!! $thead('clients') !!}
                    <tbody>
                      @forelse ($lignes as $ligne)
                        <tr class="border-t border-slate-100 hover:bg-slate-50" wire:key="client-{{ $ligne->id }}">
                          <td class="px-3 py-2.5">
                            <div class="font-semibold text-slate-800 flex items-center gap-2">
                              {{-- La case de SELECTION vit dans la cellule du
                                   nom, pas dans une colonne a elle : l'entete
                                   de ce tableau est construit par `$thead`
                                   depuis un registre de colonnes, et une
                                   colonne de plus ferait diverger le colspan
                                   de la ligne d'etat vide. Elle n'est rendue
                                   qu'a qui peut archiver — une case sans
                                   action serait un controle qui n'ouvre rien.
                                   structure-ajout:m3-clients-creances.html#case-selection --}}
                              @if ($peutArchiver && $ligne->actif)
                                <input type="checkbox" value="{{ $ligne->id }}" wire:model.live="selection"
                                       class="w-4 h-4 rounded" aria-label="{{ __('crm.archivage.selection_ligne') }}">
                              @endif
                              <span>{{ trim($ligne->nom . ' ' . ($ligne->prenom ?? '')) }}</span>
                              {{-- Un client ARCHIVE reste dans la liste,
                                   marque : le masquer le rendrait
                                   indiscernable d'une fiche inexistante, et
                                   « reste restaurable » ne serait tenue nulle
                                   part (PA-59/60/61). --}}
                              @unless ($ligne->actif)
                                <span class="text-[10px] px-1.5 py-0.5 rounded font-normal"
                                      style="background:#F3F4F6;color:#6B7280">{{ __('crm.archivage.badge') }}</span>
                              @endunless
                            </div>
                          </td>
                          <td class="px-3 py-2.5 text-right text-slate-600">{{ $ligne->telephone !== '' ? $ligne->telephone : MontantFcfa::TIRET }}</td>
                          <td class="px-3 py-2.5 text-right text-slate-600">{{ ClientsCreances::TYPES_CLIENT[$ligne->type_client] ?? $ligne->type_client }}</td>
                          <td class="px-3 py-2.5 text-right font-semibold {{ $ligne->solde !== '0.00' ? 'text-red-600' : 'text-slate-400' }}">
                            {{ $ligne->solde === '0.00' ? MontantFcfa::TIRET : MontantFcfa::format($ligne->solde) }}
                          </td>
                          <td class="px-3 py-2.5 text-right text-slate-600">{{ $ligne->pieces > 0 ? $ligne->pieces : MontantFcfa::TIRET }}</td>
                          {{-- Ancienneté de la plus ancienne impayée — même
                               prédicat que le solde (SoldeClientService,
                               02/09/2026) ; « — » = aucune dette, jamais un
                               zéro plausible. Rouge au-delà de 90 j, comme
                               l'onglet Suivi des dettes. --}}
                          <td class="px-3 py-2.5 text-right {{ $ligne->anciennete === null ? 'text-slate-300' : ($ligne->anciennete > 90 ? 'text-red-600 font-semibold' : 'text-amber-600') }}">
                            {{ $ligne->anciennete === null ? MontantFcfa::TIRET : __('pwa.clients.anciennete_jours', ['jours' => $ligne->anciennete]) }}
                          </td>
                          <td class="px-3 py-2.5 text-right whitespace-nowrap">
                            <button type="button" wire:click="ouvrirHistoriqueClient('{{ $ligne->id }}')" class="text-[12px] px-2.5 py-1 rounded-lg border border-slate-300 hover:bg-white">{{ __('pwa.clients.action_historique') }}</button>
                            @if ($ligne->solde !== '0.00' && $peutEncaisser)
                              <button type="button" wire:click="ouvrirRecouvrement('{{ $ligne->id }}')" class="text-[12px] px-2.5 py-1 rounded-lg bg-[var(--navy)] text-white hover:opacity-90 ml-1">{{ __('pwa.clients.action_recouvrement') }}</button>
                            @endif
                            {{-- « Supprimer » du maitre (crud-ui.js l.100),
                                 rendu ici comme ARCHIVAGE : le mot du bouton
                                 est celui que le client a valide, le geste
                                 pose `actif = false`.
                                 structure-ajout:m3-clients-creances.html#bouton-supprimer --}}
                            @unless ($ligne->actif)
                              @if ($peutEcrireClient)
                                <button type="button" wire:click="restaurerClient('{{ $ligne->id }}')" class="text-[12px] px-2.5 py-1 rounded-lg border border-slate-300 hover:bg-white ml-1">{{ __('crm.archivage.bouton_restaurer') }}</button>
                              @endif
                            @else
                              @if ($peutArchiver)
                                <button type="button" wire:click="confirmerArchivageClient('{{ $ligne->id }}')" class="text-[12px] px-2.5 py-1 rounded-lg border border-red-200 text-[var(--erreur)] hover:bg-red-50 ml-1">{{ __('crm.archivage.bouton_ligne') }}</button>
                              @endif
                            @endunless
                          </td>
                        </tr>
                      @empty
                        {!! $ligneVide('clients', __('pwa.clients.vide')) !!}
                      @endforelse
                    </tbody>
                  </table>
                </div>
              </div>

        {{-- =============================== ONGLET 2 — SUIVI DES DETTES ===============================
             UN SEUL `@if/@elseif` (jamais quatre `@if` séparés) : le
             comparateur de structure (`t-structure.js`) ne garde que la
             PREMIÈRE branche d'un conditionnel dans son état « nominal » —
             quatre `@if` indépendants lui feraient garder les QUATRE corps à
             la fois sous `#zone`, qui doit rester un point de montage vide
             côté maître. --}}
        @elseif ($onglet === 'dettes')
          <div class="bg-amber-50 border border-amber-200 rounded-xl p-3.5 mb-4">
            <p class="text-[13px] text-amber-900">
              <strong>{{ __('pwa.clients.dettes_titre_encadre') }}</strong>
              {{ __('pwa.clients.dettes_texte_encadre') }}
            </p>
          </div>
            <div class="bg-white rounded-xl border border-slate-200 overflow-hidden mb-2">
              <div class="overflow-x-auto">
                <table class="w-full text-[13px]">
                  <thead class="bg-[var(--navy)]"><tr>
                    {!! $entete(__('pwa.clients.col_client'), true) !!}
                    @foreach (array_keys(\App\Pwa\Livewire\Crm\ClientsCreances::TRANCHES) as $tranche)
                      {!! $entete($libelleTranche($tranche)) !!}
                    @endforeach
                    {!! $entete(__('pwa.clients.col_total_du')) !!}
                    {!! $entete('') !!}
                  </tr></thead>
                  <tbody>
                    @forelse ($detteAgee as $ligne)
                      <tr class="border-t border-slate-100 hover:bg-slate-50" wire:key="dette-{{ $ligne['client_id'] }}">
                        <td class="px-3 py-2.5 font-semibold text-slate-800">{{ $ligne['nom'] }}</td>
                        @foreach (\App\Pwa\Livewire\Crm\ClientsCreances::TRANCHES as $cle => $bornes)
                          <td class="px-3 py-2.5 text-right {{ $ligne['tranches'][$cle] !== '0.00' ? 'font-semibold text-slate-700' : 'text-slate-300' }}">{{ MontantFcfa::formatOuTiret($ligne['tranches'][$cle]) }}</td>
                        @endforeach
                        <td class="px-3 py-2.5 text-right font-bold" style="color:var(--navy)">{{ MontantFcfa::format($ligne['total']) }}</td>
                        <td class="px-3 py-2.5 text-right">
                          <button type="button" wire:click="ouvrirHistoriqueClient('{{ $ligne['client_id'] }}')" class="text-[12px] px-2.5 py-1 rounded-lg border border-slate-300 hover:bg-white">{{ __('pwa.clients.action_detail') }}</button>
                        </td>
                      </tr>
                    @empty
                      <tr><td colspan="{{ count(\App\Pwa\Livewire\Crm\ClientsCreances::TRANCHES) + 3 }}" class="py-14 text-center text-slate-400 text-[13px]">{{ __('pwa.clients.dettes_vide') }}</td></tr>
                    @endforelse
                  </tbody>
                  @if ($detteAgee !== [])
                  <tfoot>
                    <tr class="border-t-2 border-slate-300 bg-slate-50 font-bold">
                      <td class="px-3 py-2.5" style="color:var(--navy)">{{ __('pwa.clients.dettes_total') }}</td>
                      @foreach (array_keys(\App\Pwa\Livewire\Crm\ClientsCreances::TRANCHES) as $tranche)
                        <td class="px-3 py-2.5 text-right">{{ MontantFcfa::formatOuTiret(collect($detteAgee)->reduce(fn ($t, $l) => bcadd((string) $t, $l['tranches'][$tranche], 2), '0.00')) }}</td>
                      @endforeach
                      <td class="px-3 py-2.5 text-right" style="color:var(--navy)">{{ MontantFcfa::format($totaux['total_du']) }}</td>
                      <td></td>
                    </tr>
                  </tfoot>
                  @endif
                </table>
              </div>
            </div>

        {{-- =============================== ONGLET 3 — RELANCES =============================== --}}
        @elseif ($onglet === 'relances')
          <div class="bg-slate-100 border border-slate-200 rounded-xl p-3.5 mb-4">
            <p class="text-[13px] text-slate-700">{{ __('pwa.clients.relances_encadre') }}</p>
          </div>

          <h3 class="text-[15px] font-bold mb-2.5" style="color:var(--navy)">{{ __('pwa.clients.relances_a_relancer_titre', ['nombre' => count($aRelancer)]) }}</h3>
            <div class="bg-white rounded-xl border border-slate-200 overflow-hidden mb-6">
              <div class="overflow-x-auto">
                <table class="w-full text-[13px]">
                  {!! $thead('a_relancer') !!}
                  <tbody>
                    @forelse ($aRelancer as $ligne)
                      <tr class="border-t border-slate-100 hover:bg-slate-50" wire:key="arelancer-{{ $ligne['id'] }}">
                        <td class="px-3 py-2.5 font-semibold text-slate-800">{{ $ligne['nom'] }}</td>
                        <td class="px-3 py-2.5 text-right font-semibold text-red-600">{{ MontantFcfa::format($ligne['solde']) }}</td>
                        {{-- Seuils de couleur du maitre (m3-clients-creances.js l.212) : rouge au-dela de 90 j, ambre sinon. --}}
                        <td class="px-3 py-2.5 text-right {{ $ligne['anciennete_max'] > 90 ? 'text-red-600 font-semibold' : 'text-amber-600' }}">{{ __('pwa.clients.anciennete_jours', ['jours' => $ligne['anciennete_max']]) }}</td>
                        <td class="px-3 py-2.5 text-slate-600">{{ $ligne['derniere_relance'] === null ? __('pwa.clients.relance_jamais') : \Illuminate\Support\Carbon::parse($ligne['derniere_relance'])->format('d/m/Y') }}</td>
                        <td class="px-3 py-2.5 text-right">
                          <button type="button" wire:click="ouvrirRelance('{{ $ligne['id'] }}')" class="text-[12px] px-2.5 py-1 rounded-lg bg-[var(--gold)] text-white hover:opacity-90">{{ __('pwa.clients.action_relancer') }}</button>
                        </td>
                      </tr>
                    @empty
                      {!! $ligneVide('a_relancer', __('pwa.clients.relances_a_relancer_vide')) !!}
                    @endforelse
                  </tbody>
                </table>
              </div>
            </div>

          <h3 class="text-[15px] font-bold mb-2.5" style="color:var(--navy)">{{ __('pwa.clients.relances_historique_titre', ['nombre' => $historiqueRelances->count()]) }}</h3>
            <div class="bg-white rounded-xl border border-slate-200 overflow-hidden">
              <div class="overflow-x-auto">
                <table class="w-full text-[13px]">
                  {!! $thead('historique_relances') !!}
                  <tbody>
                    @forelse ($historiqueRelances as $relance)
                      <tr class="border-t border-slate-100" wire:key="relance-{{ $relance->id }}">
                        <td class="px-3 py-2.5 text-slate-600">{{ $relance->date_relance?->format('d/m/Y') }}</td>
                        <td class="px-3 py-2.5 font-semibold text-slate-800">{{ $relance->client?->nomComplet() ?? MontantFcfa::TIRET }}</td>
                        <td class="px-3 py-2.5 text-slate-600">{{ $libelleCanal($relance->canal) }}</td>
                        <td class="px-3 py-2.5 text-right text-slate-700">{{ MontantFcfa::format($relance->montant_reclame) }}</td>
                        <td class="px-3 py-2.5 text-slate-600">{{ $relance->promesse?->format('d/m/Y') ?? MontantFcfa::TIRET }}</td>
                        <td class="px-3 py-2.5 text-slate-500 text-[12px]">{{ $relance->utilisateurCreation?->login ?? MontantFcfa::TIRET }}</td>
                      </tr>
                    @empty
                      {!! $ligneVide('historique_relances', __('pwa.clients.relances_historique_vide')) !!}
                    @endforelse
                  </tbody>
                </table>
              </div>
            </div>

        {{-- =============================== ONGLET 4 — HISTORIQUE & AVANCES =============================== --}}
        @else
          <h3 class="text-[15px] font-bold mb-2.5" style="color:var(--navy)">{{ __('pwa.clients.avances_titre', ['nombre' => $avances->count()]) }}</h3>
            <div class="bg-white rounded-xl border border-slate-200 overflow-hidden mb-6">
              <div class="overflow-x-auto">
                <table class="w-full text-[13px]">
                  {!! $thead('avances') !!}
                  <tbody>
                    @forelse ($avances as $reservation)
                      <tr class="border-t border-slate-100" wire:key="avance-{{ $reservation->id }}">
                        <td class="px-3 py-2.5 text-slate-600">{{ $reservation->date_arrivee?->format('d/m/Y') }}</td>
                        <td class="px-3 py-2.5 font-semibold text-slate-800">{{ $reservation->client?->nomComplet() ?? MontantFcfa::TIRET }}</td>
                        <td class="px-3 py-2.5 text-slate-600">{{ $reservation->canal?->nom ?? MontantFcfa::TIRET }}</td>
                        <td class="px-3 py-2.5 text-right font-semibold text-emerald-600">{{ MontantFcfa::format((string) $reservation->acompte) }}</td>
                        @php $reste = $reservation->resteAPayer(); @endphp
                        <td class="px-3 py-2.5 text-right {{ $reste !== null && $reste !== '0.00' ? 'text-red-600 font-semibold' : 'text-slate-400' }}">{{ $reste === null ? MontantFcfa::TIRET : ($reste === '0.00' ? __('pwa.clients.solde_paye') : MontantFcfa::format($reste)) }}</td>
                      </tr>
                    @empty
                      {!! $ligneVide('avances', __('pwa.clients.avances_vide')) !!}
                    @endforelse
                  </tbody>
                </table>
              </div>
            </div>

          <h3 class="text-[15px] font-bold mb-2.5" style="color:var(--navy)">{{ __('pwa.clients.recouvrements_titre', ['nombre' => $recouvrements->count()]) }}</h3>
            <div class="bg-white rounded-xl border border-slate-200 overflow-hidden">
              <div class="overflow-x-auto">
                <table class="w-full text-[13px]">
                  {!! $thead('recouvrements') !!}
                  <tbody>
                    @forelse ($recouvrements as $paiement)
                      <tr class="border-t border-slate-100" wire:key="paiement-{{ $paiement->id }}">
                        <td class="px-3 py-2.5 font-mono-tatacora text-[12px] text-slate-500">{{ Str::limit($paiement->id, 8, '') }}</td>
                        <td class="px-3 py-2.5 text-slate-600">{{ $paiement->date_paiement?->format('d/m/Y') }}</td>
                        <td class="px-3 py-2.5 font-semibold text-slate-800">{{ $paiement->facture?->client?->nomComplet() ?? MontantFcfa::TIRET }}</td>
                        <td class="px-3 py-2.5 text-slate-600">{{ $paiement->facture?->numero_mecef ?? MontantFcfa::TIRET }}</td>
                        <td class="px-3 py-2.5 text-slate-600">{{ $libelleMode($paiement->mode_paiement) }}</td>
                        <td class="px-3 py-2.5 text-slate-500 text-[12px]">{{ Str::limit($paiement->id, 8, '') }}</td>
                        <td class="px-3 py-2.5 text-right font-semibold text-emerald-600">{{ MontantFcfa::format($paiement->montant) }}</td>
                        <td class="px-3 py-2.5 text-slate-500 text-[12px]">{{ $paiement->utilisateurCreation?->login ?? MontantFcfa::TIRET }}</td>
                      </tr>
                    @empty
                      {!! $ligneVide('recouvrements', __('pwa.clients.recouvrements_vide')) !!}
                    @endforelse
                  </tbody>
                </table>
              </div>
            </div>
        @endif

        {{-- ================= PANNEAUX FERMES — SQUELETTES CACHES =================
             G5 (ColonnesDesTableauxPwaTest, 01/09/2026) exige chaque colonne du
             maitre dans le HTML du premier GET, onglets fermes compris. Comme le
             maitre, le panneau ferme reste donc dans le document, masque par
             la classe hidden ; t-structure.js l'ecarte de la comparaison
             (panneau d'onglet ferme : hidden + data-panneau). Chaque squelette
             partage ses entetes avec le tableau vivant (une seule liste, dans
             le tableau des colonnes en tete de fichier) : deux listes auraient
             fini par diverger sans que la garde le voie.

             L'onglet « Suivi des dettes » n'a PAS de squelette, et c'est une
             decision datee du 01/09/2026 : ses entetes (les tranches
             d'anciennete et « Total du ») sont construits par concatenation
             dans le maitre (m3-clients-creances.js l.194) depuis
             assets/js/creances-engine.js, hors du corpus que G5 sait lire.
             La garde n'exige donc aucune colonne pour ce tableau, et les
             rendre au premier GET serait signale « colonne inventee ».
             L'onglet actif, lui, les rend reellement. --}}
        @if ($onglet !== 'clients')
          <div class="hidden" data-panneau-crm="clients">
            <div class="bg-white rounded-xl border border-slate-200 overflow-hidden mb-2">
              <div class="overflow-x-auto">
                <table class="w-full text-[13px]">
                  {!! $thead('clients') !!}
                  <tbody>{!! $ligneVide('clients', __('pwa.clients.vide')) !!}</tbody>
                </table>
              </div>
            </div>
          </div>
        @endif
        @if ($onglet !== 'relances')
          <div class="hidden" data-panneau-crm="relances">
            <div class="bg-white rounded-xl border border-slate-200 overflow-hidden mb-6">
              <div class="overflow-x-auto">
                <table class="w-full text-[13px]">
                  {!! $thead('a_relancer') !!}
                  <tbody>{!! $ligneVide('a_relancer', __('pwa.clients.relances_a_relancer_vide')) !!}</tbody>
                </table>
              </div>
            </div>
            <div class="bg-white rounded-xl border border-slate-200 overflow-hidden">
              <div class="overflow-x-auto">
                <table class="w-full text-[13px]">
                  {!! $thead('historique_relances') !!}
                  <tbody>{!! $ligneVide('historique_relances', __('pwa.clients.relances_historique_vide')) !!}</tbody>
                </table>
              </div>
            </div>
          </div>
        @endif
        @if ($onglet !== 'avances')
          <div class="hidden" data-panneau-crm="avances">
            <div class="bg-white rounded-xl border border-slate-200 overflow-hidden mb-6">
              <div class="overflow-x-auto">
                <table class="w-full text-[13px]">
                  {!! $thead('avances') !!}
                  <tbody>{!! $ligneVide('avances', __('pwa.clients.avances_vide')) !!}</tbody>
                </table>
              </div>
            </div>
            <div class="bg-white rounded-xl border border-slate-200 overflow-hidden">
              <div class="overflow-x-auto">
                <table class="w-full text-[13px]">
                  {!! $thead('recouvrements') !!}
                  <tbody>{!! $ligneVide('recouvrements', __('pwa.clients.recouvrements_vide')) !!}</tbody>
                </table>
              </div>
            </div>
          </div>
        @endif

        </div>

      </div>
    </main>
  </div>

  {{-- ============================ MODALE « NOUVEAU CLIENT » ============================ --}}
  @if ($etatFormulaire === 'client')
    <x-pwa.modale :titre="__('pwa.clients.modale_client_titre')" largeur="560px">
      <div>
        <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('pwa.clients.champ_nom') }} <span class="text-red-500">*</span></label>
        <input type="text" wire:model="clientNom" autocomplete="off"
               class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5" placeholder="{{ __('pwa.clients.champ_nom_exemple') }}">
        @error('clientNom')<p class="text-[12px] mt-1" style="color:var(--erreur)">{{ $message }}</p>@enderror
      </div>
      <div class="grid grid-cols-2 gap-3">
        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('pwa.clients.champ_telephone') }} <span class="text-red-500">*</span></label>
          <input type="tel" wire:model="clientTelephone" autocomplete="off" placeholder="{{ __('pwa.clients.champ_telephone_exemple') }}"
                 class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          @error('clientTelephone')<p class="text-[12px] mt-1" style="color:var(--erreur)">{{ $message }}</p>@enderror
        </div>
        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('pwa.clients.champ_type') }}</label>
          <select wire:model="clientType" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
            @foreach (ClientsCreances::TYPES_CLIENT as $cle => $libelle)
              <option value="{{ $cle }}">{{ $libelle }}</option>
            @endforeach
          </select>
        </div>
      </div>
      {{-- Le champ « Ville » du maître n'est pas rendu : `clients` ne porte
           aucune colonne de ville (voir le docblock du composant). --}}
      <x-slot:pied>
        <button type="button" wire:click="$set('etatFormulaire', null)" class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="enregistrerClient" class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold hover:opacity-90">{{ __('pwa.clients.champ_creer') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  {{-- ============================ MODALE « AJOUTER UN RECOUVREMENT » ============================ --}}
  @if ($etatFormulaire === 'recouvrement')
    <x-pwa.modale :titre="__('pwa.clients.modale_recouvrement_titre')" largeur="560px">
      <div class="bg-slate-50 border border-slate-200 rounded-lg p-3">
        <div class="text-[11px] uppercase tracking-wide text-slate-400 font-semibold">{{ __('pwa.clients.col_client') }}</div>
        <div class="text-[15px] font-bold" style="color:var(--navy)">{{ $recouvrementClientNom }}</div>
      </div>

      <div>
        <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('pwa.clients.champ_piece_reglee') }} <span class="text-red-500">*</span></label>
        <select wire:model.live="recouvrementFactureId" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          @foreach ($recouvrementFactures as $facture)
            <option value="{{ $facture['id'] }}">{{ $facture['libelle'] }} — {{ __('pwa.clients.champ_du') }} {{ MontantFcfa::format($facture['reste']) }}</option>
          @endforeach
        </select>
      </div>

      <div class="grid grid-cols-2 gap-3">
        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('pwa.clients.champ_montant_recu') }} <span class="text-red-500">*</span></label>
          <input type="number" min="1" step="1" wire:model="recouvrementMontant"
                 class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          @error('recouvrementMontant')<p class="text-[12px] mt-1" style="color:var(--erreur)">{{ $message }}</p>@enderror
        </div>
        <div>
          <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('pwa.clients.champ_mode') }} <span class="text-red-500">*</span></label>
          <select wire:model="recouvrementMode" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
            @foreach (\App\Domain\Facturation\Services\EncaissementFactureService::TRESORERIE_PAR_MODE as $cle => $tresorerie)
              <option value="{{ $cle }}">{{ $libelleMode($cle) }}</option>
            @endforeach
          </select>
        </div>
      </div>

      <div>
        <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('pwa.clients.champ_reference') }}</label>
        <input type="text" wire:model="recouvrementReference" placeholder="{{ __('pwa.clients.champ_reference_exemple') }}"
               class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5 placeholder:text-slate-400">
      </div>

      <div>
        <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('pwa.clients.champ_commentaire') }}</label>
        <textarea wire:model="recouvrementCommentaire" rows="2" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5"></textarea>
      </div>

      <p class="text-[11px] text-slate-500 bg-amber-50 border border-amber-200 rounded-lg p-2.5">{{ __('pwa.clients.recouvrement_avertissement') }}</p>

      <x-slot:pied>
        <button type="button" wire:click="$set('etatFormulaire', null)" class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="enregistrerRecouvrement" class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold hover:opacity-90">{{ __('pwa.clients.champ_enregistrer_recouvrement') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  {{-- ============================ MODALE « TRACER UNE RELANCE » ============================ --}}
  @if ($etatFormulaire === 'relance')
    <x-pwa.modale :titre="__('pwa.clients.modale_relance_titre')" largeur="520px">
      <div class="bg-slate-50 border border-slate-200 rounded-lg p-3">
        <div class="text-[15px] font-bold" style="color:var(--navy)">{{ $relanceClientNom }}</div>
      </div>
      <div>
        <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('pwa.clients.champ_canal') }} <span class="text-red-500">*</span></label>
        <select wire:model="relanceCanal" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
          @foreach (\App\Domain\Crm\Models\RelanceClient::CANAUX as $canal)
            <option value="{{ $canal }}">{{ $libelleCanal($canal) }}</option>
          @endforeach
        </select>
      </div>
      <div>
        <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('pwa.clients.champ_montant_reclame') }}</label>
        <input type="number" min="0" step="1" wire:model="relanceMontant" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
        @error('relanceMontant')<p class="text-[12px] mt-1" style="color:var(--erreur)">{{ $message }}</p>@enderror
      </div>
      <div>
        <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('pwa.clients.champ_promesse') }}</label>
        <input type="date" wire:model="relancePromesse" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5">
      </div>
      <div>
        <label class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('pwa.clients.champ_compte_rendu') }}</label>
        <textarea wire:model="relanceCommentaire" rows="3" placeholder="{{ __('pwa.clients.champ_compte_rendu_exemple') }}" class="w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5"></textarea>
      </div>
      <p class="text-[11px] text-slate-500 bg-slate-100 border border-slate-200 rounded-lg p-2.5">{{ __('pwa.clients.relance_avertissement') }}</p>

      <x-slot:pied>
        <button type="button" wire:click="$set('etatFormulaire', null)" class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="enregistrerRelance" class="text-[13px] px-4 py-2 rounded-lg bg-[var(--gold)] text-white font-semibold hover:opacity-90">{{ __('pwa.clients.champ_enregistrer_relance') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  {{-- ============================ MODALE « HISTORIQUE D'UN CLIENT » ============================ --}}
  @if ($etatFormulaire === 'historique' && $clientHistorique !== null)
    <x-pwa.modale :titre="$clientHistorique->nomComplet()" largeur="720px">
        {{-- Les cinq colonnes de l'etat PDF du maitre (m3-clients-creances.js
             l.597) — la promotion de la colonne du detail est motivee dans le
             tableau des colonnes en tete de fichier. Libelle : le numero de la
             piece reglee pour un encaissement (le maitre affiche le numero du
             recouvrement, que le schema ne porte pas — le numero MECeF est la
             donnee reelle la plus proche), « Relance » pour une relance
             (maitre, l.360). Detail : le mode pour un encaissement, le canal
             pour une relance — les memes registres que l'onglet 4. --}}
        <table class="w-full text-[13px]">
          {!! $thead('historique_client') !!}
          <tbody>
            @if ($historique['relances']->isEmpty() && $historique['paiements']->isEmpty())
              {!! $ligneVide('historique_client', __('pwa.clients.historique_vide')) !!}
            @endif
            @foreach ($historique['paiements'] as $paiement)
              <tr class="border-t border-slate-100" wire:key="hist-paiement-{{ $paiement->id }}">
                <td class="px-3 py-2 text-slate-600 whitespace-nowrap">{{ $paiement->date_paiement?->format('d/m/Y') }}</td>
                <td class="px-3 py-2"><span class="text-[10px] px-1.5 py-0.5 rounded bg-emerald-50 text-emerald-700">{{ __('pwa.clients.historique_type_encaissement') }}</span></td>
                <td class="px-3 py-2 text-slate-700">{{ $paiement->facture?->numero_mecef ?? MontantFcfa::TIRET }}</td>
                <td class="px-3 py-2 text-slate-600">{{ $libelleMode($paiement->mode_paiement) }}</td>
                <td class="px-3 py-2 text-right font-semibold text-emerald-600">{{ MontantFcfa::format($paiement->montant) }}</td>
              </tr>
            @endforeach
            @foreach ($historique['relances'] as $relance)
              <tr class="border-t border-slate-100" wire:key="hist-relance-{{ $relance->id }}">
                <td class="px-3 py-2 text-slate-600 whitespace-nowrap">{{ $relance->date_relance?->format('d/m/Y') }}</td>
                <td class="px-3 py-2"><span class="text-[10px] px-1.5 py-0.5 rounded bg-amber-50 text-amber-700">{{ __('pwa.clients.historique_type_relance') }}</span></td>
                <td class="px-3 py-2 text-slate-700">{{ __('pwa.clients.historique_type_relance') }}</td>
                <td class="px-3 py-2 text-slate-600">{{ $libelleCanal($relance->canal) }}</td>
                <td class="px-3 py-2 text-right font-semibold text-slate-700">{{ MontantFcfa::format($relance->montant_reclame) }}</td>
              </tr>
            @endforeach
          </tbody>
        </table>
      <x-slot:pied>
        <button type="button" wire:click="imprimerReleveClient" class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.clients.historique_imprimer_pdf') }}</button>
        <button type="button" wire:click="$set('etatFormulaire', null)" class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold">{{ __('pwa.modale.fermer') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  {{-- Squelette de la modale « Historique d'un client » quand elle est
       FERMEE : c'est une modale de LECTURE — aucun champ de saisie, la
       doctrine RefuseLaSaisie ne s'applique pas — et ses colonnes font
       partie du contrat G5 au premier GET (groupes « thead #1 » et
       « entetes #2 » du maitre). Masque par la classe hidden et ecarte par
       t-structure.js (data-panneau), comme les panneaux d'onglet fermes.
       Les entetes sont ceux du tableau vivant ci-dessus : une seule liste
       (voir le tableau des colonnes en tete de fichier). --}}
  @if ($etatFormulaire !== 'historique' || $clientHistorique === null)
    <div class="hidden" data-panneau-crm="historique-client">
      <table class="w-full text-[13px]">
        {!! $thead('historique_client') !!}
        <tbody>{!! $ligneVide('historique_client', __('pwa.clients.historique_vide')) !!}</tbody>
      </table>
    </div>
  @endif

  {{-- La modale d'export est PARTAGÉE (dérogation PO, voir le bouton
       « Exporter » ci-dessus). Le titre NOMME ce qui sera exporté, le
       sous-titre DIT le filtre appliqué (PA-119). --}}
  {{-- ============ ARCHIVAGE — « Confirmer la suppression » du maitre
       (crud-ui.js l.123-140), servi par le chassis partage. --}}
  @if ($etatFormulaire === 'archivage')
    <x-pwa.modale-archivage action="archiverClients"
                            :element="$libelleArchivage !== '' ? $libelleArchivage : null"
                            :nombre="$libelleArchivage === '' ? count($clientsAArchiver) : null"
                            :messagesVerrou="$verrousArchivage"
                            :bloque="$archivageBloque"
                            :conserves="$conservesArchivage" />
  @endif

  {{-- Le refus d'archivage est rendu HORS de la modale, et c'est le correctif
       d'un defaut reel trouve a la relecture du 03/09/2026 : le geste ferme la
       modale (`etatFormulaire = null`) avant de rendre, si bien qu'un toast
       pose a l'interieur du `@if` n'apparaissait JAMAIS. Le refus du Service —
       celui qui tombe quand un engagement est ne entre l'ouverture et le clic
       — serait reste silencieux, et l'ecran aurait eu l'air d'avoir archive. --}}
  @error('archivage')
    <div class="fixed bottom-5 right-5 z-50 px-4 py-3 rounded-xl bg-red-600 text-white text-[13px] no-print">{{ $message }}</div>
  @enderror

  @if ($etatFormulaire === 'export')
    @include('pwa.partials.modale-export', [
      'titre' => __('pwa.clients.export_titre'),
      'sousTitre' => __('pwa.clients.export_sous_titre', ['filtre' => $filtreExport]),
    ])
  @endif

</div>
