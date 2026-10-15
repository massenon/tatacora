import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/etat_du_jour.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/unite_hebergement.dart';
import 'package:tatacora_flutter/features/hebergement/impression/etat_parc.dart';

/// L'export du parc d'hébergement — tableur seulement.
///
/// Il porte sur CE QUI EST AFFICHÉ, toutes pages confondues, et il DIT son
/// filtre (PA-119). Les cas ont au moins DEUX lignes : un export d'une seule
/// ligne passerait avec une boucle qui n'écrirait que la première.
void main() {
  UniteHebergement unite(
    String id,
    String numero,
    String categorie,
    int tarif,
  ) => UniteHebergement(
    id: id,
    numero: numero,
    categorieId: 'c-$categorie',
    categorieLibelle: categorie,
    statut: StatutUnite.libre,
    tarifBase: tarif,
    capaciteMax: 2,
  );

  final unites = [
    unite('u1', 'BNG-01', 'Bungalow', 28000),
    unite('u2', 'BNG-02', 'Bungalow', 28000),
    unite('u3', 'STE-01', 'Suite', 60000),
  ];

  EtatParc etat({
    List<UniteHebergement>? lignes,
    Map<String, EtatDuJour>? etats,
    String portee = EtatParc.sansFiltre,
  }) => EtatParc(
    unites: lignes ?? unites,
    etats:
        etats ??
        {
          'u1': EtatDuJour.libre,
          'u2': EtatDuJour.occupee,
          'u3': EtatDuJour.horsService,
        },
    portee: portee,
    aujourdHui: DateTime(2026, 10, 9),
  );

  List<String> lignesDe(EtatParc e) =>
      e.csv().split('\n').where((l) => l.trim().isNotEmpty).toList();

  test('le fichier est un CSV à BOM UTF-8 et point-virgule (RG-19)', () {
    final octets = etat().csvOctets();
    expect(octets.take(3).toList(), [0xEF, 0xBB, 0xBF]);
    // Les accents survivent : sans BOM, « Unités » s'ouvre « UnitÃ©s ».
    expect(etat().csv(), contains("Unités d'hébergement"));
  });

  test('chaque unité affichée est une ligne : code, catégorie, tarif brut, '
      'état du jour', () {
    final lignes = lignesDe(etat());

    expect(
      lignes,
      contains('Code unité;Catégorie;Tarif de base (FCFA);Statut'),
    );
    // Le tarif part en nombre BRUT : un tableur ne sait pas additionner
    // « 28 000 FCFA ».
    expect(lignes, contains('BNG-01;Bungalow;28000;Libre'));
    expect(lignes, contains('BNG-02;Bungalow;28000;Occupée'));
    expect(lignes, contains('STE-01;Suite;60000;Hors service'));
  });

  test('onze unités donnent onze lignes : aucune troncature à une page', () {
    final onze = [
      for (var i = 1; i <= 11; i++)
        unite('u$i', 'CH-${i.toString().padLeft(2, '0')}', 'Chambre', 15000),
    ];
    final e = etat(
      lignes: onze,
      etats: {for (final u in onze) u.id: EtatDuJour.libre},
    );

    final lignes = lignesDe(e).where((l) => l.startsWith('CH-')).toList();
    expect(lignes, hasLength(11));
    expect(lignes.last, 'CH-11;Chambre;15000;Libre');
  });

  test('l’ordre des lignes est celui de l’écran, sans total inventé', () {
    final lignes = lignesDe(etat());
    final i1 = lignes.indexWhere((l) => l.startsWith('BNG-01'));
    final i2 = lignes.indexWhere((l) => l.startsWith('BNG-02'));
    final i3 = lignes.indexWhere((l) => l.startsWith('STE-01'));
    expect(i1, lessThan(i2));
    expect(i2, lessThan(i3));
    // Un parc n'a pas de total : sommer des tarifs à la nuit n'a aucun sens.
    expect(etat().csv().toLowerCase(), isNot(contains('total')));
  });

  test('le filtre appliqué est écrit DANS le fichier', () {
    final e = etat(lignes: [unites[2]], portee: 'Suite · STE');
    expect(e.csv(), contains('Filtre appliqué : Suite · STE'));
    expect(lignesDe(e).where((l) => l.startsWith('BNG')), isEmpty);
    expect(lignesDe(e).where((l) => l.startsWith('STE-01')), hasLength(1));
  });

  test('l’état du jour dit à quelle DATE il vaut', () {
    expect(
      etat().csv(),
      contains('Le statut est la disponibilité DU JOUR (09/10/2026)'),
    );
  });

  test('une unité sans état calculé porte « — », jamais « Libre »', () {
    final e = etat(etats: {'u1': EtatDuJour.libre});
    final lignes = lignesDe(e);
    expect(lignes, contains('BNG-01;Bungalow;28000;Libre'));
    expect(lignes, contains('BNG-02;Bungalow;28000;—'));
    expect(lignes, contains('STE-01;Suite;60000;—'));
  });

  test('un point-virgule dans une valeur ne casse pas la colonne', () {
    final e = etat(lignes: [unite('u9', 'X;1', 'Suite;luxe', 1), unites[0]]);
    expect(lignesDe(e), contains('X,1;Suite,luxe;1;—'));
  });

  group('decrireFiltre', () {
    test('sans filtre, la phrase de la vue', () {
      expect(EtatParc.decrireFiltre(), 'Aucun filtre — parc complet');
    });

    test('la catégorie, puis la recherche, séparées par « · »', () {
      expect(
        EtatParc.decrireFiltre(categorie: 'Suite', recherche: 'STE'),
        'Suite · STE',
      );
      expect(EtatParc.decrireFiltre(categorie: 'Suite'), 'Suite');
      expect(EtatParc.decrireFiltre(recherche: 'STE'), 'STE');
    });
  });

  test('un parc vide se REFUSE, avec la phrase de la vue', () {
    expect(etat(lignes: const []).vide, isTrue);
    expect(etat().vide, isFalse);
    expect(
      EtatParc.refusVide,
      "Aucune unité ne correspond aux filtres : il n'y a rien à exporter.",
    );
  });
}
