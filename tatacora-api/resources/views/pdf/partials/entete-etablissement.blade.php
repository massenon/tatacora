{{--
    EN-TÊTE ÉTABLISSEMENT — SOURCE UNIQUE du bloc d'identité sur tout document
    COMMERCIAL imprimé par ce dossier : facture A4 (`pdf.facture-mecef`),
    ticket de vente A4 (`pdf.facture-ticket`) et ticket de caisse 80 mm
    (`pwa.pos.ticket-thermique`, hors `pdf/` mais MÊME papier — PA-101, deux
    documents d'une même pièce). Créé le 01/09/2026 : avant lui, `facture-
    mecef.blade.php` et `facture-ticket.blade.php` écrivaient chacun
    « TATACORA AFRIQUE » et son adresse EN DUR, dans deux fichiers, et
    n'affichaient JAMAIS IFU/RCCM même renseignés — la dérive que RG-19 existe
    pour empêcher (`RESPECT_TABLEAU_RAPPORT.md` §4 : « développeur pressé,
    plus simple de copier l'en-tête existante »).

    ⚠ DISTINCT de `resources/views/rapports/document.blade.php`, qui reste
    l'unique en-tête des ÉTATS du catalogue M14 (RG-19, `GenerateurEtatService`)
    — deux familles de documents, deux maîtres visuels (`m2-facturation.html` /
    le gabarit ticket contre le Hub Étatas), PAS deux sources concurrentes de
    la MÊME donnée : l'identité de l'entreprise (raison sociale, adresse,
    téléphone, IFU, RCCM, logo) vient ICI ENCORE de `ReportHeaderService`,
    jamais recopiée. IFU et RCCM n'ont AUCUN repli : absents tant qu'ils ne
    sont pas renseignés dans `parametres_systeme`, jamais un exemple de format
    (`DIRECTIVE_EXPORT_PDF.md` §1, MECEF_INTEGRATION_SPEC.md §5-§7).

    Variables attendues :
    - $entete         \App\Shared\ReportEngine\Data\EnTeteRapport (identité
                       entreprise — {@see ReportHeaderService::genererEnTete()})
    - $titreDocument   string — ex. "Facture", "TICKET DE VENTE"
    - $numeroLabel     string — déjà traduit
    - $numero          ?string — ou null, rendu en tiret
    - $dateLabel       string
    - $date            string — déjà formatée (d/m/Y)
    - $auteurLabel     string
    - $auteur          string
    - $mono            bool (défaut false) — ticket 80 mm : ni logo (chemin
                        `public_path()` de {@see ReportHeaderService}, valide
                        pour dompdf, PAS pour un `<img>` de navigateur — cette
                        variante ne l'utilise donc jamais), ni colonne méta
                        séparée : tout s'empile en une seule colonne étroite.

    Classes CSS `tc-*` — chaque document appelant définit LEUR rendu dans son
    propre `<style>` (dompdf ne partage aucune feuille externe entre documents
    séparés) ; ce partiel ne fixe que le MARKUP, jamais l'apparence.
--}}
@php($mono = $mono ?? false)

@if ($mono)
  <div class="tc-entete tc-entete--mono">
    {{-- Identité UNE fois (EnTeteRapport::lignesIdentite) — jamais d'enseigne ni de mention répétées. --}}
    <div class="tc-raison-sociale">{{ $entete->lignesIdentite()[0] }}</div>
    <div class="tc-coordonnees">@foreach (array_slice($entete->lignesIdentite(), 1) as $ligneIdentite){{ $ligneIdentite }}@if (! $loop->last)<br>@endif @endforeach</div>
    <div class="tc-titre-document">{{ $titreDocument }}</div>
    <div class="tc-meta-ligne">{{ $numeroLabel }} : {{ $numero ?? \App\Pwa\Support\MontantFcfa::TIRET }}</div>
    <div class="tc-meta-ligne">{{ $dateLabel }} : {{ $date }}</div>
    <div class="tc-meta-ligne">{{ $auteurLabel }} : {{ $auteur }}</div>
  </div>
@else
  <table class="tc-entete" width="100%">
    <tr>
      @if ($entete->logo !== null)
        <td class="tc-logo-cell"><img src="{{ $entete->logo }}" alt=""></td>
      @endif
      <td class="tc-identite-cell">
        {{-- Identité UNE fois (EnTeteRapport::lignesIdentite, décision du PO du 10/11/2026). --}}
        <div class="tc-raison-sociale">{{ $entete->lignesIdentite()[0] }}</div>
        <div class="tc-coordonnees">
          @foreach (array_slice($entete->lignesIdentite(), 1) as $ligneIdentite)
            {{ $ligneIdentite }}<br>
          @endforeach
        </div>
      </td>
      <td class="tc-meta-cell">
        <div class="tc-titre-document">{{ $titreDocument }}</div>
        <div>{{ $numeroLabel }} : <strong>{{ $numero ?? \App\Pwa\Support\MontantFcfa::TIRET }}</strong></div>
        <div>{{ $dateLabel }} : <strong>{{ $date }}</strong></div>
        <div>{{ $auteurLabel }} : <strong>{{ $auteur }}</strong></div>
      </td>
    </tr>
  </table>
@endif
