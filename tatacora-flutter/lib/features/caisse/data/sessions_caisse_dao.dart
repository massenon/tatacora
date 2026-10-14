import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../domain/entities/session_caisse.dart';
import '../domain/messages_caisse.dart';
import '../domain/regles_caisse.dart';
import '../domain/repositories/sessions_caisse_repository.dart';

/// Accès Drift aux sessions de caisse — **local pur**, SEUL auteur de
/// `sessions_caisse_local`.
///
/// ## Aucun mixin généré, et c'est délibéré
///
/// Même forme que `DepenseDao` : la table est enregistrée par la session
/// principale, `attachedDatabase.sessionsCaisseLocal` suffit. Aucun `part` de
/// plus, donc aucun mixin vide possible (piège de `panier_dao.dart`).
///
/// ## Le déroulement est celui de `PosComptant`, geste par geste
///
/// Ouvrir : droit d'écriture (le serveur répond 403 avant toute validation),
/// puis forme du fond (`required|numeric|min:0`), puis « déjà ouverte à ce
/// point », puis plage de la colonne, puis écriture. Clôturer : droit, forme du
/// montant compté, « aucune caisse ouverte », forme exploitable par `bcsub`,
/// théorique, plage, écriture. L'ordre est observable dans le message rendu —
/// et confronté au vrai composant (`caisse_contre_serveur_test.dart`).
///
/// ## Aucune pièce comptable — parce que le serveur n'en passe aucune
///
/// `ouvrirCaisse()` et `cloturerCaisse()` n'appellent ni `PasserEcritureService`
/// ni aucun service d'argent : le fond de caisse n'est PAS un mouvement d'argent
/// du grand livre, c'est une mention d'exploitation, et la clôture ne
/// contre-passe rien. Ce DAO n'invoque donc pas le moteur comptable. Un balayage
/// de `lib/` (test) garde ce fait : le jour où le serveur passera une pièce à
/// l'ouverture, ce test devra être rouvert avec elle, dans la même transaction
/// (règle du 31/08/2026).
///
/// ## Rien ne part en file de synchronisation
///
/// Zéro réseau : une session ouverte ici reste ici. L'écran dit « enregistré sur
/// ce poste ».
class SessionsCaisseDao extends DatabaseAccessor<AppDatabase>
    implements SessionsCaisseRepository {
  SessionsCaisseDao(super.db, {Uuid? uuid, DateTime Function()? maintenant})
    : _uuid = uuid ?? const Uuid(),
      _maintenant = maintenant ?? DateTime.now;

  final Uuid _uuid;

  /// Injectable : « depuis 07:00 » et « 24 h » dépendent de l'heure, et un test
  /// qui lit l'horloge réelle échoue un jour sur mille.
  final DateTime Function() _maintenant;

  $SessionsCaisseLocalTable get _t => attachedDatabase.sessionsCaisseLocal;

  SessionCaisse _vers(SessionsCaisseLocalData l) => SessionCaisse(
    id: l.id,
    // La colonne porte un CHECK sur les trois valeurs : un code inconnu ne peut
    // pas venir de ce poste. S'il venait d'ailleurs, on le dirait.
    point:
        PointDeVenteCaisse.depuisCode(l.pointVente) ??
        (throw StateError('Point de vente inconnu : « ${l.pointVente} ».')),
    utilisateurOuvertureId: l.utilisateurOuvertureId,
    dateOuverture: l.dateOuverture,
    fondCentimes: l.montantFondCentimes,
    dateCloture: l.dateCloture,
    theoriqueCentimes: l.montantTheoriqueCentimes,
    constateCentimes: l.montantConstateCentimes,
  );

  /// `whereNull('date_cloture')->latest('date_ouverture')` — le départage par
  /// identifiant rend l'ordre déterministe quand deux sessions de points
  /// différents s'ouvrent dans la même seconde (le serveur ne le départage pas).
  SimpleSelectStatement<$SessionsCaisseLocalTable, SessionsCaisseLocalData>
  _ouvertes() => select(_t)
    ..where((s) => s.dateCloture.isNull())
    ..orderBy([
      (s) => OrderingTerm.desc(s.dateOuverture),
      (s) => OrderingTerm.asc(s.id),
    ]);

  @override
  Future<SessionCaisse?> sessionOuverte(PointDeVenteCaisse point) async {
    final q = _ouvertes()
      ..where((s) => s.pointVente.equals(point.code))
      ..limit(1);
    final l = await q.getSingleOrNull();
    return l == null ? null : _vers(l);
  }

  @override
  Future<SessionCaisse?> sessionOuverteLaPlusRecente() async {
    final q = _ouvertes()..limit(1);
    final l = await q.getSingleOrNull();
    return l == null ? null : _vers(l);
  }

  @override
  Future<List<SessionCaisse>> sessions() async {
    final q = select(_t)
      ..orderBy([
        (s) => OrderingTerm.desc(s.dateOuverture),
        (s) => OrderingTerm.asc(s.id),
      ]);
    return [for (final l in await q.get()) _vers(l)];
  }

  @override
  Future<SessionCaisse> ouvrir({
    required PointDeVenteCaisse point,
    required String? fondSaisi,
    required String auteurId,
    required bool peutEcrire,
  }) async {
    if (!peutEcrire) throw const RefusCaisse(MessagesCaisse.refusDroit);
    final decimal = validerMontantSaisi(fondSaisi, ChampCaisse.fond);

    return transaction(() async {
      if (await sessionOuverte(point) != null) {
        throw const RefusCaisse(
          MessagesCaisse.refusDejaOuverte,
          champ: ChampCaisse.fond,
        );
      }
      final fond = centimesStockables(decimal, ChampCaisse.fond);
      if (auteurId.isEmpty) {
        // `Auth::id()` n'est jamais nul au serveur (la route est authentifiée).
        // Ici, `sessionProvider` peut l'être ; la clé étrangère refuserait de
        // toute façon — autant le dire en français (RG-15).
        throw const RefusCaisse(
          'L\'auteur est inconnu : aucune session n\'est ouverte, et une '
          'ouverture de caisse sans auteur romprait RG-15.',
        );
      }
      final id = _uuid.v4();
      final ouverture = _maintenant();
      await into(_t).insert(
        SessionsCaisseLocalCompanion.insert(
          id: id,
          pointVente: point.code,
          utilisateurOuvertureId: auteurId,
          dateOuverture: ouverture,
          montantFondCentimes: fond,
        ),
      );
      return SessionCaisse(
        id: id,
        point: point,
        utilisateurOuvertureId: auteurId,
        dateOuverture: ouverture,
        fondCentimes: fond,
      );
    });
  }

  @override
  Future<ClotureCaisse> cloturer({
    required PointDeVenteCaisse point,
    required String? constateSaisi,
    required bool peutEcrire,
    int? especesEncaisseesCentimes,
  }) async {
    if (!peutEcrire) throw const RefusCaisse(MessagesCaisse.refusDroit);
    final decimal = validerMontantSaisi(constateSaisi, ChampCaisse.constate);

    return transaction(() async {
      final session = await sessionOuverte(point);
      if (session == null) {
        throw const RefusCaisse(
          MessagesCaisse.refusSansCaisse,
          champ: ChampCaisse.constate,
        );
      }
      exigerBienFormePourBc(decimal, ChampCaisse.constate);

      // Le serveur calcule TOUJOURS le théorique (fond + espèces de la session).
      // Depuis le lot 5 le poste a la source de ces espèces ; une session
      // ouverte sans elles est une erreur d'appel, jamais un théorique `null`.
      final especes =
          especesEncaisseesCentimes ??
          (throw StateError(
            'Les espèces de la session ne sont pas fournies : la clôture ne '
            'fabrique ni théorique ni écart.',
          ));
      final theorique = theoriqueCentimes(
        fondCentimes: session.fondCentimes,
        especesCentimes: especes,
      );
      final ecart = ecartAnnonceCentimes(decimal, theorique);
      final constate = centimesStockables(decimal, ChampCaisse.constate);

      final cloture = _maintenant();
      await (update(_t)..where((s) => s.id.equals(session.id))).write(
        SessionsCaisseLocalCompanion(
          dateCloture: Value(cloture),
          montantTheoriqueCentimes: Value(theorique),
          montantConstateCentimes: Value(constate),
        ),
      );
      return ClotureCaisse(
        session: SessionCaisse(
          id: session.id,
          point: session.point,
          utilisateurOuvertureId: session.utilisateurOuvertureId,
          dateOuverture: session.dateOuverture,
          fondCentimes: session.fondCentimes,
          dateCloture: cloture,
          theoriqueCentimes: theorique,
          constateCentimes: constate,
        ),
        ecartCentimes: ecart,
      );
    });
  }
}
