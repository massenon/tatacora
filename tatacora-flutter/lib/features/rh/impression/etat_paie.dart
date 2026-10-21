// Vue Blade maîtresse (PA-183) : pwa/rh/paie.blade.php
import 'dart:convert';

import '../../../core/format/formats.dart';
import '../../../core/impression/etat_tabulaire_a4.dart';

/// Le tiret du maître — « — » : la donnée n'existe pas. Jamais une cellule
/// vide, qui laisserait croire à un oubli d'affichage.
const String tiretPaie = '—';

/// L'export tableur de l'écran Personnel & Paie — le bouton « Exporter ».
///
/// ## Un export porte sur CE QUI EST AFFICHÉ, et il DIT son filtre (PA-119)
///
/// Les lignes reçues sont celles de l'onglet courant, déjà filtrées. La portée
/// (onglet, période, service, contrat, statut, recherche) est écrite **dans le
/// fichier**, pas seulement à l'écran : un document qui ne dit pas sa portée se
/// lit comme s'il portait tout le personnel.
///
/// ## Aucune colonne « Coût employeur » à valeur unique
///
/// Le coût employeur est TOUJOURS une fourchette : le taux CNSS de risques
/// professionnels n'est pas confirmé pour l'hôtellerie-restauration. L'onglet
/// des bulletins exporte la part patronale CONFIRMÉE, l'onglet du livre rend
/// le coût total sur une cellule « min — max ». Un chiffre unique dans un
/// classeur serait repris tel quel dans une déclaration : un export est le
/// dernier endroit où le refus pourrait se perdre.
///
/// ## « Excel » est rendu en CSV, et l'écart est nommé
///
/// Convention serveur RG-19 : BOM UTF-8 et point-virgule, ce qu'attend un Excel
/// en configuration française. Aucune bibliothèque XLSX n'est embarquée — même
/// écart que pour la dépense courante (PA-111). Les montants partent en
/// **nombres bruts** : un tableur ne sait pas additionner « 56 000 FCFA ».
///
/// ## La forme DOCUMENT du livre de paie n'est pas exportée (écart nommé)
///
/// La vue cache, pour sa garde de colonnes, une table onze colonnes
/// « Livre de paie / Bulletins de paie » (l.839-857) : Matricule, Employé,
/// Brut, CNSS 3,6 %, ITS, Autres retenues, Net à payer, CNSS pension 6,4 %,
/// « Prest. fam. 9 % », VPS 4 % et « Risques prof. (non confirmé) ». Ce n'est
/// PAS le fichier que la PWA écrit (`PaieExport::entetesDe`, huit colonnes dont
/// « Charges patronales »), et c'est celui de la PWA que ce poste suit. Les deux
/// intitulés propres à cette forme — « Prest. fam. 9 % » et « Risques prof. (non
/// confirmé) » — sont donc NOMMÉS ici et non rendus : la mesure les compte
/// « nommés », pas « portés ». (Si la forme document était un jour exportée, la
/// colonne des risques professionnels rendrait une FOURCHETTE, jamais un taux
/// supposé — PA-53.)
///
/// ## Les en-têtes sont ceux de la vue
///
/// `App\Exports\PaieExport::entetesDe()` : même casse que le maître
/// (« Matricule », pas « MATRICULE ») — `uppercase` est une règle CSS qui ne
/// s'applique pas à un fichier.
final class EtatPaie {
  const EtatPaie({
    required this.cleOnglet,
    required this.titreOnglet,
    required this.entetes,
    required this.lignes,
    required this.portee,
    this.colonnesMontant = const {},
    this.colonnesTotalisees = const {},
  });

  /// `personnel`, `bulletins`… — sert à nommer le fichier (`paie_<onglet>`).
  final String cleOnglet;

  /// Le libellé de l'onglet exporté.
  final String titreOnglet;

  /// Les colonnes, au mot de la vue.
  final List<String> entetes;

  /// Les lignes réellement affichées, une cellule par colonne.
  final List<List<String>> lignes;

  /// La portée du document, en une ligne.
  final String portee;

  /// Les index des colonnes de MONTANT : nombres bruts au CSV, « 56 000
  /// FCFA » alignés à droite au PDF. Une fourchette « min — max » garde ses
  /// deux bornes.
  final Set<int> colonnesMontant;

  /// Les colonnes dont le PDF imprime le total (somme des montants entiers),
  /// sur une ligne « Total » en gras. Vide : aucune ligne de totaux.
  final Set<int> colonnesTotalisees;

  bool get vide => lignes.isEmpty;

  /// Le préfixe du fichier écrit — `paie_<onglet>_<horodatage>.csv`.
  String get prefixeFichier => 'paie_$cleOnglet';

  /// Les mentions qui bornent le document. Une mention qui borne la portée
  /// d'un document s'imprime avec lui (PA-135).
  static const List<String> mentions = [
    'Ce fichier reprend l’onglet tel qu’il est affiché à l’écran, et rien '
        'd’autre.',
    'Les montants sont en FCFA, en nombres bruts. Aucun total de charge '
        'patronale n’y figure : le taux de risques professionnels n’est pas '
        'confirmé, le coût employeur est donc toujours donné en fourchette.',
  ];

  String csv() {
    final tampon = StringBuffer('\u{FEFF}')
      ..writeln('${_e(titreOnglet)};${_e(portee)}')
      ..writeln();

    for (final mention in mentions) {
      tampon.writeln(_e(mention));
    }
    tampon.writeln();

    tampon.writeln(entetes.map(_e).join(';'));
    for (final ligne in lignes) {
      tampon.writeln(ligne.map(_e).join(';'));
    }

    return tampon.toString();
  }

  List<int> csvOctets() => utf8.encode(csv());

  /// Les mentions du papier : celles du CSV, la forme des montants en moins
  /// (ils y sont en FCFA, groupés par milliers).
  static const List<String> mentionsPapier = [
    'Ce document reprend l’onglet tel qu’il est affiché à l’écran, et rien '
        'd’autre.',
    'Aucun total de charge patronale non confirmée n’y figure : le taux de '
        'risques professionnels n’est pas confirmé, le coût employeur est donc '
        'toujours donné en fourchette.',
  ];

  /// Le « PDF Officiel A4 Imprimable » de l'onglet affiché (directive du PO
  /// du 14/10/2026) : les colonnes et les lignes du CSV, montants en FCFA à
  /// droite. Huit colonnes (personnel, bulletins) : paysage ; sinon portrait.
  EtatTabulaireA4 etatA4() => EtatTabulaireA4(
    titre: 'Paie — $titreOnglet',
    portee: portee,
    mentions: mentionsPapier,
    colonnes: [
      for (final (i, entete) in entetes.indexed)
        colonnesMontant.contains(i)
            ? ColonneEtat.nombre(entete)
            : ColonneEtat(entete),
    ],
    lignes: [
      for (final ligne in lignes)
        [
          for (final (i, cellule) in ligne.indexed)
            colonnesMontant.contains(i) ? _montantPapier(cellule) : cellule,
        ],
    ],
    totaux: colonnesTotalisees.isEmpty
        ? null
        : [
            for (var i = 0; i < entetes.length; i++)
              if (i == 0)
                'Total'
              else if (colonnesTotalisees.contains(i))
                formaterFcfa(
                  lignes.fold<int>(
                    0,
                    (somme, l) => somme + (int.tryParse(l[i]) ?? 0),
                  ),
                )
              else
                '',
          ],
  );

  /// Un montant brut (« 56000 ») ou une fourchette (« 120 — 480 ») en FCFA.
  /// Ce qui n'est pas un nombre (le tiret d'absence) passe tel quel.
  static String _montantPapier(String brut) {
    final bornes = brut.split(' — ');
    final entiers = [for (final b in bornes) int.tryParse(b.trim())];
    if (entiers.any((e) => e == null)) return brut;
    return entiers.map((e) => formaterFcfa(e!)).join(' — ');
  }

  /// Le point-virgule est le séparateur : un point-virgule DANS une valeur
  /// casserait la colonne, et un saut de ligne casserait la ligne.
  static String _e(String v) =>
      v.replaceAll(';', ',').replaceAll('\n', ' ').replaceAll('\r', ' ');
}
