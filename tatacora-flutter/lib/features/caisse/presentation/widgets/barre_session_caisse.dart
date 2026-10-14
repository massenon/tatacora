// Vue Blade maîtresse (PA-183) : pwa/pos/comptant.blade.php
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/format/formats.dart';
import '../../../../core/rbac/garde_acces.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/di/providers.dart';
import '../../../../shared_widgets/bouton_standard.dart';
import '../../../pos/domain/entities/mode_reglement.dart';
import '../../../pos/domain/entities/panier.dart';
import '../../../pos/presentation/providers_pos.dart' show paniersProvider;
import '../../domain/entities/session_caisse.dart';
import '../../domain/messages_caisse.dart';
import '../../domain/montant_caisse.dart';
import '../providers_caisse.dart';
import 'modale_cloture_caisse.dart';
import 'modale_ouverture_caisse.dart';

/// La BARRE DE SESSION DE CAISSE du point de vente — la bande qui précède les
/// trois panneaux (`pos/comptant.blade.php` l.74-152, « maître,
/// `rendreSession()` »).
///
/// Ce fichier PORTE une partie de la vue (la barre, et l'ouverture des deux
/// modales) : il la cite donc en tête, comme `vue_salle.dart`. Les mots de la
/// barre et des modales vivent dans `messages_caisse.dart`, qui la cite aussi —
/// le comparateur de conformité ne lit que les porteurs, et un libellé rangé
/// dans un fichier qui ne la cite pas serait « absent » alors qu'il est rendu.
///
/// ## Deux états, tous deux lus de la base
///
/// * **Ouverte** — pastille verte, « Caisse bar ouverte », « depuis 07:00 », la
///   durée écoulée (« · 12 min », rouge et grasse passé 24 h : une clôture
///   oubliée, pas une session), « Fond 10 000 FCFA », puis le bouton
///   « Clôturer la caisse ».
/// * **Fermée** — pastille rouge, « Aucune caisse ouverte », puis « Ouvrir la
///   caisse ».
///
/// Les boutons sont désactivés sans droit d'écriture sur M5 (le serveur refuse
/// en 403 avant toute validation) ; ils ne sont jamais inertes avec un droit.
///
/// ## Ce que la barre ne rend PAS, avec les mots de la vue — raisons revues le 12/10/2026 (D282)
///
/// ⚠ Les raisons écrites ici avant le lot 5 sont PÉRIMÉES : elles disaient que
/// `paniers_local` ne porte aucun `session_id` et que le panier s'encaisse sans
/// caisse. Depuis la v18 (D231), `paniers_local.session_encaissement_id` est
/// écrit à la clôture d'un panier au comptant (`PanierDao.cloturer`), et la
/// clôture REFUSE sans caisse `bar` ouverte. Ce qui suit est l'état vrai.
///
/// * ⚠ RENDUS depuis le 14/10/2026 (consigne du PO) : « N vente(s) »,
///   « CA … », « Encaissé … » et « En note … » (l.112-131), calculés par
///   [compteursDeSession] sur les paniers rattachés à la session ; et
///   « Journal du jour » (l.134-136), qui ouvre l'écran Historique des ventes
///   faute de modale portée (écart nommé à l'appel). Note : la vue ne compte
///   que des ventes rattachées, et ce poste a des ventes d'avant la v18 qui ne
///   le sont pas ; la clôture les DIT (`MessagesCaisse.ventesSansSession`).
/// * « Aucune vente n'est possible tant que la caisse n'est pas ouverte. »
///   (l.146) : VRAI pour une vente au comptant (refus
///   `MessagesCaisse.refusSansCaisse` à la clôture), rendu dans la barre depuis
///   le 14/10/2026. La garde « Ouvrez la caisse pour encaisser » (l.458), elle,
///   EST rendue : c'est le libellé du bouton d'encaissement désactivé du
///   panier (`vue_panier.dart`).
///
/// ## Écarts de forme
///
/// La durée se met à jour toutes les 30 s (`setInterval` de la vue) par un
/// minuteur annulé à la fermeture de l'écran. L'horloge est injectable.
class BarreSessionCaisse extends ConsumerStatefulWidget {
  const BarreSessionCaisse({super.key});

  @override
  ConsumerState<BarreSessionCaisse> createState() => _EtatBarreSessionCaisse();
}

/// `h > 0 ? h + 'h' + mm : m + ' min'` — le texte de la durée de la vue
/// (`pos/comptant.blade.php` l.99-100). Une horloge qui recule ne produit jamais
/// une durée négative.
String dureeEcouleeDeLaBarre(Duration ecoule) {
  final ms = ecoule.isNegative ? Duration.zero : ecoule;
  final h = ms.inHours;
  final m = ms.inMinutes % 60;
  return h > 0 ? '${h}h${m.toString().padLeft(2, '0')}' : '${ms.inMinutes} min';
}

/// `date_ouverture->format('H:i')` — l'heure d'ouverture (l.81).
String heureDeLaBarre(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

class _EtatBarreSessionCaisse extends ConsumerState<BarreSessionCaisse> {
  Timer? _minuteur;

  /// `setInterval(() => majer(), 30000)` de la vue.
  static const Duration _periode = Duration(seconds: 30);

  /// `this.tardive = h >= 24` : le seuil de la clôture oubliée.
  static const int _heuresTardives = 24;

  @override
  void initState() {
    super.initState();
    _minuteur = Timer.periodic(_periode, (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _minuteur?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionDuBarProvider);
    final peutEcrire = ref
        .watch(droitsProvider)
        .peutEcrire(ModuleTatacora.m5Bar);

    return Container(
      key: const Key('barre-session-caisse'),
      width: double.infinity,
      // `px-5 py-2.5 border-b border-slate-200 bg-white`.
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.mdPlus,
        vertical: AppSpacing.xsPlus,
      ),
      decoration: const BoxDecoration(
        color: AppColors.neutre0,
        border: Border(bottom: BorderSide(color: Ardoise.c200)),
      ),
      child: session.when(
        // Le temps d'une lecture locale : on n'affiche NI « fermée » NI
        // « ouverte » — l'un ou l'autre serait une affirmation sans lecture.
        loading: () => const SizedBox.shrink(),
        error: (e, _) => Text(
          '$e',
          key: const Key('barre-session-erreur'),
          style: _petit.copyWith(color: PaletteMaitre.rouge600),
        ),
        data: (s) => s == null
            ? _Fermee(peutEcrire: peutEcrire)
            : _Ouverte(
                session: s,
                peutEcrire: peutEcrire,
                maintenant: ref.watch(horlogeCaisseProvider)(),
                // Les ventes RATTACHÉES à la session (`ventesDeLaSession`,
                // vue l.112-131) : `null` tant que les paniers ne sont pas
                // lus — les compteurs ne s'affichent pas plutôt qu'un zéro.
                compteurs: switch (ref.watch(paniersProvider)) {
                  AsyncData(:final value) => compteursDeSession(value, s.id),
                  _ => null,
                },
              ),
      ),
    );
  }
}

// `text-[12px]` dans `<main>` -> 11.5 px (app.css l.175-186).
const TextStyle _petit = TextStyle(
  fontFamily: AppTextStyles.police,
  fontSize: TaillesContenu.t12,
  color: Ardoise.c500,
);

// `text-[13px]` dans `<main>` -> 12.5 px.
const TextStyle _courant = TextStyle(
  fontFamily: AppTextStyles.police,
  fontSize: TaillesContenu.t13,
);

Widget _pastille(Color couleur) => Container(
  width: LargeursPos.pastilleCaisse,
  height: LargeursPos.pastilleCaisse,
  decoration: BoxDecoration(color: couleur, shape: BoxShape.circle),
);

/// Les quatre compteurs de la barre — réplique du calcul de la vue
/// (`pos/comptant.blade.php` l.112-131) : « N vente(s) » compte TOUTES les
/// ventes de la session ; « CA » en exclut les annulées ; « Encaissé » ne
/// retient que les modes qui encaissent ; « En note » le reste.
///
/// Sur ce poste, une vente de la session est un panier CLÔTURÉ dont
/// `sessionEncaissementId` désigne la session (écrit à la clôture depuis la
/// v18) ; un panier clôturé ne s'annule pas (l'avoir est une autre pièce). Le
/// montant est `montantCloture`, figé à la clôture. Ajouté le 14/10/2026
/// (consigne du PO, NOUVELLE_INSTRUCTION1 §2) : le « reste à livrer » de la
/// doc d'en-tête est levé pour les compteurs.
({int nombre, int chiffreAffaires, int encaisse, int enNote})
compteursDeSession(List<Panier> paniers, String sessionId) {
  var nombre = 0;
  var ca = 0;
  var encaisse = 0;
  var enNote = 0;
  for (final p in paniers) {
    if (p.statut != StatutPanier.cloture) continue;
    if (p.sessionEncaissementId != sessionId) continue;
    nombre++;
    final montant = p.montantCloture ?? p.total;
    ca += montant;
    final mode = ModeReglement.values
        .where((m) => m.code == p.modePaiement)
        .firstOrNull;
    if (mode?.encaisse ?? false) {
      encaisse += montant;
    } else {
      enNote += montant;
    }
  }
  return (
    nombre: nombre,
    chiffreAffaires: ca,
    encaisse: encaisse,
    enNote: enNote,
  );
}

class _Ouverte extends StatelessWidget {
  const _Ouverte({
    required this.session,
    required this.peutEcrire,
    required this.maintenant,
    required this.compteurs,
  });

  final SessionCaisse session;
  final bool peutEcrire;
  final DateTime maintenant;
  final ({int nombre, int chiffreAffaires, int encaisse, int enNote})?
  compteurs;

  @override
  Widget build(BuildContext context) {
    final ecoule = maintenant.difference(session.dateOuverture);
    final tardive = ecoule.inHours >= _EtatBarreSessionCaisse._heuresTardives;

    // `flex flex-wrap items-center gap-x-6 gap-y-1.5` + `<div class="flex-1">` :
    // les informations à gauche (elles passent à la ligne si la page est
    // étroite), le bouton collé à DROITE par le ressort `flex-1`.
    final informations = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      // `gap-x-6 gap-y-1.5`.
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.xxs,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _pastille(PaletteMaitre.emeraude500),
            const SizedBox(width: AppSpacing.xxs),
            Text(
              MessagesCaisse.caisseOuverte(session.point.code),
              key: const Key('caisse-ouverte'),
              style: _courant.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(width: AppSpacing.xxs),
            Text(
              MessagesCaisse.depuis(heureDeLaBarre(session.dateOuverture)),
              key: const Key('caisse-depuis'),
              style: _courant.copyWith(color: Ardoise.c400),
            ),
            const SizedBox(width: AppSpacing.xxs),
            Text(
              '· ${dureeEcouleeDeLaBarre(ecoule)}',
              key: const Key('caisse-duree'),
              style: tardive
                  ? _courant.copyWith(
                      color: PaletteMaitre.rouge600,
                      fontWeight: FontWeight.w600,
                    )
                  : _courant.copyWith(color: Ardoise.c400),
            ),
          ],
        ),
        Text(
          MessagesCaisse.fond(formaterCentimesEnFcfa(session.fondCentimes)),
          key: const Key('caisse-fond'),
          style: _petit,
        ),
        if (compteurs case final c?) ...[
          Text(
            MessagesCaisse.ventes(c.nombre),
            key: const Key('caisse-ventes'),
            style: _petit,
          ),
          Text(
            MessagesCaisse.chiffreAffaires(formaterFcfa(c.chiffreAffaires)),
            key: const Key('caisse-ca'),
            style: _petit,
          ),
          // `text-emerald-700 font-semibold`.
          Text(
            MessagesCaisse.encaisse(formaterFcfa(c.encaisse)),
            key: const Key('caisse-encaisse'),
            style: _petit.copyWith(
              color: PaletteMaitre.emeraude700,
              fontWeight: FontWeight.w600,
            ),
          ),
          // `@if (bccomp($noteSession, '0.00', 2) > 0)`, `text-amber-700`.
          if (c.enNote > 0)
            Text(
              MessagesCaisse.enNote(formaterFcfa(c.enNote)),
              key: const Key('caisse-en-note'),
              style: _petit.copyWith(
                color: PaletteMaitre.ambre700,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ],
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: informations),
        // « Journal du jour » (vue l.135-136). La vue ouvre une modale des
        // ventes de la session ; ce poste ne la porte pas encore : le bouton
        // ouvre l'écran Historique des ventes, qui liste ces ventes. Jamais
        // un bouton inerte (Article 3.3). Écart nommé le 14/10/2026.
        _BoutonContour(
          cle: const Key('caisse-journal'),
          libelle: MessagesCaisse.journalDuJour,
          onPressed: () => context.go('/historique-ventes'),
        ),
        // `gap-x-6` entre les deux boutons de droite.
        const SizedBox(width: AppSpacing.xs),
        _BoutonContour(
          cle: const Key('caisse-cloturer'),
          libelle: MessagesCaisse.cloturerLaCaisse,
          onPressed: peutEcrire
              ? () => showDialog<void>(
                  context: context,
                  builder: (_) => ModaleClotureCaisse(session: session),
                )
              : null,
        ),
      ],
    );
  }
}

class _Fermee extends StatelessWidget {
  const _Fermee({required this.peutEcrire});

  final bool peutEcrire;

  @override
  Widget build(BuildContext context) {
    // `flex flex-wrap items-center gap-3` + ressort `flex-1` : le bouton à droite.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _pastille(PaletteMaitre.rouge500),
              const SizedBox(width: AppSpacing.xxs),
              Flexible(
                child: Text(
                  MessagesCaisse.aucuneCaisse,
                  key: const Key('caisse-aucune'),
                  style: _courant.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.navy,
                  ),
                ),
              ),
              // `gap-3`, puis `text-[12px] text-slate-400` (vue l.146).
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  MessagesCaisse.aucuneCaisseAide,
                  key: const Key('caisse-aucune-aide'),
                  style: _petit.copyWith(color: Ardoise.c400),
                ),
              ),
            ],
          ),
        ),
        // `text-[12px] px-4 py-1.5 bg-navy text-white font-semibold
        // rounded-lg` — bouton standard (PO, 14/10/2026).
        BoutonStandard(
          key: const Key('caisse-ouvrir'),
          libelle: MessagesCaisse.ouvrirLaCaisse,
          variante: VarianteBouton.primaire,
          taillePolice: TaillesContenu.t12,
          margeVerticale: AppSpacing.xxs,
          onPressed: peutEcrire
              ? () => showDialog<void>(
                  context: context,
                  builder: (_) => const ModaleOuvertureCaisse(),
                )
              : null,
        ),
      ],
    );
  }
}

/// `text-[12px] px-3 py-1.5 rounded-lg border border-slate-300 hover:bg-slate-50
/// font-medium`.
class _BoutonContour extends StatelessWidget {
  const _BoutonContour({
    required this.cle,
    required this.libelle,
    required this.onPressed,
  });

  final Key cle;
  final String libelle;
  final VoidCallback? onPressed;

  /// Le bouton standard compact (PO, 14/10/2026), `py-1.5`.
  @override
  Widget build(BuildContext context) => BoutonStandard(
    key: cle,
    libelle: libelle,
    compact: true,
    margeVerticale: AppSpacing.xxs,
    onPressed: onPressed,
  );
}
