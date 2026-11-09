import '../../comptabilite/domain/correspondance_comptes.dart';
import '../../comptabilite/domain/forme_juridique.dart';
import 'entities/parametre.dart';
import 'regles_parametres.dart';
import 'registre_parametres_local.dart';
import 'resultats_parametres.dart';

/// Le stockage des paramètres — ce que le cas d'usage exige de la couche
/// données, rien de plus.
///
/// L'interface existe pour DEUX raisons : les règles se testent sans base, et
/// le dépôt réel route cinq clés vers `taux_paie_local` (leur auteur) sans que
/// le cas d'usage le sache.
abstract interface class StockageParametres {
  /// Toutes les valeurs renseignées, clé -> valeur. Une clé absente de la
  /// carte est « non renseignée ».
  Future<Map<String, String>> lireTout();

  /// Écrit le lot ENTIER ou rien (une transaction). `null` = vider la clé.
  /// Rend les clés dont la valeur a réellement changé.
  Future<List<String>> ecrire(
    Map<String, String?> valeurs, {
    required String? auteurId,
  });
}

/// Le message de refus de droit. Écrit ici parce que le contrôle du droit est
/// un geste de CE cas d'usage (voir [EnregistrerParametres.executer]).
const String refusDroitParametres =
    'Vous n’avez pas le droit de modifier les paramètres du système.';

String refusCleInconnue(String cle) =>
    'Le paramètre « $cle » n’existe pas. Aucun paramètre n’est créé depuis '
    'cet écran : une clé que rien ne lit donnerait l’illusion d’un réglage '
    'sans effet.';

/// Juge le compte choisi pour un rôle de la correspondance : la phrase du
/// refus, ou `null`. Le cas d'usage ne lit pas le plan comptable : l'appelant
/// (le fournisseur de l'écran) lui prête cette lecture — voir
/// `verifierCompteDuRoleSurPlan` pour la règle, pure.
typedef VerificateurCompteDuRole =
    Future<String?> Function(RoleCompte role, String numero);

/// Une clé `compte_<rôle>` soumise sans verificateur : refusée. Fermer par
/// défaut (un compte jamais confronté au plan serait imputé sur des pièces
/// validées, donc immuables), ouvrir par câblage.
const String refusVerificateurComptesAbsent =
    'La correspondance des comptes ne peut pas être enregistrée : le plan '
    'comptable de ce poste n’est pas disponible pour la vérifier.';

const String messageEnregistre = 'Paramètres enregistrés.';
const String messageAucunChangement = 'Aucune valeur modifiée.';

/// L'ENREGISTREMENT des paramètres — le seul chemin d'écriture.
///
/// Même ordre de garde que `EnregistrerParametreService` (serveur) :
///  1. le droit `PARAM` en écriture ;
///  2. chaque clé appartient au registre FERMÉ — sinon refus, jamais création ;
///  3. chaque valeur a la forme de son type ;
///  4. l'état RÉSULTANT est cohérent (TVA active sans taux : refusée dans les
///     deux sens) ;
///  5. seulement alors, une écriture atomique.
///
/// ## Seules les clés TOUCHÉES sont écrites
///
/// L'appelant n'envoie que ce que l'utilisateur a modifié ; une clé dont la
/// valeur normalisée égale la valeur stockée n'est PAS réécrite (elle ne
/// figure pas dans `modifiees`, et son horodatage de modification ne bouge
/// pas). Renvoyer le formulaire entier effacerait en silence le changement
/// d'un autre administrateur — ici, d'un autre poste de la même session.
///
/// @see RG-10 paramétrage sans déploiement
/// @see PA-62 / PA-124 cohérence de l'état résultant
class EnregistrerParametres {
  const EnregistrerParametres(
    this._stockage, {
    this.verifierCompte,
    this.affectationActive,
  });

  final StockageParametres _stockage;

  /// Existe-t-il une affectation du résultat ACTIVE (tous exercices) ? Exigée
  /// pour juger un changement de forme juridique, que le serveur refuse tant
  /// qu'une affectation est active. Sans ce jugement (non câblé), le
  /// changement de forme est REFUSÉ : fermer par défaut, ouvrir par câblage.
  final Future<bool> Function()? affectationActive;

  /// La vérification des clés `compte_<rôle>` contre le plan comptable
  /// (existence, classe du rôle, compte imputable) — celle du serveur
  /// (`EnregistrerParametreService::verifierComptes`).
  final VerificateurCompteDuRole? verifierCompte;

  /// [estAdministrateur] : l'auteur est un administrateur (`peutAdministrerComptes`
  /// de son rôle). Seul à pouvoir écrire les clés `reserveAdministrateur` — le mode
  /// de facturation, l'adresse de l'API, l'opérateur, la forme juridique —, comme
  /// au web ; le serveur rejoue la règle sur le compte du jeton d'appairage.
  Future<ResultatEcriture> executer(
    Map<String, Object?> soumis, {
    required bool peutEcrire,
    required String? auteurId,
    bool estAdministrateur = false,
  }) async {
    if (!peutEcrire) {
      return const EcritureRefusee(motif: refusDroitParametres);
    }

    if (soumis.isEmpty) {
      return const EcritureRefusee(motif: 'Aucun paramètre à enregistrer.');
    }

    final stocke = await _stockage.lireTout();

    // 2 et 3 : TOUTES les erreurs de forme sont rendues ensemble, rattachées à
    // leur champ — l'exploitant ne corrige pas un champ par aller-retour.
    final normalisees = <String, String?>{};
    final erreurs = <String, String>{};
    for (final e in soumis.entries) {
      final spec = RegistreParametresLocal.parCle(e.key);
      if (spec == null) {
        erreurs[e.key] = refusCleInconnue(e.key);
        continue;
      }
      switch (normaliser(spec, e.value)) {
        case ValeurNormalisee(:final valeur):
          // Les réglages RÉSERVÉS : réservés aux Administrateurs, comme au web. La
          // forme juridique rendue à sa valeur actuelle n'est pas un changement
          // (le serveur la laisse passer avant de juger le droit).
          final inchangee =
              spec.cle == ClesFacturation.formeJuridique &&
              valeur != null &&
              valeur ==
                  (stocke[spec.cle] ??
                      FormeJuridique.entrepriseIndividuelle.code);
          if (spec.reserveAdministrateur && !estAdministrateur) {
            // Rien à écrire, rien à refuser : la valeur actuelle n'est pas un changement.
            if (inchangee) continue;
            erreurs[e.key] = spec.cle == ClesFacturation.formeJuridique
                ? MessagesReglagesAdministrateur.formeReservee
                : MessagesReglagesAdministrateur.mecefReserve;
            continue;
          }
          normalisees[e.key] = valeur;
        case ValeurRefusee(:final motif):
          erreurs[e.key] = motif;
      }
    }
    // La correspondance des comptes : chaque clé `compte_<rôle>` non vidée est
    // jugée contre le plan (le serveur le fait pour toute écriture, la
    // synchronisation comprise ; ce poste le fait avant d'écrire).
    for (final e in normalisees.entries) {
      final role = RolesCorrespondance.parCle(e.key);
      final numero = e.value;
      if (role == null || numero == null || erreurs.containsKey(e.key)) {
        continue;
      }
      final verificateur = verifierCompte;
      final refus = verificateur == null
          ? refusVerificateurComptesAbsent
          : await verificateur(role, numero);
      if (refus != null) erreurs[e.key] = refus;
    }
    if (erreurs.isNotEmpty) {
      return EcritureRefusee(motif: erreurs.values.first, parCle: erreurs);
    }

    // 3 bis : la forme juridique (09/11/2026) — l'une des trois valeurs (vider
    // n'en est pas une), et refusée TANT QU'UNE AFFECTATION DU RÉSULTAT EST ACTIVE :
    // la pièce passée l'a été sous les règles de l'ancienne forme.
    if (normalisees.containsKey(ClesFacturation.formeJuridique)) {
      final refus = await _jugerFormeJuridique(
        normalisees[ClesFacturation.formeJuridique],
        stocke[ClesFacturation.formeJuridique],
      );
      if (refus != null) {
        return EcritureRefusee(
          motif: refus,
          parCle: {ClesFacturation.formeJuridique: refus},
        );
      }
    }

    // 4 : l'état RÉSULTANT, jamais le stocké seul.
    final resultant = etatResultant(stocke, normalisees);

    // 4 bis : le mode de la facturation normalisée (IFU, opérateur) — ce qu'exige
    // un mode réel doit être là, sinon la première facture échouerait devant le
    // client. Le jeton, jamais reçu ici, est jugé par le serveur.
    final refusMode = verifierFacturationNormalisee(
      resultant,
      normalisees.keys,
    );
    if (refusMode != null) {
      return EcritureRefusee(
        motif: refusMode,
        parCle: {
          for (final c in ClesFacturation.concernees)
            if (normalisees.containsKey(c)) c: refusMode,
        },
      );
    }

    final incoherence = verifierCoherence(resultant);
    if (incoherence != null) {
      return EcritureRefusee(motif: incoherence);
    }

    // 5 : seules les clés dont la valeur change sont écrites.
    final aEcrire = <String, String?>{
      for (final e in normalisees.entries)
        if (stocke[e.key] != e.value) e.key: e.value,
    };
    if (aEcrire.isEmpty) {
      return const EcritureAcceptee(
        message: messageAucunChangement,
        modifiees: [],
      );
    }

    final modifiees = await _stockage.ecrire(aEcrire, auteurId: auteurId);
    return EcritureAcceptee(
      message: modifiees.isEmpty ? messageAucunChangement : messageEnregistre,
      modifiees: modifiees,
    );
  }

  /// Le refus du changement de forme juridique, ou `null`. Même ordre que le
  /// serveur (`verifierFormeJuridique`) : valeur connue, inchangée = rien à juger,
  /// puis affectation active.
  Future<String?> _jugerFormeJuridique(String? valeur, String? stockee) async {
    final admises = [for (final f in FormeJuridique.values) f.code];
    if (valeur == null || !admises.contains(valeur)) {
      return MessagesReglagesAdministrateur.formeInconnue(
        valeur ?? '',
        admises,
      );
    }
    if (valeur == (stockee ?? FormeJuridique.entrepriseIndividuelle.code)) {
      return null;
    }
    final jugement = affectationActive;
    if (jugement == null || await jugement()) {
      return MessagesReglagesAdministrateur.formeAffectationActive;
    }
    return null;
  }

  /// Les paramètres tels que l'écran les affiche : le registre FERMÉ, chaque
  /// valeur lue du stockage (`null` = non renseignée), et les deux états
  /// DÉRIVÉS des valeurs lues.
  Future<Parametres> lire() async {
    final valeurs = await _stockage.lireTout();
    return Parametres(
      definitions: [
        for (final s in RegistreParametresLocal.definitions)
          DefinitionParametre(
            cle: s.cle,
            groupe: s.groupe,
            libelle: s.libelle,
            typeBrut: s.type.code,
            choix: s.choix,
            aide: s.aide,
            choixLibelles: s.choixLibelles,
            reserveAdministrateur: s.reserveAdministrateur,
            valeur: valeurs[s.cle],
          ),
      ],
      etats: {'tva': etatTva(valeurs), 'mecef': etatMecef(valeurs)},
    );
  }
}
