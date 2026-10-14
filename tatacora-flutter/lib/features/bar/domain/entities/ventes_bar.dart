// Vue Blade maîtresse (PA-183) : pwa/bar/carte.blade.php
/// L'onglet « Ventes du Bar » — les LIGNES de vente du rayon M5.
///
/// Traduction du panneau `ventes` du corps partagé des cartes
/// (`pwa/carte/corps.blade.php` l.555-700) ; les données viennent de
/// `GET /bar/ventes` (PA-197), qui appelle le MÊME service que l'onglet de la
/// PWA (`LignesVenteDuRayonService`) : même filtre de module sur la ligne,
/// mêmes bornes incluses, même total des seules lignes validées.
///
/// ## Aucun montant n'est recalculé en flottant
///
/// Les montants restent des CHAÎNES `decimal:2` jusqu'à l'affichage ; le seul
/// calcul fait ici — le total de la PAGE, que la vue fait en `bcadd` — se fait
/// en centièmes ENTIERS ([sommeDecimale]).
library;

/// Le statut d'une vente, tel que la vue le filtre et le badge le dit.
enum StatutVenteBar {
  validee('validee', 'Validée'),
  annulee('annulee', 'Annulée');

  const StatutVenteBar(this.code, this.libelle);

  /// La valeur du serveur (`Vente::STATUTS`).
  final String code;

  /// `carte_pwa.commun.ventes_statut_*`.
  final String libelle;
}

/// Une ligne de vente du rayon.
final class LigneVenteBar {
  const LigneVenteBar({
    required this.id,
    required this.code,
    required this.nom,
    required this.numero,
    required this.date,
    required this.prixUnitaire,
    required this.quantite,
    required this.montant,
    required this.annulee,
    required this.motifAnnulation,
    required this.utilisateur,
  });

  final String id;

  /// L'identifiant de l'article de carte FIGÉ à la vente — c'est par lui, et
  /// par lui seul, que la ligne retrouve son stock du jour (un article renommé
  /// ne se rattacherait plus par le libellé).
  final String? code;

  /// Le libellé FIGÉ à la vente.
  final String nom;
  final String? numero;
  final DateTime? date;

  /// `decimal:2` en chaîne, jamais converti en flottant.
  final String prixUnitaire;
  final int quantite;
  final String montant;

  /// RG-02 — une vente annulée reste au registre.
  final bool annulee;
  final String? motifAnnulation;

  /// RG-15 — `null` quand la vente n'a pas d'auteur : le tableau rend « — »,
  /// jamais un « système » inventé.
  final String? utilisateur;
}

/// Les compteurs du JEU FILTRÉ ENTIER — calculés par le serveur, jamais ici.
///
/// Un total refait côté client sur la page reçue changerait en tournant les
/// pages : deux vérités sur le même filtre.
final class TotauxVentesBar {
  const TotauxVentesBar({
    required this.lignes,
    required this.annulees,
    required this.totalValide,
  });

  final int lignes;
  final int annulees;

  /// `decimal:2` en chaîne.
  final String totalValide;
}

/// Une page de lignes et les compteurs de son filtre.
final class PageVentesBar {
  const PageVentesBar({
    required this.lignes,
    required this.totaux,
    required this.page,
    required this.derniere,
    required this.parPage,
  });

  final List<LigneVenteBar> lignes;
  final TotauxVentesBar totaux;
  final int page;
  final int derniere;
  final int parPage;

  /// « Affichage de :debut-:fin sur :total » (`ventes_affichage`).
  int get premier => totaux.lignes == 0 ? 0 : (page - 1) * parPage + 1;
  int get dernier => (page - 1) * parPage + lignes.length;

  /// « TOTAL DE LA PAGE » — la somme des lignes VALIDÉES affichées, en
  /// centièmes entiers. Jamais les annulations : elles restent affichées
  /// (RG-02), mais leur montant n'est pas de l'argent.
  String get totalPage => sommeDecimale([
    for (final l in lignes)
      if (!l.annulee) l.montant,
  ]);

  int get annuleesPage => lignes.where((l) => l.annulee).length;
}

/// Les filtres du panneau — PROPRES à l'onglet : ceux du haut de page filtrent
/// la CARTE, jamais les ventes (vue l.556-558).
final class FiltreVentesBar {
  const FiltreVentesBar({
    this.recherche = '',
    this.statut,
    this.du,
    this.au,
    this.page = 1,
  });

  final String recherche;
  final StatutVenteBar? statut;

  /// Bornes INCLUSES, les deux (`ventes_bornes_aide`).
  final DateTime? du;
  final DateTime? au;
  final int page;

  /// `AAAA-MM-JJ`, le format que la route valide (`date_format:Y-m-d`).
  static String? jour(DateTime? d) => d == null
      ? null
      : '${d.year.toString().padLeft(4, '0')}-'
            '${d.month.toString().padLeft(2, '0')}-'
            '${d.day.toString().padLeft(2, '0')}';
}

/// Le filtre RÉELLEMENT appliqué, en clair — la ligne « Filtre appliqué » du
/// document (`EcranDeCarte::descriptionDuFiltreVentes()`, PA-119).
///
/// ⚠ La période vient TOUJOURS en tête, écrite même sans borne (« toutes les
/// dates ») : un journal de ventes sans période affichée laisserait supposer
/// le mois courant, et c'est le premier chiffre qu'un comptable rapproche.
/// Mots de `carte_pwa.filtre_*` et `carte_pwa.periode_*`.
String descriptionFiltreVentes(FiltreVentesBar f) {
  String lisible(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';
  final du = f.du;
  final au = f.au;
  final periode = switch ((du, au)) {
    (final DateTime d, final DateTime a) =>
      'du ${lisible(d)} au ${lisible(a)} (bornes incluses)',
    (final DateTime d, null) => 'à partir du ${lisible(d)} (borne incluse)',
    (null, final DateTime a) => "jusqu'au ${lisible(a)} (borne incluse)",
    (null, null) => 'toutes les dates',
  };
  final terme = f.recherche.trim();
  return [
    'Période : $periode',
    if (f.statut case final s?) 'Statut : ${s.libelle}',
    if (terme.isNotEmpty) 'Recherche : « $terme »',
  ].join(' · ');
}

/// La phrase du compteur, écran ET document — `ventes_compteur` puis
/// `ventes_compteur_annulees`, avec le total déjà mis en forme.
String resumeVentes(TotauxVentesBar t, String totalFormate) => [
  '${t.lignes} ligne(s) · Total validé : $totalFormate',
  if (t.annulees > 0) 'dont ${t.annulees} annulée(s), hors total',
].join(' — ');

/// La somme exacte de montants `decimal:2`, en chaîne `decimal:2`.
///
/// En centièmes ENTIERS : additionner des `double` ferait dériver le total
/// d'un centime au bout de quelques lignes, et le chiffre affiché ne serait
/// plus celui du serveur. Une valeur illisible est ignorée — elle ne vaut pas
/// zéro, elle n'existe pas ; le serveur, lui, n'en rend jamais.
String sommeDecimale(Iterable<String> montants) {
  var centiemes = 0;
  for (final brut in montants) {
    final texte = brut.trim();
    final m = RegExp(r'^(-?)(\d+)(?:\.(\d{1,2}))?$').firstMatch(texte);
    if (m == null) continue;
    final valeur =
        int.parse(m[2]!) * 100 + int.parse((m[3] ?? '0').padRight(2, '0'));
    centiemes += m[1] == '-' ? -valeur : valeur;
  }
  final negatif = centiemes < 0;
  final absolu = centiemes.abs();
  return '${negatif ? '-' : ''}${absolu ~/ 100}.'
      '${(absolu % 100).toString().padLeft(2, '0')}';
}
