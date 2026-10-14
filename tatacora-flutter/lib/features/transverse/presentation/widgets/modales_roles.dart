// Vue Blade maîtresse (PA-183) : pwa/transverse/roles-permissions.blade.php
/// Les trois modales de Rôles & Permissions (14/10/2026, écran complet) —
/// « Nouveau rôle » (l.169-192), « Modifier les droits » (l.194-230) et
/// « Rétablir le socle du CdCF » (l.232-244), dans le châssis partagé
/// `x-pwa.modale` ([CoquilleModaleRestaurant]).
///
/// Les modales sont HORS de `<main>` : échelle typographique DÉCLARÉE
/// ([Tailles]), jamais [TaillesContenu] (`echelle_contenu_test`, liste
/// modale).
///
/// Chaque modale ÉCRIT par le geste qu'on lui passe (`RolesDao`) ; un refus
/// s'affiche sous le champ fautif, la saisie reste là. Elle se ferme sur
/// `true` quand l'écriture a réussi.
library;

import 'package:flutter/material.dart';

import '../../../../core/navigation/trace_svg.dart';
import '../../../../core/rbac/garde_acces.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/mesures_transverses.dart';
import '../../../../shared_widgets/bouton_standard.dart';
import '../../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import '../../../restaurant/presentation/widgets/textes_modale_restaurant.dart';
import '../../data/roles_dao.dart';
import '../../domain/roles_du_poste.dart';

/// Les textes des modales (`pwa.roles.*`, `pwa.modale.*`,
/// `notifications_pwa.enregistrer`), au mot.
abstract final class TextesModalesRoles {
  static const String nouveauRoleTitre = 'Nouveau rôle';
  static const String libelle = 'Libellé';
  static const String libelleInvite = 'ex. veilleur_nuit';
  static const String description = 'Description';
  static String modifierDroitsTitre(String role) =>
      'Modifier les droits — $role';
  static const String modifierDroitsSousTitre =
      'C = accès complet, L = lecture seule, — = aucun accès.';
  static const String verrouAdministrateur =
      "Verrouillé : un administrateur ne peut pas se retirer l'accès à "
      '« Rôles & Permissions ».';
  static const String toutRetirer = 'Tout retirer';
  static const String retablirTitre = 'Rétablir le socle du CdCF';
  static const String retablirTexte =
      'Chaque rôle du socle (onze rôles métier) retrouvera exactement la '
      'matrice du CdCF. Tout amendement que vous ou un autre administrateur '
      'avez apporté à CES rôles sera perdu. Les rôles que vous avez créés '
      'depuis cet écran ne sont pas concernés.';
  static const String retablirConfirmer = 'Rétablir';
  static const String annuler = 'Annuler';
  static const String enregistrer = 'Enregistrer';

  /// L'option `-` du `<select>` s'AFFICHE « — » (`<option value="-">—`).
  static const String tiret = '—';
}

/// Le cadenas de la case administrateur / Rôles (l.204), tracé de la vue.
const String _cadenas =
    '<rect x="3" y="11" width="18" height="11" rx="2"/>'
    '<path stroke-linecap="round" d="M7 11V7a5 5 0 0110 0v4"/>';

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

/// `w-full text-[13px] border border-slate-300 rounded-lg px-3 py-2.5`.
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

/// Les deux boutons de pied communs : « Annuler » (`px-4`) puis l'action.
List<Widget> _pied(
  BuildContext context, {
  required String cleAnnuler,
  required Widget action,
  required bool enCours,
}) => [
  BoutonStandard(
    key: Key(cleAnnuler),
    libelle: TextesModalesRoles.annuler,
    taillePolice: Tailles.t13,
    margeHorizontale: AppSpacing.md,
    onPressed: enCours ? null : () => Navigator.of(context).pop(),
  ),
  action,
];

// ------------------------------------------------------------ NOUVEAU RÔLE

/// Ouvre « Nouveau rôle ». [enregistrer] écrit (et lève [RefusRoles]).
Future<bool?> ouvrirModaleNouveauRole(
  BuildContext context, {
  required Future<void> Function(String libelle, String? description)
  enregistrer,
}) => showDialog<bool>(
  context: context,
  builder: (_) => _ModaleNouveauRole(enregistrer: enregistrer),
);

class _ModaleNouveauRole extends StatefulWidget {
  const _ModaleNouveauRole({required this.enregistrer});

  final Future<void> Function(String libelle, String? description) enregistrer;

  @override
  State<_ModaleNouveauRole> createState() => _ModaleNouveauRoleState();
}

class _ModaleNouveauRoleState extends State<_ModaleNouveauRole> {
  final _libelle = TextEditingController();
  final _description = TextEditingController();
  Map<String, String> _erreurs = const {};
  bool _enCours = false;

  @override
  void dispose() {
    _libelle.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    setState(() {
      _enCours = true;
      _erreurs = const {};
    });
    try {
      await widget.enregistrer(
        _libelle.text,
        _description.text.isEmpty ? null : _description.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on RefusRoles catch (refus) {
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
    // Un refus de droit n'a pas de champ : il s'affiche en tête de modale.
    final refusDroit = _erreurs['droit'];
    return CoquilleModaleRestaurant(
      cle: const Key('roles-modale-nouveau'),
      titre: TextesModalesRoles.nouveauRoleTitre,
      largeur: MesuresTransverses.modaleRole,
      refus: refusDroit,
      cleRefus: const Key('roles-modale-refus'),
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const EtiquetteChampRestaurant(
            texte: TextesModalesRoles.libelle,
            obligatoire: true,
          ),
          TextField(
            key: const Key('roles-saisie-libelle'),
            controller: _libelle,
            style: _saisie,
            decoration: _decoration(invite: TextesModalesRoles.libelleInvite),
          ),
          if (_erreurs['libelle'] != null) ...[
            const SizedBox(height: AppSpacing.unit),
            Text(
              _erreurs['libelle']!,
              key: const Key('roles-erreur-libelle'),
              style: _erreur,
            ),
          ],
          const SizedBox(height: AppSpacing.md), // space-y-4
          const EtiquetteChampRestaurant(texte: TextesModalesRoles.description),
          TextField(
            key: const Key('roles-saisie-description'),
            controller: _description,
            style: _saisie,
            decoration: _decoration(),
          ),
          if (_erreurs['description'] != null) ...[
            const SizedBox(height: AppSpacing.unit),
            Text(
              _erreurs['description']!,
              key: const Key('roles-erreur-description'),
              style: _erreur,
            ),
          ],
        ],
      ),
      actions: _pied(
        context,
        cleAnnuler: 'roles-modale-annuler',
        enCours: _enCours,
        action: BoutonStandard(
          key: const Key('roles-nouveau-enregistrer'),
          libelle: TextesModalesRoles.enregistrer,
          variante: VarianteBouton.primaire,
          taillePolice: Tailles.t13,
          onPressed: _enCours ? null : _valider,
        ),
      ),
    );
  }
}

// ------------------------------------------------------ MODIFIER LES DROITS

/// Ouvre « Modifier les droits » sur [role]. [enregistrer] écrit (et lève
/// [RefusRoles]).
Future<bool?> ouvrirModaleDroits(
  BuildContext context, {
  required RoleDuPoste role,
  required Future<void> Function(Map<ModuleTatacora, NiveauAcces> niveaux)
  enregistrer,
}) => showDialog<bool>(
  context: context,
  builder: (_) => _ModaleDroits(role: role, enregistrer: enregistrer),
);

class _ModaleDroits extends StatefulWidget {
  const _ModaleDroits({required this.role, required this.enregistrer});

  final RoleDuPoste role;
  final Future<void> Function(Map<ModuleTatacora, NiveauAcces> niveaux)
  enregistrer;

  @override
  State<_ModaleDroits> createState() => _ModaleDroitsState();
}

class _ModaleDroitsState extends State<_ModaleDroits> {
  /// `ouvrirFormulaireDroits()` : le niveau courant de chaque module.
  late final Map<ModuleTatacora, NiveauAcces> _niveaux = {
    for (final m in libellesModulesMatrice.keys)
      m: widget.role.droits.niveau(m),
  };
  String? _refus;
  bool _enCours = false;

  /// La case verrouillée de la vue (l.202) : administrateur / Rôles.
  bool _verrouille(ModuleTatacora m) =>
      m == ModuleTatacora.roles && widget.role.libelle == 'administrateur';

  /// `toutRetirer()` : `-` partout DANS LA SAISIE, verrou excepté. Rien
  /// n'est enregistré avant « Enregistrer ».
  void _toutRetirer() => setState(() {
    for (final m in libellesModulesMatrice.keys) {
      if (_verrouille(m)) continue;
      _niveaux[m] = NiveauAcces.aucun;
    }
  });

  Future<void> _valider() async {
    setState(() {
      _enCours = true;
      _refus = null;
    });
    try {
      await widget.enregistrer(Map.of(_niveaux));
      if (mounted) Navigator.of(context).pop(true);
    } on RefusRoles catch (refus) {
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
    final hauteur =
        MediaQuery.sizeOf(context).height *
        MesuresTransverses.fractionListeDroits;
    final libelleModule = TextesModaleRestaurant.etiquette.copyWith(
      fontWeight: FontWeight.w400,
    );
    return CoquilleModaleRestaurant(
      cle: const Key('roles-modale-droits'),
      titre: TextesModalesRoles.modifierDroitsTitre(
        libelleRole(widget.role.libelle),
      ),
      sousTitre: TextesModalesRoles.modifierDroitsSousTitre,
      largeur: MesuresTransverses.modaleDroits,
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: hauteur),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (i, m) in libellesModulesMatrice.keys.indexed)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        border: i == 0
                            ? null
                            : const Border(
                                top: BorderSide(color: Ardoise.c100),
                              ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              libellesModulesMatrice[m]!,
                              style: libelleModule,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm), // gap-3
                          if (_verrouille(m))
                            Tooltip(
                              message: TextesModalesRoles.verrouAdministrateur,
                              child: Row(
                                key: const Key('roles-verrou-administrateur'),
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const IconeTrace(
                                    trace: _cadenas,
                                    taille: MesuresTransverses.iconeVerrou,
                                    couleur: Ardoise.c400,
                                  ),
                                  const SizedBox(width: AppSpacing.xxs),
                                  Text(
                                    NiveauAcces.complet.code,
                                    style: const TextStyle(
                                      fontFamily: AppTextStyles.police,
                                      fontSize: Tailles.t12,
                                      color: Ardoise.c400,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            _ChoixNiveau(
                              cle: Key('roles-niveau-${m.code}'),
                              valeur: _niveaux[m]!,
                              onChoix: (n) => setState(() => _niveaux[m] = n),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_refus != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              _refus!,
              key: const Key('roles-erreur-niveaux'),
              style: _erreur,
            ),
          ],
        ],
      ),
      actions: [
        // `mr-auto` : « Tout retirer » se tient à gauche du pied.
        BoutonStandard(
          key: const Key('roles-tout-retirer'),
          libelle: TextesModalesRoles.toutRetirer,
          variante: VarianteBouton.contourRouge,
          taillePolice: Tailles.t13,
          onPressed: _enCours ? null : _toutRetirer,
        ),
        ..._pied(
          context,
          cleAnnuler: 'roles-modale-annuler',
          enCours: _enCours,
          action: BoutonStandard(
            key: const Key('roles-droits-enregistrer'),
            libelle: TextesModalesRoles.enregistrer,
            variante: VarianteBouton.primaire,
            taillePolice: Tailles.t13,
            onPressed: _enCours ? null : _valider,
          ),
        ),
      ],
    );
  }
}

/// `<select class="text-[13px] border border-slate-300 rounded-lg px-2.5
/// py-1.5">` : C, L, — .
class _ChoixNiveau extends StatelessWidget {
  const _ChoixNiveau({
    required Key cle,
    required this.valeur,
    required this.onChoix,
  }) : super(key: cle);

  final NiveauAcces valeur;
  final ValueChanged<NiveauAcces> onChoix;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.xsPlus,
      vertical: AppSpacing.xxs,
    ),
    decoration: BoxDecoration(
      border: Border.all(color: Ardoise.c300),
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
    ),
    child: DropdownButton<NiveauAcces>(
      value: valeur,
      isDense: true,
      underline: const SizedBox.shrink(),
      style: _saisie,
      items: [
        for (final n in NiveauAcces.values)
          DropdownMenuItem(
            value: n,
            child: Text(
              n == NiveauAcces.aucun ? TextesModalesRoles.tiret : n.code,
            ),
          ),
      ],
      onChanged: (n) {
        if (n != null) onChoix(n);
      },
    ),
  );
}

// ------------------------------------------------------ RÉTABLIR LE SOCLE

/// Ouvre la confirmation « Rétablir le socle du CdCF ». [retablir] écrit (et
/// lève [RefusRoles]) ; la modale se ferme sur le nombre de rôles rétablis.
Future<int?> ouvrirModaleRetablirSocle(
  BuildContext context, {
  required Future<int> Function() retablir,
}) => showDialog<int>(
  context: context,
  builder: (_) => _ModaleRetablir(retablir: retablir),
);

class _ModaleRetablir extends StatefulWidget {
  const _ModaleRetablir({required this.retablir});

  final Future<int> Function() retablir;

  @override
  State<_ModaleRetablir> createState() => _ModaleRetablirState();
}

class _ModaleRetablirState extends State<_ModaleRetablir> {
  String? _refus;
  bool _enCours = false;

  Future<void> _confirmer() async {
    setState(() {
      _enCours = true;
      _refus = null;
    });
    try {
      final nombre = await widget.retablir();
      if (mounted) Navigator.of(context).pop(nombre);
    } on RefusRoles catch (refus) {
      if (mounted) {
        setState(() {
          _enCours = false;
          _refus = refus.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => CoquilleModaleRestaurant(
    cle: const Key('roles-modale-socle'),
    titre: TextesModalesRoles.retablirTitre,
    largeur: MesuresTransverses.modaleRole,
    refus: _refus,
    cleRefus: const Key('roles-modale-refus'),
    corps: Text(
      TextesModalesRoles.retablirTexte,
      // `text-sm text-slate-600`.
      style: TextesModaleRestaurant.corps.copyWith(color: Ardoise.c600),
    ),
    actions: _pied(
      context,
      cleAnnuler: 'roles-modale-annuler',
      enCours: _enCours,
      action: BoutonStandard(
        key: const Key('roles-socle-confirmer'),
        libelle: TextesModalesRoles.retablirConfirmer,
        variante: VarianteBouton.erreur,
        taillePolice: Tailles.t13,
        onPressed: _enCours ? null : _confirmer,
      ),
    ),
  );
}
