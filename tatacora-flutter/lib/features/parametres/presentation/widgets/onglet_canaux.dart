// Vue Blade maîtresse (PA-183) : pwa/transverse/parametres.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared_widgets/bouton_standard.dart';
import '../../../hebergement/domain/entities/fiche_reservation.dart';
import '../../../hebergement/domain/messages_canaux.dart';
import '../../../hebergement/presentation/providers_hebergement.dart';

/// Les mots de l'onglet « Canaux de réservation » (`pwa.parametres.canaux_*`),
/// au mot — l'apostrophe est celle de la vue (typographique).
abstract final class TextesCanaux {
  static const String introA =
      'Les canaux proposés à la saisie d’une réservation, ici et dans la réservation rapide du tableau de bord.';
  static const String introFort =
      'Un canal utilisé ne se supprime pas, il se désactive';
  static const String introB =
      '— l’effacer laisserait des réservations pointant vers un canal inexistant, et l’analyse par canal perdrait son historique.';
  static const String boutonAjouter = 'Ajouter un canal';
  static const String colonneCanal = 'Canal';
  static const String colonneReservations = 'Réservations';
  static const String colonneEtat = 'État';
  static const String colonneActions = 'Actions';
  static const String etatActif = 'actif';
  static const String etatDesactive = 'désactivé';
  static const String aucun = 'Aucun canal enregistré.';
  static const String boutonRenommer = 'Renommer';
  static const String boutonDesactiver = 'Désactiver';
  static const String boutonReactiver = 'Réactiver';
  static const String modaleTitreAjout = 'Nouveau canal de réservation';
  static const String modaleTitreRenommage = 'Renommer le canal';
  static const String champNom = 'Nom du canal';
  static const String aideAjout =
      'Le nom tel qu’il apparaîtra dans les formulaires de réservation.';
  static const String aideRenommage =
      'Les réservations déjà saisies conservent l’ancien libellé : renommer ne réécrit pas le passé.';

  /// `canaux_confirmation_desactivation` (`:nom`, `:n`).
  static String confirmationDesactivation(String nom, int n) =>
      'Désactiver « $nom » ? $n réservation(s) l’emploient. Elles le conserveront ; il ne sera simplement plus proposé aux nouvelles saisies.';

  /// `pwa.modale.annuler` et `parametres_pwa.enregistrer`.
  static const String annuler = 'Annuler';
  static const String enregistrer = 'Enregistrer';
}

/// L'onglet « Canaux de réservation » (`partials/tableau-canaux`) : le
/// référentiel `canaux_reservation_local`, administré ICI (écrivain unique
/// `CanauxReservationDao`) et synchronisé — ajout, renommage, désactivation et
/// réactivation, jamais une suppression. La fiche de réservation, la
/// réservation rapide et le filtre des annulations lisent la même table.
///
/// Les boutons n'existent que pour qui écrit sur Paramètres ([peutEcrire]) ;
/// sinon la colonne des actions affiche « — », comme la vue.
class OngletCanaux extends ConsumerWidget {
  const OngletCanaux({this.peutEcrire = true, super.key});

  final bool peutEcrire;

  static TextStyle _t(
    double taille, {
    FontWeight? poids,
    Color couleur = AppColors.neutre500,
  }) => TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: taille,
    height: 1.5,
    fontWeight: poids,
    color: couleur,
  );

  void _dire(BuildContext context, String texte, {bool erreur = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: erreur ? AppColors.erreur : AppColors.succes,
          content: Text(texte, key: const Key('param-canaux-message')),
        ),
      );
  }

  void _rafraichir(WidgetRef ref) {
    ref.invalidate(canauxReservationProvider);
    ref.invalidate(reservationsParCanalProvider);
  }

  /// « Ajouter un canal » (clé vide) ou « Renommer » : la même fenêtre, un
  /// refus du service s'affichant sous le champ.
  Future<void> _saisir(
    BuildContext context,
    WidgetRef ref, {
    CanalReservation? canal,
  }) async {
    final dao = ref.read(canauxReservationDaoProvider);
    final enregistre = await showDialog<bool>(
      context: context,
      barrierColor: AppColors.voileModale,
      builder: (_) => _ModaleCanal(
        canal: canal,
        enregistrer: (nom) async {
          try {
            if (canal == null) {
              await dao.ajouter(nom);
            } else {
              await dao.renommer(canal.code, nom);
            }
            return null;
          } on RefusCanal catch (e) {
            return e.message;
          }
        },
      ),
    );
    if (enregistre != true) return;
    _rafraichir(ref);
    if (context.mounted) _dire(context, MessagesCanaux.enregistre);
  }

  Future<void> _basculer(
    BuildContext context,
    WidgetRef ref,
    CanalReservation canal,
  ) async {
    try {
      await ref.read(canauxReservationDaoProvider).basculer(canal.code);
      _rafraichir(ref);
      if (context.mounted) _dire(context, MessagesCanaux.bascule);
    } on RefusCanal catch (e) {
      if (context.mounted) _dire(context, e.message, erreur: true);
    }
  }

  /// « Désactiver » d'un canal EMPLOYÉ : la confirmation de la vue, avec le
  /// compte réel de réservations (le maître : `Dialogue.confirmer`).
  Future<void> _demanderDesactivation(
    BuildContext context,
    WidgetRef ref,
    CanalReservation canal,
    int reservations,
  ) async {
    final confirme = await showDialog<bool>(
      context: context,
      barrierColor: AppColors.voileModale,
      builder: (ctx) => Dialog(
        key: const Key('param-modale-desactivation'),
        backgroundColor: AppColors.neutre0,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Largeurs.maxSm),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  TextesCanaux.boutonDesactiver,
                  style: _t(
                    TaillesContenu.base,
                    poids: FontWeight.bold,
                    couleur: AppColors.navy,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  TextesCanaux.confirmationDesactivation(
                    canal.libelle,
                    reservations,
                  ),
                  key: const Key('param-canal-confirmation'),
                  style: _t(TaillesContenu.sm, couleur: AppColors.neutre600),
                ),
                const SizedBox(height: AppSpacing.mdPlus),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    BoutonStandard(
                      key: const Key('param-canal-desactivation-annuler'),
                      libelle: TextesCanaux.annuler,
                      onPressed: () => Navigator.of(ctx).pop(false),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    BoutonStandard(
                      key: const Key('param-canal-desactivation-confirmer'),
                      variante: VarianteBouton.primaire,
                      libelle: TextesCanaux.boutonDesactiver,
                      onPressed: () => Navigator.of(ctx).pop(true),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (confirme != true || !context.mounted) return;
    await _basculer(context, ref, canal);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lus = ref.watch(canauxReservationProvider);
    final canaux = lus.value ?? const <CanalReservation>[];
    final comptes = ref.watch(reservationsParCanalProvider).value ?? const {};

    Widget cellule(Widget enfant, {int flex = 1, Alignment? alignement}) =>
        Expanded(
          flex: flex,
          child: Container(
            alignment: alignement ?? Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, // px-4
              vertical: AppSpacing.xsPlus, // py-2.5
            ),
            child: enfant,
          ),
        );

    Widget entete(String texte, {Alignment? alignement, int flex = 1}) =>
        cellule(
          Text(
            texte.toUpperCase(),
            style:
                _t(
                  TaillesContenu.t11,
                  poids: FontWeight.w600,
                  couleur: AppColors.neutre0.withValues(alpha: 0.9),
                ).copyWith(
                  letterSpacing: AppTextStyles.suiviLarge * TaillesContenu.t11,
                ),
          ),
          alignement: alignement,
          flex: flex,
        );

    Widget lien(Key cle, String texte, Color couleur, VoidCallback geste) =>
        InkWell(
          key: cle,
          onTap: geste,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
            child: Text(
              texte,
              style: _t(
                TaillesContenu.t12,
                poids: FontWeight.w600,
                couleur: couleur,
              ),
            ),
          ),
        );

    Widget badge(String texte, Color fond, Color encre) => Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs, // px-2
        vertical: AppSpacing.demi, // py-0.5
      ),
      decoration: BoxDecoration(
        color: fond,
        borderRadius: BorderRadius.circular(AppRadius.rounded),
      ),
      child: Text(
        texte,
        style: _t(TaillesContenu.t11, poids: FontWeight.w600, couleur: encre),
      ),
    );

    return Column(
      key: const Key('param-onglet-canaux'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md), // mb-4
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text.rich(
                  key: const Key('param-canaux-intro'),
                  TextSpan(
                    style: _t(TaillesContenu.t13),
                    children: const [
                      TextSpan(text: TextesCanaux.introA),
                      TextSpan(text: ' '),
                      TextSpan(
                        text: TextesCanaux.introFort,
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      TextSpan(text: ' '),
                      TextSpan(text: TextesCanaux.introB),
                    ],
                  ),
                ),
              ),
              if (peutEcrire) ...[
                const SizedBox(width: AppSpacing.md),
                BoutonStandard(
                  key: const Key('param-canal-ajouter'),
                  variante: VarianteBouton.primaire,
                  libelle: TextesCanaux.boutonAjouter,
                  onPressed: lus.hasValue ? () => _saisir(context, ref) : null,
                ),
              ],
            ],
          ),
        ),
        Container(
          key: const Key('param-canaux-tableau'),
          margin: const EdgeInsets.only(bottom: AppSpacing.mdPlus), // mb-5
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.neutre0,
            border: Border.all(color: AppColors.neutre200),
            borderRadius: BorderRadius.circular(AppRadius.roundedXl),
          ),
          child: Column(
            children: [
              Container(
                color: AppColors.navy,
                child: Row(
                  children: [
                    entete(TextesCanaux.colonneCanal),
                    entete(
                      TextesCanaux.colonneReservations,
                      alignement: Alignment.centerRight,
                    ),
                    entete(TextesCanaux.colonneEtat),
                    entete(
                      TextesCanaux.colonneActions,
                      alignement: Alignment.centerRight,
                      flex: 2,
                    ),
                  ],
                ),
              ),
              if (!lus.hasValue)
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (canaux.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Text(
                    TextesCanaux.aucun,
                    textAlign: TextAlign.center,
                    style: _t(TaillesContenu.t13, couleur: AppColors.neutre400),
                  ),
                ),
              for (final canal in canaux)
                Container(
                  key: Key('param-canal-${canal.code}'),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: AppColors.neutre100)),
                  ),
                  child: Row(
                    children: [
                      cellule(
                        Text(
                          canal.libelle,
                          style: _t(
                            TaillesContenu.t13,
                            poids: FontWeight.w600,
                            couleur: AppColors.neutre700,
                          ),
                        ),
                      ),
                      cellule(
                        Text(
                          (comptes[canal.code] ?? 0) == 0
                              ? '—'
                              : '${comptes[canal.code]}',
                          style: _t(
                            TaillesContenu.t13,
                            poids: (comptes[canal.code] ?? 0) == 0
                                ? null
                                : FontWeight.w600,
                            couleur: (comptes[canal.code] ?? 0) == 0
                                ? AppColors.neutre400
                                : AppColors.neutre500,
                          ),
                        ),
                        alignement: Alignment.centerRight,
                      ),
                      cellule(
                        canal.actif
                            ? badge(
                                TextesCanaux.etatActif,
                                PaletteMaitre.emeraude50,
                                PaletteMaitre.emeraude700,
                              )
                            : badge(
                                TextesCanaux.etatDesactive,
                                Ardoise.c100,
                                Ardoise.c600,
                              ),
                      ),
                      cellule(
                        peutEcrire
                            ? Wrap(
                                alignment: WrapAlignment.end,
                                spacing: AppSpacing.xs,
                                children: [
                                  lien(
                                    Key('param-canal-renommer-${canal.code}'),
                                    TextesCanaux.boutonRenommer,
                                    AppColors.navy,
                                    () => _saisir(context, ref, canal: canal),
                                  ),
                                  lien(
                                    Key('param-canal-basculer-${canal.code}'),
                                    canal.actif
                                        ? TextesCanaux.boutonDesactiver
                                        : TextesCanaux.boutonReactiver,
                                    AppColors.gold,
                                    () {
                                      final n = comptes[canal.code] ?? 0;
                                      // Un canal ACTIF et EMPLOYÉ se confirme ;
                                      // les autres basculent d'un geste.
                                      if (canal.actif && n > 0) {
                                        _demanderDesactivation(
                                          context,
                                          ref,
                                          canal,
                                          n,
                                        );
                                      } else {
                                        _basculer(context, ref, canal);
                                      }
                                    },
                                  ),
                                ],
                              )
                            : Text(
                                '—',
                                style: _t(
                                  TaillesContenu.t13,
                                  couleur: Ardoise.c300,
                                ),
                              ),
                        alignement: Alignment.centerRight,
                        flex: 2,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// La fenêtre « Nouveau canal de réservation » / « Renommer le canal » : un
/// champ, « Annuler », « Enregistrer ». Le refus du service (nom vide, déjà
/// pris) s'affiche SOUS le champ et la fenêtre reste ouverte.
class _ModaleCanal extends StatefulWidget {
  const _ModaleCanal({required this.enregistrer, this.canal});

  /// `null` : création.
  final CanalReservation? canal;

  /// Rend le refus à afficher, ou `null` quand le geste a réussi.
  final Future<String?> Function(String nom) enregistrer;

  @override
  State<_ModaleCanal> createState() => _ModaleCanalState();
}

class _ModaleCanalState extends State<_ModaleCanal> {
  late final _nom = TextEditingController(text: widget.canal?.libelle ?? '');
  String? _erreur;
  bool _enCours = false;

  @override
  void dispose() {
    _nom.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    if (_enCours) return;
    setState(() => _enCours = true);
    final refus = await widget.enregistrer(_nom.text);
    if (!mounted) return;
    if (refus == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _erreur = refus;
      _enCours = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ajout = widget.canal == null;
    return Dialog(
      key: const Key('param-modale-canal'),
      backgroundColor: AppColors.neutre0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Largeurs.maxSm),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                ajout
                    ? TextesCanaux.modaleTitreAjout
                    : TextesCanaux.modaleTitreRenommage,
                style: OngletCanaux._t(
                  TaillesContenu.base,
                  poids: FontWeight.bold,
                  couleur: AppColors.navy,
                ),
              ),
              const SizedBox(height: AppSpacing.unit),
              Text(
                ajout ? TextesCanaux.aideAjout : TextesCanaux.aideRenommage,
                style: OngletCanaux._t(TaillesContenu.t13),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                TextesCanaux.champNom,
                style: OngletCanaux._t(
                  TaillesContenu.t13,
                  poids: FontWeight.w600,
                  couleur: AppColors.neutre700,
                ),
              ),
              const SizedBox(height: AppSpacing.unit),
              TextField(
                key: const Key('param-canal-nom'),
                controller: _nom,
                autofocus: true,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _valider(),
              ),
              if (_erreur != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _erreur!,
                  key: const Key('param-canal-erreur'),
                  style: OngletCanaux._t(
                    TaillesContenu.t12,
                    couleur: AppColors.erreur,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.mdPlus),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  BoutonStandard(
                    key: const Key('param-canal-annuler'),
                    libelle: TextesCanaux.annuler,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  BoutonStandard(
                    key: const Key('param-canal-valider'),
                    variante: VarianteBouton.primaire,
                    libelle: TextesCanaux.enregistrer,
                    onPressed: _enCours ? null : _valider,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
