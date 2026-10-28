{{--
    REÇU DE LOCATION — le papier remis au client pour UN contrat (M8).

    Jumeau du poste (`impression/recu_location.dart`) : mêmes lignes, mêmes
    libellés (`vehicules.pwa.recu_*`), même ordre.

    ## Ce n'est pas une facture
    La mention est au CORPS (comme la confirmation de réservation, PA-113) :
    la facture normalisée MECeF est émise à l'encaissement. Aucun numéro n'est
    alloué ici — le N° est celui du contrat (`LOC-…`), le tiret s'il n'en a pas.

    ## Un contrat ANNULÉ ne montre AUCUN montant
    Bandeau « ANNULÉ » bien visible, puis la phrase « aucun montant n'est dû ».
    Ni total, ni acompte, ni reste dû : un acompte versé n'est pas un dû, mais
    l'écrire sur un contrat annulé se lirait comme une créance.

    ## Pas de visa ni de pied de rapport
    Document remis à un client : une zone « Visa Ordonnateur » en ferait une
    pièce d'ordonnancement (comme `pdf.hebergement`, confirmation).

    Variables : `contrat` (ContratLocation, vehicule et client chargés),
    `annule` (bool), `jours` (int), `tarif` (?string), `entete` (EnTeteRapport).
--}}
@php
    $tiret = \App\Pwa\Support\MontantFcfa::TIRET;
    $montant = $contrat->montant === null ? null : (string) $contrat->montant;
    $acompte = $contrat->acompte === null ? null : (string) $contrat->acompte;
    $reste = $montant === null || $contrat->reste_a_payer === null ? null : (string) $contrat->reste_a_payer;
@endphp
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <title>{{ __('vehicules.pwa.recu_titre') }}</title>
    <style>
        @page { margin: 18mm 14mm; }
        body { font-family: DejaVu Sans, sans-serif; font-size: 9.5pt; color: #14213D; }
        @include('pdf.partials.entete-rapport-styles')
        table { width: 100%; border-collapse: collapse; }
        td { border-bottom: 1px solid #E2E8F0; padding: 5px 6px; font-size: 9.5pt; }
        .cle { color: #64748B; width: 42%; }
        .mention { border: 1px solid #B8891E; background: #FDF3E0; color: #8A6412;
                   padding: 8px 10px; margin: 12px 0; font-size: 9pt; }
        .annule { border: 2px solid #B91C1C; color: #B91C1C; text-align: center;
                  font-size: 20pt; font-weight: bold; padding: 8px; margin: 12px 0 4px; }
        .annule-mention { color: #B91C1C; font-size: 9.5pt; margin: 0 0 12px; text-align: center; }
        .fort td { font-weight: bold; }
    </style>
</head>
<body>

@include('pdf.partials.entete-rapport')

@if ($annule)
    <div class="annule">{{ __('vehicules.pwa.recu_annule_bandeau') }}</div>
    <p class="annule-mention">{{ __('vehicules.pwa.recu_annule_mention') }}</p>
@endif

<table>
    <tr>
        <td class="cle">{{ __('vehicules.pwa.recu_numero') }}</td>
        <td>{{ $contrat->numero ?? $tiret }}</td>
    </tr>
    <tr>
        <td class="cle">{{ __('vehicules.pwa.col_client') }}</td>
        <td>{{ $contrat->client?->nomComplet() ?: $tiret }}</td>
    </tr>
    <tr>
        <td class="cle">{{ __('vehicules.pwa.col_vehicule') }}</td>
        <td>{{ $contrat->vehicule?->immatriculation ?? $tiret }}</td>
    </tr>
    <tr>
        <td class="cle">{{ __('vehicules.pwa.col_periode') }}</td>
        <td>{{ __('rapports.periode.du_au', [
            'debut' => $contrat->date_debut->format('d/m/Y'),
            'fin' => $contrat->date_fin->format('d/m/Y'),
        ]) }}</td>
    </tr>
    <tr>
        <td class="cle">{{ __('vehicules.pwa.recu_duree') }}</td>
        <td>{{ __('vehicules.pwa.recu_jours', ['jours' => $jours]) }}</td>
    </tr>
    @unless ($annule)
        <tr>
            <td class="cle">{{ __('vehicules.pwa.recu_tarif') }}</td>
            <td>{{ $tarif === null ? $tiret : \App\Pwa\Support\MontantFcfa::format($tarif) }}</td>
        </tr>
        <tr class="fort">
            <td class="cle">{{ __('vehicules.pwa.recu_montant') }}</td>
            <td>{{ $montant === null ? $tiret : \App\Pwa\Support\MontantFcfa::format($montant) }}</td>
        </tr>
        <tr>
            <td class="cle">{{ __('vehicules.pwa.recu_acompte') }}</td>
            <td>{{ $acompte === null ? $tiret : \App\Pwa\Support\MontantFcfa::formatOuTiret($acompte) }}</td>
        </tr>
        <tr class="fort">
            <td class="cle">{{ __('vehicules.pwa.recu_reste') }}</td>
            <td>
                @if ($reste === null)
                    {{ $tiret }}
                @elseif (bccomp($reste, '0', 2) > 0)
                    {{ \App\Pwa\Support\MontantFcfa::format($reste) }}
                @else
                    {{ __('vehicules.pwa.solde') }}
                @endif
            </td>
        </tr>
    @endunless
    <tr>
        <td class="cle">{{ __('vehicules.pwa.recu_statut') }}</td>
        <td>{{ $annule ? __('vehicules.pwa.contrat_annule') : __('vehicules.pwa.contrat_actif') }}</td>
    </tr>
    <tr>
        <td class="cle">{{ __('vehicules.pwa.recu_emis_le') }}</td>
        <td>{{ now()->format('d/m/Y') }}</td>
    </tr>
    <tr>
        <td class="cle">{{ __('vehicules.pwa.recu_emis_par') }}</td>
        <td>{{ $entete->auteur }}</td>
    </tr>
</table>

<div class="mention">{{ __('vehicules.pwa.recu_mention') }}</div>

</body>
</html>
