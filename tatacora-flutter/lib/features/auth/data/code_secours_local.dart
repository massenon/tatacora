import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/rbac/regle_archivage.dart';
import '../../transverse/data/journal_securite_dao.dart';
import '../../transverse/domain/journal_poste.dart';
import '../domain/mot_de_passe_perdu.dart';
import 'verificateur_hors_ligne.dart';

/// Le CODE DE SECOURS de l'administrateur du poste (29/10/2026, option A du PO :
/// pas de « mot de passe oublié » par e-mail).
///
/// Si le DERNIER administrateur oublie son mot de passe, personne ne peut le
/// réinitialiser. Au premier démarrage, ou depuis « Mon profil → Code de
/// secours », l'administrateur reçoit un code à usage unique (25 caractères en
/// cinq groupes), affiché UNE seule fois, à ranger au coffre. Seul son DÉRIVÉ
/// (PBKDF2, sel neuf) est écrit. Il permet, depuis l'écran de connexion,
/// de réinitialiser CE compte (nom d'utilisateur + code + nouveau mot de passe) ;
/// le code est alors consommé et un NOUVEAU est remis, une seule fois.
///
/// ## Essais limités, refus identique
///
/// Cinq échecs bloquent quinze minutes, **par compte** (colonnes
/// `code_secours_echecs` / `code_secours_dernier_echec_le`) ET **par poste**
/// (les refus du journal de sécurité des quinze dernières minutes : un
/// identifiant inconnu n'a pas de ligne où compter). Le refus est UN SEUL
/// message, que le compte existe ou non, soit administrateur ou non, porte un
/// code ou non ; une vérification de dérivé est TOUJOURS faite (temps
/// comparable). Un compte non administrateur ne peut pas emprunter ce chemin.
///
/// ## Aucune synchronisation
///
/// Les comptes sont LOCAUX au poste : rien ne part, aucun dérivé ne quitte la
/// base. Chaque tentative, réussie ou refusée, est consignée au journal de
/// sécurité (jamais le code, jamais le nouveau mot de passe).
class CodeSecoursLocal {
  CodeSecoursLocal(this._base, {DateTime Function()? horloge})
    : _horloge = horloge ?? DateTime.now,
      _journal = JournalSecuriteDao(_base, horloge: horloge);

  final AppDatabase _base;
  final DateTime Function() _horloge;
  final JournalSecuriteDao _journal;

  /// Pose un NOUVEAU code de secours au compte [login] (administrateur actif) et
  /// le RENDU une seule fois. Sans confirmation : c'est le chemin du PREMIER
  /// démarrage (aucune session n'existe encore) — l'appelant qui a une session
  /// passe par [genererPourSession]. Remplace l'éventuel code précédent.
  Future<String> poser({required String login, String? auteurLogin}) async {
    final ligne = await _administrateur(login);
    if (ligne == null) {
      throw const RefusMotDePassePerdu(MessagesMotDePassePerdu.refusCode);
    }
    final code = GenerateurDeSecret.codeDeSecours();
    final maintenant = _horloge();
    // Le dérivé est calculé HORS de la transaction.
    final v = VerificateurHorsLigne.creer(
      login: ligne.login,
      motDePasse: GenerateurDeSecret.normaliserCode(code),
      maintenant: maintenant,
      iterations: ReglesMotDePassePerdu.iterationsCodeSecours,
    );
    await _base.transaction(() async {
      await _ecrireCode(ligne.id, v, maintenant);
      await _journal.tracer(
        action: ActionJournalPoste.codeSecoursGenere,
        auteurLogin: auteurLogin ?? ligne.login,
        cibleId: ligne.id,
        cibleLogin: ligne.login,
      );
    });
    return code;
  }

  /// « Mon profil → Code de secours » : l'administrateur CONNECTÉ confirme son
  /// mot de passe, puis reçoit un nouveau code (l'ancien cesse de fonctionner).
  /// Réservé aux deux rôles d'administration ; le mot de passe est vérifié contre
  /// le dérivé stocké (jamais comparé en clair).
  Future<String> genererPourSession({
    required String login,
    required String motDePasse,
  }) async {
    final ligne = await _administrateur(login);
    if (ligne == null) {
      throw const RefusMotDePassePerdu(MessagesMotDePassePerdu.mdpIncorrect);
    }
    final verificateur = VerificateurHorsLigne(
      login: ligne.login,
      sel: ligne.sel,
      empreinte: ligne.empreinte,
      iterations: ligne.iterations,
      derniereConnexionEnLigne: ligne.dateMotDePasse,
    );
    if (!verificateur.correspond(motDePasse)) {
      throw const RefusMotDePassePerdu(MessagesMotDePassePerdu.mdpIncorrect);
    }
    return poser(login: ligne.login, auteurLogin: ligne.login);
  }

  /// Le compte [login] porte-t-il un code de secours ? (Pour « Mon profil ».)
  Future<DateTime?> posePar(String login) async {
    final ligne = await (_base.select(
      _base.utilisateursLocal,
    )..where((u) => u.login.equals(_normaliser(login)))).getSingleOrNull();
    return ligne?.codeSecoursGenereLe;
  }

  /// « J'ai perdu mon mot de passe administrateur » : [login] + [code] +
  /// [nouveau] (8 caractères au moins ; la confirmation est un contrôle de
  /// saisie, au formulaire). Rend le NOUVEAU code de secours.
  ///
  /// Réussite : mot de passe posé, « changement obligatoire » levé, dérivé de
  /// l'ancien effacé, compteur remis à zéro, code remplacé — une seule
  /// transaction, avec sa trace.
  ///
  /// @throws RefusMotDePassePerdu un seul message de refus, ou le blocage (avec
  ///   sa durée) — jamais un détail sur ce qui a manqué.
  Future<String> reinitialiser({
    required String login,
    required String code,
    required String nouveau,
  }) async {
    // La forme d'abord : une saisie incomplète ne consomme aucun essai.
    if (nouveau.length < ReglesMotDePassePerdu.longueurMin) {
      throw const RefusMotDePassePerdu(MessagesMotDePassePerdu.tropCourt);
    }
    final maintenant = _horloge();
    final cible = _normaliser(login);
    final ligne = await (_base.select(
      _base.utilisateursLocal,
    )..where((u) => u.login.equals(cible))).getSingleOrNull();

    // 1. Le blocage, par compte puis par poste.
    final reste = await _blocageRestant(ligne, maintenant);
    if (reste != null) {
      await _journal.tracer(
        action: ActionJournalPoste.codeSecoursBloque,
        cibleId: ligne?.id,
        cibleLogin: cible,
      );
      throw RefusMotDePassePerdu(
        MessagesMotDePassePerdu.bloque(_minutes(reste)),
      );
    }

    // 2. Une vérification de dérivé est TOUJOURS faite : sans cela, le temps de
    // réponse dit si le compte existe et s'il porte un code.
    final verificateur = ligne?.codeSecoursEmpreinte == null
        ? VerificateurHorsLigne(
            login: cible,
            sel: _selFactice,
            empreinte: _empreinteFactice,
            iterations: ReglesMotDePassePerdu.iterationsCodeSecours,
            derniereConnexionEnLigne: maintenant,
          )
        : VerificateurHorsLigne(
            login: ligne!.login,
            sel: ligne.codeSecoursSel!,
            empreinte: ligne.codeSecoursEmpreinte!,
            iterations:
                ligne.codeSecoursIterations ??
                ReglesMotDePassePerdu.iterationsCodeSecours,
            derniereConnexionEnLigne: maintenant,
          );
    final codeValide = verificateur.correspond(
      GenerateurDeSecret.normaliserCode(code),
    );

    if (!codeValide ||
        ligne == null ||
        ligne.codeSecoursEmpreinte == null ||
        !ligne.actif ||
        !rolesAdministration.contains(roleNormalise(ligne.role))) {
      await _enregistrerRefus(ligne, cible, maintenant);
      throw const RefusMotDePassePerdu(MessagesMotDePassePerdu.refusCode);
    }

    // 3. Succès : le nouveau mot de passe et le NOUVEAU code.
    final nouveauCode = GenerateurDeSecret.codeDeSecours();
    final v = VerificateurHorsLigne.creer(
      login: ligne.login,
      motDePasse: nouveau,
      maintenant: maintenant,
    );
    final vCode = VerificateurHorsLigne.creer(
      login: ligne.login,
      motDePasse: GenerateurDeSecret.normaliserCode(nouveauCode),
      maintenant: maintenant,
      iterations: ReglesMotDePassePerdu.iterationsCodeSecours,
    );
    await _base.transaction(() async {
      await (_base.update(
        _base.utilisateursLocal,
      )..where((u) => u.id.equals(ligne.id))).write(
        UtilisateursLocalCompanion(
          sel: Value(v.sel),
          empreinte: Value(v.empreinte),
          iterations: Value(v.iterations),
          dateMotDePasse: Value(maintenant),
          changementObligatoire: const Value(false),
          mdpTemporaireExpireLe: const Value(null),
          selPrecedent: const Value(null),
          empreintePrecedente: const Value(null),
          iterationsPrecedentes: const Value(null),
          // Usage unique : l'ancien code est remplacé dans la même écriture.
          codeSecoursSel: Value(vCode.sel),
          codeSecoursEmpreinte: Value(vCode.empreinte),
          codeSecoursIterations: Value(vCode.iterations),
          codeSecoursGenereLe: Value(maintenant),
          codeSecoursEchecs: const Value(0),
          codeSecoursDernierEchecLe: const Value(null),
        ),
      );
      await _journal.tracer(
        action: ActionJournalPoste.codeSecoursUtilise,
        auteurLogin: ligne.login,
        cibleId: ligne.id,
        cibleLogin: ligne.login,
      );
    });
    return nouveauCode;
  }

  // ------------------------------------------------------------------ interne

  static String _normaliser(String login) => login.trim().toLowerCase();

  /// Le compte [login], s'il est un administrateur ACTIF.
  Future<UtilisateurLocal?> _administrateur(String login) async {
    final ligne = await (_base.select(
      _base.utilisateursLocal,
    )..where((u) => u.login.equals(_normaliser(login)))).getSingleOrNull();
    if (ligne == null ||
        !ligne.actif ||
        !rolesAdministration.contains(roleNormalise(ligne.role))) {
      return null;
    }
    return ligne;
  }

  Future<void> _ecrireCode(
    String id,
    VerificateurHorsLigne v,
    DateTime maintenant,
  ) => (_base.update(_base.utilisateursLocal)..where((u) => u.id.equals(id)))
      .write(
        UtilisateursLocalCompanion(
          codeSecoursSel: Value(v.sel),
          codeSecoursEmpreinte: Value(v.empreinte),
          codeSecoursIterations: Value(v.iterations),
          codeSecoursGenereLe: Value(maintenant),
          codeSecoursEchecs: const Value(0),
          codeSecoursDernierEchecLe: const Value(null),
        ),
      );

  /// Combien de temps reste-t-il à attendre ? `null` : pas de blocage.
  Future<Duration?> _blocageRestant(
    UtilisateurLocal? ligne,
    DateTime maintenant,
  ) async {
    Duration? reste;

    // Par COMPTE : cinq échecs, quinze minutes après le dernier.
    if (ligne != null &&
        ligne.codeSecoursEchecs >= ReglesMotDePassePerdu.essaisMax &&
        ligne.codeSecoursDernierEchecLe != null) {
      final fin = ligne.codeSecoursDernierEchecLe!.add(
        ReglesMotDePassePerdu.blocage,
      );
      if (maintenant.isBefore(fin)) reste = fin.difference(maintenant);
    }

    // Par POSTE : cinq refus, tous comptes confondus, dans la fenêtre.
    final refus = await _journal.refusDepuis(
      maintenant.subtract(ReglesMotDePassePerdu.blocage),
    );
    if (refus.length >= ReglesMotDePassePerdu.essaisMax) {
      final fin = refus.first.add(ReglesMotDePassePerdu.blocage);
      if (maintenant.isBefore(fin)) {
        final r = fin.difference(maintenant);
        if (reste == null || r > reste) reste = r;
      }
    }
    return reste;
  }

  Future<void> _enregistrerRefus(
    UtilisateurLocal? ligne,
    String cible,
    DateTime maintenant,
  ) => _base.transaction(() async {
    if (ligne != null) {
      // La fenêtre repart de zéro si le dernier échec est plus vieux que le
      // blocage : cinq échecs étalés sur des semaines ne bloquent personne.
      final recent =
          ligne.codeSecoursDernierEchecLe != null &&
          maintenant.isBefore(
            ligne.codeSecoursDernierEchecLe!.add(ReglesMotDePassePerdu.blocage),
          );
      await (_base.update(
        _base.utilisateursLocal,
      )..where((u) => u.id.equals(ligne.id))).write(
        UtilisateursLocalCompanion(
          codeSecoursEchecs: Value(recent ? ligne.codeSecoursEchecs + 1 : 1),
          codeSecoursDernierEchecLe: Value(maintenant),
        ),
      );
    }
    await _journal.tracer(
      action: ActionJournalPoste.codeSecoursRefuse,
      cibleId: ligne?.id,
      cibleLogin: cible,
    );
  });

  static int _minutes(Duration d) {
    final m = (d.inSeconds / 60).ceil();
    return m < 1 ? 1 : m;
  }

  // Un dérivé qui ne correspond à rien : le calcul PBKDF2 a lieu quand même.
  static const String _selFactice =
      'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
  static const String _empreinteFactice =
      'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
}
