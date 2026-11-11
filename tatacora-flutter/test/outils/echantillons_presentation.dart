/// **Les échantillons du POSTE — dossier `presentation/` du dépôt.**
///
/// Ticket thermique 80 mm et facture A4, simple et normalisée, rendus par le VRAI code
/// d'impression du poste (`TicketFacture.composer`, `FactureA4.composer`) avec des données
/// FICTIVES. Aucune base, aucun réseau, aucune valeur réelle du Gîte.
///
/// ## Ce qui garantit qu'un échantillon ne passe jamais pour un vrai document
///
///  - la mention « ÉCHANTILLON — SANS VALEUR FISCALE » est posée par CE générateur seul, sur le
///    document composé (cadre en tête et en pied du ticket, filigrane et cadre de l'A4 par le champ
///    `filigrane` de [FactureA4Composee]) : le code de production ne la produit jamais ;
///  - le contenu du QR est manifestement factice (`F;ECHANTILLON;…`), le NIM-TC aussi ;
///  - l'IFU de l'entreprise est `0000000000000`, celui du client `1234567890123`.
///
/// Régénération : `flutter test tool/generer_echantillons_poste_test.dart`.
library;

import 'dart:typed_data';

import 'package:tatacora_flutter/core/impression/entete_etablissement.dart';
import 'package:tatacora_flutter/core/impression/texte_ticket.dart';
import 'package:tatacora_flutter/features/facturation/domain/entities/piece_facturation.dart';
import 'package:tatacora_flutter/features/facturation/domain/statut_normalisation.dart';
import 'package:tatacora_flutter/features/facturation/impression/facture_a4.dart';
import 'package:tatacora_flutter/features/facturation/impression/ticket_facture.dart';

/// La mention posée sur tous les échantillons.
const String mentionEchantillon = 'ÉCHANTILLON — SANS VALEUR FISCALE';

/// Le QR de l'échantillon : cinq champs comme le vrai, sans aucun sens fiscal.
const String qrFactice =
    'F;ECHANTILLON;ECHA-NTIL-LON0-FAUX-0000-0000;0000000000000;20261107120000';

const String nimTcFactice = 'ECHANTILLON-1';
const String codeMecefFactice = 'ECHA-NTIL-LON0-FAUX-0000-0000';
const String ifuEntrepriseFictif = '0000000000000';
const String ifuClientFictif = '1234567890123';

/// Un échantillon rendu : son nom de fichier, ses octets PDF et ce qui le compose.
final class EchantillonPoste {
  const EchantillonPoste({
    required this.nom,
    required this.pdf,
    required this.textes,
    required this.qrCode,
  });

  final String nom;
  final Uint8List pdf;

  /// Les textes composés (ce que le papier reçoit).
  final List<String> textes;

  /// Le QR composé, `null` quand le document n'en porte pas.
  final String? qrCode;
}

/// La même facture que le serveur (`GenerateurEchantillons.php`) : 2 nuitées, repas, jus et
/// taxe de séjour ; 33 500 FCFA TTC, réglés en espèces et mobile money.
PieceFacturation pieceEchantillon({required bool normalisee}) {
  return PieceFacturation(
    id: 'echantillon-1',
    numero: 'F-2026-00001',
    origine: OrigineFacture.posSejour,
    dateEmission: DateTime(2026, 11, 7, 12),
    clientNom: 'Client Exemple',
    statut: StatutPiece.emise,
    modePaiement: 'Espèces et Mobile Money',
    pointVente: 'Réception',
    acheteurIfu: ifuClientFictif,
    acheteurNom: 'Client Exemple',
    numeroMecef: normalisee ? nimTcFactice : null,
    normalisationStatut: normalisee ? StatutNormalisation.normalisee : null,
    codeMecef: normalisee ? codeMecefFactice : null,
    qrCodeFiscal: normalisee ? qrFactice : null,
    normaliseeLe: normalisee ? DateTime(2026, 11, 7, 12) : null,
    lignes: const [
      LigneFacture(
        id: 'l1',
        module: ModuleFacturable.m1Hebergement,
        libelle: 'Chambre ventilée, nuitée',
        prixUnitaire: 12000,
        quantite: 2,
        ordre: 0,
      ),
      LigneFacture(
        id: 'l2',
        module: ModuleFacturable.m4Restaurant,
        libelle: 'Repas du soir : poulet braisé, igname',
        prixUnitaire: 3500,
        quantite: 2,
        ordre: 1,
      ),
      LigneFacture(
        id: 'l3',
        module: ModuleFacturable.m5Bar,
        libelle: 'Jus de bissap',
        prixUnitaire: 500,
        quantite: 3,
        ordre: 2,
      ),
      LigneFacture(
        id: 'l4',
        module: ModuleFacturable.m1Hebergement,
        libelle: 'Taxe de séjour',
        prixUnitaire: 500,
        quantite: 2,
        ordre: 3,
      ),
    ],
  );
}

/// L'en-tête : l'identité par DÉFAUT du dépôt (Gîte Chez Noël) + l'IFU fictif ; le logo est
/// celui embarqué (`assets/img/logo.png`), jamais un logo téléversé.
EnteteEtablissement enteteEchantillon({
  Uint8List? logo,
}) => const EnteteEtablissement(
  ifu: ifuEntrepriseFictif,
  // Jamais le courriel réel du repli par défaut : une adresse réservée (RFC 2606).
  email: 'contact@exemple.invalid',
).avecLogo(logo);

/// Ajoute au ticket composé la mention d'échantillon, en cadre, en tête ET en pied.
TicketCompose _marquerTicket(TicketCompose t) {
  final cadre = LigneTicket(
    mentionEchantillon,
    style: StyleLigneTicket.filigrane,
  );
  return TicketCompose(
    List.unmodifiable([
      cadre,
      ...t.lignes,
      const LigneTicket.separateur(),
      cadre,
    ]),
    piece: t.piece,
    qrCode: t.qrCode,
  );
}

/// La facture A4 composée, avec le filigrane et le cadre d'échantillon.
FactureA4Composee _marquerA4(FactureA4Composee f) => FactureA4Composee(
  piece: f.piece,
  entete: f.entete,
  auteur: f.auteur,
  dateEdition: f.dateEdition,
  lignesEntete: f.lignesEntete,
  titre: f.titre,
  identification: f.identification,
  colonnes: f.colonnes,
  lignesTableau: f.lignesTableau,
  recapitulatif: f.recapitulatif,
  libelleTotal: f.libelleTotal,
  montantTotal: f.montantTotal,
  cachetFiscal: f.cachetFiscal,
  mentions: f.mentions,
  piedDePage: f.piedDePage,
  gabaritPagination: f.gabaritPagination,
  // Normalisée comme tout texte du papier : les polices intégrées n'ont pas le tiret cadratin.
  filigrane: texteTicket(mentionEchantillon),
  qrCode: f.qrCode,
);

/// Rend les quatre échantillons du poste (ticket et A4, simple et normalisée).
Future<List<EchantillonPoste>> genererEchantillonsPoste({
  Uint8List? logo,
}) async {
  final entete = enteteEchantillon(logo: logo);
  final auteur = const AuteurEdition(
    nom: 'Réception (exemple)',
    role: 'Exemple',
  );
  final dateEdition = DateTime(2026, 11, 7, 12);
  final sortie = <EchantillonPoste>[];

  for (final (suffixe, normalisee) in [
    ('simple', false),
    ('normalisee', true),
  ]) {
    final piece = pieceEchantillon(normalisee: normalisee);

    final ticket = _marquerTicket(
      TicketFacture.composer(piece, entete: entete),
    );
    sortie.add(
      EchantillonPoste(
        nom: '03_ticket_thermique_poste_$suffixe.pdf',
        pdf: await ticket.pdf(),
        textes: ticket.textes,
        qrCode: ticket.qrCode,
      ),
    );

    final a4 = _marquerA4(
      FactureA4.composer(
        piece,
        auteur: auteur,
        dateEdition: dateEdition,
        entete: entete,
      ),
    );
    sortie.add(
      EchantillonPoste(
        nom: '04_facture_A4_poste_$suffixe.pdf',
        pdf: await a4.pdf(),
        textes: a4.textes,
        qrCode: a4.qrCode,
      ),
    );
  }
  return sortie;
}
