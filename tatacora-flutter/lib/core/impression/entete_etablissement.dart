/// **L'en-tête de l'établissement — un seul objet, pour tous les papiers.**
///
/// ## Pourquoi ce fichier existe, et pourquoi il est ici et pas dans un module
///
/// `RESPECT_TABLEAU_RAPPORT.md` §4 recense l'en-tête **recopiée localement**
/// comme non-conformité n°1 : *« plus simple de copier l'en-tête existante »*.
/// `DIRECTIVE_EXPORT_PDF.md` §3 pose la contrepartie — un seul point de
/// composition, appelé *« par tout export PDF quel que soit le module
/// d'origine (Hub M14 à 13 onglets à terme, ou document transactionnel unitaire
/// type ticket de vente/contrat de location) »*.
///
/// Le rouleau 80 mm (D3) et la facture A4 (D4) sont **deux papiers de la même
/// pièce**. Ils n'affichent pas la même quantité de texte — une bande de 80 mm
/// ne porte pas une adresse postale complète — mais ils partent du **même**
/// objet. Deux jeux de valeurs finiraient par diverger, et c'est le second,
/// celui que personne ne relit, qui porterait le mauvais numéro de téléphone.
///
/// ## ⚠ Valeurs en dur, et c'est un écart NOMMÉ (repris de D3, non aggravé)
///
/// Depuis le 09/10/2026 (schéma v11), le poste a une table locale
/// `parametres_systeme_local` où l'exploitant saisit l'identité, l'IFU et le
/// RCCM (écran Paramètres). **Cet objet ne les lit PAS encore** : ses valeurs
/// restent celles du prototype ci-dessous, et rien de ce qui se saisit dans
/// Paramètres n'atteint un document imprimé. Le brancher touche 19 appels de
/// `EnteteEtablissement(` (14 fichiers de `lib`) — un lot à part, à faire d'un seul
/// geste pour que tous les papiers disent la même chose. Les lire d'une
/// configuration absente produirait un en-tête **vide** sur un document remis
/// à un client : il faudra garder ces valeurs comme repli.
///
/// Source des valeurs : `DIRECTIVE_EXPORT_PDF.md` §1, colonne « Confirmé,
/// valeurs réellement saisies dans le prototype ».
///
/// ## ⚠ IFU et RCCM sont VIDES, délibérément
///
/// La directive est explicite : le prototype ne montre qu'un `placeholder` de
/// format (`Ex. 3202612345678`, `Ex. RB/NAT/23 B 0456`), **jamais une vraie
/// valeur**. L'en-tête « s'adapte silencieusement selon ce qui est renseigné »
/// et n'imprime *« jamais un placeholder du type "Ex. ..." sur un document
/// réel »*.
///
/// Un IFU d'exemple sur une facture remise à un client serait un **faux
/// identifiant fiscal**. [ligneIdentificationFiscale] rend donc `null` tant que
/// rien n'est renseigné — et [_renseigne] refuse aussi ce qui *ressemble* à un
/// exemple de format, parce que la seule façon dont cette valeur peut arriver
/// un jour est la saisie manuelle d'un écran Paramètres qui n'existe pas
/// encore.
library;

import 'dart:typed_data';

import 'texte_ticket.dart';

/// L'identité de l'établissement, telle qu'elle s'imprime.
final class EnteteEtablissement {
  const EnteteEtablissement({
    this.etablissement = 'GÎTE CHEZ NOËL',
    this.localite = 'Natitingou — Bénin',
    this.raisonSociale = 'TATACORA AFRIQUE',
    this.enseigne = 'Gîte Chez Noël',
    // `rapports.entete.localisation`, la clé que l'en-tête des états du
    // serveur imprime. Décision du PO du 13/10/2026 (PA-209, D389) :
    // « Système de gestion Intégré », casse exacte du PO ; tenu égal à la clé
    // par `entete_etablissement_test`.
    this.sousTitre = 'Natitingou, Bénin — Système de gestion Intégré',
    this.adresse = 'Quartier Sountichirantikou, Natitingou, Bénin',
    this.telephone = '+229 01 97 35 59 74',
    this.email = 'nabogounoel@yahoo.fr',
    this.siteWeb = 'www.tatacora.com',
    this.ifu,
    this.rccm,
    this.logo,
    this.mentionInstitutionnelle = 'Projet PAEB — Cabinet FAGUEZ SARL',
  });

  /// La mention du pied des états d'export — `rapports.entete.mention_institutionnelle`
  /// côté serveur, au mot (grille `RESPECT_TABLEAU_RAPPORT.md` : « mention
  /// PAEB/FAGUEZ SARL + date/heure d'édition »). Jamais sur un document remis
  /// au client (PA-194).
  final String mentionInstitutionnelle;

  /* ---------------- Ce que le rouleau 80 mm porte ------------------ */

  /// Titre court du ticket — une bande de 80 mm ne porte rien de plus.
  final String etablissement;

  /// Sous-titre court du ticket.
  final String localite;

  /* ---------------- Ce que la page A4 porte en plus ---------------- */

  final String raisonSociale;
  final String enseigne;
  final String sousTitre;
  final String adresse;
  final String telephone;
  final String email;
  final String siteWeb;

  /// Identifiant Fiscal Unique — `null` tant qu'il n'est pas attribué.
  final String? ifu;

  /// Registre du Commerce — `null` tant qu'il n'est pas attribué.
  final String? rccm;

  /// Le logo, en octets d'image (`AppAssets.logo`, PNG paysage du PO depuis
  /// le 14/10/2026, D392), ou `null`.
  ///
  /// **Injecté, jamais lu ici.** Une lecture de fichier dans un objet de
  /// composition rendrait la composition impossible à éprouver hors d'une
  /// application complète — et surtout impossible à rendre déterministe.
  final Uint8List? logo;

  /// La ligne d'identification fiscale, ou `null` s'il n'y a rien à dire.
  ///
  /// Jamais une ligne vide visible, jamais un exemple de format : c'est
  /// exactement le traitement imposé par `DIRECTIVE_EXPORT_PDF.md` §1.
  String? get ligneIdentificationFiscale {
    final i = _renseigne(ifu) ? 'IFU : ${ifu!.trim()}' : null;
    final r = _renseigne(rccm) ? 'RCCM : ${rccm!.trim()}' : null;
    if (i == null && r == null) return null;
    if (i != null && r != null) return '$i — $r';
    return i ?? r;
  }

  /// Les lignes de l'en-tête A4, dans l'ordre, **déjà normalisées**.
  ///
  /// L'ordre suit le gabarit de `DIRECTIVE_EXPORT_PDF.md` §2.
  List<String> get lignesA4 => [
    for (final ligne in <String?>[
      raisonSociale,
      enseigne,
      sousTitre,
      adresse,
      'Tél. $telephone — $email',
      siteWeb,
      ligneIdentificationFiscale,
    ])
      if (ligne != null && ligne.trim().isNotEmpty) texteTicket(ligne),
  ];

  /// Une valeur est-elle réellement renseignée ?
  ///
  /// Vide, blanche — ou **exemple de format**. Le troisième cas n'est pas
  /// théorique : c'est littéralement ce que le prototype affiche
  /// (`Ex. 3202612345678`), et le seul chemin par lequel un IFU peut arriver
  /// ici un jour est la recopie manuelle d'un champ de saisie. Refuser un
  /// « Ex. ... » coûte trois lignes ; l'imprimer sur une facture remise à un
  /// client serait un faux identifiant fiscal.
  static bool _renseigne(String? valeur) {
    final v = valeur?.trim();
    if (v == null || v.isEmpty) return false;
    final majuscules = v.toUpperCase();
    return !majuscules.startsWith('EX.') &&
        !majuscules.startsWith('EX ') &&
        !majuscules.startsWith('EXEMPLE');
  }

  EnteteEtablissement avecLogo(Uint8List? octets) => EnteteEtablissement(
    etablissement: etablissement,
    localite: localite,
    raisonSociale: raisonSociale,
    enseigne: enseigne,
    sousTitre: sousTitre,
    adresse: adresse,
    telephone: telephone,
    email: email,
    siteWeb: siteWeb,
    ifu: ifu,
    rccm: rccm,
    logo: octets,
    mentionInstitutionnelle: mentionInstitutionnelle,
  );
}
