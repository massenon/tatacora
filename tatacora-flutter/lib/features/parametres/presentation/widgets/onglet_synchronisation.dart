import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/providers.dart';
import '../../../transverse/domain/comptes_utilisateurs.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared_widgets/bouton_standard.dart';
import '../../../synchronisation/domain/appairage.dart';
import '../../../synchronisation/presentation/providers_synchronisation.dart';
import '../../../transverse/data/configuration_poste.dart';

/// Les mots de l'onglet « Synchronisation » (lot F2a, 15/10/2026). La vue
/// de Paramètres n'a pas cet onglet : c'est un AJOUT du poste (le serveur
/// n'a pas à s'appairer à lui-même), décidé par le PO le 15/10/2026.
abstract final class TextesOngletSynchronisation {
  static const titre = 'Appairage du poste';
  static const intro =
      'Le poste enregistre tout sur place et envoie ses opérations au serveur '
      'en tâche de fond, sans jamais bloquer un écran. Pour cela, un '
      'Administrateur l’appaire UNE fois avec un compte du serveur : le mot '
      'de passe sert à obtenir un jeton, il n’est enregistré nulle part.';
  static const interrupteur = 'Synchronisation activée';
  static const aideActivee =
      'Le poste envoie ses opérations au serveur et reçoit le catalogue en '
      'tâche de fond.';
  static const aideDesactivee =
      'Désactivée : ce poste travaille seul, sans aucune connexion au '
      'serveur. Tout reste enregistré ici ; les opérations en attente '
      'partiront à la réactivation, dans l’ordre.';
  static const interrupteurEchec =
      'L’interrupteur n’a pas pu être enregistré : le fichier de '
      'configuration du poste est inaccessible.';
  static const champIdentifiant = 'Identifiant (compte serveur)';
  static const champMotDePasse = 'Mot de passe (compte serveur)';
  static const champNomPoste = 'Nom du poste';
  static const aideNomPoste =
      'Lettres, chiffres, « - », « _ », « . » — le nom sous lequel le serveur '
      'connaît ce poste.';
  static const appairer = 'Appairer le poste';
  static const reappairer = 'Réappairer le poste';
  static const tester = 'Tester la connexion';
  static const dissocier = 'Dissocier';
  static const synchroniser = 'Synchroniser maintenant';
  static const voirEcran = 'Voir la synchronisation';
  static const aideEcran =
      'La file d\'envoi, le catalogue reçu du serveur et les opérations à '
      'traiter sont détaillés sur l\'écran de synchronisation.';
  static const nonAppaire = 'Ce poste n’est pas appairé au serveur.';
  static String appaire(AppairagePoste a) =>
      'Appairé à ${a.serveur} — poste « ${a.posteId} », compte '
      '« ${a.compte} », depuis le ${_date(a.appaireLe)}.';
  static String refus(int code) => code == 403
      ? 'Le serveur ne reconnaît pas ce poste (403) : la synchronisation est '
            'suspendue — réappairer le poste.'
      : 'Le serveur refuse le jeton de ce poste (401) : la synchronisation '
            'est suspendue — réappairer le poste.';
  static const demonstration =
      'La démonstration ne se synchronise jamais : aucun appairage possible.';
  static const reserveAdministrateurs =
      'L’appairage du poste est réservé aux Administrateurs.';
  static String appairageReussi(AppairageReussi r) =>
      'Poste « ${r.posteId} » appairé (compte « ${r.compte} »).';

  static String _date(DateTime d) {
    final l = d.toLocal();
    String deux(int n) => n.toString().padLeft(2, '0');
    return '${deux(l.day)}/${deux(l.month)}/${l.year} à '
        '${deux(l.hour)}:${deux(l.minute)}';
  }
}

/// Le nom proposé par défaut : le nom Windows du poste (`COMPUTERNAME`),
/// nettoyé. Un test le remplace.
final nomPosteParDefautProvider = Provider<String>((ref) {
  final brut =
      Platform.environment['COMPUTERNAME'] ??
      (() {
        try {
          return Platform.localHostname;
        } on Object {
          return '';
        }
      })();
  return nettoyerNomPoste(brut) ?? '';
});

/// L'onglet « Synchronisation » de Paramètres : l'appairage du poste —
/// réservé aux Administrateurs, la même règle que « Comptes utilisateurs »
/// (`rolesAdministration`).
class OngletSynchronisation extends ConsumerStatefulWidget {
  const OngletSynchronisation({super.key});

  @override
  ConsumerState<OngletSynchronisation> createState() =>
      _OngletSynchronisationState();
}

class _OngletSynchronisationState extends ConsumerState<OngletSynchronisation> {
  final _identifiant = TextEditingController();
  final _motDePasse = TextEditingController();
  late final TextEditingController _nomPoste = TextEditingController(
    text: ref.read(nomPosteParDefautProvider),
  );
  bool _occupe = false;
  String? _message;
  bool _messageErreur = false;

  @override
  void dispose() {
    _identifiant.dispose();
    _motDePasse.dispose();
    _nomPoste.dispose();
    super.dispose();
  }

  Future<void> _geste(Future<(String, bool)> Function() action) async {
    setState(() {
      _occupe = true;
      _message = null;
    });
    (String, bool) issue;
    try {
      issue = await action();
    } on Object catch (e) {
      // Un fichier de configuration inaccessible, par exemple : la phrase le
      // dit, rien ne remonte.
      issue = ('Opération impossible sur ce poste : $e', true);
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
    if (!mounted) return;
    setState(() {
      _message = issue.$1;
      _messageErreur = issue.$2;
    });
    ref.invalidate(appairageActuelProvider);
  }

  Future<(String, bool)> _appairer() async {
    final resultat = await ref
        .read(serviceAppairageProvider)
        .appairer(
          identifiant: _identifiant.text,
          motDePasse: _motDePasse.text,
          nomPoste: _nomPoste.text,
        );
    switch (resultat) {
      case AppairageReussi():
        // Le mot de passe ne reste pas dans le champ.
        _motDePasse.clear();
        return (TextesOngletSynchronisation.appairageReussi(resultat), false);
      case AppairageRefuse(:final message):
        return (message, true);
    }
  }

  /// Le lien vers l'écran de synchronisation (lot F2b) — offert à qui voit
  /// l'onglet, administrateur ou non : l'écran se LIT avec le droit sur
  /// Paramètres, ses gestes restent réservés aux Administrateurs.
  Widget _lienEcran(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _ligne(
        TextesOngletSynchronisation.aideEcran,
        const Key('sync-aide-ecran'),
      ),
      const SizedBox(height: AppSpacing.xs),
      BoutonStandard(
        key: const Key('sync-ouvrir-ecran'),
        libelle: TextesOngletSynchronisation.voirEcran,
        onPressed: () => context.go('/synchronisation'),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    if (!peutAdministrerComptes(session?.role)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ligne(
            TextesOngletSynchronisation.reserveAdministrateurs,
            const Key('sync-reserve'),
          ),
          const SizedBox(height: AppSpacing.md),
          _lienEcran(context),
        ],
      );
    }
    if (ref.watch(synchronisationInterditeProvider) ||
        ref.watch(urlServeurSynchronisationProvider) == null) {
      return _ligne(
        TextesOngletSynchronisation.demonstration,
        const Key('sync-demonstration'),
      );
    }
    final appairage = ref.watch(appairageActuelProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          TextesOngletSynchronisation.titre,
          style: _style(TaillesContenu.t15, poids: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          TextesOngletSynchronisation.intro,
          style: _style(TaillesContenu.t13, couleur: AppColors.neutre600),
        ),
        const SizedBox(height: AppSpacing.md),
        _interrupteur(),
        const SizedBox(height: AppSpacing.md),
        appairage.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => _ligne('$e', const Key('sync-etat')),
          data: _etat,
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          key: const Key('sync-identifiant'),
          controller: _identifiant,
          enabled: !_occupe,
          decoration: const InputDecoration(
            labelText: TextesOngletSynchronisation.champIdentifiant,
            isDense: true,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          key: const Key('sync-mot-de-passe'),
          controller: _motDePasse,
          enabled: !_occupe,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: TextesOngletSynchronisation.champMotDePasse,
            isDense: true,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          key: const Key('sync-nom-poste'),
          controller: _nomPoste,
          enabled: !_occupe,
          decoration: const InputDecoration(
            labelText: TextesOngletSynchronisation.champNomPoste,
            helperText: TextesOngletSynchronisation.aideNomPoste,
            isDense: true,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            BoutonStandard(
              key: const Key('sync-appairer'),
              libelle: appairage.value == null
                  ? TextesOngletSynchronisation.appairer
                  : TextesOngletSynchronisation.reappairer,
              variante: VarianteBouton.primaire,
              onPressed: _occupe ? null : () => _geste(_appairer),
            ),
            if (appairage.value != null) ...[
              BoutonStandard(
                key: const Key('sync-tester'),
                libelle: TextesOngletSynchronisation.tester,
                onPressed: _occupe
                    ? null
                    : () => _geste(() async {
                        final m = await ref
                            .read(serviceAppairageProvider)
                            .testerConnexion();
                        return (m, !m.startsWith('Connexion établie'));
                      }),
              ),
              BoutonStandard(
                key: const Key('sync-maintenant'),
                libelle: TextesOngletSynchronisation.synchroniser,
                onPressed: _occupe
                    ? null
                    : () => _geste(() async {
                        final bilan = await ref
                            .read(syncManagerProvider)
                            .synchroniserMaintenant();
                        final descente = bilan.descente;
                        return (
                          '${bilan.etat.libelle} Envoyées : '
                              '${bilan.envoyees} (synchronisées '
                              '${bilan.synchronisees}, refusées '
                              '${bilan.rejetees}, conflits ${bilan.conflits}).'
                              '${descente == null ? '' : ' ${descente.etat.libelle}'}',
                          bilan.rejetees > 0 || bilan.conflits > 0,
                        );
                      }),
              ),
              BoutonStandard(
                key: const Key('sync-dissocier'),
                libelle: TextesOngletSynchronisation.dissocier,
                onPressed: _occupe
                    ? null
                    : () => _geste(() async {
                        final m = await ref
                            .read(serviceAppairageProvider)
                            .dissocier();
                        return (m, m != TextesAppairage.dissocie);
                      }),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _lienEcran(context),
        if (_message != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            _message!,
            key: const Key('sync-message'),
            style: _style(
              TaillesContenu.t13,
              poids: FontWeight.w600,
              couleur: _messageErreur ? AppColors.erreur : AppColors.succes,
            ),
          ),
        ],
      ],
    );
  }

  /// La bascule « Synchronisation activée » (Administrateurs).
  Widget _interrupteur() {
    final activee = ref.watch(synchronisationActiveeProvider).value ?? true;
    return SwitchListTile(
      key: const Key('sync-interrupteur'),
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(
        TextesOngletSynchronisation.interrupteur,
        style: _style(TaillesContenu.t13, poids: FontWeight.w600),
      ),
      subtitle: Text(
        activee
            ? TextesOngletSynchronisation.aideActivee
            : TextesOngletSynchronisation.aideDesactivee,
        key: const Key('sync-interrupteur-aide'),
        style: _style(TaillesContenu.t13, couleur: AppColors.neutre600),
      ),
      value: activee,
      onChanged: _occupe
          ? null
          : (v) => _geste(() async {
              await ref.read(basculerSynchronisationProvider)(
                v,
                par: ref.read(sessionProvider)?.login ?? '',
              );
              return (
                v
                    ? TextesOngletSynchronisation.aideActivee
                    : TextesOngletSynchronisation.aideDesactivee,
                false,
              );
            }),
    );
  }

  Widget _etat(AppairagePoste? a) {
    if (a == null) {
      return _ligne(
        TextesOngletSynchronisation.nonAppaire,
        const Key('sync-etat'),
      );
    }
    final refus = a.refus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ligne(TextesOngletSynchronisation.appaire(a), const Key('sync-etat')),
        if (refus != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              TextesOngletSynchronisation.refus(refus.codeHttp),
              key: const Key('sync-refus'),
              style: _style(
                TaillesContenu.t13,
                poids: FontWeight.w600,
                couleur: AppColors.erreur,
              ),
            ),
          ),
      ],
    );
  }

  static Widget _ligne(String texte, Key cle) => Text(
    texte,
    key: cle,
    style: _style(TaillesContenu.t13, couleur: AppColors.neutre700),
  );

  static TextStyle _style(
    double taille, {
    FontWeight poids = FontWeight.normal,
    Color couleur = AppColors.neutre900,
  }) => TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: taille,
    fontWeight: poids,
    color: couleur,
  );
}
