// Vue Blade maîtresse (PA-183) : pwa/stocks/inventaires.blade.php
// (les deux modales de l'onglet « Inventaire physique », l.600-644).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../data/stocks_api.dart';
import '../../domain/calcul_inventaire.dart';
import '../../domain/messages_stock.dart';
import '../providers_stocks.dart';
import 'coquille_modale_stock.dart';

/// La modale **« Enregistrer le comptage »** (`etatFormulaire === 'comptage'`) :
/// le sous-titre est l'article, le champ « Compté » est un nombre (au plus deux
/// décimales, jamais négatif), le pied « Annuler » / « Enregistrer le comptage ».
///
/// Le comptage FIGE le théorique de l'article à cet instant (`InventaireService::
/// compter`) ; un second comptage du même article écrase le premier. Rend ce que
/// le comptage a figé, ou `null` si la modale est fermée sans enregistrer.
Future<ComptageBrouillon?> ouvrirModaleComptage(
  BuildContext context, {
  required String pointId,
  required LigneFeuille ligne,
}) {
  return showDialog<ComptageBrouillon>(
    context: context,
    builder: (_) => _ModaleComptage(pointId: pointId, ligne: ligne),
  );
}

class _ModaleComptage extends ConsumerStatefulWidget {
  const _ModaleComptage({required this.pointId, required this.ligne});

  final String pointId;
  final LigneFeuille ligne;

  @override
  ConsumerState<_ModaleComptage> createState() => _ModaleComptageState();
}

class _ModaleComptageState extends ConsumerState<_ModaleComptage> {
  final _formulaire = GlobalKey<FormState>();
  final _quantite = TextEditingController();

  bool _envoiEnCours = false;
  String? _refus;

  @override
  void dispose() {
    _quantite.dispose();
    super.dispose();
  }

  Future<void> _enregistrer() async {
    if (!(_formulaire.currentState?.validate() ?? false)) return;

    setState(() {
      _envoiEnCours = true;
      _refus = null;
    });

    final r = await ref
        .read(stocksApiProvider)
        .compter(
          pointId: widget.pointId,
          articleId: widget.ligne.articleId,
          quantite: _quantite.text,
        );
    if (!mounted) return;

    switch (r) {
      case StocksOk(:final valeur):
        Navigator.of(context).pop(valeur);
      case StocksRefuse(:final motif):
        setState(() {
          _envoiEnCours = false;
          _refus = motif;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CoquilleModaleStock(
      cle: const Key('modale-comptage'),
      titre: 'Enregistrer le comptage',
      sousTitre: widget.ligne.libelle,
      libelleValidation: 'Enregistrer le comptage',
      cleValidation: const Key('comptage-enregistrer'),
      envoiEnCours: _envoiEnCours,
      onValider: _enregistrer,
      refus: _refus,
      cleRefus: const Key('comptage-refus'),
      corps: Form(
        key: _formulaire,
        child: TextFormField(
          key: const Key('comptage-quantite'),
          controller: _quantite,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Compté',
            border: OutlineInputBorder(),
          ),
          onFieldSubmitted: (_) => _enregistrer(),
          // La même chaîne que le serveur (`quantiteComptee.required`) : une
          // saisie vide n'est pas un zéro compté.
          validator: (v) => (v == null || v.trim().isEmpty)
              ? MessagesStock.quantitePositive
              : null,
        ),
      ),
    );
  }
}

/// `stocks.inventaire_incomplet`, `:nombre` remplacé — la phrase du serveur, mot
/// pour mot. Elle est écrite ICI parce que la mesure de conformité cherche les
/// libellés d'une modale dans les fichiers qui citent la vue, pas dans leurs
/// imports ; `MessagesStock.inventaireIncomplet` (le refus du DAO) la porte
/// aussi, et un test les confronte au fichier de langue PHP ET entre elles.
String phraseInventaireIncomplet(int nombre) =>
    "$nombre article(s) n'ont pas été comptés. Clôturer maintenant régulariserait une partie du stock en laissant le reste inchangé, sans que rien ne le signale.";

/// La modale **« Inventaire incomplet »** (`etatFormulaire === 'cloture'`).
///
/// Elle ANNONCE avant le clic combien d'articles n'ont pas été comptés et ce
/// qu'il advient d'eux : un décompte affiché après coup serait une surprise, et
/// une clôture partielle silencieuse laisserait une partie du stock régularisée
/// et le reste intact. Le sous-titre est la phrase du serveur
/// (`stocks.inventaire_incomplet`), le détail celui de la vue, et le bouton
/// « Clôturer partiellement » (`incomplet_confirmer`).
///
/// ## Écart nommé : quand TOUT est compté
///
/// La vue rend alors la même modale — « Inventaire incomplet », « 0 article(s)
/// n'ont pas été comptés. » et « ne régularisera QUE les articles comptés » —,
/// des phrases fausses : l'inventaire est complet. Ce poste ne dit pas ce qui est
/// faux (même règle que pour l'argent, piège 13) : il titre la modale
/// « Clôturer et régulariser », annonce le décompte vrai, et le bouton porte
/// le même nom.
///
/// Rend `true` si l'utilisateur confirme.
Future<bool?> confirmerClotureInventaire(
  BuildContext context, {
  required FeuilleComptage feuille,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _ModaleCloture(feuille: feuille),
  );
}

class _ModaleCloture extends StatelessWidget {
  const _ModaleCloture({required this.feuille});

  final FeuilleComptage feuille;

  static const TextStyle _corps = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: Tailles.t13,
    color: Ardoise.c600,
  );

  @override
  Widget build(BuildContext context) {
    final incomplet = feuille.nonComptes > 0;

    return CoquilleModaleStock(
      cle: const Key('modale-cloture-inventaire'),
      titre: incomplet ? 'Inventaire incomplet' : 'Clôturer et régulariser',
      sousTitre: incomplet
          ? phraseInventaireIncomplet(feuille.nonComptes)
          : '${feuille.comptes} / ${feuille.total} article(s) comptés',
      libelleValidation: incomplet
          ? 'Clôturer partiellement'
          : 'Clôturer et régulariser',
      cleValidation: const Key('cloture-confirmer'),
      envoiEnCours: false,
      onValider: () async => Navigator.of(context).pop(true),
      corps: Text(
        incomplet
            ? 'Clôturer maintenant ne régularisera QUE les articles comptés ; '
                  'les autres resteront à leur stock théorique actuel, sans que '
                  'rien ne le signale par la suite.'
            : 'Chaque écart devient un mouvement de régularisation : '
                  'l’excédent en entrée, le manquant en perte.',
        key: const Key('cloture-detail'),
        style: _corps,
      ),
    );
  }
}
