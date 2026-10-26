import '../../comptabilite/domain/correspondance_comptes.dart';
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
  const EnregistrerParametres(this._stockage, {this.verifierCompte});

  final StockageParametres _stockage;

  /// La vérification des clés `compte_<rôle>` contre le plan comptable
  /// (existence, classe du rôle, compte imputable) — celle du serveur
  /// (`EnregistrerParametreService::verifierComptes`).
  final VerificateurCompteDuRole? verifierCompte;

  Future<ResultatEcriture> executer(
    Map<String, Object?> soumis, {
    required bool peutEcrire,
    required String? auteurId,
  }) async {
    if (!peutEcrire) {
      return const EcritureRefusee(motif: refusDroitParametres);
    }

    if (soumis.isEmpty) {
      return const EcritureRefusee(motif: 'Aucun paramètre à enregistrer.');
    }

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

    // 4 : l'état RÉSULTANT, jamais le stocké seul.
    final stocke = await _stockage.lireTout();
    final incoherence = verifierCoherence(etatResultant(stocke, normalisees));
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
            valeur: valeurs[s.cle],
          ),
      ],
      etats: {'tva': etatTva(valeurs), 'mecef': etatMecef(valeurs)},
    );
  }
}
