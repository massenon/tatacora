{{--
    RAPPORT PDF DU TABLEAU DE BORD (M11).

    Maître : `prototype_v2/pages/tableau-de-bord.html` (modale « Générer un
    rapport »). Rendu par `App\Pwa\Livewire\Accueil::exporterPdf()`, dompdf
    (PA-47 — pur PHP, cPanel mutualisé interdit les binaires).

    ## CE DOCUMENT N'EST PAS UNE FACTURE, ET IL NE PORTE AUCUNE MENTION FISCALE

    Ni IFU, ni RCCM, ni cachet MECeF, ni QR : au Bénin une facture est
    normalisée, et imprimer un identifiant fiscal d'exemple sur un document
    remis produirait un FAUX (PA-101, PA-113). Le titre dit ce que c'est — un
    état de gestion interne.

    ## En-tête, signatures, pied (11/09/2026, PA-192 (a) / PA-194 — Directive §6)

    L'identité était écrite ici à la main (« TATACORA AFRIQUE — GÎTE CHEZ
    NOËL ») : elle vient désormais de `pdf.partials.entete-rapport`
    (`ReportHeaderService`, RG-19, source unique), dont le bloc titre porte le
    titre, la période, l'auteur et l'heure.

    ⚠ Une version antérieure avait RETIRÉ la zone de signatures, et le disait :
    « un tableau de bord n'est ni ordonnancé ni validé ». Le Product Owner a
    tranché le 11/09/2026 que TOUT export PDF tient la Directive §6, zone de
    signatures comprise : elle est rétablie avec les visas de la directive, au
    mot. Le motif ancien reste vrai sur le fond — le paragraphe de pied dit
    toujours que ce document ne vaut pas facture —, mais il ne décide plus.

    Variables : `entete` (EnTeteRapport), `titre`, `entetes`, `lignes`.
--}}
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <title>{{ $titre }} — {{ $entete->raisonSociale }}</title>
    <style>
        @page { margin: 12mm 12mm 18mm 12mm; }
        /* dompdf ne charge aucune police distante : DejaVu Sans est intégrée,
           et c'est la seule qui couvre les accents ET l'espace insécable des
           montants. Sans elle, « Dépenses » sort en « DÃ©penses ». */
        body { font-family: 'DejaVu Sans', sans-serif; font-size: 10px; color: #1f2937; }
        table { width: 100%; border-collapse: collapse; margin-top: 8px; }
        th { background: #14213D; color: #ffffff; text-align: left; padding: 5px 6px; font-size: 9px; }
        td { border-bottom: 1px solid #e2e8f0; padding: 5px 6px; }
        td.nombre { text-align: right; }
        .pied { margin-top: 18px; font-size: 8px; color: #6b7280; }
        @include('pdf.partials.entete-rapport-styles')
    </style>
</head>
<body>
    {{-- En-tête RG-19 : identité, puis titre, période, auteur, heure. --}}
    @include('pdf.partials.entete-rapport')

    <table>
        <thead>
            <tr>
                @foreach ($entetes as $index => $colonne)
                    <th @if ($index > 0) class="nombre" @endif>{{ $colonne }}</th>
                @endforeach
            </tr>
        </thead>
        <tbody>
            @foreach ($lignes as $ligne)
                <tr>
                    @foreach ($ligne as $index => $cellule)
                        <td @if ($index > 0) class="nombre" @endif>{{ $cellule }}</td>
                    @endforeach
                </tr>
            @endforeach
        </tbody>
    </table>

    {{-- PA-119 : un export DIT son filtre. Sans cette ligne, deux exports de
         deux périodes différentes seraient indiscernables une fois imprimés. --}}
    <p class="pied">
        Document de gestion interne — il ne vaut pas facture et ne porte aucune
        mention fiscale. Les chiffres portent sur la période indiquée ci-dessus
        et sur elle seule.
    </p>

    @include('pdf.partials.signatures')
    @include('pdf.partials.pied-rapport')
</body>
</html>
