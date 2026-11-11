/// M13 Personnel & Paie — le dossier du personnel, les bulletins et le
/// référentiel de taux, **en local pur**.
///
/// Vue Blade maîtresse (PA-183) : pwa/rh/paie.blade.php
///
/// ## Ce périmètre est une EXTENSION délibérée, pas un oubli
///
/// `app_database.dart` §0 écrit que « M4, M7, M10 à M13 ne sont pas répliqués :
/// leurs écrans affichent *fonctionnalité nécessitant une connexion* hors
/// ligne ». Ces quatre tables l'étendent à M13, sur décision du Product Owner :
/// la paie du Gîte se tient sur le poste de comptoir, sans réseau du tout.
///
/// **Conséquence à ne pas perdre de vue : ces tables ne montent nulle part.**
/// `SynchronisationService::TABLES_SYNCHRONISABLES` ne connaît que
/// `reservations` et `clients` ; une opération sur `employes` ou
/// `bulletins_paie` serait rejetée à chaque tentative. Aucune de ces tables ne
/// porte donc de colonne `statutSync`, aucune écriture n'entre en
/// `sync_queue`, et **aucun écran n'annonce « en attente de
/// synchronisation »** : ce serait l'indicateur qui affirme un état qu'il n'a
/// pas vérifié (PA-59 / PA-60 / PA-61). L'écran dit « enregistré sur ce
/// poste ».
///
/// ## Les montants sont des ENTIERS
///
/// Le serveur porte `DECIMAL(15,2)` et calcule en `bcmath` ; ici, tout montant
/// est un entier de francs CFA — le XOF n'a pas de sous-unité en circulation,
/// et `CalculPaieService` arrondit au franc comme le serveur (arrondi
/// commercial). Un bulletin au centime serait impayable en espèces.
///
/// ## Rien ne se supprime
///
/// Un salarié qui part passe à `statut = 'parti'` (RG-15 : un bulletin doit
/// continuer de porter le nom de son bénéficiaire) ; un bulletin faux s'annule
/// avec un motif obligatoire et reste au dossier. Aucun DAO n'expose de
/// `delete` sur ces deux tables.
///
/// @see EF-M13-01 Dossier du personnel
/// @see EF-M13-07 Calcul de la paie conforme à la réglementation béninoise
/// @see RG-15 Journalisation des opérations
library;

import 'package:drift/drift.dart';

/// Le service (département) d'affectation — nomenclature.
///
/// C'est une **vraie clé étrangère** pour `employes`, jamais un texte libre :
/// l'anti-pattern « Employé / Service en texte libre » a été trouvé quatre fois
/// dans le prototype d'origine, et chaque occurrence produit des lignes
/// orphelines invisibles dans le dossier du bon salarié.
///
/// Sans colonnes d'audit, comme `services` côté serveur : simple nomenclature,
/// sans enjeu de traçabilité financière.
class ServicesRhLocal extends Table {
  TextColumn get id => text()();

  TextColumn get libelle => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Le dossier d'un salarié.
///
/// Distinct du compte d'accès applicatif (`utilisateurs_local`) : tout employé
/// n'a pas de compte, et tout compte n'appartient pas à un employé.
class EmployesLocal extends Table {
  /// UUID posé **côté client**, comme partout dans ce dépôt.
  TextColumn get id => text()();

  /// `EMP-AAAA-NNNNN`, **alloué** sous transaction à la création.
  ///
  /// Jamais dérivé d'une position dans une liste : « le 3ᵉ de la liste »
  /// changerait dès qu'un salarié est ajouté avant lui — et c'est ce numéro
  /// que le bulletin de paie imprime.
  TextColumn get matricule => text()();

  TextColumn get nom => text()();

  TextColumn get prenom => text().withDefault(const Constant(''))();

  /// L'adresse e-mail FACULTATIVE du salarié (v45, 28/10/2026) : destinataire des
  /// notifications e-mail qui le visent (`bulletin_disponible`, composé par le
  /// serveur). Nulle = non renseignée — jamais une adresse déduite. Normalisée
  /// (trim, minuscules) et validée par `adresse_email_facultative.dart`, comme le
  /// serveur (`AdresseEmailFacultative`) ; aucune unicité. Écrite par `EmployeDao`
  /// et par l'aligneur de la descente (qui n'enfile jamais).
  TextColumn get email => text().nullable()();

  TextColumn get poste => text()();

  TextColumn get serviceId => text().references(ServicesRhLocal, #id)();

  DateTimeColumn get dateEmbauche => dateTime()();

  /// Nulle pour un CDI — une fin de contrat inventée ferait sortir un salarié
  /// de l'effectif à une date que personne n'a arrêtée.
  DateTimeColumn get dateFinContrat => dateTime().nullable()();

  /// ⚠ Nul = **non immatriculé**, et ce n'est pas une anomalie de saisie.
  ///
  /// Le bulletin d'un salarié sans numéro CNSS se calcule normalement ; ce
  /// salarié ne peut simplement pas figurer à la déclaration. L'écran le
  /// signale, il ne bloque pas.
  TextColumn get numeroCnss => text().nullable()();

  /// `CDI` | `CDD` | `Stage` | `Journalier` — registre fermé du maître,
  /// vérifié à l'écriture par le DAO.
  TextColumn get typeContrat => text().nullable()();

  /// Salaire de base mensuel, en francs CFA (entier).
  ///
  /// ⚠ **C'est le SEUL montant saisi de tout le module** : c'est une donnée du
  /// contrat de travail. Le net, la CNSS, l'ITS et la part patronale sont
  /// calculés et rendus en lecture seule.
  IntColumn get salaireBase => integer()();

  /// `actif` | `conge` | `suspendu` | `parti`.
  TextColumn get statut => text().withDefault(const Constant('actif'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Le bulletin de paie d'un salarié pour un mois.
///
/// ## Chaque montant est FIGÉ à l'établissement, aucun n'est recalculé
///
/// Les recalculer à l'affichage les reprendrait aux taux d'aujourd'hui : un
/// bulletin de mars relu en décembre changerait de montant si un taux avait
/// bougé entre-temps — sur un document remis au salarié et conservé sans
/// limitation de durée. Même raisonnement que `tarifNuit` figé à la
/// réservation (PA-55).
///
/// ## AUCUNE colonne de charge patronale TOTALE, et c'est le livrable (PA-53)
///
/// [chargesPatronalesConfirmees] porte 19,4 % du brut — CNSS pension 6,4 %,
/// prestations familiales 9 %, VPS 4 %, tous confirmés à la source. Le taux de
/// risques professionnels est « 1 % à 4 % selon l'activité » et n'est pas
/// confirmé pour l'hôtellerie-restauration : **aucune colonne ne l'accueille**.
/// Une colonne `charges_patronales_total` appellerait un jour un chiffre, et ce
/// chiffre serait supposé.
///
/// ## Le VPS n'est JAMAIS une retenue
///
/// Il entre dans [chargesPatronalesConfirmees] et jamais dans
/// [totalRetenues] : c'est une taxe directe à la charge de l'employeur, assise
/// sur le brut sans plafond. L'inscrire en retenue minorerait le net du
/// salarié de 4 % — un bulletin faux, donc une déclaration sociale erronée.
class BulletinsPaieLocal extends Table {
  TextColumn get id => text()();

  /// `BUL-AAAA-NNNNN`, alloué dans la transaction d'établissement.
  TextColumn get numero => text()();

  TextColumn get employeId => text().references(EmployesLocal, #id)();

  /// `AAAA-MM`.
  TextColumn get periode => text()();

  IntColumn get salaireBase => integer()();

  /// Toujours zéro dans ce dépôt, et la raison est écrite : les primes et
  /// retenues du mois vivraient dans une table `primes_sanctions` qu'aucun
  /// code ne touche. La colonne existe parce que le brut est
  /// `salaireBase + totalPrimes` au maître ; la rendre à l'écran comme si elle
  /// était alimentée serait PA-126.
  IntColumn get totalPrimes => integer().withDefault(const Constant(0))();

  IntColumn get totalRetenues => integer()();

  IntColumn get cnssSalarie => integer()();

  IntColumn get its => integer()();

  /// 19,4 % du brut — la part **certaine**. Voir le docblock de la table.
  IntColumn get chargesPatronalesConfirmees => integer()();

  IntColumn get netAPayer => integer()();

  /// `brouillon` | `validee` | `annulee`.
  TextColumn get statut => text().withDefault(const Constant('brouillon'))();

  TextColumn get motifAnnulation => text().nullable()();

  DateTimeColumn get etabliLe => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};

  /// Un seul bulletin par salarié et par période.
  ///
  /// C'est cette contrainte qui rend l'établissement **idempotent** : un
  /// second clic rend le bulletin existant au lieu d'en allouer un second, et
  /// aucun numéro n'est brûlé (même piège que `FactureDao.numeroSuivant()`,
  /// qui ALLOUE et n'est jamais une lecture — PA-101).
  @override
  List<Set<Column>> get uniqueKeys => [
    {employeId, periode},
  ];
}

/// Le référentiel des taux de paie — **modifiable, jamais codé en dur**.
///
/// `05_MODULE_SPECIFICATIONS.md` §M13, point de vigilance juridique : « les
/// taux de charges sociales (CNSS) et barèmes fiscaux doivent être des
/// paramètres système modifiables, jamais codés en dur, la réglementation
/// pouvant évoluer indépendamment des cycles de release ». C'est l'équivalent
/// local de `parametres_systeme`.
///
/// ⚠ **Le taux de risques professionnels n'y entre pas**, et son absence est
/// le comportement voulu : `CalculPaieService` refuse alors de rendre un
/// total de charge patronale (PA-53). Ne jamais « compléter » ce référentiel
/// avec une valeur plausible — elle deviendrait la règle appliquée en
/// production, et personne ne la rouvrirait.
class TauxPaieLocal extends Table {
  /// La clé de paramètre, identique à celle du serveur (`taux_cnss_salarie`…).
  TextColumn get cle => text()();

  /// Le taux en pourcentage, **en texte** : « 3.6 », « 6.4 », « 9 », « 4 ».
  ///
  /// En texte et non en `real` : `3.6` n'est pas représentable exactement en
  /// binaire, et un taux qui dérive d'un millionième au stockage produit un
  /// arrondi différent un mois sur douze. Le calcul le lit comme un rationnel
  /// entier (voir `Taux.depuisTexte`).
  TextColumn get valeur => text()();

  /// D'où vient ce taux. Un taux sans source est un taux deviné.
  TextColumn get description => text().withDefault(const Constant(''))();

  @override
  Set<Column> get primaryKey => {cle};
}
