import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/impression/texte_ticket.dart';
import 'package:tatacora_flutter/features/rh/domain/entities/bulletin_paie.dart';
import 'package:tatacora_flutter/features/rh/domain/entities/employe.dart';
import 'package:tatacora_flutter/features/rh/domain/services/bulletin_paie_service.dart';
import 'package:tatacora_flutter/features/rh/domain/services/calcul_paie_service.dart';
import 'package:tatacora_flutter/features/rh/impression/bulletin_paie_a4.dart';

import '../../support/vue_blade.dart';

/// Le bulletin de paie A4 (`pdf/paie-bulletin.blade.php`) : les mots, les
/// montants figés, la fourchette, le pied de document REMIS, et le papier
/// réellement composé.
void main() {
  Employe employe({String? cnss = 'BJ-CNSS-0088412'}) => Employe(
    id: 'e-1',
    matricule: 'EMP-0001',
    nom: 'KORA',
    prenom: 'Jean-Baptiste',
    poste: 'Réceptionniste',
    serviceId: 's-1',
    serviceLibelle: 'Hébergement',
    dateEmbauche: DateTime(2023, 3, 15),
    salaireBase: 150000,
    statut: StatutEmploye.actif,
    numeroCnss: cnss,
  );

  BulletinPaie bulletin({
    String? cnss = 'BJ-CNSS-0088412',
    int retenues = 9000 + 4000,
    StatutBulletin statut = StatutBulletin.validee,
  }) => BulletinPaie(
    id: 'b-1',
    numero: 'BUL-2026-00001',
    employe: employe(cnss: cnss),
    periode: '2026-09',
    salaireBase: 150000,
    totalPrimes: 10000,
    totalRetenues: retenues,
    cnssSalarie: 9000,
    its: 4000,
    chargesPatronalesConfirmees: 31040,
    netAPayer: 160000 - retenues,
    statut: statut,
    motifAnnulation: statut == StatutBulletin.annulee
        ? 'Erreur de saisie'
        : null,
    etabliLe: DateTime(2026, 9, 14, 10),
  );

  RecapitulatifBulletin recapitulatif(BulletinPaie b) => RecapitulatifBulletin(
    bulletin: b,
    cout: CoutEmployeur.composer(
      brut: b.brut,
      confirmees: null,
      totalConfirmees: b.chargesPatronalesConfirmees,
      fourchette: CalculPaieService.fourchetteRisquesProfessionnels(b.brut),
    ),
  );

  BulletinPaieA4 document(BulletinPaie b, {String? auteur = 'essai'}) =>
      BulletinPaieA4(
        recapitulatif: recapitulatif(b),
        periodeLongue: 'septembre 2026',
        auteur: auteur,
      );

  /// Les textes lus DANS le papier produit (non compressé : `TJ` par mot).
  Future<String> papier(BulletinPaieA4 d) async {
    final brut = latin1.decode(await d.pdf(compresse: false));
    return RegExp(
      r'\(((?:[^()\\]|\\.)*)\)\]TJ',
    ).allMatches(brut).map((m) => m[1]!).join(' ');
  }

  group('Les mots sont ceux du gabarit serveur (lang/fr/rh_pwa.php)', () {
    String l(String cle) {
      final v = VueBlade.libelle('rh_pwa.$cle');
      expect(v, isNotNull, reason: 'clé rh_pwa.$cle introuvable (vide = vert)');
      return v!;
    }

    test('chaque libellé du papier est celui du serveur', () {
      expect(BulletinPaieA4.titre, l('bulletin_entete'));
      expect(BulletinPaieA4.salarie, l('bulletin_salarie'));
      expect(BulletinPaieA4.affectation, l('bulletin_affectation'));
      expect(
        BulletinPaieA4.matricule('X'),
        l('bulletin_matricule').replaceAll(':valeur', 'X'),
      );
      expect(
        BulletinPaieA4.cnss('X'),
        l('bulletin_cnss').replaceAll(':valeur', 'X'),
      );
      expect(BulletinPaieA4.cnssAbsent, l('bulletin_cnss_absent'));
      expect(
        BulletinPaieA4.etabliLe('D'),
        l('bulletin_etabli_le').replaceAll(':date', 'D'),
      );
      expect(BulletinPaieA4.colonnes, [
        l('col_designation'),
        l('col_base'),
        l('col_taux'),
        l('col_gain'),
        l('col_retenue'),
      ]);
      expect(BulletinPaieA4.brutLibelle, l('bulletin_brut'));
      expect(BulletinPaieA4.cnssSalarialeLibelle, l('bulletin_cnss_salariale'));
      expect(BulletinPaieA4.imposableLibelle, l('bulletin_imposable'));
      expect(BulletinPaieA4.itsLibelle, l('bulletin_its'));
      expect(BulletinPaieA4.autresLibelle, l('bulletin_autres'));
      expect(BulletinPaieA4.netLibelle, l('bulletin_net'));
      expect(BulletinPaieA4.patronalesTitre, l('bulletin_patronales'));
      expect(BulletinPaieA4.confirmeesLibelle, l('livre_total_confirmees'));
      expect(BulletinPaieA4.rpLibelle, l('bulletin_rp'));
      expect(BulletinPaieA4.coutTotalLibelle, l('bulletin_cout_total'));
      expect(BulletinPaieA4.pied, l('bulletin_pied'));
      expect(
        BulletinPaieA4.annule('M'),
        l('bulletin_annule').replaceAll(':motif', 'M'),
      );
    });

    test('la note des risques professionnels est celle du serveur, sans ses '
        'balises', () {
      expect(
        BulletinPaieA4.noteRp,
        l('bulletin_note_rp').replaceAll(RegExp(r'</?strong>'), ''),
      );
    });
  });

  group('Le contenu : rien d’inventé, la fourchette reste une fourchette', () {
    test('les montants sont ceux des colonnes figées du bulletin', () {
      final textes = document(bulletin()).textes;
      for (final attendu in [
        '160 000 FCFA', // brut
        '9 000 FCFA', // CNSS salariale
        '151 000 FCFA', // revenu imposable
        '4 000 FCFA', // ITS
        '147 000 FCFA', // net
        '31 040 FCFA', // charges patronales confirmées
      ]) {
        expect(textes, contains(attendu), reason: attendu);
      }
    });

    test('le risque professionnel et le coût total sont des FOURCHETTES', () {
      final d = document(bulletin());
      final cout = recapitulatif(bulletin()).cout;
      expect(cout.rpMax, greaterThan(cout.rpMin));
      expect(
        d.textes,
        contains(BulletinPaieA4.fourchette(cout.rpMin, cout.rpMax)),
      );
      expect(
        d.textes,
        contains(BulletinPaieA4.fourchette(cout.coutMin, cout.coutMax)),
      );
      // 1 % et 4 % du brut (160 000) : bornes réglementaires.
      expect(cout.rpMin, 1600);
      expect(cout.rpMax, 6400);
      expect(cout.coutMin, 160000 + 31040 + 1600);
      expect(cout.coutMax, 160000 + 31040 + 6400);
    });

    test('« Autres retenues » n’apparaît que si elle est positive', () {
      expect(document(bulletin()).textes, isNot(contains('Autres retenues')));
      final avec = document(bulletin(retenues: 9000 + 4000 + 2500)).textes;
      expect(avec, contains('Autres retenues'));
      expect(avec, contains('2 500 FCFA'));
    });

    test('un salarié sans numéro CNSS le DIT, un bulletin annulé aussi', () {
      expect(
        document(bulletin(cnss: null)).textes,
        contains('N° CNSS non communiqué'),
      );
      final annule = document(bulletin(statut: StatutBulletin.annulee)).textes;
      expect(annule, contains('Annulé — Erreur de saisie'));
      expect(
        document(bulletin()).textes.any((t) => t.startsWith('Annulé')),
        isFalse,
      );
    });

    test(
      'le pied est la phrase du gabarit, un tiret, le login ; sans login : —',
      () {
        expect(
          document(bulletin()).textes.last,
          '${BulletinPaieA4.pied} — essai',
        );
        expect(
          document(bulletin(), auteur: null).textes.last,
          '${BulletinPaieA4.pied} — —',
        );
      },
    );

    test('le fichier se nomme bulletin_<numéro>', () {
      expect(document(bulletin()).prefixeFichier, 'bulletin_BUL-2026-00001');
    });
  });

  group('Le papier réellement composé', () {
    test('chaque texte est imprimable en Latin-1 après texteTicket', () {
      for (final b in [
        bulletin(),
        bulletin(cnss: null),
        bulletin(statut: StatutBulletin.annulee),
      ]) {
        for (final t in document(b).textes) {
          expect(caracteresNonImprimables(texteTicket(t)), isEmpty, reason: t);
        }
      }
    });

    test('le PDF porte l’identité, les montants, la fourchette et le pied — '
        'et AUCUN visa ni pied de rapport (document remis)', () async {
      final d = document(bulletin());
      final octets = await d.pdf();
      expect(latin1.decode(octets.sublist(0, 5)), '%PDF-');

      final texte = await papier(d);
      for (final attendu in [
        'BULLETIN DE PAIE',
        'septembre 2026',
        'BUL-2026-00001',
        'KORA',
        'EMP-0001',
        'Hébergement',
        '160 000 FCFA',
        '147 000 FCFA',
        'Total charges patronales confirmées',
        'risques professionnels',
        'Page 1 / 1',
        'essai',
      ]) {
        expect(texte, contains(attendu), reason: attendu);
      }
      for (final interdit in ['Visa', 'Projet PAEB', 'Signature']) {
        expect(texte, isNot(contains(interdit)), reason: interdit);
      }
    });

    test('l’en-tête de l’établissement est celui de l’appelant', () async {
      final texte = await papier(document(bulletin()));
      expect(texte, contains('TATACORA'));
    });
  });
}
