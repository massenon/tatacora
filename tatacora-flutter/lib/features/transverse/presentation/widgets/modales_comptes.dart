/// Les modales de « Comptes utilisateurs » (Lot J2, 14/10/2026) — « Nouveau
/// compte », « Réinitialiser le mot de passe » et la confirmation de
/// désactivation, dans le châssis partagé des modales
/// ([CoquilleModaleRestaurant]) et aux mesures des modales de « Rôles &
/// Permissions » (saisie, étiquettes, pied « Annuler » puis l'action).
///
/// AJOUT du poste : aucune vue n'a ces modales. Elles sont HORS de `<main>` :
/// échelle typographique DÉCLARÉE ([Tailles]).
///
/// Chaque modale ÉCRIT par le geste qu'on lui passe (`ComptesUtilisateursDao`)
/// ; un refus s'affiche sous le champ fautif, la saisie reste là. Elle se
/// ferme sur `true` quand l'écriture a réussi.
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/mesures_transverses.dart';
import '../../../../shared_widgets/bouton_standard.dart';
import '../../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import '../../domain/comptes_utilisateurs.dart';
import '../../domain/roles_du_poste.dart';

/// Les textes des modales.
abstract final class TextesModalesComptes {
  static const String nouveauCompteTitre = 'Nouveau compte';
  static const String nomComplet = 'Nom complet';
  static const String nomInvite = 'ex. NABOGOU Winribasse Noël';
  static const String identifiant = 'Identifiant';
  static const String identifiantInvite = 'ex. n.nabogou';
  static const String identifiantAide =
      'Minuscules sans accent, chiffres, point, tiret ou souligné — de 3 à 50 '
      'caractères. Il sert à la connexion et ne se modifie plus ensuite.';
  static const String role = 'Rôle';
  static const String roleInvite = 'Choisir un rôle';
  static const String motDePasse = 'Mot de passe';
  static const String nouveauMotDePasse = 'Nouveau mot de passe';
  static const String motDePasseInvite = '8 caractères au minimum';
  static const String confirmation = 'Confirmer le mot de passe';
  static const String confirmationInvite = "à l'identique";
  static const String noteMotDePasse =
      "Ce mot de passe n'est enregistré nulle part en clair et ne peut pas "
      'être récupéré. Transmettez-le à son titulaire.';
  static String reinitialiserTitre(String identifiant) =>
      'Réinitialiser le mot de passe — $identifiant';
  static const String reinitialiserSousTitre =
      'Le titulaire se connectera avec ce nouveau mot de passe ; il pourra le '
      'changer depuis « Mon profil ».';
  static String desactiverTitre(String identifiant) =>
      'Désactiver le compte — $identifiant';
  static const String desactiverTexte =
      'Le compte ne pourra plus se connecter. Il reste en base, avec tout ce '
      "qu'il a saisi (traçabilité), et peut être réactivé à tout moment.";
  static const String desactiver = 'Désactiver';
  static const String annuler = 'Annuler';
  static const String enregistrer = 'Enregistrer';
  static const String creer = 'Créer le compte';
}

const TextStyle _erreur = TextStyle(
  fontFamily: AppTextStyles.police,
  fontSize: Tailles.t12,
  color: PaletteMaitre.rouge600,
);

const TextStyle _saisie = TextStyle(
  fontFamily: AppTextStyles.police,
  fontSize: Tailles.t13,
  color: Ardoise.c800,
);

const TextStyle _aide = TextStyle(
  fontFamily: AppTextStyles.police,
  fontSize: Tailles.t12,
  color: Ardoise.c500,
);

/// La saisie des modales de « Rôles & Permissions » : `w-full text-[13px]
/// border border-slate-300 rounded-lg px-3 py-2.5`.
InputDecoration _decoration({String? invite}) {
  final bord = OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.roundedLg),
    borderSide: const BorderSide(color: Ardoise.c300),
  );
  return InputDecoration(
    hintText: invite,
    hintStyle: _saisie.copyWith(color: Ardoise.c400),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.xsPlus,
    ),
    border: bord,
    enabledBorder: bord,
  );
}

List<Widget> _pied(
  BuildContext context, {
  required String cleAnnuler,
  required Widget action,
  required bool enCours,
}) => [
  BoutonStandard(
    key: Key(cleAnnuler),
    libelle: TextesModalesComptes.annuler,
    taillePolice: Tailles.t13,
    margeHorizontale: AppSpacing.md,
    onPressed: enCours ? null : () => Navigator.of(context).pop(),
  ),
  action,
];

/// Un champ de saisie, son étiquette et son erreur.
List<Widget> _champ({
  required String cle,
  required String etiquette,
  required TextEditingController controleur,
  required String? erreur,
  String? invite,
  String? aide,
  bool masque = false,
  bool obligatoire = true,
}) => [
  EtiquetteChampRestaurant(texte: etiquette, obligatoire: obligatoire),
  TextField(
    key: Key('comptes-saisie-$cle'),
    controller: controleur,
    obscureText: masque,
    style: _saisie,
    decoration: _decoration(invite: invite),
  ),
  if (aide != null) ...[
    const SizedBox(height: AppSpacing.unit),
    Text(aide, style: _aide),
  ],
  if (erreur != null) ...[
    const SizedBox(height: AppSpacing.unit),
    Text(erreur, key: Key('comptes-erreur-$cle'), style: _erreur),
  ],
];

/// La saisie de « Nouveau compte ».
typedef SaisieCompte = ({
  String nom,
  String identifiant,
  String? role,
  String motDePasse,
  String confirmation,
});

// ---------------------------------------------------------- NOUVEAU COMPTE

/// Ouvre « Nouveau compte ». [enregistrer] écrit (et lève [RefusComptes]).
Future<bool?> ouvrirModaleNouveauCompte(
  BuildContext context, {
  required List<RoleDuPoste> roles,
  required Future<void> Function(SaisieCompte saisie) enregistrer,
}) => showDialog<bool>(
  context: context,
  builder: (_) => _ModaleNouveauCompte(roles: roles, enregistrer: enregistrer),
);

class _ModaleNouveauCompte extends StatefulWidget {
  const _ModaleNouveauCompte({required this.roles, required this.enregistrer});

  final List<RoleDuPoste> roles;
  final Future<void> Function(SaisieCompte saisie) enregistrer;

  @override
  State<_ModaleNouveauCompte> createState() => _ModaleNouveauCompteState();
}

class _ModaleNouveauCompteState extends State<_ModaleNouveauCompte> {
  final _nom = TextEditingController();
  final _identifiant = TextEditingController();
  final _motDePasse = TextEditingController();
  final _confirmation = TextEditingController();
  String? _role;
  Map<String, String> _erreurs = const {};
  bool _enCours = false;

  @override
  void dispose() {
    _nom.dispose();
    _identifiant.dispose();
    _motDePasse.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    setState(() {
      _enCours = true;
      _erreurs = const {};
    });
    try {
      await widget.enregistrer((
        nom: _nom.text,
        identifiant: _identifiant.text,
        role: _role,
        motDePasse: _motDePasse.text,
        confirmation: _confirmation.text,
      ));
      if (mounted) Navigator.of(context).pop(true);
    } on RefusComptes catch (refus) {
      if (mounted) {
        setState(() {
          _enCours = false;
          _erreurs = refus.erreurs;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CoquilleModaleRestaurant(
      cle: const Key('comptes-modale-nouveau'),
      titre: TextesModalesComptes.nouveauCompteTitre,
      largeur: MesuresTransverses.modaleCompte,
      refus: _erreurs['droit'],
      cleRefus: const Key('comptes-modale-refus'),
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ..._champ(
            cle: 'nom',
            etiquette: TextesModalesComptes.nomComplet,
            controleur: _nom,
            invite: TextesModalesComptes.nomInvite,
            erreur: _erreurs['nom'],
          ),
          const SizedBox(height: AppSpacing.md),
          ..._champ(
            cle: 'identifiant',
            etiquette: TextesModalesComptes.identifiant,
            controleur: _identifiant,
            invite: TextesModalesComptes.identifiantInvite,
            aide: TextesModalesComptes.identifiantAide,
            erreur: _erreurs['identifiant'],
          ),
          const SizedBox(height: AppSpacing.md),
          const EtiquetteChampRestaurant(
            texte: TextesModalesComptes.role,
            obligatoire: true,
          ),
          DropdownButtonFormField<String>(
            key: const Key('comptes-saisie-role'),
            initialValue: _role,
            isExpanded: true,
            style: _saisie,
            hint: Text(
              TextesModalesComptes.roleInvite,
              style: _saisie.copyWith(color: Ardoise.c400),
            ),
            decoration: _decoration(),
            items: [
              for (final r in widget.roles)
                DropdownMenuItem(
                  value: r.libelle,
                  child: Text(libelleRole(r.libelle)),
                ),
            ],
            onChanged: _enCours ? null : (v) => setState(() => _role = v),
          ),
          if (_erreurs['role'] != null) ...[
            const SizedBox(height: AppSpacing.unit),
            Text(
              _erreurs['role']!,
              key: const Key('comptes-erreur-role'),
              style: _erreur,
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          ..._champ(
            cle: 'mot-de-passe',
            etiquette: TextesModalesComptes.motDePasse,
            controleur: _motDePasse,
            invite: TextesModalesComptes.motDePasseInvite,
            masque: true,
            erreur: _erreurs['motDePasse'],
          ),
          const SizedBox(height: AppSpacing.md),
          ..._champ(
            cle: 'confirmation',
            etiquette: TextesModalesComptes.confirmation,
            controleur: _confirmation,
            invite: TextesModalesComptes.confirmationInvite,
            masque: true,
            erreur: _erreurs['confirmation'],
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(TextesModalesComptes.noteMotDePasse, style: _aide),
        ],
      ),
      actions: _pied(
        context,
        cleAnnuler: 'comptes-modale-annuler',
        enCours: _enCours,
        action: BoutonStandard(
          key: const Key('comptes-nouveau-enregistrer'),
          libelle: TextesModalesComptes.creer,
          variante: VarianteBouton.primaire,
          taillePolice: Tailles.t13,
          onPressed: _enCours ? null : _valider,
        ),
      ),
    );
  }
}

// ------------------------------------------ RÉINITIALISER LE MOT DE PASSE

/// Ouvre « Réinitialiser le mot de passe » sur [compte]. [enregistrer] écrit
/// (et lève [RefusComptes]).
Future<bool?> ouvrirModaleReinitialiserMotDePasse(
  BuildContext context, {
  required CompteUtilisateur compte,
  required Future<void> Function(String nouveau, String confirmation)
  enregistrer,
}) => showDialog<bool>(
  context: context,
  builder: (_) =>
      _ModaleReinitialiser(compte: compte, enregistrer: enregistrer),
);

class _ModaleReinitialiser extends StatefulWidget {
  const _ModaleReinitialiser({required this.compte, required this.enregistrer});

  final CompteUtilisateur compte;
  final Future<void> Function(String nouveau, String confirmation) enregistrer;

  @override
  State<_ModaleReinitialiser> createState() => _ModaleReinitialiserState();
}

class _ModaleReinitialiserState extends State<_ModaleReinitialiser> {
  final _motDePasse = TextEditingController();
  final _confirmation = TextEditingController();
  Map<String, String> _erreurs = const {};
  bool _enCours = false;

  @override
  void dispose() {
    _motDePasse.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    setState(() {
      _enCours = true;
      _erreurs = const {};
    });
    try {
      await widget.enregistrer(_motDePasse.text, _confirmation.text);
      if (mounted) Navigator.of(context).pop(true);
    } on RefusComptes catch (refus) {
      if (mounted) {
        setState(() {
          _enCours = false;
          _erreurs = refus.erreurs;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CoquilleModaleRestaurant(
      cle: const Key('comptes-modale-mot-de-passe'),
      titre: TextesModalesComptes.reinitialiserTitre(widget.compte.identifiant),
      sousTitre: TextesModalesComptes.reinitialiserSousTitre,
      largeur: MesuresTransverses.modaleCompte,
      refus: _erreurs['droit'] ?? _erreurs['compte'],
      cleRefus: const Key('comptes-modale-refus'),
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ..._champ(
            cle: 'mot-de-passe',
            etiquette: TextesModalesComptes.nouveauMotDePasse,
            controleur: _motDePasse,
            invite: TextesModalesComptes.motDePasseInvite,
            masque: true,
            erreur: _erreurs['motDePasse'],
          ),
          const SizedBox(height: AppSpacing.md),
          ..._champ(
            cle: 'confirmation',
            etiquette: TextesModalesComptes.confirmation,
            controleur: _confirmation,
            invite: TextesModalesComptes.confirmationInvite,
            masque: true,
            erreur: _erreurs['confirmation'],
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(TextesModalesComptes.noteMotDePasse, style: _aide),
        ],
      ),
      actions: _pied(
        context,
        cleAnnuler: 'comptes-modale-annuler',
        enCours: _enCours,
        action: BoutonStandard(
          key: const Key('comptes-mot-de-passe-enregistrer'),
          libelle: TextesModalesComptes.enregistrer,
          variante: VarianteBouton.primaire,
          taillePolice: Tailles.t13,
          onPressed: _enCours ? null : _valider,
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ DÉSACTIVER

/// Confirme la désactivation de [compte]. [desactiver] écrit (et lève
/// [RefusComptes], affiché dans la modale).
Future<bool?> ouvrirModaleDesactiver(
  BuildContext context, {
  required CompteUtilisateur compte,
  required Future<void> Function() desactiver,
}) => showDialog<bool>(
  context: context,
  builder: (_) => _ModaleDesactiver(compte: compte, desactiver: desactiver),
);

class _ModaleDesactiver extends StatefulWidget {
  const _ModaleDesactiver({required this.compte, required this.desactiver});

  final CompteUtilisateur compte;
  final Future<void> Function() desactiver;

  @override
  State<_ModaleDesactiver> createState() => _ModaleDesactiverState();
}

class _ModaleDesactiverState extends State<_ModaleDesactiver> {
  String? _refus;
  bool _enCours = false;

  Future<void> _valider() async {
    setState(() {
      _enCours = true;
      _refus = null;
    });
    try {
      await widget.desactiver();
      if (mounted) Navigator.of(context).pop(true);
    } on RefusComptes catch (refus) {
      if (mounted) {
        setState(() {
          _enCours = false;
          _refus = refus.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CoquilleModaleRestaurant(
      cle: const Key('comptes-modale-desactiver'),
      titre: TextesModalesComptes.desactiverTitre(widget.compte.identifiant),
      largeur: MesuresTransverses.modaleCompte,
      refus: _refus,
      cleRefus: const Key('comptes-modale-refus'),
      corps: const Text(
        TextesModalesComptes.desactiverTexte,
        style: TextStyle(
          fontFamily: AppTextStyles.police,
          fontSize: Tailles.t13,
          color: Ardoise.c600,
        ),
      ),
      actions: _pied(
        context,
        cleAnnuler: 'comptes-modale-annuler',
        enCours: _enCours,
        action: BoutonStandard(
          key: const Key('comptes-desactiver-confirmer'),
          libelle: TextesModalesComptes.desactiver,
          variante: VarianteBouton.erreur,
          taillePolice: Tailles.t13,
          onPressed: _enCours ? null : _valider,
        ),
      ),
    );
  }
}
