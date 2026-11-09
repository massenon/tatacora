{{--
    EN-TÊTE DE RAPPORT — SOURCE UNIQUE de l'en-tête de tout PDF d'EXPORT et de
    tout état M14 (RG-19, `DIRECTIVE_EXPORT_PDF.md` §2).

    Extrait le 11/09/2026 de `rapports/document`, qui en était l'unique
    porteur, pour la mise en conformité des PDF d'export décidée par le
    Product Owner (PA-192) : dix-neuf gabarits écrivaient « TATACORA
    AFRIQUE » à la main, ou n'avaient aucune identité. Deux blocs, dans
    l'ordre de la directive :

      1. l'identité de l'établissement — logo, raison sociale, enseigne et
         localisation, promoteur, adresse, téléphone et courriel, WhatsApp,
         site ; IFU / RCCM / régime fiscal SEULEMENT s'ils sont renseignés,
         jamais un exemple de format (§1) ;
      2. le bloc titre — type de rapport, période réellement filtrée, auteur
         réellement connecté et sa fonction, date et heure d'édition.

    Variable attendue : `$entete` — \App\Shared\ReportEngine\Data\EnTeteRapport,
    produit par le SEUL `ReportHeaderService::genererEnTete()`. Aucun champ ne
    se passe à la main.

    Styles : `pdf.partials.entete-rapport-styles`, inclus dans le <style> du
    document.

    ⚠ DISTINCT de `pdf.partials.entete-etablissement`, l'en-tête des pièces
    COMMERCIALES (facture, ticket) : un numéro de pièce à la place du bloc
    titre. Même identité, lue au même service.
--}}
<table class="er-entete" width="100%">
    <tr>
        @if ($entete->logo !== null)
            <td width="60"><img class="er-logo" src="{{ $entete->logo }}" alt=""></td>
        @endif
        <td>
            <p class="er-raison-sociale">{{ $entete->lignesIdentite()[0] }}</p>
            {{-- Les cinq lignes d'identité, UNE fois (EnTeteRapport::lignesIdentite, décision du PO du 10/11/2026). --}}
            <div class="er-coordonnees">
                @foreach (array_slice($entete->lignesIdentite(), 1) as $ligne)
                    {{ $ligne }}<br>
                @endforeach
            </div>
        </td>
    </tr>
</table>

<table class="er-bloc-titre" width="100%">
    <tr>
        <td><span class="er-type-rapport">{{ $entete->typeRapport }}</span></td>
        <td align="right"><span class="er-periode">{{ $entete->periode }}</span></td>
    </tr>
    <tr>
        <td colspan="2">
            <div class="er-edition">
                {{ __('rapports.entete.genere_par', ['auteur' => $entete->auteur]) }}<br>
                {{ __('rapports.entete.edite_le', ['date' => $entete->dateEdition]) }}
            </div>
        </td>
    </tr>
</table>
