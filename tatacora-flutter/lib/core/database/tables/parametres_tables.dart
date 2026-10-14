import 'package:drift/drift.dart';

import 'utilisateurs_table.dart';

/// Les paramètres du système SAISIS sur ce poste — v11 (09/10/2026).
///
/// Équivalent local de `parametres_systeme` (serveur), à une différence près et
/// elle est voulue : **une clé sans ligne est « non renseignée »**, jamais une
/// valeur par défaut. Aucune MIGRATION n'y sème rien : un taux ou un seuil
/// plausible inscrit par une migration deviendrait la règle appliquée en
/// production sans que personne le rouvre (PA-53, PA-19).
///
/// ⚠ Depuis le Lot J2 (14/10/2026, directive du PO), un poste VIERGE reçoit
/// les seize clés ordinaires de `ParametresEtablissementSeeder` (données
/// d'établissement fournies par le PO, `parametresEtablissementInitiaux`), à
/// la création du premier compte et après « Réinitialiser comme neuf », clé
/// absente par clé absente — jamais par-dessus une valeur saisie.
///
/// ## Qui l'écrit, qui la lit, qui la descend (pièges 9 et 11)
///
///  * **Qui l'écrit** : `ParametresDao`, seul auteur — `ecrire`, appelé par
///    le seul `EnregistrerParametres` (écran Paramètres, droit `PARAM` = `C`),
///    et `semerSiAbsentes`, appelé par le seul
///    `ParametresDepotLocal.installerParametresInitiaux` (poste vierge, Lot
///    J2). Aucune migration, aucun autre chemin.
///  * **Qui la lit** : `ParametresDao.lire` pour l'écran, et — module par
///    module, chacun l'écrit dans `SpecParametre.lecteur` — les services qui
///    consomment une clé. Une clé dont `lecteur` est nul n'est lue par PERSONNE
///    à ce jour, et l'écran le dit en toutes lettres.
///  * **Qui la descend** : personne, et c'est délibéré. Le poste ne parle plus à
///    aucun serveur (décision « zéro réseau » du 14/09/2026) ; la table n'a ni
///    `statutSync`, ni file, et aucun écran n'y annonce d'attente.
///
/// ## Ce qu'elle ne porte JAMAIS
///
/// Aucun secret : une clé d'API ou un mot de passe SMTP ne figure pas au
/// registre (`RegistreParametresLocal`), donc ne peut pas arriver ici — et le
/// test structurel refuse tout motif de secret dans une clé.
///
/// ## Les taux de charges sociales n'y vivent PAS
///
/// `taux_cnss_*` et `taux_vps` ont déjà un auteur sur ce poste :
/// `taux_paie_local` (`PaieDao`). Les copier ici ferait deux sources pour le
/// même taux — le piège exact de PA-160/161. Le dépôt des paramètres route ces
/// cinq clés vers `PaieDao`.
///
/// ## Journal d'audit : il n'existe pas sur ce poste
///
/// Aucune table d'audit locale. La trace est donc minimale — qui et quand pour
/// la DERNIÈRE modification de chaque clé — et l'ancienne valeur n'est pas
/// conservée. C'est dit ici plutôt que supposé.
class ParametresSystemeLocal extends Table {
  /// La clé du registre fermé — jamais une chaîne libre.
  TextColumn get cle => text()();

  /// La valeur normalisée par le registre (`true`/`false`, décimal à point…).
  /// Vider un paramètre SUPPRIME la ligne : « non renseigné » n'est pas une
  /// chaîne vide.
  TextColumn get valeur => text()();

  DateTimeColumn get modifieLe => dateTime()();

  /// Qui a saisi la valeur — vraie clé étrangère (RG-15). Nul seulement si
  /// aucune session n'était ouverte, ce que l'écran n'autorise pas.
  TextColumn get modifiePar =>
      text().nullable().references(UtilisateursLocal, #id)();

  @override
  Set<Column> get primaryKey => {cle};
}
