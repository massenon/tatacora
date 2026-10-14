/// Les trois modales de M12 — les mots du maître, sans adoucissement.
///
/// Maître : `pwa/notifications/hub.blade.php` l.565-665.
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/entities/canal_notification.dart';
import '../../domain/entities/declencheur_notification.dart';
import '../../domain/entities/modele_notification.dart';

/// Ce que la modale « modèle » rend au rappelant.
final class SaisieModele {
  const SaisieModele({
    required this.declencheur,
    required this.canal,
    required this.contenu,
    required this.actif,
    this.objet,
  });

  final DeclencheurNotification declencheur;
  final CanalNotification canal;
  final String contenu;
  final String? objet;
  final bool actif;
}

/// « Nouveau modèle » / « Modifier le modèle » — maître l.565-620.
///
/// Le déclencheur est VERROUILLÉ à l'édition, comme au maître (son `<select>`
/// est `disabled`) : changer l'événement d'un modèle reviendrait à en créer un
/// autre en perdant la trace du premier.
Future<SaisieModele?> demanderModele(
  BuildContext context, {
  ModeleNotification? existant,
}) => showDialog<SaisieModele>(
  context: context,
  builder: (_) => _ModaleModele(existant: existant),
);

class _ModaleModele extends StatefulWidget {
  const _ModaleModele({this.existant});

  final ModeleNotification? existant;

  @override
  State<_ModaleModele> createState() => _ModaleModeleState();
}

class _ModaleModeleState extends State<_ModaleModele> {
  late DeclencheurNotification _declencheur;
  late CanalNotification _canal;
  late final TextEditingController _objet;
  late final TextEditingController _contenu;
  late bool _actif;
  String? _erreur;

  bool get _edition => widget.existant != null;

  @override
  void initState() {
    super.initState();
    final m = widget.existant;
    _declencheur = m?.declencheur ?? DeclencheurNotification.values.first;
    _canal = m?.canal ?? CanalNotification.whatsapp;
    _objet = TextEditingController(text: m?.objet ?? '');
    _contenu = TextEditingController(text: m?.contenuTemplate ?? '');
    _actif = m?.actif ?? true;
  }

  @override
  void dispose() {
    _objet.dispose();
    _contenu.dispose();
    super.dispose();
  }

  void _enregistrer() {
    if (_contenu.text.trim().isEmpty) {
      setState(() => _erreur = 'Le contenu du message est obligatoire.');
      return;
    }

    Navigator.of(context).pop(
      SaisieModele(
        declencheur: _declencheur,
        canal: _canal,
        contenu: _contenu.text,
        objet: _objet.text,
        actif: _actif,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(_edition ? 'Modifier le modèle' : 'Nouveau modèle'),
      content: SizedBox(
        width: AppLayout.modaleModeleNotification,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _Champ(
                      libelle: 'Déclencheur',
                      obligatoire: true,
                      enfant: DropdownButtonFormField<DeclencheurNotification>(
                        key: const Key('notifications-modale-declencheur'),
                        initialValue: _declencheur,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final d in DeclencheurNotification.values)
                            DropdownMenuItem(value: d, child: Text(d.libelle)),
                        ],
                        // Verrouillé à l'édition — le maître fait de même.
                        onChanged: _edition
                            ? null
                            : (d) => setState(
                                () => _declencheur = d ?? _declencheur,
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _Champ(
                      libelle: 'Canal',
                      obligatoire: true,
                      enfant: DropdownButtonFormField<CanalNotification>(
                        key: const Key('notifications-modale-canal'),
                        initialValue: _canal,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final c in CanalNotification.values)
                            DropdownMenuItem(value: c, child: Text(c.libelle)),
                        ],
                        onChanged: (c) => setState(() => _canal = c ?? _canal),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              _Champ(
                libelle: 'Objet',
                aide: '(e-mail et push)',
                enfant: TextField(
                  key: const Key('notifications-modale-objet'),
                  controller: _objet,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              _Champ(
                libelle: 'Message',
                obligatoire: true,
                enfant: TextField(
                  key: const Key('notifications-modale-message'),
                  controller: _contenu,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                'Variables : '
                '${_declencheur.variables.map((v) => '{$v}').join(' ')}',
                style: theme.textTheme.labelMedium,
              ),
              if (_erreur != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    _erreur!,
                    key: const Key('notifications-modale-erreur'),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: PaletteMaitre.rouge600,
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.xs),
              InkWell(
                onTap: () => setState(() => _actif = !_actif),
                child: Row(
                  children: [
                    Checkbox(
                      key: const Key('notifications-modale-actif'),
                      value: _actif,
                      onChanged: (v) => setState(() => _actif = v ?? _actif),
                    ),
                    Expanded(
                      child: Text(
                        'Modèle actif — il sera pris en compte à la prochaine '
                        'détection',
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const Key('notifications-modale-enregistrer'),
          onPressed: _enregistrer,
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

/// Ce que la modale « Transmis à la main » rend.
///
/// Un objet plutôt qu'une `String?` : le commentaire est FACULTATIF, et
/// `null` doit pouvoir dire « annulé » sans se confondre avec « validé sans
/// commentaire ».
final class SaisieTransmission {
  const SaisieTransmission(this.commentaire);

  final String? commentaire;
}

/// « Message transmis hors du système » — maître l.629-645.
Future<SaisieTransmission?> demanderTransmission(BuildContext context) =>
    showDialog<SaisieTransmission>(
      context: context,
      builder: (_) => const _ModaleTransmission(),
    );

class _ModaleTransmission extends StatefulWidget {
  const _ModaleTransmission();

  @override
  State<_ModaleTransmission> createState() => _ModaleTransmissionState();
}

class _ModaleTransmissionState extends State<_ModaleTransmission> {
  final _commentaire = TextEditingController();

  @override
  void dispose() {
    _commentaire.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Message transmis hors du système'),
      content: SizedBox(
        width: AppLayout.modaleGesteNotification,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Les mots du maître, mot pour mot : c'est cette phrase qui
            // empêche de lire « transmis » comme « envoyé par le logiciel ».
            Text(
              'Il sortira de la file, mais restera marqué « non envoyé par le '
              'système ». Ce n’est pas le logiciel qui l’a fait partir : la '
              'distinction doit rester lisible à l’audit.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            _Champ(
              libelle: 'Comment a-t-il été transmis ?',
              enfant: TextField(
                key: const Key('notifications-transmission-commentaire'),
                controller: _commentaire,
                maxLines: 3,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const Key('notifications-transmission-confirmer'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.succes),
          onPressed: () =>
              Navigator.of(context).pop(SaisieTransmission(_commentaire.text)),
          child: const Text('Sortir de la file'),
        ),
      ],
    );
  }
}

/// « Abandonner ce message » — maître l.649-665.
///
/// Le motif est OBLIGATOIRE, et la modale le tient elle-même : un message qui
/// ne partira jamais doit dire pourquoi. Le DAO le revérifie — ce contrôle-ci
/// est une politesse d'interface, pas la garantie.
Future<String?> demanderAbandon(BuildContext context) => showDialog<String>(
  context: context,
  builder: (_) => const _ModaleAbandon(),
);

class _ModaleAbandon extends StatefulWidget {
  const _ModaleAbandon();

  @override
  State<_ModaleAbandon> createState() => _ModaleAbandonState();
}

class _ModaleAbandonState extends State<_ModaleAbandon> {
  final _motif = TextEditingController();
  String? _erreur;

  @override
  void dispose() {
    _motif.dispose();
    super.dispose();
  }

  void _confirmer() {
    if (_motif.text.trim().isEmpty) {
      setState(() => _erreur = 'Le motif de l’abandon est obligatoire.');
      return;
    }
    Navigator.of(context).pop(_motif.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Abandonner ce message'),
      content: SizedBox(
        width: AppLayout.modaleGesteNotification,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Il ne sera jamais envoyé. Le message reste au journal, marqué '
              'abandonné, avec son motif.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            _Champ(
              libelle: 'Motif de l’abandon',
              obligatoire: true,
              enfant: TextField(
                key: const Key('notifications-abandon-motif'),
                controller: _motif,
                maxLines: 3,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            if (_erreur != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  _erreur!,
                  key: const Key('notifications-abandon-erreur'),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: PaletteMaitre.rouge600,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const Key('notifications-abandon-confirmer'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.erreur),
          onPressed: _confirmer,
          child: const Text('Abandonner'),
        ),
      ],
    );
  }
}

/// Une étiquette de champ du maître : libellé, astérisque rouge, aide grise.
class _Champ extends StatelessWidget {
  const _Champ({
    required this.libelle,
    required this.enfant,
    this.aide,
    this.obligatoire = false,
  });

  final String libelle;
  final Widget enfant;
  final String? aide;
  final bool obligatoire;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              libelle,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: Ardoise.c700,
              ),
            ),
            if (obligatoire)
              Text(
                ' *',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: PaletteMaitre.rouge500,
                ),
              ),
            if (aide != null)
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.unit),
                child: Text(aide!, style: theme.textTheme.labelMedium),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxs),
        enfant,
      ],
    );
  }
}
