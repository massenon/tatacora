<!DOCTYPE html>
{{--
    ÉTAT DES DÉPENSES COURANTES — document A4 de l'écran « Dépense courante ».
    Maître : prototype_v2/pages/depenses.html (entêtes d'export :
    prototype_v2/pages/depenses.js l.316).

    ⚠ PA-119 : l'export porte sur CE QUI EST AFFICHÉ, et il DIT son filtre —
    la ligne « Périmètre » ci-dessous. Sans elle, quelqu'un qui filtre puis
    exporte enverrait au comptable un document qu'il croit exhaustif.

    ⚠ Les entêtes sont ceux du maître, dans SA casse. `uppercase` est une règle
    CSS : une majuscule écrite en dur ressortirait telle quelle dans le CSV, où
    aucune feuille de style ne s'applique.

    ⚠ La colonne « Comptabilisation » lit `ecriture_id`, jamais
    `ecriture_refus` : une dépense antérieure au lot PA-159 n'a NI l'un NI
    l'autre, et se serait imprimée « comptabilisée » sur un document remis au
    Comptable. `estComptabilisee()` est la seule preuve qu'une pièce existe.
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
<title>{{ __('depenses_pwa.export_document') }} — {{ $entete->raisonSociale }}</title>
<style>
  @page {
    size: A4 landscape;
    margin: 10mm 10mm 15mm 10mm;
  }
  body {
    font-family: 'Helvetica', 'Arial', sans-serif;
    font-size: 9pt;
    color: #1e293b;
    margin: 0;
    padding: 0;
  }
  table {
    width: 100%;
    border-collapse: collapse;
    table-layout: fixed;
  }

  .data-table { margin-top: 10px; }
  .data-table thead th {
    background-color: #14213D;
    color: #ffffff;
    font-size: 8pt;
    font-weight: bold;
    text-transform: uppercase;
    padding: 6px 4px;
    border: 1px solid #14213D;
  }
  .data-table tbody td {
    padding: 6px 4px;
    border-bottom: 1px solid #e2e8f0;
    font-size: 8.5pt;
    word-wrap: break-word;
    overflow: hidden;
  }
  .data-table tbody tr:nth-child(even) { background-color: #f8fafc; }
  .data-table tfoot td {
    padding: 7px 4px;
    border-top: 2px solid #14213D;
    font-size: 9.5pt;
    font-weight: bold;
    color: #14213D;
  }

  .text-left { text-align: left; }
  .text-right { text-align: right; }
  .text-center { text-align: center; }
  .font-bold { font-weight: bold; }
  .alerte { color: #C62828; font-weight: bold; }

  @include('pdf.partials.entete-rapport-styles')
</style>
</head>
<body>


  {{-- En-tête RG-19 : identité, puis titre, filtre, auteur, heure. --}}
  @include('pdf.partials.entete-rapport')

  <table class="data-table">
    <thead>
      <tr>
        <th class="text-left" style="width: 10%;">{{ __('depenses_pwa.col_date') }}</th>
        <th class="text-left" style="width: 24%;">{{ __('depenses_pwa.col_libelle') }}</th>
        <th class="text-left" style="width: 14%;">{{ __('depenses_pwa.col_nature') }}</th>
        <th class="text-left" style="width: 24%;">{{ __('depenses_pwa.col_charge') }}</th>
        <th class="text-left" style="width: 10%;">{{ __('depenses_pwa.col_tresorerie') }}</th>
        <th class="text-right" style="width: 10%;">{{ __('depenses_pwa.col_montant') }}</th>
        <th class="text-center" style="width: 8%;">{{ __('depenses_pwa.export_col_comptabilisation') }}</th>
      </tr>
    </thead>
    <tbody>
      @foreach ($depenses as $depense)
        <tr>
          <td class="text-left">{{ $depense->date_transaction->format('d/m/Y') }}</td>
          <td class="text-left font-bold" style="color: #14213D;">{{ $depense->libelle }}</td>
          <td class="text-left">{{ \App\Pwa\Livewire\Depenses\Depenses::valeursDistinctes($depense->lignes, 'nature') }}</td>
          <td class="text-left">
            @foreach ($depense->lignes as $ligne)
              {{ $ligne->compte_charge }} — {{ $libellesComptes[$ligne->compte_charge] ?? \App\Pwa\Support\MontantFcfa::TIRET }}@if (! $loop->last)<br>@endif
            @endforeach
          </td>
          <td class="text-left">{{ \App\Pwa\Livewire\Depenses\Depenses::TRESORERIES[$depense->tresorerie] ?? $depense->tresorerie }}</td>
          <td class="text-right">{{ \App\Pwa\Support\MontantFcfa::format((string) $depense->montant_total) }}</td>
          <td class="text-center {{ $depense->estComptabilisee() ? '' : 'alerte' }}">
            {{ $depense->estComptabilisee() ? __('depenses_pwa.export_comptabilisee') : __('depenses_pwa.export_non_comptabilisee') }}
          </td>
        </tr>
      @endforeach
    </tbody>
    <tfoot>
      <tr>
        <td colspan="5" class="text-right">{{ __('depenses_pwa.kpi_total') }}</td>
        <td class="text-right">{{ \App\Pwa\Support\MontantFcfa::format($total) }}</td>
        <td></td>
      </tr>
    </tfoot>
  </table>

  @include('pdf.partials.signatures', ['visas' => ['Visa Caissier / Ordonnateur', 'Visa Direction / Comptable']])

  @include('pdf.partials.pied-rapport')
</body>
</html>
