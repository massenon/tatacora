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
<title>Fiche de Stock — {{ $entete->raisonSociale }}</title>
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

  {{-- FOOTER PERMANENT --}}

  {{-- EN-TÊTE INSTITUTIONNEL UNIVERSEL --}}
  {{-- En-tête RG-19 : identité, puis titre, filtre, auteur, heure. --}}
  @include('pdf.partials.entete-rapport')

  @if ($fiche)
    {{-- METRICS DE SYNTHÈSE (KPIS) --}}
    <table class="kpi-table">
      <tr>
        <td class="kpi-box">
          <div>STOCK INITIAL</div>
          <div class="kpi-value">{{ $fiche['stock_initial'] }}</div>
        </td>
        <td class="kpi-box">
          <div>ENTRÉES</div>
          <div class="kpi-value text-emerald">+{{ $fiche['entrees'] }}</div>
        </td>
        <td class="kpi-box">
          <div>SORTIES</div>
          <div class="kpi-value text-red">−{{ $fiche['sorties'] }}</div>
        </td>
        <td class="kpi-box">
          <div>STOCK THÉORIQUE</div>
          <div class="kpi-value">{{ $fiche['stock_theorique'] }}</div>
        </td>
        {{-- PA-194 (11/09/2026) : la clé lue ici était `valeur_theorique`,
             que `FicheStockService::pourArticle()` ne rend pas — elle rend
             `valeur_stock_theorique`. Le document levait « Undefined array
             key » à CHAQUE export PDF de fiche, et aucun test ne le rendait :
             `PdfExportsRendusTest` l'a trouvé en l'exécutant. --}}
        <td class="kpi-box">
          <div>VALEUR TOTALE</div>
          <div class="kpi-value text-gold">{{ number_format((float)$fiche['valeur_stock_theorique'], 0, ',', ' ') }} FCFA</div>
        </td>
      </tr>
    </table>

    {{-- TABLEAU DÉTAIL DES MOUVEMENTS --}}
    <table class="data-table">
      <thead>
        <tr>
          <th class="text-left" style="width: 20%;">Date & Heure</th>
          <th class="text-left" style="width: 35%;">Motif / Origine</th>
          <th class="text-right" style="width: 15%;">Entrée</th>
          <th class="text-right" style="width: 15%;">Sortie</th>
          <th class="text-right" style="width: 15%;">Solde</th>
        </tr>
      </thead>
      <tbody>
        @foreach ($fiche['lignes'] as $l)
          <tr>
            <td class="text-left text-slate">{{ \Carbon\Carbon::parse($l['date'])->format('d/m/Y H:i') }}</td>
            <td class="text-left font-bold">{{ $l['motif'] }}</td>
            <td class="text-right text-emerald font-bold">{{ $l['entree'] > 0 ? '+'.$l['entree'] : '—' }}</td>
            <td class="text-right text-red font-bold">{{ $l['sortie'] > 0 ? '−'.$l['sortie'] : '—' }}</td>
            <td class="text-right font-bold">{{ $l['solde'] }}</td>
          </tr>
        @endforeach
      </tbody>
    </table>
  @endif

  {{-- SIGNATURES --}}
  <div style="margin-top: 30px; page-break-inside: avoid;">
  @include('pdf.partials.signatures', ['visas' => ['Signature Magasinier / Contrôleur', 'Signature Direction / Validation']])
  </div>

  @include('pdf.partials.pied-rapport')
</body>
</html>