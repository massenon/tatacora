<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<title>{{ $titre }} — {{ $entete->raisonSociale }}</title>
<style>
  @page {
    size: A4 portrait;
    margin: 16mm 14mm 18mm 14mm;
  }
  body {
    font-family: 'Helvetica', 'Arial', sans-serif;
    color: #262626;
    margin: 0;
    padding: 0;
    font-size: 10pt;
  }
  .entete {
    display: table;
    width: 100%;
    border-bottom: 2px solid #14213D;
    padding-bottom: 6mm;
    margin-bottom: 6mm;
  }
  .entete-gauche {
    display: table-cell;
    vertical-align: top;
  }
  .entete-droite {
    display: table-cell;
    vertical-align: top;
    text-align: right;
  }
  .etab {
    font-size: 14pt;
    font-weight: bold;
    color: #14213D;
  }
  .coord {
    font-size: 8pt;
    color: #555555;
    line-height: 1.4;
    margin-top: 2mm;
  }
  .titre {
    font-size: 12pt;
    font-weight: bold;
    color: #B8891E;
    text-transform: uppercase;
  }
  .genere {
    font-size: 8pt;
    color: #777777;
    margin-top: 1mm;
  }
  .groupe {
    margin-bottom: 6mm;
    page-break-inside: avoid;
  }
  .groupe h2 {
    font-size: 10pt;
    font-weight: bold;
    color: #14213D;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    border-bottom: 1px solid #E5E5E5;
    padding-bottom: 1.5mm;
    margin: 0 0 2.5mm 0;
    page-break-after: avoid;
  }
  table {
    width: 100%;
    border-collapse: collapse;
  }
  td {
    padding: 1.8mm 0;
    vertical-align: baseline;
    font-size: 9.5pt;
  }
  tr {
    border-bottom: 1px dashed #F1F5F9;
    page-break-inside: avoid;
  }
  .nom {
    font-weight: 500;
    color: #1e293b;
  }
  .prix {
    text-align: right;
    white-space: nowrap;
    font-weight: bold;
    color: #14213D;
    width: 35mm;
  }
  .avert {
    font-size: 8pt;
    color: #B45309;
    margin-top: 4mm;
    background-color: #FFFBEB;
    border: 1px solid #FDE68A;
    padding: 2.5mm;
    border-radius: 4px;
  }
  /*
    PA-161 (b) — les deux marques de prix, SUR LE PAPIER REMIS AU CLIENT.

    Mêmes couleurs qu'à l'écran (carte-module.js l.108-109) : rouge semi-gras
    pour « prix provisoire », ambre normal pour « corrigé à la main ». Elles
    sont sous le prix, à droite, pour qu'on ne puisse pas lire le montant sans
    les voir. Un prix provisoire imprimé sans sa marque devient un tarif ferme.
  */
  .marque-provisoire {
    display: block;
    font-size: 7pt;
    font-weight: bold;
    color: #DC2626;
    text-transform: none;
  }
  .marque-corrige {
    display: block;
    font-size: 7pt;
    color: #B45309;
  }
  .footer {
    position: fixed;
    bottom: -10mm;
    left: 0;
    right: 0;
    height: 10mm;
    font-size: 7.5pt;
    color: #94a3b8;
    border-top: 1px solid #e2e8f0;
    padding-top: 2mm;
    text-align: center;
  }
</style>
</head>
<body>

  <div class="footer">
    Tous les prix sont exprimés en FCFA, taxes comprises · {{ $entete->raisonSociale }} · Document édité le {{ $quand }}
  </div>

  {{-- Identité de `ReportHeaderService` (RG-19, source unique — PA-194) :
       elle était écrite ici à la main, adresse et téléphone compris. Document
       affiché au comptoir et remis au client : ni visa ni pied de rapport. --}}
  <div class="entete">
    <div class="entete-gauche">
      <div class="etab">{{ $entete->raisonSociale }}</div>
      <div class="coord">
        @if (filled($entete->enseigne)){{ $entete->enseigne }}<br>@endif
        {{ $entete->adresse }} | Tél : {{ $entete->telephone }}
      </div>
    </div>
    <div class="entete-droite">
      <div class="titre">{{ $titre }}</div>
      <div class="genere">Générée le {{ $quand }}</div>
      <div class="genere">{{ $total }} article(s) · Prix exprimés en FCFA</div>
    </div>
  </div>

  @foreach ($groupes as $g)
    <div class="groupe">
      {{-- ⚠ CE TITRE ETAIT RENDU « 2. Locale ».

           La balise `<h2>` avait perdu ses chevrons a l'ecriture : le gabarit
           `.groupe h2` ci-dessus, avec sa capitale, son filet et son
           `page-break-after: avoid`, ne s'appliquait a rien, et chaque
           categorie de la fiche REMISE AU CLIENT s'imprimait « 2. » suivi de
           son nom, en corps de texte. Le style existait, la balise non. --}}
      <h2>{{ $g['libelle'] }}</h2>
      <table>
        @foreach ($g['articles'] as $art)
          <tr>
            <td>
              <div class="nom">{{ $art->libelle }}</div>
            </td>
            {{-- `number_format((float) …)` faisait passer un `DECIMAL(15,2)`
                 par un flottant sur le document remis au client. Le formatage
                 des montants a un point unique dans ce dépôt. --}}
            <td class="prix">{{ \App\Pwa\Support\MontantFcfa::format((string) $art->prix_vente) }}
              {{-- ⚠ ÉCART ASSUMÉ AVEC LE MAÎTRE, et c'est le cœur de
                   PA-161 (b) : `assets/js/fiche-prix.js` n'imprime aucune
                   marque. Six boissons figurent ici à un tarif INVENTÉ, posé
                   faute de relevé et appliqué à de vrais clients à chaque
                   service. L'imprimer sans le dire en ferait un prix ferme,
                   opposable au comptoir — la version papier de PA-61. --}}
              @if ($art->prix_provisoire)
                <span class="marque-provisoire">{{ __('carte_pwa.fiche_prix_marque_provisoire') }}</span>
              @endif
              @if ($art->prix_corrige_main)
                <span class="marque-corrige">{{ __('carte_pwa.fiche_prix_marque_corrige_main') }}</span>
              @endif
            </td>
          </tr>
        @endforeach
      </table>
    </div>
  @endforeach

  @if ($sansPrix > 0)
    <div class="avert">
      <strong>Attention :</strong> {{ $sansPrix }} article(s) sans tarif ne figurent pas sur cette fiche. Un tarif manquant doit être renseigné avant d'être proposé au client.
    </div>
  @endif

  @php
      // PA-161 (b) — le nombre de tarifs provisoires réellement IMPRIMÉS sur
      // cette fiche, compté sur les groupes rendus et non sur le référentiel :
      // un avertissement portant sur des lignes absentes du papier enverrait
      // chercher ce qui n'y est pas.
      $provisoiresImprimes = 0;

      foreach ($groupes as $groupeCompte) {
          foreach ($groupeCompte['articles'] as $articleCompte) {
              if ($articleCompte->prix_provisoire) {
                  $provisoiresImprimes++;
              }
          }
      }
  @endphp

  @if ($provisoiresImprimes > 0)
    <div class="avert">
      <strong>Attention :</strong> {{ __('carte_pwa.fiche_prix_avertissement_provisoire', ['nombre' => $provisoiresImprimes]) }}
    </div>
  @endif

</body>
</html>