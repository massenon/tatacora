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
/// ## Les valeurs viennent de `parametres_systeme_local` (14/10/2026)
///
/// Directive du PO du 14/10/2026 : l'en-tête de TOUS les états se lit des
/// paramètres saisis sur ce poste (écran Paramètres), par
/// [EnteteEtablissement.depuisParametres] — appelée par le seul
/// `lireEnteteEtablissementProvider` (`entete_parametree.dart`). Traduction de
/// `ReportHeaderService::genererEnTete()` du serveur, à une différence près,
/// décidée par le PO : une clé de la directive (raison sociale, promoteur,
/// WhatsApp, site web, IFU, RCCM, régime fiscal) VIDE ou ABSENTE fait
/// **disparaître** sa ligne — jamais une ligne blanche, jamais un « IFU : »
/// suivi de rien. Adresse, téléphone et courriel, hors de la directive,
/// gardent le repli confirmé du serveur (`ReportHeaderService::DEFAUTS`).
///
/// Le constructeur `const EnteteEtablissement()` garde les valeurs du
/// prototype (`DIRECTIVE_EXPORT_PDF.md` §1, colonne « Confirmé ») : c'est le
/// repli d'une composition sans base, jamais celui d'un état exporté.
///
/// ## ⚠ Jamais un exemple de format
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
/// exemple de format, recopié par erreur d'un champ de saisie.
library;

import 'dart:typed_data';

import 'texte_ticket.dart';

/// Les clés de `parametres_systeme_local` que l'en-tête lit — celles de
/// `ReportHeaderService` (`CLE_*`), au caractère près. Ce fichier est leur
/// LECTEUR déclaré au registre (`SpecParametre.lecteur`).
abstract final class ClesEntete {
  static const raisonSociale = 'entreprise_raison_sociale';
  static const promoteur = 'entreprise_promoteur';
  static const adresse = 'entreprise_adresse';
  static const telephone = 'entreprise_telephone';
  static const email = 'entreprise_email';
  static const whatsapp = 'communication_whatsapp';
  static const siteWeb = 'entreprise_site_web';
  static const ifu = 'entreprise_ifu';
  static const rccm = 'entreprise_rccm';
  static const regimeFiscal = 'fiscalite_regime';
}

/// Les libellés du régime fiscal — `choixLibelles` de la définition serveur
/// (`RegistreParametres`, clé `fiscalite_regime`). Un code inconnu n'imprime
/// RIEN : un code technique (`reel_normal`) sur un document remis dirait
/// moins que rien.
const Map<String, String> libellesRegimeFiscal = {
  'reel_normal': 'Réel normal',
  'reel_simplifie': 'Réel simplifié',
  'tpu': 'Taxe Professionnelle Unique',
};

/// L'identité de l'établissement, telle qu'elle s'imprime.
final class EnteteEtablissement {
  const EnteteEtablissement({
    this.etablissement = 'GÎTE CHEZ NOËL',
    this.localite = 'Natitingou — Bénin',
    this.raisonSociale = 'TATACORA AFRIQUE',
    this.enseigne = 'Gîte Chez Noël',
    // `rapports.entete.localisation`, la clé que l'en-tête des états du
    // serveur imprime. Décision du PO du 14/10/2026 : « Système de gestion
    // Intégré — Gîte Chez Noël, Natitingou (Bénin) », la même phrase que
    // l'écran Aide (`ecran_aide_a_propos.dart`) et que `pwa.aide.enseigne`.
    this.sousTitre =
        'Système de gestion Intégré — Gîte Chez Noël, Natitingou (Bénin)',
    this.adresse = 'Quartier Sountichirantikou, Natitingou, Bénin',
    this.telephone = '+229 01 97 35 59 74',
    this.email = 'nabogounoel@yahoo.fr',
    this.siteWeb = 'www.tatacora.com',
    this.promoteur,
    this.whatsapp,
    this.ifu,
    this.rccm,
    this.regimeFiscal,
    this.logo,
    this.mentionInstitutionnelle = 'Projet PAEB — Cabinet FAGUEZ SARL',
  });

  /// L'en-tête composé depuis les paramètres saisis sur ce poste
  /// ([valeurs] : clé -> valeur de `parametres_systeme_local`).
  ///
  /// Une clé de la directive du PO vide ou absente rend `null`, et sa ligne
  /// disparaît de [lignesA4]. Adresse, téléphone et courriel gardent le repli
  /// confirmé du constructeur.
  factory EnteteEtablissement.depuisParametres(Map<String, String> valeurs) {
    const repli = EnteteEtablissement();
    String? lue(String cle) =>
        _renseigne(valeurs[cle]) ? valeurs[cle]!.trim() : null;
    final codeRegime = lue(ClesEntete.regimeFiscal);

    return EnteteEtablissement(
      raisonSociale: lue(ClesEntete.raisonSociale),
      promoteur: lue(ClesEntete.promoteur),
      adresse: lue(ClesEntete.adresse) ?? repli.adresse,
      telephone: lue(ClesEntete.telephone) ?? repli.telephone,
      email: lue(ClesEntete.email) ?? repli.email,
      whatsapp: lue(ClesEntete.whatsapp),
      siteWeb: lue(ClesEntete.siteWeb),
      ifu: lue(ClesEntete.ifu),
      rccm: lue(ClesEntete.rccm),
      regimeFiscal: codeRegime == null
          ? null
          : libellesRegimeFiscal[codeRegime],
    );
  }

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

  /// `entreprise_raison_sociale` — `null` : la ligne disparaît.
  final String? raisonSociale;
  final String enseigne;
  final String sousTitre;
  final String? adresse;
  final String? telephone;
  final String? email;

  /// `entreprise_site_web` — `null` : la ligne disparaît.
  final String? siteWeb;

  /// `entreprise_promoteur`, imprimé « Promoteur : … » — `null` : absent.
  final String? promoteur;

  /// `communication_whatsapp`, imprimé « WhatsApp : … » — `null` : absent.
  final String? whatsapp;

  /// Identifiant Fiscal Unique — `null` tant qu'il n'est pas attribué.
  final String? ifu;

  /// Registre du Commerce — `null` tant qu'il n'est pas attribué.
  final String? rccm;

  /// Le LIBELLÉ du régime fiscal (« Réel normal »), jamais son code —
  /// `null` tant qu'il n'est pas renseigné.
  final String? regimeFiscal;

  /// Le logo, en octets d'image (`AppAssets.logo`, PNG paysage du PO depuis
  /// le 14/10/2026, D392), ou `null`.
  ///
  /// **Injecté, jamais lu ici.** Une lecture de fichier dans un objet de
  /// composition rendrait la composition impossible à éprouver hors d'une
  /// application complète — et surtout impossible à rendre déterministe.
  final Uint8List? logo;

  /// La ligne des mentions légales, ou `null` s'il n'y a rien à dire —
  /// `EnTeteRapport::mentionsLegales()` du serveur : IFU, RCCM, régime fiscal,
  /// chacun SEULEMENT s'il est renseigné.
  ///
  /// Jamais une ligne vide visible, jamais un exemple de format : c'est
  /// exactement le traitement imposé par `DIRECTIVE_EXPORT_PDF.md` §1.
  String? get ligneIdentificationFiscale {
    final mentions = [
      if (_renseigne(ifu)) 'IFU : ${ifu!.trim()}',
      if (_renseigne(rccm)) 'RCCM : ${rccm!.trim()}',
      if (_renseigne(regimeFiscal)) 'Régime fiscal : ${regimeFiscal!.trim()}',
    ];
    return mentions.isEmpty ? null : mentions.join(' — ');
  }

  /// Les lignes de l'en-tête A4, dans l'ordre, **déjà normalisées**.
  ///
  /// L'ordre suit le gabarit serveur `pdf/partials/entete-rapport.blade.php` :
  /// raison sociale, enseigne et localisation, promoteur, adresse, téléphone
  /// et courriel, WhatsApp, site, puis les mentions légales. Une valeur
  /// absente fait disparaître sa ligne entière, libellé compris.
  List<String> get lignesA4 => [
    for (final ligne in <String?>[
      raisonSociale,
      enseigne,
      sousTitre,
      if (_renseigne(promoteur)) 'Promoteur : ${promoteur!.trim()}',
      adresse,
      _ligneContact,
      if (_renseigne(whatsapp)) 'WhatsApp : ${whatsapp!.trim()}',
      siteWeb,
      ligneIdentificationFiscale,
    ])
      if (ligne != null && ligne.trim().isNotEmpty) texteTicket(ligne),
  ];

  /// « Tél. … — courriel », ou ce qui en est renseigné.
  String? get _ligneContact {
    final tel = _renseigne(telephone) ? 'Tél. ${telephone!.trim()}' : null;
    final mel = _renseigne(email) ? email!.trim() : null;
    if (tel == null && mel == null) return null;
    if (tel != null && mel != null) return '$tel — $mel';
    return tel ?? mel;
  }

  /// Une valeur est-elle réellement renseignée ?
  ///
  /// Vide, blanche — ou **exemple de format**. Le troisième cas n'est pas
  /// théorique : c'est littéralement ce que le prototype affiche
  /// (`Ex. 3202612345678`), et un IFU arrive ici par la recopie manuelle d'un
  /// champ de saisie. Refuser un « Ex. ... » coûte trois lignes ; l'imprimer
  /// sur une facture remise à un client serait un faux identifiant fiscal.
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
    promoteur: promoteur,
    whatsapp: whatsapp,
    ifu: ifu,
    rccm: rccm,
    regimeFiscal: regimeFiscal,
    logo: octets,
    mentionInstitutionnelle: mentionInstitutionnelle,
  );
}
