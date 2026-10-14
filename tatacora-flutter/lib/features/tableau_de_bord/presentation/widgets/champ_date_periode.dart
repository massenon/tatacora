import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';

/// Une borne de la période du tableau de bord — le `<input type="date">` de la
/// vue d'accueil : `text-[13px] border border-slate-300 rounded-lg px-2.5
/// py-2` (en-tête, « Période personnalisée », et barre du pilotage).
///
/// Vide, il dit ce que dit le contrôle natif du navigateur (« jj/mm/aaaa ») :
/// aucune date n'est devinée. Le choix passe par le calendrier de Flutter ;
/// [initiale] est la date proposée à l'ouverture quand le champ est vide
/// (l'horloge du tableau de bord, jamais l'heure réelle d'un test).
///
/// ## Il se VIDE, comme le contrôle natif (12/10/2026)
///
/// Dans la vue, l'`<input type="date">` se vide (touche Suppr, ou la croix du
/// navigateur) : `$du` / `$au` reçoivent `''` et `Periode::resoudre` retombe
/// sur le mois courant. Le calendrier de Flutter n'offre aucun « effacer » ;
/// une croix ([onEffacer]) tient ce geste à l'intérieur du champ, à la place
/// de l'indicateur de calendrier du navigateur, et seulement quand une date
/// est posée — sur un champ vide, elle n'aurait rien à faire (Article 3.3).
class ChampDatePeriode extends StatelessWidget {
  const ChampDatePeriode({
    required Key cle,
    required this.titre,
    required this.valeur,
    required this.initiale,
    required this.onChoix,
    this.onEffacer,
  }) : super(key: cle);

  /// L'attribut `title` de la vue (« Du » / « Au ») : l'infobulle du champ.
  final String titre;
  final DateTime? valeur;
  final DateTime initiale;
  final ValueChanged<DateTime> onChoix;

  /// Vider le champ — même effet que vider le contrôle natif de la vue.
  /// `null` : aucune croix.
  final VoidCallback? onEffacer;

  /// L'infobulle de la croix.
  static const String effacer = 'Effacer la date';

  /// Le texte d'un `<input type="date">` vide, locale française.
  static const String vide = 'jj/mm/aaaa';

  /// Les bornes du calendrier. La vue n'en pose aucune ; un calendrier Flutter
  /// en exige : elles sont larges plutôt que d'interdire une saisie légitime.
  static final DateTime _premier = DateTime(2000);
  static final DateTime _dernier = DateTime(2100, 12, 31);

  @override
  Widget build(BuildContext context) {
    final d = valeur;

    return Tooltip(
      message: titre,
      child: SizedBox(
        width: AppLayout.champDatePeriode,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.roundedLg),
          onTap: () async {
            final choisi = await showDatePicker(
              context: context,
              initialDate: d ?? initiale,
              firstDate: _premier,
              lastDate: _dernier,
            );
            if (choisi == null) return;
            onChoix(choisi);
          },
          child: Container(
            // `px-2.5 py-2` — 10 px et 8 px.
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xsPlus,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: AppColors.neutre0,
              borderRadius: BorderRadius.circular(AppRadius.roundedLg),
              border: Border.all(color: Ardoise.c300),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    d == null
                        ? vide
                        : '${d.day.toString().padLeft(2, '0')}/'
                              '${d.month.toString().padLeft(2, '0')}/${d.year}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: TaillesContenu.t13,
                      color: d == null ? Ardoise.c400 : Ardoise.c700,
                    ),
                  ),
                ),
                if (d != null && onEffacer != null)
                  Tooltip(
                    message: effacer,
                    child: InkWell(
                      key: key is ValueKey<String>
                          ? Key('${(key! as ValueKey<String>).value}-effacer')
                          : null,
                      onTap: onEffacer,
                      child: const Icon(
                        Icons.close,
                        size: AppLayout.iconeChamp,
                        color: Ardoise.c400,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
