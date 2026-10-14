{{--
    Gabarit unique de tout état édité — RG-19, EF-M14-01.

    Ce fichier est le SEUL endroit où la mise en page d'un en-tête existe.
    `RESPECT_TABLEAU_RAPPORT.md` §4 : une en-tête recopiée localement diverge à
    la première évolution, et deux modules impriment alors des coordonnées
    différentes sur des documents opposables.

    Jetons visuels de `04_UIUX_DESIGN_SYSTEM.md` §2.1 — jamais une couleur
    improvisée.
--}}
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="utf-8">
    <title>{{ $entete->typeRapport }}</title>
    <style>
        @page { margin: 18mm 14mm 22mm 14mm; }

        body {
            font-family: DejaVu Sans, sans-serif;
            font-size: 9pt;
            color: #262626;
            margin: 0;
        }

        {{-- L'en-tête RG-19 vit dans un partiel depuis le 11/09/2026 : les
             PDF d'export le portent aussi (PA-192), et deux copies de ces
             règles divergeraient. --}}
        @include('pdf.partials.entete-rapport-styles')

        .kpis { width: 100%; border-collapse: collapse; margin-bottom: 12px; }
        .kpis td {
            border: 1px solid #E5E7EB;
            padding: 6px 8px;
            width: 25%;
        }
        .kpi-libelle { font-size: 7.5pt; color: #6B7280; text-transform: uppercase; }
        .kpi-valeur { font-size: 11pt; font-weight: bold; color: #14213D; }

        table.donnees { width: 100%; border-collapse: collapse; }
        table.donnees th {
            background: #14213D;
            color: #fff;
            font-size: 8pt;
            text-align: left;
            padding: 5px 6px;
        }
        table.donnees td {
            border-bottom: 1px solid #E5E7EB;
            padding: 4px 6px;
            font-size: 8.5pt;
        }
        table.donnees tr:nth-child(even) td { background: #F2F2F2; }

        .aucune-donnee {
            padding: 18px;
            text-align: center;
            color: #6B7280;
            border: 1px dashed #E5E7EB;
        }

    </style>
</head>
<body>

{{-- ---------------------------- En-tête officielle RG-19 et bloc titre --}}
@include('pdf.partials.entete-rapport')

{{-- ------------------------------------------------------------------ KPIs --}}
@if ($etat->kpis !== [])
    <table class="kpis">
        <tr>
            @foreach ($etat->kpis as $libelle => $valeur)
                <td>
                    <div class="kpi-libelle">{{ $libelle }}</div>
                    <div class="kpi-valeur">{{ $valeur }}</div>
                </td>
                @if ($loop->iteration % 4 === 0 && ! $loop->last)
        </tr><tr>
                @endif
            @endforeach
        </tr>
    </table>
@endif

{{-- ---------------------------------------------------------------- Données --}}
@if ($etat->estVide())
    {{--
        Grille RESPECT_TABLEAU_RAPPORT : message explicite, jamais un tableau
        vide sans explication ni une erreur technique.
    --}}
    <p class="aucune-donnee">{{ __('rapports.aucune_donnee') }}</p>
@else
    <table class="donnees">
        <thead>
        <tr>
            @foreach ($etat->entetes as $colonne)
                <th>{{ $colonne }}</th>
            @endforeach
        </tr>
        </thead>
        <tbody>
        @foreach ($etat->lignes as $ligne)
            <tr>
                @foreach ($ligne as $cellule)
                    <td>{{ $cellule }}</td>
                @endforeach
            </tr>
        @endforeach
        </tbody>
    </table>
@endif

{{-- ------------------------------------------------------- Pied de page --}}
@include('pdf.partials.pied-rapport')

</body>
</html>
