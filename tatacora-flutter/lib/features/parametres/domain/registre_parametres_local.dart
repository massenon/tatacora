/// Le REGISTRE FERMÉ des paramètres modifiables sur ce poste.
///
/// ## D'où vient cette liste
///
/// Du serveur, mot pour mot : `RegistreParametres::definitions()` (Laravel) est
/// la source, et ce fichier en est la copie locale — le poste n'a plus de
/// serveur à interroger. La copie n'est donc **jamais relue à la main** : le
/// test `registre_parametres_local_test.dart` exécute le registre PHP (par
/// `php`, comme le comparateur de conformité) et exige, clé par clé, le même
/// groupe, le même type, le même libellé, la même aide (à l'ajout près des
/// phrases sur les secrets), les mêmes choix et les mêmes bornes. Une clé
/// ajoutée au serveur fait échouer ce test : on ne l'ajoute pas ici « pour
/// faire passer », on se demande d'abord si elle a un lecteur sur ce poste.
///
/// ## Ce qu'une clé inconnue devient
///
/// Refusée, jamais créée (`EnregistrerParametres`). Un `mecef_actif` que
/// l'écran confirmerait et que rien ne lirait serait l'indicateur qui affirme
/// un état qu'il n'a pas vérifié (PA-59/60/61).
///
/// ## Aucun secret, aucune valeur réglementaire par défaut
///
/// Le registre n'en déclare aucun : une clé dont le nom évoque un secret est
/// refusée par le test structurel. Et AUCUNE spécification ne porte de valeur
/// par défaut — un paramètre non saisi reste « — » (PA-53, PA-19).
///
/// ## `lecteur` : qui lit cette clé SUR CE POSTE
///
/// Le chemin du fichier qui la consomme, ou `null` quand **personne** ne la lit
/// encore. C'est écrit à l'écran (voir `LigneParametre`) : une valeur que
/// l'exploitant saisit sans qu'aucun module ne s'en serve donnerait
/// l'illusion d'un réglage sans effet (piège 9). Le test relit chaque
/// `lecteur` non nul et exige que le fichier contienne la clé — ou, pour les
/// trois bascules d'activation, leur constante `OptionsSysteme.cle…`. Il balaie
/// aussi tout `lib/` à la recherche d'un lecteur NON déclaré (D278 : la sonde
/// excluait tout `features/parametres/`, et un lecteur logé là lui échappait).
library;

import 'entities/parametre.dart';

/// Comment un texte se contrôle, au-delà de sa longueur.
enum FormatTexte {
  libre,

  /// `regex:/^\+?[0-9 ().\-]{6,}$/` du serveur — chiffres, espaces, indicatif.
  telephone,

  /// `email:rfc` du serveur, approché : une adresse avec une arobase et un
  /// domaine pointé. Il protège un en-tête imprimé et, depuis le 14/10/2026,
  /// l'expéditeur des messages à l'éditeur (`email_smtp_utilisateur`).
  courriel,
}

/// Pourquoi un taux confirmé de la paie ne peut pas être vidé.
///
/// `PaieDao.installerReferentielConfirme` réinstalle toute clé confirmée
/// ABSENTE à la prochaine ouverture de l'écran Paie : vider ce taux ne ferait
/// que le faire revenir à sa valeur d'origine, en laissant croire qu'il avait
/// disparu (test : `enregistrer_parametres_test.dart`, « un taux confirmé ne se vide pas »).
const String raisonTauxConfirmeNonVidable =
    'Ce taux est exigé par le calcul de la paie : modifiez-le, ne le videz '
    'pas. Un taux vidé serait réinstallé à sa valeur d’origine à la prochaine '
    'ouverture de l’écran Paie.';

/// Une définition de paramètre — la forme, jamais la valeur.
final class SpecParametre {
  const SpecParametre({
    required this.cle,
    required this.groupe,
    required this.libelle,
    required this.type,
    this.choix = const [],
    this.aide,
    this.longueurMax,
    this.minimum,
    this.maximum,
    this.format = FormatTexte.libre,
    this.videRefuse,
    this.lecteur,
  });

  final String cle;

  /// Le groupe du serveur, en chaîne (voir `DefinitionParametre.groupe`).
  final String groupe;
  final String libelle;
  final TypeParametre type;
  final List<String> choix;
  final String? aide;

  /// Longueur maximale d'un texte (`max:N` d'un `string`).
  final int? longueurMax;

  /// Bornes d'un `decimal` ou d'un `entier`, en CHAÎNES : un seuil comme « 1 »
  /// ou « 4 » se compare en arithmétique entière, jamais en flottant.
  final String? minimum;
  final String? maximum;
  final FormatTexte format;

  /// Le motif pour lequel cette clé ne peut pas être vidée, ou `null`.
  final String? videRefuse;

  /// Le fichier qui LIT cette clé sur ce poste, ou `null` si personne.
  final String? lecteur;
}

/// Le registre fermé.
abstract final class RegistreParametresLocal {
  /// Les clés des taux de charges sociales : leur stockage est `taux_paie_local`
  /// (`PaieDao`), pas `parametres_systeme_local` — un seul auteur par taux.
  static const List<String> clesDeLaPaie = [
    'taux_cnss_salarie',
    'taux_cnss_pension_employeur',
    'taux_cnss_prestations_familiales',
    'taux_vps',
    'taux_cnss_risques_professionnels',
  ];

  static SpecParametre? parCle(String cle) {
    for (final s in definitions) {
      if (s.cle == cle) return s;
    }
    return null;
  }

  static bool existe(String cle) => parCle(cle) != null;

  static List<String> get cles => [for (final s in definitions) s.cle];

  /// L'ordre est celui du serveur : l'écran range par onglet, mais deux
  /// champs d'un même onglet se suivent comme au serveur.
  static const List<SpecParametre> definitions = [
    SpecParametre(
      cle: 'entreprise_raison_sociale',
      groupe: 'entreprise',
      libelle: 'Raison sociale',
      type: TypeParametre.texte,
      longueurMax: 150,
      // LUE depuis le 14/10/2026 (directive du PO) : l'en-tête de tous les
      // états imprimés (`EnteteEtablissement.depuisParametres`).
      lecteur: 'lib/core/impression/entete_etablissement.dart',
    ),
    SpecParametre(
      cle: 'entreprise_promoteur',
      groupe: 'entreprise',
      libelle: 'Nom du promoteur',
      type: TypeParametre.texte,
      aide:
          'Imprimé sous la raison sociale dans l’en-tête des états quand il est renseigné — jamais un nom deviné.',
      longueurMax: 150,
      lecteur: 'lib/core/impression/entete_etablissement.dart',
    ),
    SpecParametre(
      cle: 'entreprise_adresse',
      groupe: 'entreprise',
      libelle: "Adresse du siège d'exploitation",
      type: TypeParametre.texte,
      longueurMax: 255,
      lecteur: 'lib/core/impression/entete_etablissement.dart',
    ),
    SpecParametre(
      cle: 'entreprise_telephone',
      groupe: 'entreprise',
      libelle: 'Téléphone principal',
      type: TypeParametre.texte,
      longueurMax: 40,
      format: FormatTexte.telephone,
      lecteur: 'lib/core/impression/entete_etablissement.dart',
    ),
    SpecParametre(
      cle: 'entreprise_email',
      groupe: 'entreprise',
      libelle: 'Email de contact',
      type: TypeParametre.texte,
      format: FormatTexte.courriel,
      longueurMax: 150,
      lecteur: 'lib/core/impression/entete_etablissement.dart',
    ),
    SpecParametre(
      cle: 'communication_whatsapp',
      groupe: 'entreprise',
      libelle: 'Numéro WhatsApp Business',
      type: TypeParametre.texte,
      aide:
          'Le numéro, pas la clé d’API — celle-ci vit en configuration serveur. Imprimé dans l’en-tête des états quand il est renseigné.',
      longueurMax: 40,
      format: FormatTexte.telephone,
      lecteur: 'lib/core/impression/entete_etablissement.dart',
    ),
    SpecParametre(
      cle: 'entreprise_site_web',
      groupe: 'entreprise',
      libelle: 'Site web',
      type: TypeParametre.texte,
      longueurMax: 150,
      lecteur: 'lib/core/impression/entete_etablissement.dart',
    ),
    SpecParametre(
      cle: 'entreprise_ifu',
      groupe: 'entreprise',
      libelle: 'IFU (Identifiant Fiscal Unique)',
      type: TypeParametre.texte,
      aide:
          'L’IFU est obligatoire pour la facturation MECeF. Laissé vide, la mention n’apparaît sur aucun document : imprimer un exemple de format serait un faux identifiant fiscal.',
      longueurMax: 30,
      lecteur: 'lib/core/impression/entete_etablissement.dart',
    ),
    SpecParametre(
      cle: 'entreprise_rccm',
      groupe: 'entreprise',
      libelle: 'RCCM',
      type: TypeParametre.texte,
      aide: 'Même règle que l’IFU : absent tant qu’il n’est pas renseigné.',
      longueurMax: 30,
      lecteur: 'lib/core/impression/entete_etablissement.dart',
    ),
    SpecParametre(
      cle: 'entreprise_numero_mecef',
      groupe: 'entreprise',
      libelle: 'N° Contribuable MECeF',
      type: TypeParametre.texte,
      aide:
          'Fourni par la DGI. Identifiant, donc paramétrable — la CLÉ D’API MECeF, elle, vit en configuration serveur et n’apparaîtra jamais ici.',
      longueurMax: 30,
    ),
    SpecParametre(
      cle: 'tva_active',
      // LUE depuis le 12/10/2026 (lot 6) : `calcul_tva.dart` ventile HT/TVA dans
      // la PIÈCE COMPTABLE d'une vente. La correction ne dit donc plus « n'agit
      // sur aucune facture » — c'était vrai jusque-là, et cela cesserait de
      // l'être : elle dit ce qui reste vrai (aucune FACTURE n'est ventilée).
      //
      // L'AIDE du serveur (« la facture lèverait au comptoir ») reste mot pour
      // mot, confrontée à la vue : l'écart est NOMMÉ ici, dans la correction.
      // Sur ce poste ce n'est pas la facture qui est refusée sans taux, c'est la
      // CLÔTURE de la vente (`RefusTva` de `PanierDao.cloturer`).
      groupe: 'fiscalite',
      libelle: 'Assujettissement à la TVA',
      type: TypeParametre.booleen,
      aide:
          'Ne peut pas être activé tant que le taux n’est pas renseigné : la facture lèverait au comptoir.',
      lecteur: 'lib/features/comptabilite/domain/calcul_tva.dart',
    ),
    SpecParametre(
      cle: 'taux_tva',
      groupe: 'fiscalite',
      libelle: 'Taux de TVA (%)',
      type: TypeParametre.decimal,
      minimum: '0',
      maximum: '100',
      lecteur: 'lib/features/comptabilite/domain/calcul_tva.dart',
    ),
    SpecParametre(
      cle: 'convention_prix',
      groupe: 'fiscalite',
      libelle: 'Convention des prix du catalogue',
      type: TypeParametre.choix,
      choix: ['ht', 'ttc'],
      aide:
          '« ht » : la TVA s’ajoute aux tarifs. « ttc » : elle en est extraite.',
      lecteur: 'lib/features/comptabilite/domain/calcul_tva.dart',
    ),
    SpecParametre(
      cle: 'fiscalite_regime',
      groupe: 'fiscalite',
      libelle: 'Régime fiscal',
      type: TypeParametre.choix,
      choix: ['reel_normal', 'reel_simplifie', 'tpu'],
      aide:
          'Imprimé avec l’IFU et le RCCM dans les mentions légales des états quand il est renseigné.',
      lecteur: 'lib/core/impression/entete_etablissement.dart',
    ),
    SpecParametre(
      cle: 'taux_cnss_salarie',
      groupe: 'social',
      libelle: 'CNSS part salariale (%)',
      type: TypeParametre.decimal,
      minimum: '0',
      maximum: '100',
      videRefuse: raisonTauxConfirmeNonVidable,
      lecteur: 'lib/features/rh/domain/entities/taux_paie.dart',
    ),
    SpecParametre(
      cle: 'taux_cnss_pension_employeur',
      groupe: 'social',
      libelle: 'CNSS pension, part patronale (%)',
      type: TypeParametre.decimal,
      minimum: '0',
      maximum: '100',
      videRefuse: raisonTauxConfirmeNonVidable,
      lecteur: 'lib/features/rh/domain/entities/taux_paie.dart',
    ),
    SpecParametre(
      cle: 'taux_cnss_prestations_familiales',
      groupe: 'social',
      libelle: 'CNSS prestations familiales (%)',
      type: TypeParametre.decimal,
      minimum: '0',
      maximum: '100',
      videRefuse: raisonTauxConfirmeNonVidable,
      lecteur: 'lib/features/rh/domain/entities/taux_paie.dart',
    ),
    SpecParametre(
      cle: 'taux_vps',
      groupe: 'social',
      libelle: 'Versement Patronal sur Salaires (%)',
      type: TypeParametre.decimal,
      aide:
          'Assiette : total des bruts, sans plafond. Jamais une retenue salariale.',
      minimum: '0',
      maximum: '100',
      videRefuse: raisonTauxConfirmeNonVidable,
      lecteur: 'lib/features/rh/domain/entities/taux_paie.dart',
    ),
    SpecParametre(
      cle: 'taux_cnss_risques_professionnels',
      groupe: 'social',
      libelle: 'CNSS risques professionnels (%)',
      type: TypeParametre.decimal,
      aide:
          'Non confirmé pour l’hôtellerie : la charge patronale reste publiée en fourchette tant qu’il est vide. Bornes réglementaires 1 à 4 %.',
      minimum: '1',
      maximum: '4',
      lecteur: 'lib/features/rh/domain/entities/taux_paie.dart',
    ),
    SpecParametre(
      cle: 'tolerance_reception_pct',
      groupe: 'exploitation',
      libelle: 'Tolérance de réception (%)',
      type: TypeParametre.decimal,
      aide:
          'RG-10 — écart de quantité toléré entre le bon de commande et la réception, en % : au-delà, la réception est refusée. Tant que ce champ est vide, aucune réception n’est possible — une tolérance devinée ferait accepter ou refuser des livraisons sur un critère arbitraire.',
      minimum: '0',
      maximum: '100',
      // LUE depuis le 09/10/2026 : `AchatsDao.enregistrerReception` lit cette
      // clé pour juger la conformité d'une réception (RG-10) et refuse de la
      // deviner. Le jour où M7 est devenu local, ce réglage a cessé d'être
      // « sans effet » — et l'écran Paramètres a cessé de le dire.
      lecteur: 'lib/features/achats/data/achats_dao.dart',
    ),
    SpecParametre(
      cle: 'hebergement_taux_annulation_moins_24h',
      groupe: 'exploitation',
      libelle: 'Taux d’annulation — moins de 24h avant la prestation (%)',
      type: TypeParametre.decimal,
      aide:
          'Pré-remplit le formulaire d’annulation d’une réservation à moins de 24h de la prestation (référence client : 50 %). Reste modifiable au cas par cas dans le formulaire — ce paramètre ne change jamais une annulation déjà enregistrée.',
      minimum: '0',
      maximum: '100',
      // LUE depuis le 12/10/2026 (lot 6) : le formulaire d'annulation d'une
      // réservation s'ouvre avec ce taux (`annulation_reservation.dart`). Avant,
      // l'aide promettait un formulaire qui n'existait pas.
      lecteur: 'lib/features/hebergement/domain/annulation_reservation.dart',
    ),
    SpecParametre(
      cle: 'delai_preavis_conge_jours',
      groupe: 'exploitation',
      libelle: 'Préavis de congé (jours)',
      type: TypeParametre.entier,
      minimum: '0',
      maximum: '365',
      // LUE depuis le 21/10/2026 : valider une demande de congé (RG-14) exige
      // ce réglage et REFUSE sans lui (`conges_plannings_dao.dart`).
      lecteur: 'lib/features/rh/data/conges_plannings_dao.dart',
    ),
    SpecParametre(
      cle: 'couverture_minimale_par_service',
      groupe: 'exploitation',
      libelle: 'Effectif minimal présent par service',
      type: TypeParametre.entier,
      minimum: '0',
      maximum: '100',
      // LUE depuis le 21/10/2026 : valider une demande de congé (RG-14) exige
      // ce réglage et REFUSE sans lui (`conges_plannings_dao.dart`).
      lecteur: 'lib/features/rh/data/conges_plannings_dao.dart',
    ),
    SpecParametre(
      cle: 'duree_retention_audit_jours',
      groupe: 'exploitation',
      libelle: 'Rétention du journal d’audit (jours)',
      type: TypeParametre.entier,
      aide:
          'Vide ou 0 : aucune purge n’a lieu. La durée contractuelle n’est pas tranchée (PA-08) — la renseigner DÉMARRE la suppression définitive de traces d’audit.',
      minimum: '0',
      maximum: '3650',
    ),
    SpecParametre(
      cle: 'email_smtp_hote',
      groupe: 'email',
      libelle: 'Serveur SMTP',
      type: TypeParametre.texte,
      aide:
          'Vide : la configuration serveur (.env) reste seule maîtresse. Renseigné, il prend la main sur elle pour tous les envois.',
      // LUE depuis le 14/10/2026 (Lot J2 partie 2) par l'envoi des messages à
      // l'éditeur (action réseau du poste). L'aide du serveur parle de
      // `.env`, qui n'existe pas ici : l'écart est NOMMÉ dans la correction.
      longueurMax: 150,
      lecteur: 'lib/features/transverse/data/envoi_messages_editeur.dart',
    ),
    SpecParametre(
      cle: 'email_smtp_port',
      groupe: 'email',
      libelle: 'Port',
      type: TypeParametre.entier,
      minimum: '1',
      maximum: '65535',
      lecteur: 'lib/features/transverse/data/envoi_messages_editeur.dart',
    ),
    SpecParametre(
      cle: 'email_smtp_securite',
      groupe: 'email',
      libelle: 'Sécurité',
      type: TypeParametre.choix,
      choix: ['tls', 'ssl', 'aucune'],
      lecteur: 'lib/features/transverse/data/envoi_messages_editeur.dart',
    ),
    SpecParametre(
      cle: 'email_smtp_utilisateur',
      groupe: 'email',
      libelle: 'Utilisateur SMTP',
      type: TypeParametre.texte,
      aide:
          'Le mot de passe SMTP, lui, reste en configuration serveur (.env) et n’apparaîtra jamais ici.',
      format: FormatTexte.courriel,
      longueurMax: 150,
      lecteur: 'lib/features/transverse/data/envoi_messages_editeur.dart',
    ),
    SpecParametre(
      cle: 'activation_suppression',
      groupe: 'activation',
      libelle: "Suppression d'un enregistrement",
      type: TypeParametre.booleen,
      aide:
          "Affiche le bouton Supprimer dans tous les modules. La suppression reste un archivage : l'élément part aux archives et peut être restauré.",
      // LUE depuis le 12/10/2026 (lot 7, D269) par les fournisseurs de M7, et
      // depuis le 13/10/2026 par le bouton d'archivage des unités d'hébergement
      // (décision du PO : « comme dans la vue »), et depuis le 21/10/2026 par
      // l'archivage des articles de stock (M6). L'aide du serveur, identique mot pour mot à la vue,
      // dit « tous les modules » : c'est faux sur ce poste (la Paie garde sa
      // règle propre, D272 ; les autres écrans n'ont pas de bouton Supprimer
      // branché sur la bascule). L'aide n'est donc PAS touchée ; l'écart est
      // NOMMÉ dans la correction, comme pour `tva_active`.
      // Le lecteur est celui qui interroge la base : `suppressionActiveProvider`
      // (la règle d'archivage `peutArchiver` en est le consommateur).
      lecteur:
          'lib/features/parametres/presentation/providers_options_systeme.dart',
    ),
    SpecParametre(
      cle: 'reinitialisation_seeders',
      groupe: 'activation',
      libelle: 'Réinitialisation des données de test',
      type: TypeParametre.booleen,
      aide:
          "Ouvre l'onglet qui vide les jeux de démonstration. À laisser fermé dès que l'exploitation réelle a commencé.",
      // LUE depuis le 14/10/2026 (lot E) par « Réinitialiser comme neuf »
      // d'Import & Export, relue au moment d'agir (`executer`).
      lecteur: 'lib/features/transverse/data/reinitialisation_locale.dart',
    ),
    SpecParametre(
      cle: 'activation_alertes_ouverture',
      groupe: 'activation',
      libelle: "Alertes à l'ouverture de session",
      type: TypeParametre.booleen,
      aide:
          'Affiche les stocks critiques et les créances échues dès la connexion.',
      // LUE depuis le 14/10/2026 (lot B, cloche de la barre supérieure) :
      // fermée, la cloche ne dérive plus aucune alerte, comme au serveur
      // (`AlertesOuverture::pour()`). Les deux modales d'ouverture de session
      // de la vue ne sont pas portées sur ce poste : l'aide (celle de la vue,
      // non touchée) promet plus que ce que le poste fait, l'écart est NOMMÉ
      // dans la correction.
      lecteur: 'lib/features/alertes/presentation/providers_alertes.dart',
    ),
  ];
}

/// Un paramètre de la base vierge : clé, valeur, description.
typedef ParametreInitial = ({String cle, String valeur, String? description});

/// Les paramètres INITIAUX d'un poste vierge — `ParametresEtablissementSeeder::
/// PARAMETRES` du serveur (script SQL du Product Owner du 14/10/2026,
/// directive Lot J2), recopié À L'IDENTIQUE : les 20 mêmes clés, valeurs et
/// descriptions, dans le même ordre. Une divergence avec le seeder se corrige
/// ICI.
///
/// ## Ce que cette liste change à la règle « aucune valeur par défaut »
///
/// Le registre ([RegistreParametresLocal.definitions]) ne porte toujours
/// AUCUNE valeur. Ces vingt valeurs sont des DONNÉES D'ÉTABLISSEMENT fournies
/// par le PO, posées UNE fois sur un poste vierge (création du premier compte)
/// et après « Réinitialiser comme neuf », clé par clé et SEULEMENT si la clé
/// est absente : une valeur corrigée à l'écran Paramètres n'est jamais
/// réécrite (`firstOrCreate` du serveur). Elles ne sont posées par aucune
/// migration et à aucun démarrage.
///
/// Comme au serveur : `email_smtp_securite` vaut `tls` (le script la laissait
/// vide, la directive dit « TLS ») ; aucun mot de passe SMTP (il n'est pas au
/// registre) ; `taux_cnss_risques_professionnels` n'y est PAS (PA-53).
///
/// Où elles vont : les quatre taux de la paie dans `taux_paie_local` (par
/// `PaieDao`, leur seul auteur, AVEC leur description), les seize autres dans
/// `parametres_systeme_local` (par `ParametresDao`). Cette table n'a pas de
/// colonne de description : les trois descriptions des clés ordinaires
/// (`taux_tva`, `tva_active`, `convention_prix`) restent ici, l'écran
/// Paramètres affichant l'aide du registre — comme la vue, qui ne lit pas
/// `parametres_systeme.description`.
const List<ParametreInitial> parametresEtablissementInitiaux = [
  (
    cle: 'taux_cnss_salarie',
    valeur: '3.6',
    description:
        'Cotisation CNSS part salariale, en % du brut, sans plafond. Source : '
        'cnss.bj (branche pension, 10 % dont 3,6 % salarié).',
  ),
  (
    cle: 'taux_cnss_pension_employeur',
    valeur: '6.4',
    description:
        'Cotisation CNSS pension part employeur, en % du brut. Source : '
        'cnss.bj.',
  ),
  (
    cle: 'taux_cnss_prestations_familiales',
    valeur: '9',
    description:
        'Cotisation CNSS prestations familiales, employeur uniquement, en % du '
        'brut. Source : cnss.bj.',
  ),
  (
    cle: 'taux_vps',
    valeur: '4',
    description:
        'VPS (Versement Patronal sur Salaires), en % du total des salaires '
        "bruts, SANS plafond. Taxe a la charge de l'employeur, jamais retenue "
        'sur le salaire. Declaration et paiement au plus tard le 10 du mois '
        'suivant. Source : ATELIER_PLAN_COMPTABLE.md.',
  ),
  (
    cle: 'taux_tva',
    valeur: '18.00',
    description:
        'Taux de TVA en % — fourni par le Consultant Technique le 15/08/2026. '
        'Référence au Code Général des Impôts à joindre (voir PA-36).',
  ),
  (
    cle: 'tva_active',
    valeur: 'true',
    description:
        "Assujettissement à la TVA (true/false). Inactive tant qu'un "
        "Administrateur ne l'active pas : aucune taxe n'est ajoutée aux "
        'factures.',
  ),
  (
    cle: 'convention_prix',
    valeur: 'ttc',
    description:
        'Convention des prix du catalogue : `ht` (les tarifs '
        "s'entendent hors taxe, la TVA s'ajoute) ou `ttc` (les tarifs "
        'incluent déjà la TVA, elle en est extraite). Résout PA-37 — à '
        'confirmer par le Product Owner et le Comptable.',
  ),
  (cle: 'activation_suppression', valeur: 'true', description: null),
  (cle: 'entreprise_ifu', valeur: '0202011344660', description: null),
  (cle: 'entreprise_rccm', valeur: 'RB/NAT/2020-A-137', description: null),
  (
    cle: 'entreprise_raison_sociale',
    valeur: 'TATACORA AFRIQUE Gîte Chez Noël',
    description: null,
  ),
  (cle: 'entreprise_promoteur', valeur: 'NABOGOU Noel', description: null),
  (cle: 'communication_whatsapp', valeur: '0197355974', description: null),
  (
    cle: 'entreprise_site_web',
    valeur: 'https://tatacora.com/',
    description: null,
  ),
  (
    cle: 'email_smtp_hote',
    valeur: 'mail.logirestock.digitonpro.com',
    description: null,
  ),
  (cle: 'email_smtp_port', valeur: '587', description: null),
  // Vide dans le script ; « TLS » selon la directive PO du 14/10/2026.
  (cle: 'email_smtp_securite', valeur: 'tls', description: null),
  (
    cle: 'email_smtp_utilisateur',
    valeur: 'contact@logirestock.digitonpro.com',
    description: null,
  ),
  // Vide, comme au serveur : « (vide) » à l'écran, l'exploitant choisit.
  (cle: 'fiscalite_regime', valeur: '', description: null),
  (cle: 'reinitialisation_seeders', valeur: 'true', description: null),
];
