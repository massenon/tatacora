/// La pièce de facturation — portage Dart de
/// `prototype_v2/assets/js/facture-engine.js`.
///
/// ## Quatre propriétés, et chacune se trompe en silence
///
/// Le moteur du prototype en fige quatre. Aucune ne provoque d'erreur quand
/// elle est enfreinte : c'est précisément pourquoi elles sont écrites, et
/// pourquoi le portage les nomme une par une.
///
/// 1. **Un seul registre, trois origines.** [OrigineFacture] est un filtre, pas
///    un entrepôt. Trois entrepôts donneraient trois séquences de numéros qui
///    se recouvrent, et personne ne le verrait avant un contrôle fiscal.
/// 2. **Les lignes sont copiées, jamais référencées.** [LigneFacture] porte son
///    libellé et son prix ; rien n'est relu depuis un catalogue. *Une facture
///    qui change est une facture fausse.* Même raisonnement que le prix figé au
///    panier (D2) et `tarifNuit` figé à la réservation (PA-55).
/// 3. **Une seule séquence de numéros, à compteur persisté séparément de la
///    liste.** Portée par `SequencesFactureLocal` et `FactureDao.numeroSuivant`.
/// 4. **Annulation par avoir, jamais par effacement.** Aucune méthode de
///    suppression n'existe sur ce registre. C'est la règle RG-11 des écritures
///    comptables : la correction passe exclusivement par contre-passation, et
///    un trou dans une séquence est indistinguable d'une pièce dissimulée.
///
/// ## Le piège MECeF, qui n'est pas dans cette liste et qui est le plus grave
///
/// **Aucune pièce ne se déclare certifiée.** La certification se dérive d'un
/// **vrai** numéro fiscal, jamais d'une intention ni d'une configuration
/// présente — voir `../certification_mecef.dart`, où la règle vit seule.
library;

import '../certification_mecef.dart';

/// D'où vient la pièce — **registre fermé**, jamais une chaîne libre.
///
/// C'est une **colonne** du registre unique. La tentation serait de stocker
/// séparément les tickets du POS comptant, les factures de séjour et les
/// factures émises à la main, puisque l'écran les filtre. Ce serait le même
/// défaut que les deux POS avant correction : trois entrepôts obligeraient à
/// réécrire trois fois la numérotation, l'archivage et l'export — et c'est la
/// troisième copie qui divergerait, celle que personne ne relit.
enum OrigineFacture {
  /// Client de passage, réglé immédiatement.
  posComptant(
    'pos_comptant',
    'POS au comptant',
    'Client de passage, réglé immédiatement',
  ),

  /// Panier de séjour clôturé au départ.
  posSejour('pos_sejour', 'Séjour client hébergé', 'Panier clôturé au départ'),

  /// Émise à la main.
  factureDirecte('facture_directe', 'Facture directe', 'Émise à la main');

  const OrigineFacture(this.code, this.libelle, this.detail);

  final String code;
  final String libelle;
  final String detail;

  /// Une origine hors registre **lève**, elle ne retombe sur rien.
  ///
  /// Retomber sur `posComptant` rangerait une facture de séjour parmi les
  /// ventes de passage : le chiffre du comptoir serait faux et la créance du
  /// client invisible, sans qu'aucune erreur ne soit signalée.
  static OrigineFacture depuisCode(String code) => values.firstWhere(
    (o) => o.code == code,
    orElse: () => throw ArgumentError.value(
      code,
      'origine',
      'Origine de facture inconnue',
    ),
  );
}

/// État de la pièce dans le registre.
///
/// ⚠ **À ne pas confondre avec le cycle MECeF.** `FacturesLocal.statut` —
/// l'autre table, celle transcrite du schéma serveur — porte
/// `brouillon` / `en_attente_certification` / `certifiee` /
/// `echec_certification`. Ce sont deux axes indépendants : une pièce peut être
/// émise et non certifiée, ce qui est d'ailleurs le seul cas existant
/// aujourd'hui. PA-49 fait le même constat côté serveur sur `factures.statut`.
enum StatutPiece {
  emise('emise'),
  annulee('annulee');

  const StatutPiece(this.code);
  final String code;

  static StatutPiece depuisCode(String code) => values.firstWhere(
    (s) => s.code == code,
    orElse: () =>
        throw ArgumentError.value(code, 'statut', 'Statut de pièce inconnu'),
  );
}

/// Les activités qui peuvent apparaître sur une facture — **registre fermé**.
///
/// ## Pourquoi ce n'est pas `ModuleVendable`, le registre du panier
///
/// `ModuleVendable` exclut délibérément **M1 Hébergement** : c'est la forme
/// structurelle donnée à ⚠ **Q3**, qui demande si l'hébergement est une *ligne
/// de panier*. Tant que Q3 n'est pas tranchée, une ligne d'hébergement au
/// panier est inexprimable, et c'est voulu.
///
/// Mais **une facture de départ porte la nuitée** — ce n'est pas un arbitrage,
/// c'est ce qu'une facture est. Réutiliser ici le registre du panier ferait
/// dépendre le contenu de la facture d'une question qui ne la concerne pas, et
/// obligerait à ouvrir M1 au panier pour de mauvaises raisons.
///
/// Les deux registres restent donc distincts, et le pont entre eux est explicite
/// ([depuisModuleVendableCode]). C'est aussi ce qui garantit que la composition
/// d'une facture de séjour passe par `CompositionFactureSejour`, seul endroit
/// où Q3 est lue.
enum ModuleFacturable {
  m1Hebergement('M1', 'Hébergement'),
  m4Restaurant('M4', 'Restaurant'),
  m5Bar('M5', 'Bar'),
  m8Vehicules('M8', 'Location'),
  m9Tourisme('M9', 'Tourisme');

  const ModuleFacturable(this.code, this.libelle);

  final String code;
  final String libelle;

  /// Un code inconnu n'est **jamais** deviné : la lecture échoue.
  ///
  /// Retomber sur `m5Bar` par défaut ferait apparaître une prestation de
  /// tourisme dans le chiffre du bar, et le chiffre serait faux sans que rien
  /// ne le signale (même raison que `ModuleVendable.depuisCode`).
  static ModuleFacturable depuisCode(String code) => values.firstWhere(
    (m) => m.code == code,
    orElse: () =>
        throw ArgumentError.value(code, 'module', 'Module facturable inconnu'),
  );

  /// Pont explicite depuis le registre du panier (`ModuleVendable.code`).
  ///
  /// Nommé plutôt qu'implicite : c'est le seul endroit où les deux registres se
  /// rencontrent, et le jour où Q3 sera tranchée c'est ici qu'on regardera.
  static ModuleFacturable depuisModuleVendableCode(String code) =>
      depuisCode(code);
}

/// Une ligne de facture — **une copie**, jamais une jointure.
///
/// ## La quantité d'un avoir est négative, et c'est une divergence assumée
///
/// Le prototype construit l'avoir en gardant la quantité positive et en
/// stockant un `montant` négatif à côté : sa ligne d'avoir porte donc un
/// montant qui **contredit** le produit de ses deux facteurs.
///
/// Ce portage prend l'autre chemin : le montant est **calculé**
/// (`prixUnitaire × quantite`) et l'avoir porte une quantité négative. Deux
/// raisons, dans cet ordre :
///
///  1. un montant stocké finit toujours par contredire ses facteurs, et c'est
///     le montant stocké qui l'emporte — le défaut nommé dans `LignePanier` ;
///  2. l'invariant `montant = prixUnitaire × quantite` vaut alors sur **toutes**
///     les lignes du registre, avoirs compris. Une seule règle, aucune
///     exception à retenir, et un test peut la vérifier sur toute la base.
///
/// La contrepartie est visible : un avoir imprime « × -2 ». C'est ce qu'un
/// avoir est.
final class LigneFacture {
  const LigneFacture({
    required this.id,
    required this.module,
    required this.libelle,
    required this.prixUnitaire,
    required this.quantite,
    required this.ordre,
    this.codeArticle,
  });

  final String id;

  /// L'activité, **copiée avec la ligne** : c'est ce qui permet de dire d'où
  /// vient l'argent d'une facture mêlant bar et restaurant.
  final ModuleFacturable module;

  /// Libellé **figé à l'émission**.
  final String libelle;

  /// Prix unitaire **figé à l'émission**, en francs CFA.
  final int prixUnitaire;

  /// Négative sur un avoir — voir le docblock de la classe.
  final int quantite;

  /// Rang d'affichage, pour que deux impressions de la même pièce sortent
  /// identiques.
  final int ordre;

  /// Provenance au catalogue d'origine, `null` pour une ligne qui n'en a pas
  /// (la nuitée vient de la réservation). Jamais relu pour recalculer.
  final String? codeArticle;

  /// Montant de ligne — **calculé, jamais stocké**.
  int get montant => prixUnitaire * quantite;

  /// La même ligne, de sens inverse — la brique d'un avoir.
  LigneFacture inversee(String nouvelId) => LigneFacture(
    id: nouvelId,
    module: module,
    libelle: libelle,
    prixUnitaire: prixUnitaire,
    quantite: -quantite,
    ordre: ordre,
    codeArticle: codeArticle,
  );

  @override
  bool operator ==(Object other) => other is LigneFacture && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Une pièce du registre : une facture, ou l'avoir qui la neutralise.
final class PieceFacturation {
  const PieceFacturation({
    required this.id,
    required this.numero,
    required this.origine,
    required this.dateEmission,
    required this.clientNom,
    required this.statut,
    required this.lignes,
    this.clientId,
    this.reservationId,
    this.panierId,
    this.modePaiement,
    this.pointVente,
    this.numeroMecef,
    this.avoirDe,
    this.motifAvoir,
    this.motifAnnulation,
    this.dateAnnulation,
  });

  final String id;

  /// Identité **comptable** — `F-2026-00042`, unique toutes origines
  /// confondues.
  final String numero;

  final OrigineFacture origine;
  final DateTime dateEmission;

  /// Copié à l'émission, comme le libellé d'une ligne.
  final String clientNom;

  final StatutPiece statut;
  final List<LigneFacture> lignes;

  /// `null` pour un client de passage.
  final String? clientId;

  /// Provenance — jamais une source de recalcul.
  final String? reservationId;
  final String? panierId;

  final String? modePaiement;
  final String? pointVente;

  /// Identité **fiscale**. Toujours `null` aujourd'hui : voir
  /// [estCertifiee] et `../certification_mecef.dart`.
  final String? numeroMecef;

  /// Le **numéro** de la pièce que cet avoir neutralise, `null` sur une
  /// facture.
  final String? avoirDe;

  final String? motifAvoir;
  final String? motifAnnulation;
  final DateTime? dateAnnulation;

  /// Montant total, en francs CFA — **calculé depuis les lignes figées**.
  ///
  /// Il est stable parce que les lignes le sont : aucune écriture du registre
  /// ne touche une ligne après l'émission. Le stocker en plus créerait une
  /// seconde source pour un même montant, et deux sources finissent toujours
  /// par diverger.
  int get montantTotal => lignes.fold(0, (t, l) => t + l.montant);

  bool get estAvoir => avoirDe != null;

  bool get estEmise => statut == StatutPiece.emise;

  bool get estAnnulee => statut == StatutPiece.annulee;

  /// Répartition par activité — ce que la facture recouvre, et où.
  Map<ModuleFacturable, int> get ventilation {
    final parModule = <ModuleFacturable, int>{};
    for (final l in lignes) {
      parModule[l.module] = (parModule[l.module] ?? 0) + l.montant;
    }
    return parModule;
  }

  /// Cette pièce porte-t-elle une certification fiscale **réelle** ?
  ///
  /// Toujours `false` aujourd'hui. La règle vit dans un seul fichier —
  /// `../certification_mecef.dart` — pour qu'elle reste trouvable le jour de
  /// l'inscription DGI (PA-17).
  bool get estCertifiee => CertificationMecef.estReelle(numeroMecef);

  /// Le libellé à afficher, qui **dit la vérité** plutôt que de la supposer.
  String get libelleCertification => CertificationMecef.libelle(numeroMecef);

  @override
  bool operator ==(Object other) => other is PieceFacturation && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'PieceFacturation($numero, ${origine.code}, ${statut.code}, '
      '${lignes.length} ligne(s), $montantTotal FCFA)';
}
