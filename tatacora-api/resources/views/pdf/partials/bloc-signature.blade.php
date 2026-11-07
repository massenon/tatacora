{{--
    BLOC SIGNATURE — source unique des documents A4 (facture et proforma), PO du 07/11/2026.
    Attend : $entete (EnTeteRapport). Rend RIEN quand l'interrupteur « Afficher la signature et le
    cachet sur les factures » est sur Non : ni nom, ni fonction, ni images. Jamais sur un ticket.
--}}
@php($blocSignature = app(\App\Domain\Facturation\Services\BlocSignature::class)->donnees())
@if ($blocSignature !== null)
  <table style="width: 100%; margin-top: 18px; page-break-inside: avoid;">
    <tr>
      <td style="width: 55%;"></td>
      <td style="width: 45%; text-align: center; font-size: 9.5pt;">
        <div style="font-weight: bold;">{{ __('facturation_pwa.signature_pour', ['entreprise' => mb_strtoupper($entete->raisonSociale)]) }}</div>
        <div style="height: 80px; margin: 4px 0;">
          @if ($blocSignature['signature'] !== null)
            <img src="{{ $blocSignature['signature'] }}" alt="" style="max-height: 70px; max-width: 150px;">
          @endif
          @if ($blocSignature['cachet'] !== null)
            <img src="{{ $blocSignature['cachet'] }}" alt="" style="max-height: 75px; max-width: 110px; margin-left: 6px;">
          @endif
        </div>
        @if (filled($blocSignature['nom']))
          <div style="font-weight: bold;">{{ $blocSignature['nom'] }}</div>
        @endif
        @if (filled($blocSignature['fonction']))
          <div>{{ $blocSignature['fonction'] }}</div>
        @endif
      </td>
    </tr>
  </table>
@endif
