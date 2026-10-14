{{--
    FOURNISSEURS & ACHATS (M7)
    Maître : prototype_v2/pages/m7-achats.html
    Moteur du tableau : prototype_v2/assets/js/crud-ui.js (barre d'outils l.16-46,
    tableau l.48-83, modale de détail l.107-121, état vide l.75-79,
    pagination — prototype_v2/assets/js/crud-engine.js l.250-262).

    ⚠ DÉROGATION DU 31/08/2026 RENVERSÉE LE 01/09/2026 (décision du Product
    Owner) : l'entête `slate-50` que la PWA gardait sur ses quarante-deux
    écrans est ABANDONNÉE — l'entête de tableau est désormais NAVY partout
    (`<thead class="bg-[var(--navy)]">`, crud-ui.js l.61) avec un texte blanc,
    comme le maître. Voir `App\Pwa\Support\DerogationsMaquette` — la
    dérogation y est marquée renversée, pas supprimée.

    ⚠ La casse des entêtes est celle du MAÎTRE (`Fournisseur`, pas
    `FOURNISSEUR`) : `uppercase` est une règle CSS, elle ne s'applique ni dans
    un CSV ni dans un PDF généré côté serveur, et la majuscule en dur
    ressortirait telle quelle sur le document remis au comptable.
--}}
@php
    use App\Pwa\Livewire\Achats\Achats;
    use App\Pwa\Support\MontantFcfa;

    // Classes d'onglets : directive PO du 01/09/2026, UN SEUL AUTEUR —
    // voir le docblock de `App\Pwa\Support\Onglets`.
    $classeOnglet = static fn (bool $actif): string => \App\Pwa\Support\Onglets::classes($actif);

    /** Entête de colonne — casse du maître, `uppercase` laissé au CSS. */
    $entete = static fn (string $libelle, string $align = 'left'): string
        => '<th class="px-4 py-2.5 text-' . $align
        . ' text-[11px] font-semibold uppercase tracking-wide text-white/90">' . e($libelle) . '</th>';

    /** Pastille de badge — mêmes dimensions que le maître (crud-engine.js l.219). */
    $badge = 'px-2 py-0.5 rounded text-[11px] font-semibold';
@endphp

<div class="contents">

  @include('pwa.partials.barre-superieure')

  <div class="flex flex-1 overflow-hidden">
    @include('pwa.partials.menu-lateral')

    <main class="flex-1 overflow-y-auto">
      <div class="max-w-[1440px] mx-auto p-5 lg:p-8">

        {{-- En-tête institutionnel d'IMPRESSION.
             ⚠ `<h2>`, jamais `<h1>` : le papier garde le nom de
             l'établissement, l'écran garde UN SEUL titre — celui du maître. --}}
        <div class="hidden print:block mb-6 border-b-2 border-[var(--navy)] pb-4">
          <h2 class="text-xl font-bold" style="color:var(--navy)">{{ __('pwa.marque') }} — {{ __('pwa.enseigne_courte') }}</h2>
          <p class="text-xs text-slate-600 mt-1">{{ __('pwa.achats.titre') }} — {{ now()->format('d/m/Y H:i') }}</p>
        </div>

        {{--
            ============================ EN-TÊTE (maître l.23-33) ============================
            ⚠ « Exporter » et « + Ajouter » vivaient ICI jusqu'au 01/09/2026 :
            le maître les pose dans la BARRE D'OUTILS du moteur CRUD
            (`crud-ui.js` `toolbarHtml()`, l.16-38), à droite de la recherche —
            jamais dans l'en-tête de page. Déplacés ci-dessous, avec
            « Actualiser » et le refus nommé d'« Importer ».
        --}}
        <div class="mb-5">
          <div class="flex flex-wrap items-start justify-between gap-3">
            <div>
              <div class="flex items-center gap-2.5">
                <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--navy)" stroke-width="2"><circle cx="9" cy="21" r="1"/><circle cx="20" cy="21" r="1"/><path stroke-linecap="round" stroke-linejoin="round" d="M1 1h4l2.68 13.39a2 2 0 002 1.61h9.72a2 2 0 002-1.61L23 6H6"/></svg>
                <h1 class="text-lg lg:text-xl font-bold" style="color:var(--navy)">{{ __('pwa.achats.titre') }}</h1>
              </div>
              <p class="text-[15px] text-slate-500 mt-1.5">{{ __('pwa.achats.sous_titre') }}</p>
            </div>
          </div>

          {{-- Les DEUX onglets du maître (l.31-32). --}}
          <div class="flex gap-2 mt-4 no-print">
            <button type="button" wire:click="$set('onglet', 'fournisseurs')"
                    class="{{ $classeOnglet($onglet === 'fournisseurs') }}">{{ __('pwa.achats.onglet_fournisseurs') }}</button>
            <button type="button" wire:click="$set('onglet', 'commandes')"
                    class="{{ $classeOnglet($onglet === 'commandes') }}">{{ __('pwa.achats.onglet_commandes') }}</button>
          </div>
        </div>

        @if (session('pwa-succes'))
          <div class="mb-4 rounded-xl px-4 py-3 text-[13px] font-semibold no-print"
               style="background:#E8F5E9;color:#2E7D32;border:1px solid #C8E6C9">{{ session('pwa-succes') }}</div>
        @endif

        {{-- ============================ BARRE D'OUTILS (crud-ui.js l.16-27) --}}
        <div class="flex flex-col lg:flex-row lg:items-center gap-3 mb-4 no-print">
          <div class="relative flex-1">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#9CA3AF" stroke-width="2" class="absolute left-3.5 top-1/2 -translate-y-1/2"><circle cx="11" cy="11" r="8"/><path stroke-linecap="round" d="M21 21l-4.35-4.35"/></svg>
            <input type="text" wire:model.live.debounce.300ms="recherche"
                   placeholder="{{ $onglet === 'fournisseurs' ? __('pwa.achats.recherche_fournisseur') : __('pwa.achats.recherche_commande') }}"
                   class="champ w-full border border-slate-200 rounded-lg pl-10 pr-4 py-2.5 text-sm bg-white">
          </div>
          <div class="flex flex-wrap gap-2">
            @if ($onglet === 'fournisseurs')
              <select wire:model.live="evaluation" class="champ border border-slate-200 rounded-lg px-3 py-2.5 text-sm bg-white">
                <option value="">{{ __('pwa.achats.toutes_evaluations') }}</option>
                @foreach (Achats::EVALUATIONS as $cle => $style)
                  <option value="{{ $cle }}">{{ $style['libelle'] }}</option>
                @endforeach
              </select>
            @else
              <select wire:model.live="statut" class="champ border border-slate-200 rounded-lg px-3 py-2.5 text-sm bg-white">
                <option value="">{{ __('pwa.achats.tous_statuts') }}</option>
                @foreach (Achats::STATUTS as $cle => $style)
                  <option value="{{ $cle }}">{{ $style['libelle'] }}</option>
                @endforeach
              </select>
            @endif
          </div>

          {{--
              LE GROUPE D'ACTIONS — `crud-ui.js` l.24-37 : Actualiser /
              Importer / Exporter / « + Nouveau », à droite de la recherche
              (01/09/2026). Chaque onglet reconstruit ce groupe (le maître
              rappelle `rendreMiseEnPageCrud()` au changement d'onglet,
              l.300) : le libellé du bouton de création suit `$onglet`.
          --}}
          <div class="flex items-center gap-2 shrink-0">
            <button type="button" wire:click="$refresh"
                    class="btn p-2.5 rounded-lg border border-slate-200 bg-white text-slate-500" title="{{ __('achats_pwa.achats.actualiser') }}">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M23 4v6h-6M1 20v-6h6"/><path stroke-linecap="round" stroke-linejoin="round" d="M3.51 9a9 9 0 0114.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0020.49 15"/></svg>
            </button>

            {{--
                Importer : REFUSÉ, non inerte (Article 3.3). Ni les
                fournisseurs ni les commandes d'achat n'ont de moteur
                d'import (contrairement à `Stocks::lancerImport()`) : en
                inventer un serait une écriture de service hors périmètre.
                Jeton : maitre-refuse:m7-achats.html#crud-bouton-importer
            --}}

            <button type="button" wire:click="$set('etatFormulaire', 'export')"
                    class="flex items-center gap-2 px-3.5 py-2.5 rounded-lg border border-slate-200 bg-white text-slate-600 text-xs font-semibold">
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4M7 10l5 5 5-5M12 15V3"/></svg>
              {{ __('achats_pwa.achats.exporter') }}
            </button>

            {{-- 1er niveau du RBAC : le bouton n'apparaît que pour un rôle
                 qui pourra effectivement soumettre. Il ne protège rien — la
                 garde serveur est dans `ouvrirFormulaireFournisseur()` — mais
                 son absence évite de proposer un geste qui sera refusé. --}}
            @if ($peutEcrire)
              @if ($onglet === 'fournisseurs')
                <button type="button" wire:click="ouvrirFormulaireFournisseur"
                        class="flex items-center gap-2 px-4 py-2.5 rounded-lg bg-[var(--navy)] text-white text-xs font-semibold">
                  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path stroke-linecap="round" d="M12 5v14M5 12h14"/></svg>
                  <span>{{ __('achats_pwa.achats.ajouter') }}</span>
                </button>
              @else
                {{--
                    « + Ajouter commande d'achat » — même geste que
                    « Nouvelle réservation » en M1 (hebergement.blade.php) :
                    un lien vers l'écran qui PORTE réellement la création.
                    `commandes_achat` n'a aucune colonne de montant qu'un
                    chemin de ce dépôt écrive (voir le docblock de
                    `Achats`) — une commande se crée là où ses lignes
                    existent, dans Approvisionnement, jamais ici.
                --}}
                <a href="{{ route('pwa.achats.approvisionnement') }}" wire:navigate
                   class="flex items-center gap-2 px-4 py-2.5 rounded-lg bg-[var(--navy)] text-white text-xs font-semibold">
                  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><path stroke-linecap="round" d="M12 5v14M5 12h14"/></svg>
                  <span>{{ __('achats_pwa.achats.ajouter_commande') }}</span>
                </a>
              @endif
            @endif
          </div>
        </div>

        {{-- Barre de sélection groupée du maître (crud-ui.js l.36-46).
             « Supprimer » Y EST RENDU depuis le 03/09/2026 (demande du Product
             Owner : « la suppression en bulk » pour administrateur et
             super_admin). Il ARCHIVE — `ReferentielFournisseurService` pose
             `actif = false` : aucun `delete()` n'existe dans ce dépôt. Le
             bouton n'apparaît QUE pour qui peut archiver (Article 3.3 :
             retiré, pas grisé). --}}
        @if ($selection !== [])
          <div class="flex items-center gap-3 bg-[var(--navy)] text-white rounded-lg px-4 py-2.5 mb-3 text-xs no-print">
            <span>{!! __('achats_pwa.tableau.selectionnes', ['nombre' => '<strong>' . count($selection) . '</strong>']) !!}</span>
            <div class="flex-1"></div>
            @if ($onglet === 'fournisseurs' && $peutArchiver)
              <button type="button" wire:click="confirmerArchivageFournisseur"
                      class="underline decoration-white/40 hover:decoration-white">{{ __('achats_pwa.archivage.bouton_lot') }}</button>
            @endif
            <button type="button" wire:click="$set('etatFormulaire', 'export')"
                    class="underline decoration-white/40 hover:decoration-white">{{ __('achats_pwa.achats.exporter') }}</button>
            <button type="button" wire:click="$set('selection', [])" class="text-white/60 hover:text-white"
                    aria-label="{{ __('pwa.modale.annuler') }}">✕</button>
          </div>
        @endif

        {{-- ============================ ONGLET FOURNISSEURS --}}
        <section class="{{ $onglet === 'fournisseurs' ? '' : 'hidden' }}">
          <div class="bg-white rounded-xl border border-slate-200 overflow-hidden">
            <div class="overflow-x-auto">
              <table class="w-full text-[13px]">
                <thead class="bg-[var(--navy)]">
                  <tr>
                    <th class="px-4 py-2.5 w-10">
                      <input type="checkbox" wire:model.live="toutSelectionne" class="w-4 h-4 rounded"
                             aria-label="{{ __('achats_pwa.tableau.selection_tout') }}">
                    </th>
                    {!! $entete(__('pwa.achats.col_fournisseur')) !!}
                    {!! $entete(__('pwa.achats.col_contact')) !!}
                    {!! $entete(__('pwa.achats.col_categorie')) !!}
                    {!! $entete(__('pwa.achats.col_conditions')) !!}
                    {!! $entete(__('pwa.achats.col_evaluation')) !!}
                    {!! $entete(__('pwa.achats.col_actions'), 'right') !!}
                  </tr>
                </thead>
                <tbody>
                  @foreach ($fournisseurs as $f)
                    <tr wire:key="fournisseur-{{ $f->id }}" class="border-t border-slate-100 hover:bg-slate-50">
                      <td class="px-4 py-2.5">
                        <input type="checkbox" value="{{ $f->id }}" wire:model.live="selection" class="w-4 h-4 rounded"
                               aria-label="{{ __('achats_pwa.tableau.selection_ligne') }}">
                      </td>
                      <td class="px-4 py-2.5 font-medium text-slate-800">
                        {{ $f->raison_sociale }}
                        {{-- Un fournisseur ARCHIVÉ reste dans la liste, marqué.
                             Le masquer le rendrait indiscernable d'une fiche
                             inexistante — et « reste restaurable » ne serait
                             une promesse tenue nulle part (PA-59/60/61). --}}
                        @unless ($f->actif)
                          <span class="{{ $badge }} ml-1"
                                style="background:#F3F4F6;color:#6B7280">{{ __('achats_pwa.archivage.badge') }}</span>
                        @endunless
                      </td>
                      {{-- Article 7 : « — » quand la donnée n'existe pas. Une
                           case vide se lirait comme une donnée non chargée. --}}
                      <td class="px-4 py-2.5 text-slate-600">{{ $f->contact ?? MontantFcfa::TIRET }}</td>
                      <td class="px-4 py-2.5 text-slate-600">{{ $f->categorie ?? MontantFcfa::TIRET }}</td>
                      <td class="px-4 py-2.5 text-slate-600">{{ $f->conditions_paiement ?? MontantFcfa::TIRET }}</td>
                      <td class="px-4 py-2.5">
                        @php $style = Achats::EVALUATIONS[$f->evaluation] ?? null; @endphp
                        @if ($style === null)
                          {{ MontantFcfa::TIRET }}
                        @else
                          <span class="{{ $badge }}"
                                style="background:{{ $style['fond'] }};color:{{ $style['texte'] }}">{{ $style['libelle'] }}</span>
                        @endif
                      </td>
                      <td class="px-4 py-2.5 text-right whitespace-nowrap no-print">
                        <button type="button" wire:click="$set('detailId', '{{ $f->id }}')"
                                class="text-[12px] px-2.5 py-1 rounded-lg border border-slate-200 hover:bg-slate-100">{{ __('achats_pwa.achats.detail_voir') }}</button>
                        @if ($peutEcrire)
                          <button type="button" wire:click="ouvrirFormulaireFournisseur('{{ $f->id }}')"
                                  class="text-[12px] px-2.5 py-1 rounded-lg border border-slate-200 hover:bg-slate-100 ml-1">{{ __('achats_pwa.achats.detail_modifier') }}</button>
                        @endif
                        {{-- « Supprimer » du maître (crud-ui.js l.100), rendu
                             ici comme ARCHIVAGE : le mot du bouton est celui
                             que le client a validé, le geste pose `actif =
                             false`. Restaurer n'est PAS derrière la même garde
                             — voir `Achats::restaurerFournisseur()`. --}}
                        @unless ($f->actif)
                          @if ($peutEcrire)
                            <button type="button" wire:click="restaurerFournisseur('{{ $f->id }}')"
                                    class="text-[12px] px-2.5 py-1 rounded-lg border border-slate-200 hover:bg-slate-100 ml-1">{{ __('achats_pwa.archivage.bouton_restaurer') }}</button>
                          @endif
                        @else
                          @if ($peutArchiver)
                            <button type="button" wire:click="confirmerArchivageFournisseur('{{ $f->id }}')"
                                    class="text-[12px] px-2.5 py-1 rounded-lg border border-red-200 text-[var(--erreur)] hover:bg-red-50 ml-1">{{ __('achats_pwa.archivage.bouton_ligne') }}</button>
                          @endif
                        @endunless
                      </td>
                    </tr>
                  @endforeach
                </tbody>
              </table>

              {{-- État vide du maître (crud-ui.js l.75-79). Toujours dans le
                   DOM, masqué quand des lignes existent — comme le maître. --}}
              <div class="{{ $fournisseurs->total() === 0 ? 'flex' : 'hidden' }} flex-col items-center justify-center py-16 text-center">
                <svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="#CBD5E1" stroke-width="1.5" class="mb-3"><path stroke-linecap="round" stroke-linejoin="round" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"/></svg>
                <p class="text-sm font-semibold text-slate-500">{{ __('pwa.achats.vide_titre') }}</p>
                <p class="text-xs text-slate-400 mt-1">{{ __('pwa.achats.vide_detail') }}</p>
              </div>
            </div>

            <div class="flex items-center justify-between px-4 py-3 border-t border-slate-100 no-print">
              <p class="text-xs text-slate-500">{!! __('achats_pwa.tableau.affichage', [
                  'debut' => '<strong>' . ($fournisseurs->total() === 0 ? 0 : $fournisseurs->firstItem()) . '</strong>',
                  'fin' => '<strong>' . ($fournisseurs->lastItem() ?? 0) . '</strong>',
                  'total' => '<strong>' . $fournisseurs->total() . '</strong>',
              ]) !!}</p>
              {{ $fournisseurs->onEachSide(1)->links() }}
            </div>
          </div>
        </section>

        {{-- ============================ ONGLET COMMANDES D'ACHAT --}}
        <section class="{{ $onglet === 'commandes' ? '' : 'hidden' }}">
          <div class="bg-white rounded-xl border border-slate-200 overflow-hidden">
            <div class="overflow-x-auto">
              <table class="w-full text-[13px]">
                <thead class="bg-[var(--navy)]">
                  <tr>
                    <th class="px-4 py-2.5 w-10">
                      <input type="checkbox" wire:model.live="toutSelectionne" class="w-4 h-4 rounded"
                             aria-label="{{ __('achats_pwa.tableau.selection_tout') }}">
                    </th>
                    {!! $entete(__('pwa.achats.col_fournisseur')) !!}
                    {!! $entete(__('pwa.achats.col_date_commande')) !!}
                    {!! $entete(__('pwa.achats.col_montant_estime'), 'right') !!}
                    {!! $entete(__('pwa.achats.col_statut')) !!}
                    {{-- maître — `crud-ui.js` l.70 : la colonne Actions clôt TOUJOURS le tableau. --}}
                    {!! $entete(__('pwa.achats.col_actions'), 'right') !!}
                  </tr>
                </thead>
                <tbody>
                  @foreach ($commandes as $c)
                    <tr wire:key="commande-{{ $c->id }}" class="border-t border-slate-100 hover:bg-slate-50">
                      <td class="px-4 py-2.5">
                        <input type="checkbox" value="{{ $c->id }}" wire:model.live="selection" class="w-4 h-4 rounded"
                               aria-label="{{ __('achats_pwa.tableau.selection_ligne') }}">
                      </td>
                      <td class="px-4 py-2.5 font-medium text-slate-800">{{ $c->fournisseur?->raison_sociale ?? MontantFcfa::TIRET }}</td>
                      <td class="px-4 py-2.5 text-slate-600">{{ $c->date_commande?->format('d/m/Y') ?? MontantFcfa::TIRET }}</td>
                      {{-- CALCULÉ depuis les lignes (`bcadd`), jamais lu dans
                           une colonne : `commandes_achat.montant_total` existe
                           depuis le 28/08/2026 mais AUCUN chemin de ce dépôt
                           ne l'écrit — elle vaut zéro pour toutes les
                           commandes. --}}
                      <td class="px-4 py-2.5 text-right font-semibold">{{ MontantFcfa::format($c->montantTotal()) }}</td>
                      <td class="px-4 py-2.5">
                        @php $st = Achats::STATUTS[$c->statut] ?? null; @endphp
                        @if ($st === null)
                          {{ MontantFcfa::TIRET }}
                        @else
                          <span class="{{ $badge }}"
                                style="background:{{ $st['fond'] }};color:{{ $st['texte'] }}">{{ $st['libelle'] }}</span>
                        @endif
                      </td>
                      {{--
                          « Voir le détail » — maître, `crud-engine.js` l.234.
                          Seule action honnête ici : le cycle complet d'une
                          commande (réception, règlement) vit dans
                          Approvisionnement (voir le docblock de `Achats`),
                          jamais dans cette liste de consultation.
                      --}}
                      <td class="px-4 py-2.5 text-right whitespace-nowrap no-print">
                        <a href="{{ route('pwa.achats.approvisionnement') }}" wire:navigate
                           class="text-[12px] px-2.5 py-1 rounded-lg border border-slate-200 hover:bg-slate-100 inline-block"
                           title="{{ __('achats_pwa.achats.detail_voir') }}">{{ __('achats_pwa.achats.detail_voir') }}</a>
                      </td>
                    </tr>
                  @endforeach
                </tbody>
              </table>

              <div class="{{ $commandes->total() === 0 ? 'flex' : 'hidden' }} flex-col items-center justify-center py-16 text-center">
                <svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="#CBD5E1" stroke-width="1.5" class="mb-3"><path stroke-linecap="round" stroke-linejoin="round" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"/></svg>
                <p class="text-sm font-semibold text-slate-500">{{ __('pwa.achats.vide_titre') }}</p>
                <p class="text-xs text-slate-400 mt-1">{{ __('pwa.achats.vide_detail') }}</p>
              </div>
            </div>

            <div class="flex items-center justify-between px-4 py-3 border-t border-slate-100 no-print">
              <p class="text-xs text-slate-500">{!! __('achats_pwa.tableau.affichage', [
                  'debut' => '<strong>' . ($commandes->total() === 0 ? 0 : $commandes->firstItem()) . '</strong>',
                  'fin' => '<strong>' . ($commandes->lastItem() ?? 0) . '</strong>',
                  'total' => '<strong>' . $commandes->total() . '</strong>',
              ]) !!}</p>
              {{ $commandes->onEachSide(1)->links() }}
            </div>
          </div>
        </section>

        {{--
            NON PORTE, ET PLUS RENDU A L'ECRAN (02/09/2026). Formulaire de
            commande complet, import de masse et duplication du maitre ne sont
            pas portes. La section « ce que cet ecran ne fait pas » est retiree
            par directive du Product Owner : un ecran dit ce qu'il FAIT.

            ⚠ MISE A JOUR DU 03/09/2026 — une des deux lacunes de schema est
            FERMEE, et cette declaration disait le contraire : la table des
            fournisseurs porte desormais un indicateur d'activite (`actif`,
            migration `2026_09_08_100000_ajouter_archivage_aux_referentiels`),
            et « Supprimer » est rendu, par ligne et en lot, comme ARCHIVAGE.
            Une seule lacune de schema subsiste : l'annulation d'une commande
            d'achat, dont le statut n'admet aucune valeur « annulee ».

            Le jeton `maitre-refuse:m7-achats.html#modale-import` reste declare
            dans `lang/fr/pwa.php` ; celui de `#modale-suppression` a ete
            retire le meme jour — la modale de suppression EST portee.
        --}}

      </div>
    </main>
  </div>

  {{-- ============================ MODALE DE DÉTAIL (crud-ui.js l.107-121) --}}
  @if ($detail !== null)
    <x-pwa.modale :titre="__('achats_pwa.achats.detail_titre', ['element' => $detail->raison_sociale])"
                  largeur="480px" fermer="$set('detailId', null)">
      <dl class="space-y-3">
        @foreach ([
            __('pwa.achats.col_fournisseur') => $detail->raison_sociale,
            __('pwa.achats.col_contact') => $detail->contact,
            __('pwa.achats.col_categorie') => $detail->categorie,
            __('pwa.achats.col_conditions') => $detail->conditions_paiement,
            __('pwa.achats.col_evaluation') => \App\Pwa\Livewire\Achats\Achats::EVALUATIONS[$detail->evaluation]['libelle'] ?? null,
        ] as $libelle => $valeur)
          <div class="flex justify-between gap-4 border-b border-slate-100 pb-2">
            <dt class="text-[12px] font-semibold text-slate-500">{{ $libelle }}</dt>
            <dd class="text-[13px] text-slate-800 text-right">{{ $valeur ?? MontantFcfa::TIRET }}</dd>
          </div>
        @endforeach
      </dl>

      <x-slot:pied>
        <button type="button" wire:click="$set('detailId', null)"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('achats_pwa.achats.detail_fermer') }}</button>
        @if ($peutEcrire)
          <button type="button" wire:click="ouvrirFormulaireFournisseur('{{ $detail->id }}')"
                  class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold hover:opacity-90">{{ __('achats_pwa.achats.detail_modifier') }}</button>
        @endif
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  {{-- ============================ FORMULAIRE FOURNISSEUR (EF-M7-01) --}}
  @if ($etatFormulaire === 'fournisseur')
    <x-pwa.modale :titre="$fId === null ? __('achats_pwa.achats.form_nouveau') : __('achats_pwa.achats.form_edition')"
                  :sousTitre="__('achats_pwa.achats.form_sous_titre')"
                  largeur="560px" fermer="$set('etatFormulaire', null)">
      <div>
        <label for="f-raison" class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('achats_pwa.achats.form_raison_sociale') }}</label>
        <input id="f-raison" type="text" wire:model="fRaisonSociale"
               placeholder="{{ __('achats_pwa.achats.form_raison_sociale_invite') }}"
               class="w-full rounded-lg px-3 py-2.5 text-[13px] border border-slate-300">
        @error('fRaisonSociale')<p class="text-[12px] mt-1" style="color:var(--erreur)">{{ $message }}</p>@enderror
      </div>

      <div>
        <label for="f-contact" class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('achats_pwa.achats.form_contact') }}</label>
        <input id="f-contact" type="tel" wire:model="fContact"
               placeholder="{{ __('achats_pwa.achats.form_contact_invite') }}"
               class="w-full rounded-lg px-3 py-2.5 text-[13px] border border-slate-300">
        @error('fContact')<p class="text-[12px] mt-1" style="color:var(--erreur)">{{ $message }}</p>@enderror
      </div>

      <div>
        <label for="f-categorie" class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('achats_pwa.achats.form_categorie') }}</label>
        <select id="f-categorie" wire:model="fCategorie" class="w-full rounded-lg px-3 py-2.5 text-[13px] border border-slate-300">
          <option value="">{{ __('achats_pwa.achats.form_non_renseigne') }}</option>
          @foreach (Achats::CATEGORIES as $categorie)
            <option value="{{ $categorie }}">{{ $categorie }}</option>
          @endforeach
          {{-- Une catégorie historique hors des cinq du maître reste
               sélectionnable : la fermer rendrait le fournisseur inmodifiable
               à la première correction de son téléphone. --}}
          @if ($fCategorie !== '' && ! in_array($fCategorie, Achats::CATEGORIES, true))
            <option value="{{ $fCategorie }}">{{ $fCategorie }}</option>
          @endif
        </select>
        @error('fCategorie')<p class="text-[12px] mt-1" style="color:var(--erreur)">{{ $message }}</p>@enderror
      </div>

      <div>
        <label for="f-conditions" class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('achats_pwa.achats.form_conditions') }}</label>
        <select id="f-conditions" wire:model="fConditionsPaiement" class="w-full rounded-lg px-3 py-2.5 text-[13px] border border-slate-300">
          <option value="">{{ __('achats_pwa.achats.form_non_renseigne') }}</option>
          @foreach (Achats::CONDITIONS_PAIEMENT as $condition)
            <option value="{{ $condition }}">{{ $condition }}</option>
          @endforeach
          @if ($fConditionsPaiement !== '' && ! in_array($fConditionsPaiement, Achats::CONDITIONS_PAIEMENT, true))
            <option value="{{ $fConditionsPaiement }}">{{ $fConditionsPaiement }}</option>
          @endif
        </select>
        @error('fConditionsPaiement')<p class="text-[12px] mt-1" style="color:var(--erreur)">{{ $message }}</p>@enderror
      </div>

      <div>
        <label for="f-evaluation" class="block text-[13px] font-semibold text-slate-700 mb-1.5">{{ __('achats_pwa.achats.form_evaluation') }}</label>
        <select id="f-evaluation" wire:model="fEvaluation" class="w-full rounded-lg px-3 py-2.5 text-[13px] border border-slate-300">
          {{-- « Non renseigné » n'est PAS « À revoir » : les confondre
               reprocherait à un fournisseur neuf une note que personne ne lui
               a donnée. --}}
          <option value="">{{ __('achats_pwa.achats.form_non_renseigne') }}</option>
          @foreach (Achats::EVALUATIONS as $cle => $style)
            <option value="{{ $cle }}">{{ $style['libelle'] }}</option>
          @endforeach
        </select>
        @error('fEvaluation')<p class="text-[12px] mt-1" style="color:var(--erreur)">{{ $message }}</p>@enderror
      </div>

      <x-slot:pied>
        <button type="button" wire:click="$set('etatFormulaire', null)"
                class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
        <button type="button" wire:click="enregistrerFournisseur"
                class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold hover:opacity-90">{{ __('achats_pwa.achats.form_enregistrer') }}</button>
      </x-slot:pied>
    </x-pwa.modale>
  @endif

  {{-- ============================ ARCHIVAGE — « Confirmer la suppression »
       du maître (crud-ui.js l.123-140), servi par le châssis partagé. Le
       titre et le bouton gardent les mots du maître ; le corps dit ce qui a
       réellement lieu — l'élément part aux archives. --}}
  @if ($etatFormulaire === 'archivage')
    <x-pwa.modale-archivage action="archiverFournisseurs"
                            :element="$libelleArchivage !== '' ? $libelleArchivage : null"
                            :nombre="$libelleArchivage === '' ? count($fournisseursAArchiver) : null"
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

  {{-- ============================ EXPORT — le châssis PARTAGÉ, jamais une copie --}}
  @if ($etatFormulaire === 'export')
    @include('pwa.partials.modale-export', [
        'titre' => $onglet === 'fournisseurs'
            ? __('achats_pwa.export.titre_fournisseurs')
            : __('achats_pwa.export.titre_commandes'),
        'sousTitre' => $descriptionFiltre,
    ])
    @error('formatExport')
      <p class="fixed bottom-5 right-5 z-50 rounded-lg px-4 py-3 text-[13px] font-semibold text-white"
         style="background:var(--erreur)">{{ $message }}</p>
    @enderror
  @endif

</div>
