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
<title>Rapport d'Inventaire Physique — {{ $entete->raisonSociale }}</title>
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
    table-layout: fixed; /* ANTI-DÉBORDEMENT */
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

  @include('pdf.partials.entete-rapport-styles')
</style>
</head>
<body>


  {{-- EN-TÊTE INSTITUTIONNEL --}}
  {{-- En-tête RG-19 : identité, puis titre, filtre, auteur, heure. --}}
  @include('pdf.partials.entete-rapport')

  {{-- KPIS BILAN DE L'INVENTAIRE --}}
  <table class="kpi-table">
    <tr>
      <td class="kpi-box">
        <div>ARTICLES COMPTÉS</div>
        <div class="kpi-value">{{ count($inventaire->lignes) }}</div>
      </td>
      <td class="kpi-box">
        <div>ÉCARTS DÉTECTÉS</div>
        <div class="kpi-value text-gold">{{ $nbEcarts }}</div>
      </td>
      <td class="kpi-box">
        <div>IMPACT VALORISÉ</div>
        <div class="kpi-value {{ $impactNet < 0 ? 'text-red' : 'text-emerald' }}">
          {{ number_format($impactNet, 0, ',', ' ') }} FCFA
        </div>
      </td>
    </tr>
  </table>

  {{-- TABLEAU DES LIGNES COMPTÉES ET ÉCARTS --}}
  <table class="data-table">
    <thead>
      <tr>
        <th class="text-left" style="width: 35%;">Article</th>
        <th class="text-right" style="width: 15%;">Stock Théorique</th>
        <th class="text-right" style="width: 15%;">Stock Compté</th>
        <th class="text-right" style="width: 15%;">Écart</th>
        <th class="text-right" style="width: 20%;">Valeur Écart (FCFA)</th>
      </tr>
    </thead>
    <tbody>
      @foreach ($inventaire->lignes as $ligne)
        @php
          $theorique = (float) $ligne->quantite_theorique;
          $constatee = $ligne->quantite_constatee !== null ? (float) $ligne->quantite_constatee : $theorique;
          $ecart = $constatee - $theorique;
          $cmp = (float) ($ligne->article->cout_moyen_pondere ?? 0);
          $valeurEcart = $ecart * $cmp;
        @endphp
        <tr>
          <td class="text-left font-bold">{{ $ligne->article->libelle ?? 'Article' }}</td>
          <td class="text-right">{{ $theorique }}</td>
          <td class="text-right font-bold">{{ $constatee }}</td>
          <td class="text-right font-bold {{ $ecart < 0 ? 'text-red' : ($ecart > 0 ? 'text-emerald' : '') }}">
            {{ $ecart > 0 ? '+' : '' }}{{ $ecart }}
          </td>
          <td class="text-right font-bold {{ $valeurEcart < 0 ? 'text-red' : ($valeurEcart > 0 ? 'text-emerald' : '') }}">
            {{ number_format($valeurEcart, 0, ',', ' ') }} FCFA
          </td>
        </tr>
      @endforeach
    </tbody>
  </table>

  {{-- SIGNATURES --}}
  @include('pdf.partials.signatures', ['visas' => ['Visa Agent Recenseur', 'Visa Responsable Magasin / Direction']])

  @include('pdf.partials.pied-rapport')
</body>
</html>