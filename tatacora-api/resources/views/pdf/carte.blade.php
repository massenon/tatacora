{{--
    ÉTAT DE LA CARTE — un seul document, pour le bar (M5) et le restaurant (M4).

    Maître : prototype_v2/pages/carte-module.js l.393-406 (`etatCourant()`),
    rendu par `assets/js/export-engine.js`. Le maître n'a qu'UN état pour les
    deux rayons : le titre change, la structure non.

    ## Il remplace deux fichiers

    `pdf/carte-bar.blade.php` et `pdf/carte-restaurant.blade.php` portaient le
    même document sous deux noms, et avaient déjà divergé. Le défaut de
    `/pwa/stocks` (HTTP 500) est né exactement d'un copier-coller de vue.

    ## Il DIT son filtre (PA-119)

    L'export porte sur ce qui est affiché. Quelqu'un qui filtre puis exporte
    attend son filtre — lui rendre le registre entier lui ferait envoyer au
    comptable un document qu'il croit avoir vérifié. Le filtre appliqué est
    imprimé en tête, toujours, même quand il n'y en a aucun.

    ## En-tête, signatures, pied (11/09/2026, PA-192 — Directive §6)

    L'en-tête de RAPPORT (`pdf.partials.entete-rapport`) remplace celui des
    pièces commerciales : ce document est un export, son bloc titre porte le
    titre, le filtre (PA-119), l'auteur et l'heure. Zone de signatures et
    pied de rapport, comme tout export.

    Variables : entete (EnTeteRapport — titre et filtre compris), entetes,
    lignes, indicateurs.
--}}
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<title>{{ $titre }} — {{ __('pwa.marque') }}</title>
<style>
  @page { size: A4 portrait; margin: 14mm 12mm 16mm 12mm; }
  body { font-family: 'Helvetica', 'Arial', sans-serif; color: #262626; margin: 0; padding: 0; font-size: 9pt; }
  @include('pdf.partials.entete-rapport-styles')
  .kpis { width: 100%; border-collapse: collapse; margin-bottom: 4mm; }
  .kpis td { border: 1px solid #E2E8F0; padding: 2mm; font-size: 8pt; }
  .kpis .lib { color: #64748B; }
  .kpis .val { font-weight: bold; color: #14213D; }
  table.corps { width: 100%; border-collapse: collapse; }
  table.corps th { background: #F1F5F9; color: #334155; font-size: 7.5pt; text-transform: uppercase;
                   letter-spacing: 0.04em; padding: 2mm 1.5mm; border-bottom: 1px solid #CBD5E1; text-align: right; }
  table.corps th:first-child { text-align: left; }
  table.corps td { padding: 1.8mm 1.5mm; border-bottom: 1px solid #F1F5F9; font-size: 8.5pt; text-align: right; }
  table.corps td:first-child { text-align: left; font-weight: 500; color: #1e293b; }
  table.corps tr { page-break-inside: avoid; }
  thead { display: table-header-group; }

</style>
</head>
<body>

  {{-- En-tête RG-19 : identité, puis titre, FILTRE (PA-119), auteur, heure. --}}
  @include('pdf.partials.entete-rapport')

  <table class="kpis">
    <tr>
      <td><span class="lib">{{ __('carte_pwa.commun.kpi_articles') }} :</span> <span class="val">{{ $indicateurs['articles'] }}</span></td>
      <td><span class="lib">{{ __('carte_pwa.commun.kpi_lies') }} :</span> <span class="val">{{ $indicateurs['lies'] }} ({{ $indicateurs['taux_couverture'] }} %)</span></td>
      <td><span class="lib">{{ __('carte_pwa.commun.kpi_sans_lien') }} :</span> <span class="val">{{ $indicateurs['sans_lien'] }}</span></td>
      <td><span class="lib">{{ __('carte_pwa.commun.kpi_retires') }} :</span> <span class="val">{{ $indicateurs['indisponibles'] }}</span></td>
      {{-- maître — carte-module.js l.407 : « Prix provisoires » fait partie
           des quatre indicateurs de l'état exporté. Il en manquait faute de
           colonne au schéma (PA-161 (b) l'a créée). --}}
      <td><span class="lib">{{ __('carte_pwa.commun.kpi_provisoires') }} :</span> <span class="val">{{ $indicateurs['prix_provisoires'] }}</span></td>
    </tr>
  </table>

  <table class="corps">
    <thead>
      <tr>
        {{-- `$colonne`, jamais `$entete` : la boucle écraserait l'en-tête
             RG-19, que le pied et les signatures lisent plus bas. --}}
        @foreach ($entetes as $colonne)
          <th>{{ $colonne }}</th>
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
