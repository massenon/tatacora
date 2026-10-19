// Vue Blade maîtresse (PA-183) : pwa/transverse/contact-editeur.blade.php
/// Les deux modales de « Contactez l'éditeur » — « Envoyer un message » et
/// « Signaler un bug » — aux mots et aux champs de la vue (`<x-pwa.modale …
/// largeur="560px">`), dans le châssis partagé des modales
/// ([CoquilleModaleRestaurant]).
///
/// Chaque modale VALIDE comme le composant du serveur
/// (`ContactEditeur::envoyerMessage` / `signalerBug` : obligatoire, 255 / 4096
/// caractères, module du registre fermé), puis ÉCRIT par le geste qu'on lui
/// passe et se ferme sur le message écrit. L'ENVOI n'a pas lieu ici : l'écran
/// le tente après la fermeture, sans retenir la saisie (le poste ne doit
/// jamais rester figé sur une connexion qui ne vient pas).
///
/// ## Ce qui n'est pas porté, et pourquoi
///
/// « Capture d'écran (optionnel) » — PNG ou JPG, 2 Mo maximum : NON porté sur
/// ce poste. Le courriel du serveur joint la capture depuis son disque
/// public ; le poste n'a pas encore de pièce jointe à son envoi. Le
/// signalement part sans elle, ce que le serveur fait aussi quand le fichier
/// manque.
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/mesures_transverses.dart';
import '../../../../shared_widgets/bouton_standard.dart';
import '../../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import '../../domain/messages_editeur.dart';

/// Les textes des deux modales (`pwa.contact.*`), au mot.
abstract final class TextesModalesContact {
  static const String messageTitre = 'Envoyer un message';
  static const String messageSousTitre =
      "Question d'utilisation, demande d'évolution ou remarque générale.";
  static const String messageObjet = 'Objet';
  static const String messageObjetInvite =
      'ex : Question sur le module Comptabilité';
  static const String messageCorps = 'Message';
  static const String messageCorpsInvite =
      'Décrivez votre question ou suggestion...';
  static const String messageBouton = 'Envoyer le message';

  static const String bugTitre = 'Signaler un bug';
  static const String bugSousTitre =
      'Un comportement inattendu, un calcul douteux, un écran qui ne répond pas.';
  static const String bugModule = 'Module concerné';
  static const String bugModuleInvite = '-- Sélectionner --';
  static const String bugDescription = 'Description du problème';
  static const String bugDescriptionInvite =
      "Que s'est-il passé ? Qu'attendiez-vous ?";
  static const String bugEtapes = 'Étapes pour reproduire';
  static const String bugEtapesInvite = '1. Aller dans... 2. Cliquer sur...';
  static const String bugEtapesNote =
      "C'est le champ le plus utile du formulaire. Un bug que l'éditeur sait "
      "reproduire est corrigé ; un bug décrit sans ses étapes est d'abord une "
      'enquête.';
  static const String bugBouton = 'Signaler le bug';

  static const String annuler = 'Annuler';

  /// `validation.required` / `validation.max.string` du serveur.
  static String obligatoire(String champ) => 'Le champ $champ est obligatoire.';
  static String tropLong(String champ, int max) =>
      'Le champ $champ ne peut pas contenir plus de $max caractères.';
  static String moduleInvalide(String champ) =>
      'La valeur sélectionnée pour $champ est invalide.';
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
  color: Ardoise.c400,
);

/// `w-full border border-slate-200 rounded-lg px-3 py-2.5 text-sm`.
InputDecoration _decoration({String? invite}) {
  final bord = OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.roundedLg),
    borderSide: const BorderSide(color: Ardoise.c200),
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

/// Un texte obligatoire borné : l'erreur à afficher, ou `null`.
String? _verifier(String valeur, String champ, int max, {bool requis = true}) {
  final v = valeur.trim();
  if (requis && v.isEmpty) return TextesModalesContact.obligatoire(champ);
  if (v.length > max) return TextesModalesContact.tropLong(champ, max);
  return null;
}

/// Ouvre « Envoyer un message » ([TypeMessageEditeur.message]) ou « Signaler
/// un bug » ([TypeMessageEditeur.bug]). [enregistrer] ÉCRIT la saisie dans la
/// boîte d'envoi et rend le message écrit ; la modale se ferme sur lui
/// (`null` : annulée).
Future<MessageEditeur?> ouvrirModaleContact(
  BuildContext context, {
  required TypeMessageEditeur type,
  required Future<MessageEditeur> Function(SaisieMessageEditeur saisie)
  enregistrer,
}) => showDialog<MessageEditeur>(
  context: context,
  builder: (_) => _ModaleContact(type: type, enregistrer: enregistrer),
);

class _ModaleContact extends StatefulWidget {
  const _ModaleContact({required this.type, required this.enregistrer});

  final TypeMessageEditeur type;
  final Future<MessageEditeur> Function(SaisieMessageEditeur saisie)
  enregistrer;

  @override
  State<_ModaleContact> createState() => _ModaleContactState();
}

class _ModaleContactState extends State<_ModaleContact> {
  final _objet = TextEditingController();
  final _corps = TextEditingController();
  final _etapes = TextEditingController();
  String? _module;
  Map<String, String> _erreurs = const {};
  String? _refus;
  bool _enCours = false;

  bool get _bug => widget.type == TypeMessageEditeur.bug;

  @override
  void dispose() {
    _objet.dispose();
    _corps.dispose();
    _etapes.dispose();
    super.dispose();
  }

  Map<String, String> _valider() {
    final erreurs = <String, String>{};
    void noter(String cle, String? erreur) {
      if (erreur != null) erreurs[cle] = erreur;
    }

    if (_bug) {
      final module = _module;
      if (module == null) {
        erreurs['module'] = TextesModalesContact.obligatoire('module concerné');
      } else if (!modulesContactEditeur.contains(module)) {
        erreurs['module'] = TextesModalesContact.moduleInvalide(
          'module concerné',
        );
      }
      noter(
        'corps',
        _verifier(
          _corps.text,
          'description du problème',
          BornesMessageEditeur.texte,
        ),
      );
      noter(
        'etapes',
        _verifier(
          _etapes.text,
          'étapes pour reproduire',
          BornesMessageEditeur.texte,
          requis: false,
        ),
      );
    } else {
      noter(
        'objet',
        _verifier(_objet.text, 'objet', BornesMessageEditeur.sujet),
      );
      noter(
        'corps',
        _verifier(_corps.text, 'message', BornesMessageEditeur.texte),
      );
    }
    return erreurs;
  }

  Future<void> _soumettre() async {
    final erreurs = _valider();
    if (erreurs.isNotEmpty) {
      setState(() => _erreurs = erreurs);
      return;
    }
    setState(() {
      _enCours = true;
      _erreurs = const {};
      _refus = null;
    });
    final etapes = _etapes.text.trim();
    final SaisieMessageEditeur saisie = _bug
        ? (
            type: TypeMessageEditeur.bug,
            sujet: sujetBug(_module!),
            moduleConcerne: _module,
            corps: _corps.text.trim(),
            etapes: etapes.isEmpty ? null : etapes,
          )
        : (
            type: TypeMessageEditeur.message,
            sujet: _objet.text.trim(),
            moduleConcerne: null,
            corps: _corps.text.trim(),
            etapes: null,
          );
    try {
      final ecrit = await widget.enregistrer(saisie);
      if (mounted) Navigator.of(context).pop(ecrit);
    } on Object catch (erreur) {
      // L'écriture LOCALE a échoué (base indisponible) : la saisie reste
      // là, et la raison est dite dans la modale.
      if (mounted) {
        setState(() {
          _enCours = false;
          _refus = '$erreur';
        });
      }
    }
  }

  List<Widget> _champ({
    required String cle,
    required String etiquette,
    required TextEditingController controleur,
    required String invite,
    required int lignes,
    bool obligatoire = true,
    String? note,
  }) => [
    EtiquetteChampRestaurant(texte: etiquette, obligatoire: obligatoire),
    TextField(
      key: Key('contact-saisie-$cle'),
      controller: controleur,
      enabled: !_enCours,
      minLines: lignes,
      maxLines: lignes,
      style: _saisie,
      decoration: _decoration(invite: invite),
    ),
    if (note != null) ...[
      const SizedBox(height: AppSpacing.xxs),
      Text(note, style: _aide),
    ],
    if (_erreurs[cle] != null) ...[
      const SizedBox(height: AppSpacing.unit),
      Text(_erreurs[cle]!, key: Key('contact-erreur-$cle'), style: _erreur),
    ],
  ];

  @override
  Widget build(BuildContext context) {
    final corps = _bug
        ? <Widget>[
            const EtiquetteChampRestaurant(
              texte: TextesModalesContact.bugModule,
              obligatoire: true,
            ),
            DropdownButtonFormField<String>(
              key: const Key('contact-saisie-module'),
              initialValue: _module,
              isExpanded: true,
              style: _saisie,
              hint: Text(
                TextesModalesContact.bugModuleInvite,
                style: _saisie.copyWith(color: Ardoise.c400),
              ),
              decoration: _decoration(),
              items: [
                for (final m in modulesContactEditeur)
                  DropdownMenuItem(value: m, child: Text(m)),
              ],
              onChanged: _enCours ? null : (v) => setState(() => _module = v),
            ),
            if (_erreurs['module'] != null) ...[
              const SizedBox(height: AppSpacing.unit),
              Text(
                _erreurs['module']!,
                key: const Key('contact-erreur-module'),
                style: _erreur,
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            ..._champ(
              cle: 'corps',
              etiquette: TextesModalesContact.bugDescription,
              controleur: _corps,
              invite: TextesModalesContact.bugDescriptionInvite,
              lignes: 4,
            ),
            const SizedBox(height: AppSpacing.md),
            ..._champ(
              cle: 'etapes',
              etiquette: TextesModalesContact.bugEtapes,
              controleur: _etapes,
              invite: TextesModalesContact.bugEtapesInvite,
              lignes: 3,
              obligatoire: false,
              note: TextesModalesContact.bugEtapesNote,
            ),
          ]
        : <Widget>[
            ..._champ(
              cle: 'objet',
              etiquette: TextesModalesContact.messageObjet,
              controleur: _objet,
              invite: TextesModalesContact.messageObjetInvite,
              lignes: 1,
            ),
            const SizedBox(height: AppSpacing.md),
            ..._champ(
              cle: 'corps',
              etiquette: TextesModalesContact.messageCorps,
              controleur: _corps,
              invite: TextesModalesContact.messageCorpsInvite,
              lignes: 6,
            ),
          ];

    return CoquilleModaleRestaurant(
      cle: Key(_bug ? 'contact-modale-bug' : 'contact-modale-message'),
      titre: _bug
          ? TextesModalesContact.bugTitre
          : TextesModalesContact.messageTitre,
      sousTitre: _bug
          ? TextesModalesContact.bugSousTitre
          : TextesModalesContact.messageSousTitre,
      largeur: MesuresTransverses.modaleContact,
      refus: _refus,
      cleRefus: const Key('contact-modale-refus'),
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: corps,
      ),
      actions: [
        BoutonStandard(
          key: const Key('contact-modale-annuler'),
          libelle: TextesModalesContact.annuler,
          taillePolice: Tailles.t13,
          margeHorizontale: AppSpacing.md,
          onPressed: _enCours ? null : () => Navigator.of(context).pop(),
        ),
        BoutonStandard(
          key: const Key('contact-modale-envoyer'),
          libelle: _bug
              ? TextesModalesContact.bugBouton
              : TextesModalesContact.messageBouton,
          variante: _bug ? VarianteBouton.erreur : VarianteBouton.primaire,
          taillePolice: Tailles.t13,
          onPressed: _enCours ? null : _soumettre,
        ),
      ],
    );
  }
}
