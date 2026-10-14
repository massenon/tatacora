{{--
    ZONE DE SIGNATURES des PDF d'export — `Directive.txt` §6.2 (l.416),
    décision de mise en conformité du Product Owner du 11/09/2026 (PA-192).

    Par défaut, les deux visas de la directive, au mot : « Visa Ordonnateur /
    Caissier » et « Visa Direction / Contrôle ». Un document dont le circuit
    nomme d'autres signataires (magasinier, responsable achats…) passe les
    siens :

        @include('pdf.partials.signatures', ['visas' => [__('…'), __('…')]])

    ⚠ JAMAIS sur un document REMIS À UN CLIENT (confirmation de réservation,
    facture, ticket, relevé) : un « Visa Ordonnateur » y ferait croire à une
    pièce d'ordonnancement interne. La directive vise les exports.

    Styles : `pdf.partials.entete-rapport-styles`.
--}}
@php($visas = $visas ?? [
    __('rapports.signatures.visa_ordonnateur'),
    __('rapports.signatures.visa_direction'),
])
<table class="er-signatures">
    <tr>
        @foreach ($visas as $visa)
            <td>
                <strong>{{ $visa }} :</strong><br><br><br>
                __________________________________________
            </td>
        @endforeach
    </tr>
</table>
