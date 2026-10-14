/// Le CONTRÔLE d'un fichier d'import par module — onglet « Importer les
/// données » de l'écran Import & Export. Réplique, sur ce poste, de
/// `ControleImportService` du serveur (lu le 14/10/2026) : **fonction pure**,
/// elle ne lit ni n'écrit la base.
///
/// ## Erreur et avertissement ne sont pas la même chose (règle du serveur)
///
///  - **Erreur** — la ligne est inexploitable (obligatoire vide, valeur hors
///    liste, nombre illisible, montant négatif, référence inconnue, doublon
///    interne au fichier). Rien n'est importé tant qu'il en reste une.
///  - **Avertissement** — la ligne est exploitable mais mérite un regard
///    (doublon avec l'existant, colonne inconnue ignorée).
///
/// ## Un écart, NOMMÉ : le doublon avec l'existant est IGNORÉ
///
/// Le serveur avertit puis crée la fiche en double. Sur ce poste (demande du
/// PO du 14/10/2026, « idempotent sur une clé naturelle »), une ligne dont
/// l'identifiant existe déjà est **ignorée**, et l'avertissement le dit :
/// réimporter le même fichier ne crée rien la seconde fois.
///
/// ## Ce que la correspondance d'en-têtes tolère
///
/// Casse et accents, comme au serveur ; une colonne reconnue par son LIBELLÉ
/// ou par son CHAMP. Le sens, jamais : une colonne inconnue reste inconnue.
library;

import '../../../core/fichiers/lecture_csv.dart';

/// Le type d'une colonne — celui du serveur (`ColonneImport::$type`).
enum TypeColonneImport {
  texte('Texte libre'),
  nombre('Nombre entier'),
  montant('Montant en FCFA'),
  liste(''),
  reference("Libellé exact d'une fiche existante");

  const TypeColonneImport(this.libelle);

  /// La colonne « VALEURS ATTENDUES » quand il n'y a pas de liste fermée
  /// (`imports.types.*`).
  final String libelle;
}

/// Une colonne attendue — la déclaration UNIQUE dont découlent la fiche
/// « Colonnes attendues », le fichier modèle ET le contrôle.
final class ColonneImport {
  const ColonneImport({
    required this.champ,
    required this.libelle,
    required this.requis,
    this.type = TypeColonneImport.texte,
    this.valeurs,
    this.exemple = '',
  });

  /// Clé interne (colonne du schéma ou clé du DAO).
  final String champ;

  /// En-tête lisible, celle du fichier modèle.
  final String libelle;
  final bool requis;
  final TypeColonneImport type;

  /// Liste fermée (type `liste`) — lue du registre du poste, jamais recopiée.
  final List<String>? valeurs;
  final String exemple;
}

/// Une anomalie du rapport — `ligne` compte COMME EXCEL (l'en-tête est la
/// ligne 1) ; `0` : le fichier entier.
final class AnomalieImport {
  const AnomalieImport({
    required this.ligne,
    required this.message,
    this.colonne,
  });

  final int ligne;
  final String? colonne;
  final String message;
}

/// Une ligne CONTRÔLÉE, prête pour l'écriture : les valeurs converties
/// (texte rogné, nombre nettoyé, graphie canonique d'une liste, identifiant
/// d'une référence), par champ ; `null` pour une cellule vide.
final class LigneImport {
  const LigneImport({required this.numero, required this.valeurs});

  final int numero;
  final Map<String, String?> valeurs;

  String? operator [](String champ) => valeurs[champ];

  /// La valeur d'un champ obligatoire (le contrôle l'a garantie non vide).
  String exiger(String champ) => valeurs[champ] ?? '';
}

/// Le rapport de contrôle d'un fichier.
final class RapportImport {
  const RapportImport({
    required this.erreurs,
    required this.avertissements,
    required this.lignes,
    required this.total,
    required this.enErreur,
    required this.ignorees,
  });

  /// Le fichier entier refusé (vide, illisible) : une seule erreur, ligne 0.
  factory RapportImport.refusGlobal(String message) => RapportImport(
    erreurs: [AnomalieImport(ligne: 0, message: message)],
    avertissements: const [],
    lignes: const [],
    total: 0,
    enErreur: 0,
    ignorees: 0,
  );

  final List<AnomalieImport> erreurs;
  final List<AnomalieImport> avertissements;

  /// Les lignes à ÉCRIRE — vide dès qu'il reste une erreur (aucun import
  /// partiel).
  final List<LigneImport> lignes;

  /// Lignes non blanches lues.
  final int total;

  /// Lignes portant au moins une erreur.
  final int enErreur;

  /// Lignes déjà présentes, ignorées (écart nommé de l'en-tête).
  final int ignorees;

  bool get ok => erreurs.isEmpty;

  /// Lignes exploitables — à importer ou ignorées comme déjà présentes.
  int get valides => total - enErreur;

  /// Le même rapport, enrichi des refus et réserves de la SIMULATION
  /// d'écriture (le DAO a son mot à dire, comme au serveur où le service de
  /// domaine peut refuser une ligne pourtant contrôlée).
  RapportImport avecSimulation({
    required List<AnomalieImport> refus,
    required List<AnomalieImport> reserves,
  }) {
    final lignesRefusees = {for (final r in refus) r.ligne};
    final toutes = [...erreurs, ...refus];
    return RapportImport(
      erreurs: toutes,
      avertissements: [...avertissements, ...reserves],
      lignes: toutes.isEmpty ? lignes : const [],
      total: total,
      enErreur: enErreur + lignesRefusees.length,
      ignorees: ignorees,
    );
  }
}

/// Les mots du contrôle — `lang/fr/imports.php` (`controle`), au mot, sauf
/// [doublonExistantIgnore] (écart nommé de l'en-tête).
abstract final class TextesControleImport {
  static const String fichierVide = 'Fichier vide.';
  static const String fichierIllisible =
      "Le fichier n'a pas pu être lu en UTF-8 : enregistrez-le en CSV UTF-8, "
      'puis redéposez-le.';
  static String colonneManquante(String libelle) =>
      'Colonne obligatoire absente du fichier : « $libelle ».';
  static String colonneInconnue(String libelle) =>
      'Colonne « $libelle » non reconnue — elle sera ignorée.';
  static const String valeurObligatoire = 'valeur obligatoire absente';
  static String valeurHorsListe(String valeur, List<String> attendu) =>
      'valeur « $valeur » hors liste (attendu : ${attendu.join(', ')})';
  static String valeurNonNumerique(String valeur) =>
      "valeur « $valeur » n'est pas un nombre";
  static String montantNegatif(String valeur) => 'montant négatif ($valeur)';
  static String referenceInconnue(String valeur, String referentiel) =>
      'aucun enregistrement « $valeur » au référentiel $referentiel — la '
      'fiche se crée depuis son propre écran, jamais en silence depuis un '
      'import';
  static String doublonFichier(String valeur) =>
      'Doublon dans le fichier : « $valeur » apparaît plusieurs fois.';

  /// Écart NOMMÉ au serveur (« la ligne sera ajoutée en doublon si vous
  /// poursuivez ») : sur ce poste, la ligne est ignorée.
  static String doublonExistantIgnore(String valeur) =>
      '« $valeur » existe déjà — la ligne sera ignorée : un import ne crée '
      'jamais de doublon sur ce poste.';
  static const String aucuneLigne = 'Aucune ligne à importer.';
  static String refusModule(String raison) => 'refusée par le module : $raison';
  static String refusService(int ligne, String element, String raison) =>
      'Ligne $ligne (« $element ») refusée par le module : $raison';
  static String importFait(int nombre, String module) =>
      '$nombre ligne(s) importée(s) dans $module.';
}

/// Casse et accents neutralisés — le SENS, jamais.
String normaliserImport(String texte) {
  const accents = {
    'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a', //
    'ç': 'c', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'í': 'i', //
    'ì': 'i', 'î': 'i', 'ï': 'i', 'ñ': 'n', 'ó': 'o', 'ò': 'o', //
    'ô': 'o', 'ö': 'o', 'õ': 'o', 'ú': 'u', 'ù': 'u', 'û': 'u', //
    'ü': 'u', 'ý': 'y', 'ÿ': 'y', 'œ': 'oe', 'æ': 'ae',
  };
  return texte
      .trim()
      .toLowerCase()
      .split('')
      .map((c) => accents[c] ?? c)
      .join();
}

/// Excel sème espaces fines et virgules décimales — tolérées, jamais devinées.
String nettoyerNombreImport(String brut) => brut
    .replaceAll(' ', '')
    .replaceAll('\u{202F}', '')
    .replaceAll('\u{00A0}', '')
    .replaceAll(',', '.');

final RegExp _nombre = RegExp(r'^-?\d+(\.\d+)?$');

/// Découpe le contenu d'un CSV — séparateur point-virgule OU virgule, celui des
/// deux que l'en-tête emploie le plus.
List<List<String>> analyserCsvImport(String contenu) =>
    lireCsv(contenu, separateur: separateurDe(contenu));

/// Contrôle [tableau] (première ligne = en-tête) contre [colonnes].
///
/// [existants] : les identifiants déjà en base, NORMALISÉS
/// ([normaliserImport]). [references] : par champ de type `reference`, le
/// libellé EXACT → identifiant de la fiche visée.
RapportImport controlerImport({
  required List<ColonneImport> colonnes,
  required String identifiant,
  required List<List<String>> tableau,
  required Set<String> existants,
  Map<String, Map<String, String>> references = const {},
}) {
  if (tableau.isEmpty || tableau.first.every((c) => c.trim().isEmpty)) {
    return RapportImport.refusGlobal(TextesControleImport.fichierVide);
  }

  final erreurs = <AnomalieImport>[];
  final avertissements = <AnomalieImport>[];

  // Correspondance des en-têtes : champ → index.
  final carte = <String, int>{};
  for (final (index, entete) in tableau.first.indexed) {
    final normalise = normaliserImport(entete);
    if (normalise.isEmpty) continue;
    ColonneImport? trouvee;
    for (final c in colonnes) {
      if (normaliserImport(c.libelle) == normalise ||
          normaliserImport(c.champ) == normalise) {
        trouvee = c;
        break;
      }
    }
    if (trouvee != null) {
      carte[trouvee.champ] = index;
    } else {
      // Une colonne en trop n'empêche pas l'import : ignorée, et on le dit.
      avertissements.add(
        AnomalieImport(
          ligne: 1,
          colonne: entete,
          message: TextesControleImport.colonneInconnue(entete),
        ),
      );
    }
  }
  for (final c in colonnes) {
    if (c.requis && !carte.containsKey(c.champ)) {
      erreurs.add(
        AnomalieImport(
          ligne: 1,
          colonne: c.libelle,
          message: TextesControleImport.colonneManquante(c.libelle),
        ),
      );
    }
  }

  // Les lignes non blanches, numérotées comme Excel (+2 : l'en-tête est 1).
  final corps = <(int, List<String>)>[
    for (final (i, brute) in tableau.skip(1).indexed)
      if (brute.any((v) => v.trim().isNotEmpty)) (i + 2, brute),
  ];

  if (erreurs.isNotEmpty) {
    return RapportImport(
      erreurs: erreurs,
      avertissements: avertissements,
      lignes: const [],
      total: corps.length,
      enErreur: corps.length,
      ignorees: 0,
    );
  }

  final colonneIdentifiant = colonnes.firstWhere((c) => c.champ == identifiant);
  final vus = <String>{};
  final valides = <LigneImport>[];
  final enErreur = <int>{};
  var ignorees = 0;

  for (final (numero, brute) in corps) {
    final valeurs = <String, String?>{};
    for (final c in colonnes) {
      final index = carte[c.champ];
      final valeur = index == null || index >= brute.length ? '' : brute[index];
      final probleme = _controlerCellule(c, valeur, references[c.champ]);
      if (probleme != null) {
        erreurs.add(
          AnomalieImport(ligne: numero, colonne: c.libelle, message: probleme),
        );
        enErreur.add(numero);
        continue;
      }
      valeurs[c.champ] = _convertir(c, valeur, references[c.champ]);
    }

    final cle = valeurs[identifiant];
    var ignoree = false;
    if (cle != null && cle.isNotEmpty) {
      final normalise = normaliserImport(cle);
      if (!vus.add(normalise)) {
        // Doublon INTERNE au fichier : erreur — importer deux fois la même
        // ligne créerait deux fiches identiques d'un coup.
        erreurs.add(
          AnomalieImport(
            ligne: numero,
            colonne: colonneIdentifiant.libelle,
            message: TextesControleImport.doublonFichier(cle),
          ),
        );
        enErreur.add(numero);
      } else if (existants.contains(normalise)) {
        avertissements.add(
          AnomalieImport(
            ligne: numero,
            colonne: colonneIdentifiant.libelle,
            message: TextesControleImport.doublonExistantIgnore(cle),
          ),
        );
        ignoree = true;
      }
    }

    if (enErreur.contains(numero)) continue;
    if (ignoree) {
      ignorees++;
    } else {
      valides.add(LigneImport(numero: numero, valeurs: valeurs));
    }
  }

  return RapportImport(
    erreurs: erreurs,
    avertissements: avertissements,
    lignes: erreurs.isEmpty ? valides : const [],
    total: corps.length,
    enErreur: enErreur.length,
    ignorees: ignorees,
  );
}

/// Vérifie une cellule contre le type déclaré — `null` : rien à redire.
String? _controlerCellule(
  ColonneImport c,
  String valeur,
  Map<String, String>? reference,
) {
  final brut = valeur.trim();
  if (brut.isEmpty) {
    return c.requis ? TextesControleImport.valeurObligatoire : null;
  }
  switch (c.type) {
    case TypeColonneImport.texte:
      return null;
    case TypeColonneImport.liste:
      final valeurs = c.valeurs ?? const <String>[];
      final n = normaliserImport(brut);
      return valeurs.any((v) => normaliserImport(v) == n)
          ? null
          : TextesControleImport.valeurHorsListe(brut, valeurs);
    case TypeColonneImport.nombre:
    case TypeColonneImport.montant:
      final nettoye = nettoyerNombreImport(brut);
      if (!_nombre.hasMatch(nettoye)) {
        return TextesControleImport.valeurNonNumerique(brut);
      }
      if (c.type == TypeColonneImport.montant && nettoye.startsWith('-')) {
        return TextesControleImport.montantNegatif(brut);
      }
      return null;
    case TypeColonneImport.reference:
      // Libellé EXACT, jamais un rapprochement « au plus proche ».
      return (reference ?? const {}).containsKey(brut)
          ? null
          : TextesControleImport.referenceInconnue(brut, c.libelle);
  }
}

String? _convertir(
  ColonneImport c,
  String valeur,
  Map<String, String>? reference,
) {
  final brut = valeur.trim();
  if (brut.isEmpty) return null;
  return switch (c.type) {
    TypeColonneImport.texte => brut,
    TypeColonneImport.nombre ||
    TypeColonneImport.montant => nettoyerNombreImport(brut),
    // Graphie CANONIQUE : « LOCALE » saisi en capitales devient `locale`.
    TypeColonneImport.liste => (c.valeurs ?? const <String>[]).firstWhere(
      (v) => normaliserImport(v) == normaliserImport(brut),
      orElse: () => brut,
    ),
    TypeColonneImport.reference => reference?[brut],
  };
}
