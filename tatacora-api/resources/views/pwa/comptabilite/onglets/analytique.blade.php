{{--
    Onglet « Analytique » du hub — maître :
    `prototype_v2/pages/m10-syscohada-etats.js` `vueAnalytique()` l.163-206.

    Sept colonnes du maître (l.204) : « Centre », « Libellé », « Produits »,
    « Charges directes », « Marge sur coûts directs », « Taux », « Lignes ».
    L'encadré ambre (l.196-202) est repris : il explique pourquoi les colonnes
    sont des marges sur coûts directs et non des résultats nets.

    ⚠ Ce n'est PAS le tableau de `m10-analytique.html`, qui n'a que cinq
    colonnes et les nomme autrement (« Charges », « Marge », « Taux de
    marge »). Les deux sont portés séparément.

    ## L'alerte sur les lignes non ventilées n'est pas rendue — Article 8

    ÉCART DÉLIBÉRÉ — `m10-syscohada-etats.js` l.169-174
    Le maître : un encadré rouge comptant les lignes SANS centre analytique et
    le montant concerné, « elles proviennent d'un import ou d'une version
    antérieure et faussent chaque colonne ci-dessous ».
    Ici : absent.
    Raison : `Analytique::ventilationGarantieParSchema` vaut `true` — la
    colonne `ecritures_comptables.centre_id` est NOT NULL au schéma, si bien
    qu'une ligne sans centre ne peut pas exister. Le compteur du maître ne
    pourrait donc valoir que zéro, et un indicateur qui ne peut prendre qu'une
    valeur n'apprend rien : c'est PA-59/60/61 dans l'autre sens, un voyant
    perpétuellement vert. Le ReadModel du serveur porte déjà ce constat, et le
    dit dans son propre en-tête.
    Refus déclaré : maitre-refuse:m10-syscohada.html#analytique
--}}
@php
    use App\Pwa\Support\MontantFcfa;

    // Les colonnes de l'onglet, écrites UNE fois (voir `_entetes`).
    $colonnesEntete = [
        ['Centre', 'left'],
        ['Libellé', 'left'],
        ['Produits', 'right'],
        ['Charges directes', 'right'],
        ['Marge sur coûts directs', 'right'],
        ['Taux', 'right'],
        ['Lignes', 'right'],
    ];
@endphp
@if ($squelette ?? false)
  @include('pwa.comptabilite.onglets._squelette_tableau', ['colonnes' => $colonnesEntete, 'message' => $messageSquelette])
@else
@php
    $styleSoldeFinal = 'background: var(--navy); color: #fff; font-weight: 700;';
    $centresActifs = array_values(array_filter($analytique->centres, fn ($centre) => $centre->nombreLignes > 0));
@endphp
@if ($centresActifs === [])
  <div class="bg-white rounded-xl border border-slate-200 py-14 text-center text-slate-400 text-[13px]">
    Aucune écriture ventilée sur la période.
  </div>
@else
  @unless ($analytique->repartitionStructureEffectuee)
    {{-- L'encadré ambre du maître (l.196-202), mot pour mot. --}}
    <div class="rounded-xl p-3.5 mb-4" style="background:#FFFBEB;border:1px solid #FDE68A">
      <p class="text-[13px]" style="color:#78350F">
        <strong>Aucune charge de structure n'est répartie.</strong>
        Les charges imputées au centre ADM y restent. Une clé de répartition (au chiffre d'affaires,
        aux nuitées, à la surface) est une <strong>décision de gestion</strong>, pas une constante technique :
        la choisir ici rendrait le bar bénéficiaire ou déficitaire selon une règle que personne n'aurait validée.
        Les résultats par centre sont donc des <strong>marges sur coûts directs</strong>, pas des résultats nets.
      </p>
    </div>
  @endunless

  <div class="bg-white rounded-xl border border-slate-200 overflow-hidden mb-3">
    <div class="px-4 py-3 border-b border-slate-200 flex items-center justify-between">
      <h3 class="text-[14px] font-bold" style="color:var(--navy)">Résultat par centre d'analyse</h3>
    </div>
    <div class="overflow-x-auto">
      <table class="w-full text-[13px] compta" style="white-space: nowrap">
        @include('pwa.comptabilite.onglets._entetes', ['colonnes' => $colonnesEntete])
        <tbody>
          @foreach ($centresActifs as $centre)
            <tr class="border-t border-slate-100 hover:bg-slate-50">
              {{-- ÉCART DÉLIBÉRÉ — `m10-syscohada-etats.js` l.178, colonne « Centre »
                   Le maître : un CODE court (`c.code`, du type ADM, BAR).
                   Ici : le libellé du centre, et la colonne « Libellé » porte
                   son type.
                   Raison : `centres_cout` n'a pas de colonne `code` au schéma —
                   `CentreCout` ne porte que `libelle` et `type`. Fabriquer un
                   code par abréviation du libellé inventerait un identifiant
                   que rien ne stocke, et deux centres pourraient produire le
                   même. --}}
              <td class="px-3 py-2 font-semibold" style="color:var(--navy)">{{ $centre->libelle }}</td>
              <td class="px-3 py-2 text-left text-slate-700">{{ $centre->type ?? '—' }}</td>
              <td class="px-3 py-2 text-right text-emerald-700 font-semibold">{{ MontantFcfa::formatOuTiret($centre->produits) }}</td>
              <td class="px-3 py-2 text-right text-red-600">{{ MontantFcfa::formatOuTiret($centre->charges) }}</td>
              <td class="px-3 py-2 text-right font-bold {{ MontantFcfa::estNegatif($centre->resultat) ? 'text-red-600' : '' }}"
                  @if (! MontantFcfa::estNegatif($centre->resultat)) style="color:var(--navy)" @endif>{{ MontantFcfa::format($centre->resultat) }}</td>
              {{-- « — », jamais « 0 % » : un centre sans produits n'a pas de taux. --}}
              <td class="px-3 py-2 text-right {{ $centre->tauxMarge === null ? 'text-slate-300' : (MontantFcfa::estNegatif($centre->tauxMarge) ? 'text-red-600' : 'text-slate-600') }}">
                {{ $centre->tauxMarge === null ? '—' : $centre->tauxMarge . ' %' }}
              </td>
              <td class="px-3 py-2 text-right text-slate-400 text-[12px]">{{ $centre->nombreLignes }}</td>
            </tr>
          @endforeach
          <tr style="{{ $styleSoldeFinal }}">
            <td class="px-3 py-2.5" colspan="2">TOTAL</td>
            <td class="px-3 py-2.5 text-right">{{ MontantFcfa::format($analytique->totalProduits) }}</td>
            <td class="px-3 py-2.5 text-right">{{ MontantFcfa::format($analytique->totalCharges) }}</td>
            <td class="px-3 py-2.5 text-right">{{ MontantFcfa::format($analytique->totalResultat) }}</td>
            <td colspan="2"></td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
@endif
@endif
