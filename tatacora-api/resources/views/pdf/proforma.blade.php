<!DOCTYPE html>
{{--
    FACTURE PROFORMA — A4, document NON FISCAL (PO, 07/11/2026). Structure du modèle papier :
    en-tête (logo / activités / Facebook / e-mail / RCCM-IFU / Tel-Qtier / double filet), ville et date longue,
    titre, Réf., client, IFU, Tel, Objet, tableau à en-tête VERT, TOTAL, « Arrêté la présente… » en lettres
    sur lignes pointillées, bloc signature (interrupteur des Paramètres).

    ⚠ JAMAIS de numéro MECeF, de QR, de NIM, de mention de normalisation ni de « démonstration », quel que
    soit le mode de facturation : une proforma n'est pas une facture (ProformaPdfTest le mord).
    Variables : $proforma, $entete, $activites, $facebook, $vert.
--}}
@php
    use App\Domain\Facturation\Support\MiseEnPageProforma as Mep;
    use App\Domain\Facturation\Support\MontantEnLettres;
    $e = $entete;
    $date = $proforma->date_emission ?? now();
@endphp
<html lang="fr">
<head>
<meta charset="UTF-8">
<title>{{ __('proforma.titre') }} {{ $proforma->numero }}</title>
<style>
  @page { size: A4 portrait; margin: 12mm 14mm 14mm 14mm; }
  body { font-family: 'Helvetica', 'Arial', sans-serif; color: #111; font-size: 10pt; margin: 0; }
  table { width: 100%; border-collapse: collapse; }
  .entete td { vertical-align: top; }
  .entete .droite { text-align: right; font-size: 9pt; line-height: 1.45; }
  .activites { font-weight: bold; text-decoration: underline; }
  .filet { border-top: 1px solid #111; border-bottom: 1px solid #111; height: 2px; margin: 6px 0 12px; }
  .ville-date { text-align: right; margin-bottom: 8px; }
  .titre { text-align: center; font-size: 15pt; font-weight: bold; margin: 8px 0 12px; }
  .bloc p { margin: 3px 0; }
  .lignes { margin-top: 12px; }
  .lignes th { background: {{ $vert }}; color: #fff; padding: 6px 5px; border: 1px solid #111; font-size: 9pt; }
  .lignes td { padding: 6px 5px; border: 1px solid #111; font-size: 9.5pt; }
  .droite-texte { text-align: right; }
  .centre { text-align: center; }
  .total td { font-weight: bold; }
  .lettres { margin-top: 16px; }
  .pointilles { border-bottom: 1px dotted #111; min-height: 18px; padding: 4px 0; font-weight: bold; }
  .validite { margin-top: 10px; font-style: italic; }
</style>
</head>
<body>
  <table class="entete">
    <tr>
      <td style="width: 38%;">
        @if ($e->logo !== null)<img src="{{ $e->logo }}" alt="" style="max-height: 70px; max-width: 200px;">@endif
      </td>
      <td class="droite">
        @if (filled($activites))<div class="activites">{{ $activites }}</div>@endif
        @if (filled($facebook))<div>{{ __('proforma.facebook') }} : {{ $facebook }}</div>@endif
        @if (filled($e->email))<div>{{ __('proforma.email') }} : {{ $e->email }}</div>@endif
        @if (filled($e->rccm) || filled($e->ifu))
          <div>@if (filled($e->rccm)){{ __('proforma.rccm') }} : {{ $e->rccm }}@endif @if (filled($e->rccm) && filled($e->ifu)) – @endif @if (filled($e->ifu))N°IFU : {{ $e->ifu }}@endif</div>
        @endif
        <div>@if (filled($e->telephone)){{ __('proforma.telephone') }} : {{ $e->telephone }}@endif @if (filled($e->adresse)) / {{ __('proforma.qtier') }} : {{ $e->adresse }}@endif</div>
      </td>
    </tr>
  </table>
  <div class="filet"></div>

  <div class="ville-date">{{ filled($proforma->ville) ? $proforma->ville.', le ' : 'Le ' }}{{ Mep::dateLongue($date) }}</div>
  <div class="titre">{{ __('proforma.titre') }}</div>

  <div class="bloc">
    <p><strong>{{ __('proforma.reference') }} :</strong> {{ filled($proforma->numero) ? $proforma->numero : __('proforma.brouillon_mention') }}</p>
    <p><strong>{{ __('proforma.client') }} :</strong> {{ $proforma->client_nom }}</p>
    <p><strong>{{ __('proforma.ifu') }} :</strong> {{ $proforma->client_ifu }}</p>
    <p><strong>{{ __('proforma.telephone') }} :</strong> {{ $proforma->client_telephone }}</p>
    <p><strong>{{ __('proforma.objet') }} :</strong> {{ $proforma->objet }}</p>
  </div>

  <table class="lignes">
    <thead>
      <tr>
        <th style="width: 46%; text-align: left;">{{ __('proforma.designation') }}</th>
        <th style="width: 12%;">{{ __('proforma.quantite') }}</th>
        <th style="width: 21%;">{{ __('proforma.prix_unitaire') }}</th>
        <th style="width: 21%;">{{ __('proforma.montant') }}</th>
      </tr>
    </thead>
    <tbody>
      @foreach ($proforma->lignes as $ligne)
        <tr>
          <td>{{ $ligne->designation }}</td>
          <td class="centre">{{ $ligne->quantite }}</td>
          <td class="droite-texte">{{ Mep::montant($ligne->prix_unitaire) }}</td>
          <td class="droite-texte">{{ Mep::montant($ligne->montant) }}</td>
        </tr>
      @endforeach
      <tr class="total">
        <td colspan="3">{{ __('proforma.total') }}</td>
        <td class="droite-texte">{{ Mep::montant($proforma->total) }}</td>
      </tr>
    </tbody>
  </table>

  <div class="lettres">
    <div>{{ __('proforma.arrete') }}</div>
    <div class="pointilles">{{ MontantEnLettres::francsCfa($proforma->total) }}</div>
    <div class="pointilles">&nbsp;</div>
  </div>

  @if ($proforma->valide_jusqu_au !== null)
    <div class="validite">{{ __('proforma.valable_jusqu_au', ['date' => Mep::dateLongue($proforma->valide_jusqu_au)]) }}</div>
  @endif

  @include('pdf.partials.bloc-signature', ['entete' => $entete])
</body>
</html>
