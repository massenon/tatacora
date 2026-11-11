// Vue Blade maîtresse (PA-183) : pwa/restaurant/restauration.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../data/restaurant_api.dart';
import '../../domain/calcul_restaurant.dart';
import '../../domain/entities/plat.dart';
import '../../domain/messages_restaurant.dart';
import '../providers_restaurant.dart';
import 'coquille_modale_restaurant.dart';
import 'textes_modale_restaurant.dart';

/// Les trois types de carte — `menu_type_local`, `menu_type_europeen`,
/// `menu_type_special`. Le registre est le FERMÉ du serveur ([typesDeMenu]) ; les
/// libellés sont ceux de la vue.
const Map<String, String> libellesTypesMenu = {
  'local': 'Local',
  'europeen': 'Européen',
  'special': 'Spécial',
};

/// La modale du formulaire de menu — création ou modification (EF-M4-01).
///
/// @see EF-M4-01 Gestion des menus et cartes
///
/// ## Ce que la vue pose, et ce qui est repris
///
/// Quatre champs, dans l'ordre de la vue : le nom, le type de carte, le début et
/// la fin de saison. Les dates ENCADRENT la saison, elles ne la déclarent pas :
/// vides, le menu est permanent, et rien ne remplace une date absente. Une fin
/// antérieure au début est refusée, avec la phrase du serveur — la carte ne
/// rendrait jamais aucun plat.
///
/// Le menu est écrit par `RestaurantDao.enregistrerMenu`, seul auteur de
/// `menus_local`. Rend le menu enregistré (`null` si la modale est fermée sans
/// enregistrer) : le formulaire de plat, d'où la modale peut être ouverte, le
/// présélectionne.
Future<MenuRestaurant?> ouvrirModaleMenu(
  BuildContext context, {
  MenuRestaurant? menu,
}) => showDialog<MenuRestaurant>(
  context: context,
  // Fermeture au voile — Article 4.6.
  barrierDismissible: true,
  barrierColor: AppColors.voileModale,
  builder: (_) => _ModaleMenu(menu: menu),
);

class _ModaleMenu extends ConsumerStatefulWidget {
  const _ModaleMenu({this.menu});

  final MenuRestaurant? menu;

  @override
  ConsumerState<_ModaleMenu> createState() => _ModaleMenuState();
}

class _ModaleMenuState extends ConsumerState<_ModaleMenu> {
  late final TextEditingController _libelle = TextEditingController(
    text: widget.menu?.libelle ?? '',
  );
  late final TextEditingController _debut = TextEditingController(
    text: widget.menu?.dateDebut ?? '',
  );
  late final TextEditingController _fin = TextEditingController(
    text: widget.menu?.dateFin ?? '',
  );

  /// Le premier type du registre à la création, comme la vue (`menuTypeSaisi`
  /// vaut `local`) : aucun type n'est « inventé », c'est le premier de la liste.
  late String _type = widget.menu?.typeBrut ?? typesDeMenu.first;

  bool _envoi = false;
  String? _refus;
  Map<String, String> _parChamp = const {};

  bool get _modification => widget.menu != null;

  @override
  void dispose() {
    _libelle.dispose();
    _debut.dispose();
    _fin.dispose();
    super.dispose();
  }

  Future<void> _enregistrer() async {
    setState(() {
      _envoi = true;
      _refus = null;
      _parChamp = const {};
    });

    final messager = ScaffoldMessenger.of(context);
    final navigateur = Navigator.of(context);

    final resultat = await ref
        .read(restaurantApiProvider)
        .enregistrerMenu(
          SaisieMenu(
            id: widget.menu?.id,
            libelle: _libelle.text,
            type: _type,
            dateDebut: _debut.text,
            dateFin: _fin.text,
          ),
        );

    if (!mounted) return;

    switch (resultat) {
      case RestaurantRecu<MenuRestaurant>(:final donnees):
        invaliderRestaurant(ref);
        // Le message REMPLACE le précédent : les files d'attente de messages
        // feraient lire « menu créé » quatre secondes après avoir créé la fiche.
        messager
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(
                MessagesRestaurant.menuEnregistre(
                  donnees.libelle,
                  creation: !_modification,
                ),
                key: const Key('toast-menu-enregistre'),
              ),
            ),
          );
        navigateur.pop(donnees);
      case RestaurantRefuse<MenuRestaurant>(:final motif, :final erreurs):
        setState(() {
          _envoi = false;
          _refus = motif;
          _parChamp = erreurs;
        });
      case RestaurantInjoignable<MenuRestaurant>():
        // Jamais produite : une base locale n'est pas hors connexion.
        setState(() => _envoi = false);
    }
  }

  Future<void> _choisirDate(TextEditingController controleur) async {
    final actuelle = estDateValide(controleur.text.trim())
        ? DateTime.parse(controleur.text.trim())
        : DateTime.now();
    final choisie = await showDatePicker(
      context: context,
      initialDate: actuelle,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (choisie == null) return;
    controleur.text =
        '${choisie.year.toString().padLeft(4, '0')}-'
        '${choisie.month.toString().padLeft(2, '0')}-'
        '${choisie.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return CoquilleModaleRestaurant(
      cle: const Key('modale-menu'),
      // `menu_form_titre` / `menu_form_titre_modification`.
      titre: _modification ? 'Modifier le menu' : 'Nouveau menu',
      // `menu_form_sous_titre`.
      sousTitre: 'Une carte à laquelle rattacher les plats.',
      largeur: AppLayout.modaleMenu,
      refus: _parChamp.isEmpty ? _refus : null,
      cleRefus: const Key('modale-menu-refus'),
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const EtiquetteChampRestaurant(
            texte: 'Nom du menu',
            obligatoire: true,
          ),
          TextField(
            key: const Key('modale-menu-libelle'),
            controller: _libelle,
            style: TextesModaleRestaurant.etiquette,
            decoration: InputDecoration(
              hintText: 'Ex. Carte du jour',
              isDense: true,
              border: const OutlineInputBorder(),
              errorText: _parChamp['libelle'],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const EtiquetteChampRestaurant(
            texte: 'Type de carte',
            obligatoire: true,
          ),
          DropdownButtonFormField<String>(
            key: const Key('modale-menu-type'),
            initialValue: _type,
            isExpanded: true,
            style: TextesModaleRestaurant.etiquette,
            decoration: InputDecoration(
              isDense: true,
              border: const OutlineInputBorder(),
              errorText: _parChamp['type'],
            ),
            items: [
              for (final t in typesDeMenu)
                DropdownMenuItem(value: t, child: Text(libellesTypesMenu[t]!)),
            ],
            onChanged: (v) => setState(() => _type = v ?? _type),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _ChampDate(
                  cle: const Key('modale-menu-debut'),
                  etiquette: 'Début de saison',
                  controleur: _debut,
                  erreur: _parChamp['date_debut'],
                  onCalendrier: () => _choisirDate(_debut),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _ChampDate(
                  cle: const Key('modale-menu-fin'),
                  etiquette: 'Fin de saison',
                  controleur: _fin,
                  erreur: _parChamp['date_fin'],
                  onCalendrier: () => _choisirDate(_fin),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            // `menu_aide_dates`.
            "Facultatives : un menu permanent n'a pas de saison. Une fin antérieure au début est refusée — la carte ne rendrait jamais aucun plat.",
            style: TextesModaleRestaurant.aide,
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('modale-menu-annuler'),
          onPressed: _envoi ? null : () => Navigator.of(context).pop(),
          // Le libellé commun des modales (`pwa.modale.annuler`).
          child: const Text('Annuler', style: TextesModaleRestaurant.bouton),
        ),
        FilledButton(
          key: const Key('modale-menu-enregistrer'),
          onPressed: _envoi ? null : _enregistrer,
          // `bouton_enregistrer`.
          child: const Text(
            'Enregistrer',
            style: TextesModaleRestaurant.bouton,
          ),
        ),
      ],
    );
  }
}

/// Un champ de date : la saisie `AAAA-MM-JJ` ET le calendrier. La vue pose un
/// `<input type="date">`, qui offre les deux ; une saisie au clavier reste
/// possible, et c'est elle que les tests tapent.
class _ChampDate extends StatelessWidget {
  const _ChampDate({
    required this.cle,
    required this.etiquette,
    required this.controleur,
    required this.erreur,
    required this.onCalendrier,
  });

  final Key cle;
  final String etiquette;
  final TextEditingController controleur;
  final String? erreur;
  final VoidCallback onCalendrier;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        EtiquetteChampRestaurant(texte: etiquette),
        TextField(
          key: cle,
          controller: controleur,
          style: TextesModaleRestaurant.etiquette,
          decoration: InputDecoration(
            hintText: 'AAAA-MM-JJ',
            isDense: true,
            border: const OutlineInputBorder(),
            errorText: erreur,
            errorMaxLines: 4,
            suffixIcon: IconButton(
              tooltip: 'Calendrier',
              onPressed: onCalendrier,
              icon: const Icon(Icons.calendar_today_outlined, size: 16),
            ),
          ),
        ),
      ],
    );
  }
}
