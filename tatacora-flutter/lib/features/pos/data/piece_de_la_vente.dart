import '../../comptabilite/data/moteur_comptable.dart';
import '../../comptabilite/domain/calcul_tva.dart';
import '../../comptabilite/domain/comptes_syscohada.dart';
import '../../depenses/domain/categories_depense.dart';
import '../domain/entities/mode_reglement.dart';
import '../domain/messages_ventes.dart';

/// Le journal d'imputation des ventes — `VenteService::JOURNAL`.
///
/// Imputer les ventes au journal de caisse ou de banque comme les dépenses
/// laisserait le journal des ventes VIDE pour toujours.
const String journalDesVentes = 'VTE';

/// Les modules réellement encaissables — `VenteService::MODULES_ENCAISSABLES`,
/// DANS CET ORDRE : c'est aussi l'ordre de la pièce (deux tickets portant les
/// mêmes articles produisent la même pièce).
///
/// Depuis le 22/10/2026 (directive du PO : « tourisme et location sont
/// encaissables au comptoir, au poste comme au web »), M8 (location de
/// véhicules, `tarif_jour`) et M9 (tourisme, `circuits.prix`) s'ajoutent à M4
/// et M5 : ils ont un catalogue local d'où figer prix et libellé. Vente LIBRE
/// de prestation — voir `CLAUDE.md`, « Tourisme et location au comptoir ».
const List<String> modulesEncaissables = ['M4', 'M5', 'M8', 'M9'];

/// Les modules que le panier d'un SÉJOUR (note de chambre) porte : bar et
/// restaurant. Le tourisme et la location s'encaissent au COMPTOIR, pas sur la
/// note de chambre (`PosHeberges::MODULES_DU_SEJOUR` au serveur) ; la clôture
/// d'un séjour qui en porterait une ligne est refusée, comme sur le web.
const List<String> modulesEncaissablesAuSejour = ['M4', 'M5'];

/// Le compte de produits de chaque module — `VenteService::COMPTES_PRODUIT`.
/// Location (M8) sur 7073 « Locations » ; tourisme (M9) sur 7061 « services
/// vendus » (le plan du PO n'a pas de compte dédié aux circuits).
const Map<String, String> comptesProduitParModule = {
  'M4': ComptesSyscohada.produitPrestations,
  'M5': ComptesSyscohada.produitMarchandises,
  'M8': ComptesSyscohada.produitLocations,
  'M9': ComptesSyscohada.produitPrestations,
};

/// Le compte de TVA facturée de chaque module — `VenteService::COMPTES_TVA` :
/// boissons revendues (M5) sur 4431, prestations servies (M4 repas, M8
/// location, M9 circuit) sur 4432. Table « à valider par le comptable »,
/// comme `ComptesSyscohada`.
const Map<String, String> comptesTvaParModule = {
  'M4': ComptesSyscohada.tvaFactureePrestations,
  'M5': ComptesSyscohada.tvaFactureeBiens,
  'M8': ComptesSyscohada.tvaFactureePrestations,
  'M9': ComptesSyscohada.tvaFactureePrestations,
};

/// Le centre de coût de chaque module — `VenteService::CENTRES_PAR_MODULE` :
/// les comptes 7061/7011 ne distinguent plus restaurant et bar, le centre le
/// fait (RG-12) ; de même « Tourisme » sur 7061 et « Véhicules » sur 7073.
const Map<String, String> centresParModule = {
  'M4': 'Restaurant',
  'M5': 'Bar',
  'M8': 'Véhicules',
  'M9': 'Tourisme',
};

/// Un franc CFA vaut cent centimes de pièce (voir `piece_de_la_depense.dart`).
const int _centimesParFranc = 100;

/// Le libellé porté par TOUTES les lignes de la pièce d'une vente.
///
/// Identique d'une ligne à l'autre, et c'est voulu : faute d'identifiant de
/// pièce (PA-52), il est le seul lien qui rassemble les lignes d'un même
/// encaissement. **Écart du poste** : le serveur y met le numéro de vente
/// `V-AAAA-NNNNN`, que le poste n'a pas (aucune séquence de numéros de vente
/// n'existe ici, voir `ventes/domain/entities/vente.dart`) ; il y met donc la
/// référence locale ET l'identifiant complet du panier, qui est unique.
String libelleDeLaPiece(String panierId) {
  final brut = panierId.replaceAll('-', '').toUpperCase();
  final courte = brut.length <= 8 ? brut : brut.substring(0, 8);
  return '${MessagesVentes.libelleDeLaPiece(courte)} — $panierId';
}

/// Le compte de DÉBIT d'une vente selon le mode — `VenteService::
/// compteDeContrepartie`.
///
/// `note_chambre` : aucune trésorerie ne bouge, la consommation devient une
/// créance client (`4111`). Débiter la caisse gonflerait le fond de caisse d'un
/// argent que personne n'a remis. Les quatre autres modes passent par la table
/// de trésorerie des dépenses (`TresorerieDepense`, réplique de
/// `DepenseService::TRESORERIES`), seule à faire foi : « carte » entre en
/// BANQUE, le TPE crédite le compte bancaire, jamais le tiroir.
String compteDeContrepartie(ModeReglement mode) => switch (mode) {
  ModeReglement.noteChambre => ComptesSyscohada.clients,
  ModeReglement.especes => TresorerieDepense.caisse.compte,
  ModeReglement.mobileMoney => TresorerieDepense.momo.compte,
  ModeReglement.carte => TresorerieDepense.banque.compte,
  ModeReglement.virement => TresorerieDepense.banque.compte,
};

/// La pièce comptable d'une vente — **fonction pure**, réplique de
/// `VenteService::lignesDeLaPiece` et de l'en-tête de pièce d'`enregistrer`.
///
/// * un DÉBIT unique de la contrepartie, du total ;
/// * un CRÉDIT par module sur son compte de produits (HT quand la TVA est
///   active), centre de coût du module ;
/// * un CRÉDIT de TVA par compte de TVA, SEULEMENT quand la part est positive,
///   sans centre (le défaut du compte joue).
///
/// [montantsParModule] : centimes par module, déjà cumulés. Il est RÉORDONNÉ ici
/// (M4 puis M5) : l'ordre du panier ne doit pas changer la pièce.
///
/// ## La TVA est celle du serveur, quirk compris
///
/// La part TVA d'un module est la DIFFÉRENCE `montant - HT`, jamais un second
/// arrondi : c'est ce qui équilibre la pièce au centime. **Sous la convention
/// `ht`**, `ventiler` rend `HT = montant` : la part TVA vaut donc ZÉRO et la
/// pièce ne porte aucune ligne de TVA, alors que le taux est exigé. C'est ce que
/// fait le serveur (le montant du catalogue est pris pour hors taxe sans que la
/// taxe soit ajoutée au montant encaissé) : défaut du SERVEUR répliqué à
/// l'identique, non corrigé, à remonter (D-ticket du lot 6).
///
/// @see RG-11 La pièce est VALIDÉE d'emblée, donc immuable
/// @see EF-M5-06 Vente au comptoir du bar
DemandePiece pieceDeLaVente({
  required String libelle,
  required String dateIso,
  required ModeReglement mode,
  required Map<String, int> montantsParModule,
  required ParametresTva tva,
  required String? Function(String module) centreDuModule,
}) {
  // `ventilerParModule` : les modules encaissables d'abord, dans l'ordre fixe.
  final ordonne = <String, int>{
    for (final m in modulesEncaissables)
      if (montantsParModule.containsKey(m)) m: montantsParModule[m]!,
    for (final e in montantsParModule.entries)
      if (!modulesEncaissables.contains(e.key)) e.key: e.value,
  };

  var total = 0;
  for (final m in ordonne.values) {
    total += m;
  }

  final lignes = <LigneDemandee>[
    LigneDemandee(compte: compteDeContrepartie(mode), debitCentimes: total),
  ];

  final tvaActive = tva.estActive;
  // Dans l'ordre d'insertion, comme le tableau PHP : le premier module qui
  // porte de la TVA ouvre sa ligne.
  final tvaParCompte = <String, int>{};

  for (final e in ordonne.entries) {
    final module = e.key;
    final compte = comptesProduitParModule[module];
    if (compte == null) {
      throw RefusVente(
        MessagesVentes.compteProduitAbsent(
          MessagesVentes.modulesDuServeur[module] ?? module,
        ),
      );
    }

    var credit = e.value;
    if (tvaActive) {
      final ht = tva.ventiler(e.value).htCentimes;
      final compteTva = comptesTvaParModule[module]!;
      tvaParCompte[compteTva] = (tvaParCompte[compteTva] ?? 0) + (e.value - ht);
      credit = ht;
    }

    lignes.add(
      LigneDemandee(
        compte: compte,
        creditCentimes: credit,
        centreId: centreDuModule(module),
      ),
    );
  }

  for (final e in tvaParCompte.entries) {
    if (e.value > 0) {
      lignes.add(LigneDemandee(compte: e.key, creditCentimes: e.value));
    }
  }

  return DemandePiece(
    journal: journalDesVentes,
    date: dateIso,
    libelle: libelle,
    lignes: lignes,
  );
}

/// Les centimes d'un montant en francs entiers.
int centimesDeFrancs(int francs) => francs * _centimesParFranc;
