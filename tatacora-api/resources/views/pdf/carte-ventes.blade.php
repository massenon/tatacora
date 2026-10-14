{{--
    VENTES DU RAYON — document A4 de l'onglet « Ventes » des deux écrans de
    carte (bar M5, restaurant M4). Ajout du 03/09/2026, demande du Product
    Owner : l'onglet était livré sans export, et le bouton « Exporter » rendait
    la CARTE quel que soit l'onglet ouvert.

    ## Un seul document pour les deux rayons

    Même raison que `pdf/carte.blade.php` : `carte-module.js` l.7 refuse
    explicitement deux écrans jumeaux, « qui finiraient par diverger au premier
    ajustement ». Seul le titre change, et il vient du composant
    (`EcranDeCarte::libelleDesVentes()`, la clé de l'onglet).

    ## L'EN-TÊTE VIENT DE `ReportHeaderService`, jamais recopiée

    Le bloc d'identité passe par `pdf.partials.entete-etablissement`, la source
    unique du dossier : raison sociale, enseigne, adresse, téléphone, logo, IFU
    et RCCM. `RESPECT_TABLEAU_RAPPORT.md` §4 recense l'en-tête recopiée
    localement comme non-conformité n° 1 — et IFU/RCCM n'ont AUCUN repli : ils
    sont absents tant qu'ils ne sont pas renseignés, jamais un exemple de
    format, qui serait un faux identifiant fiscal sur un document remis.

    ⚠ Ce partiel ne fixe que le MARKUP : dompdf ne partage aucune feuille de
    style entre documents, donc les classes `tc-*` sont définies ci-dessous.

    ## Il DIT son filtre ET sa période (PA-119)

    Un export porte sur CE QUI EST AFFICHÉ. La ligne « Filtre » est écrite
    toujours, période comprise — même sans borne de dates, où elle vaut
    « Toutes les dates » : un journal de ventes sans période affichée laisserait
    supposer le mois courant, et c'est le premier chiffre qu'un comptable
    rapproche.

    ## Le total est CELUI DE L'ÉCRAN

    `$resume` est la phrase du compteur de l'écran, alimentée par
    `EcranDeCarte::totauxDesVentes()` — l'auteur unique. Les annulations
    restent listées (RG-02) avec leur statut, et hors du total : leur montant
    n'est pas de l'argent.

    ## « Stock actuel », et le document le répète

    `lignes_vente` ne garde aucune trace du stock au moment de l'encaissement.
    Le chiffre imprimé est celui du jour de l'ÉDITION ; `$aideStock` le dit,
    avec les mots de l'écran. Sans cette phrase, un lecteur du fichier la
    semaine suivante y verrait un relevé du jour de la vente.

    ## Paysage

    Neuf colonnes, dont un horodatage, un numéro de ticket et deux libellés :
    en portrait, les noms d'article se replient sur trois lignes.

    ## En-tête, signatures, pied (11/09/2026, PA-192 — Directive §6)

    L'en-tête de RAPPORT (`pdf.partials.entete-rapport`) remplace celui des
    pièces commerciales : son bloc titre porte le titre, la PÉRIODE,
    l'auteur et l'heure ; le filtre reste dit ci-dessous. Zone de signatures
    et pied de rapport, comme tout export.

    Variables : entete, titre, filtre, resume, entetes, lignes, aideStock.
--}}
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<title>{{ $titre }} — {{ __('pwa.marque') }}</title>
<style>
  @page { size: A4 landscape; margin: 12mm 10mm 16mm 10mm; }
  body { font-family: 'Helvetica', 'Arial', sans-serif; color: #262626; margin: 0; padding: 0; font-size: 9pt; }

  @include('pdf.partials.entete-rapport-styles')

  .filtre { font-size: 8pt; color: #14213D; background: #F8FAFC; border: 1px solid #E2E8F0;
            border-radius: 3px; padding: 2mm 2.5mm; margin-bottom: 2mm; }
  .resume { font-size: 9pt; font-weight: bold; color: #14213D; margin-bottom: 2mm; }
  .avertissement { font-size: 7.5pt; color: #78350F; background: #FFFBEB; border: 1px solid #FDE68A;
                   border-radius: 3px; padding: 2mm 2.5mm; margin-bottom: 4mm; }

  table.corps { width: 100%; border-collapse: collapse; }
  table.corps th { background: #14213D; color: #FFFFFF; font-size: 7.5pt; text-transform: uppercase;
                   letter-spacing: 0.04em; padding: 2mm 1.5mm; text-align: right; }
  table.corps th:first-child, table.corps th:nth-child(2), table.corps th:nth-child(3) { text-align: left; }
  table.corps td { padding: 1.8mm 1.5mm; border-bottom: 1px solid #F1F5F9; font-size: 8.5pt; text-align: right; }
  table.corps td:first-child, table.corps td:nth-child(2) { text-align: left; color: #475569; }
  table.corps td:nth-child(3) { text-align: left; font-weight: 500; color: #1e293b; }
  table.corps tr { page-break-inside: avoid; }
  table.corps tbody tr:nth-child(even) { background-color: #F8FAFC; }
  thead { display: table-header-group; }


</style>
</head>
<body>

  {{-- En-tête RG-19 : identité, puis titre, PÉRIODE, auteur, heure. --}}
  @include('pdf.partials.entete-rapport')

  {{-- PA-119 : le document DIT son filtre, toujours. --}}
  <p class="filtre"><strong>{{ __('carte_pwa.commun.ventes_doc_filtre') }} :</strong> {{ $filtre }}</p>

  {{-- Le compteur de l'écran, mot pour mot — annulations hors total (RG-02). --}}
  <p class="resume">{{ $resume }}</p>

  <p class="avertissement">{{ $aideStock }}</p>

  <table class="corps">
    <thead>
      <tr>
        @foreach ($entetes as $entetecolonne)
          <th>{{ $entetecolonne }}</th>
        @endforeach
      </tr>
    </thead>
    <tbody>
      @foreach ($lignes as $ligne)
        <tr>
          @foreach ($ligne as $cellule)
            <td>{{ $cellule }}</td>
          @endforeach
        </tr>
      @endforeach
    </tbody>
  </table>

  @include('pdf.partials.signatures')
  @include('pdf.partials.pied-rapport')

</body>
</html>
