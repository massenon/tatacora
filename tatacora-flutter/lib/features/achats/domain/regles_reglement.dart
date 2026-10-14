/// Les règles du règlement fournisseur — FONCTIONS PURES, montants en centimes
/// entiers.
///
/// Réplique de `ReglementFournisseurService::regler` / `annuler` ET de la
/// validation du composant `Approvisionnement::enregistrerReglement`, qui la
/// précède. Elles vivent ici, sans Drift ni widget, pour qu'un test les éprouve
/// seules ; puis le vrai service et le vrai composant PHP les confrontent
/// (`reglement_contre_serveur_test.dart`).
///
/// ## Deux étages, comme au serveur
///
/// 1. le COMPOSANT (`Approvisionnement`) : le droit d'écriture sur M7, puis la
///    validation Laravel de trois propriétés — la commande (`required`,
///    `exists`), le montant (`required`, `numeric`, `gt:0`), la trésorerie
///    (`required`, `in`) ;
/// 2. le SERVICE (`ReglementFournisseurService`) : trésorerie connue, montant
///    lisible et positif, montant ≤ reste dû — dans CET ordre.
///
/// @see EF-M7-04 Dettes fournisseurs
/// @see RG-11 La pièce comptable d'un règlement est validée, donc immuable
library;

import '../../caisse/domain/montant_caisse.dart'
    show DecimalSaisi, formaterCentimesEnFcfa;
import '../../comptabilite/domain/montant_comptable.dart';
import '../../depenses/domain/categories_depense.dart';
import '../../facturation/domain/messages_encaissement.dart';
import '../../facturation/domain/regles_encaissement.dart'
    show centimesTronquesDuServeur, estVideAuSensDePhp;
import 'entities/commande_achat.dart';
import 'messages_reglement.dart';

export '../../facturation/domain/regles_encaissement.dart'
    show estVideAuSensDePhp;

/// Le champ d'une saisie refusée, pour que l'écran pose le message SOUS le bon
/// champ (le `@error('regMontant')` de la vue).
enum ChampReglement {
  commande('regCommandeId', MessagesReglement.attributCommande),
  montant('regMontant', MessagesReglement.attributMontant),
  tresorerie('regTresorerie', MessagesReglement.attributTresorerie);

  const ChampReglement(this.propriete, this.attribut);

  /// Le nom de la propriété Livewire du serveur.
  final String propriete;

  /// L'attribut que Laravel écrit dans le message de validation.
  final String attribut;
}

/// Un geste refusé : rien n'a été écrit.
class RefusReglement implements Exception {
  const RefusReglement(this.message, {this.champ});

  final String message;

  /// Le champ visé, ou `null` pour un refus qui ne tient pas à une saisie
  /// (droit manquant, commande soldée — l'erreur `selection` de la vue).
  ///
  /// ⚠ Au serveur, TOUT refus du service s'affiche sous le champ montant
  /// (`addError('regMontant', …)`), trésorerie inconnue comprise. Le champ est
  /// donc renseigné par l'appelant du service, pas par la règle.
  final ChampReglement? champ;

  @override
  String toString() => message;
}

/// `['required', 'numeric', 'gt:0']` du montant, dans l'ordre de Laravel.
///
/// Un seul message sort. `gt:0` sur la valeur EXACTE : `0.004` passe ici (et
/// sera refusé par le service, qui tronque à deux décimales avant de comparer).
void validerMontantReglement(String? brut) {
  const champ = ChampReglement.montant;
  if (estVideAuSensDePhp(brut)) {
    throw RefusReglement(
      MessagesEncaissement.obligatoire(champ.attribut),
      champ: champ,
    );
  }
  final decimal = DecimalSaisi.lire(brut!);
  if (decimal == null) {
    throw RefusReglement(
      MessagesEncaissement.nombre(champ.attribut),
      champ: champ,
    );
  }
  if (!decimal.estStrictementPositif) {
    throw const RefusReglement(
      MessagesReglement.superieurAZero,
      champ: ChampReglement.montant,
    );
  }
}

/// `['required', 'in:caisse,momo,banque']` de la trésorerie.
TresorerieDepense validerTresorerieReglement(String? brut) {
  const champ = ChampReglement.tresorerie;
  if (estVideAuSensDePhp(brut)) {
    throw RefusReglement(
      MessagesEncaissement.obligatoire(champ.attribut),
      champ: champ,
    );
  }
  final tresorerie = TresorerieDepense.depuisCode(brut!);
  if (tresorerie == null) {
    throw RefusReglement(
      MessagesEncaissement.invalide(champ.attribut),
      champ: champ,
    );
  }
  return tresorerie;
}

/// Le montant tel que `ReglementFournisseurService::regler` le lit :
/// `is_numeric`, puis `bccomp($montant, '0', 2)` — qui TRONQUE à la deuxième
/// décimale et lève une `ValueError` sur un texte mal formé.
///
/// Rend les centimes TRONQUÉS (jamais arrondis : `100.999` vaut `100.99`, comme
/// `bcadd($montant, '0', 2)` qui l'écrit — et la pièce passe le même montant).
/// Lève [RefusReglement] sur un montant illisible ou ≤ 0 ; le contrôle contre le
/// reste dû est un autre geste.
BigInt montantDuReglementCentimes(String montant) {
  final decimal = DecimalSaisi.lire(montant);
  if (decimal == null) {
    throw const RefusReglement(MessagesReglement.montantInvalide);
  }
  if (!decimal.estBienFormePourBc) {
    // Le serveur plante ici (HTTP 500) AVANT d'écrire ; le poste refuse, avec sa
    // propre phrase (écart nommé, D259).
    throw const RefusReglement(MessagesReglement.malForme);
  }
  final centimes = centimesTronquesDuServeur(montant);
  if (centimes <= BigInt.zero) {
    throw const RefusReglement(MessagesReglement.montantInvalide);
  }
  return centimes;
}

/// `resteDu()` du service : le total de la commande moins ses règlements ACTIFS,
/// planché à zéro (un trop-payé ne devient pas un reste négatif).
int resteDuCentimes({
  required int totalCommandeCentimes,
  required int regleActifCentimes,
}) {
  final reste = totalCommandeCentimes - regleActifCentimes;
  return reste < 0 ? 0 : reste;
}

/// La chaîne à deux décimales du serveur, pour les messages (« 2500.00 »).
String chaineDuReglement(int centimes) => chaineDepuisCentimes(centimes);

/// Le libellé de la pièce d'un règlement — `sprintf('Règlement fournisseur %s —
/// %s', raison_sociale, reglement->id)` du serveur. C'est LE lien entre un
/// règlement et sa pièce (PA-52 : aucune colonne `ecriture_id`), unique par
/// l'identifiant.
String libellePieceReglement(String raisonSociale, String reglementId) =>
    'Règlement fournisseur $raisonSociale — $reglementId';

/// Les statuts qui ENGAGENT encore une dette : tout sauf `receptionnee` et
/// `cloturee` — `CommandeAchat::estCloturee()` du serveur, que `dettes()` de la
/// vue emploie pour écarter une commande de l'onglet.
bool figureAuxDettes(StatutCommande? statut) =>
    statut != StatutCommande.receptionnee && statut != StatutCommande.cloturee;

/// `MontantFcfa::format($valeurDuChamp)` — le « reste dû » du sous-titre de la
/// modale, qui est en réalité la valeur COURANTE du champ montant (D261).
///
/// Arrondi à l'unité (la demi-unité s'éloigne de zéro), signe conservé, « FCFA »
/// derrière. Une chaîne VIDE vaut zéro (`bccomp('')` l'accepte). Une valeur qui
/// ne se lit pas comme un nombre bien formé rend `null` : le serveur plante au
/// rendu (`ValueError` de `bcmath`, HTTP 500 — D259) et le poste garde le
/// sous-titre précédent plutôt que d'en inventer un.
String? montantAffichableDuChamp(String brut) {
  if (brut.isEmpty) return formaterCentimesEnFcfa(0);
  final decimal = DecimalSaisi.lire(brut);
  if (decimal == null || !decimal.estBienFormePourBc) return null;
  return formaterCentimesEnFcfa(centimesTronquesDuServeur(brut).toInt());
}

/// Le libellé d'une trésorerie à la liste de la modale — `match ($cle)` de la
/// vue (`achats_pwa.appro.tresorerie_*`). Ce n'est PAS `TresorerieDepense.
/// libelle` (« Compte bancaire »), qui est celui de l'écran Dépenses : deux
/// écrans, deux mots pour le même compte, et chacun garde le sien.
String libelleTresorerieDuReglement(TresorerieDepense tresorerie) =>
    switch (tresorerie) {
      TresorerieDepense.caisse => MessagesReglement.tresorerieCaisse,
      TresorerieDepense.momo => MessagesReglement.tresorerieMobileMoney,
      TresorerieDepense.banque => MessagesReglement.tresorerieBanque,
    };
