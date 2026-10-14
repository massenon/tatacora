<!DOCTYPE html>
{{--
    RELEVÉ DE COMPTE CLIENT — document REMIS AU CLIENT.

    ## En-tête (11/09/2026, PA-194)

    L'identité était écrite ici à la main, et elle avait DIVERGÉ : un second
    numéro de téléphone (« 01 42 27 81 66 ») que les paramètres ne portent pas,
    et un pied « TATACORA AFRIQUE — LogiRestock v2.0 », nom d'un autre produit,
    sur un papier remis au client. Elle vient désormais de
    pdf.partials.entete-rapport (ReportHeaderService, RG-19, source unique).
    Ni visa ni pied de rapport : c'est un document client, pas un état interne.
--}}
<html lang="fr">
<head>
<meta charset="UTF-8">
<title>{{ $entete->typeRapport }} — {{ $entete->raisonSociale }}</title>
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
  .text-emerald { color: #059669; }
  .text-slate { color: #64748b; }

  .rc-pied { position: fixed; bottom: -10mm; left: 0; right: 0; font-size: 7.5pt; color: #94a3b8; border-top: 1px solid #e2e8f0; padding-top: 4px; }
  .rc-pied td { border: none; padding: 0; }
  .rc-pied .rc-pagination:after { content: counter(page) " / " counter(pages); }

  @include('pdf.partials.entete-rapport-styles')
</style>
</head>
<body>


  {{-- Pied NEUTRE : raison sociale et pagination seulement. Un document remis
       au client ne porte ni visa ni pied de rapport interne (PA-194). --}}
  <div class="rc-pied">
    <table style="width: 100%;"><tr>
      <td class="text-left">{{ $entete->raisonSociale }}</td>
      <td class="text-right">Page <span class="rc-pagination"></span></td>
    </tr></table>
  </div>

  {{-- En-tête RG-19 : identité de ReportHeaderService, puis titre (le relevé),
       période (le client), auteur, heure. --}}
  @include('pdf.partials.entete-rapport')

  {{-- TABLEAU — encaissements ET relances, du plus récent au plus ancien --}}
  <table class="data-table">
    <thead>
      <tr>
        <th class="text-left" style="width: 20%;">Date</th>
        <th class="text-left" style="width: 20%;">Type</th>
        <th class="text-right" style="width: 60%;">Montant</th>
      </tr>
    </thead>
    <tbody>
      @forelse ($paiements as $paiement)
        <tr>
          <td class="text-left text-slate">{{ $paiement->date_paiement?->format('d/m/Y') }}</td>
          <td class="text-left font-bold">Encaissement</td>
          <td class="text-right text-emerald font-bold">{{ number_format((float) $paiement->montant, 0, ',', ' ') }} FCFA</td>
        </tr>
      @empty
      @endforelse
      @forelse ($relances as $relance)
        <tr>
          <td class="text-left text-slate">{{ $relance->date_relance?->format('d/m/Y') }}</td>
          <td class="text-left font-bold">Relance</td>
          <td class="text-right font-bold">{{ number_format((float) $relance->montant_reclame, 0, ',', ' ') }} FCFA</td>
        </tr>
      @empty
      @endforelse
      @if ($paiements->isEmpty() && $relances->isEmpty())
        <tr>
          <td colspan="3" class="text-center text-slate">Aucun mouvement pour ce client.</td>
        </tr>
      @endif
    </tbody>
  </table>

</body>
</html>
