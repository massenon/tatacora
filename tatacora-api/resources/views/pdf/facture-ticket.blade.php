{{--
    TICKET DE VENTE — le document transactionnel unitaire (PA-101).

    ## Ticket et facture sont DEUX documents, pas deux formats du meme

    `05_MODULE_SPECIFICATIONS.md` §M14 distingue le document transactionnel
    unitaire — emis depuis l'ecran du module au moment de l'operation — de la
    facture normalisee MECeF (UC-07), qui porte le cachet fiscal et se classe.
    Ce gabarit rend le PREMIER. Il porte donc « TICKET DE VENTE », et il DIT
    qu'il ne vaut pas facture : ecrire « FACTURE » sur un papier sans numero
    MECeF, sans IFU et sans cachet, puis le remettre a un client, ce serait
    produire un faux document fiscal (meme raisonnement que PA-113).

    ## Aucun cachet fiscal n'est INVENTE

    Le format du QR MECeF n'est pas public (`MECEF_INTEGRATION_SPEC.md` §5).
    L'emplacement est donc RESERVE et NOMME, sans rien de scannable : imprimer
    un carre de demonstration donnerait a un client un code qui ne renvoie a
    rien, sur un papier qu'il conservera.

    ## IFU et RCCM sont CONDITIONNELS — affiches SEULEMENT s'ils sont
    renseignes dans `parametres_systeme`

    Jusqu'au 01/09/2026 ce gabarit ne les affichait JAMAIS, meme renseignes :
    l'entete ecrivait « TATACORA AFRIQUE » et son adresse EN DUR au lieu de
    lire `ReportHeaderService` (RG-19), seule source qui les porte. Corrige
    par le partiel `pdf.partials.entete-etablissement`, partage avec
    `facture-mecef.blade.php`.
--}}
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<title>{{ __('pos_pwa.document.ticket_titre') }} — {{ __('pwa.marque') }}</title>
<style>
  @page { size: A4 portrait; margin: 12mm 12mm 15mm 12mm; }
  body {
    font-family: 'Helvetica', 'Arial', sans-serif;
    color: #1e293b;
    margin: 0;
    padding: 0;
    font-size: 9.5pt;
  }
  {{-- En-tête établissement — markup partagé, `pdf.partials.entete-etablissement`. --}}
  .tc-entete { display: table; width: 100%; border-bottom: 3px solid #14213D; padding-bottom: 12px; margin-bottom: 16px; }
  .tc-logo-cell { display: table-cell; width: 60px; vertical-align: top; }
  .tc-logo-cell img { width: 50px; height: auto; }
  .tc-identite-cell { display: table-cell; vertical-align: top; }
  .tc-meta-cell { display: table-cell; vertical-align: top; text-align: right; }
  .tc-raison-sociale { color: #14213D; font-size: 16pt; font-weight: bold; }
  .tc-enseigne { color: #64748b; font-size: 9.5pt; }
  .tc-coordonnees { font-size: 9pt; margin-top: 2px; color: #64748b; }
  .tc-mentions-legales { font-size: 8pt; color: #64748b; margin-top: 2px; }
  .tc-titre-document { font-size: 14pt; font-weight: bold; color: #14213D; }
  .tc-poste { font-size: 9pt; color: #64748b; }
  table.donnees { width: 100%; border-collapse: collapse; margin: 16px 0; }
  table.donnees th {
    background: #14213D; color: #ffffff; text-align: left;
    padding: 7px 8px; font-size: 8.5pt; text-transform: uppercase;
  }
  table.donnees td { padding: 7px 8px; border-bottom: 1px solid #e2e8f0; }
  .recap { margin-top: 16px; width: 300px; margin-left: auto; font-size: 9pt; }
  .recap div { display: table; width: 100%; padding: 3px 0; }
  .recap div span:first-child { display: table-cell; text-align: left; }
  .recap div span:last-child { display: table-cell; text-align: right; font-weight: bold; }
  .recap .total { font-weight: bold; border-top: 2px solid #14213D; padding-top: 6px; font-size: 11pt; color: #14213D; }
  .cachet {
    margin-top: 20px; width: 210px; height: 74px;
    border: 1px dashed #94a3b8; border-radius: 4px;
    color: #94a3b8; font-size: 7.5pt; text-align: center;
    padding-top: 22px;
  }
  .avertissement {
    margin-top: 14px; padding: 8px 10px;
    border: 1px solid #fcd34d; background: #fffbeb;
    color: #92400e; font-size: 8pt;
  }
  .footer {
    position: fixed; bottom: -10mm; left: 0; right: 0; height: 10mm;
    font-size: 7.5pt; color: #94a3b8; text-align: center;
    border-top: 1px solid #e2e8f0; padding-top: 4px;
  }
</style>
</head>
<body>

  <div class="footer">{{ __('pwa.marque') }} — {{ __('pwa.enseigne_courte') }}</div>

  @include('pdf.partials.entete-etablissement', [
      'entete' => $entete,
      'titreDocument' => __('pos_pwa.document.ticket_titre'),
      'numeroLabel' => __('pos_pwa.document.entete_numero'),
      'numero' => $vente->numero,
      'dateLabel' => __('pos_pwa.document.edite_le'),
      'date' => $quand,
      'auteurLabel' => __('pos_pwa.document.auteur'),
      'auteur' => $auteur,
  ])

  {{-- Le poste (et la table, le cas echeant) n'a pas de place dans le
       partiel partage — propre a la vente, il n'a pas de sens sur une
       facture A4. Ligne ajoutee juste en dessous, meme alignement. --}}
  <div class="tc-poste" style="text-align: right; margin: -10px 0 16px;">
    {{ __('pos_pwa.journal.colonne_poste') }} :
    <strong>{{ $vente->point_vente }}@if ($vente->table) · {{ $vente->table }}@endif</strong>
    {{-- MENTION CLIENT (PO 02/09/2026) — `ventes.client_mention`, un nom
         imprime, jamais une fiche client. Absente = pas de ligne. --}}
    @if (filled($vente->client_mention))
      <br>{{ __('pos_pwa.document.client') }} : <strong>{{ $vente->client_mention }}</strong>
    @endif
  </div>

  <table class="donnees">
    <thead>
      <tr>
        <th style="width: 40%;">{{ __('pos_pwa.document.colonne_designation') }}</th>
        <th style="width: 15%;">{{ __('pos_pwa.document.colonne_activite') }}</th>
        <th style="width: 10%; text-align: center;">{{ __('pos_pwa.document.colonne_quantite') }}</th>
        <th style="width: 17%; text-align: right;">{{ __('pos_pwa.document.colonne_prix') }}</th>
        <th style="width: 18%; text-align: right;">{{ __('pos_pwa.document.colonne_montant') }}</th>
      </tr>
    </thead>
    <tbody>
      @foreach ($vente->lignes as $ligne)
        <tr>
          <td>{{ $ligne->nom }}</td>
          <td>{{ \App\Domain\Ventes\Services\VenteService::MODULES[$ligne->module] ?? $ligne->module }}</td>
          <td style="text-align: center;">{{ $ligne->quantite }}</td>
          <td style="text-align: right;">{{ \App\Pwa\Support\MontantFcfa::format((string) $ligne->prix_unitaire) }}</td>
          <td style="text-align: right; font-weight: bold;">{{ \App\Pwa\Support\MontantFcfa::format((string) $ligne->montant) }}</td>
        </tr>
      @endforeach
    </tbody>
  </table>

  <div class="recap">
    {{-- La REMISE (PO 02/09/2026) est DERIVEE : lignes brutes − net encaisse
         (`Vente::remiseDeduite()`), jamais une colonne recopiee. --}}
    @if (bccomp($vente->remiseDeduite(), '0.00', 2) > 0)
      <div>
        <span>{{ __('pos_pwa.document.remise') }}</span>
        <span>- {{ \App\Pwa\Support\MontantFcfa::format($vente->remiseDeduite()) }}</span>
      </div>
    @endif
    <div class="total">
      {{-- Le libelle DIT ce qui s'est passe : une note de chambre n'est pas un
           encaissement, c'est une creance reglee au depart du client. --}}
      <span>{{ $vente->encaisse
          ? __('pos_pwa.document.total_encaisse')
          : __('pos_pwa.document.total_porte_en_note') }}</span>
      <span style="color: #B8891E;">{{ \App\Pwa\Support\MontantFcfa::format((string) $vente->montant_total) }}</span>
    </div>
    <div style="margin-top: 4px; font-size: 8pt; color: #64748b;">
      <span>{{ __('pos_pwa.document.reglement') }}</span>
      <span>{{ \App\Domain\Ventes\Services\VenteService::MODES_PAIEMENT[$vente->mode_paiement] ?? $vente->mode_paiement }}</span>
    </div>
  </div>

  @if ($vente->estAnnulee())
    <div class="avertissement">
      {{ __('pos_pwa.journal.detail_annulee', [
          'motif' => $vente->motif_annulation ? ' — ' . $vente->motif_annulation : '',
      ]) }}
    </div>
  @endif

  {{--
      Directive PO du 02/09/2026 : ni l'emplacement du cachet fiscal ni la
      mention « Document transactionnel unitaire. Ne vaut pas facture
      normalisée » ne s'impriment tant que MECeF n'est pas configurée. Le
      retour est commandé par `etatConfiguration() === 'active'` — DÉRIVÉ du
      client réellement lié (PA-61), jamais une constante ni la simple
      présence d'une clé.
  --}}
  @if (\App\Domain\Facturation\Providers\MecefServiceProvider::etatConfiguration() === 'active')
    {{-- PA-101 — emplacement RESERVE et NOMME, sans rien de scannable. --}}
    <div class="cachet">{{ __('pos_pwa.document.mecef_reserve') }}</div>

    <div class="avertissement">{{ __('pos_pwa.document.ticket_mention') }}</div>
  @endif

</body>
</html>
