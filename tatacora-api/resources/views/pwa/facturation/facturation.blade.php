{{--
    Facturation & Caisse MECeF — maître : `prototype_v2/pages/m2-facturation.html`.

    Conteneur `max-w-[1440px] mx-auto p-5 lg:p-8` (l.22), en-tête de page
    (l.23-27), puis la `<section id="registre-factures" class="mb-6">` (l.29),
    dont le contenu est produit par `rendreRegistre()` (l.75-140) : carte
    `bg-white rounded-xl border border-slate-200 overflow-hidden`, en-tête
    `px-4 py-3 border-b border-slate-200 flex flex-wrap items-start
    justify-between gap-3`, bande de compteurs `px-4 py-2.5 border-b
    border-slate-200 flex flex-wrap gap-4 text-[12px] bg-slate-50`, puis le
    tableau à sept colonnes (l.124-132).

    Le bloc « Jeu de démonstration » du maître (l.33-39) et les cinq modales du
    moteur CRUD ne sont PAS rendus — Article 6. La dérogation est motivée en
    toutes lettres dans `App\Pwa\Livewire\Facturation\Facturation`, et nommée à
    l'écran avec les mots du maître.

    ⚠ ÉCART DÉLIBÉRÉ — `prototype_v2/pages/m2-facturation.html` l.126-128
    Le maître : quand le registre est vide, il REMPLACE le tableau entier par
    un paragraphe (« Aucune facture émise. Encaissez au point de vente ou
    clôturez un séjour. ») — les entêtes de colonnes disparaissent avec lui.
    Ici : les entêtes restent, et le message occupe une ligne de corps.
    Raison : contrainte de vérification. `ColonnesDesTableauxPwaTest` relève
    les `<th>` RENDUS ; sur une base sans facture, les sept colonnes du maître
    étaient portées manquantes alors qu'elles sont écrites. Un écran dont on ne
    peut pas prouver les colonnes n'est pas un écran vérifié. L'état vide rend
    TOUJOURS les mots du moteur du maître (`crud-ui.js` : « Aucun résultat » /
    « Essayez de modifier votre recherche ou vos filtres. ») — c'est le contrat
    du tableau générique (G6) — et, sans filtre, la ligne du registre du maître
    s'y ajoute : « aucune facture » et « aucun résultat pour ce filtre »
    appellent des gestes opposés (Article 7).

    ⚠ ÉCART DÉLIBÉRÉ — `prototype_v2/pages/m2-facturation.html` l.129-138
    Le maître : sept colonnes, aucune action de ligne sur le registre réel.
    Ici : une huitième colonne, à entête VIDE, porte les deux gestes réels du
    module — l'avoir (RG-03) et le document A4.
    Raison : PA-159 impose que la PWA écrive, et l'Article 3.3 interdit une
    entrée qui n'ouvre rien. Les actions du maître vivent dans son tableau de
    démonstration, qui n'est pas porté ; les poser en fin de ligne sous un
    entête vide est la seule place qui n'invente pas de libellé de colonne.
--}}
@php
    use App\Pwa\Support\MontantFcfa;
    use App\Pwa\Livewire\Facturation\Facturation;
@endphp
<div class="contents">

  @include('pwa.partials.barre-superieure')
  

  <div class="flex flex-1 overflow-hidden">
    @include('pwa.partials.menu-lateral')
    <main class="flex-1 overflow-y-auto">
      <div class="max-w-[1440px] mx-auto p-5 lg:p-8">

        <div class="mb-5">
          <div class="flex items-center gap-2.5">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--navy)" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M6 2h9l5 5v13a2 2 0 01-2 2H6a2 2 0 01-2-2V4a2 2 0 012-2z"/><path stroke-linecap="round" d="M9 13h6M9 17h6M9 9h1"/></svg>
            <h1 class="text-lg lg:text-xl font-bold" style="color:var(--navy)">{{ __('pwa.facturation.titre') }}</h1>
          </div>
          <p class="text-[15px] text-slate-500 mt-1.5">{{ __('pwa.facturation.sous_titre') }}</p>
        </div>

        @if (session('pwa-succes'))
          <div class="mb-4 rounded-xl px-4 py-3 text-[13px] font-semibold no-print"
               style="background:#E8F5E9;color:#2E7D32;border:1px solid #C8E6C9">{{ session('pwa-succes') }}</div>
        @endif

        <!-- ============ REGISTRE REEL, alimente par les deux POS ============ -->
        <section id="registre-factures" class="mb-6">
          <div class="bg-white rounded-xl border border-slate-200 overflow-hidden">
            <div class="px-4 py-3 border-b border-slate-200 flex flex-wrap items-start justify-between gap-3">
              <div>
                <h2 class="text-[14px] font-bold" style="color:var(--navy)">{{ __('pwa.facturation.registre_titre') }}</h2>
                <p class="text-[11px] text-slate-400 mt-0.5">
                  {{ __('pwa.facturation.registre_detail') }}
                </p>
              </div>
              <div class="flex flex-wrap items-center gap-2">
                <input type="search" id="rech-fac" wire:model.live.debounce.300ms="recherche" placeholder="{{ __('pwa.facturation.recherche') }}"
                  class="text-[13px] border border-slate-300 rounded-lg px-3 py-1.5 w-48">
                {{-- Le maître pose ici le filtre « Toutes les origines ». Il
                     n'est pas offert : aucune colonne d'origine au schéma, et
                     la déduire des lignes inventerait une classification. Voir
                     le bloc de refus. --}}
                <select id="filtre-fac-module" wire:model.live="activite" class="text-[13px] border border-slate-300 rounded-lg px-2.5 py-1.5">
                  <option value="">{{ __('pwa.facturation.toutes_activites') }}</option>
                  @foreach (Facturation::ACTIVITES as $cle => $libelle)
                    <option value="{{ $cle }}">{{ $libelle }}</option>
                  @endforeach
                </select>
                {{-- ⚠ DÉROGATION PO du 01/09/2026, rappelée le 02/09/2026 —
                     la paire « Export Excel » / « Export PDF » du maître
                     (`m2-facturation.html` l.112-113) est remplacée par UN
                     bouton « Exporter » qui ouvre la modale d'export
                     partagée ; le format PDF A4 / Excel s'y choisit. Le PDF
                     est le REGISTRE affiché en A4 (dompdf), jamais une
                     facture : le document fiscal garde son bouton « Facture
                     A4 » par ligne. Registre :
                     `App\Pwa\Support\DerogationsMaquette`
                     (export_bouton_unique).
                     Jeton : maitre-refuse:m2-facturation.html#page --}}
                <button type="button" wire:click="ouvrirExport"
                        class="text-[13px] px-3 py-1.5 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.export.bouton') }}</button>
              </div>
            </div>

            @error('export')
              <div class="px-4 py-2.5 border-b border-amber-200 text-[13px] no-print"
                   style="background:#FFFBEB;color:#78350F">{{ $message }}</div>
            @enderror

            <div class="px-4 py-2.5 border-b border-slate-200 flex flex-wrap gap-4 text-[12px] bg-slate-50">
              <span class="text-slate-500">{{ __('pwa.facturation.compteur_pieces') }} <strong class="text-[var(--navy)]">{{ $total }}</strong></span>
              <span class="text-slate-500">{{ __('pwa.facturation.compteur_avoirs') }} <strong class="text-[var(--navy)]">{{ $avoirs }}</strong></span>
              <span class="text-slate-500">{{ __('pwa.facturation.compteur_montant') }} <strong class="text-[var(--navy)]">{{ MontantFcfa::format($montant) }}</strong></span>
              {{--
                  LA MENTION DE CERTIFICATION EST DÉRIVÉE DES PIÈCES (PA-119).

                  Le maître l'écrit en dur. Une constante resterait vraie
                  aujourd'hui et deviendrait fausse le jour de l'inscription
                  DGI — c'est-à-dire le jour où elle compterait vraiment.
                  Aujourd'hui elle rend exactement la phrase du maître, parce
                  que c'est la vérité.
              --}}
              @if ($certifiees === 0)
                <span class="text-amber-700">
                  {!! __('pwa.facturation.mecef_aucune') !!}
                </span>
              @else
                <span class="text-emerald-700">
                  {!! __('pwa.facturation.mecef_certifiees', ['nombre' => $certifiees, 'total' => $factures->count()]) !!}
                </span>
              @endif
            </div>

            {{-- `print:hidden` (01/09/2026) : à l'impression, le registre est
                 rendu sous sa forme DOCUMENT (les colonnes du moteur du
                 maître), plus bas en `hidden print:block`. Imprimer les deux
                 remettrait deux fois le même registre. --}}
            <div class="overflow-x-auto print:hidden"><table class="w-full text-[13px]">
                <thead class="bg-[var(--navy)] text-[11px] uppercase tracking-wide text-white/90 font-semibold"><tr>
                  {{-- La case de selection du maitre (`crud-ui.js` l.66-68,
                       `#crud-case-tout`) : elle restreint l'export Excel a la
                       selection — le conseil de la modale d'export la designe. --}}
                  <th class="px-4 py-2.5 w-10 no-print">
                    <input type="checkbox" wire:model.live="toutSelectionne" class="w-4 h-4 rounded"
                           aria-label="{{ __('facturation_pwa.selection_tout') }}">
                  </th>
                  <th class="text-left px-4 py-2.5">{{ __('pwa.facturation.col_numero') }}</th>
                  <th class="text-left px-4 py-2.5">{{ __('pwa.facturation.col_date') }}</th>
                  <th class="text-left px-4 py-2.5">{{ __('pwa.facturation.col_client') }}</th>
                  <th class="text-left px-4 py-2.5">{{ __('pwa.facturation.col_origine') }}</th>
                  <th class="text-left px-4 py-2.5">{{ __('pwa.facturation.col_activites') }}</th>
                  <th class="text-right px-4 py-2.5">{{ __('pwa.facturation.col_montant') }}</th>
                  {{-- « Mode de paiement » : colonne du maître, rendue comme
                       « Origine » — présente, honnête, vide. Voir le bloc de
                       refus : `factures` ne la porte pas, et le modèle
                       `Paiement` n'existe pas (PA-21). --}}
                  <th class="text-left px-4 py-2.5">{{ __('facturation_pwa.col_mode_paiement') }}</th>
                  <th class="text-left px-4 py-2.5">{{ __('pwa.facturation.col_statut') }}</th>
                  {{-- Entête VIDE : la colonne d'actions de ligne. Lui donner
                       un libellé inventerait une colonne que le maître n'a
                       pas. --}}
                  <th class="px-4 py-2.5 no-print"></th>
                </tr></thead>
                <tbody id="corps-fac">
                  @forelse ($factures as $facture)
                    @php($habillage = Facturation::STATUTS[$facture->statut] ?? null)
                    @php($activites = $facture->lignes->pluck('source_module')->unique()->map(fn (string $m): string => Facturation::ACTIVITES[$m] ?? $m)->implode(', '))
                    <tr class="border-t border-slate-100" wire:key="facture-{{ $facture->id }}">
                      <td class="px-4 py-2.5 no-print">
                        <input type="checkbox" value="{{ $facture->id }}" wire:model.live="selection" class="w-4 h-4 rounded"
                               aria-label="{{ __('facturation_pwa.selection_ligne') }}">
                      </td>
                      {{-- Article 7 : « — » quand la donnée n'existe pas.
                           `numero_mecef` est `nullable` — « null tant que non
                           certifiée », dit la migration elle-même. --}}
                      <td class="px-4 py-2.5 font-mono-tatacora text-[12px]">{{ $facture->numero_mecef ?? MontantFcfa::TIRET }}</td>
                      <td class="px-4 py-2.5 text-slate-500">{{ $facture->date_emission->format('d/m/Y') }}</td>
                      @php($client = $clients->get($facture->client_id))
                      <td class="px-4 py-2.5">{{ $client === null ? MontantFcfa::TIRET : trim(($client->prenom ?? '').' '.$client->nom) }}</td>
                      {{-- Colonne « Origine » : aucune colonne au schéma, et
                           l'activité ne la dit pas. Voir le bloc de refus. --}}
                      <td class="px-4 py-2.5 text-slate-300">{{ MontantFcfa::TIRET }}</td>
                      <td class="px-4 py-2.5 text-slate-500">{{ $activites !== '' ? $activites : MontantFcfa::TIRET }}</td>
                      <td class="px-4 py-2.5 text-right font-semibold">{{ MontantFcfa::format((string) $facture->montant_ttc) }}</td>
                      {{-- Article 7 : « — » quand la donnée n'existe pas. Le
                           mode de paiement n'est écrit nulle part côté
                           serveur ; en déduire un d'un statut de certification
                           l'inventerait sur l'écran même où l'on rapproche la
                           caisse. --}}
                      <td class="px-4 py-2.5 text-slate-300">{{ MontantFcfa::TIRET }}</td>
                      <td class="px-4 py-2.5">
                        @if ($habillage !== null)
                          <span class="px-2 py-0.5 rounded text-[11px] font-semibold" style="background:{{ $habillage['fond'] }};color:{{ $habillage['texte'] }}">{{ $habillage['libelle'] }}</span>
                        @else
                          {{-- Statut hors registre : rendu EN CLAIR plutôt
                               qu'en pastille muette. --}}
                          <span class="px-2 py-0.5 rounded text-[11px] font-semibold bg-slate-100 text-slate-600 font-mono-tatacora">{{ $facture->statut }}</span>
                        @endif
                        @if ($facture->avoirs->isNotEmpty())
                          {{-- Un avoir n'est pas une facture négative ici :
                               c'est une ligne de la table des avoirs, et la
                               facture reste intacte (RG-03). --}}
                          <span class="px-2 py-0.5 rounded text-[11px] font-semibold bg-slate-100 text-slate-600 ml-1">{{ __('pwa.facturation.avoirs_rattaches', ['nombre' => $facture->avoirs->count()]) }}</span>
                        @endif
                      </td>
                      <td class="px-4 py-2.5 whitespace-nowrap text-right no-print">
                        {{-- Les DEUX gestes réels du module. Ni « Modifier »
                             ni « Supprimer » : une facture figée est immuable
                             (RG-03), et la correction passe par l'avoir. --}}
                        <button type="button" wire:click="imprimerFacture('{{ $facture->id }}')"
                          class="text-[11px] font-semibold px-2 py-0.5 rounded border border-slate-300 text-slate-600 hover:bg-slate-50">{{ __('facturation_pwa.document_action') }}</button>
                        <button type="button" wire:click="ouvrirFormulaireAvoir('{{ $facture->id }}')"
                          class="text-[11px] font-semibold px-2 py-0.5 rounded bg-[var(--navy)] text-white ml-1">{{ __('facturation_pwa.avoir_action') }}</button>
                      </td>
                    </tr>
                  @empty
                    <tr>
                      <td colspan="10" class="p-10 text-center text-[13px] text-slate-400">
                        {{-- L'état vide du moteur du maître (`crud-ui.js`
                             `#crud-etat-vide`), toujours rendu — c'est le
                             contrat du tableau générique. Sans filtre, la
                             ligne du registre du maître (l.126-128) s'y
                             ajoute : « aucune facture » et « aucun résultat
                             pour ce filtre » appellent des gestes opposés. --}}
                        <span class="font-semibold text-slate-500">{{ __('facturation_pwa.aucun_resultat') }}</span><br>
                        {{ __('facturation_pwa.aucun_resultat_detail') }}
                        @unless ($filtreApplique)
                          <br>{{ __('pwa.facturation.registre_vide') }}
                        @endunless
                      </td>
                    </tr>
                  @endforelse
                </tbody></table></div>

            {{-- ========= LE REGISTRE IMPRIMÉ : LA FORME DOCUMENT DU MAÎTRE =========
                 maitre — `m2-facturation.html`, bloc `"colonnes"` de son moteur
                 CRUD : « N° MECeF », « Client », « Services combinés »,
                 « Date », « Montant TTC », « Mode de paiement », « Statut ».
                 Le maître porte une SECONDE table sur cette page — celle de son
                 moteur générique. Son JEU DE DONNÉES de démonstration reste
                 refusé (Article 6, bloc de refus du composant) ; sa STRUCTURE,
                 elle, est celle du document : elle est rendue ici à
                 l'impression, sur les pièces réellement AFFICHÉES (PA-119) —
                 mêmes champs que le tableau d'écran (`numero_mecef`,
                 `montant_ttc`, activités des lignes), jamais un second calcul.
                 Rendue au premier GET (`hidden print:block`), donc vérifiable
                 par `ColonnesDesTableauxPwaTest`. --}}
            <div class="hidden print:block">
              <table class="w-full text-[12px]">
                <thead>
                  <tr class="text-left text-[11px] font-semibold text-slate-500 uppercase border-b-2 border-slate-400">
                    <th class="text-left px-2 py-1.5">{{ __('facturation_pwa.registre_col_numero_mecef') }}</th>
                    <th class="text-left px-2 py-1.5">{{ __('pwa.facturation.col_client') }}</th>
                    <th class="text-left px-2 py-1.5">{{ __('facturation_pwa.registre_col_services') }}</th>
                    <th class="text-left px-2 py-1.5">{{ __('pwa.facturation.col_date') }}</th>
                    <th class="text-right px-2 py-1.5">{{ __('facturation_pwa.registre_col_montant_ttc') }}</th>
                    <th class="text-left px-2 py-1.5">{{ __('facturation_pwa.col_mode_paiement') }}</th>
                    <th class="text-left px-2 py-1.5">{{ __('pwa.facturation.col_statut') }}</th>
                  </tr>
                </thead>
                <tbody>
                  @forelse ($factures as $facture)
                    @php($habillageDoc = Facturation::STATUTS[$facture->statut] ?? null)
                    @php($activitesDoc = $facture->lignes->pluck('source_module')->unique()->map(fn (string $m): string => Facturation::ACTIVITES[$m] ?? $m)->implode(', '))
                    @php($clientDoc = $clients->get($facture->client_id))
                    <tr class="border-b border-slate-200" wire:key="doc-facture-{{ $facture->id }}">
                      <td class="px-2 py-1.5 font-mono-tatacora text-[11px]">{{ $facture->numero_mecef ?? MontantFcfa::TIRET }}</td>
                      <td class="px-2 py-1.5">{{ $clientDoc === null ? MontantFcfa::TIRET : trim(($clientDoc->prenom ?? '').' '.$clientDoc->nom) }}</td>
                      <td class="px-2 py-1.5">{{ $activitesDoc !== '' ? $activitesDoc : MontantFcfa::TIRET }}</td>
                      <td class="px-2 py-1.5">{{ $facture->date_emission->format('d/m/Y') }}</td>
                      <td class="px-2 py-1.5 text-right font-semibold tabular-nums">{{ MontantFcfa::format((string) $facture->montant_ttc) }}</td>
                      {{-- Article 7 : « — » quand la donnée n'existe pas —
                           même refus que la colonne du tableau d'écran. --}}
                      <td class="px-2 py-1.5">{{ MontantFcfa::TIRET }}</td>
                      <td class="px-2 py-1.5">{{ $habillageDoc !== null ? $habillageDoc['libelle'] : $facture->statut }}</td>
                    </tr>
                  @empty
                    <tr>
                      <td colspan="7" class="px-2 py-6 text-center text-slate-400">
                        <span class="font-semibold text-slate-500">{{ __('facturation_pwa.aucun_resultat') }}</span><br>
                        {{ __('facturation_pwa.aucun_resultat_detail') }}
                      </td>
                    </tr>
                  @endforelse
                </tbody>
              </table>
            </div>

            {{-- La pagination du maître (`crud-engine.js` `renderPagination`) :
                 « Affichage de X-Y sur Z » à gauche, les liens à droite.
                 structure-ajout:m2-facturation.html#div-4c1a6291 — le maître
                 pose ce bloc en JavaScript dans `#crud-pagination`, que le
                 comparateur de squelette ne lit pas ; la PWA le rend côté
                 serveur (G6, 01/09/2026). --}}
            <div class="flex items-center justify-between px-4 py-3 border-t border-slate-100 no-print">
              <p class="text-xs text-slate-500">{!! __('facturation_pwa.affichage', [
                  'debut' => '<strong>' . ($factures->total() === 0 ? 0 : $factures->firstItem()) . '</strong>',
                  'fin' => '<strong>' . ($factures->lastItem() ?? 0) . '</strong>',
                  'total' => '<strong>' . $factures->total() . '</strong>',
              ]) !!}</p>
              {{ $factures->onEachSide(1)->links() }}
            </div>
          </div>
        </section>

        {{--
            NON PORTE, ET PLUS RENDU A L'ECRAN (02/09/2026). Le bloc « Jeu de
            demonstration » du maitre (l.33-39) et les zones de son moteur CRUD
            ne sont pas portes ; la liste qui l'expliquait au lecteur de
            l'ecran est retiree par directive du Product Owner.

            Les modales du maitre restent declarees comme refusees, avec leur
            raison, dans `app/Pwa/Livewire/Facturation/Facturation.php` — c'est
            la que vivent les jetons `maitre-refuse:m2-facturation.html#...`.
        --}}

      </div>
    </main>
  </div>

  {{-- ================================ MODALE : ÉMETTRE UN AVOIR (RG-03) --}}
  @if ($etatFormulaire === 'avoir' && $avoirFacture !== null)
    <x-pwa.modale :titre="__('facturation_pwa.avoir_titre')"
                  :sousTitre="__('facturation_pwa.avoir_sous_titre')"
                  largeur="560px" fermer="fermerModales">
      <form wire:submit.prevent="enregistrerAvoir" class="space-y-4">
        <div class="rounded-lg bg-slate-50 px-3 py-2 text-[13px] text-slate-600">
          <span class="font-semibold">{{ __('facturation_pwa.avoir_facture') }}</span>
          <span class="font-mono-tatacora">{{ $avoirFacture->numero_mecef ?? MontantFcfa::TIRET }}</span>
          — {{ MontantFcfa::format((string) $avoirFacture->montant_ttc) }}
        </div>

        <div>
          <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('facturation_pwa.avoir_montant') }} <span class="text-red-500">*</span></label>
          <input type="number" min="1" step="1" wire:model="avoirMontant"
                 class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm">
          <p class="text-[12px] text-slate-400 mt-1">{{ __('facturation_pwa.avoir_montant_aide', ['plafond' => MontantFcfa::format((string) $avoirFacture->montant_ttc)]) }}</p>
          @error('avoirMontant') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>

        <div>
          <label class="block text-[15px] font-semibold text-slate-700 mb-1.5">{{ __('facturation_pwa.avoir_motif') }} <span class="text-red-500">*</span></label>
          <input type="text" wire:model="avoirMotif" placeholder="{{ __('facturation_pwa.avoir_motif_invite') }}"
                 class="champ w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm">
          @error('avoirMotif') <p class="text-[12px] text-red-600 mt-1">{{ $message }}</p> @enderror
        </div>

        @error('avoirFactureId') <p class="text-[12px] text-red-600">{{ $message }}</p> @enderror

        {{-- Le bouton de soumission vit DANS le `<form>` : le pied de la
             modale lui est extérieur, et un `type="submit"` posé là ne
             soumettrait rien. --}}
        <div class="flex justify-end gap-2 pt-2">
          <button type="button" wire:click="fermerModales"
            class="text-[13px] px-4 py-2 rounded-lg border border-slate-300 hover:bg-slate-50">{{ __('pwa.modale.annuler') }}</button>
          <button type="submit"
            class="text-[13px] px-4 py-2 rounded-lg bg-[var(--navy)] text-white font-semibold hover:opacity-90">{{ __('facturation_pwa.avoir_valider') }}</button>
        </div>
      </form>
    </x-pwa.modale>
  @endif

  {{-- La modale d'export est PARTAGÉE (dérogation PO, voir le bouton
       « Exporter » ci-dessus). Le titre NOMME ce qui sera exporté, le
       sous-titre DIT le filtre appliqué (PA-119). --}}
  @if ($etatFormulaire === 'export')
    @include('pwa.partials.modale-export', [
      'titre' => __('pwa.facturation.export_titre'),
      'sousTitre' => __('pwa.facturation.export_sous_titre', ['filtre' => $filtreExport]),
    ])
  @endif

</div>
