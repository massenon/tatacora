/// La composition, le filtrage et les indicateurs du journal des ventes.
///
/// ## Des fonctions PURES, montées à part de la base
///
/// Rien ici ne lit Drift : le journal reçoit des paniers déjà lus. C'est ce qui
/// permet d'éprouver le filtrage et les totaux sur des cas construits à la
/// main — y compris ceux qu'une base peine à produire, comme une vente clôturée
/// sans mode de règlement.
///
/// ## Les indicateurs portent sur CE QUI EST AFFICHÉ
///
/// Le maître appelle `rendreKpis(liste)` avec la liste **filtrée**, jamais avec
/// le journal entier. C'est cohérent avec l'export (PA-119) : ce qu'on voit,
/// ce qu'on compte et ce qu'on exporte sont la même chose. Trois portées
/// différentes sur un même écran feraient douter des trois.
library;

import '../../pos/domain/entities/mode_reglement.dart';
import '../../pos/domain/entities/panier.dart';
import '../../pos/domain/entities/reference_catalogue.dart';
import 'entities/vente.dart';

/// Compose le journal depuis les paniers du poste.
///
/// Les paniers **ouverts sont écartés** : ce ne sont pas des ventes (voir
/// l'en-tête de `entities/vente.dart`). Ils ne sont pas silencieusement
/// perdus pour autant — [JournalVentes.paniersOuverts] les compte, et l'écran
/// le dit.
///
/// L'ordre est **antichronologique sur la date de vente**, départagé par
/// l'identifiant : deux ventes clôturées dans la même milliseconde auraient
/// sinon un ordre indéfini, et la liste changerait à chaque rafraîchissement
/// sans qu'aucune donnée n'ait bougé (même raison que `PanierDao.paniers`).
JournalVentes composerJournal({
  required List<Panier> paniers,
  Map<String, String> libellesTables = const {},
  Map<String, String> numeroFactureParPanier = const {},
}) {
  final ventes = <Vente>[];
  var ouverts = 0;

  for (final panier in paniers) {
    final tableId = panier.tableId;
    final vente = Vente.depuisPanier(
      panier,
      libelleTable: tableId == null ? null : libellesTables[tableId],
      numeroFacture: numeroFactureParPanier[panier.id],
    );
    if (vente == null) {
      ouverts++;
      continue;
    }
    ventes.add(vente);
  }

  ventes.sort((a, b) {
    final parDate = b.date.compareTo(a.date);
    return parDate != 0 ? parDate : b.id.compareTo(a.id);
  });

  return JournalVentes(ventes: ventes, paniersOuverts: ouverts);
}

/// Ce que le poste contient : les ventes, et ce qui n'en est pas une.
final class JournalVentes {
  const JournalVentes({required this.ventes, required this.paniersOuverts});

  final List<Vente> ventes;

  /// Le nombre de paniers **encore ouverts**, donc écartés du journal.
  ///
  /// Compté et affiché, jamais avalé : un barman qui ne retrouve pas la table
  /// qu'il vient de servir doit lire *pourquoi* elle n'y est pas, sinon il
  /// conclut que l'écran a perdu sa vente.
  final int paniersOuverts;
}

/// Les critères des sept contrôles de la barre du maître (l.36-48).
final class FiltreVentes {
  const FiltreVentes({
    this.terme = '',
    this.pointVente,
    this.activite,
    this.mode,
    this.statut,
    this.debut,
    this.fin,
  });

  final String terme;
  final String? pointVente;
  final ModuleVendable? activite;
  final ModeReglement? mode;
  final StatutVente? statut;

  /// Bornes **incluses** aux deux extrémités, comme au maître, qui compare des
  /// chaînes `AAAA-MM-JJ`. Exclure la borne de fin ferait disparaître les
  /// ventes du dernier jour d'un mois — celles qu'on cherche justement quand on
  /// arrête une période.
  final DateTime? debut;
  final DateTime? fin;

  bool get estVierge =>
      terme.trim().isEmpty &&
      pointVente == null &&
      activite == null &&
      mode == null &&
      statut == null &&
      debut == null &&
      fin == null;

  FiltreVentes copyWith({
    String? terme,
    Object? pointVente = _absent,
    Object? activite = _absent,
    Object? mode = _absent,
    Object? statut = _absent,
    Object? debut = _absent,
    Object? fin = _absent,
  }) => FiltreVentes(
    terme: terme ?? this.terme,
    // `_absent` distingue « ne change pas » de « remets à null ». Sans lui,
    // aucun filtre ne pourrait être effacé — le bouton « Tous les postes »
    // n'aurait aucun effet, et ce serait un contrôle inerte.
    pointVente: pointVente == _absent ? this.pointVente : pointVente as String?,
    activite: activite == _absent ? this.activite : activite as ModuleVendable?,
    mode: mode == _absent ? this.mode : mode as ModeReglement?,
    statut: statut == _absent ? this.statut : statut as StatutVente?,
    debut: debut == _absent ? this.debut : debut as DateTime?,
    fin: fin == _absent ? this.fin : fin as DateTime?,
  );

  /// La phrase imprimée sur les exports — le filtre **dit** ce qu'il retient
  /// (PA-119). « Aucun filtre » est une information, pas un blanc.
  String get mention {
    final parts = <String>[
      if (debut != null || fin != null)
        'Du ${debut == null ? '…' : _jour(debut!)} au '
            '${fin == null ? '…' : _jour(fin!)}',
      if (statut != null) 'Statut : ${statut!.libelleFiltre}',
      if (pointVente != null) 'Poste : $pointVente',
      if (activite != null) 'Activité : ${activite!.libelle}',
      if (mode != null) 'Règlement : ${mode!.libelle}',
      if (terme.trim().isNotEmpty) 'Recherche : ${terme.trim()}',
    ];
    return parts.isEmpty ? 'Aucun filtre' : parts.join(' · ');
  }

  static String _jour(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  static const Object _absent = Object();
}

/// Applique les sept contrôles, dans l'ordre du maître.
///
/// ## Ce que la recherche NE couvre PAS, délibérément
///
/// **Le numéro de facture.** Le maître cherche un numéro de vente et une
/// table ; ce client n'a pas de numéro de vente (voir [Vente.referenceLocale]),
/// et il serait tentant d'offrir le `F-` à la place. Ce serait précisément le
/// piège de cet écran : on chercherait ici une pièce que le registre des
/// factures sait retrouver, et les deux écrans finiraient par répondre aux
/// mêmes questions — donc par afficher les mêmes totaux.
///
/// La recherche porte donc sur ce qui identifie une **vente** : sa référence
/// locale, son identifiant complet, sa table, son client et son poste.
List<Vente> filtrerVentes(List<Vente> ventes, FiltreVentes filtre) {
  final terme = filtre.terme.trim().toLowerCase();
  final debut = filtre.debut == null ? null : _minuit(filtre.debut!);
  final fin = filtre.fin == null ? null : _minuit(filtre.fin!);

  return ventes
      .where((v) {
        if (terme.isNotEmpty) {
          final champs = [
            v.referenceLocale,
            v.id,
            v.tableLibelle ?? '',
            v.clientNom ?? '',
            v.pointVente ?? '',
          ].join(' ').toLowerCase();
          if (!champs.contains(terme)) return false;
        }
        if (filtre.pointVente != null && v.pointVente != filtre.pointVente) {
          return false;
        }
        if (filtre.mode != null && v.mode != filtre.mode) return false;
        if (filtre.statut != null && v.statut != filtre.statut) return false;

        final jour = _minuit(v.date);
        if (debut != null && jour.isBefore(debut)) return false;
        if (fin != null && jour.isAfter(fin)) return false;

        // `any` et non `every` : une vente qui mêle bar et restaurant appartient
        // aux deux activités. C'est le point même de la règle 4 du panier — les
        // deux tiennent dans la même addition — et l'inverse ferait disparaître du
        // filtre les ventes les plus fournies, celles qui portent le plus d'argent.
        if (filtre.activite != null &&
            !v.lignes.any((l) => l.module == filtre.activite)) {
          return false;
        }
        return true;
      })
      .toList(growable: false);
}

/// Les postes réellement présents dans le journal — jamais une liste écrite à
/// la main.
///
/// Le maître dérive la même liste de ses ventes (`[...new Set(...)].filter
/// (Boolean)`) : un filtre qui propose un poste dont aucune vente ne vient
/// passe pour cassé. Les ventes de séjour n'ont **aucun** poste
/// (`ecran_pos_heberges.dart` n'en passe pas) : elles ne sont donc offertes
/// sous aucune entrée, exactement comme le `filter(Boolean)` du maître.
List<String> postesDuJournal(List<Vente> ventes) {
  final postes = <String>{
    for (final v in ventes)
      if (v.pointVente != null && v.pointVente!.trim().isNotEmpty)
        v.pointVente!,
  }.toList();
  postes.sort();
  return postes;
}

/// Les cinq indicateurs de la bande du maître (l.191-205).
///
/// ## `encaisse` n'est pas `montant`
///
/// Le maître l'écrit en tête de sa page : *« Une consommation portée sur la
/// note de chambre n'est pas dans le tiroir : c'est une créance, réglée au
/// départ du client. Les KPI les séparent, sans quoi le total du jour
/// annoncerait un encaissement qui n'a pas eu lieu. »*
///
/// ## Le troisième cas que le maître n'a pas
///
/// Chez lui, `encaisse` est toujours un booléen. Ici le mode de règlement peut
/// **manquer** (`PanierDao.cloturer` l'accepte nul), et il y a donc trois
/// paquets, pas deux. Ranger le troisième avec l'un des deux ferait entrer en
/// caisse — ou en créance — un argent dont personne n'a dit ce qu'il était
/// devenu, et l'écart entre le chiffre d'affaires et la somme des deux autres
/// ne se verrait nulle part. [ventesSansReglement] existe pour cela, et
/// l'écran l'affiche dès qu'il n'est pas nul.
final class KpisJournalVentes {
  const KpisJournalVentes({
    required this.ventes,
    required this.annulees,
    required this.chiffreAffaires,
    required this.encaisse,
    required this.enNote,
    required this.ventesSansReglement,
    required this.montantSansReglement,
    required this.avecFacture,
  });

  factory KpisJournalVentes.calculer(List<Vente> liste) {
    final validees = liste.where((v) => v.estValidee).toList(growable: false);

    return KpisJournalVentes(
      ventes: validees.length,
      // Le maître compte les annulées comme la différence entre la liste et
      // les validées. Ici on les compte directement : le registre n'a que deux
      // états, mais un troisième ajouté demain serait compté « annulé » par
      // soustraction, sans que rien ne le signale.
      annulees: liste.where((v) => v.estAnnulee).length,
      chiffreAffaires: validees.fold(0, (t, v) => t + v.montant),
      encaisse: validees
          .where((v) => v.encaisse == true)
          .fold(0, (t, v) => t + v.montant),
      enNote: validees
          .where((v) => v.encaisse == false)
          .fold(0, (t, v) => t + v.montant),
      ventesSansReglement: validees.where((v) => v.encaisse == null).length,
      montantSansReglement: validees
          .where((v) => v.encaisse == null)
          .fold(0, (t, v) => t + v.montant),
      avecFacture: liste.where((v) => v.aUneFacture).length,
    );
  }

  /// Ventes **validées**. Les annulées sont comptées à part : les additionner
  /// gonflerait le journal d'un chiffre d'affaires qui n'a pas eu lieu.
  final int ventes;

  final int annulees;

  /// Somme des ventes validées — l'argent facturé, encaissé ou non.
  final int chiffreAffaires;

  /// Réellement dans le tiroir.
  final int encaisse;

  /// Porté sur la note de chambre : une créance, pas un encaissement.
  final int enNote;

  /// Ventes validées dont le mode de règlement n'a **pas été enregistré**.
  final int ventesSansReglement;

  final int montantSansReglement;

  /// Combien de ventes du journal portent une facture.
  ///
  /// Sert à la mention de certification des exports — **dérivée des pièces,
  /// jamais figée** (PA-119). Une vente sans facture n'affirme rien de fiscal.
  final int avecFacture;
}

DateTime _minuit(DateTime d) => DateTime(d.year, d.month, d.day);
