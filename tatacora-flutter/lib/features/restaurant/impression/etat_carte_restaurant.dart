import 'dart:convert';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/format/formats.dart';
import '../../../core/impression/entete_a4.dart';
import '../../../core/impression/entete_etablissement.dart';
import '../../../core/impression/texte_ticket.dart';
import '../../../core/impression/visas.dart';
import '../domain/entities/carte_restaurant.dart';
import '../domain/entities/plat.dart' show CategorieCarte;

/// Les documents de la carte du restaurant — `m4-restaurant-carte.html`
/// l.35-45.
///
/// ## DEUX documents, pas deux formats du même
///
/// Le maître le commente en toutes lettres (l.39-44) : le bouton « PDF »
/// exporte le **tableau de gestion**, qui se consulte ; « Imprimer la fiche des
/// prix » rend un document qui **se lit**, groupé par catégorie, destiné au
/// comptoir et au client. Les fondre en un seul laisserait croire à un seul
/// usage. C'est le même raisonnement que ticket et facture (PA-101).
///
/// ## Aucun de ces documents n'affirme un statut fiscal
///
/// Ni numéro de séquence, ni cachet MECeF : ce sont des états de gestion et une
/// fiche tarifaire, pas des pièces comptables (PA-113).
///
/// ## Tout texte passe par `texteTicket`
///
/// Les polices intégrées du format couvrent Latin-1 et rien de plus :
/// l'apostrophe typographique disparaît réellement du papier, sans erreur ni
/// trace.
final class EtatCarteRestaurant {
  const EtatCarteRestaurant._();

  static const titre = 'Carte du restaurant';

  /// Le titre exact que le maître donne à ce document pour M4 —
  /// `fiche-prix.js` l.91.
  static const titreFiche = 'Fiche des prix — Restaurant';

  /// Les marques de prix imprimées EN REGARD du prix (PA-161 b), dans l'ordre
  /// de la vue : « prix provisoire », puis « prix corrigé à la main ».
  ///
  /// Un tarif posé faute de relevé, imprimé sans sa marque, se lirait comme un
  /// tarif ferme et opposable au comptoir — la version papier de PA-61. La
  /// case à cocher du formulaire de plat PROMET que la marque s'imprime, y
  /// compris sur la fiche remise au client : c'est ce qui rend la promesse vraie.
  static List<String> marquesDePrix(LigneCarteRestaurant l) => [
    if (l.prixProvisoire) 'prix provisoire',
    if (l.prixCorrigeMain) 'prix corrigé à la main',
  ];

  /// Le mot du maître quand une donnée n'existe pas. Une case CSV **vide** dit
  /// « on ne sait pas » ; un zéro dirait « il n'en reste plus ».
  static const String _rien = '';

  /// CSV du tableau — BOM UTF-8 et point-virgule (convention serveur RG-19).
  ///
  /// Le maître écrit « Excel » sur le bouton ; l'écart de FORMAT est nommé au
  /// bloc « Ce que cet écran ne rend pas », pas masqué sous un autre mot.
  static String csv(
    List<LigneCarteRestaurant> lignes, {
    required String filtre,
  }) {
    final tampon = StringBuffer('\u{FEFF}')
      ..writeln('$titre;${_sansPointVirgule(filtre)}')
      ..writeln()
      ..writeln(
        'Article;Categorie;Prix;Ingredients;Portions vendables;Cout matiere;'
        'Marque de prix',
      );

    for (final l in lignes) {
      tampon.writeln(
        [
          _sansPointVirgule(l.libelle),
          _sansPointVirgule(l.categorieLibelle),
          // Nombres bruts : un tableur ne sait pas additionner « 4 500 F ».
          l.prixVente,
          '${l.nbIngredients}',
          l.portionsVendables?.toString() ?? _rien,
          l.coutMatiere ?? _rien,
          // Vide quand le tarif est ferme : une case vide dit « aucune marque ».
          marquesDePrix(l).join(' · '),
        ].join(';'),
      );
    }

    return tampon.toString();
  }

  static List<int> csvOctets(
    List<LigneCarteRestaurant> lignes, {
    required String filtre,
  }) => utf8.encode(csv(lignes, filtre: filtre));

  /// Le **tableau de gestion** — ce que l'écran affiche, filtres compris.
  ///
  /// Un export porte sur CE QUI EST AFFICHÉ et il DIT son filtre (PA-119) :
  /// [filtre] est repris du serveur (`filtres_appliques`), jamais reconstruit
  /// ici — deux formulations du même filtre finiraient par diverger.
  static Future<Uint8List> pdf(
    List<LigneCarteRestaurant> lignes, {
    required String filtre,
    EnteteEtablissement entete = const EnteteEtablissement(),
    DateTime? edition,
  }) async {
    final document = pw.Document();
    final editeLe = edition ?? DateTime.now();

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (c) =>
            enTeteA4(entete: entete, titre: titre, sousTitre: filtre),
        // Un EXPORT : pied de rapport et zone de signatures de la Directive §6
        // (PA-195), comme `pdf/carte.blade.php`.
        footer: (c) => piedRapportA4(
          c.pageNumber,
          c.pagesCount,
          entete: entete,
          edition: editeLe,
        ),
        build: (contexte) => [
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
            ),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignments: {
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
            },
            headers: [
              'Article',
              'Categorie',
              'Prix',
              'Portions',
              'Cout matiere',
              'Marque de prix',
            ].map(texteTicket).toList(),
            data: [
              for (final l in lignes)
                [
                  texteTicket(l.libelle),
                  texteTicket(l.categorieLibelle),
                  texteTicket(
                    formaterMontantDecimal(l.prixVente, suffixe: devise) ??
                        inconnu,
                  ),
                  // « — » et non « 0 » : personne n'a compte.
                  texteTicket(l.portionsVendables?.toString() ?? inconnu),
                  texteTicket(
                    formaterMontantDecimal(l.coutMatiere, suffixe: devise) ??
                        inconnu,
                  ),
                  texteTicket(marquesDePrix(l).join(' · ')),
                ],
            ],
          ),
          zoneSignaturesA4(visas: Visas.directive),
        ],
      ),
    );

    return document.save();
  }

  /// Les groupes de la fiche des prix, dans l'ordre de la vue
  /// (`EcranDeCarte::grouperParCategorie`) : les catégories du registre dans SON
  /// ordre, puis les clés hors registre (dont les plats sans catégorie,
  /// « Autres »). Dans un groupe, le libellé. Une catégorie sans plat n'est pas
  /// imprimée : un intitulé seul laisserait croire à un oubli.
  static List<(String, List<LigneCarteRestaurant>)> groupesDeLaFiche(
    List<LigneCarteRestaurant> lignes,
  ) {
    int rang(LigneCarteRestaurant l) =>
        l.categorie?.index ?? CategorieCarte.values.length;

    final triees = [...lignes]
      ..sort((a, b) {
        final parRang = rang(a).compareTo(rang(b));
        if (parRang != 0) return parRang;
        final parCle = a.categorieBrute.compareTo(b.categorieBrute);
        return parCle != 0 ? parCle : a.libelle.compareTo(b.libelle);
      });

    final groupes = <String, List<LigneCarteRestaurant>>{};
    for (final l in triees) {
      groupes.putIfAbsent(l.categorieLibelle, () => []).add(l);
    }
    return [for (final e in groupes.entries) (e.key, e.value)];
  }

  /// La **fiche des prix** : un document qui se lit, groupé par catégorie.
  ///
  /// **Les plats sans tarif en sont écartés, et leur nombre est rendu.** La
  /// règle est du maître, et sa raison y est écrite (`m4-restaurant-carte.html`
  /// l.107) : *« on ne masque pas : un tarif absent devient négociable au
  /// comptoir »*. Les écarter en silence produirait une fiche qui a l'air
  /// complète ; les imprimer à zéro ferait croire à la gratuité.
  static Future<(Uint8List, int)> ficheDesPrix(
    List<LigneCarteRestaurant> lignes, {
    EnteteEtablissement entete = const EnteteEtablissement(),
  }) async {
    final retenues = lignes
        .where(
          (l) => formaterMontantDecimal(l.prixVente, suffixe: devise) != null,
        )
        .toList(growable: false);
    final ecartes = lignes.length - retenues.length;
    final parCategorie = groupesDeLaFiche(retenues);

    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        header: (c) => enTeteA4(
          entete: entete,
          titre: titreFiche,
          sousTitre: 'Tarifs en vigueur',
        ),
        footer: (c) => piedA4(c.pageNumber, c.pagesCount),
        build: (contexte) => [
          for (final entree in parCategorie) ...[
            pw.Text(
              texteTicket(entree.$1.toUpperCase()),
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            for (final l in entree.$2)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 2),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      texteTicket(l.libelle),
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                    pw.Row(
                      children: [
                        // La marque PRÉCÈDE le prix, comme dans la vue : elle
                        // se lit avant le montant qu'elle qualifie.
                        if (marquesDePrix(l).isNotEmpty)
                          pw.Padding(
                            padding: const pw.EdgeInsets.only(right: 6),
                            child: pw.Text(
                              texteTicket(marquesDePrix(l).join(' · ')),
                              style: const pw.TextStyle(fontSize: 8),
                            ),
                          ),
                        pw.Text(
                          texteTicket(
                            formaterMontantDecimal(
                                  l.prixVente,
                                  suffixe: devise,
                                ) ??
                                inconnu,
                          ),
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            pw.SizedBox(height: 10),
          ],
        ],
      ),
    );

    return (await document.save(), ecartes);
  }

  /// Le suffixe monétaire — « FCFA » partout, PWA comprise : décision du
  /// Product Owner du 11/09/2026 (PA-186), qui renverse le « F » de PA-185.
  /// Ne pas réaligner sur « F ».
  static const String devise = 'FCFA';

  /// Le tiret de l'Article 7, sur le papier comme à l'écran.
  static const String inconnu = '—';

  static String _sansPointVirgule(String valeur) => valeur.replaceAll(';', ',');
}
