<!DOCTYPE html>
{{--
    REGISTRE DES CLIENTS ET CRÉANCES — document A4 de l'écran « Clients &
    Créances » (M3). Maître : prototype_v2/pages/m3-clients-creances.html
    (boutons d'export l.64-65, fusionnés — dérogation PO du 01/09/2026,
    rappelée le 02/09/2026, voir `DerogationsMaquette` export_bouton_unique).

    ⚠ PA-119 : l'export porte sur CE QUI EST AFFICHÉ, et il DIT son filtre —
    la ligne « Périmètre » ci-dessous. Sans elle, quelqu'un qui filtre puis
    exporte enverrait au comptable un document qu'il croit exhaustif.

    ⚠ L'IDENTITÉ DE L'ÉTABLISSEMENT VIENT DE `ReportHeaderService`
    (`$entete`, {@see \App\Shared\ReportEngine\Services\ReportHeaderService}),
    jamais recopiée en dur : c'est la dérive que RG-19 existe pour empêcher
    (`RESPECT_TABLEAU_RAPPORT.md` §4, non-conformité n° 1). IFU et RCCM sont
    CONDITIONNELS — absents tant qu'ils ne sont pas renseignés, jamais un
    exemple de format.

    ⚠ Les lignes sont EXACTEMENT `SoldeClientService::registre()` filtré comme
    l'écran — la même source que `ClientsCreancesExport` (branche Excel de la
    même modale). Le solde est CALCULÉ (PA-126), jamais lu d'une colonne.

    ## En-tête, signatures, pied (11/09/2026, PA-192 — Directive §6)

    Le bloc d'identité recopié ici (classes `tc-*`, sans le site ni le
    courriel) cède la place au partiel de RAPPORT, source unique ; zone de
    signatures et pied de rapport, comme tout export.
--}}
<html lang="fr">
<head>
<meta charset="UTF-8">
<title>{{ __('pwa.clients.export_document') }} — {{ __('pwa.marque') }}</title>
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

  {{-- PA-119 — le document DIT son filtre. --}}
  <div class="filtre">{{ __('pwa.clients.export_sous_titre', ['filtre' => $filtre]) }}</div>

  <table class="data-table">
    <thead>
      <tr>
        <th class="text-left" style="width: 30%;">{{ __('pwa.clients.col_client') }}</th>
        <th class="text-left" style="width: 20%;">{{ __('pwa.clients.col_telephone') }}</th>
        <th class="text-left" style="width: 20%;">{{ __('pwa.clients.col_type') }}</th>
        <th class="text-right" style="width: 20%;">{{ __('pwa.clients.col_solde') }}</th>
        <th class="text-center" style="width: 10%;">{{ __('pwa.clients.col_pieces') }}</th>
      </tr>
    </thead>
    <tbody>
      @foreach ($lignes as $ligne)
        @php($nom = trim($ligne->nom.' '.($ligne->prenom ?? '')))
        <tr>
          <td class="text-left">{{ $nom !== '' ? $nom : \App\Pwa\Support\MontantFcfa::TIRET }}</td>
          <td class="text-left">{{ $ligne->telephone !== '' ? $ligne->telephone : \App\Pwa\Support\MontantFcfa::TIRET }}</td>
          <td class="text-left">{{ \App\Pwa\Livewire\Crm\ClientsCreances::TYPES_CLIENT[$ligne->type_client] ?? $ligne->type_client }}</td>
          <td class="text-right">{{ \App\Pwa\Support\MontantFcfa::format($ligne->solde) }}</td>
          <td class="text-center">{{ $ligne->pieces }}</td>
        </tr>
      @endforeach
    </tbody>
    <tfoot>
      <tr>
        <td class="text-left" colspan="3">{{ __('pwa.clients.dettes_total') }}</td>
        <td class="text-right">{{ \App\Pwa\Support\MontantFcfa::format($total) }}</td>
        <td></td>
      </tr>
    </tfoot>
  </table>

  @include('pdf.partials.signatures')
  @include('pdf.partials.pied-rapport')

</body>
</html>
