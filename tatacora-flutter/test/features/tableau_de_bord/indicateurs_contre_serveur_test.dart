@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/bar/presentation/widgets/modale_export_carte.dart'
    show TextesExport;
import 'package:tatacora_flutter/features/facturation/domain/entities/piece_facturation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/periode_sejour.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/unite_hebergement.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/mode_reglement.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/panier.dart';
import 'package:tatacora_flutter/features/rh/domain/entities/employe.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_api.dart'
    show StockRefuse;
import 'package:tatacora_flutter/features/stocks/domain/calcul_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/etat_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/mouvement_stock.dart';
import 'package:tatacora_flutter/features/tableau_de_bord/data/tableau_de_bord_local.dart';
import 'package:tatacora_flutter/features/tableau_de_bord/domain/entities/tableau_de_bord.dart';
import 'package:tatacora_flutter/features/tableau_de_bord/domain/exploitation_locale.dart';
import 'package:tatacora_flutter/features/ventes/domain/entities/vente.dart';
import 'package:tatacora_flutter/features/tableau_de_bord/domain/indicateurs_locaux.dart';
import 'package:tatacora_flutter/features/tableau_de_bord/domain/periode_locale.dart';
import 'package:tatacora_flutter/features/tableau_de_bord/domain/pilotage_local.dart';
import 'package:tatacora_flutter/features/tableau_de_bord/presentation/ecran_pilotage_consolide.dart'
    show noteExportPilotage, titreExportPilotage;
import 'package:tatacora_flutter/features/tableau_de_bord/presentation/ecran_tableau_de_bord.dart';

/// La période et les indicateurs de M11, CONFRONTÉS au serveur par exécution.
///
/// `tool/tableau_de_bord/exporter_indicateurs.php` charge le VRAI `Periode`
/// (`depuisCode` ET `resoudre`), le VRAI `TableauDeBordService`
/// (`tauxOccupation`, `reservationsEnAttente`, `ventilationParActivite`,
/// `effectif`, `variation`) et le VRAI `Accueil::articlesCritiques` sur un
/// SQLite en mémoire, et rejoue les scénarios qu'on lui donne. Une formule
/// recopiée à la main dans un test ne vérifierait qu'elle-même (piège 12).
///
/// PHP absent, ou `vendor/` absent : le test ÉCHOUE, il ne saute pas.
Future<Map<String, dynamic>> _executer(Map<String, dynamic> cas) async {
  final php = await Process.start('php', [
    'tool/tableau_de_bord/exporter_indicateurs.php',
  ]);
  php.stdin.write(jsonEncode(cas));
  await php.stdin.close();

  final sortie = utf8.decodeStream(php.stdout);
  final erreur = utf8.decodeStream(php.stderr);
  final code = await php.exitCode;

  if (code != 0) {
    fail(
      'Le serveur n’a pas pu rejouer les calculs (php, code $code) : '
      '${await erreur}. C’est un ÉCHEC, pas un saut.',
    );
  }
  return jsonDecode(await sortie) as Map<String, dynamic>;
}

String _horodatage(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')} '
    '${d.hour.toString().padLeft(2, '0')}:'
    '${d.minute.toString().padLeft(2, '0')}:'
    '${d.second.toString().padLeft(2, '0')}';

String _jour(DateTime d) => _horodatage(d).substring(0, 10);

/// Une demande de période, côté poste ET côté serveur : la fenêtre que le poste
/// calcule, et la requête que le script PHP rejoue avec la vraie classe.
typedef _Demande = ({
  String etiquette,
  FenetreTableauDeBord fenetre,
  Map<String, Object?> requete,
});

_Demande _aDate(PeriodeADate p, DateTime reference) => (
  etiquette: 'à date ${p.code} @ ${_horodatage(reference)}',
  fenetre: FenetreTableauDeBord.depuis(p, reference),
  requete: {'code': p.code, 'reference': _horodatage(reference)},
);

_Demande _calendaire(
  PeriodeTableauDeBord p,
  DateTime reference, {
  DateTime? du,
  DateTime? au,
}) => (
  etiquette:
      'calendaire ${p.code} @ ${_horodatage(reference)}'
      '${du == null && au == null ? '' : ' (du $du au $au)'}',
  fenetre: FenetreTableauDeBord.resoudre(
    SelectionPeriode(p, du: du, au: au),
    reference,
  ),
  requete: {
    'calendaire': p.code,
    'reference': _horodatage(reference),
    // Un champ vide de la vue arrive en chaîne vide.
    'du': du == null ? '' : _jour(du),
    'au': au == null ? '' : _jour(au),
  },
);

Reservation _reservation(
  String id,
  StatutReservation statut,
  DateTime arrivee,
  int nuits,
  DateTime creeeLe,
) => Reservation(
  id: id,
  reference: id,
  clientId: 'c',
  clientNom: 'C',
  uniteId: 'u1',
  periode: PeriodeSejour(
    arrivee: arrivee,
    depart: DateTime(arrivee.year, arrivee.month, arrivee.day + nuits),
  ),
  tarifNuit: 10000,
  statut: statut,
  statutSynchronisation: StatutSynchronisation.local,
  creeeLe: creeeLe,
);

UniteHebergement _unite(String id, StatutUnite statut) => UniteHebergement(
  id: id,
  numero: id,
  categorieId: 'k',
  categorieLibelle: 'K',
  statut: statut,
  tarifBase: 10000,
  capaciteMax: 2,
);

Employe _employe(StatutEmploye statut) => Employe(
  id: 'e',
  matricule: 'E',
  nom: 'N',
  prenom: 'P',
  poste: 'x',
  serviceId: 's',
  serviceLibelle: 'S',
  dateEmbauche: DateTime(2025, 1, 1),
  salaireBase: 100000,
  statut: statut,
);

/// Les périodes personnalisées éprouvées : ordinaire, un seul jour, à cheval
/// sur deux années, INVERSÉE (que le serveur accepte), une seule borne, aucune.
final List<(DateTime?, DateTime?)> _bornesPersonnalisees = [
  (DateTime(2026, 10, 5), DateTime(2026, 10, 20)),
  (DateTime(2026, 10, 10), DateTime(2026, 10, 10)),
  (DateTime(2026, 12, 20), DateTime(2027, 1, 10)),
  (DateTime(2026, 10, 20), DateTime(2026, 10, 5)),
  (null, DateTime(2026, 10, 5)),
  (DateTime(2026, 10, 5), null),
  (null, null),
];

void main() {
  // Des dates choisies pour casser une règle approximative : fin de mois, fin
  // de trimestre, 1er janvier, 29 février, première seconde d'un trimestre,
  // et des DIMANCHES (« Cette semaine » commence le lundi).
  final references = <DateTime>[
    DateTime(2026, 10, 10, 14, 30),
    DateTime(2026, 1, 1, 0, 0, 0),
    DateTime(2026, 12, 31, 23, 59, 59),
    DateTime(2028, 2, 29, 12),
    DateTime(2026, 3, 31, 8),
    DateTime(2026, 7, 1, 0, 0, 1),
    DateTime(2026, 6, 30, 23, 59),
    DateTime(2026, 9, 30, 6),
    DateTime(2026, 4, 1, 9),
    DateTime(2027, 3, 1),
    DateTime(2026, 10, 11, 23), // dimanche
    DateTime(2027, 1, 3, 8), // dimanche, la semaine commence en 2026
    DateTime(2026, 3, 1, 10), // dimanche, 1er du mois
  ];

  group('La période locale est celle du serveur', () {
    late Map<String, dynamic> reponse;
    late List<_Demande> demandes;

    setUpAll(() async {
      demandes = [
        // Le sélecteur de l'écran : `Periode::resoudre`.
        for (final p in PeriodeTableauDeBord.values)
          if (p != PeriodeTableauDeBord.personnalisee)
            for (final r in references) _calendaire(p, r),
        for (final (du, au) in _bornesPersonnalisees)
          for (final r in [
            DateTime(2026, 10, 10, 14, 30),
            DateTime(2027, 2, 1),
          ])
            _calendaire(PeriodeTableauDeBord.personnalisee, r, du: du, au: au),
        // L'aperçu M14 : `Periode::depuisCode`.
        for (final p in PeriodeADate.values)
          for (final r in references) _aDate(p, r),
      ];
      reponse = await _executer({
        'requetes': [for (final d in demandes) d.requete],
      });
    });

    test('calendaire (sept codes, dont la période personnalisée) et « à '
        'date » (cinq codes) : bornes, durée et libellé, courant ET '
        'précédent', () {
      final resultats = (reponse['resultats'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(
        resultats,
        hasLength(demandes.length),
        reason: 'balayage non vide',
      );
      expect(demandes, hasLength(6 * 13 + 7 * 2 + 5 * 13));

      for (var i = 0; i < demandes.length; i++) {
        final d = demandes[i];

        void comparer(FenetreTableauDeBord f, Map<String, dynamic> serveur) {
          expect(_horodatage(f.debut), serveur['debut'], reason: d.etiquette);
          expect(_horodatage(f.finExclue), serveur['fin'], reason: d.etiquette);
          expect(f.nombreJours, serveur['jours'], reason: d.etiquette);
          expect(f.libelle, serveur['libelle'], reason: d.etiquette);
        }

        comparer(d.fenetre, resultats[i]['periode'] as Map<String, dynamic>);
        comparer(
          d.fenetre.precedente,
          resultats[i]['precedente'] as Map<String, dynamic>,
        );
      }
    });

    test('le sélecteur est celui de la vue : mêmes codes dans le même ordre, '
        'mêmes libellés (apostrophe droite), même défaut', () {
      final selecteur = reponse['selecteur'] as Map<String, dynamic>;
      final codes = (selecteur['codes'] as List<dynamic>).cast<String>();
      final libelles = (selecteur['libelles'] as Map<String, dynamic>)
          .cast<String, String>();
      expect(codes, hasLength(7), reason: 'balayage non vide');
      expect([for (final p in PeriodeTableauDeBord.values) p.code], codes);
      // L'ordre des options du `<select>` est celui du tableau de langue.
      expect(libelles.keys.toList(), codes);
      for (final p in PeriodeTableauDeBord.values) {
        expect(p.libelle, libelles[p.code], reason: p.code);
      }
      // `Accueil::$filtrePeriode`, lu par réflexion — pas recopié.
      expect(selecteur['defaut'], 'mois');
      expect(PeriodeTableauDeBord.parDefaut.code, selecteur['defaut']);
      expect(SelectionPeriode.parDefaut.periode, PeriodeTableauDeBord.mois);
    });

    test('« Ce trimestre » au 10/10 couvre le trimestre ENTIER (calendaire) ; '
        'l’aperçu M14 s’arrête ce soir (« à date »)', () {
      final calendaire = FenetreTableauDeBord.resoudre(
        const SelectionPeriode(PeriodeTableauDeBord.trimestre),
        DateTime(2026, 10, 10, 14, 30),
      );
      expect(calendaire.debut, DateTime(2026, 10));
      expect(calendaire.finExclue, DateTime(2027));
      expect(calendaire.nombreJours, 92);

      final aDate = FenetreTableauDeBord.depuis(
        PeriodeADate.trimestre,
        DateTime(2026, 10, 10, 14, 30),
      );
      expect(aDate.nombreJours, 10);
      expect(aDate.finExclue, DateTime(2026, 10, 11));
    });
  });

  group('Les huit cartes disent ce que dit la vue', () {
    test('libellés et notes = lang/fr/accueil_pwa.php, clé par clé', () async {
      final reponse = await _executer({'requetes': <dynamic>[]});
      final kpi = (reponse['kpi'] as Map<String, dynamic>)
          .cast<String, dynamic>();
      expect(kpi.keys, hasLength(8), reason: 'balayage non vide');
      expect(EcranTableauDeBord.libelles.keys.toSet(), kpi.keys.toSet());
      expect(EcranTableauDeBord.notes.keys.toSet(), kpi.keys.toSet());
      for (final cle in kpi.keys) {
        final langue = kpi[cle] as Map<String, dynamic>;
        expect(
          EcranTableauDeBord.libelles[cle],
          langue['libelle'],
          reason: cle,
        );
        expect(EcranTableauDeBord.notes[cle], langue['note'], reason: cle);
      }
    });

    test(
      'la modale d’export du pilotage : bouton, titre et sous-titre = '
      'pwa.export.bouton, accueil_pwa.export_titre, modale_rapport.note',
      () async {
        final reponse = await _executer({'requetes': <dynamic>[]});
        final export = (reponse['export'] as Map<String, dynamic>)
            .cast<String, String>();
        expect(export, hasLength(3), reason: 'balayage non vide');
        expect(TextesExport.bouton, export['bouton']);
        expect(titreExportPilotage, export['titre']);
        expect(noteExportPilotage, export['sous_titre']);
      },
    );
  });

  group(
    'La locale de Carbon est celle du serveur (`fr`), pas celle du poste',
    () {
      test('« Cette semaine » commence le LUNDI même quand la locale ambiante '
          'de Carbon est `en_US` (dimanche) — le script impose `fr`', () async {
        // Trois dimanches et un lundi : en `en_US`, le dimanche OUVRE sa propre
        // semaine ; en `fr`, il FERME celle du lundi précédent.
        final demandes = [
          for (final r in [
            DateTime(2026, 10, 11, 23),
            DateTime(2027, 1, 3, 8),
            DateTime(2026, 3, 1, 10),
            DateTime(2026, 10, 12, 9),
          ])
            _calendaire(PeriodeTableauDeBord.semaine, r),
        ];
        final reponse = await _executer({
          'locale_ambiante': 'en_US',
          'requetes': [for (final d in demandes) d.requete],
        });
        expect(reponse['carbon_locale'], 'fr');
        final resultats = (reponse['resultats'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        expect(
          resultats,
          hasLength(demandes.length),
          reason: 'balayage non vide',
        );
        for (var i = 0; i < demandes.length; i++) {
          final serveur = resultats[i]['periode'] as Map<String, dynamic>;
          expect(
            _horodatage(demandes[i].fenetre.debut),
            serveur['debut'],
            reason: demandes[i].etiquette,
          );
          // Un lundi, toujours (DateTime.monday == 1).
          expect(
            DateTime.parse(serveur['debut'] as String).weekday,
            DateTime.monday,
            reason: demandes[i].etiquette,
          );
        }
      });
    },
  );

  group('Les indicateurs calculés sont ceux du serveur', () {
    // Un scénario ALÉATOIRE mais reproductible, plus des cas aux bornes.
    final alea = Random(20261010);
    final unites = [
      _unite('u1', StatutUnite.libre),
      _unite('u2', StatutUnite.occupee),
      _unite('u3', StatutUnite.reservee),
      _unite('u4', StatutUnite.nettoyage),
      _unite('u5', StatutUnite.horsService),
      _unite('u6', StatutUnite.horsService),
    ];
    final statuts = StatutReservation.values;
    final reservations = <Reservation>[
      for (var i = 0; i < 70; i++)
        _reservation(
          'r$i',
          statuts[alea.nextInt(statuts.length)],
          DateTime(2026, 5, 1).add(Duration(days: alea.nextInt(190))),
          1 + alea.nextInt(9),
          DateTime(
            2026,
            5,
            1,
            alea.nextInt(24),
            alea.nextInt(60),
          ).add(Duration(days: alea.nextInt(190))),
        ),
      // Aux bornes de « 30 jours » au 10/10/2026 (11/09 -> 11/10) :
      // créée pile à minuit de la borne EXCLUE — comptée DEUX fois par le
      // serveur (`whereBetween`, les deux bornes incluses).
      _reservation(
        'borne-exclue',
        StatutReservation.enAttente,
        DateTime(2026, 10, 20),
        2,
        DateTime(2026, 10, 11),
      ),
      _reservation(
        'borne-debut',
        StatutReservation.enAttente,
        DateTime(2026, 10, 20),
        2,
        DateTime(2026, 9, 11),
      ),
      _reservation(
        'veille-debut',
        StatutReservation.enAttente,
        DateTime(2026, 10, 20),
        2,
        DateTime(2026, 9, 10, 23, 59, 59),
      ),
      // Séjour à cheval sur la borne de début ET sur la borne de fin.
      _reservation(
        'cheval',
        StatutReservation.confirmee,
        DateTime(2026, 9, 8),
        40,
        DateTime(2026, 9, 1),
      ),
      // Un long séjour qui ENJAMBE la période personnalisée inversée « du 20
      // au 5 octobre » : le serveur y somme des nuits NÉGATIVES (D297).
      _reservation(
        'longue',
        StatutReservation.confirmee,
        DateTime(2026, 10, 1),
        25,
        DateTime(2026, 9, 1),
      ),
    ];
    final salaries = [
      for (final s in StatutEmploye.values) ...[_employe(s), _employe(s)],
      _employe(StatutEmploye.actif),
    ];
    final pieces = <PieceFacturation>[
      for (var i = 0; i < 25; i++)
        PieceFacturation(
          id: 'p$i',
          numero: 'F$i',
          origine: OrigineFacture.factureDirecte,
          dateEmission: DateTime(
            2026,
            8,
            1,
            alea.nextInt(24),
          ).add(Duration(days: alea.nextInt(90))),
          clientNom: 'C',
          statut: StatutPiece.emise,
          lignes: [
            for (var l = 0; l < 1 + alea.nextInt(3); l++)
              LigneFacture(
                id: 'p$i-$l',
                module: ModuleFacturable
                    .values[alea.nextInt(ModuleFacturable.values.length)],
                libelle: 'x',
                prixUnitaire: 500 * (1 + alea.nextInt(40)),
                // Les avoirs ont une quantité négative au registre.
                quantite: alea.nextInt(5) == 0 ? -1 : 1 + alea.nextInt(3),
                ordre: l,
              ),
          ],
        ),
    ];

    final datesDeReference = [
      DateTime(2026, 10, 10, 14, 30),
      DateTime(2026, 9, 30, 10),
      DateTime(2026, 11, 20),
      DateTime(2026, 12, 31, 23),
    ];
    final demandes = <_Demande>[
      for (final p in PeriodeTableauDeBord.values)
        if (p != PeriodeTableauDeBord.personnalisee)
          for (final r in datesDeReference) _calendaire(p, r),
      for (final (du, au) in _bornesPersonnalisees)
        _calendaire(
          PeriodeTableauDeBord.personnalisee,
          DateTime(2026, 10, 10, 14, 30),
          du: du,
          au: au,
        ),
      for (final p in PeriodeADate.values)
        for (final r in datesDeReference) _aDate(p, r),
    ];

    late Map<String, dynamic> reponse;

    setUpAll(() async {
      reponse = await _executer({
        'requetes': [for (final d in demandes) d.requete],
        'unites': [
          for (final u in unites) {'id': u.id, 'statut': u.statut.code},
        ],
        'reservations': [
          for (final r in reservations)
            {
              'id': r.id,
              'statut': r.statut.code,
              'arrivee': _jour(r.periode.arrivee),
              'depart': _jour(r.periode.depart),
              'creee_le': _horodatage(r.creeeLe),
            },
        ],
        'employes': [
          for (final e in salaries) {'statut': e.statut.code},
        ],
        'factures': [
          for (final p in pieces)
            {
              'id': p.id,
              'date_emission': _horodatage(p.dateEmission),
              'lignes': [
                for (final l in p.lignes)
                  {'module': l.module.code, 'montant': '${l.montant}.00'},
              ],
            },
        ],
      });
    });

    test('taux d’occupation, réservations en attente et variations : '
        'fenêtres calendaires, personnalisées et « à date », courant et '
        'précédent', () {
      final resultats = (reponse['resultats'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(resultats, hasLength(demandes.length));

      var comparaisonsNonTriviales = 0;
      var tauxNegatifsConfrontes = 0;
      for (var i = 0; i < demandes.length; i++) {
        final d = demandes[i];
        final fenetre = d.fenetre;
        final avant = fenetre.precedente;
        final serveur = resultats[i];
        final courant = serveur['courant'] as Map<String, dynamic>;
        final precedent = serveur['avant'] as Map<String, dynamic>;

        final taux = tauxOccupationCentiemes(
          unites: unites,
          reservations: reservations,
          fenetre: fenetre,
        );
        final tauxAvant = tauxOccupationCentiemes(
          unites: unites,
          reservations: reservations,
          fenetre: avant,
        );
        expect(
          centiemesEnChaine(taux!),
          courant['taux_occupation'],
          reason: d.etiquette,
        );
        expect(
          centiemesEnChaine(tauxAvant!),
          precedent['taux_occupation'],
          reason: d.etiquette,
        );
        if (fenetre.nombreJours < 0 && taux != 0) tauxNegatifsConfrontes++;

        final attente = reservationsEnAttente(reservations, fenetre);
        final attenteAvant = reservationsEnAttente(reservations, avant);
        expect(
          attente,
          courant['reservations_en_attente'],
          reason: d.etiquette,
        );
        expect(
          attenteAvant,
          precedent['reservations_en_attente'],
          reason: d.etiquette,
        );

        final variations = serveur['variations'] as Map<String, dynamic>;
        expect(
          variationEnPourcent(
            centiemesEnChaine(taux),
            centiemesEnChaine(tauxAvant),
          ),
          variations['taux_occupation'],
          reason: '${d.etiquette} — variation du taux',
        );
        expect(
          variationEnPourcent('$attente', '$attenteAvant'),
          variations['reservations_en_attente'],
          reason: '${d.etiquette} — variation des réservations',
        );

        if (variations['taux_occupation'] != null ||
            variations['reservations_en_attente'] != null) {
          comparaisonsNonTriviales++;
        }
      }
      // Garde contre un balayage vert à vide : des variations NON nulles ont
      // bien été confrontées, pas seulement des « pas de comparaison ».
      expect(comparaisonsNonTriviales, greaterThan(3));
      // Et la période inversée a réellement produit des nuits négatives,
      // sommées comme au serveur (sinon le cas ne prouverait rien).
      expect(tauxNegatifsConfrontes, greaterThan(0));
    });

    test('les cas aux bornes comptent comme le serveur : minuit de la borne '
        'exclue est compté dans les DEUX fenêtres', () {
      final f = FenetreTableauDeBord.depuis(
        PeriodeADate.trenteJours,
        DateTime(2026, 10, 10, 14, 30),
      );
      final i = demandes.indexWhere(
        (d) => d.etiquette == 'à date 30j @ 2026-10-10 14:30:00',
      );
      expect(i, isNonNegative);
      final serveur =
          (reponse['resultats'] as List<dynamic>)[i] as Map<String, dynamic>;
      // Les trois réservations aux bornes + celles du hasard, comptées pareil.
      final courant = reservationsEnAttente(reservations, f);
      expect(courant, (serveur['courant'] as Map)['reservations_en_attente']);
      expect(f.contientComme(DateTime(2026, 10, 11)), isTrue);
      expect(f.contientComme(DateTime(2026, 9, 10, 23, 59, 59)), isFalse);
      expect(f.precedente.contientComme(DateTime(2026, 9, 11)), isTrue);
    });

    test('un séjour à cheval ne compte que ses nuits intérieures', () {
      final cheval = reservations.firstWhere((r) => r.id == 'cheval');
      final f = FenetreTableauDeBord.depuis(
        PeriodeADate.septJours,
        DateTime(2026, 10, 10),
      );
      // Fenêtre 04/10 -> 11/10 (7 jours) : tout le séjour (08/09 -> 18/10) la
      // couvre, donc 7 nuits et pas 40.
      expect(nuitsDansLaFenetre(cheval, f), 7);
    });

    test('la ventilation par activité = ventilationParActivite() du serveur, '
        'avoirs en diminution', () {
      final resultats = (reponse['resultats'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      var modulesComparees = 0;
      for (var i = 0; i < demandes.length; i++) {
        final d = demandes[i];
        final attendu = {
          for (final l
              in ((resultats[i]['courant'] as Map)['ventilation'] as List)
                  .cast<Map<String, dynamic>>())
            l['module'] as String: l['montant'] as String,
        };
        final obtenu = {
          for (final p in ventilationParActivite(pieces, d.fenetre))
            p.module: p.montant,
        };
        expect(obtenu, attendu, reason: d.etiquette);
        modulesComparees += attendu.length;
      }
      expect(modulesComparees, greaterThan(10), reason: 'balayage non vide');
    });

    test('employés actifs et effectif total : « actif » seul, « parti » '
        'exclu du total', () {
      final employes = reponse['employes'] as Map<String, dynamic>;
      expect(employesActifs(salaries), employes['actifs']);
      expect(effectifTotal(salaries), employes['total']);
      // Un salarié en congé n'est PAS « actif » pour le serveur.
      expect(employesActifs([_employe(StatutEmploye.conge)]), 0);
    });
  });

  group('« À traiter » : le compte des articles critiques est celui de '
      'Accueil::articlesCritiques()', () {
    // Trois jeux : un registre ordinaire, un registre où les JOURNALIERS font
    // la différence avec le « sous seuil » de l'écran Stocks, et un registre
    // de plus de 50 articles critiques (le plafond de la liste du serveur).
    final alea = Random(20261012);

    ({List<ArticleCalcul> articles, List<MouvementCalcul> mouvements}) jeu(
      String prefixe,
      int nombre, {
      required double partJournaliers,
      required int seuilMax,
    }) {
      final articles = <ArticleCalcul>[];
      final mouvements = <MouvementCalcul>[];
      for (var i = 0; i < nombre; i++) {
        final journalier = alea.nextDouble() < partJournaliers;
        final id = '$prefixe-$i';
        articles.add(
          ArticleCalcul(
            id: id,
            libelle: 'Article $prefixe ${i.toString().padLeft(3, '0')}',
            categorie: null,
            uniteMesure: 'u',
            // Le seuil d'un journalier retombe à zéro (`StocksDao`).
            seuilCentiemes: journalier ? 0 : 100 * alea.nextInt(seuilMax + 1),
            suivi: journalier
                ? SuiviArticle.journalier
                : SuiviArticle.permanent,
          ),
        );
        for (var m = 0; m < alea.nextInt(4); m++) {
          final type =
              TypeMouvement.values[alea.nextInt(TypeMouvement.values.length)];
          // Inventaire SIGNÉ (une régularisation peut retirer), les autres
          // positifs ; des quantités au centième près, et des soldes pile AU
          // seuil (multiples de 100).
          final quantite = alea.nextBool()
              ? 100 * (1 + alea.nextInt(8))
              : 1 + alea.nextInt(900);
          mouvements.add(
            MouvementCalcul(
              id: '$id-$m',
              articleId: id,
              pointId: 'p${alea.nextInt(2)}',
              type: type,
              centiemes: type == TypeMouvement.inventaire && alea.nextBool()
                  ? -quantite
                  : quantite,
              ordre: m,
              date: DateTime(2026, 10, 1),
            ),
          );
        }
      }
      return (articles: articles, mouvements: mouvements);
    }

    final jeux = [
      jeu('ord', 40, partJournaliers: 0.1, seuilMax: 5),
      jeu('jour', 30, partJournaliers: 0.6, seuilMax: 2),
      jeu('plaf', 90, partJournaliers: 0.3, seuilMax: 9),
    ];

    String centiemes(int c) => ecrireCentiemes(c);

    test('trois registres : même nombre que le serveur, journaliers compris, '
        'plafonné à 50', () async {
      final reponse = await _executer({
        'requetes': <dynamic>[],
        'stocks': [
          for (final j in jeux)
            {
              'articles': [
                for (final a in j.articles)
                  {
                    'id': a.id,
                    'libelle': a.libelle,
                    'unite_mesure': a.uniteMesure,
                    'seuil_alerte': centiemes(a.seuilCentiemes),
                  },
              ],
              'mouvements': [
                for (final m in j.mouvements)
                  {
                    'article_id': m.articleId,
                    'type_mouvement': m.type.code,
                    'quantite': centiemes(m.centiemes),
                  },
              ],
            },
        ],
      });

      final serveur = (reponse['stocks'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(serveur, hasLength(jeux.length), reason: 'balayage non vide');
      expect(
        (reponse['selecteur'] as Map<String, dynamic>)['plafond_critiques'],
        plafondArticlesCritiques,
      );

      var differeDuSousSeuil = 0;
      var plafonne = 0;
      for (var i = 0; i < jeux.length; i++) {
        final etat = calculerEtat(
          articles: jeux[i].articles,
          mouvements: jeux[i].mouvements,
          maintenant: DateTime(2026, 10, 12),
          libellesPoints: const {},
        );
        final nombre = nombreArticlesCritiques(etat.lignes);
        expect(nombre, serveur[i]['nombre'], reason: 'jeu $i');
        // La LISTE elle-même (bandeau rouge et modale de l'accueil, lot 2) :
        // mêmes articles, dans l'ordre du serveur (`orderBy('libelle')`, puis
        // `limit(50)` — ce sont les cinquante PREMIERS libellés qui restent),
        // et le stock et le seuil que la modale écrit, au centième.
        final liste = articlesCritiques(etat.lignes);
        expect(
          [for (final l in liste) l.id],
          serveur[i]['ids'],
          reason: 'jeu $i (ordre et plafond)',
        );
        expect(
          [for (final l in liste) l.stock],
          serveur[i]['stocks'],
          reason: 'jeu $i (stock)',
        );
        expect(
          [for (final l in liste) l.seuilAlerte],
          serveur[i]['seuils'],
          reason: 'jeu $i (seuil)',
        );
        if (nombre != etat.kpis.sousSeuil) differeDuSousSeuil++;
        if (etat.lignes.where((l) => l.auSeuilOuDessous).length >
            plafondArticlesCritiques) {
          plafonne++;
          expect(nombre, plafondArticlesCritiques);
        }
      }
      // Les jeux mordent réellement : la règle du serveur diffère du « sous
      // seuil » de M6 sur au moins un registre, et le plafond est atteint.
      expect(differeDuSousSeuil, greaterThan(0));
      expect(plafonne, greaterThan(0));
    });
  });

  test('articlesCritiques TRIE puis PLAFONNE, comme `orderBy(libelle)` puis '
      '`limit(50)` — sur une entrée NON triée', () {
    // `calculerEtat` rend déjà ses lignes triées par libellé : par cette
    // chaîne, plafonner avant de trier donnerait le même résultat, et la
    // mutation ne mordrait pas (constaté le 12/10/2026, piège 7). La fonction
    // est donc éprouvée ici sur une liste DÉSORDONNÉE, telle qu'un autre
    // appelant pourrait la lui donner.
    LigneStock ligne(int n) => LigneStock(
      id: 'a$n',
      libelle: 'Article ${n.toString().padLeft(3, '0')}',
      categorie: null,
      uniteMesure: 'u',
      seuilAlerte: '5.00',
      coutMoyenPondere: '0',
      stock: '1.00',
      valeurStock: '0',
      portee: 'tous',
      suivi: SuiviArticle.permanent,
      pointStockageId: null,
      pointLibelle: null,
      prixAchat: null,
      deriveCmp: null,
    );
    // 90 articles critiques, numérotés dans le désordre (×37 mod 90).
    final desordre = [for (var i = 0; i < 90; i++) ligne((i * 37) % 90)];
    final liste = articlesCritiques(desordre);
    expect(liste, hasLength(plafondArticlesCritiques));
    expect(
      [for (final l in liste) l.id],
      [for (var n = 0; n < plafondArticlesCritiques; n++) 'a$n'],
    );
  });

  group('La « Vue d’exploitation » : récapitulatif de la journée et chambres '
      'disponibles = Accueil::recapDuJour et Accueil::chambresDisponibles', () {
    // Un parc de 12 unités de tous statuts, 80 réservations de tous statuts
    // autour du mois d'octobre, 60 ventes (validées ou annulées, encaissées
    // ou portées en note de chambre), et 31 journées — rejouées par le VRAI
    // composant (méthodes privées, par réflexion).
    final alea = Random(20261013);
    final statutsUnite = StatutUnite.values;
    final unites = [
      for (var i = 0; i < 12; i++)
        UniteHebergement(
          id: 'u$i',
          // Numéros dans le désordre de la création : le tri est celui de
          // `orderBy('numero')`.
          numero: 'CH-${((i * 7) % 12).toString().padLeft(2, '0')}',
          categorieId: 'k1',
          categorieLibelle: 'Chambre',
          statut: statutsUnite[alea.nextInt(statutsUnite.length)],
          tarifBase: 20000,
          capaciteMax: 2,
        ),
    ];
    DateTime jourAlea() => DateTime(2026, 9, 25 + alea.nextInt(40));
    final reservations = [
      for (var i = 0; i < 80; i++)
        () {
          final arrivee = jourAlea();
          return Reservation(
            id: 'r$i',
            reference: 'r$i',
            clientId: 'c',
            clientNom: 'C',
            uniteId: 'u${alea.nextInt(12)}',
            periode: PeriodeSejour(
              arrivee: arrivee,
              depart: DateTime(
                arrivee.year,
                arrivee.month,
                arrivee.day + 1 + alea.nextInt(5),
              ),
            ),
            tarifNuit: 20000,
            statut: StatutReservation
                .values[alea.nextInt(StatutReservation.values.length)],
            statutSynchronisation: StatutSynchronisation.local,
            creeeLe: jourAlea().add(
              Duration(hours: alea.nextInt(24), minutes: alea.nextInt(60)),
            ),
          );
        }(),
    ];
    final modes = [
      ModeReglement.especes,
      ModeReglement.mobileMoney,
      ModeReglement.noteChambre,
    ];
    final ventes = [
      for (var i = 0; i < 60; i++)
        Vente(
          id: 'v$i',
          date: jourAlea().add(
            Duration(hours: alea.nextInt(24), minutes: alea.nextInt(60)),
          ),
          statut: alea.nextInt(5) == 0
              ? StatutVente.annulee
              : StatutVente.validee,
          typeVente: TypeVente.comptant,
          lignes: const [],
          montant: 500 * (1 + alea.nextInt(20)),
          montantFige: true,
          mode: modes[alea.nextInt(modes.length)],
        ),
      // Des ventes VALIDÉES SANS MODE (`Vente.encaisse == null`), le jour
      // même, sur cinq journées d'octobre (13/10/2026, contrôle du lot 2) :
      // « Encaissé aujourd'hui » ne les compte pas — rien ne dit que l'argent
      // est entré. Le serveur n'a pas cet état ; la vente lui part en
      // `encaisse = false` (la correspondance ci-dessous), l'état le plus
      // proche qu'il connaisse. Sans ces lignes, `v.encaisse == true` et
      // `v.encaisse != false` disaient la même chose sur tout le jeu.
      for (final jour in const [3, 7, 12, 18, 25])
        Vente(
          id: 'sans-mode-$jour',
          date: DateTime(2026, 10, jour, 11, 30),
          statut: StatutVente.validee,
          typeVente: TypeVente.comptant,
          lignes: const [],
          montant: 7000,
          montantFige: true,
        ),
    ];
    final journees = [for (var j = 0; j < 31; j++) DateTime(2026, 10, 1 + j)];
    // Le titre du récapitulatif, confronté sur les DOUZE mois et les SEPT
    // jours de la semaine (le jeu d'octobre n'éprouvait qu'un seul mois) :
    // le jour (m + 1) du mois m de 2026 — 2 janvier, 3 février, …, 13
    // décembre, un quantième qui varie avec le mois et passe à deux chiffres
    // —, puis une semaine complète de février. (Ce commentaire disait « le 1er
    // de chaque mois » : faux, corrigé le 13/10/2026.)
    final joursDuTitre = [
      for (var m = 1; m <= 12; m++) DateTime(2026, m, 1 + m),
      for (var j = 0; j < 7; j++) DateTime(2026, 2, 16 + j),
    ];

    late Map<String, dynamic> reponse;
    setUpAll(() async {
      reponse = await _executer({
        'requetes': <dynamic>[],
        'categories': [
          {'id': 'k1', 'libelle': 'Chambre', 'tarif_base': '20000.00'},
        ],
        'unites': [
          for (final u in unites)
            {
              'id': u.id,
              'statut': u.statut.code,
              'numero': u.numero,
              'categorie_id': u.categorieId,
            },
        ],
        'reservations': [
          for (final r in reservations)
            {
              'id': r.id,
              'statut': r.statut.code,
              'arrivee': _jour(r.periode.arrivee),
              'depart': _jour(r.periode.depart),
              'creee_le': _horodatage(r.creeeLe),
              'unite_id': r.uniteId,
            },
        ],
        'ventes': [
          for (final v in ventes)
            {
              'statut': v.statut.code,
              'encaisse': v.encaisse ?? false,
              'created_at': _horodatage(v.date),
              'montant_total': '${v.montant}.00',
            },
        ],
        'journees': [
          for (final j in journees) _jour(j),
          for (final j in joursDuTitre) _jour(j),
        ],
      });
    });

    List<Map<String, dynamic>> serveur() =>
        (reponse['journees'] as List<dynamic>).cast<Map<String, dynamic>>();

    test('les quatre compteurs du récapitulatif, jour par jour', () {
      expect(
        serveur(),
        hasLength(journees.length + joursDuTitre.length),
        reason: 'balayage vide',
      );
      var encaisseNonNul = 0, nouvellesAvecAnnulees = 0, sansMode = 0;
      for (var i = 0; i < journees.length; i++) {
        final attendu = serveur()[i]['recap'] as Map<String, dynamic>;
        final local = recapDuJour(
          reservations: reservations,
          ventes: ventes,
          jour: journees[i].add(const Duration(hours: 15)),
        );
        final jour = _jour(journees[i]);
        expect(local.arrivees, attendu['arrivees'], reason: '$jour arrivées');
        expect(local.departs, attendu['departs'], reason: '$jour départs');
        expect(local.nouvelles, attendu['nouvelles'], reason: '$jour nouv.');
        expect(
          '${local.encaisse}.00',
          attendu['encaisse'],
          reason: '$jour encaissé',
        );
        if (local.encaisse != 0) encaisseNonNul++;
        if (ventes.any(
          (v) => v.estValidee && v.encaisse == null && _jour(v.date) == jour,
        )) {
          sansMode++;
        }
        if (reservations.any(
          (r) =>
              r.statut == StatutReservation.annulee && _jour(r.creeeLe) == jour,
        )) {
          nouvellesAvecAnnulees++;
        }
      }
      // Le jeu mord : des journées encaissent, et des annulées créées le jour
      // même comptent parmi les « nouvelles » (règle du serveur, répliquée).
      expect(encaisseNonNul, greaterThan(5));
      expect(nouvellesAvecAnnulees, greaterThan(0));
      // Cinq journées portent une vente validée SANS MODE : elles ont été
      // confrontées (et le serveur ne l'a pas comptée).
      expect(sansMode, 5);
    });

    test('les chambres disponibles cette nuit : mêmes unités, même ordre '
        '(numéro), ni hors service ni nettoyage', () {
      var vides = 0, pleines = 0;
      for (var i = 0; i < journees.length; i++) {
        final local = chambresDisponiblesCeSoir(
          unites: unites,
          reservations: reservations,
          jour: journees[i].add(const Duration(hours: 9)),
        );
        expect(
          [for (final u in local) u.id],
          serveur()[i]['chambres'],
          reason: _jour(journees[i]),
        );
        if (local.isEmpty) vides++;
        if (local.length > 1) pleines++;
      }
      expect(pleines, greaterThan(0), reason: 'le jeu doit mordre');
      expect(vides + pleines, greaterThan(0));
      // Le nettoyage est exclu (`estCommercialisable`), le jeu en contient.
      expect(
        unites.where((u) => u.statut == StatutUnite.nettoyage),
        isNotEmpty,
      );
    });

    test("le titre du récapitulatif : `translatedFormat('l j F')` de "
        'Carbon en locale fr, jour par jour — les douze mois et les sept '
        'jours de la semaine', () {
      final tous = [...journees, ...joursDuTitre];
      final mois = <int>{}, joursSemaine = <int>{};
      for (var i = 0; i < tous.length; i++) {
        expect(
          jourDuRecapitulatif(tous[i]),
          serveur()[i]['titre'],
          reason: _jour(tous[i]),
        );
        mois.add(tous[i].month);
        joursSemaine.add(tous[i].weekday);
      }
      // Le jeu couvre réellement les deux registres.
      expect(mois, hasLength(12));
      expect(joursSemaine, hasLength(7));
      expect(
        [for (final j in joursDuTitre) j.month].where((m) => m == 2),
        hasLength(8),
        reason: 'une semaine entière de février, et son 3',
      );
    });
  });

  group('La variation tronque comme bcdiv, sans jamais inventer de base', () {
    test('base nulle -> aucune variation (jamais +100 % ni +∞)', () {
      expect(variationEnPourcent('5', '0'), isNull);
      expect(variationEnPourcent('5.00', '0.00'), isNull);
      expect(variationEnPourcent('0.00', '0.00'), isNull);
    });

    test('troncature vers zéro, signe conservé', () {
      expect(variationEnPourcent('3', '2'), '50.00');
      expect(variationEnPourcent('1', '3'), '-66.66');
      expect(variationEnPourcent('2', '3'), '-33.33');
      expect(variationEnPourcent('10.00', '10.00'), '0.00');
    });
  });

  test('TableauDeBordLocal : l’écran lit la fenêtre CALENDAIRE, M14 la '
      'fenêtre « à date »', () async {
    final local = TableauDeBordLocal(
      unites: () async => const [],
      reservations: () async => const [],
      employes: () async => const [],
      stock: () async => const StockRefuse(motif: 'refus', codeHttp: 403),
      pieces: () async => const [],
      creances: () async => const [],
      paiements: () async => const [],
      sessions: () async => const [],
      peutLire: () => true,
      maintenant: () => DateTime(2026, 10, 10, 14, 30),
    );
    final ecran =
        (await local.consulter(SelectionPeriode.parDefaut))
            as TableauDeBordRecu;
    expect(ecran.tableau.libellePeriode, 'Du 01/10/2026 au 31/10/2026');
    // `EtatTableauDeBord` : `Periode::depuisCode(Periode::DEFAUT)`.
    final m14 =
        (await local.consulterADate(PeriodeADate.parDefaut))
            as TableauDeBordRecu;
    expect(m14.tableau.libellePeriode, 'Du 11/09/2026 au 10/10/2026');
  });
}
