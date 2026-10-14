{{--
    TICKET DE CAISSE 80 mm — TROISIÈME papier de la MÊME pièce (PA-101).

    `05_MODULE_SPECIFICATIONS.md` §M14 : ticket et facture sont DEUX
    documents. Cette vue rend la MÊME vente que `pdf.facture-ticket` (A4) et
    que le ticket téléchargé en PDF depuis le point de vente — mêmes lignes
    figées, même total, même règlement — sur un TROISIÈME papier : celui du
    rouleau thermique du comptoir. Décision du Product Owner du 01/09/2026,
    en attendant la validation de l'API MECeF par la Direction des impôts.

    Servie par `App\Pwa\Http\Controllers\TicketThermiqueController` — voir
    son docblock pour pourquoi un contrôleur plutôt qu'un composant Livewire.
    Route GET dédiée, LECTURE SEULE : `ForcerLectureSeule` la laisse passer
    (GET), `module:M5,L` la protège comme le reste du point de vente.

    Aucun cachet fiscal n'est inventé (MECEF_INTEGRATION_SPEC.md §5) : le
    format du QR n'est pas public, l'emplacement est réservé et NOMMÉ, sans
    rien de scannable. Le pied de page se dérive d'un fait structurel du
    schéma (voir `pos_pwa.document.ticket_thermique_pied`), jamais figé.

    Impression : `window.print()` au chargement — la fenêtre EST le ticket,
    rien d'autre n'y est affiché hors le bouton de secours (masqué à
    l'impression par `.no-print`), pour le cas où le navigateur bloque
    l'ouverture automatique de la boîte de dialogue.
--}}
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<title>{{ __('pos_pwa.document.ticket_titre') }} — {{ $vente->numero }}</title>
<style>
  @page { size: 80mm auto; margin: 3mm; }
  * { box-sizing: border-box; }
  html, body {
    margin: 0;
    padding: 0;
    width: 80mm;
    font-family: 'Courier New', Courier, monospace;
    font-size: 10.5px;
    line-height: 1.35;
    color: #111827;
    background: #f1f5f9;
  }
  body { padding: 2mm; }

  .tc-entete { text-align: center; margin-bottom: 2mm; }
  .tc-raison-sociale { font-size: 13px; font-weight: bold; text-transform: uppercase; }
  .tc-enseigne { font-size: 10px; }
  .tc-coordonnees { font-size: 9.5px; margin-top: 1mm; }
  .tc-mentions-legales { font-size: 9px; margin-top: 1mm; }
  .tc-titre-document { font-size: 11.5px; font-weight: bold; margin-top: 2mm; letter-spacing: 1px; }
  .tc-meta-ligne { font-size: 9.5px; }

  .separateur { border-top: 1px dashed #111827; margin: 2mm 0; }

  .poste { text-align: center; font-size: 9.5px; margin-bottom: 1mm; }

  table.lignes { width: 100%; border-collapse: collapse; font-size: 9.5px; }
  table.lignes th { text-align: left; border-bottom: 1px dashed #111827; padding-bottom: 1mm; font-weight: bold; }
  table.lignes td { padding: 0.8mm 0; vertical-align: top; }
  table.lignes .col-qte { text-align: center; }
  table.lignes .col-montant { text-align: right; white-space: nowrap; }

  .recap { display: flex; justify-content: space-between; margin-top: 2mm; font-size: 12px; font-weight: bold; }
  .reglement { display: flex; justify-content: space-between; font-size: 9.5px; margin-top: 1mm; }

  .avertissement {
    margin-top: 2mm; padding: 1.5mm; border: 1px solid #111827;
    font-size: 9px; text-align: center;
  }
  .cachet {
    margin-top: 3mm; border: 1px dashed #94a3b8; padding: 2mm;
    text-align: center; font-size: 8.5px; color: #64748b;
  }
  .pied-mecef { margin-top: 2mm; font-size: 8.5px; text-align: center; color: #374151; }

  .barre-actions { text-align: center; margin-bottom: 3mm; }
  .barre-actions button {
    font-family: inherit; font-size: 11px; padding: 2mm 4mm;
    border: 1px solid #111827; background: #ffffff; border-radius: 2mm;
  }

  @media print {
    html, body { background: #ffffff; }
    .no-print { display: none; }
  }
</style>
</head>
<body>

  <div class="barre-actions no-print">
    <button type="button" onclick="window.print()">{{ __('pos_pwa.comptant.ticket_imprimer') }}</button>
  </div>

  @include('pdf.partials.entete-etablissement', [
      'entete' => $entete,
      'mono' => true,
      'titreDocument' => __('pos_pwa.document.ticket_titre'),
      'numeroLabel' => __('pos_pwa.document.entete_numero'),
      'numero' => $vente->numero,
      'dateLabel' => __('pos_pwa.document.edite_le'),
      'date' => $quand,
      'auteurLabel' => __('pos_pwa.document.auteur'),
      'auteur' => $entete->auteur,
  ])

  <div class="poste">
    {{ __('pos_pwa.journal.colonne_poste') }} :
    {{ $vente->point_vente }}@if ($vente->table) · {{ $vente->table }}@endif
  </div>

  {{-- MENTION CLIENT (PO 02/09/2026) — un nom imprime, jamais une fiche :
       `ventes.client_mention` (texte libre du comptoir). Absente = pas de
       ligne, comme IFU/RCCM. --}}
  @if (filled($vente->client_mention))
    <div class="poste">{{ __('pos_pwa.document.client') }} : {{ $vente->client_mention }}</div>
  @endif

  <div class="separateur"></div>

  {{-- ⚠ EXCLUE de la conversion navy du 01/09/2026 : ticket thermique 80mm
       (impression noir/blanc, PA-101) — l'imprimante n'a pas d'encre couleur,
       et un fond bleu nuit n'y a aucun sens. --}}
  <table class="lignes">
    <thead>
      <tr>
        <th>{{ __('pos_pwa.document.entete_article') }}</th>
        <th class="col-qte">{{ __('pos_pwa.document.entete_quantite') }}</th>
        <th class="col-montant">{{ __('pos_pwa.document.entete_montant') }}</th>
      </tr>
    </thead>
    <tbody>
      @foreach ($vente->lignes as $ligne)
        <tr>
          <td>{{ $ligne->nom }}</td>
          <td class="col-qte">{{ $ligne->quantite }}</td>
          <td class="col-montant">{{ \App\Pwa\Support\MontantFcfa::format((string) $ligne->montant) }}</td>
        </tr>
      @endforeach
    </tbody>
  </table>

  <div class="separateur"></div>

  {{-- La REMISE (PO 02/09/2026) est DERIVEE : lignes brutes − net encaisse
       (`Vente::remiseDeduite()`), jamais une colonne recopiee. --}}
  @if (bccomp($vente->remiseDeduite(), '0.00', 2) > 0)
    <div class="reglement">
      <span>{{ __('pos_pwa.document.remise') }}</span>
      <span>- {{ \App\Pwa\Support\MontantFcfa::format($vente->remiseDeduite()) }}</span>
    </div>
  @endif

  <div class="recap">
    {{-- Le libellé DIT ce qui s'est passé : une note de chambre n'est pas un
         encaissement, c'est une créance réglée au départ du client. --}}
    <span>{{ $vente->encaisse
        ? __('pos_pwa.document.total_encaisse')
        : __('pos_pwa.document.total_porte_en_note') }}</span>
    <span>{{ \App\Pwa\Support\MontantFcfa::format((string) $vente->montant_total) }}</span>
  </div>
  <div class="reglement">
    <span>{{ __('pos_pwa.document.reglement') }}</span>
    <span>{{ \App\Domain\Ventes\Services\VenteService::MODES_PAIEMENT[$vente->mode_paiement] ?? $vente->mode_paiement }}</span>
  </div>

  @if ($vente->estAnnulee())
    <div class="avertissement">
      {{ __('pos_pwa.journal.detail_annulee', [
          'motif' => $vente->motif_annulation ? ' — '.$vente->motif_annulation : '',
      ]) }}
    </div>
  @endif

  @if ($vente->aDesLignesSansImpactStock())
    <div class="avertissement">
      {{ __('pos_pwa.journal.detail_stock', [
          'nombre' => count($vente->stock_non_impacte),
          'articles' => implode(', ', array_column($vente->stock_non_impacte, 'ligne')),
      ]) }}
    </div>
  @endif

  {{--
      Directive PO du 02/09/2026 : l'emplacement du cachet fiscal ne
      s'imprime PLUS tant que MECeF n'est pas configurée — il ne revient que
      le jour où `etatConfiguration()` dit `active`, DÉRIVÉ du client
      réellement lié (PA-61), jamais une constante. La mention « en attente
      d'inscription » (pied) RESTE : elle est honnête aujourd'hui.
  --}}
  @if (\App\Domain\Facturation\Providers\MecefServiceProvider::etatConfiguration() === 'active')
    {{-- PA-101 — emplacement RÉSERVÉ et NOMMÉ, sans rien de scannable. --}}
    <div class="cachet">{{ __('pos_pwa.document.mecef_reserve') }}</div>
  @endif

  <div class="pied-mecef">{{ __('pos_pwa.document.ticket_thermique_pied') }}</div>

  <script>
    // Fenêtre d'impression dédiée (PA-101) : la boîte de dialogue s'ouvre
    // dès que la page est prête. `.no-print` masque le bouton de secours à
    // l'impression elle-même — il ne sert qu'au cas où le navigateur bloque
    // l'ouverture automatique.
    window.addEventListener('load', function () {
      window.print();
    });
  </script>

</body>
</html>
