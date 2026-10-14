/// Un modèle de message — et la composition, qui REFUSE plutôt que de tronquer.
library;

import 'canal_notification.dart';
import 'declencheur_notification.dart';

/// Le résultat d'une composition : un message, ou un refus motivé.
///
/// Un type somme plutôt qu'une exception : la composition échoue pour une
/// raison **normale et attendue** — un modèle relu trop vite —, et l'appelant
/// doit traiter les deux branches. Avec une exception, le cas de refus se
/// serait oublié dans un `try` absent, et le message serait parti avec ses
/// accolades.
sealed class ResultatComposition {
  const ResultatComposition();
}

/// Le message, variables substituées.
final class MessageCompose extends ResultatComposition {
  const MessageCompose({
    required this.contenu,
    required this.longueur,
    this.objet,
  });

  final String? objet;
  final String contenu;

  /// Le nombre de caractères du CONTENU seul — l'objet n'est pas compté, comme
  /// au serveur : c'est le corps que la limite d'un canal borne.
  final int longueur;
}

/// Le refus : une ou plusieurs variables seraient restées littérales.
///
/// Le maître l'écrit en toutes lettres, et c'est la règle qui compte : « un
/// client ne doit jamais lire une accolade ». Le message n'est pas mis en file,
/// pas même tronqué.
final class CompositionRefusee extends ResultatComposition {
  const CompositionRefusee(this.variables);

  final List<String> variables;

  /// Le libellé du maître (`notifications_pwa.variables_non_resolues`).
  String get message =>
      'Variable(s) non résolue(s) : '
      '${variables.map((v) => '{$v}').join(', ')}'
      ' — le message n’est pas mis en file : un client ne doit jamais lire '
      'une accolade.';
}

/// Un modèle de message : une CONFIGURATION, jamais une promesse d'envoi.
///
/// `actif` dit que le modèle « sera pris en compte à la prochaine détection »
/// — les mots du maître. Il ne dit pas qu'un message part.
final class ModeleNotification {
  const ModeleNotification({
    required this.id,
    required this.evenementCode,
    required this.declencheur,
    required this.canalCode,
    required this.canal,
    required this.contenuTemplate,
    required this.actif,
    required this.creeLe,
    this.objet,
    this.modifieLe,
  });

  final String id;

  /// Le code STOCKÉ, toujours présent — même hors registre.
  ///
  /// Il est conservé à côté de [declencheur] pour que l'écran puisse afficher
  /// ce qui est réellement en base quand le registre ne le reconnaît pas. Sans
  /// lui, un modèle orphelin n'aurait plus aucun nom.
  final String evenementCode;

  /// `null` quand [evenementCode] est hors registre — l'anomalie doit se voir.
  final DeclencheurNotification? declencheur;

  final String canalCode;

  /// `null` quand [canalCode] est hors registre.
  final CanalNotification? canal;

  final String contenuTemplate;
  final String? objet;
  final bool actif;
  final DateTime creeLe;
  final DateTime? modifieLe;

  /// Les variables du maître : `{nom}`, minuscules et soulignés.
  ///
  /// Le motif est celui du serveur, au caractère près : l'élargir ferait
  /// reconnaître ici des variables que la composition du serveur laisserait
  /// littérales, et les deux canaux diffuseraient deux textes différents.
  static final RegExp motifVariable = RegExp(r'\{([a-z_]+)\}');

  bool get declencheurHorsRegistre => declencheur == null;

  /// Les variables `{nom}` encore présentes dans le modèle, sans doublon.
  List<String> get variablesCitees {
    final texte = '$contenuTemplate ${objet ?? ''}';
    final vues = <String>{};
    for (final t in motifVariable.allMatches(texte)) {
      final nom = t.group(1);
      if (nom != null) vues.add(nom);
    }
    return vues.toList(growable: false);
  }

  /// Les variables citées que le déclencheur n'offre PAS.
  ///
  /// Le maître le signale en rouge sous l'aperçu : « le message serait
  /// refusé ». Ici, aucun message ne part — mais l'anomalie doit se voir à la
  /// relecture, seul moment où elle est corrigeable gratuitement.
  ///
  /// Un modèle hors registre voit **toutes** ses variables déclarées inconnues :
  /// aucun déclencheur ne les offre, puisqu'aucun déclencheur ne le porte.
  List<String> get variablesInconnues {
    final offertes = declencheur?.variables;
    if (offertes == null) return variablesCitees;
    return variablesCitees
        .where((v) => !offertes.contains(v))
        .toList(growable: false);
  }

  /// Substitue les variables — et refuse si l'une d'elles resterait littérale.
  ///
  /// Une valeur vide est traitée comme ABSENTE, exactement comme au serveur :
  /// « vous devez  FCFA » est aussi faux que « vous devez {montant} FCFA », et
  /// bien plus difficile à repérer à la relecture.
  ResultatComposition composer(Map<String, String> variables) {
    String substituer(String texte) =>
        texte.replaceAllMapped(motifVariable, (t) {
          final cle = t.group(1);
          final valeur = cle == null ? null : variables[cle];
          return valeur == null || valeur.isEmpty ? t.group(0)! : valeur;
        });

    final contenu = substituer(contenuTemplate);
    final objetCompose = objet == null ? null : substituer(objet!);

    final restantes = <String>{};
    for (final t in motifVariable.allMatches(
      '$contenu ${objetCompose ?? ''}',
    )) {
      final nom = t.group(1);
      if (nom != null) restantes.add(nom);
    }

    if (restantes.isNotEmpty) {
      return CompositionRefusee(restantes.toList(growable: false));
    }

    return MessageCompose(
      objet: objetCompose,
      contenu: contenu,
      longueur: contenu.length,
    );
  }
}
