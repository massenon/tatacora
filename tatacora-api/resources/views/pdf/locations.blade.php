<!DOCTYPE html>
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
<title>Véhicules & Locations — {{ $entete->raisonSociale }}</title>
<style>
  @page {
    size: A4 portrait;
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
  .kpi-table {
    margin-bottom: 12px;
  }
  .kpi-box {
    border: 1px solid #cbd5e1;
    background-color: #f8fafc;
    padding: 5px;
    text-align: center;
    font-size: 7.5pt;
  }
  .kpi-value {
    font-size: 11pt;
    font-weight: bold;
    color: #14213D;
    margin-top: 2px;
  }
  .data-table {
    margin-top: 6px;
  }
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
    padding: 5px 4px;
    border-bottom: 1px solid #e2e8f0;
    font-size: 8.5pt;
    word-wrap: break-word;
    overflow: hidden;
  }
  .data-table tbody tr:nth-child(even) {
    background-color: #f8fafc;
  }
  .text-left { text-align: left; }
  .text-right { text-align: right; }
  .text-center { text-align: center; }
  .font-bold { font-weight: bold; }
  .text-gold { color: #B8891E; }
  .text-emerald { color: #059669; }
  .text-red { color: #dc2626; }
  .text-slate { color: #64748b; }

  @include('pdf.partials.entete-rapport-styles')
</style>
</head>
<body>


  {{-- En-tête RG-19 : identité, puis titre, filtre, auteur, heure. --}}
  @include('pdf.partials.entete-rapport')

  {{--
    Le tableau est rendu depuis `$entetes` et `$lignes`, calculés par l'écran :
    le document porte EXACTEMENT ce que la page affiche, filtres compris
    (PA-119). Une seconde requête ici rendrait un document qui n'est pas
    celui qu'on a vérifié à l'écran.
  --}}
  <table class="data-table">
    <thead>
      <tr>
        @foreach ($entetes as $indice => $colonne)
          <th class="{{ $indice === 0 ? 'text-left' : 'text-right' }}">{{ $colonne }}</th>
        @endforeach
      </tr>
    </thead>
    <tbody>
      @foreach ($lignes as $ligne)
        <tr>
          @foreach ($ligne as $indice => $cellule)
            <td class="{{ $indice === 0 ? 'text-left font-bold' : 'text-right text-slate' }}">{{ $cellule }}</td>
          @endforeach
        </tr>
      @endforeach
    </tbody>
  </table>

  <div style="margin-top: 18px; font-size: 7.5pt; color: #64748b;">
    {{ count($lignes) }} ligne(s) — extrait de la consultation web, sur le filtre indiqué ci-dessus.
  </div>

  @include('pdf.partials.signatures')
  @include('pdf.partials.pied-rapport')
</body>
</html>
