/// Le démarrage RÉSILIENT du poste (PRD réinstallation, exigence R1).
///
/// Ordre voulu : la fenêtre s'ouvre tout de suite sur l'écran d'attente
/// « Mise à jour de la base du poste… », la base est ouverte ET migrée, et
/// SEULEMENT ENSUITE le premier écran métier est construit. Toute erreur — du
/// démarrage lui-même, de `FlutterError.onError`, de `PlatformDispatcher` ou de
/// la zone — est écrite dans `demarrage.log` ; avant que l'application soit
/// prête, elle remplace l'écran par l'écran de panne. Jamais une fenêtre vide.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../database/app_database.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../theme/mesures_ecran_panne.dart';
import 'journal_demarrage.dart';
import 'textes_demarrage.dart';

/// Au-delà, la préparation est déclarée bloquée.
const Duration delaiPreparationBloquee = Duration(seconds: 45);

/// Une erreur de démarrage retenue pour l'écran de panne.
class ErreurDemarrage {
  const ErreurDemarrage(this.erreur, this.pile);
  final Object erreur;
  final StackTrace? pile;
}

/// Les gestes de l'écran de panne, injectables pour les tests.
class ActionsPanne {
  const ActionsPanne({
    this.copier = _copierPressePapiers,
    this.ouvrirDossier = _ouvrirDossier,
    this.quitter = _quitter,
  });
  final Future<void> Function(String texte) copier;
  final Future<void> Function(String chemin) ouvrirDossier;
  final Future<void> Function() quitter;
}

Future<void> _copierPressePapiers(String texte) =>
    Clipboard.setData(ClipboardData(text: texte));

Future<void> _ouvrirDossier(String chemin) async {
  final commande = Platform.isWindows
      ? 'explorer'
      : (Platform.isMacOS ? 'open' : 'xdg-open');
  await Process.start(commande, [chemin], mode: ProcessStartMode.detached);
}

Future<void> _quitter() async => exit(0);

/// Reçoit toutes les erreurs et les écrit au journal ; retient la première
/// tant que l'application n'est pas prête.
class ControleurDemarrage extends ChangeNotifier {
  JournalDemarrage? _journal;
  final List<String> _enAttente = [];
  ErreurDemarrage? _panne;
  bool _prete = false;

  JournalDemarrage? get journal => _journal;
  ErreurDemarrage? get panne => _panne;
  bool get prete => _prete;

  /// Branche le journal et y verse ce qui s'est dit avant lui.
  void attacherJournal(JournalDemarrage journal) {
    _journal = journal;
    for (final l in _enAttente) {
      journal.ecrire(l);
    }
    _enAttente.clear();
  }

  void noter(String ligne) {
    final j = _journal;
    if (j == null) {
      _enAttente.add(ligne);
    } else {
      j.ecrire(ligne);
    }
  }

  /// Signale une erreur : journal d'abord, écran de panne ensuite si
  /// l'application n'est pas encore ouverte.
  void signaler(String contexte, Object erreur, StackTrace? pile) {
    final j = _journal;
    if (j == null) {
      _enAttente.add('ERREUR $contexte : $erreur\n${pile ?? ''}');
    } else {
      j.ecrireErreur(contexte, erreur, pile);
    }
    if (!_prete && _panne == null) {
      _panne = ErreurDemarrage(erreur, pile);
      notifyListeners();
    }
  }

  void marquerPrete() {
    _prete = true;
    notifyListeners();
  }
}

/// Ouvre la base du poste et force sa migration (sinon paresseuse, au premier
/// accès, donc APRÈS le premier écran).
Future<AppDatabase> ouvrirBaseDuPoste(JournalDemarrage? journal) async {
  final base = AppDatabase();
  base.journalDemarrage = journal?.ecrire;
  try {
    await base.customSelect('SELECT 1').get();
  } on Object {
    try {
      await base.close();
    } on Object {
      // La cause d'origine prime.
    }
    rethrow;
  }
  return base;
}

/// L'enveloppe racine : attente, panne ou application.
class DemarrageResilient extends StatefulWidget {
  const DemarrageResilient({
    super.key,
    required this.controleur,
    required this.preparer,
    required this.construire,
    this.delai = delaiPreparationBloquee,
    this.actions = const ActionsPanne(),
    this.dossierDonnees,
  });

  final ControleurDemarrage controleur;

  /// Ouvre et migre la base (et tout ce qui doit être prêt avant l'écran métier).
  final Future<AppDatabase> Function() preparer;

  /// Construit l'application une fois la base prête.
  final Widget Function(AppDatabase base) construire;

  final Duration delai;
  final ActionsPanne actions;
  final String? dossierDonnees;

  @override
  State<DemarrageResilient> createState() => _EtatDemarrage();
}

class _EtatDemarrage extends State<DemarrageResilient> {
  AppDatabase? _base;
  bool _bloquee = false;
  Timer? _minuteur;

  @override
  void initState() {
    super.initState();
    widget.controleur.addListener(_actualiser);
    _minuteur = Timer(widget.delai, () {
      if (_base == null && widget.controleur.panne == null) {
        widget.controleur.noter(
          'ALERTE préparation bloquée : plus de ${widget.delai.inSeconds} s '
          'sans que la base soit prête.',
        );
        setState(() => _bloquee = true);
      }
    });
    unawaited(_demarrer());
  }

  Future<void> _demarrer() async {
    try {
      final base = await widget.preparer();
      widget.controleur.noter('Base prête : premier écran métier.');
      _minuteur?.cancel();
      if (!mounted) return;
      widget.controleur.marquerPrete();
      setState(() => _base = base);
    } on Object catch (e, s) {
      _minuteur?.cancel();
      widget.controleur.signaler('ouverture de la base', e, s);
    }
  }

  void _actualiser() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _minuteur?.cancel();
    widget.controleur.removeListener(_actualiser);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = _base;
    if (base != null) return widget.construire(base);
    final panne = widget.controleur.panne;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.clair,
      home: panne != null || _bloquee
          ? EcranPanneDemarrage(
              titre: panne != null
                  ? TextesDemarrage.titrePanne
                  : TextesDemarrage.titreBloquee,
              explication: panne != null
                  ? TextesDemarrage.explicationPanne
                  : TextesDemarrage.explicationBloquee,
              cause: panne == null
                  ? TextesDemarrage.explicationBloquee
                  : TextesDemarrage.cause(panne.erreur),
              pile: panne?.pile,
              cheminJournal: widget.controleur.journal?.chemin,
              dossierDonnees: widget.dossierDonnees,
              actions: widget.actions,
              journal: widget.controleur.journal,
            )
          : const _EcranAttente(),
    );
  }
}

class _EcranAttente extends StatelessWidget {
  const _EcranAttente();

  @override
  Widget build(BuildContext context) {
    final texte = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: AppColors.fondClair,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: MesuresEcranPanne.coteAttente,
              height: MesuresEcranPanne.coteAttente,
              child: CircularProgressIndicator(
                strokeWidth: MesuresEcranPanne.epaisseurAttente,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(TextesDemarrage.attente, style: texte.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(TextesDemarrage.attenteExplication, style: texte.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// L'écran « L'application ne peut pas démarrer ».
class EcranPanneDemarrage extends StatelessWidget {
  const EcranPanneDemarrage({
    super.key,
    required this.titre,
    required this.explication,
    required this.cause,
    required this.actions,
    this.pile,
    this.cheminJournal,
    this.dossierDonnees,
    this.journal,
  });

  final String titre;
  final String explication;
  final String cause;
  final StackTrace? pile;
  final String? cheminJournal;
  final String? dossierDonnees;
  final ActionsPanne actions;
  final JournalDemarrage? journal;

  String get _detail {
    final brut =
        '$titre\n${TextesDemarrage.libelleCause} : $cause\n'
        '${TextesDemarrage.libelleJournal} : '
        '${cheminJournal ?? TextesDemarrage.journalIndisponible}'
        '${pile == null ? '' : '\n$pile'}';
    return journal?.expurger(brut) ?? brut;
  }

  @override
  Widget build(BuildContext context) {
    final texte = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: AppColors.fondClair,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: MesuresEcranPanne.largeurCarte,
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titre,
                  key: const ValueKey('panne-titre'),
                  style: texte.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(explication, style: texte.bodyMedium),
                const SizedBox(height: AppSpacing.md),
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxHeight: MesuresEcranPanne.hauteurDetail,
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      _detail,
                      key: const ValueKey('panne-detail'),
                      style: texte.bodySmall,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    FilledButton(
                      key: const ValueKey('panne-copier'),
                      onPressed: () => actions.copier(_detail),
                      child: const Text(TextesDemarrage.copier),
                    ),
                    OutlinedButton(
                      key: const ValueKey('panne-dossier'),
                      onPressed: dossierDonnees == null
                          ? null
                          : () => actions.ouvrirDossier(dossierDonnees!),
                      child: const Text(TextesDemarrage.ouvrirDossier),
                    ),
                    OutlinedButton(
                      key: const ValueKey('panne-quitter'),
                      onPressed: actions.quitter,
                      child: const Text(TextesDemarrage.quitter),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Branche les trois filets globaux sur [controleur] et rend le gestionnaire
/// de zone.
void brancherFilets(ControleurDemarrage controleur) {
  final precedent = FlutterError.onError;
  FlutterError.onError = (details) {
    controleur.signaler('FlutterError', details.exception, details.stack);
    precedent?.call(details);
  };
  PlatformDispatcher.instance.onError = (erreur, pile) {
    controleur.signaler('PlatformDispatcher', erreur, pile);
    return true;
  };
}
