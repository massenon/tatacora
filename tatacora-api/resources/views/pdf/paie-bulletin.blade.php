{{--
    BULLETIN DE PAIE SUR PAPIER A4 — M13.

    Maitre : `prototype_v2/pages/m13-paie.js`, modale `modale-bulletin`.

    ## Ce document n'invente AUCUN montant

    Tout vient de `$recapitulatif`, calcule par `BulletinPaieService` sur les
    colonnes FIGEES a l'etablissement. Le papier ne recalcule rien : un
    bulletin reimprime six mois plus tard doit porter les memes chiffres que
    celui qui a ete remis.

    ## Le cout employeur est une FOURCHETTE, y compris sur le papier (PA-53)

    Le taux CNSS de risques professionnels est « 1 % a 4 % selon l'activite »
    et n'est pas confirme pour l'hotellerie-restauration. Un chiffre unique
    imprime sur un document conserve deviendrait la reference d'une
    declaration sociale. La note du maitre est reprise mot pour mot.

    ## Aucun IFU, aucun RCCM, aucun cachet

    Ce n'est pas une facture : rien de fiscal n'y figure. Le meme raisonnement
    que PA-113 — imprimer un identifiant fiscal d'exemple sur un document remis
    serait produire un faux.
--}}
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<title>{{ __('rh_pwa.bulletin_entete') }} — {{ $entete->raisonSociale }}</title>
<style>
  @page { size: A4 portrait; margin: 12mm 12mm 16mm 12mm; }
  body { font-family: 'Helvetica', 'Arial', sans-serif; font-size: 9pt; color: #1e293b; margin: 0; }
  table { width: 100%; border-collapse: collapse; }
  .entete { border-bottom: 2px solid #14213D; padding-bottom: 8px; margin-bottom: 12px; }
  .etablissement { font-size: 11pt; font-weight: bold; color: #14213D; }
  .ville { font-size: 8pt; color: #64748b; }
  .doc-titre { font-size: 12pt; font-weight: bold; color: #14213D; text-align: right; }
  .doc-meta { font-size: 8.5pt; color: #475569; text-align: right; }
  .encart { background-color: #f8fafc; border: 1px solid #e2e8f0; padding: 6px 8px; font-size: 8.5pt; }
  .encart-titre { font-size: 7.5pt; text-transform: uppercase; color: #64748b; font-weight: bold; }
  .lignes th { background-color: #f1f5f9; font-size: 7.5pt; text-transform: uppercase; color: #64748b;
               padding: 5px 4px; text-align: right; }
  .lignes th.g { text-align: left; }
  .lignes td { padding: 5px 4px; border-bottom: 1px solid #e2e8f0; font-size: 8.5pt; text-align: right; }
  .lignes td.g { text-align: left; }
  .sous-total td { background-color: #f1f5f9; font-weight: bold; }
  .total-fort td { background-color: #14213D; color: #ffffff; font-weight: bold; }
  .patronales { background-color: #FFFBEB; border: 1px solid #FDE68A; padding: 8px; margin-top: 12px; }
  .patronales td { color: #78350F; padding: 2px 0; font-size: 8.5pt; }
  .rouge { color: #7F1D1D; font-weight: bold; }
  .note { font-size: 7.5pt; color: #78350F; margin-top: 6px; }
  .pied { font-size: 7.5pt; color: #94a3b8; text-align: center; margin-top: 14px; }
  .annule { color: #dc2626; font-weight: bold; }
</style>
</head>
<body>

  <table class="entete">
    <tr>
      <td>
        {{-- Identité de `ReportHeaderService` (RG-19, source unique — PA-194) :
             elle était lue de deux clés de langue, une seconde copie de la
             raison sociale que la correction des paramètres n'atteignait pas.
             Ces clés restent celles de la modale d'écran. --}}
        <div class="etablissement">{{ $entete->raisonSociale }}</div>
        @if (filled($entete->enseigne))
          <div class="ville">{{ $entete->enseigne }}</div>
        @endif
        <div class="ville">{{ $entete->adresse }} · {{ $entete->telephone }}</div>
      </td>
      <td>
        <div class="doc-titre">{{ __('rh_pwa.bulletin_entete') }}</div>
        <div class="doc-meta">{{ $periodeLongue }}</div>
        <div class="doc-meta">{{ $bulletin->numero }}</div>
      </td>
    </tr>
  </table>

  <table>
    <tr>
      <td style="width:50%; padding-right:6px;">
        <div class="encart">
          <div class="encart-titre">{{ __('rh_pwa.bulletin_salarie') }}</div>
          <strong>{{ $bulletin->employe->nomComplet() }}</strong><br>
          {{ $bulletin->employe->poste }}<br>
          {{ __('rh_pwa.bulletin_matricule', ['valeur' => $bulletin->employe->matricule ?? '—']) }}<br>
          {{ __('rh_pwa.bulletin_cnss', ['valeur' => $bulletin->employe->sansNumeroCnss() ? __('rh_pwa.bulletin_cnss_absent') : $bulletin->employe->numero_cnss]) }}
        </div>
      </td>
      <td style="width:50%; padding-left:6px;">
        <div class="encart">
          <div class="encart-titre">{{ __('rh_pwa.bulletin_affectation') }}</div>
          {{ $bulletin->employe->service?->libelle ?? '—' }}<br>
          {{ __('rh_pwa.bulletin_etabli_le', ['date' => optional($bulletin->date_creation ?? $bulletin->created_at)->format('d/m/Y')]) }}
          @if ($bulletin->estAnnule())
            <div class="annule">{{ __('rh_pwa.bulletin_annule', ['motif' => $bulletin->motif_annulation]) }}</div>
          @endif
        </div>
      </td>
    </tr>
  </table>

  <table class="lignes" style="margin-top:12px;">
    <thead>
      <tr>
        <th class="g">{{ __('rh_pwa.col_designation') }}</th>
        <th>{{ __('rh_pwa.col_base') }}</th>
        <th>{{ __('rh_pwa.col_taux') }}</th>
        <th>{{ __('rh_pwa.col_gain') }}</th>
        <th>{{ __('rh_pwa.col_retenue') }}</th>
      </tr>
    </thead>
    <tbody>
      <tr class="sous-total">
        <td class="g" colspan="3">{{ __('rh_pwa.bulletin_brut') }}</td>
        <td>{{ \App\Pwa\Support\MontantFcfa::format($recapitulatif['brut']) }}</td>
        <td></td>
      </tr>
      <tr>
        <td class="g">{{ __('rh_pwa.bulletin_cnss_salariale') }}</td>
        <td>{{ \App\Pwa\Support\MontantFcfa::format($recapitulatif['brut']) }}</td>
        <td></td>
        <td></td>
        <td>{{ \App\Pwa\Support\MontantFcfa::format($recapitulatif['cnss_salarie']) }}</td>
      </tr>
      <tr class="sous-total">
        <td class="g" colspan="3">{{ __('rh_pwa.bulletin_imposable') }}</td>
        <td>{{ \App\Pwa\Support\MontantFcfa::format($recapitulatif['revenu_imposable']) }}</td>
        <td></td>
      </tr>
      <tr>
        <td class="g">{{ __('rh_pwa.bulletin_its') }}</td>
        <td colspan="3"></td>
        <td>{{ \App\Pwa\Support\MontantFcfa::format($recapitulatif['its']) }}</td>
      </tr>
      @if (bccomp($recapitulatif['autres_retenues'], '0.00', 2) > 0)
        <tr>
          <td class="g">{{ __('rh_pwa.bulletin_autres') }}</td>
          <td colspan="3"></td>
          <td>{{ \App\Pwa\Support\MontantFcfa::format($recapitulatif['autres_retenues']) }}</td>
        </tr>
      @endif
      <tr class="total-fort">
        <td class="g" colspan="3">{{ __('rh_pwa.bulletin_net') }}</td>
        <td colspan="2">{{ \App\Pwa\Support\MontantFcfa::format($recapitulatif['net_a_payer']) }}</td>
      </tr>
    </tbody>
  </table>

  <div class="patronales">
    <div class="encart-titre" style="color:#78350F;">{{ __('rh_pwa.bulletin_patronales') }}</div>
    <table>
      <tr>
        <td>{{ __('rh_pwa.livre_total_confirmees') }}</td>
        <td style="text-align:right;"><strong>{{ \App\Pwa\Support\MontantFcfa::format($recapitulatif['patronales_confirmees']) }}</strong></td>
      </tr>
      <tr>
        <td class="rouge">{{ __('rh_pwa.bulletin_rp') }}</td>
        <td class="rouge" style="text-align:right;">
          {{ \App\Pwa\Support\MontantFcfa::format($recapitulatif['rp_min']) }}
          — {{ \App\Pwa\Support\MontantFcfa::format($recapitulatif['rp_max']) }}
        </td>
      </tr>
      <tr>
        <td><strong>{{ __('rh_pwa.bulletin_cout_total') }}</strong></td>
        <td style="text-align:right;"><strong>
          {{ \App\Pwa\Support\MontantFcfa::format($recapitulatif['cout_min']) }}
          — {{ \App\Pwa\Support\MontantFcfa::format($recapitulatif['cout_max']) }}
        </strong></td>
      </tr>
    </table>
    <p class="note">{!! __('rh_pwa.bulletin_note_rp') !!}</p>
  </div>

  <p class="pied">{{ __('rh_pwa.bulletin_pied') }} — {{ $auteur ?? '—' }}</p>

</body>
</html>
