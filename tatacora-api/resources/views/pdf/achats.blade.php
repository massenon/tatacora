{{--
    COMMANDES D'ACHAT — document A4 de l'écran « Fournisseurs & Achats ».
    Maître : prototype_v2/pages/m7-achats.html (onglet « Commandes d'achat »).

    ⚠ Ce document rendait auparavant DEUX registres (fournisseurs ET commandes)
    et attendait six variables — `$onglet`, `$totalFournisseurs`,
    `$chiffreAchatsTotal`… Il ne rend plus qu'un registre : le référentiel
    fournisseurs a son propre document (`pdf/fournisseurs-liste.blade.php`), et
    un papier qui mélange deux registres oblige son lecteur à trouver lequel des
    deux il tenait en main.

    Trois colonnes du prototype ne sont PAS écrites, et le document le dit :
      - « N° de bon » : `commandes_achat` n'en porte aucun au schéma. En
        fabriquer un créerait une référence introuvable partout ailleurs.
      - « Réglé » et « Reste dû » : rien ne rattache un règlement à une commande
        d'achat dans ce dépôt — la table `paiements` va vers les factures
        CLIENTS. Un papier remis hors de l'écran qui l'a produit transforme une
        valeur plausible en fait.

    Le montant est CALCULÉ depuis les lignes (`bcadd`), jamais lu dans une
    colonne : `commandes_achat.montant_total` existe depuis le 28/08/2026 et
    aucun chemin de ce dépôt ne l'écrit.

    ⚠ PA-119 : l'export porte sur CE QUI EST AFFICHÉ, et il DIT son filtre —
    la ligne « Périmètre » de l'en-tête.
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
<title>Commandes d'achat — {{ $entete->raisonSociale }}</title>
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

  <table class="data-table">
    <thead>
      <tr>
        <th class="text-left" style="width: 30%;">Fournisseur</th>
        <th class="text-center" style="width: 16%;">Date de commande</th>
        <th class="text-right" style="width: 10%;">Lignes</th>
        <th class="text-right" style="width: 20%;">Montant estimé</th>
        <th class="text-center" style="width: 24%;">Statut</th>
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

  <p style="margin-top: 14px; font-size: 8pt; color: #64748b;">
    Le montant est la somme des lignes de chaque commande. Les colonnes
    « Réglé » et « Reste dû » du prototype ne figurent pas : aucun règlement
    fournisseur n'est enregistré par ce système.
  </p>

  @include('pdf.partials.signatures', ['visas' => ['Visa Responsable Achats', 'Visa Direction Générale']])

  @include('pdf.partials.pied-rapport')
</body>
</html>
