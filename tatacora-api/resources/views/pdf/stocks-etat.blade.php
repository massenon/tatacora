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
<title>Gestion des Stocks — {{ $entete->raisonSociale }}</title>
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

  {{-- METRICS DE SYNTHÈSE (KPIS) --}}
  <table class="kpi-table">
    <tr>
      <td class="kpi-box">
        <div>RÉFÉRENCES</div>
        <div class="kpi-value">{{ $consolide->references }}</div>
      </td>
      <td class="kpi-box">
        <div>VALEUR TOTALE</div>
        <div class="kpi-value text-gold">{{ number_format((float)$consolide->valeurTotale, 0, ',', ' ') }} FCFA</div>
      </td>
      <td class="kpi-box">
        <div>SOUS SEUIL</div>
        <div class="kpi-value text-red">{{ $consolide->sousSeuil }}</div>
      </td>
    </tr>
  </table>

  {{-- CORPS DE DONNÉES CONTRÔLÉ --}}
  <table class="data-table">
    <thead>
      {{-- PA-161 (a) — « Point », « Suivi » et « Valeur d'achat » manquaient à
           ce document alors qu'elles s'affichent à l'écran : le Gérant lisait
           un état plus pauvre que la page dont il l'avait tiré. Ordre du
           maître (`m6-stocks.html` l.464). --}}
      {{-- PA-186 (11/09/2026) — L'UNITÉ EST DANS L'EN-TÊTE, décision du Product
           Owner. « FCFA partout » posé dans CHAQUE cellule faisait passer à la
           ligne 76 montants sur 98 lignes réelles : les colonnes de montant
           font 9 à 10 % de la page, soit 42 à 48 pt utiles, et « 12 500 FCFA »
           en demande 51 (mesuré avec les métriques de dompdf). Porter
           « (FCFA) » dans l'en-tête ramène à zéro les montants coupés sans
           toucher aux largeurs — la présentation du rapport d'inventaire. Ne
           pas remettre le suffixe dans les cellules. --}}
      <tr>
        <th class="text-left" style="width: 21%;">Article</th>
        <th class="text-left" style="width: 13%;">Catégorie</th>
        <th class="text-left" style="width: 12%;">Point</th>
        <th class="text-left" style="width: 9%;">Suivi</th>
        <th class="text-right" style="width: 9%;">Stock</th>
        <th class="text-right" style="width: 7%;">Seuil</th>
        <th class="text-right" style="width: 10%;">Valeur d'achat (FCFA)</th>
        <th class="text-right" style="width: 9%;">CMP (FCFA)</th>
        <th class="text-right" style="width: 10%;">Valeur (FCFA)</th>
      </tr>
    </thead>
    <tbody>
      @foreach ($lignes as $l)
        @php
            // Un article journalier n'a NI stock, NI seuil, NI valeur : le
            // maître écrit « non suivi » et « — » (l.468-472). Un « 0 » sur un
            // document remis se lirait comme une rupture constatée.
            $journalier = ! $l->article->estSuiviEnStock();
        @endphp
        <tr>
          <td class="text-left font-bold">{{ $l->article->libelle }}</td>
          <td class="text-left text-slate">{{ $l->article->categorie }}</td>
          <td class="text-left text-slate">{{ $l->article->pointStockage?->libelle ?? '—' }}</td>
          <td class="text-left text-slate">{{ $journalier ? 'Journalier' : 'Permanent' }}</td>
          <td class="text-right font-bold {{ ! $journalier && $l->rupture ? 'text-red' : '' }}">{{ $journalier ? 'non suivi' : $l->stock }}</td>
          <td class="text-right text-slate">{{ $journalier ? '—' : $l->article->seuil_alerte }}</td>
          <td class="text-right text-slate">{{ $l->article->prix_achat === null ? '—' : number_format((float) $l->article->prix_achat, 0, ',', ' ') }}</td>
          <td class="text-right font-bold text-slate">{{ number_format((float)$l->article->cout_moyen_pondere, 0, ',', ' ') }}</td>
          <td class="text-right font-bold text-gold">{{ $journalier ? '—' : number_format((float)$l->valeur, 0, ',', ' ') }}</td>
        </tr>
      @endforeach
    </tbody>
  </table>

  {{-- SIGNATURES --}}
  <div style="margin-top: 30px; page-break-inside: avoid;">
  @include('pdf.partials.signatures', ['visas' => ['Signature Magasinier / Gestionnaire', 'Signature Direction / Validation']])
  </div>

  @include('pdf.partials.pied-rapport')
</body>
</html>