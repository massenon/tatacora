{{--
    APPROVISIONNEMENT — document A4 de l'écran, sur l'onglet AFFICHÉ.
    Maître : prototype_v2/pages/m7-approvisionnement.html

    ⚠ LE DÉFAUT QUE CE FICHIER PORTAIT, ET QUI N'AURAIT PARU QU'À L'IMPRESSION.
    Il attendait `$commande` — un bon de commande UNIQUE — alors que ses deux
    appelants lui passaient `$commandes` et `$receptions` : la vue aurait levé
    sur une variable indéfinie à la première exécution réelle, et rien dans la
    suite de tests n'y allait. Il rend désormais ce que l'écran affiche.

    Le nom du fichier est conservé (aucune route ni aucun autre appelant ne le
    désigne, vérifié le 31/08/2026) ; son contenu, lui, dit ce qu'il rend.

    ⚠ Aucun montant DÛ n'est écrit : rien ne rattache un règlement à une
    commande d'achat dans ce dépôt. Le chiffre porté est le montant COMMANDÉ.
--}}
<!DOCTYPE html>
{{--
    ## En-tête, signatures, pied (11/09/2026, PA-192 — Directive §6)

    L'identité de l'établissement était écrite ici à la main — et avait
    DIVERGÉ : un second numéro de téléphone que les paramètres ne portent pas.
    Elle vient désormais de `pdf.partials.entete-rapport` (`ReportHeaderService`,
    RG-19, source unique), dont le bloc titre porte le titre, le filtre,
    l'auteur et l'heure. Zone de signatures (`pdf.partials.signatures`) et pied
    de rapport (`pdf.partials.pied-rapport`), comme tout export.
--}}
<html lang="fr">
<head>
<meta charset="UTF-8">
<title>Approvisionnement — {{ $entete->raisonSociale }}</title>
<style>
  @page { size: A4 portrait; margin: 10mm 10mm 15mm 10mm; }
  body { font-family: 'Helvetica', 'Arial', sans-serif; font-size: 9pt; color: #1e293b; margin: 0; padding: 0; }
  table { width: 100%; border-collapse: collapse; table-layout: fixed; }


  .data-table { margin-top: 10px; }
  .data-table thead th { background-color: #14213D; color: #ffffff; font-size: 8pt; font-weight: bold; text-transform: uppercase; padding: 6px 4px; border: 1px solid #14213D; }
  .data-table tbody td { padding: 6px 4px; border-bottom: 1px solid #e2e8f0; font-size: 8.5pt; word-wrap: break-word; overflow: hidden; }
  .data-table tbody tr:nth-child(even) { background-color: #f8fafc; }

  .text-left { text-align: left; }
  .text-right { text-align: right; }
  .text-center { text-align: center; }
  .font-bold { font-weight: bold; }

  @include('pdf.partials.entete-rapport-styles')
</style>
</head>
<body>


  {{-- En-tête RG-19 : identité, puis titre, filtre, auteur, heure. --}}
  @include('pdf.partials.entete-rapport')

  @if ($onglet === 'besoins')
    <table class="data-table">
      <thead>
        <tr>
          <th class="text-left" style="width: 40%;">Article</th>
          <th class="text-right" style="width: 15%;">Stock</th>
          <th class="text-right" style="width: 15%;">Seuil</th>
          <th class="text-right" style="width: 15%;">Manque</th>
          <th class="text-right" style="width: 15%;">À commander</th>
        </tr>
      </thead>
      <tbody>
        @foreach ($besoins as $b)
          <tr>
            <td class="text-left font-bold" style="color: #14213D;">{{ $b['libelle'] }}</td>
            <td class="text-right">{{ $b['stock'] }}</td>
            <td class="text-right">{{ $b['seuil'] }}</td>
            <td class="text-right">{{ $b['manque'] }}</td>
            <td class="text-right font-bold">{{ $b['a_commander'] }} {{ $b['unite'] }}</td>
          </tr>
        @endforeach
      </tbody>
    </table>
    <p style="margin-top: 12px; font-size: 8pt; color: #64748b;">
      La quantité à commander remonte au double du seuil d'alerte. Le stock
      est consolidé sur tous les points de stockage.
    </p>

  @elseif ($onglet === 'receptions')
    <table class="data-table">
      <thead>
        <tr>
          <th class="text-left" style="width: 30%;">Réception</th>
          <th class="text-left" style="width: 30%;">Commande</th>
          <th class="text-left" style="width: 22%;">Fournisseur</th>
          <th class="text-center" style="width: 9%;">Date</th>
          <th class="text-center" style="width: 9%;">Conformité</th>
        </tr>
      </thead>
      <tbody>
        @foreach ($receptions as $r)
          <tr>
            <td class="text-left" style="font-size: 7pt;">{{ $r->id }}</td>
            <td class="text-left" style="font-size: 7pt;">{{ $r->commande_id }}</td>
            <td class="text-left">{{ $r->commande?->fournisseur?->raison_sociale ?? '—' }}</td>
            <td class="text-center">{{ $r->date_reception?->format('d/m/Y') ?? '—' }}</td>
            <td class="text-center font-bold">{{ $r->conformite }}</td>
          </tr>
        @endforeach
      </tbody>
    </table>

  @else
    <table class="data-table">
      <thead>
        <tr>
          <th class="text-left" style="width: 34%;">Fournisseur</th>
          <th class="text-center" style="width: 16%;">Date</th>
          <th class="text-right" style="width: 12%;">Lignes</th>
          <th class="text-right" style="width: 20%;">Montant commandé</th>
          <th class="text-center" style="width: 18%;">Statut</th>
        </tr>
      </thead>
      <tbody>
        @foreach ($commandes as $c)
          <tr>
            <td class="text-left font-bold" style="color: #14213D;">{{ $c->fournisseur?->raison_sociale ?? '—' }}</td>
            <td class="text-center">{{ $c->date_commande?->format('d/m/Y') ?? '—' }}</td>
            <td class="text-right">{{ $c->lignes->count() }}</td>
            <td class="text-right font-bold">{{ \App\Pwa\Support\MontantFcfa::format($c->montantTotal()) }}</td>
            <td class="text-center">{{ \App\Pwa\Livewire\Achats\Achats::STATUTS[$c->statut]['libelle'] ?? $c->statut }}</td>
          </tr>
        @endforeach
      </tbody>
    </table>
    <p style="margin-top: 12px; font-size: 8pt; color: #64748b;">
      Montant commandé, pas montant dû.
    </p>
  @endif

  @include('pdf.partials.signatures', ['visas' => ['Visa Magasinier', 'Visa Responsable Achats']])

  @include('pdf.partials.pied-rapport')
</body>
</html>
