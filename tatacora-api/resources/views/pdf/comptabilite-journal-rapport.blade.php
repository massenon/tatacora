<!DOCTYPE html>
{{--
    JOURNAL COMPTABLE — document A4 de l'onglet « Journal » du hub SYSCOHADA.
    Maître : `prototype_v2/pages/m10-syscohada.js` `etatCourant()` (branche
    Journal/Grand livre, l.149-160).

    ⚠ PA-119 : l'export porte sur CE QUI EST AFFICHÉ (l'exercice et les
    statuts consultés), et il DIT son périmètre.

    Même gabarit que `pdf/depenses-rapport.blade.php` — en-tête, pied de
    page, tableau — repris ici plutôt que réinventé : un même en-tête sur deux
    documents qui divergeraient serait la non-conformité n°1 de
    `RESPECT_TABLEAU_RAPPORT.md` §4.
--}}
{{--
    ## En-tête, signatures, pied (11/09/2026, PA-192 — Directive §6)

    L'identité de l'établissement était écrite ici à la main — et avait
    DIVERGÉ : un second numéro de téléphone que les paramètres ne portent pas.
    Elle vient désormais de `pdf.partials.entete-rapport` (`ReportHeaderService`,
    RG-19, source unique), dont le bloc titre porte le titre, le filtre,
    l'auteur et l'heure. Zone de signatures (`pdf.partials.signatures`) et pied
    de rapport (`pdf.partials.pied-rapport`), comme tout export.
--}}
<html lang="fr">
<head>
<meta charset="UTF-8">
<title>{{ __('comptabilite_pwa.export_journal_titre') }} — {{ $entete->raisonSociale }}</title>
<style>
  @page { size: A4 landscape; margin: 10mm 10mm 15mm 10mm; }
  body { font-family: 'Helvetica', 'Arial', sans-serif; font-size: 9pt; color: #1e293b; margin: 0; padding: 0; }
  table { width: 100%; border-collapse: collapse; table-layout: fixed; }
  .data-table { margin-top: 10px; }
  .data-table thead th {
    background-color: #14213D; color: #ffffff; font-size: 8pt; font-weight: bold;
    text-transform: uppercase; padding: 6px 4px; border: 1px solid #14213D;
  }
  .data-table tbody td { padding: 6px 4px; border-bottom: 1px solid #e2e8f0; font-size: 8.5pt; word-wrap: break-word; overflow: hidden; }
  .data-table tbody tr:nth-child(even) { background-color: #f8fafc; }
  .data-table tfoot td { padding: 7px 4px; border-top: 2px solid #14213D; font-size: 9.5pt; font-weight: bold; color: #14213D; }
  .text-left { text-align: left; }
  .text-right { text-align: right; }
  @include('pdf.partials.entete-rapport-styles')
</style>
</head>
<body>


  {{-- En-tête RG-19 : identité, puis titre, filtre, auteur, heure. --}}
  @include('pdf.partials.entete-rapport')

  <table class="data-table">
    <thead>
      <tr>
        <th class="text-left" style="width: 9%;">{{ __('comptabilite_pwa.col_date') }}</th>
        <th class="text-left" style="width: 12%;">{{ __('comptabilite_pwa.col_numero_piece') }}</th>
        <th class="text-left" style="width: 9%;">{{ __('comptabilite_pwa.col_journal') }}</th>
        <th class="text-left" style="width: 12%;">{{ __('comptabilite_pwa.col_compte') }}</th>
        <th class="text-left" style="width: 24%;">{{ __('comptabilite_pwa.col_libelle_ligne') }}</th>
        <th class="text-left" style="width: 12%;">{{ __('comptabilite_pwa.col_centre') }}</th>
        <th class="text-right" style="width: 11%;">{{ __('comptabilite_pwa.col_debit') }}</th>
        <th class="text-right" style="width: 11%;">{{ __('comptabilite_pwa.col_credit') }}</th>
      </tr>
    </thead>
    <tbody>
      @foreach ($lignes as $ligne)
        <tr>
          <td class="text-left">{{ $ligne->date_ecriture->format('d/m/Y') }}</td>
          <td class="text-left">{{ $ligne->numero_piece ?? \App\Pwa\Support\MontantFcfa::TIRET }}</td>
          <td class="text-left">{{ $ligne->journal?->code }}</td>
          <td class="text-left">{{ $ligne->compte?->numero_compte }} — {{ $ligne->compte?->libelle }}</td>
          <td class="text-left">{{ $ligne->libelle }}</td>
          <td class="text-left">{{ $ligne->centre?->libelle ?? \App\Pwa\Support\MontantFcfa::TIRET }}</td>
          <td class="text-right">{{ \App\Pwa\Support\MontantFcfa::formatOuTiret($ligne->debit) }}</td>
          <td class="text-right">{{ \App\Pwa\Support\MontantFcfa::formatOuTiret($ligne->credit) }}</td>
        </tr>
      @endforeach
    </tbody>
    <tfoot>
      <tr>
        <td colspan="6" class="text-right">{{ __('comptabilite_pwa.totaux') }}</td>
        <td class="text-right">{{ \App\Pwa\Support\MontantFcfa::format($totalDebit) }}</td>
        <td class="text-right">{{ \App\Pwa\Support\MontantFcfa::format($totalCredit) }}</td>
      </tr>
    </tfoot>
  </table>

  @include('pdf.partials.signatures')
  @include('pdf.partials.pied-rapport')
</body>
</html>
