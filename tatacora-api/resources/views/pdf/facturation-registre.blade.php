<!DOCTYPE html>
{{--
    REGISTRE DES FACTURES ÉMISES — document A4 de l'écran « Facturation &
    Caisse MECeF » (M2). Maître : prototype_v2/pages/m2-facturation.html
    (boutons d'export l.112-113, fusionnés — dérogation PO du 01/09/2026,
    rappelée le 02/09/2026, voir `DerogationsMaquette` export_bouton_unique).

    ⚠ CE DOCUMENT N'EST PAS UNE FACTURE. C'est le REGISTRE affiché à l'écran,
    rendu sur papier — la pièce fiscale individuelle reste `pdf.facture-mecef`
    (« Facture A4 », bouton par ligne). Aucun cachet, aucun QR : rien ici ne
    doit pouvoir être pris pour un document MECeF (PA-101/PA-113).

    ⚠ PA-119 : l'export porte sur CE QUI EST AFFICHÉ (filtres ET sélection),
    et il DIT son filtre — la ligne « Périmètre » ci-dessous.

    ⚠ L'IDENTITÉ DE L'ÉTABLISSEMENT VIENT DE `ReportHeaderService`
    (`$entete`), jamais recopiée en dur (RG-19,
    `RESPECT_TABLEAU_RAPPORT.md` §4). IFU/RCCM conditionnels — absents tant
    que non renseignés, jamais un exemple de format.

    ⚠ La colonne « Statut » rend les valeurs RÉELLES de `factures.statut`
    (cycle MECeF), comme l'écran et comme `FacturationExport` — jamais les
    libellés du prototype (même arbitrage que PA-49).

    ## En-tête, signatures, pied (11/09/2026, PA-192 — Directive §6)

    Le bloc d'identité recopié ici (classes `tc-*`) cède la place au partiel
    de RAPPORT, source unique ; zone de signatures et pied de rapport. Ce
    REGISTRE est un export interne — ce n'est pas une facture, et aucune
    facture n'y gagne de visa.
--}}
<html lang="fr">
<head>
<meta charset="UTF-8">
<title>{{ __('pwa.facturation.export_document') }} — {{ __('pwa.marque') }}</title>
<style>
  @page { size: A4 portrait; margin: 10mm 10mm 15mm 10mm; }
  body { font-family: 'Helvetica', 'Arial', sans-serif; font-size: 9pt; color: #1e293b; margin: 0; padding: 0; }
  table { width: 100%; border-collapse: collapse; table-layout: fixed; }

  @include('pdf.partials.entete-rapport-styles')

  .filtre {
    margin-bottom: 10px; padding: 6px 8px;
    background: #f8fafc; border: 1px solid #cbd5e1;
    font-size: 8pt; color: #475569;
  }

  .data-table { margin-top: 6px; }
  .data-table thead th {
    background-color: #14213D; color: #ffffff; font-size: 8pt; font-weight: bold;
    text-transform: uppercase; padding: 6px 4px; border: 1px solid #14213D;
  }
  .data-table tbody td {
    padding: 5px 4px; border-bottom: 1px solid #e2e8f0;
    font-size: 8.5pt; word-wrap: break-word; overflow: hidden;
  }
  .data-table tbody tr:nth-child(even) { background-color: #f8fafc; }
  .data-table tfoot td {
    padding: 7px 4px; border-top: 2px solid #14213D;
    font-size: 9.5pt; font-weight: bold; color: #14213D;
  }

  .text-left { text-align: left; }
  .text-right { text-align: right; }
  .text-center { text-align: center; }


</style>
</head>
<body>

  {{-- En-tête RG-19 : identité, puis titre, période, auteur, heure. --}}
  @include('pdf.partials.entete-rapport')

  {{-- PA-119 — le document DIT son filtre, sélection comprise. --}}
  <div class="filtre">{{ __('pwa.facturation.export_sous_titre', ['filtre' => $filtre]) }}</div>

  <table class="data-table">
    <thead>
      <tr>
        <th class="text-left" style="width: 20%;">{{ __('pwa.facturation.col_numero') }}</th>
        <th class="text-left" style="width: 12%;">{{ __('pwa.facturation.col_date') }}</th>
        <th class="text-left" style="width: 22%;">{{ __('pwa.facturation.col_client') }}</th>
        <th class="text-left" style="width: 16%;">{{ __('pwa.facturation.col_activites') }}</th>
        <th class="text-right" style="width: 14%;">{{ __('pwa.facturation.col_montant') }}</th>
        <th class="text-left" style="width: 16%;">{{ __('pwa.facturation.col_statut') }}</th>
      </tr>
    </thead>
    <tbody>
      @foreach ($factures as $facture)
        @php($clientPiece = $clients->get($facture->client_id))
        @php($lignesActivites = $facture->lignes->pluck('source_module')->unique()->map(fn (string $m): string => $activites[$m] ?? $m)->implode(', '))
        <tr>
          <td class="text-left">{{ $facture->numero_mecef ?? \App\Pwa\Support\MontantFcfa::TIRET }}</td>
          <td class="text-left">{{ $facture->date_emission->format('d/m/Y') }}</td>
          <td class="text-left">{{ $clientPiece === null ? \App\Pwa\Support\MontantFcfa::TIRET : trim(($clientPiece->prenom ?? '').' '.$clientPiece->nom) }}</td>
          <td class="text-left">{{ $lignesActivites !== '' ? $lignesActivites : \App\Pwa\Support\MontantFcfa::TIRET }}</td>
          <td class="text-right">{{ \App\Pwa\Support\MontantFcfa::format((string) $facture->montant_ttc) }}</td>
          <td class="text-left">{{ ($statuts[$facture->statut] ?? [])['libelle'] ?? $facture->statut }}</td>
        </tr>
      @endforeach
    </tbody>
    <tfoot>
      <tr>
        <td class="text-left" colspan="4">{{ __('pwa.facturation.compteur_montant') }}</td>
        <td class="text-right">{{ \App\Pwa\Support\MontantFcfa::format($montant) }}</td>
        <td></td>
      </tr>
    </tfoot>
  </table>

  @include('pdf.partials.signatures')
  @include('pdf.partials.pied-rapport')

</body>
</html>
