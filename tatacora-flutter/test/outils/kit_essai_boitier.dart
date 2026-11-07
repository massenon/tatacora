/// **Le kit d'essai du boîtier CC300** (`presentation/05_essai_boitier/`).
///
/// Les trois JSON sont produits par le VRAI code de conversion du poste
/// (`construireJsonPilote`, celui de `ClientMecefBoitier`) : montants entiers, libellés ASCII
/// ≤ 60, `seller_name` ≤ 30, jamais `specific_tax` ni `original_price`, sommes lignes = paiements.
/// Ils ne peuvent donc pas diverger des règles du client.
///
/// ⚠ Sur un boîtier RÉEL, un `POST /bill` crée un vrai document fiscal : les montants sont
/// volontairement minuscules. Régénération : `flutter test tool/generer_echantillons_poste_test.dart`.
library;

import 'dart:convert';

import 'package:tatacora_flutter/features/facturation/domain/conversion_boitier.dart';

/// Marque à remplacer dans le JSON de l'avoir par le NIM-TC relevé à l'essai 1.
const String rnARemplacer = 'NIM_A_REMPLACER-TC_A_REMPLACER';

const _operateurId = 'ESSAI01';
const _operateurNom = 'RECEPTION ESSAI';

const _chambre = LigneDemande(
  libelle: 'Essai chambre ventilée, nuitée',
  prixUnitaire: 500,
  quantite: 2,
  groupe: GroupeTaxe.b,
);

/// Les trois demandes de l'essai, par nom de fichier.
Map<String, DemandeNormalisation> demandesEssai() => {
  'bill_essai_1_simple.json': const DemandeNormalisation(
    pieceId: 'essai-1',
    numero: 'ESSAI-1',
    lignes: [
      LigneDemande(
        libelle: 'Essai article taxable',
        prixUnitaire: 100,
        quantite: 1,
        groupe: GroupeTaxe.b,
      ),
    ],
    paiements: [
      PaiementDemande(mode: ModePaiementPilote.especes, montant: 100),
    ],
    clientNom: 'Client Exemple',
    operateurId: _operateurId,
    operateurNom: _operateurNom,
  ),
  'bill_essai_2_multi.json': const DemandeNormalisation(
    pieceId: 'essai-2',
    numero: 'ESSAI-2',
    lignes: [
      _chambre,
      LigneDemande(
        libelle: 'Essai repas du soir : poulet braisé',
        prixUnitaire: 300,
        quantite: 1,
        groupe: GroupeTaxe.b,
      ),
      LigneDemande(
        libelle: 'Essai jus de bissap',
        prixUnitaire: 100,
        quantite: 3,
        groupe: GroupeTaxe.b,
      ),
      LigneDemande(
        libelle: 'Taxe de séjour',
        prixUnitaire: 50,
        quantite: 2,
        groupe: GroupeTaxe.f,
      ),
    ],
    paiements: [
      PaiementDemande(mode: ModePaiementPilote.especes, montant: 1000),
      PaiementDemande(mode: ModePaiementPilote.mobileMoney, montant: 700),
    ],
    clientNom: 'Client Exemple',
    clientIfu: '1234567890123',
    operateurId: _operateurId,
    operateurNom: _operateurNom,
  ),
  'bill_essai_3_avoir.json': const DemandeNormalisation(
    pieceId: 'essai-3',
    numero: 'ESSAI-3',
    lignes: [
      LigneDemande(
        libelle: 'Essai article taxable',
        prixUnitaire: 100,
        quantite: 1,
        groupe: GroupeTaxe.b,
      ),
    ],
    paiements: [
      PaiementDemande(mode: ModePaiementPilote.especes, montant: 100),
    ],
    clientNom: 'Client Exemple',
    operateurId: _operateurId,
    operateurNom: _operateurNom,
    referenceAvoir: rnARemplacer,
  ),
};

/// Les JSON du kit, lisibles (indentés) et terminés par un saut de ligne.
Map<String, String> jsonDuKit() => {
  for (final e in demandesEssai().entries)
    e.key:
        '${const JsonEncoder.withIndent('  ').convert(jsonDecode(construireJsonPilote(e.value)))}\n',
};
