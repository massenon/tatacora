<!DOCTYPE html>
{{--
    RÉFÉRENTIEL FOURNISSEURS — document A4 de l'écran « Fournisseurs & Achats ».
    Maître : prototype_v2/pages/m7-achats.html (onglet Fournisseurs).

    ⚠ PA-119 : l'export porte sur CE QUI EST AFFICHÉ, et il DIT son filtre —
    la ligne « Périmètre » ci-dessous. Sans elle, quelqu'un qui filtre puis
    exporte enverrait au comptable un document qu'il croit exhaustif.
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
<title>Référentiel Fournisseurs — {{ $entete->raisonSociale }}</title>
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



  .data-table {
    margin-top: 10px;
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
    padding: 6px 4px;
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

  @include('pdf.partials.entete-rapport-styles')
</style>
</head>
<body>


  {{-- EN-TÊTE INSTITUTIONNEL OFFICIEL --}}
  {{-- En-tête RG-19 : identité, puis titre, filtre, auteur, heure. --}}
  @include('pdf.partials.entete-rapport')

  {{-- TABLEAU AVEC LARGEURS EN % --}}
  <table class="data-table">
    <thead>
      <tr>
        <th class="text-left" style="width: 30%;">Raison Sociale</th>
        <th class="text-left" style="width: 20%;">Contact</th>
        <th class="text-left" style="width: 20%;">Catégorie</th>
        <th class="text-center" style="width: 15%;">Conditions</th>
        <th class="text-center" style="width: 15%;">Évaluation</th>
      </tr>
    </thead>
    <tbody>
      @foreach ($lignes as $f)
        <tr>
          <td class="text-left font-bold" style="color: #14213D;">{{ $f->raison_sociale }}</td>
          <td class="text-left">{{ $f->contact ?? '—' }}</td>
          <td class="text-left">{{ $f->categorie ?? '—' }}</td>
          {{-- Article 7 : « — » quand la donnée n'existe pas. Ce document
               écrivait « Comptant » et « Moyen » par défaut : il affirmait des
               conditions de paiement et une note que personne n'avait saisies,
               sur un papier remis hors de l'écran qui l'a produit. --}}
          <td class="text-center">{{ $f->conditions_paiement ?? '—' }}</td>
          <td class="text-center font-bold">{{ \App\Pwa\Livewire\Achats\Achats::EVALUATIONS[$f->evaluation]['libelle'] ?? '—' }}</td>
        </tr>
      @endforeach
    </tbody>
  </table>

  {{-- SIGNATURES --}}
  @include('pdf.partials.signatures', ['visas' => ['Visa Responsable Achats', 'Visa Direction Générale']])

  @include('pdf.partials.pied-rapport')
</body>
</html>