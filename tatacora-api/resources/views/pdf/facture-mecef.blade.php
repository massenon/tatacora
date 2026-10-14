<!DOCTYPE html>
{{--
    FACTURE (M2) — document A4 du registre « Facturation & Caisse MECeF ».
    Maître : prototype_v2/pages/m2-facturation.html (registre réel l.90-140).

    ⚠ CE DOCUMENT EST LE PREMIER ÉTAT DE FACTURE GÉNÉRÉ CÔTÉ SERVEUR.
    `Facture::estCertificationDemonstration()` existait et était appelé ; ce
    qui manquait, c'était le papier où imprimer le filigrane (PA-124,
    troisième obligation ouverte). Il est ici.

    ⚠ LE FILIGRANE EST COMMANDÉ PAR `estCertifiee()`, JAMAIS PAR `estFigee()`.
    Les deux prédicats sont de sens opposé (PA-100) : une facture
    `MECEF-DEMO-` passée à `certifiee` par le job de rejeu EST figée, et n'a
    pourtant aucune valeur fiscale. Fonder le filigrane sur le cycle de vie le
    ferait disparaître de l'exact document qu'il doit marquer.

    ⚠ AUCUN CACHET FISCAL N'EST DESSINÉ. Le format du code MECeF n'est pas
    public (MECEF_INTEGRATION_SPEC.md §5) : l'emplacement est RÉSERVÉ et NOMMÉ,
    sans rien de scannable. En inventer un produirait un faux.

    ⚠ IFU ET RCCM SONT CONDITIONNELS — affichés SEULEMENT s'ils sont renseignés
    dans `parametres_systeme` (vides ici = ABSENTS, jamais un exemple de
    format, PA-101/PA-113). Jusqu'au 01/09/2026 ce document ne les affichait
    JAMAIS, même renseignés : l'en-tête était recopiée en dur plutôt que lue
    via `ReportHeaderService`, seule source qui les porte — corrigé par le
    partiel `pdf.partials.entete-etablissement` ci-dessous.

    ⚠ LES ENCAISSEMENTS ET LE RESTE DÛ sont lus depuis la relation
    `Facture::paiements` et `Facture::resteDu()` — jamais une seconde formule
    recrite ici : le modèle reste l'AUTORITÉ (PA-165).
--}}
<html lang="fr">
<head>
<meta charset="UTF-8">
<title>{{ __('facturation_pwa.document_titre') }} — {{ $entete->raisonSociale }}</title>
<style>
  @page { size: A4 portrait; margin: 12mm 12mm 15mm 12mm; }
  body {
    font-family: 'Helvetica', 'Arial', sans-serif;
    color: #1e293b;
    font-size: 9.5pt;
    margin: 0;
    padding: 0;
  }
  table { width: 100%; border-collapse: collapse; table-layout: fixed; }

  .filigrane {
    position: fixed;
    top: 40%;
    left: 0;
    right: 0;
    text-align: center;
    font-size: 34pt;
    font-weight: bold;
    color: #C62828;
    opacity: 0.12;
    letter-spacing: 3px;
    z-index: 0;
  }

  {{-- En-tête établissement — markup partagé, `pdf.partials.entete-etablissement`. --}}
  .tc-entete { margin-bottom: 14px; border-bottom: 3px solid #14213D; padding-bottom: 10px; }
  .tc-logo-cell { width: 70px; vertical-align: top; }
  .tc-logo-cell img { width: 60px; height: auto; }
  .tc-identite-cell { vertical-align: top; font-size: 8pt; color: #475569; line-height: 1.35; }
  .tc-raison-sociale { font-size: 11pt; font-weight: bold; color: #14213D; }
  .tc-enseigne { color: #64748b; font-size: 8.5pt; }
  .tc-coordonnees { margin-top: 2px; }
  .tc-mentions-legales { margin-top: 2px; }
  .tc-meta-cell { width: 240px; vertical-align: top; text-align: right; font-size: 8.5pt; color: #475569; }
  .tc-titre-document { font-size: 14pt; font-weight: bold; color: #14213D; text-transform: uppercase; }

  .encaissements { margin-top: 16px; font-size: 8.5pt; }
  .encaissements .titre { font-weight: bold; color: #14213D; margin-bottom: 4px; }
  .encaissements .ligne-annulee { color: #94a3b8; text-decoration: line-through; }
  .recap-reste td { padding: 3px 0; }
  .recap-reste .total td {
    font-weight: bold;
    border-top: 2px solid #14213D;
    padding-top: 6px;
    font-size: 11pt;
    color: #14213D;
  }

  .bloc-client { margin-bottom: 14px; font-size: 9pt; line-height: 1.5; }

  .data-table { margin-top: 8px; }
  .data-table thead th {
    background-color: #14213D;
    color: #ffffff;
    font-size: 8pt;
    font-weight: bold;
    text-transform: uppercase;
    padding: 6px 5px;
    border: 1px solid #14213D;
  }
  .data-table tbody td {
    padding: 6px 5px;
    border-bottom: 1px solid #e2e8f0;
    font-size: 8.5pt;
    word-wrap: break-word;
  }

  .recap { margin-top: 14px; width: 300px; margin-left: auto; font-size: 9pt; }
  .recap td { padding: 3px 0; }
  .recap .total td {
    font-weight: bold;
    border-top: 2px solid #14213D;
    padding-top: 6px;
    font-size: 11pt;
    color: #14213D;
  }

  .mention {
    margin-top: 16px;
    border: 1px solid #F5C6C6;
    background: #FDECEC;
    color: #C62828;
    padding: 8px 10px;
    font-size: 8pt;
    line-height: 1.4;
  }
  .cachet {
    margin-top: 14px;
    border: 1px dashed #94a3b8;
    color: #64748b;
    padding: 14px 10px;
    font-size: 8pt;
    text-align: center;
    line-height: 1.4;
  }
  .avoirs { margin-top: 16px; font-size: 8.5pt; }
  .avoirs .titre { font-weight: bold; color: #14213D; margin-bottom: 4px; }

  .text-left { text-align: left; }
  .text-right { text-align: right; }
  .text-center { text-align: center; }

  .footer {
    position: fixed;
    bottom: -10mm;
    left: 0;
    right: 0;
    height: 10mm;
    font-size: 7.5pt;
    color: #94a3b8;
    border-top: 1px solid #e2e8f0;
    padding-top: 4px;
  }
  .pagenum:before { content: counter(page); }
</style>
</head>
<body>

  {{-- FILIGRANE RETIRÉ le 01/09/2026 — décision du Product Owner : « on
       enlève le filigrane de démonstration, on passe au réel ». La facture
       est un document commercial réel remis au client pendant l'attente de
       l'inscription MECeF (PA-17). Ce qui RESTE dérivé et affiché, jamais
       tu : la mention de certification (« en attente ») dans le bloc MECeF —
       imprimer un document muet sur ce point laisserait croire à une
       certification qui n'a pas eu lieu (PA-61). Aucun QR n'est inventé. --}}

  <div class="footer">
    <table>
      <tr>
        <td class="text-left">{{ __('pwa.marque') }}</td>
        <td class="text-right">Page <span class="pagenum"></span></td>
      </tr>
    </table>
  </div>

  {{-- Passage au RÉEL (01/09/2026, décision PO) : un numéro « MECEF-DEMO-… »
       n'apparaît JAMAIS sur un document remis — tant que la certification
       réelle n'a pas eu lieu, la facture porte sa référence interne, stable
       et unique (année + tête d'UUID). Le numéro MECeF réel prendra sa place
       au premier document certifié. Article 7 : « — » quand la donnée
       n'existe pas. --}}
  @include('pdf.partials.entete-etablissement', [
      'entete' => $entete,
      'titreDocument' => __('facturation_pwa.document_titre'),
      'numeroLabel' => __('facturation_pwa.document_numero'),
      'numero' => $facture->estCertifiee()
          ? $facture->numero_mecef
          : 'FAC-'.$facture->date_emission->format('Y').'-'.strtoupper(substr((string) $facture->id, 0, 8)),
      'dateLabel' => __('facturation_pwa.document_date'),
      'date' => $facture->date_emission->format('d/m/Y'),
      'auteurLabel' => __('facturation_pwa.document_etabli_par'),
      'auteur' => $auteur,
  ])

  <div class="bloc-client">
    <strong>{{ __('facturation_pwa.document_client') }} :</strong>
    {{ $client === null
        ? \App\Pwa\Support\MontantFcfa::TIRET
        : trim(($client->prenom ?? '').' '.($client->nom ?? '')) }}
  </div>

  <table class="data-table">
    <thead>
      <tr>
        <th class="text-left" style="width: 42%;">{{ __('facturation_pwa.document_col_designation') }}</th>
        <th class="text-left" style="width: 16%;">{{ __('facturation_pwa.document_col_activite') }}</th>
        <th class="text-center" style="width: 10%;">{{ __('facturation_pwa.document_col_quantite') }}</th>
        <th class="text-right" style="width: 16%;">{{ __('facturation_pwa.document_col_prix') }}</th>
        <th class="text-right" style="width: 16%;">{{ __('facturation_pwa.document_col_montant') }}</th>
      </tr>
    </thead>
    <tbody>
      @foreach ($facture->lignes as $ligne)
        <tr>
          <td class="text-left">{{ $ligne->libelle }}</td>
          <td class="text-left">{{ $activites[$ligne->source_module] ?? $ligne->source_module }}</td>
          <td class="text-center">{{ $ligne->quantite }}</td>
          <td class="text-right">{{ \App\Pwa\Support\MontantFcfa::format((string) $ligne->prix_unitaire) }}</td>
          <td class="text-right">{{ \App\Pwa\Support\MontantFcfa::format((string) $ligne->montant) }}</td>
        </tr>
      @endforeach
    </tbody>
  </table>

  <table class="recap">
    <tr>
      <td class="text-left">{{ __('facturation_pwa.document_total_ht') }}</td>
      <td class="text-right">{{ \App\Pwa\Support\MontantFcfa::format((string) $facture->montant_ht) }}</td>
    </tr>
    <tr>
      <td class="text-left">{{ __('facturation_pwa.document_tva') }}</td>
      <td class="text-right">{{ \App\Pwa\Support\MontantFcfa::format((string) $facture->montant_tva) }}</td>
    </tr>
    <tr class="total">
      <td class="text-left">{{ __('facturation_pwa.document_total_ttc') }}</td>
      <td class="text-right">{{ \App\Pwa\Support\MontantFcfa::format((string) $facture->montant_ttc) }}</td>
    </tr>
  </table>

  @if ($facture->avoirs->isNotEmpty())
    {{-- RG-03 : l'avoir ne modifie PAS la facture — il la neutralise, et les
         deux pièces coexistent. Le net est donc affiché EN PLUS du TTC,
         jamais à sa place. --}}
    <div class="avoirs">
      <div class="titre">{{ __('facturation_pwa.document_avoirs') }}</div>
      @foreach ($facture->avoirs as $avoir)
        <div>
          {{ __('facturation_pwa.document_avoir_ligne', [
              'date' => $avoir->date_emission->format('d/m/Y'),
              'motif' => $avoir->motif,
          ]) }}
          — <strong>{{ \App\Pwa\Support\MontantFcfa::format((string) $avoir->montant) }}</strong>
        </div>
      @endforeach
      <div style="margin-top: 6px;">
        <strong>{{ __('facturation_pwa.document_net') }} :
          {{ \App\Pwa\Support\MontantFcfa::format($net) }}</strong>
      </div>
    </div>
  @endif

  @if ($facture->paiements->isNotEmpty())
    {{--
        Encaissements — PA-165. Un paiement `annule` (PA-168) reste AFFICHÉ,
        jamais masqué : le journal doit dire ce qui a eu lieu, y compris une
        correction. Il est simplement rendu barré, comme le fait le journal
        des ventes pour une vente annulée (`historique-ventes.html`).

        ⚠ Le total ci-dessus n'inclut PAS les paiements annulés — c'est
        cohérent avec `Facture::SQL_PAIEMENTS_RECUS`, qui les compte
        actuellement SANS filtrer sur `statut` (constaté le 01/09/2026,
        hors périmètre de ce lot : voir `Facture::resteDu()`). Cette liste ne
        réécrit AUCUNE formule — elle affiche les paiements du modèle tels
        quels, dans l'ordre où ils ont eu lieu.
    --}}
    <div class="encaissements">
      <div class="titre">{{ __('facturation_pwa.document_encaissements') }}</div>
      @foreach ($facture->paiements->sortBy('date_paiement') as $paiement)
        <div class="{{ $paiement->statut === 'annule' ? 'ligne-annulee' : '' }}">
          @if ($paiement->statut === 'annule')
            {{ __('facturation_pwa.document_encaissement_ligne_annulee', [
                'date' => $paiement->date_paiement->format('d/m/Y'),
                'mode' => $modesPaiement[$paiement->mode_paiement] ?? $paiement->mode_paiement,
                'motif' => $paiement->motif_annulation,
            ]) }}
          @else
            {{ __('facturation_pwa.document_encaissement_ligne', [
                'date' => $paiement->date_paiement->format('d/m/Y'),
                'mode' => $modesPaiement[$paiement->mode_paiement] ?? $paiement->mode_paiement,
            ]) }}
          @endif
          — <strong>{{ \App\Pwa\Support\MontantFcfa::format((string) $paiement->montant) }}</strong>
        </div>
      @endforeach
    </div>
  @endif

  <table class="recap-reste">
    <tr class="total">
      <td class="text-left">{{ __('facturation_pwa.document_reste_du') }}</td>
      <td class="text-right">{{ \App\Pwa\Support\MontantFcfa::format($resteDu) }}</td>
    </tr>
  </table>

  {{--
      Directive PO du 02/09/2026 : « Emplacement réservé au cachet fiscal
      MECeF » et sa phrase « Aucun cachet n'est imprimé… » ne s'impriment
      PLUS tant que l'API MECeF n'est pas configurée. L'emplacement ne
      revient que le jour où `etatConfiguration()` dit `active` — DÉRIVÉ du
      client réellement lié (PA-61), jamais une constante. La mention
      d'attente ci-dessous, elle, RESTE : elle est honnête.
  --}}
  @if (\App\Domain\Facturation\Providers\MecefServiceProvider::etatConfiguration() === 'active')
    <div class="cachet">
      <strong>{{ __('facturation_pwa.document_cachet_reserve') }}</strong><br>
      {{ __('facturation_pwa.document_cachet_absent') }}
    </div>
  @endif

  @unless ($facture->estCertifiee())
    {{-- Mention DÉRIVÉE, discrète — plus jamais le pavé « démonstration »
         (passage au réel, 01/09/2026). Se taire tout à fait laisserait
         croire à une certification qui n'a pas eu lieu (PA-61). --}}
    <div class="mention">{{ __('facturation_pwa.document_mention_attente') }}</div>
  @endunless

</body>
</html>
