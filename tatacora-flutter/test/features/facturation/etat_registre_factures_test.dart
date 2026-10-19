import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/impression/texte_ticket.dart';
import 'package:tatacora_flutter/features/facturation/domain/certification_mecef.dart';
import 'package:tatacora_flutter/features/facturation/domain/entities/piece_facturation.dart';
import 'package:tatacora_flutter/features/facturation/impression/etat_registre_factures.dart';

/// L'état « Registre des factures » — `m2-facturation.html`.
///
/// ## Ce que ces cas protègent avant tout
///
/// **Que le document n'affirme jamais une certification qui n'a pas eu lieu.**
/// Le maître écrit sa mention en dur, avec un commentaire qui dit pourquoi ; le
/// portage la DÉRIVE des pièces. Une constante resterait vraie aujourd'hui et
/// deviendrait fausse le jour de l'inscription DGI — c'est-à-dire le jour où
/// elle compterait vraiment.
void main() {
  PieceFacturation piece({
    String id = 'p-1',
    String numero = 'FAC-2026-0001',
    OrigineFacture origine = OrigineFacture.posComptant,
    String client = 'KORA Jean',
    int montant = 12000,
    StatutPiece statut = StatutPiece.emise,
    String? avoirDe,
    String? numeroMecef,
  }) => PieceFacturation(
    id: id,
    numero: numero,
    origine: origine,
    dateEmission: DateTime(2026, 9, 20),
    clientNom: client,
    statut: statut,
    avoirDe: avoirDe,
    numeroMecef: numeroMecef,
    lignes: [
      LigneFacture(
        id: 'l-$id',
        module: ModuleFacturable.m5Bar,
        libelle: 'Bière Béninoise',
        prixUnitaire: montant,
        quantite: 1,
        ordre: 0,
      ),
    ],
  );

  EtatRegistreFactures etat(
    List<PieceFacturation> pieces, {
    String filtre = 'Toutes origines',
  }) => EtatRegistreFactures(pieces: pieces, filtre: filtre);

  /* ================================================================== */
  group('La ligne de certification ne ment pas', () {
    test('aucune pièce certifiée : la phrase du maître, mot pour mot', () {
      final e = etat([piece(numeroMecef: 'MECEF-DEMO-AB12CD34')]);
      expect(e.mentionCertification, CertificationMecef.libelleDemonstration);
      expect(e.mentionCertification.toLowerCase(), contains('démonstration'));
      // Jamais « certifiées : 1 » sur un numéro de démonstration.
      expect(e.nombreCertifiees, 0);
    });

    test('une pièce sans numéro MECeF n’est pas certifiée non plus', () {
      expect(etat([piece()]).nombreCertifiees, 0);
    });

    test('le jour où une certification RÉELLE arrivera, le compte suivra', () {
      // C'est tout l'intérêt de dériver plutôt que de figer : une constante
      // « non certifiées » deviendrait fausse le jour de l'inscription DGI,
      // et personne ne penserait à rouvrir ce fichier.
      final e = etat([
        piece(numeroMecef: 'ABC123XYZ'),
        piece(id: 'p-2', numero: 'FAC-2026-0002'),
      ]);
      expect(e.nombreCertifiees, 1);
      expect(e.mentionCertification, '1 certifiée(s) sur 2');
    });
  });

  /* ================================================================== */
  group('Le contenu est celui du maître', () {
    test('les six colonnes, dans son ordre', () {
      expect(EtatRegistreFactures.entetes, [
        'N°',
        'Date',
        'Client',
        'Origine',
        'Montant',
        'Statut',
      ]);
    });

    test('un AVOIR s’affiche « avoir », à la place du statut', () {
      // C'est ce qu'on cherche en lisant la colonne : un avoir reste « émis »
      // au cycle de vie, et l'écrire ainsi le rendrait indiscernable d'une
      // facture.
      final cellules = etat([
        piece(avoirDe: 'FAC-2026-0001'),
      ]).cellules(piece(avoirDe: 'FAC-2026-0001'));
      expect(cellules.last, 'avoir');
    });

    test('le montant part en nombre BRUT', () {
      // Un tableur ne sait pas additionner « 12 000 FCFA ».
      final e = etat([piece(montant: 12000)]);
      expect(e.cellules(e.pieces.single)[4], '12000');
      expect(e.csv(), contains('"12000"'));
    });

    test('les trois indicateurs du maître', () {
      final e = etat([piece(montant: 12000), piece(id: 'p-2', montant: 8000)]);
      expect(e.indicateurs['Pièces'], '2');
      expect(e.indicateurs['Montant'], contains('20 000'));
      expect(e.indicateurs.containsKey('Certification MECeF'), isTrue);
    });

    test('le filtre appliqué est DIT sur le document', () {
      // Sans cette mention, un extrait se lirait comme un registre complet —
      // et c'est sur un registre qu'on rapproche une caisse.
      final e = etat([piece()], filtre: 'Origine : POS au comptant');
      expect(e.csv(), contains('Origine : POS au comptant'));
    });
  });

  /* ================================================================== */
  group('Le CSV et le PDF sortent réellement', () {
    test('le CSV commence par le BOM et sépare au point-virgule', () {
      final csv = etat([piece()]).csv();
      expect(csv.codeUnitAt(0), 0xFEFF);
      expect(csv, contains('"N°";"Date";"Client"'));
    });

    test('le PDF se sérialise', () async {
      final octets = await etat([piece()]).pdf();
      expect(octets.length, greaterThan(1000));
      expect(String.fromCharCodes(octets.take(4)), '%PDF');
    });

    test('un registre vide produit un document qui le DIT', () async {
      // L'écran refuse d'exporter une liste vide ; cette garde est le second
      // rideau, et elle dit plutôt que de rendre une page blanche.
      final e = etat(const []);
      expect(e.estVide, isTrue);
      final octets = await e.pdf();
      expect(String.fromCharCodes(octets.take(4)), '%PDF');
    });

    test('aucun caractère ne peut être PERDU sur le papier', () {
      final e = etat([piece(client: 'Auberge « L’Étoile »')]);
      final textes = <String>[
        EtatRegistreFactures.titre,
        e.filtre,
        ...EtatRegistreFactures.entetes,
        ...e.indicateurs.keys,
        ...e.indicateurs.values,
        ...e.pieces.expand(e.cellules),
      ].map(texteTicket);

      for (final texte in textes) {
        expect(
          caracteresNonImprimables(texte),
          isEmpty,
          reason: '« $texte » perdrait des caractères à l’impression.',
        );
      }
    });
  });
}
