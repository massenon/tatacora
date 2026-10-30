import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/providers.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../shared_widgets/bouton_standard.dart';
import '../../../synchronisation/data/service_adresse_serveur.dart';
import '../../../synchronisation/domain/adresse_serveur.dart';
import '../../../synchronisation/domain/frequence_synchronisation.dart';
import '../../../synchronisation/presentation/providers_synchronisation.dart';
import '../../../transverse/data/configuration_poste.dart';
import '../../../transverse/domain/comptes_utilisateurs.dart';

/// Les mots des deux cartes « Adresse du serveur » et « Synchronisation
/// automatique » (29/10/2026). Un AJOUT du poste, comme l'onglet qui les porte :
/// la vue de Paramètres du serveur n'a pas d'onglet « Synchronisation ».
abstract final class TextesCartesAdresseServeur {
  static const titreAdresse = 'ADRESSE DU SERVEUR';
  static const champ = 'Adresse du serveur';
  static const aide = 'Adresse de l’espace web LogiReStock.';
  static String actuelle(String racine) => 'Actuelle : $racine';
  static const enregistrer = 'Enregistrer';
  static const tester = 'Tester la connexion';
  static const dejaCelle = 'Cette adresse est déjà celle du poste.';
  static String enregistree(String racine) =>
      'Adresse du serveur enregistrée : $racine.';
  static const jetonGarde =
      ' Le jeton d’appairage est conservé : s’il appartient à l’ancien '
      'serveur, le nouveau le refusera (401) et il faudra réappairer le poste.';
  static const jetonEfface =
      ' Le jeton a été effacé : réappairez le poste avec un compte du '
      'nouveau serveur.';
  static const reserve =
      'L’adresse du serveur est réservée aux Administrateurs.';

  static const titreJeton = 'Le poste est déjà appairé';
  static String texteJeton(String ancienne, String nouvelle) =>
      'Le jeton d’appairage appartient à l’ancien serveur ($ancienne). Avec '
      'le nouveau ($nouvelle), il serait refusé (401) tant que le poste ne '
      'sera pas réappairé. Les opérations en attente ne sont pas touchées.';
  static const garderJeton = 'Garder le jeton';
  static const effacerJeton = 'Effacer le jeton et réappairer';
  static const annuler = 'Annuler';
  static const titreEffacer = 'Effacer le jeton ?';
  static const texteEffacer =
      'Le poste ne sera plus appairé : il n’enverra rien avant un nouvel '
      'appairage. Le jeton reste valide sur l’ancien serveur jusqu’à sa '
      'révocation dans « Postes & Appairage ». La file d’envoi est conservée.';
  static const confirmerEffacer = 'Effacer le jeton';

  static const titreFrequence = 'SYNCHRONISATION AUTOMATIQUE';
  static const champFrequence = 'Fréquence';
}

enum _ChoixJeton { annuler, garder, effacer }

/// Les deux cartes, rendues dans l'onglet « Synchronisation » de Paramètres.
/// Réservées aux Administrateurs (`peutAdministrerComptes`), comme l'appairage.
class CartesAdresseServeur extends ConsumerStatefulWidget {
  const CartesAdresseServeur({super.key});

  @override
  ConsumerState<CartesAdresseServeur> createState() =>
      _CartesAdresseServeurState();
}

class _CartesAdresseServeurState extends ConsumerState<CartesAdresseServeur> {
  final _champ = TextEditingController();
  bool _touche = false;
  bool _occupe = false;
  String? _message;
  bool _messageErreur = false;
  String? _messageFrequence;

  @override
  void initState() {
    super.initState();
    ref.read(adresseServeurActuelleProvider.future).then((etat) {
      if (mounted && !_touche && etat != null) _champ.text = etat.racine;
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _champ.dispose();
    super.dispose();
  }

  void _dire(String message, {required bool erreur}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _messageErreur = erreur;
    });
  }

  String get _login => ref.read(sessionProvider)?.login ?? '';

  Future<void> _tester() async {
    setState(() => _occupe = true);
    try {
      final r = await ref
          .read(serviceAdresseServeurProvider)
          .tester(_champ.text);
      _dire(r.message, erreur: !r.succes);
    } on Object catch (e) {
      _dire('Opération impossible sur ce poste : $e', erreur: true);
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  Future<void> _enregistrer() async {
    if (!peutAdministrerComptes(ref.read(sessionProvider)?.role)) {
      _dire(TextesCartesAdresseServeur.reserve, erreur: true);
      return;
    }
    final saisie = validerAdresseServeur(_champ.text);
    if (saisie is AdresseInvalide) {
      _dire(saisie.message, erreur: true);
      return;
    }
    final adresse = (saisie as AdresseValide).adresse;
    setState(() => _occupe = true);
    try {
      final service = ref.read(serviceAdresseServeurProvider);
      final etat = await service.etat();
      if (etat == null) {
        _dire('La démonstration ne se synchronise jamais.', erreur: true);
        return;
      }
      if (etat.racine == adresse.racine) {
        _dire(TextesCartesAdresseServeur.dejaCelle, erreur: false);
        return;
      }
      var effacer = false;
      if (etat.appaire) {
        if (!mounted) return;
        final choix = await _demanderSortDuJeton(etat.racine, adresse.racine);
        if (choix == _ChoixJeton.annuler) return;
        if (choix == _ChoixJeton.effacer) {
          if (!mounted || !await _confirmerEffacement()) return;
          effacer = true;
        }
      }
      final r = await service.enregistrer(
        _champ.text,
        auteurLogin: _login,
        effacerJeton: effacer,
      );
      switch (r) {
        case AdresseRefusee(:final message):
          _dire(message, erreur: true);
        case AdresseInchangee():
          _dire(TextesCartesAdresseServeur.dejaCelle, erreur: false);
        case AdresseEnregistree(:final racine, :final jetonEfface):
          _champ.text = racine;
          ref
            ..invalidate(adresseServeurActuelleProvider)
            ..invalidate(appairageActuelProvider);
          _dire(
            TextesCartesAdresseServeur.enregistree(racine) +
                (jetonEfface
                    ? TextesCartesAdresseServeur.jetonEfface
                    : etat.appaire
                    ? TextesCartesAdresseServeur.jetonGarde
                    : ''),
            erreur: false,
          );
      }
    } on Object catch (e) {
      _dire('Opération impossible sur ce poste : $e', erreur: true);
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  Future<_ChoixJeton> _demanderSortDuJeton(
    String ancienne,
    String nouvelle,
  ) async {
    final choix = await showDialog<_ChoixJeton>(
      context: context,
      builder: (contexte) => AlertDialog(
        key: const Key('sync-adresse-dialogue-jeton'),
        title: Text(
          TextesCartesAdresseServeur.titreJeton,
          style: _style(TaillesContenu.t17, poids: FontWeight.w700),
        ),
        content: Text(
          TextesCartesAdresseServeur.texteJeton(ancienne, nouvelle),
          style: _style(TaillesContenu.t13, couleur: AppColors.neutre700),
        ),
        actions: [
          BoutonStandard(
            key: const Key('sync-adresse-annuler'),
            libelle: TextesCartesAdresseServeur.annuler,
            onPressed: () => Navigator.of(contexte).pop(_ChoixJeton.annuler),
          ),
          BoutonStandard(
            key: const Key('sync-adresse-garder-jeton'),
            libelle: TextesCartesAdresseServeur.garderJeton,
            onPressed: () => Navigator.of(contexte).pop(_ChoixJeton.garder),
          ),
          BoutonStandard(
            key: const Key('sync-adresse-effacer-jeton'),
            libelle: TextesCartesAdresseServeur.effacerJeton,
            variante: VarianteBouton.contourRouge,
            onPressed: () => Navigator.of(contexte).pop(_ChoixJeton.effacer),
          ),
        ],
      ),
    );
    return choix ?? _ChoixJeton.annuler;
  }

  Future<bool> _confirmerEffacement() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (contexte) => AlertDialog(
        key: const Key('sync-adresse-dialogue-effacer'),
        title: Text(
          TextesCartesAdresseServeur.titreEffacer,
          style: _style(TaillesContenu.t17, poids: FontWeight.w700),
        ),
        content: Text(
          TextesCartesAdresseServeur.texteEffacer,
          style: _style(TaillesContenu.t13, couleur: AppColors.neutre700),
        ),
        actions: [
          BoutonStandard(
            key: const Key('sync-adresse-effacer-annuler'),
            libelle: TextesCartesAdresseServeur.annuler,
            onPressed: () => Navigator.of(contexte).pop(false),
          ),
          BoutonStandard(
            key: const Key('sync-adresse-effacer-confirmer'),
            libelle: TextesCartesAdresseServeur.confirmerEffacer,
            variante: VarianteBouton.erreur,
            onPressed: () => Navigator.of(contexte).pop(true),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _changerFrequence(FrequenceSynchronisation f) async {
    try {
      await EcrivainConfigurationPoste(
        chemin: ref.read(cheminConfigurationPosteProvider),
      ).enregistrerFrequenceSynchronisation(f.minutes);
      ref.invalidate(frequenceSynchronisationProvider);
      if (mounted) {
        setState(
          () => _messageFrequence =
              TextesFrequenceSynchronisation.enregistree + f.libelle,
        );
      }
    } on Object catch (e) {
      if (mounted) {
        setState(
          () => _messageFrequence = 'Opération impossible sur ce poste : $e',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!peutAdministrerComptes(ref.watch(sessionProvider)?.role)) {
      return const SizedBox.shrink();
    }
    final etat = ref.watch(adresseServeurActuelleProvider).value;
    final frequence =
        ref.watch(frequenceSynchronisationProvider).value ??
        FrequenceSynchronisation.parDefaut;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _carte(
          cle: const Key('sync-carte-adresse'),
          titre: TextesCartesAdresseServeur.titreAdresse,
          enfants: [
            TextField(
              key: const Key('sync-adresse-champ'),
              controller: _champ,
              enabled: !_occupe,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
              maxLength: longueurMaxAdresseServeur,
              onChanged: (_) => _touche = true,
              decoration: const InputDecoration(
                labelText: TextesCartesAdresseServeur.champ,
                helperText: TextesCartesAdresseServeur.aide,
                counterText: '',
                isDense: true,
              ),
            ),
            if (etat != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                TextesCartesAdresseServeur.actuelle(etat.racine),
                key: const Key('sync-adresse-actuelle'),
                style: _style(TaillesContenu.t13, couleur: AppColors.neutre700),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                BoutonStandard(
                  key: const Key('sync-adresse-enregistrer'),
                  libelle: TextesCartesAdresseServeur.enregistrer,
                  variante: VarianteBouton.primaire,
                  onPressed: _occupe ? null : _enregistrer,
                ),
                BoutonStandard(
                  key: const Key('sync-adresse-tester'),
                  libelle: TextesCartesAdresseServeur.tester,
                  onPressed: _occupe ? null : _tester,
                ),
              ],
            ),
            if (_message != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _message!,
                key: const Key('sync-adresse-message'),
                style: _style(
                  TaillesContenu.t13,
                  poids: FontWeight.w600,
                  couleur: _messageErreur ? AppColors.erreur : AppColors.succes,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _carte(
          cle: const Key('sync-carte-frequence'),
          titre: TextesCartesAdresseServeur.titreFrequence,
          enfants: [
            InputDecorator(
              decoration: const InputDecoration(
                labelText: TextesCartesAdresseServeur.champFrequence,
                isDense: true,
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<FrequenceSynchronisation>(
                  key: const Key('sync-frequence'),
                  value: frequence,
                  isExpanded: true,
                  isDense: true,
                  items: [
                    for (final f in FrequenceSynchronisation.values)
                      DropdownMenuItem(
                        value: f,
                        child: Text(
                          f.libelle,
                          overflow: TextOverflow.ellipsis,
                          style: _style(TaillesContenu.t13),
                        ),
                      ),
                  ],
                  onChanged: (f) {
                    if (f != null) _changerFrequence(f);
                  },
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              TextesFrequenceSynchronisation.aide,
              key: const Key('sync-frequence-aide'),
              style: _style(TaillesContenu.t13, couleur: AppColors.neutre600),
            ),
            if (_messageFrequence != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _messageFrequence!,
                key: const Key('sync-frequence-message'),
                style: _style(
                  TaillesContenu.t13,
                  poids: FontWeight.w600,
                  couleur: AppColors.succes,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  static Widget _carte({
    required Key cle,
    required String titre,
    required List<Widget> enfants,
  }) => Container(
    key: cle,
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.neutre0,
      border: Border.all(color: AppColors.neutre200),
      borderRadius: BorderRadius.circular(AppRadius.md),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          titre,
          style: _style(
            TaillesContenu.t12,
            poids: FontWeight.w700,
            couleur: AppColors.neutre600,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        ...enfants,
      ],
    ),
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
