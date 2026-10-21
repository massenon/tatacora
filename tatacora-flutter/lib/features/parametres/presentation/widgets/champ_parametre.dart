// Vue Blade maîtresse (PA-183) : pwa/transverse/parametres.blade.php
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/entities/parametre.dart';

/// L'aide du serveur telle qu'elle s'AFFICHE : sans code interne de suivi.
///
/// Directive absolue du PO (14/10/2026) : aucun texte visible ne cite un code
/// PA-xx. L'aide reste celle du serveur, MOT POUR MOT, dans le registre (un
/// test la confronte au PHP) ; seul le rendu retire la parenthèse
/// « (PA-08) » que `RegistreParametres` porte sur la rétention du journal
/// d'audit. Écart avec la vue, qui l'affiche : nommé ici.
String aideAffichee(String aide) =>
    aide.replaceAll(RegExp(r'\s*\(PA-\d+\)'), '');

/// Un champ de l'écran Paramètres, **rendu d'après le type déclaré par le
/// serveur**.
///
/// ## Un type inconnu ne devient PAS un champ texte
///
/// Le poste peut tourner une version plus ancienne que l'API : un type ajouté
/// côté serveur arrivera ici sans que ce fichier le connaisse. Le rendre en
/// texte libre par défaut laisserait saisir n'importe quoi dans un booléen ou
/// un montant, et le refus n'apparaîtrait qu'à l'enregistrement — sur un écran
/// qui semblait fonctionner. Le champ dit qu'il ne sait pas le rendre, montre
/// la valeur en place, et n'accepte aucune saisie.
class ChampParametre extends StatefulWidget {
  const ChampParametre({
    super.key,
    required this.definition,
    required this.saisie,
    required this.erreur,
    required this.modifiable,
    required this.onChange,
  });

  final DefinitionParametre definition;

  /// La saisie en cours, `null` si l'utilisateur n'a pas touché ce champ.
  final Object? saisie;

  final String? erreur;
  final bool modifiable;
  final ValueChanged<Object?> onChange;

  @override
  State<ChampParametre> createState() => _ChampParametreState();
}

class _ChampParametreState extends State<ChampParametre> {
  late final TextEditingController _controleur = TextEditingController(
    text: widget.definition.valeurTexte,
  );

  @override
  void didUpdateWidget(ChampParametre ancien) {
    super.didUpdateWidget(ancien);

    // « Annuler » vide les saisies : le champ doit revenir à la valeur du
    // serveur, pas conserver ce que l'utilisateur venait d'écrire.
    if (widget.saisie == null &&
        _controleur.text != widget.definition.valeurTexte) {
      _controleur.text = widget.definition.valeurTexte;
    }
  }

  @override
  void dispose() {
    _controleur.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.definition;
    final cle = Key('param-champ-${d.cle}');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        switch (d.type) {
          null => _TypeInconnu(definition: d),
          TypeParametre.booleen => SwitchListTile(
            key: cle,
            contentPadding: EdgeInsets.zero,
            title: Text(
              d.libelle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            value: widget.saisie as bool? ?? d.valeurBooleenne,
            onChanged: widget.modifiable ? widget.onChange : null,
          ),
          TypeParametre.choix => DropdownButtonFormField<String>(
            key: cle,
            initialValue: _choixCourant(d),
            decoration: InputDecoration(labelText: d.libelle, isDense: true),
            items: [
              for (final c in d.choix)
                DropdownMenuItem(value: c, child: Text(c)),
            ],
            onChanged: widget.modifiable ? widget.onChange : null,
          ),
          TypeParametre.entier ||
          TypeParametre.decimal => _texte(cle, d, numerique: true),
          TypeParametre.texte => _texte(cle, d, numerique: false),
        },
        if (d.aide != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.unit),
            child: Text(
              aideAffichee(d.aide!),
              key: Key('param-aide-${d.cle}'),
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: AppColors.neutre500),
            ),
          ),
        // Ce que CE POSTE ajoute à l'aide du serveur (secret refusé, « aucun
        // module ne lit cette valeur »), visible ICI plutôt qu'en infobulle :
        // c'est au moment de saisir qu'on a besoin de le savoir.
        for (final (i, note) in d.notes.indexed)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.unit),
            child: Text(
              note,
              key: Key('param-champ-note-${d.cle}-$i'),
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: AppColors.neutre500),
            ),
          ),
        if (widget.erreur != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.unit),
            child: Text(
              widget.erreur!,
              key: Key('param-erreur-${d.cle}'),
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: AppColors.erreur),
            ),
          ),
      ],
    );
  }

  /// La valeur du serveur n'est retenue que si elle appartient au registre de
  /// choix : une valeur hors registre ferait lever le `Dropdown`, et l'écran
  /// entier disparaîtrait au lieu de montrer le paramètre à corriger.
  String? _choixCourant(DefinitionParametre d) {
    final courant = widget.saisie as String? ?? d.valeur;
    return d.choix.contains(courant) ? courant : null;
  }

  Widget _texte(Key cle, DefinitionParametre d, {required bool numerique}) {
    return TextField(
      key: cle,
      controller: _controleur,
      enabled: widget.modifiable,
      keyboardType: numerique
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(labelText: d.libelle, isDense: true),
      // Une saisie VIDÉE part en chaîne vide, jamais en `null` : l'écran lit
      // `null` comme « champ non touché » et grise Enregistrer. Avec `null`,
      // un IFU erroné ne pouvait plus jamais être retiré (« vider » est un
      // état voulu : un IFU absent fait disparaître la mention du document
      // plutôt qu'imprimer un exemple de format). Constaté en branchant la
      // source locale, le 09/10/2026 : tant qu'aucune écriture n'aboutissait,
      // la différence ne se voyait pas.
      onChanged: (v) => widget.onChange(v.trim()),
    );
  }
}

class _TypeInconnu extends StatelessWidget {
  const _TypeInconnu({required this.definition});

  final DefinitionParametre definition;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: Key('param-type-inconnu-${definition.cle}'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.neutre100,
        borderRadius: BorderRadius.circular(AppSpacing.xs),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            definition.libelle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.unit),
          Text(
            'Valeur actuelle : ${definition.valeurTexte.isEmpty ? "(vide)" : definition.valeurTexte}',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          // `pwa.parametres.type_inconnu` (la vue), puis ce que le poste ajoute.
          Text(
            'Type non reconnu par cet écran : la valeur est affichée telle que le serveur la stocke, sans interprétation.',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          Text(
            'Ce poste ne sait pas éditer un paramètre de type '
            '« ${definition.typeBrut} » : mettez l’application à jour.',
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: AppColors.alerte),
          ),
        ],
      ),
    );
  }
}
