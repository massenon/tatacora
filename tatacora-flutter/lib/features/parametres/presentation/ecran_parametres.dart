// Vue Blade maîtresse (PA-183) : pwa/transverse/parametres.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/rbac/garde_acces.dart';
import '../../transverse/domain/comptes_utilisateurs.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/mesures_transverses.dart' show PaletteTransverse;
import '../../../core/theme/mesures_transverses_complement.dart';
import '../../../shared_widgets/bouton_standard.dart';
import '../data/parametres_depot_local.dart';
import '../domain/enregistrer_parametres.dart';
import '../domain/entities/parametre.dart';
import '../domain/options_systeme.dart';
import '../domain/resultats_parametres.dart';
import 'widgets/cadre_modale_parametre.dart';
import 'widgets/bouton_email_test.dart';
import 'widgets/champ_mot_de_passe_smtp.dart';
import 'widgets/champ_parametre.dart';
import 'widgets/onglet_apparence.dart';
import 'widgets/onglet_canaux.dart';
import 'widgets/onglet_espaces_tables.dart';
import 'widgets/onglet_synchronisation.dart';

// Les refus de la vue, DITS dans le code plutôt qu'affichés (la vue n'a plus de
// section de refus à l'écran — directive du 31/08/2026). Ce sont des champs ou
// des gestes, pas des blocs entiers : le jeton `blade-refuse:` du comparateur
// refuserait l'onglet tout entier, ce qui n'est pas ce qui est dit ici :
//
//  - Refus, onglet « communication » — l'invite
//    « •••••••••••••••• » de la « Clé API WhatsApp Business » : un secret
//    n'entre JAMAIS dans `parametres_systeme`, lisible par tout profil ayant
//    l'écran ; il vit en `.env`.
//  - (Levé le 19/10/2026, onglet « email » : le champ « Mot de passe SMTP »
//    est SAISI — décision du PO —, écrit dans `poste.json`, jamais en base.)
//  - Refus, onglet « activation » — le pied de formulaire
//    unique du maître (« Annuler » / « Enregistrer les paramètres ») : cet écran
//    enregistre une clé à la fois, par fenêtre ; un enregistrement groupé
//    écraserait en silence le changement d'un autre Administrateur.
//  - Refus, onglet « identite » — les invites d'exemple
//    (« Ex. 3202612345678 ») : l'écran affiche des valeurs, pas des champs.
//  - (Levé le 21/10/2026, onglet « canaux » : ajout, renommage, désactivation et
//    réactivation d'un canal de réservation sont PORTÉS — table locale,
//    écrivain unique `CanauxReservationDao`, synchronisation, fiche de
//    réservation qui lit la table. Plus aucun jeton de refus pour cet onglet.)
//

// Les libellés des champs viennent du serveur (registre `RegistreParametres`) :
//  libelles-du-serveur:transverse/parametres

/// Le stockage LOCAL des paramètres (`parametres_systeme_local`, plus
/// `taux_paie_local` pour les cinq taux de la paie). Un fournisseur, pour que
/// les tests posent leur propre base sans toucher au fichier du poste.
final stockageParametresProvider = Provider<StockageParametres>(
  (ref) => ParametresDepotLocal(ref.watch(baseLocaleProvider)),
);

final enregistrerParametresProvider = Provider<EnregistrerParametres>(
  (ref) => EnregistrerParametres(ref.watch(stockageParametresProvider)),
);

/// Le motif affiché quand le droit de lecture manque. La route filtre déjà
/// par module (`PARAM`), mais un écran ne suppose pas que son appelant l'a fait.
const String refusLectureParametres =
    'Vous n’avez pas le droit de consulter les paramètres du système.';

/// La consultation, LOCALE. `autoDispose` : revenir sur l'écran relit la base,
/// il ne réaffiche pas ce qu'on avait vu.
final parametresProvider = FutureProvider.autoDispose<ResultatParametres>((
  ref,
) async {
  if (!ref.watch(droitsProvider).peutLire(ModuleTatacora.parametres)) {
    return const ParametresRefuses(motif: refusLectureParametres);
  }
  return ParametresRecus(await ref.watch(enregistrerParametresProvider).lire());
});

/// Les sept onglets du maître, dans son ordre (`Parametres::ONGLETS`).
const _onglets = <(String, String)>[
  ('identite', 'Identité & Légal'),
  ('communication', 'Communication'),
  ('email', 'Email (SMTP)'),
  ('apparence', 'Logo & Apparence'),
  ('canaux', 'Canaux de réservation'),
  ('tables', 'Espaces & tables'),
  ('activation', 'Activation & Sécurité'),
];

/// L'onglet AJOUTÉ par le poste (lot F2a, 15/10/2026, décision du PO) :
/// l'appairage au serveur. La vue n'en a pas — le serveur ne s'appaire pas à
/// lui-même. Affiché aux seuls Administrateurs (`rolesAdministration`, la
/// règle de « Comptes utilisateurs »).
const _ongletSynchronisation = ('synchronisation', 'Synchronisation');

/// Les clés que le maître loge sous « Informations légales & fiscales ».
const _clesLegales = {
  'entreprise_ifu',
  'entreprise_rccm',
  'entreprise_numero_mecef',
};

/// Les deux champs du groupe `entreprise` que le maître pose sous
/// « Communication » (`Parametres::ongletDe`).
const _clesCommunication = {'communication_whatsapp', 'entreprise_site_web'};

/// Le champ que le maître étale sur les deux colonnes (`sm:col-span-2`).
const _cleAdresse = 'entreprise_adresse';

/// L'onglet du maître qui porte une définition (`Parametres::ongletDe`).
String _ongletDe(DefinitionParametre d) {
  if (_clesCommunication.contains(d.cle)) return 'communication';
  return switch (d.groupe) {
    'social' || 'exploitation' || 'activation' => 'activation',
    'email' => 'email',
    _ => 'identite',
  };
}

/// L'écran **Paramètres** — la vue `transverse/parametres`, module RBAC
/// `PARAM`.
///
/// ## La mise en page est celle de la vue
///
/// Un conteneur de 1 100 px, l'engrenage et le titre, la phrase d'introduction,
/// les SEPT onglets fixes du maître, la carte « État réel de la
/// configuration » (TVA et MECeF, états DÉRIVÉS jamais des commutateurs bruts,
/// PA-61), puis la carte blanche du formulaire en grille à deux colonnes. Un
/// champ s'affiche en LECTURE — sa valeur dans une pastille —, et « Modifier »
/// ouvre une fenêtre qui n'enregistre que cette clé : un enregistrement groupé
/// écraserait en silence le changement d'un autre Administrateur.
///
/// Jusqu'au 08/10/2026 les onglets étaient ceux des GROUPES du serveur
/// (« Fiscalité », « Charges sociales »…) et les champs s'empilaient en une
/// colonne : la mesure de géométrie (Phase 1D) plaçait « Logo & Apparence » à
/// 1 113 px sous sa position dans la vue.
class EcranParametres extends ConsumerWidget {
  const EcranParametres({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultat = ref.watch(parametresProvider);

    return resultat.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _Note(cle: const Key('param-erreur'), texte: '$e'),
      data: (r) => switch (r) {
        ParametresRecus(:final parametres) => _Page(parametres: parametres),
        ParametresRefuses(:final motif) => _Note(
          cle: const Key('param-refus'),
          texte: motif,
        ),
      },
    );
  }
}

class _Page extends ConsumerStatefulWidget {
  const _Page({required this.parametres});

  final Parametres parametres;

  @override
  ConsumerState<_Page> createState() => _PageState();
}

class _PageState extends ConsumerState<_Page> {
  String _onglet = 'identite';

  @override
  Widget build(BuildContext context) {
    final parametres = widget.parametres;
    final peutEcrire = ref
        .watch(droitsProvider)
        .peutEcrire(ModuleTatacora.parametres);

    return SingleChildScrollView(
      // `p-5 lg:p-8` : 32 px au poste de travail, le seul gabarit du client
      // (décision du 08/10/2026). Posé ICI, écran par écran : le poser dans la
      // coquille fait déborder les écrans qui ne défilent pas encore (voir
      // `docs/AUDIT_FIDELITE_FLUTTER_BLADE_2026-10-08.md`, §4novies).
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          // `max-w-[1100px]`
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _EnTete(),
              _BarreOnglets(
                onglets: [
                  ..._onglets,
                  if (peutAdministrerComptes(ref.watch(sessionProvider)?.role))
                    _ongletSynchronisation,
                ],
                actif: _onglet,
                onChoisir: (o) => setState(() => _onglet = o),
              ),
              _EtatsReels(etats: parametres.etats),
              Container(
                padding: const EdgeInsets.all(AppSpacing.lg), // p-6
                decoration: _carte(),
                child: _contenu(parametres, peutEcrire),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _contenu(Parametres p, bool peutEcrire) {
    List<DefinitionParametre> de(bool Function(DefinitionParametre) f) => [
      for (final d in p.definitions)
        if (_ongletDe(d) == _onglet && f(d)) d,
    ];

    Widget ligne(DefinitionParametre d) => _LigneParametre(
      key: Key('param-ligne-${d.cle}'),
      definition: d,
      peutEcrire: peutEcrire,
      onModifier: () => _modifier(d),
    );

    switch (_onglet) {
      case 'identite':
        final identite = de(
          (d) => d.groupe == 'entreprise' && !_clesLegales.contains(d.cle),
        );
        final legal = de(
          (d) => _clesLegales.contains(d.cle) || d.groupe == 'fiscalite',
        );
        return _Grille(
          enfants: [
            // Apostrophe DROITE, comme la vue (le panneau supprimé le 09/10/2026 la portait
            // seul, et la comparaison par sous-chaîne la comptait présente à tort).
            const _TitreSection("Identité de l'entreprise"),
            for (final d in identite)
              _Cellule(pleine: d.cle == _cleAdresse, enfant: ligne(d)),
            const _TitreSection('Informations légales & fiscales', filet: true),
            for (final d in legal) _Cellule(enfant: ligne(d)),
          ],
        );
      case 'communication':
        final communication = de((_) => true);
        // Dans l'ordre de la vue : WhatsApp, la clé API (un secret, rendu en
        // ligne et refusé comme valeur), le site web sur deux colonnes, puis
        // le message de bienvenue (porté par les modèles de Notifications).
        return _Grille(
          enfants: [
            const _TitreSection('Canaux de notification'),
            for (final d in communication.where(
              (d) => d.cle != 'entreprise_site_web',
            ))
              _Cellule(enfant: ligne(d)),
            const _Cellule(
              enfant: _ChampRefuse(
                cle: 'param-cle-api-whatsapp',
                libelle: _TextesCommunication.cleApiLibelle,
                mention: _TextesCommunication.cleApiMention,
              ),
            ),
            for (final d in communication.where(
              (d) => d.cle == 'entreprise_site_web',
            ))
              _Cellule(pleine: true, enfant: ligne(d)),
            const _Cellule(
              pleine: true,
              enfant: _ChampRefuse(
                cle: 'param-message-bienvenue',
                libelle: _TextesCommunication.messageLibelle,
                mention: _TextesCommunication.messageMention,
              ),
            ),
          ],
        );
      case 'email':
        return _Grille(
          enfants: [
            const _TitreSection('Configuration Email (SMTP)'),
            for (final d in de((_) => true)) _Cellule(enfant: ligne(d)),
            // « Mot de passe SMTP » : SAISI depuis le 19/10/2026 (décision du
            // PO), écrit dans `poste.json`, jamais dans la base.
            _Cellule(enfant: ChampMotDePasseSmtp(peutEcrire: peutEcrire)),
            // « Envoyer un email de test » : RÉEL, par la configuration SMTP de
            // ce poste ; il rapporte ce que le transport a répondu.
            _Cellule(
              pleine: true,
              enfant: BoutonEmailTest(peutEcrire: peutEcrire),
            ),
          ],
        );
      case 'activation':
        final regroupes = <String, List<DefinitionParametre>>{
          'activation': de((d) => d.groupe == 'activation'),
          'social': de((d) => d.groupe == 'social'),
          'exploitation': de((d) => d.groupe == 'exploitation'),
        };
        return _OngletActivation(
          bascules: regroupes['activation']!,
          peutEcrire: peutEcrire,
          onBasculer: _basculer,
          groupes: [
            (
              _TextesActivation.sectionSocial,
              [
                for (final d in regroupes['social']!)
                  _Cellule(enfant: ligne(d)),
              ],
            ),
            (
              _TextesActivation.sectionExploitation,
              [
                for (final d in regroupes['exploitation']!)
                  _Cellule(enfant: ligne(d)),
              ],
            ),
          ],
          versRestauration: () => GoRouter.of(context).go('/import-export'),
        );
      case 'tables':
        // Le référentiel des tables de salle du poste (`tables_local`, seul
        // écrivain `TablesPosDao`) — le même que lit le point de vente.
        return OngletEspacesTables(peutEcrire: peutEcrire);
      case 'apparence':
        // Logo et favicon téléversés, charte en lecture seule (21/10/2026).
        return OngletApparence(peutEcrire: peutEcrire);
      case 'synchronisation':
        // L'onglet refait lui-même la vérification du rôle.
        return const OngletSynchronisation();
      case 'canaux':
        // Le référentiel `canaux_reservation_local` : ajout, renommage,
        // désactivation et réactivation, synchronisés (21/10/2026).
        return OngletCanaux(peutEcrire: peutEcrire);
      default:
        return const SizedBox.shrink();
    }
  }

  /// « Modifier » : une fenêtre qui n'enregistre que CETTE clé.
  ///
  /// Fenêtre COMPACTE (PO, 14/10/2026) : l'`AlertDialog` d'avant sortait trop
  /// haute (« Raison sociale ») ; un `Dialog` borné, à la hauteur de son
  /// contenu, la remplace — mêmes champ, validation et enregistrement.
  Future<void> _modifier(DefinitionParametre d) async {
    Object? saisie;
    String? erreur;
    var envoi = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => CadreModaleParametre(
          titre: d.libelle,
          champ: ChampParametre(
            definition: d,
            saisie: saisie,
            erreur: erreur,
            modifiable: true,
            onChange: (v) => setLocal(() {
              saisie = v;
              erreur = null;
            }),
          ),
          actions: [
            BoutonStandard(
              key: const Key('param-annuler'),
              libelle: 'Annuler',
              onPressed: () => Navigator.of(ctx).pop(),
            ),
            BoutonStandard(
              key: const Key('param-enregistrer'),
              libelle: 'Enregistrer',
              variante: VarianteBouton.primaire,
              // Désactivé tant que rien n'a changé : un envoi vide ne
              // modifierait rien et rendrait tout de même
              // « enregistré ».
              onPressed: saisie == null || envoi
                  ? null
                  : () async {
                      setLocal(() => envoi = true);
                      final r = await ref
                          .read(enregistrerParametresProvider)
                          .executer(
                            {d.cle: saisie},
                            peutEcrire: ref
                                .read(droitsProvider)
                                .peutEcrire(ModuleTatacora.parametres),
                            auteurId: ref.read(sessionProvider)?.utilisateurId,
                          );
                      if (!ctx.mounted) return;
                      switch (r) {
                        case EcritureAcceptee(:final message):
                          Navigator.of(ctx).pop();
                          _dire(message);
                          // La valeur affichée est celle de la base,
                          // normalisée par le registre : la relire
                          // est le seul moyen de montrer ce qui a
                          // réellement été enregistré.
                          ref.invalidate(parametresProvider);
                        case EcritureRefusee(:final motif, :final parCle):
                          setLocal(() {
                            envoi = false;
                            erreur = parCle[d.cle] ?? motif;
                          });
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  /// Une bascule d'activation, appliquée AU CLIC — jamais au bouton
  /// Enregistrer : « un réglage de sécurité laissé en attente d'un
  /// enregistrement qu'on oublie donne l'illusion d'une protection qui n'est
  /// pas posée » (`Parametres::basculerOption`). L'écriture passe par
  /// l'unique `EnregistrerParametres` (donc par la file d'envoi, que le Journal
  /// d'Audit de ce poste relit).
  Future<void> _basculer(DefinitionParametre d) async {
    final active = !OptionsSysteme.actif(d.cle, d.valeur);
    final r = await ref
        .read(enregistrerParametresProvider)
        .executer(
          {d.cle: active ? 'true' : 'false'},
          peutEcrire: ref
              .read(droitsProvider)
              .peutEcrire(ModuleTatacora.parametres),
          auteurId: ref.read(sessionProvider)?.utilisateurId,
        );
    if (!mounted) return;
    switch (r) {
      case EcritureAcceptee():
        _dire(
          active
              ? _TextesActivation.activee(d.libelle)
              : _TextesActivation.desactivee(d.libelle),
        );
        ref.invalidate(parametresProvider);
      case EcritureRefusee(:final motif, :final parCle):
        _dire(parCle[d.cle] ?? motif, erreur: true);
    }
  }

  void _dire(String message, {bool erreur = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const Key('param-message'),
        content: Text(message),
        backgroundColor: erreur ? AppColors.erreur : AppColors.succes,
      ),
    );
  }
}

BoxDecoration _carte() => BoxDecoration(
  color: AppColors.neutre0,
  borderRadius: BorderRadius.circular(AppRadius.roundedXl), // rounded-xl
  border: Border.all(color: AppColors.neutre200),
);

/// `<div class="mb-6">` : l'engrenage et le titre, puis l'introduction.
class _EnTete extends StatelessWidget {
  const _EnTete();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg), // mb-6
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.settings_outlined,
                size: AppLayout.iconeTitrePage,
                color: AppColors.navy,
              ),
              const SizedBox(width: AppSpacing.xsPlus), // gap-2.5
              Text(
                'Paramètres',
                style: TextStyle(
                  fontFamily: AppTextStyles.police,
                  fontSize: TaillesContenu.lg,
                  // `line-height` hérité du corps de la vue (1,5) ; 1,4 au titre.
                  height: TaillesContenu.interligneLg,
                  fontWeight: FontWeight.bold,
                  color: AppColors.navy,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs), // mt-1.5
          Text(
            "Identité de l'entreprise, informations légales, canaux de communication et paramétrage technique du système.",
            style: TextStyle(
              fontFamily: AppTextStyles.police,
              fontSize: TaillesContenu.t15,
              // `line-height` hérité du corps de la vue (1,5) ; 1,4 au titre.
              height: 1.5,
              color: AppColors.neutre500,
            ),
          ),
        ],
      ),
    );
  }
}

/// `<div class="flex flex-wrap gap-2 mb-5">` et `Onglets::classes()`.
class _BarreOnglets extends StatelessWidget {
  const _BarreOnglets({
    required this.onglets,
    required this.actif,
    required this.onChoisir,
  });

  final List<(String, String)> onglets;
  final String actif;
  final ValueChanged<String> onChoisir;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.mdPlus), // mb-5
      child: Wrap(
        spacing: AppSpacing.xs, // gap-2
        runSpacing: AppSpacing.xs,
        children: [
          for (final (cle, libelle) in onglets)
            _Onglet(
              key: Key('param-onglet-$cle'),
              libelle: libelle,
              actif: cle == actif,
              onTap: () => onChoisir(cle),
            ),
        ],
      ),
    );
  }
}

/// `px-3.5 py-2 rounded-lg text-[13px] font-semibold` — actif : fond marine,
/// texte blanc ; inactif : fond blanc, texte `slate-500`, bordure `slate-200`.
class _Onglet extends StatelessWidget {
  const _Onglet({
    required super.key,
    required this.libelle,
    required this.actif,
    required this.onTap,
  });

  final String libelle;
  final bool actif;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: actif ? AppColors.navy : AppColors.neutre0,
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.smPlus, // px-3.5
            vertical: AppSpacing.xs, // py-2
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.roundedLg),
            border: actif ? null : Border.all(color: AppColors.neutre200),
          ),
          child: Text(
            libelle,
            style: TextStyle(
              fontFamily: AppTextStyles.police,
              fontSize: TaillesContenu.t13,
              // `line-height` hérité du corps de la vue (1,5) ; 1,4 au titre.
              height: 1.5,
              fontWeight: FontWeight.w600,
              color: actif ? AppColors.neutre0 : AppColors.neutre500,
            ),
          ),
        ),
      ),
    );
  }
}

/// La carte « État réel de la configuration » — les états DÉRIVÉS du serveur.
class _EtatsReels extends StatelessWidget {
  const _EtatsReels({required this.etats});

  final Map<String, EtatDerive> etats;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.mdPlus), // mb-5
      padding: const EdgeInsets.all(AppSpacing.mdPlus), // p-5
      decoration: _carte(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'État réel de la configuration',
            style: TextStyle(
              fontFamily: AppTextStyles.police,
              fontSize: TaillesContenu.sm,
              // `line-height` hérité du corps de la vue (1,5) ; 1,4 au titre.
              height: 1.5,
              fontWeight: FontWeight.bold,
              color: AppColors.neutre700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm), // mb-3
          LayoutBuilder(
            builder: (context, c) {
              final largeur = (c.maxWidth - AppSpacing.sm) / 2;
              return Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final (cle, titre) in const [
                    ('tva', 'TVA'),
                    ('mecef', 'MECeF'),
                  ])
                    SizedBox(
                      width: largeur,
                      child: Container(
                        key: Key('param-etat-$cle'),
                        padding: const EdgeInsets.all(AppSpacing.sm), // p-3
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                            AppRadius.roundedLg,
                          ),
                          border: Border.all(color: AppColors.neutre200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              titre.toUpperCase(),
                              style: TextStyle(
                                fontFamily: AppTextStyles.police,
                                fontSize: TaillesContenu.t11,
                                // `line-height` hérité du corps de la vue (1,5) ; 1,4 au titre.
                                height: 1.5,
                                letterSpacing: 0.5, // tracking-wide
                                color: AppColors.neutre400,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.unit), // mt-1
                            Text(
                              // Le libellé vient du serveur en entier : le
                              // recomposer en ferait une seconde formulation.
                              etats[cle]?.libelle ?? '—',
                              style: TextStyle(
                                fontFamily: AppTextStyles.police,
                                fontSize: TaillesContenu.t13,
                                // `line-height` hérité du corps de la vue (1,5) ; 1,4 au titre.
                                height: 1.5,
                                color: AppColors.neutre700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// `grid grid-cols-1 sm:grid-cols-2 gap-4` : deux colonnes au poste.
class _Grille extends StatelessWidget {
  const _Grille({required this.enfants});

  final List<Widget> enfants;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final moitie = (c.maxWidth - AppSpacing.md) / 2;
        return Wrap(
          spacing: AppSpacing.md, // gap-4
          runSpacing: AppSpacing.md,
          children: [
            for (final e in enfants)
              SizedBox(
                width: e is _Cellule && !e.pleine ? moitie : c.maxWidth,
                child: e,
              ),
          ],
        );
      },
    );
  }
}

/// Une cellule de la grille : une colonne, ou les deux (`sm:col-span-2`).
class _Cellule extends StatelessWidget {
  const _Cellule({required this.enfant, this.pleine = false});

  final Widget enfant;
  final bool pleine;

  @override
  Widget build(BuildContext context) => enfant;
}

/// `<h3 class="text-sm font-bold text-slate-700 mb-1">` sur deux colonnes ;
/// une section suivante est séparée par `pt-3 mt-1 border-t border-slate-100`.
class _TitreSection extends StatelessWidget {
  const _TitreSection(this.texte, {this.filet = false});

  final String texte;
  final bool filet;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(top: filet ? AppSpacing.sm : 0), // pt-3
      margin: EdgeInsets.only(top: filet ? AppSpacing.unit : 0), // mt-1
      decoration: filet
          ? const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.neutre100)),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.unit), // mb-1
        child: Text(
          texte,
          style: TextStyle(
            fontFamily: AppTextStyles.police,
            fontSize: TaillesContenu.sm,
            // `line-height` hérité du corps de la vue (1,5) ; 1,4 au titre.
            height: 1.5,
            fontWeight: FontWeight.bold,
            color: AppColors.neutre700,
          ),
        ),
      ),
    );
  }
}

/// Un champ en LECTURE — le bloc `groupe-champ` de la vue : le libellé, la
/// valeur dans une pastille, « Modifier », puis l'aide.
class _LigneParametre extends StatelessWidget {
  const _LigneParametre({
    required super.key,
    required this.definition,
    required this.peutEcrire,
    required this.onModifier,
  });

  final DefinitionParametre definition;
  final bool peutEcrire;
  final VoidCallback onModifier;

  /// « — » quand la clé n'est PAS renseignée, « 0 » quand elle vaut zéro : les
  /// confondre ferait croire l'arbitrage de PA-53 rendu. Un booléen se DIT
  /// (Oui / Non), jamais « true ».
  String get _valeur {
    final v = definition.valeur;
    if (v == null) return '—';
    if (definition.typeBrut == 'booleen') return v == 'true' ? 'Oui' : 'Non';
    return v;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          definition.libelle,
          style: TextStyle(
            fontFamily: AppTextStyles.police,
            fontSize: TaillesContenu.t15,
            // `line-height` hérité du corps de la vue (1,5) ; 1,4 au titre.
            height: 1.5,
            fontWeight: FontWeight.w600,
            color: AppColors.neutre700,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs), // mb-1.5
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xsPlus, // px-2.5
                vertical: AppSpacing.unit, // py-1
              ),
              decoration: BoxDecoration(
                color: AppColors.neutre100,
                borderRadius: BorderRadius.circular(AppRadius.rounded),
              ),
              child: Text(
                _valeur,
                style: TextStyle(
                  fontFamily: AppTextStyles.police,
                  fontSize: TaillesContenu.t13,
                  // `line-height` hérité du corps de la vue (1,5) ; 1,4 au titre.
                  height: 1.5,
                  color: AppColors.neutre600,
                ),
              ),
            ),
            if (peutEcrire) ...[
              const SizedBox(width: AppSpacing.xs), // gap-2
              OutlinedButton(
                key: Key('param-modifier-${definition.cle}'),
                onPressed: onModifier,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, // px-3
                    vertical: AppSpacing.xxs, // py-1.5
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  side: const BorderSide(color: AppColors.neutre200),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.roundedLg),
                  ),
                ),
                child: Text(
                  'Modifier',
                  style: TextStyle(
                    fontFamily: AppTextStyles.police,
                    fontSize: TaillesContenu.t12,
                    // `line-height` hérité du corps de la vue (1,5) ; 1,4 au titre.
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.neutre700,
                  ),
                ),
              ),
            ],
            // AJOUT de ce poste, absent de la vue (09/10/2026) : ce que la
            // source locale sait et que le serveur ne disait pas — le refus
            // d'un secret, « aucun module ne lit cette valeur ». En INFOBULLE
            // sur la ligne (précédent D91 : la raison d'une absence passe en
            // infobulle), et en TEXTE VISIBLE dans la fenêtre de modification,
            // là où l'exploitant s'apprête à saisir. Poser ces phrases en
            // ligne sous l'aide ajoutait une ligne à dix champs et décalait
            // toute la grille : la mesure de géométrie passait de 24 à 19
            // éléments alignés sur 26 (relevé du 09/10/2026), sans qu'aucun
            // libellé de la vue ait changé.
            // CORRECTION de l'aide du serveur quand elle affirme un fait faux sur
            // ce poste (D114) : VISIBLE en ligne, dans la rangée de la valeur —
            // et non sous l'aide, où une ligne de plus décalait toute la grille
            // (géométrie 24 → 19 sur 26, relevé du 09/10/2026).
            if (definition.correction != null) ...[
              const SizedBox(width: AppSpacing.xs), // gap-2
              Flexible(
                child: Text(
                  definition.correction!,
                  key: Key('param-correction-${definition.cle}'),
                  style: TextStyle(
                    fontFamily: AppTextStyles.police,
                    fontSize: TaillesContenu.t12,
                    height: 1.5,
                    color: AppColors.neutre700,
                  ),
                ),
              ),
            ],
            if (definition.notes.isNotEmpty) ...[
              const SizedBox(width: AppSpacing.xs), // gap-2
              Tooltip(
                key: Key('param-note-${definition.cle}'),
                message: definition.notes.join('\n'),
                child: const Icon(
                  Icons.info_outline,
                  size: AppLayout.iconeChamp,
                  color: AppColors.neutre400,
                ),
              ),
            ],
          ],
        ),
        if (definition.aide != null) ...[
          const SizedBox(height: AppSpacing.xxs), // mt-1.5
          Text(
            aideAffichee(definition.aide!),
            style: TextStyle(
              fontFamily: AppTextStyles.police,
              fontSize: TaillesContenu.t12,
              // `line-height` hérité du corps de la vue (1,5) ; 1,4 au titre.
              height: 1.5,
              color: AppColors.neutre400,
            ),
          ),
        ],
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required Key cle, required this.texte}) : super(key: cle);

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.neutre100,
        borderRadius: BorderRadius.circular(AppSpacing.md),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline,
            size: AppLayout.iconeNote,
            color: AppColors.neutre500,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              texte,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: AppColors.neutre500),
            ),
          ),
        ],
      ),
    );
  }
}

/* ====================================================================== */
/* Communication — les deux champs refusés, rendus en ligne                */
/* ====================================================================== */

/// Les mots des deux champs du maître que ce poste ne tient pas comme valeurs
/// (`pwa.parametres.communication_*`) : un secret (la clé API), et un texte
/// que portent déjà les modèles de Notifications (le message de bienvenue).
abstract final class _TextesCommunication {
  static const String cleApiLibelle = 'Clé API WhatsApp Business';
  static const String cleApiMention =
      "Secret technique : n'entrera jamais dans les paramètres système, lisibles par tout profil ayant accès à cet écran — il vit en configuration serveur.";
  static const String messageLibelle =
      'Message de bienvenue (notifications automatiques)';
  static const String messageMention =
      'Porté par les modèles du module Notifications (un texte par évènement et par canal) : une seconde source de texte ici finirait par diverger de la première.';
}

/// `groupe-champ` d'un champ refusé comme valeur : le libellé, « — » dans une
/// pastille mono (`font-mono-tatacora px-2.5 py-1 rounded bg-slate-100
/// text-slate-400`), puis la mention qui dit pourquoi.
class _ChampRefuse extends StatelessWidget {
  const _ChampRefuse({
    required this.cle,
    required this.libelle,
    required this.mention,
  });

  final String cle;
  final String libelle;
  final String mention;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: Key(cle),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          libelle,
          style: TextStyle(
            fontFamily: AppTextStyles.police,
            fontSize: TaillesContenu.t15,
            height: 1.5,
            fontWeight: FontWeight.w600,
            color: AppColors.neutre700,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs), // mb-1.5
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xsPlus, // px-2.5
            vertical: AppSpacing.unit, // py-1
          ),
          decoration: BoxDecoration(
            color: AppColors.neutre100,
            borderRadius: BorderRadius.circular(AppRadius.rounded),
          ),
          child: Text(
            '—',
            style: TextStyle(
              fontFamily: AppTextStyles.policeMonospace,
              fontSize: TaillesContenu.t13,
              height: 1.5,
              color: AppColors.neutre400,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xxs), // mt-1.5
        Text(
          mention,
          style: TextStyle(
            fontFamily: AppTextStyles.police,
            fontSize: TaillesContenu.t12,
            height: 1.5,
            color: AppColors.neutre400,
          ),
        ),
      ],
    );
  }
}

/* ====================================================================== */
/* Activation & Sécurité — les bascules de la vue                          */
/* ====================================================================== */

/// Les mots de l'onglet (`pwa.parametres.activation_*`, `suppression_rappel_*`,
/// `risque_*`, `bascule_*`), découpés autour des `<strong>` de la vue comme
/// ses clés de langue.
abstract final class _TextesActivation {
  static const String sectionActions = 'Actions sensibles';
  static const String sectionSocial = 'Charges sociales';
  static const String sectionExploitation = 'Exploitation';
  static const String sectionSuppression = 'Rappel sur la suppression';

  static const String introA =
      "Ces bascules commandent ce que l'application propose";
  static const String introFortProfils = 'à tous les profils';
  static const String introB = ', dans ';
  static const String introFortModules = 'tous les modules';
  static const String introC =
      ". Elles ne remplacent pas les droits RBAC, qui disent ce que chaque profil a le droit de faire : les deux s'appliquent, et la plus restrictive gagne.";

  static const String infoA = 'Une action désactivée est';
  static const String infoFort = 'retirée';
  static const String infoB =
      " de l'écran, pas grisée : un bouton grisé invite à cliquer et ne produit qu'un refus. Chaque changement est tracé au journal d'audit.";

  static const String risqueFaible = 'Risque faible';
  static const String risqueModere = 'Risque modéré';
  static const String risqueEleve = 'Risque élevé';

  static String activee(String titre) => '$titre — activée.';
  static String desactivee(String titre) => '$titre — désactivée.';

  static const String rappelA = 'Même activée, la suppression';
  static const String rappelFort = 'archive';
  static const String rappelB =
      " : l'enregistrement complet part aux archives et reste restaurable depuis ";
  static const String rappelLien = 'Import & Export › Restaurer';
  static const String rappelC =
      ". Un élément engagé dans une réservation ou une vente encaissée est refusé à l'archivage — la ligne correspondante deviendrait illisible.";
}

/// Le risque du maître de chaque bascule (`Parametres::bascules`, un `match` à
/// clés littérales) : suppression `moyen`, réinitialisation `eleve`, alertes
/// d'ouverture `faible`, toute autre `eleve`.
({String libelle, Color fond, Color texte}) _risqueDe(String cle) =>
    switch (cle) {
      'activation_suppression' => (
        libelle: _TextesActivation.risqueModere,
        fond: PaletteMaitre.ambre50,
        texte: PaletteTransverse.texteOr,
      ),
      'activation_alertes_ouverture' => (
        libelle: _TextesActivation.risqueFaible,
        fond: AppColors.badgeVertFond,
        texte: PaletteTransverse.texteVert,
      ),
      _ => (
        libelle: _TextesActivation.risqueEleve,
        fond: AppColors.badgeRougeFond,
        texte: PaletteTransverse.texteRouge,
      ),
    };

TextStyle _styleActivation(
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

/// L'onglet « Activation & Sécurité » : titre, phrase d'introduction,
/// encadré bleu, une rangée à bascule par option (pastille de risque, titre,
/// aide du registre), puis les groupes « Charges sociales » et
/// « Exploitation » (servis par le registre) et le rappel sur la suppression.
class _OngletActivation extends StatelessWidget {
  const _OngletActivation({
    required this.bascules,
    required this.peutEcrire,
    required this.onBasculer,
    required this.groupes,
    required this.versRestauration,
  });

  final List<DefinitionParametre> bascules;
  final bool peutEcrire;
  final Future<void> Function(DefinitionParametre) onBasculer;
  final List<(String, List<Widget>)> groupes;
  final VoidCallback versRestauration;

  @override
  Widget build(BuildContext context) {
    const fort = TextStyle(fontWeight: FontWeight.bold);
    Widget separe(Widget enfant) => Container(
      margin: const EdgeInsets.only(top: AppSpacing.mdPlus), // mt-5
      padding: const EdgeInsets.only(top: AppSpacing.md), // pt-4
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.neutre100)),
      ),
      child: enfant,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md), // mb-4
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _TitreSection(_TextesActivation.sectionActions),
              Text.rich(
                TextSpan(
                  style: _styleActivation(TaillesContenu.t15),
                  children: const [
                    TextSpan(text: _TextesActivation.introA),
                    TextSpan(text: ' '),
                    TextSpan(
                      text: _TextesActivation.introFortProfils,
                      style: fort,
                    ),
                    TextSpan(text: _TextesActivation.introB),
                    TextSpan(
                      text: _TextesActivation.introFortModules,
                      style: fort,
                    ),
                    TextSpan(text: _TextesActivation.introC),
                  ],
                ),
              ),
            ],
          ),
        ),
        Container(
          key: const Key('param-activation-info'),
          margin: const EdgeInsets.only(bottom: AppSpacing.md), // mb-4
          padding: MesuresBasculeActivation.margeInfo,
          decoration: BoxDecoration(
            color: AppColors.badgeBleuFond,
            borderRadius: BorderRadius.circular(AppRadius.roundedLg),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: AppSpacing.demi), // mt-0.5
                child: Icon(
                  Icons.info_outline,
                  size: MesuresBasculeActivation.iconeInfo,
                  color: AppColors.info,
                ),
              ),
              const SizedBox(width: AppSpacing.xsPlus), // gap-2.5
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: _styleActivation(
                      TaillesContenu.t13,
                      couleur: PaletteMaitre.bleu900,
                    ),
                    children: const [
                      TextSpan(text: _TextesActivation.infoA),
                      TextSpan(text: ' '),
                      TextSpan(text: _TextesActivation.infoFort, style: fort),
                      TextSpan(text: _TextesActivation.infoB),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        for (final d in bascules)
          _Bascule(
            definition: d,
            peutEcrire: peutEcrire,
            onBasculer: () => onBasculer(d),
          ),
        for (final (titre, cellules) in groupes)
          separe(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TitreSection(titre),
                _Grille(enfants: cellules),
              ],
            ),
          ),
        separe(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _TitreSection(_TextesActivation.sectionSuppression),
              Text.rich(
                TextSpan(
                  style: _styleActivation(TaillesContenu.t15),
                  children: [
                    const TextSpan(text: _TextesActivation.rappelA),
                    const TextSpan(text: ' '),
                    const TextSpan(
                      text: _TextesActivation.rappelFort,
                      style: fort,
                    ),
                    const TextSpan(text: _TextesActivation.rappelB),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: InkWell(
                        key: const Key('param-rappel-restaurer'),
                        onTap: versRestauration,
                        child: Text(
                          _TextesActivation.rappelLien,
                          style: _styleActivation(
                            TaillesContenu.t15,
                            poids: FontWeight.w600,
                            couleur: AppColors.navy,
                          ).copyWith(decoration: TextDecoration.underline),
                        ),
                      ),
                    ),
                    const TextSpan(text: _TextesActivation.rappelC),
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

/// Une rangée de bascule (`flex items-start gap-3 rounded-lg border
/// border-slate-200 p-3.5`) : l'interrupteur `role="switch"`, le titre et la
/// pastille de risque, l'aide du registre — et, quand l'aide du serveur
/// promet plus que ce poste ne fait, la correction « Sur ce poste : … ».
class _Bascule extends StatelessWidget {
  const _Bascule({
    required this.definition,
    required this.peutEcrire,
    required this.onBasculer,
  });

  final DefinitionParametre definition;
  final bool peutEcrire;
  final VoidCallback onBasculer;

  @override
  Widget build(BuildContext context) {
    final active = OptionsSysteme.actif(definition.cle, definition.valeur);
    final risque = _risqueDe(definition.cle);
    return Container(
      key: Key('param-bascule-${definition.cle}'),
      margin: const EdgeInsets.only(bottom: AppSpacing.xsPlus), // space-y-2.5
      padding: const EdgeInsets.all(AppSpacing.smPlus), // p-3.5
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.neutre200),
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.demi), // mt-0.5
            child: Semantics(
              toggled: active,
              label: definition.libelle,
              child: GestureDetector(
                key: Key('param-bascule-interrupteur-${definition.cle}'),
                // `disabled` sans le droit d'écrire : l'interrupteur se voit,
                // il ne répond pas.
                onTap: peutEcrire ? onBasculer : null,
                child: Container(
                  width: MesuresBasculeActivation.largeur,
                  height: MesuresBasculeActivation.hauteur,
                  decoration: BoxDecoration(
                    color: active
                        ? AppColors.succes
                        : MesuresBasculeActivation.pisteInactive,
                    borderRadius: BorderRadius.circular(AppRadius.roundedFull),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        top: MesuresBasculeActivation.haut,
                        left: active
                            ? MesuresBasculeActivation.decalageActif
                            : MesuresBasculeActivation.decalageInactif,
                        child: Container(
                          width: MesuresBasculeActivation.curseur,
                          height: MesuresBasculeActivation.curseur,
                          decoration: const BoxDecoration(
                            color: AppColors.neutre0,
                            shape: BoxShape.circle,
                            boxShadow: AppShadows.tailwindSm,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm), // gap-3
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppSpacing.xs, // gap-2
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      definition.libelle,
                      style: _styleActivation(
                        TaillesContenu.t15,
                        poids: FontWeight.w600,
                        couleur: AppColors.neutre700,
                      ),
                    ),
                    Container(
                      padding: MesuresBasculeActivation.margePastille,
                      decoration: BoxDecoration(
                        color: risque.fond,
                        borderRadius: BorderRadius.circular(AppRadius.rounded),
                      ),
                      child: Text(
                        risque.libelle,
                        style: _styleActivation(
                          TaillesContenu.t11,
                          poids: FontWeight.bold,
                          couleur: risque.texte,
                        ),
                      ),
                    ),
                  ],
                ),
                if (definition.aide != null) ...[
                  const SizedBox(height: AppSpacing.demi), // mt-0.5
                  Text(
                    aideAffichee(definition.aide!),
                    style: _styleActivation(TaillesContenu.t13),
                  ),
                ],
                if (definition.correction != null) ...[
                  const SizedBox(height: AppSpacing.unit),
                  Text(
                    definition.correction!,
                    key: Key('param-correction-${definition.cle}'),
                    style: _styleActivation(
                      TaillesContenu.t12,
                      couleur: AppColors.neutre700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
