{{--
    PIED DE RAPPORT — mention institutionnelle, date et heure d'édition,
    pagination. La grille `RESPECT_TABLEAU_RAPPORT.md` l'exige sur tout état
    (date/heure d'édition + pagination ; la mention « Projet PAEB — Cabinet FAGUEZ SARL » est RETIRÉE, décision du PO du 10/11/2026).

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
            <td>{{ __('rapports.entete.edite_le', ['date' => $entete->dateEdition]) }}</td>
            <td align="right"><span class="er-pagination"></span></td>
        </tr>
    </table>
</div>
