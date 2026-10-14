{{--
    JOURNAL DES VENTES — document A4 imprimable.

    ## PA-119 — le document DIT son filtre

    Un export porte sur CE QUI EST AFFICHE. Quelqu'un qui filtre puis exporte
    attend son filtre ; lui rendre le registre entier lui ferait envoyer au
    comptable un document qu'il croit avoir verifie. La ligne « Filtre
    applique » est donc obligatoire — elle vaut « Aucun filtre » quand il n'y
    en a pas, jamais rien.

    ## Trois indicateurs, et le troisieme n'est pas un detail

    « Chiffre d'affaires » et « Encaisse » ne sont pas le meme montant : ce qui
    est porte en note de chambre est une CREANCE, pas de l'argent dans le
    tiroir. Les confondre ferait chercher un ecart de caisse qui n'existe pas.
--}}
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
<title>{{ __('pos_pwa.document.journal_titre') }} — {{ __('pwa.marque') }}</title>
<style>
  @page { size: A4 portrait; margin: 10mm 10mm 15mm 10mm; }
  body { font-family: 'Helvetica', 'Arial', sans-serif; font-size: 9pt; color: #1e293b; margin: 0; padding: 0; }
  table { width: 100%; border-collapse: collapse; table-layout: fixed; }


  .filtre {
    margin-bottom: 10px; padding: 6px 8px;
    background: #f8fafc; border: 1px solid #cbd5e1;
    font-size: 8pt; color: #475569;
  }

  .kpi-table { margin-bottom: 12px; }
  .kpi-box { border: 1px solid #cbd5e1; background-color: #f8fafc; padding: 6px; text-align: center; font-size: 7.5pt; }
  .kpi-value { font-size: 11pt; font-weight: bold; color: #14213D; margin-top: 2px; }

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

  .text-left { text-align: left; }
  .text-right { text-align: right; }
  .text-center { text-align: center; }
  .font-bold { font-weight: bold; }

  @include('pdf.partials.entete-rapport-styles')
</style>
</head>
<body>


  {{-- En-tête RG-19 : identité, puis titre, filtre, auteur, heure. --}}
  @include('pdf.partials.entete-rapport')

  {{-- PA-119 — le filtre est ECRIT, pas seulement applique. --}}
  <div class="filtre"><strong>{{ __('pos_pwa.document.filtre') }} :</strong> {{ $filtre }}</div>

  <table class="kpi-table">
    <tr>
      <td class="kpi-box">
        <div>{{ __('pos_pwa.journal.kpi_ca') }}</div>
        <div class="kpi-value">{{ \App\Pwa\Support\MontantFcfa::format($chiffreAffaires) }}</div>
      </td>
      <td class="kpi-box">
        <div>{{ __('pos_pwa.journal.kpi_encaisse') }}</div>
        <div class="kpi-value" style="color:#059669;">{{ \App\Pwa\Support\MontantFcfa::format($encaisse) }}</div>
      </td>
      <td class="kpi-box">
        <div>{{ __('pos_pwa.journal.kpi_note') }}</div>
        <div class="kpi-value" style="color:#B8891E;">{{ \App\Pwa\Support\MontantFcfa::format($porteEnNote) }}</div>
      </td>
      <td class="kpi-box">
        <div>{{ __('pos_pwa.journal.kpi_ventes') }}</div>
        <div class="kpi-value">{{ $ventes->count() }}</div>
      </td>
    </tr>
  </table>

  <table class="data-table">
    <thead>
      {{-- maitre — `historique-ventes.html` l.348 : les huit entetes de l'export. --}}
      <tr>
        <th class="text-left" style="width: 13%;">{{ __('pos_pwa.document.entete_numero') }}</th>
        <th class="text-left" style="width: 14%;">{{ __('pos_pwa.document.entete_date') }}</th>
        <th class="text-left" style="width: 14%;">{{ __('pos_pwa.document.entete_poste') }}</th>
        <th class="text-left" style="width: 11%;">{{ __('pos_pwa.document.entete_table') }}</th>
        <th class="text-left" style="width: 15%;">{{ __('pos_pwa.document.entete_reglement_export') }}</th>
        <th class="text-right" style="width: 13%;">{{ __('pos_pwa.document.entete_montant') }}</th>
        <th class="text-center" style="width: 10%;">{{ __('pos_pwa.document.entete_encaisse') }}</th>
        <th class="text-center" style="width: 10%;">{{ __('pos_pwa.document.entete_statut') }}</th>
      </tr>
    </thead>
    <tbody>
      @forelse ($ventes as $vente)
        <tr>
          <td class="text-left font-bold">{{ $vente->numero }}</td>
          <td class="text-left">{{ $vente->created_at?->format('d/m/Y H:i') }}</td>
          <td class="text-left">{{ $vente->point_vente }}</td>
          <td class="text-left">{{ $vente->table ?? '' }}</td>
          <td class="text-left">{{ \App\Domain\Ventes\Services\VenteService::MODES_PAIEMENT[$vente->mode_paiement] ?? $vente->mode_paiement }}</td>
          <td class="text-right font-bold">{{ \App\Pwa\Support\MontantFcfa::format((string) $vente->montant_total) }}</td>
          {{-- « Encaisse » n'est PAS « Montant » : une note de chambre est une
               creance, pas de l'argent dans le tiroir. --}}
          <td class="text-center">
            {{ $vente->encaisse
                ? __('pos_pwa.journal.badge_encaissee')
                : __('pos_pwa.journal.badge_note') }}
          </td>
          <td class="text-center">
            {{ $vente->estAnnulee()
                ? __('pos_pwa.journal.statut_annulees')
                : __('pos_pwa.journal.statut_validees') }}
          </td>
        </tr>
      @empty
        <tr>
          <td colspan="8" class="text-center">{{ __('pos_pwa.journal.liste_vide') }}</td>
        </tr>
      @endforelse
    </tbody>
  </table>

  @include('pdf.partials.signatures', ['visas' => [__('pos_pwa.document.visa_caisse'), __('pos_pwa.document.visa_direction')]])

  @include('pdf.partials.pied-rapport')
</body>
</html>
