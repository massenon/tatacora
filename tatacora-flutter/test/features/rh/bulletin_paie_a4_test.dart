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

  /// Le papier, normalisé comme `texteTicket` le compose : les parenthèses
  /// échappées du flux PDF rendues, les mots recollés par une espace.
  Future<String> lu(BulletinPaieA4 d) async =>
      (await papier(d)).replaceAll(r'\(', '(').replaceAll(r'\)', ')');

  group('Le contenu : rien d’inventé, la fourchette reste une fourchette', () {
    test('les montants sont ceux des colonnes figées, À LEUR PLACE', () async {
      final texte = await lu(document(bulletin()));
      // Chaque ligne du tableau : libellé puis ses cellules, dans l'ordre.
      expect(
        texte,
        contains('Salaire brut soumis à cotisations 160 000 FCFA CNSS'),
      );
      expect(
        texte,
        contains(
          'CNSS - cotisation salariale 160 000 FCFA 9 000 FCFA '
          'Revenu imposable (brut - CNSS) 151 000 FCFA '
          'ITS - Impôt sur les Traitements et Salaires 4 000 FCFA '
          'NET À PAYER 147 000 FCFA',
        ),
      );
      expect(
        texte,
        contains('Total charges patronales confirmées 31 040 FCFA'),
      );
    });

    test(
      'le risque professionnel et le coût total sont des FOURCHETTES',
      () async {
        final cout = recapitulatif(bulletin()).cout;
        // 1 % et 4 % du brut (160 000) : bornes réglementaires.
        expect(cout.rpMin, 1600);
        expect(cout.rpMax, 6400);
        expect(cout.coutMin, 160000 + 31040 + 1600);
        expect(cout.coutMax, 160000 + 31040 + 6400);
        final texte = await lu(document(bulletin()));
        expect(
          texte,
          contains(
            'CNSS - risques professionnels 1 600 FCFA - 6 400 FCFA '
            'Coût total employeur 192 640 FCFA - 197 440 FCFA',
          ),
        );
      },
    );

    test('« Autres retenues » n’apparaît que si elle est positive', () async {
      expect(
        await lu(document(bulletin())),
        isNot(contains('Autres retenues')),
      );
      final avec = await lu(document(bulletin(retenues: 9000 + 4000 + 2500)));
      expect(
        avec,
        contains('4 000 FCFA Autres retenues 2 500 FCFA NET À PAYER'),
      );
    });

    test(
      'un salarié sans numéro CNSS le DIT, un bulletin annulé aussi',
      () async {
        expect(
          await lu(document(bulletin(cnss: null))),
          contains('N° CNSS non communiqué'),
        );
        expect(
          await lu(document(bulletin(statut: StatutBulletin.annulee))),
          contains('Annulé - Erreur de saisie'),
        );
        expect(await lu(document(bulletin())), isNot(contains('Annulé')));
      },
    );

    test('la note des risques professionnels est imprimée en Latin-1 (les '
        'apostrophes typographiques ne disparaissent pas)', () async {
      final texte = await lu(document(bulletin()));
      expect(texte, contains(texteTicket(BulletinPaieA4.noteRp)));
      expect(
        caracteresNonImprimables(texteTicket(BulletinPaieA4.noteRp)),
        isEmpty,
      );
      expect(
        BulletinPaieA4.noteRp,
        contains('’'),
        reason: 'la source a bien des ’',
      );
    });

    test(
      'le pied est la phrase du gabarit, un tiret, le login ; sans login : —',
      () async {
        expect(
          await lu(document(bulletin())),
          contains(texteTicket('${BulletinPaieA4.pied} — essai')),
        );
        expect(
          await lu(document(bulletin(), auteur: null)),
          contains(texteTicket('${BulletinPaieA4.pied} — —')),
        );
      },
    );

    test('le fichier se nomme bulletin_<numéro>', () {
      expect(document(bulletin()).prefixeFichier, 'bulletin_BUL-2026-00001');
    });
  });

  group('Le papier réellement composé', () {
    test('le PDF porte l’identité, le salarié et la pagination — et AUCUN visa '
        'ni pied de rapport (document remis)', () async {
      final d = document(bulletin());
      final octets = await d.pdf();
      expect(latin1.decode(octets.sublist(0, 5)), '%PDF-');

      final texte = await lu(d);
      for (final attendu in [
        'BULLETIN DE PAIE',
        'septembre 2026 · BUL-2026-00001',
        'SALARIÉ KORA Jean-Baptiste Réceptionniste Matricule EMP-0001 '
            'N° CNSS BJ-CNSS-0088412',
        'AFFECTATION Hébergement Établi le 14/09/2026',
        'Désignation Base Taux Gain Retenue',
        'Page 1 / 1',
      ]) {
        expect(texte, contains(attendu), reason: attendu);
      }
      for (final interdit in ['Visa', 'Projet PAEB', 'Signature']) {
        expect(texte, isNot(contains(interdit)), reason: interdit);
      }
    });

    test('l’en-tête de l’établissement est celui de l’appelant', () async {
      expect(await lu(document(bulletin())), contains('TATACORA'));
    });
  });
}
