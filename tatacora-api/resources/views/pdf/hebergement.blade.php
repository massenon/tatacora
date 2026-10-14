{{--
    DOCUMENTS IMPRIMÉS DE M1 — trois documents, un seul gabarit.

    Maîtres : `prototype_v2/pages/m1-hebergement.html` (le parc) et
    `prototype_v2/pages/reservations.html` (l'historique et le papier remis au
    client).

    ## ⚠ LE PAPIER REMIS À LA PRISE DE RÉSERVATION N'EST PAS UNE FACTURE (PA-113)

    Le maître titre son document « Facture ». Il n'a pourtant ni numéro, ni
    IFU, ni cachet, et son pied de page dit « prototype de démonstration ». Au
    Bénin, une facture est normalisée MECeF : imprimer « FACTURE » sur ce
    papier et le remettre à un client, ce serait produire un FAUX DOCUMENT
    FISCAL — la version papier de PA-61.

    Le document porte donc le titre « CONFIRMATION DE RÉSERVATION », et la
    mention « ne vaut pas facture » est au CORPS, là où on la lit, pas en pied
    de page. La modale de l'écran, elle, garde les mots du maître.

    Aucun cachet fiscal n'est inventé : le format du QR MECeF n'est pas public
    (`MECEF_INTEGRATION_SPEC.md` §5), et un carré scannable qui ne mène nulle
    part serait pire qu'un espace vide. IFU et RCCM sont conditionnels — vides
    ici, donc ABSENTS : imprimer un exemple de format sur un document remis
    serait un faux identifiant fiscal.

    ## Aucun montant de séjour n'est reconstitué (PA-55, PA-57)

    `reservations` ne porte que l'acompte. Les colonnes « Total » et
    « Reste dû » rendent le tiret que l'écran affiche — la même valeur, jamais
    un chiffre recalculé depuis la grille tarifaire courante, qui réécrirait le
    prix d'un séjour déjà vendu.

    ## En-tête et signatures (11/09/2026, PA-192 — Directive §6)

    L'en-tête vient de `pdf.partials.entete-rapport` (`ReportHeaderService`,
    RG-19) : il remplace le « TATACORA AFRIQUE » écrit ici à la main, et son
    bloc titre porte le titre, le filtre, l'auteur et l'heure — ce que le
    pied « auteur · quand » disait moins bien. Les deux EXPORTS (`parc`,
    `historique`) portent la zone de signatures de la directive ; la
    CONFIRMATION, remise au client, n'en porte pas — un « Visa Ordonnateur »
    sur un papier client ferait croire à une pièce d'ordonnancement.

    Variables communes : `document` (`parc` | `historique` | `confirmation`),
    `entete` (EnTeteRapport).
--}}
@php
    $tiret = '—';
    $document = $document ?? 'parc';
@endphp
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <title>{{ __('pwa.hebergement.titre') }}</title>
    <style>
        @page { margin: 18mm 14mm; }
        body { font-family: DejaVu Sans, sans-serif; font-size: 9.5pt; color: #14213D; }
        @include('pdf.partials.entete-rapport-styles')
        .filtre { font-size: 8.5pt; color: #64748B; margin: 0 0 10px; }
        table { width: 100%; border-collapse: collapse; }
        th { background: #14213D; color: #fff; font-size: 8pt; text-transform: uppercase;
             text-align: left; padding: 5px 6px; }
        td { border-bottom: 1px solid #E2E8F0; padding: 5px 6px; font-size: 9pt; }
        .droite { text-align: right; }
        .mention { border: 1px solid #B8891E; background: #FDF3E0; color: #8A6412;
                   padding: 8px 10px; margin: 12px 0; font-size: 9pt; }
        .paire td { font-size: 9.5pt; }
        .paire .cle { color: #64748B; width: 42%; }
    </style>
</head>
<body>

{{-- En-tête RG-19 : identité, puis titre, filtre, auteur et heure. IFU et
     RCCM n'y paraissent que s'ils sont renseignés — jamais un exemple. --}}
@include('pdf.partials.entete-rapport')

@if ($document === 'confirmation')

    {{-- La mention est au CORPS, pas en pied de page (PA-113). --}}
    <div class="mention">{{ __('hebergement_pwa.reservations.confirmation_mention') }}</div>

    <table class="paire">
        <tr>
            <td class="cle">{{ __('pwa.reservations.champ_client') }}</td>
            <td>{{ $reservation->client?->nomComplet() ?: $tiret }}</td>
        </tr>
        <tr>
            <td class="cle">{{ __('pwa.reservations.champ_unite') }}</td>
            <td>{{ $reservation->unite?->numero ?? $tiret }}
                @if ($reservation->unite?->categorie)
                    ({{ $reservation->unite->categorie->libelle }})
                @endif
            </td>
        </tr>
        <tr>
            <td class="cle">{{ __('pwa.reservations.champ_arrivee') }}</td>
            <td>{{ $reservation->date_arrivee->format('d/m/Y') }}</td>
        </tr>
        <tr>
            <td class="cle">{{ __('pwa.reservations.champ_depart') }}</td>
            <td>{{ $reservation->date_depart->format('d/m/Y') }}</td>
        </tr>
        <tr>
            <td class="cle">{{ __('pwa.reservations.hist_col_nuits') }}</td>
            <td>{{ $reservation->nombreNuitees() }}</td>
        </tr>
        <tr>
            <td class="cle">{{ __('pwa.reservations.champ_acompte') }}</td>
            <td>{{ \App\Pwa\Support\MontantFcfa::format((string) $reservation->acompte) }}</td>
        </tr>
        <tr>
            <td class="cle">{{ __('pwa.reservations.hist_col_etat') }}</td>
            <td>{{ $etat['libelle'] }}</td>
        </tr>
        {{-- « Total » et « Reste dû » : le schéma ne porte aucun montant de
             séjour, et le reconstituer réécrirait un prix déjà convenu. --}}
        <tr>
            <td class="cle">{{ __('pwa.reservations.hist_col_total') }}</td>
            <td>{{ $tiret }}</td>
        </tr>
        <tr>
            <td class="cle">{{ __('pwa.reservations.hist_col_reste') }}</td>
            <td>{{ $tiret }}</td>
        </tr>
    </table>

@elseif ($document === 'historique')

    {{-- PA-119 : le filtre est dit au bloc titre de l'en-tête ; les nuitées
         restent ici, c'est une mesure du document, pas son périmètre. --}}
    <p class="filtre">{{ __('pwa.reservations.hist_kpi_nuitees') }} : {{ $nuitees }}</p>

    <table>
        <thead>
        <tr>
            <th>{{ __('pwa.reservations.hist_col_client') }}</th>
            <th>{{ __('pwa.reservations.hist_col_sejour') }}</th>
            <th class="droite">{{ __('pwa.reservations.hist_col_nuits') }}</th>
            <th>{{ __('pwa.reservations.hist_col_unites') }}</th>
            <th>{{ __('pwa.reservations.hist_col_services') }}</th>
            <th class="droite">{{ __('pwa.reservations.hist_col_total') }}</th>
            <th class="droite">{{ __('pwa.reservations.hist_col_reste') }}</th>
            <th>{{ __('pwa.reservations.hist_col_etat') }}</th>
        </tr>
        </thead>
        <tbody>
        @foreach ($lignes as $ligne)
            <tr>
                <td>{{ $ligne->client?->nomComplet() ?: $tiret }}</td>
                <td>{{ $ligne->date_arrivee->format('d/m/Y') }} → {{ $ligne->date_depart->format('d/m/Y') }}</td>
                <td class="droite">{{ $ligne->nombreNuitees() }}</td>
                <td>{{ $ligne->unite?->numero ?? $tiret }}</td>
                <td>{{ __('hebergement_pwa.reservations.service_hebergement') }}</td>
                <td class="droite">{{ $tiret }}</td>
                <td class="droite">{{ $tiret }}</td>
                <td>{{ $etats[$ligne->id]['libelle'] ?? $tiret }}</td>
            </tr>
        @endforeach
        </tbody>
    </table>

    @include('pdf.partials.signatures')
    @include('pdf.partials.pied-rapport')

@else

    <table>
        <thead>
        <tr>
            <th>{{ __('hebergement_pwa.hebergement.champ_code') }}</th>
            <th>{{ __('hebergement_pwa.hebergement.champ_categorie') }}</th>
            <th class="droite">{{ __('pwa.hebergement.tarif_de_base') }}</th>
            <th>{{ __('pwa.hebergement.col_statut') }}</th>
        </tr>
        </thead>
        <tbody>
        @foreach ($parc as $unite)
            <tr>
                <td>{{ $unite->numero }}</td>
                <td>{{ $unite->categorie?->libelle ?? $tiret }}</td>
                {{-- Le tarif est celui de la CATÉGORIE, seule colonne de tarif
                     du schéma. Aucun repli chiffré : une unité sans catégorie
                     rend le tiret, jamais un prix que personne n'a fixé. --}}
                <td class="droite">
                    {{ $unite->categorie === null
                        ? $tiret
                        : \App\Pwa\Support\MontantFcfa::format((string) $unite->categorie->tarif_base) }}
                </td>
                {{-- L'état du JOUR, dérivé comme à l'écran (RG-02) — jamais la
                     colonne `statut` lue seule. --}}
                <td>{{ $etats[$unite->id]['libelle'] ?? $tiret }}</td>
            </tr>
        @endforeach
        </tbody>
    </table>

    @include('pdf.partials.signatures')
    @include('pdf.partials.pied-rapport')

@endif

</body>
</html>
