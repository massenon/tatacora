// Vue Blade maîtresse (PA-183) : pwa/comptabilite/correspondance-comptes.blade.php
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/navigation/coquille_vue.dart';
import '../../../core/rbac/garde_acces.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/mesures_transverses.dart';
import '../../../shared_widgets/bouton_standard.dart';
import '../../parametres/domain/registre_parametres_local.dart';
import '../../parametres/domain/resultats_parametres.dart';
import '../../parametres/presentation/ecran_parametres.dart'
    show enregistrerParametresProvider;
import '../../transverse/presentation/widgets/briques_transverses.dart';
import '../domain/correspondance_comptes.dart';
import '../domain/regle_numero_compte.dart';
import 'providers_correspondance.dart';
import 'widgets/modales_hub_comptabilite.dart';

/// L'écran **Correspondance des comptes** — le compte que chaque pièce
/// automatique utilise pour chaque rôle (produits par module, TVA,
/// trésoreries, tiers, résultat), MODIFIABLE sur le poste comme sur le web
/// (décision du PO du 26/10/2026 : « on peut impérativement modifier les
/// comptes sur poste et le web »).
///
/// Écran AJOUTÉ par le PO, absent du maître ; la vue Blade qui le porte est
/// `correspondance-comptes.blade.php`, dont ce fichier est la TRADUCTION : mêmes
/// groupes, mêmes colonnes, mêmes phrases (relues de
/// `lang/fr/comptes_correspondance.php` par `MessagesCorrespondance`).
///
/// ## Ce que « modifier » fait
///
/// UN paramètre (`compte_<rôle>`) écrit par le seul `EnregistrerParametres` :
/// registre fermé, validation contre le plan de ce poste (format, existence,
/// classe cohérente avec le rôle, compte imputable — les phrases du serveur),
/// puis un enregistrement part au serveur par la file d'envoi (dernier écrit
/// gagnant, clé par clé) ; le Journal d'Audit de ce poste, qui relit cette
/// file, en garde la trace. Le moteur comptable lit la correspondance AU
/// MOMENT de passer chaque pièce : un changement vaut pour les pièces futures,
/// une pièce déjà passée n'est JAMAIS réécrite (RG-11) — l'écran le DIT.
///
/// ## Écart au maître, nommé
///
/// Trois rôles n'ont AUCUN lecteur sur ce poste : la TVA récupérable sur achats
/// et les deux comptes de résultat sont lus par la déclaration de TVA et la
/// clôture de l'exercice, qui sont au serveur. Leur ligne porte une phrase de
/// plus que la vue (`TextesCorrespondancePoste.serveurSeul`) : sans elle,
/// l'écran laisserait croire qu'une pièce de ce poste les utilise.
///
/// Droit : lecture M10 pour voir l'écran, écriture M10 pour modifier — la route
/// de la vue exige `M10,L`, `exigerEcriture(M10)` garde chaque geste.
class EcranCorrespondanceComptes extends ConsumerWidget {
  const EcranCorrespondanceComptes({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final droits = ref.watch(droitsProvider);
    if (!droits.peutLire(ModuleTatacora.m10Comptabilite)) {
      return const RefusDroitTransverse(message: LibellesCoquille.sansDroit);
    }
    final peutEcrire = droits.peutEcrire(ModuleTatacora.m10Comptabilite);
    final lu = ref.watch(correspondanceComptesProvider);

    return PageTransverse(
      largeurMax: MesuresTransverses.pageComptabilite,
      enfants: [
        const _LienRetour(),
        EnTeteTransverse(
          trace: IconeCorrespondanceComptes.trace,
          titre: MessagesCorrespondance.dire('titre'),
          sousTitre: MessagesCorrespondance.dire('sous_titre'),
          margeBas: AppSpacing.mdPlus,
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md), // mb-4
          child: EncadreTransverse(
            key: const Key('correspondance-avertissement'),
            fond: PaletteMaitre.ambre50,
            bordure: PaletteMaitre.ambre200,
            padding: const EdgeInsets.all(AppSpacing.smPlus),
            child: Text(
              MessagesCorrespondance.dire('avertissement'),
              style: styleTransverse(
                TaillesContenu.t13,
                couleur: PaletteMaitre.ambre900,
              ),
            ),
          ),
        ),
        if (!peutEcrire)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Text(
              MessagesCorrespondance.dire('lecture_seule'),
              key: const Key('correspondance-lecture-seule'),
              style: styleTransverse(TaillesContenu.t13, couleur: Ardoise.c500),
            ),
          ),
        if (lu.hasError)
          Text(
            TextesCorrespondancePoste.illisible,
            key: const Key('correspondance-illisible'),
            style: styleTransverse(
              TaillesContenu.t13,
              couleur: AppColors.erreur,
            ),
          ),
        if (lu.hasValue)
          for (final groupe in RolesCorrespondance.groupes)
            _Groupe(
              groupe: groupe,
              lignes: [
                for (final l in lu.value!)
                  if (l.role.groupe == groupe) l,
              ],
              peutEcrire: peutEcrire,
            ),
      ],
    );
  }
}

/// Les mots de la MODALE de la vue (`etatFormulaire === 'role'`), écrits ICI en
/// littéraux : le comparateur Blade cherche les libellés d'une modale dans les
/// seuls fichiers qui portent la vue. `correspondance_comptes_contre_serveur_test`
/// exige qu'ils soient ceux de `lang/fr/comptes_correspondance.php` — une copie
/// qui dériverait ferait rougir ce test, pas l'écran en silence.
abstract final class TextesModaleCorrespondance {
  static const String titre = 'Modifier le compte du rôle';
  static const String champCompte = 'Numéro de compte';
  static const String champCompteAide =
      'De deux à quatre chiffres, un compte du plan comptable.';

  /// Suivi de ce que le rôle attend, puis d'un point (`Numéro attendu : :attendu.`).
  static const String roleAttendu = 'Numéro attendu : ';

  /// Suivi du compte par défaut, puis d'un point (`Compte par défaut : :defaut.`).
  static const String defautRappel = 'Compte par défaut : ';
  static const String annuler = 'Annuler';
  static const String retablir = 'Rétablir le défaut';
  static const String enregistrer = 'Enregistrer';
}

/// Les phrases de ce poste que la vue ne porte pas.
abstract final class TextesCorrespondancePoste {
  static const String retourHub = 'Retour au Hub Comptabilité';

  /// Les trois rôles que le serveur seul lit (voir l'écart de l'écran).
  static const String serveurSeul =
      'Ce poste ne passe aucune pièce sur ce rôle : il est lu par le serveur '
      '(déclaration de TVA, clôture de l’exercice).';

  static const String illisible =
      'La correspondance des comptes de ce poste n’a pas pu être lue.';
}

/// Le tracé de l'icône du titre (`correspondance-comptes.blade.php`).
abstract final class IconeCorrespondanceComptes {
  static const String trace =
      r'<path stroke-linecap="round" stroke-linejoin="round" d="M4 7h16M4 12h16M4 17h10"/>';
}

/// `<a href="{{ route('pwa.comptabilite.hub') }}">` — le lien de retour doré de
/// l'en-tête des écrans M10 (`partials/en-tete.blade.php`).
class _LienRetour extends StatelessWidget {
  const _LienRetour();

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm), // mb-3
      child: InkWell(
        key: const Key('correspondance-retour'),
        onTap: () => context.go('/comptabilite'),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.arrow_back, size: 14, color: AppColors.gold),
            const SizedBox(width: AppSpacing.xxs),
            Text(
              TextesCorrespondancePoste.retourHub,
              style: styleTransverse(
                TaillesContenu.t15,
                poids: FontWeight.w600,
                couleur: AppColors.gold,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Une carte par groupe : son titre, puis un tableau Rôle / Compte actuel / Par
/// défaut / Action.
class _Groupe extends ConsumerWidget {
  const _Groupe({
    required this.groupe,
    required this.lignes,
    required this.peutEcrire,
  });

  final String groupe;
  final List<LigneCorrespondance> lignes;
  final bool peutEcrire;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (lignes.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md), // mb-4
      child: CarteTransverse(
        key: Key('correspondance-groupe-$groupe'),
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Ardoise.c200)),
              ),
              child: Text(
                MessagesCorrespondance.dire('groupe_$groupe'),
                style: styleTransverse(
                  TaillesContenu.t14,
                  poids: FontWeight.bold,
                  couleur: AppColors.navy,
                ),
              ),
            ),
            TableauTransverse(
              colonnes: [
                (
                  titre: MessagesCorrespondance.dire('colonne_role'),
                  alignement: TextAlign.left,
                ),
                (
                  titre: MessagesCorrespondance.dire('colonne_compte'),
                  alignement: TextAlign.left,
                ),
                (
                  titre: MessagesCorrespondance.dire('colonne_defaut'),
                  alignement: TextAlign.left,
                ),
                if (peutEcrire)
                  (
                    titre: MessagesCorrespondance.dire('colonne_action'),
                    alignement: TextAlign.left,
                  ),
              ],
              lignes: [
                for (final l in lignes)
                  [
                    _CelluleRole(ligne: l),
                    _CelluleCompte(ligne: l),
                    Text(
                      l.role.defaut,
                      key: Key('correspondance-defaut-${l.role.code}'),
                      style: styleTransverse(
                        TaillesContenu.t15,
                        couleur: Ardoise.c500,
                        police: AppTextStyles.policeMonospace,
                      ),
                    ),
                    if (peutEcrire)
                      BoutonTransverse(
                        cle: Key('correspondance-modifier-${l.role.code}'),
                        libelle: MessagesCorrespondance.dire('modifier'),
                        onTap: () => _ouvrirModale(context, ref, l),
                      ),
                  ],
              ],
              vide: '',
            ),
          ],
        ),
      ),
    );
  }
}

class _CelluleRole extends StatelessWidget {
  const _CelluleRole({required this.ligne});

  final LigneCorrespondance ligne;

  @override
  Widget build(BuildContext context) {
    final role = ligne.role;
    final sansLecteur =
        RegistreParametresLocal.parCle(role.cle)?.lecteur == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          role.libelle,
          style: styleTransverse(
            TaillesContenu.t14,
            poids: FontWeight.w600,
            couleur: Ardoise.c700,
          ),
        ),
        Text(
          role.aide,
          style: styleTransverse(TaillesContenu.t12, couleur: Ardoise.c400),
        ),
        if (sansLecteur)
          Text(
            TextesCorrespondancePoste.serveurSeul,
            key: Key('correspondance-serveur-seul-${role.code}'),
            style: styleTransverse(
              TaillesContenu.t12,
              couleur: PaletteMaitre.ambre700,
            ),
          ),
      ],
    );
  }
}

class _CelluleCompte extends StatelessWidget {
  const _CelluleCompte({required this.ligne});

  final LigneCorrespondance ligne;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        TextSpan(
          text: ligne.actuel,
          style: styleTransverse(
            TaillesContenu.t15,
            couleur: Ardoise.c700,
            police: AppTextStyles.policeMonospace,
          ),
        ),
        TextSpan(
          text:
              ' — ${ligne.libelleActuel ?? MessagesCorrespondance.dire('libelle_inconnu')}',
          style: styleTransverse(TaillesContenu.t14, couleur: Ardoise.c500),
        ),
        const TextSpan(text: ' '),
        TextSpan(
          text: ligne.personnalise
              ? MessagesCorrespondance.dire('etat_modifie')
              : MessagesCorrespondance.dire('etat_defaut'),
          style: styleTransverse(
            TaillesContenu.t12,
            poids: FontWeight.w600,
            couleur: ligne.personnalise ? PaletteMaitre.ambre700 : Ardoise.c600,
          ),
        ),
      ],
    ),
    key: Key('correspondance-actuel-${ligne.role.code}'),
  );
}

Future<void> _ouvrirModale(
  BuildContext context,
  WidgetRef ref,
  LigneCorrespondance ligne,
) async {
  final message = await showDialog<String>(
    context: context,
    barrierColor: AppColors.voileModale,
    builder: (_) => _ModaleRole(ligne: ligne),
  );
  if (message == null || !context.mounted) return;
  direTransverse(context, message, cle: const Key('correspondance-enregistre'));
}

/// La modale « Modifier le compte du rôle » — `etatFormulaire === 'role'`.
/// Le refus de la validation s'affiche TEL QUEL sous le champ, rien n'est écrit
/// sur un refus.
class _ModaleRole extends ConsumerStatefulWidget {
  const _ModaleRole({required this.ligne});

  final LigneCorrespondance ligne;

  @override
  ConsumerState<_ModaleRole> createState() => _ModaleRoleState();
}

class _ModaleRoleState extends ConsumerState<_ModaleRole> {
  late final TextEditingController _numero = TextEditingController(
    text: widget.ligne.actuel,
  );
  String? _erreur;
  bool _envoi = false;

  @override
  void dispose() {
    _numero.dispose();
    super.dispose();
  }

  /// [numero] vide : le rôle revient à son compte par défaut.
  Future<void> _ecrire(String numero, {required bool retablir}) async {
    final role = widget.ligne.role;
    if (!retablir && numero.isEmpty) {
      setState(
        () => _erreur = MessagesCorrespondance.dire('champ_compte_requis'),
      );
      return;
    }
    setState(() {
      _envoi = true;
      _erreur = null;
    });
    final r = await ref
        .read(enregistrerParametresProvider)
        .executer(
          {role.cle: numero},
          peutEcrire: ref
              .read(droitsProvider)
              .peutEcrire(ModuleTatacora.m10Comptabilite),
          auteurId: ref.read(sessionProvider)?.utilisateurId,
        );
    if (!mounted) return;
    switch (r) {
      case EcritureAcceptee(:final modifiees):
        ref.invalidate(correspondanceComptesProvider);
        final retenu = retablir ? role.defaut : numero;
        Navigator.of(context).pop(
          modifiees.isEmpty
              ? MessagesCorrespondance.dire('aucun_changement')
              : MessagesCorrespondance.dire(
                  retablir ? 'retabli' : 'enregistre',
                  {'numero': retenu},
                ),
        );
      case EcritureRefusee(:final motif, :final parCle):
        setState(() {
          _envoi = false;
          _erreur = parCle[role.cle] ?? motif;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = widget.ligne.role;
    final aide = styleTransverse(TaillesContenu.t11, couleur: Ardoise.c500);
    return CadreModaleComptabilite(
      cle: const Key('modale-correspondance'),
      largeur: AppLayout.modaleCompte,
      titre: TextesModaleCorrespondance.titre,
      corps: [
        Text(
          role.libelle,
          key: const Key('modale-correspondance-role'),
          style: styleTransverse(
            TaillesContenu.t13,
            poids: FontWeight.w600,
            couleur: Ardoise.c700,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        ChampModaleComptabilite(
          libelle: TextesModaleCorrespondance.champCompte,
          child: TextField(
            key: const Key('modale-correspondance-numero'),
            controller: _numero,
            enabled: !_envoi,
            maxLength: RegleNumeroCompte.chiffresMax,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: styleTransverse(
              TaillesContenu.t13,
              police: AppTextStyles.policeMonospace,
            ),
            decoration: decorationModaleComptabilite(invite: role.defaut),
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(TextesModaleCorrespondance.champCompteAide, style: aide),
        Text(
          '${TextesModaleCorrespondance.roleAttendu}'
          '${RolesCorrespondance.attendu(role.prefixes)}.',
          style: aide,
        ),
        Text(
          '${TextesModaleCorrespondance.defautRappel}${role.defaut}.',
          style: aide,
        ),
        if (_erreur != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxs),
            child: Text(
              _erreur!,
              key: const Key('modale-correspondance-refus'),
              style: styleTransverse(
                TaillesContenu.t11,
                couleur: AppColors.erreur,
              ),
            ),
          ),
      ],
      pied: [
        BoutonStandard(
          key: const Key('modale-correspondance-annuler'),
          libelle: TextesModaleCorrespondance.annuler,
          variante: VarianteBouton.fantome,
          onPressed: _envoi ? null : () => Navigator.of(context).pop(),
        ),
        BoutonStandard(
          key: const Key('modale-correspondance-retablir'),
          libelle: TextesModaleCorrespondance.retablir,
          variante: VarianteBouton.fantome,
          onPressed: _envoi ? null : () => _ecrire('', retablir: true),
        ),
        BoutonStandard(
          key: const Key('modale-correspondance-enregistrer'),
          libelle: TextesModaleCorrespondance.enregistrer,
          variante: VarianteBouton.primaire,
          onPressed: _envoi
              ? null
              : () => _ecrire(_numero.text.trim(), retablir: false),
        ),
      ],
    );
  }
}
