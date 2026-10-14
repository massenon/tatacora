/// M9 Tourisme — **PROPOSITION LIVRÉE. CE FICHIER EST SUPERSÉDÉ.**
///
/// ⚠ **Ce qui suit décrit un état RÉVOLU depuis le 14/09/2026.** La v10 a été
/// ouverte ce jour-là : `duree` vit désormais sur le VRAI `CircuitsLocal`
/// (`tourisme_tables.dart`), la migration est écrite dans `app_database.dart`,
/// le DAO lit la colonne et l'écran en rend les valeurs. La classe
/// `CircuitsLocalV10` ci-dessous est un DOUBLON mort : elle n'est enregistrée
/// nulle part et ne doit jamais l'être — deux classes pour la table
/// `circuits_local` seraient deux vérités.
///
/// Le fichier est conservé, non supprimé, parce qu'il porte la trace de la
/// décision et de son raisonnement ; son retrait est une décision du Product
/// Owner. Ne le citez plus comme « la colonne est proposée en v10 » : cinq
/// messages d'écran le faisaient encore le matin de sa livraison.
///
/// Texte d'origine, conservé tel quel :
///
/// ⚠ **CE FICHIER N'EST ENREGISTRÉ NULLE PART.** Il n'est pas listé dans le
/// `@DriftDatabase` de `app_database.dart`, et il ne le sera que le jour où
/// une v10 sera ouverte, migration additive à l'appui. Tant qu'il ne l'est
/// pas, **aucune de ces colonnes n'existe en base** : l'écran Tourisme les
/// rend « — » avec leur raison, et ne les déduit jamais.
///
/// C'est la consigne du lot : « si l'écran exige une colonne absente, ne
/// modifie pas le fichier de tables, signale-la ». Le déclarer ici plutôt que
/// dans un rapport lui donne un endroit où être lu par celui qui ouvrira la
/// v10 — un rapport ne se relit pas au moment où l'on touche le schéma.
///
/// ## La colonne qui manque, et ce qu'elle coûte (ÉTAT D'ORIGINE, RÉVOLU)
///
/// ⚠ Mis à jour le 09/10/2026 : tout ce qui suit est FAUX aujourd'hui. La
/// colonne `duree` existe sur `CircuitsLocal`, elle est écrite par
/// `tourisme_dao.dart` (`enregistrerCircuit`, l.446-472) et lue par le DAO ; la
/// colonne « Durée », l'indicateur « Durée indéterminée » ET le bandeau
/// « N départ(s) à durée indéterminée » sont RENDUS, avec de vrais chiffres. Le
/// tableau ci-dessous est l'état du 14/09/2026 avant la v10, conservé comme
/// trace.
///
/// `circuits.duree` existe **au serveur** (`Circuit::$fillable` porte
/// `duree`), pas dans `CircuitsLocal`. Trois éléments du maître en dépendent,
/// et tous les trois sont donc rendus absents plutôt que devinés :
///
/// | Élément de `pwa/tourisme/departs.blade.php` | État |
/// |---|---|
/// | Colonne « Durée » du catalogue (l.561) | « — » + raison |
/// | Indicateur « Durée indéterminée » (l.162-165) | « — » + raison |
/// | Bandeau « N départ(s) à durée indéterminée » (l.251-258) | non rendu |
///
/// **Compter tous les circuits comme « durée indéterminée » aurait été le
/// pire choix** : le chiffre aurait l'air mesuré, alors qu'il ne mesurerait
/// que l'absence d'une colonne. C'est PA-59/60/61 — un indicateur qui affirme
/// un état qu'il n'a pas vérifié. La RÈGLE, elle, est portée et éprouvée
/// (`domain/departs.dart`, `dureeIndeterminee`) : le jour de la v10, il n'y a
/// que la lecture à brancher.
///
/// ## Ce qui n'est PAS proposé ici, et pourquoi
///
/// Le maître nomme lui-même comme absents du schéma SERVEUR : le numéro de
/// prestation, l'acompte et le reste dû d'une réservation, le véhicule d'un
/// départ, l'indicatif en euros, la page catalogue, le motif de
/// réaffectation. Les ajouter au seul schéma LOCAL en ferait des saisies qui
/// ne remonteraient nulle part et que le serveur ignorerait — une seconde
/// vérité. Ils restent absents des deux côtés, nommés à l'écran.
library;

import 'package:drift/drift.dart';

/// La v10 proposée de `circuits_local` : `duree` en plus, **et rien d'autre**.
///
/// Migration attendue le jour de l'enregistrement — additive, jamais une
/// recréation de table : `circuits_local` porte le catalogue descendu du
/// serveur (`CatalogueDao.alignerCatalogue`), et une table recréée serait vide
/// jusqu'au prochain alignement, donc un point de vente sans rien à vendre le
/// temps d'une coupure.
///
/// ```dart
/// if (from < 10) {
///   await m.addColumn(circuitsLocal, circuitsLocal.duree);
/// }
/// ```
///
/// La colonne est **nullable**, et c'est ce qui rend la migration sûre : les
/// circuits déjà descendus n'ont pas de durée, et leur en attribuer une par
/// défaut (« 1 jour ») inventerait un programme que personne n'a vendu. `null`
/// est d'ailleurs exactement ce que la règle du serveur traite comme
/// « indéterminée ».
class CircuitsLocalV10 extends Table {
  @override
  String get tableName => 'circuits_local';

  TextColumn get id => text()();
  TextColumn get nom => text()();
  TextColumn get theme => text()();
  TextColumn get zone => text()();
  RealColumn get prix => real()();
  IntColumn get capaciteMax => integer()();

  /// `circuits.duree` — un `varchar` **libre** au serveur (PA-51).
  ///
  /// Ce n'est pas une durée exploitable : « Plusieurs jours » en est une
  /// valeur légitime. Un circuit de plusieurs jours ne bloque donc que son
  /// jour de départ, et l'écran le signale au lieu de le calculer.
  TextColumn get duree => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
