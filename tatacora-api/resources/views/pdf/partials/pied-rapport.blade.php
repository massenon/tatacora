{{--
    PIED DE RAPPORT — mention institutionnelle, date et heure d'édition,
    pagination. La grille `RESPECT_TABLEAU_RAPPORT.md` l'exige sur tout état
    (« mention PAEB/FAGUEZ SARL + date/heure d'édition »).

    Extrait le 11/09/2026 de `rapports/document`, avec l'en-tête (PA-192) :
    les PDF d'export n'avaient AUCUN pied conforme. Fixé en bas de chaque
    page par dompdf, qui substitue les numéros à l'impression.

    ⚠ Pas sur un document REMIS À UN CLIENT : une mention de cabinet de
    conseil n'a rien à faire sur une confirmation de réservation.

    Variable attendue : `$entete` — EnTeteRapport. Styles :
    `pdf.partials.entete-rapport-styles`.
--}}
<div class="er-pied">
    <table width="100%">
        <tr>
            <td>{{ $entete->mentionInstitutionnelle }}</td>
            <td align="right">
                {{ $entete->dateEdition }} — <span class="er-pagination"></span>
            </td>
        </tr>
    </table>
</div>
