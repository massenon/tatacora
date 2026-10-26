<!DOCTYPE html>
{{--
    ÉTATS DE CLÔTURE — le PDF de l'archive légale d'un exercice clôturé
    (`ArchiveClotureService`, lot 4, 20/10/2026) : balance générale, compte
    de résultat, bilan, et les pièces de clôture et d'à-nouveaux.

    Les états sont ceux d'AVANT le solde des comptes de gestion (journal CL
    exclu, `BalanceGeneraleService`) : le compte de résultat de l'exercice,
    pas un compte de résultat soldé à zéro.

    Son empreinte SHA-256 est notée dans `manifeste.json` ; il ne la porte pas
    lui-même (un fichier ne peut contenir sa propre empreinte).
--}}
<html lang="fr">
<head>
<meta charset="UTF-8">
<title>{{ __('comptabilite_pwa.archive_titre', ['annee' => $exercice->annee]) }} — {{ $entete->raisonSociale }}</title>
<style>
  @page { size: A4 portrait; margin: 10mm 10mm 15mm 10mm; }
  body { font-family: 'Helvetica', 'Arial', sans-serif; font-size: 8.5pt; color: #1e293b; margin: 0; padding: 0; }
  table { width: 100%; border-collapse: collapse; table-layout: fixed; }
  h2 { font-size: 11pt; color: #14213D; margin: 14px 0 4px 0; }
  .data-table { margin-top: 4px; }
  .data-table thead th {
    background-color: #14213D; color: #ffffff; font-size: 7.5pt; font-weight: bold;
    text-transform: uppercase; padding: 5px 4px; border: 1px solid #14213D;
  }
  .data-table tbody td { padding: 4px; border-bottom: 1px solid #e2e8f0; font-size: 8pt; word-wrap: break-word; overflow: hidden; }
  .data-table tfoot td { padding: 5px 4px; border-top: 2px solid #14213D; font-weight: bold; color: #14213D; }
  .solde td { font-weight: bold; background-color: #f1f5f9; }
  .text-left { text-align: left; }
  .text-right { text-align: right; }
  .saut { page-break-before: always; }
  @include('pdf.partials.entete-rapport-styles')
</style>
</head>
<body>
  @include('pdf.partials.entete-rapport')

  <h2>{{ __('comptabilite_pwa.archive_section_cloture') }}</h2>
  <table class="data-table">
    <tbody>
      <tr><td class="text-left" style="width: 40%;">{{ __('comptabilite_pwa.archive_cloturee_le') }}</td><td class="text-left">{{ $cloture->cloturee_le->format('d/m/Y H:i') }}</td></tr>
      <tr><td class="text-left">{{ __('comptabilite_pwa.archive_piece_cloture') }}</td><td class="text-left">{{ $cloture->piece_cloture ?? \App\Pwa\Support\MontantFcfa::TIRET }}</td></tr>
      <tr><td class="text-left">{{ __('comptabilite_pwa.archive_piece_a_nouveaux') }}</td><td class="text-left">{{ $cloture->piece_a_nouveaux ?? \App\Pwa\Support\MontantFcfa::TIRET }}</td></tr>
      <tr><td class="text-left">{{ __('comptabilite_pwa.archive_resultat') }}</td><td class="text-left">{{ \App\Pwa\Support\MontantFcfa::format((string) $cloture->resultat) }}</td></tr>
    </tbody>
  </table>

  <h2>{{ __('comptabilite_pwa.archive_section_balance') }}</h2>
  <table class="data-table">
    <thead>
      <tr>
        <th class="text-left" style="width: 12%;">{{ __('comptabilite_pwa.col_compte') }}</th>
        <th class="text-left" style="width: 36%;">{{ __('comptabilite_pwa.col_libelle_ligne') }}</th>
        <th class="text-right" style="width: 13%;">{{ __('comptabilite_pwa.col_debit') }}</th>
        <th class="text-right" style="width: 13%;">{{ __('comptabilite_pwa.col_credit') }}</th>
        <th class="text-right" style="width: 13%;">{{ __('comptabilite_pwa.archive_solde_debiteur') }}</th>
        <th class="text-right" style="width: 13%;">{{ __('comptabilite_pwa.archive_solde_crediteur') }}</th>
      </tr>
    </thead>
    <tbody>
      @foreach ($balance->lignes as $ligne)
        <tr>
          <td class="text-left">{{ $ligne->numeroCompte }}</td>
          <td class="text-left">{{ $ligne->libelle }}</td>
          <td class="text-right">{{ \App\Pwa\Support\MontantFcfa::formatOuTiret($ligne->totalDebit) }}</td>
          <td class="text-right">{{ \App\Pwa\Support\MontantFcfa::formatOuTiret($ligne->totalCredit) }}</td>
          <td class="text-right">{{ \App\Pwa\Support\MontantFcfa::formatOuTiret($ligne->soldeDebiteur) }}</td>
          <td class="text-right">{{ \App\Pwa\Support\MontantFcfa::formatOuTiret($ligne->soldeCrediteur) }}</td>
        </tr>
      @endforeach
    </tbody>
    <tfoot>
      <tr>
        <td colspan="2" class="text-right">{{ __('comptabilite_pwa.totaux') }}</td>
        <td class="text-right">{{ \App\Pwa\Support\MontantFcfa::format($balance->totalDebit) }}</td>
        <td class="text-right">{{ \App\Pwa\Support\MontantFcfa::format($balance->totalCredit) }}</td>
        <td class="text-right">{{ \App\Pwa\Support\MontantFcfa::format($balance->totalSoldeDebiteur) }}</td>
        <td class="text-right">{{ \App\Pwa\Support\MontantFcfa::format($balance->totalSoldeCrediteur) }}</td>
      </tr>
    </tfoot>
  </table>

  <h2 class="saut">{{ __('comptabilite_pwa.archive_section_resultat') }}</h2>
  <table class="data-table">
    <tbody>
      @foreach ($compteResultat->lignes as $ligne)
        <tr @class(['solde' => $ligne->estSolde])>
          <td class="text-left" style="width: 75%;">{{ $ligne->libelle }}</td>
          <td class="text-right">{{ \App\Pwa\Support\MontantFcfa::format($ligne->montant) }}</td>
        </tr>
      @endforeach
    </tbody>
    <tfoot>
      <tr>
        <td class="text-right">{{ __('comptabilite_pwa.archive_resultat') }}</td>
        <td class="text-right">{{ \App\Pwa\Support\MontantFcfa::format($compteResultat->resultatNet) }}</td>
      </tr>
    </tfoot>
  </table>

  <h2>{{ __('comptabilite_pwa.archive_section_bilan') }}</h2>
  <table class="data-table">
    <thead>
      <tr>
        <th class="text-left" style="width: 40%;">{{ __('comptabilite_pwa.archive_poste') }}</th>
        <th class="text-right" style="width: 20%;">{{ __('comptabilite_pwa.archive_brut') }}</th>
        <th class="text-right" style="width: 20%;">{{ __('comptabilite_pwa.archive_amortissement') }}</th>
        <th class="text-right" style="width: 20%;">{{ __('comptabilite_pwa.archive_net') }}</th>
      </tr>
    </thead>
    <tbody>
      @foreach ([...$bilan->actif, ...$bilan->passif] as $poste)
        <tr>
          <td class="text-left">{{ $poste->libelle }}</td>
          <td class="text-right">{{ \App\Pwa\Support\MontantFcfa::formatOuTiret($poste->brut) }}</td>
          <td class="text-right">{{ \App\Pwa\Support\MontantFcfa::formatOuTiret($poste->amortissement) }}</td>
          <td class="text-right">{{ \App\Pwa\Support\MontantFcfa::format($poste->net) }}</td>
        </tr>
      @endforeach
    </tbody>
    <tfoot>
      <tr>
        <td class="text-right">{{ __('comptabilite_pwa.archive_total_actif') }}</td>
        <td colspan="3" class="text-right">{{ \App\Pwa\Support\MontantFcfa::format($bilan->totalActif) }}</td>
      </tr>
      <tr>
        <td class="text-right">{{ __('comptabilite_pwa.archive_total_passif') }}</td>
        <td colspan="3" class="text-right">{{ \App\Pwa\Support\MontantFcfa::format($bilan->totalPassif) }}</td>
      </tr>
    </tfoot>
  </table>

  @include('pdf.partials.signatures', ['visas' => [__('comptabilite_pwa.archive_visa_comptable'), __('rapports.signatures.visa_direction')]])
  @include('pdf.partials.pied-rapport')
</body>
</html>
