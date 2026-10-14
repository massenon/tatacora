/// Les règles de l'encaissement de facture — FONCTIONS PURES, montants en
/// centimes entiers.
///
/// Réplique de `EncaissementFactureService::encaisser` / `annuler` ET de la
/// validation du composant `ClientsCreances::enregistrerRecouvrement`, qui la
/// précède. Elles vivent ici, sans Drift ni widget, pour qu'un test les éprouve
/// seules ; puis le vrai service et le vrai composant PHP les confrontent
/// (`encaissement_contre_serveur_test.dart`).
///
/// ## Deux étages, comme au serveur
///
/// 1. le COMPOSANT (`ClientsCreances`) : droit sur M3 puis M2, puis la
///    validation Laravel de trois propriétés — la pièce (`required`, `exists`),
///    le montant (`required`, `numeric`, `gt:0`), le mode (`required`, `in`) ;
/// 2. le SERVICE (`EncaissementFactureService`) : facture figée, mode connu,
///    montant lisible et positif, montant ≤ reste dû, caisse ouverte.
///
/// @see EF-M2-03 Encaissement des factures
/// @see RG-11 La pièce comptable d'un encaissement est validée, donc immuable
library;

import '../../../core/rbac/garde_acces.dart';
import '../../caisse/domain/montant_caisse.dart';
import '../../comptabilite/domain/montant_comptable.dart';
import 'entities/paiement_facture.dart';
import 'messages_encaissement.dart';

/// Le champ d'une saisie refusée, pour que l'écran pose le message SOUS le bon
/// champ (le `@error('recouvrementMontant')` de la vue).
enum ChampEncaissement {
  piece('recouvrementFactureId', MessagesEncaissement.attributPiece),
  montant('recouvrementMontant', MessagesEncaissement.attributMontant),
  mode('recouvrementMode', MessagesEncaissement.attributMode);

  const ChampEncaissement(this.propriete, this.attribut);

  /// Le nom de la propriété Livewire du serveur.
  final String propriete;

  /// L'attribut que Laravel écrit dans le message de validation.
  final String attribut;
}

/// Un geste refusé : rien n'a été écrit.
class RefusEncaissement implements Exception {
  const RefusEncaissement(this.message, {this.champ});

  final String message;

  /// Le champ visé, ou `null` pour un refus qui ne tient pas à une saisie
  /// (droit manquant, caisse fermée).
  ///
  /// ⚠ Au serveur, TOUT refus du service s'affiche sous le champ montant
  /// (`addError('recouvrementMontant', …)`), caisse fermée comprise. Le champ est
  /// donc renseigné par l'appelant du service, pas par la règle.
  final ChampEncaissement? champ;

  @override
  String toString() => message;
}

final RegExp _videAuSensDePhp = RegExp(r'^[ \t\n\r\v\x00]*$');

/// `required` de Laravel : `trim()` de PHP (espace, \t, \n, \r, \v, NUL) — pas
/// le `trim()` de Dart, qui retire aussi l'espace insécable.
bool estVideAuSensDePhp(String? valeur) =>
    _videAuSensDePhp.hasMatch(valeur ?? '');

final RegExp _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

/// La règle `uuid` de Laravel (`Str::isUuid`) : huit-quatre-quatre-quatre-douze
/// chiffres hexadécimaux, sans regard sur la version.
bool estUnUuid(String valeur) => _uuid.hasMatch(valeur);

/// `['required', 'numeric', 'gt:0']` du montant, dans l'ordre de Laravel.
///
/// Un seul message sort. `gt:0` sur la valeur EXACTE : `0.004` passe ici (et
/// sera refusé par le service, qui tronque à deux décimales avant de comparer).
void validerMontantRecouvrement(String? brut) {
  const champ = ChampEncaissement.montant;
  if (estVideAuSensDePhp(brut)) {
    throw RefusEncaissement(
      MessagesEncaissement.obligatoire(champ.attribut),
      champ: champ,
    );
  }
  final decimal = DecimalSaisi.lire(brut!);
  if (decimal == null) {
    throw RefusEncaissement(
      MessagesEncaissement.nombre(champ.attribut),
      champ: champ,
    );
  }
  if (!decimal.estStrictementPositif) {
    // La clé de langue `validation.gt.numeric` n'existe pas : Laravel rend la
    // clé comme message (voir `MessagesEncaissement.superieurAZero`).
    throw const RefusEncaissement(
      MessagesEncaissement.superieurAZero,
      champ: ChampEncaissement.montant,
    );
  }
}

/// `['required', 'in:especes,mobile_money,carte,virement']` du mode.
ModePaiementFacture validerModeRecouvrement(String? brut) {
  const champ = ChampEncaissement.mode;
  if (estVideAuSensDePhp(brut)) {
    throw RefusEncaissement(
      MessagesEncaissement.obligatoire(champ.attribut),
      champ: champ,
    );
  }
  final mode = ModePaiementFacture.depuisCode(brut!);
  if (mode == null) {
    throw RefusEncaissement(
      MessagesEncaissement.invalide(champ.attribut),
      champ: champ,
    );
  }
  return mode;
}

/// Le montant tel que `EncaissementFactureService::encaisser` le lit :
/// `is_numeric`, puis `bccomp($montant, '0', 2)` — qui TRONQUE à la deuxième
/// décimale et lève une `ValueError` sur un texte mal formé.
///
/// Rend les centimes TRONQUÉS (jamais arrondis : `100.999` vaut `100.99`, comme
/// `bcadd($montant, '0', 2)` qui l'écrit). Lève [RefusEncaissement] sur un
/// montant illisible ou ≤ 0 ; le contrôle contre le reste dû est un autre geste.
BigInt montantDuServiceCentimes(String montant) {
  final decimal = DecimalSaisi.lire(montant);
  if (decimal == null) {
    throw const RefusEncaissement(MessagesEncaissement.montantInvalide);
  }
  if (!decimal.estBienFormePourBc) {
    // Le serveur plante ici (HTTP 500) AVANT d'écrire ; le poste refuse, avec sa
    // propre phrase (écart nommé).
    throw const RefusEncaissement(MessagesEncaissement.malForme);
  }
  final centimes = _centimesTronques(montant);
  if (centimes <= BigInt.zero) {
    throw const RefusEncaissement(MessagesEncaissement.montantInvalide);
  }
  return centimes;
}

/// `bcadd($v, '0', 2)` en centimes, pour un montant DÉJÀ reconnu bien formé
/// (`DecimalSaisi.estBienFormePourBc`). Exposée pour que le règlement
/// fournisseur (M7) tronque comme l'encaissement : UN auteur de la troncature
/// de `bcmath`, pas deux.
BigInt centimesTronquesDuServeur(String texte) => _centimesTronques(texte);

final RegExp _bcNombre = RegExp(r'^([+-]?)(\d*)(?:\.(\d*))?$');

/// `bcadd($v, '0', 2)` en centimes, sur un texte déjà reconnu bien formé.
BigInt _centimesTronques(String texte) {
  final m = _bcNombre.firstMatch(texte)!;
  final signe = m.group(1) == '-' ? BigInt.from(-1) : BigInt.one;
  final entiers = (m.group(2) ?? '').isEmpty ? '0' : m.group(2)!;
  final decimales = (m.group(3) ?? '').padRight(2, '0').substring(0, 2);
  return signe *
      (BigInt.parse(entiers) * BigInt.from(100) + BigInt.parse(decimales));
}

/// Le libellé de la pièce d'un encaissement — `sprintf('Encaissement %s — %s',
/// numero_mecef, paiement->id)` du serveur. C'est LE lien entre un paiement et
/// sa pièce (PA-52 : aucune colonne `ecriture_id`), unique par l'identifiant.
///
/// Le serveur écrit `numero_mecef` ; le poste n'en a pas (aucune facture n'y est
/// certifiée) et écrit le numéro de pièce `F-AAAA-NNNNN`, qui tient le même rôle
/// d'identité de la facture. Écart nommé (D229).
String libellePieceEncaissement(String numeroPiece, String paiementId) =>
    'Encaissement $numeroPiece — $paiementId';

/// La chaîne à deux décimales du serveur, pour les messages (« 6000.00 »).
String chaineDuServeur(int centimes) => chaineDepuisCentimes(centimes);

/// Le droit d'un recouvrement : écrire sur M3 (l'écran Clients & Créances) ET sur
/// M2 (l'écriture d'un encaissement de facture).
///
/// Le serveur les exige tous deux — `ouvrirRecouvrement` et
/// `enregistrerRecouvrement` appellent `exigerEcriture(M3)` puis
/// `exigerEcriture(M2)` — et répond 403 au premier qui manque, AVANT toute
/// validation (PA-65 : un module écrit DEPUIS un écran exige les deux droits,
/// jamais l'un pour l'autre). Le bouton « Recouvrement » de la vue porte la même
/// condition (`$peutEncaisser`).
bool peutEncaisserUneFacture(GardeAcces droits) =>
    droits.peutEcrire(ModuleTatacora.m3Crm) &&
    droits.peutEcrire(ModuleTatacora.m2Facturation);

/// Le message de succès d'un recouvrement — `pwa.clients.recouvrement_succes` :
/// « Recouvrement de 5 000 FCFA enregistré pour Jean KORA. ». Le montant est mis
/// en forme par l'auteur unique des montants (`MontantFcfa::format`, PA-186), le
/// décimal brut (« 5000.00 F ») n'apparaît jamais.
String messageDeRecouvrement(PaiementFacture paiement, String clientNom) =>
    MessagesEncaissement.succes(
      formaterCentimesEnFcfa(paiement.montantCentimes),
      clientNom,
    );
