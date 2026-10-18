// Vue Blade maîtresse (PA-183) : pwa/transverse/synchronisation-postes.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/coquille_vue.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/mesures_transverses.dart';
import '../../transverse/presentation/widgets/briques_transverses.dart';
import '../data/service_suivi_postes.dart';
import 'providers_synchronisation.dart';

/// Le service de l'écran — un test pose le sien.
final serviceSuiviPostesProvider = Provider<ServiceSuiviPostes>(
  (ref) => ServiceSuiviPostes(
    transport: ref.watch(transportSynchronisationProvider),
    urlServeur: ref.watch(urlServeurSynchronisationProvider),
  ),
);

/// L'écran **Synchroniser les postes** — décision du Product Owner du
/// 18/10/2026 (« le serveur doit avoir aussi le bouton synchroniser »), porté
/// sur le poste à l'identique de la page web.
///
/// Le bouton enregistre une DEMANDE au serveur : chaque poste allumé la lit
/// dans les 30 s et passe aussitôt (envoi de sa file, puis réception de tout
/// ce que le serveur détient, tous modules) — CE poste compris, qui passe
/// tout de suite. Le tableau dit, poste par poste, ce que le serveur en sait.
/// Hors réseau, l'écran le dit : rien de ce tableau ne vit sur ce poste.
/// Ouvert à tout compte, comme la route de la vue.
class EcranSynchronisationPostes extends ConsumerStatefulWidget {
  const EcranSynchronisationPostes({super.key});

  @override
  ConsumerState<EcranSynchronisationPostes> createState() =>
      _EtatEcranSynchronisationPostes();
}

class _EtatEcranSynchronisationPostes
    extends ConsumerState<EcranSynchronisationPostes> {
  IssueSuiviPostes? _etat;
  String? _confirmation;
  bool _enCours = false;

  @override
  void initState() {
    super.initState();
    _relire();
  }

  Future<void> _relire() async {
    final etat = await ref.read(serviceSuiviPostesProvider).lire();
    if (mounted) setState(() => _etat = etat);
  }

  Future<void> _synchroniser() async {
    setState(() => _enCours = true);
    final le = await ref.read(serviceSuiviPostesProvider).demander();
    if (!mounted) return;
    setState(() {
      _enCours = false;
      _confirmation = le == null
          ? ServiceSuiviPostes.horsReseau
          : TextesSynchronisationPostes.demandeFaite(_horodatage(le));
    });
    if (le != null) {
      // Ce poste n'attend pas son passage court : il passe tout de suite.
      lancerSynchronisationSansAttendre(() => ref.read(syncManagerProvider));
    }
    await _relire();
  }

  @override
  Widget build(BuildContext context) {
    final etat = _etat;
    final petit = styleTransverse(TaillesContenu.sm, couleur: Ardoise.c600);
    return PageTransverse(
      largeurMax: MesuresTransverses.pageLarge,
      enfants: [
        const EnTeteTransverse(
          trace: TracesCoquille.importExport,
          titre: TextesSynchronisationPostes.titre,
          sousTitre: TextesSynchronisationPostes.sousTitre,
          margeBas: AppSpacing.mdPlus,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: BoutonTransverse(
            cle: const Key('bouton-synchroniser-postes'),
            libelle: TextesSynchronisationPostes.bouton,
            fond: AppColors.navy,
            onTap: _enCours ? () {} : _synchroniser,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (_confirmation != null) ...[
          Text(
            _confirmation!,
            key: const Key('confirmation-synchronisation'),
            style: petit,
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        switch (etat) {
          null => const Center(child: CircularProgressIndicator()),
          SuiviPostesIndisponible(:final raison) => Text(
            raison,
            key: const Key('suivi-postes-indisponible'),
            style: petit,
          ),
          SuiviPostesLu(:final demandeeLe, :final postes) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                demandeeLe == null
                    ? TextesSynchronisationPostes.aucuneDemande
                    : TextesSynchronisationPostes.derniereDemande(
                        _horodatage(demandeeLe),
                      ),
                key: const Key('derniere-demande'),
                style: petit,
              ),
              const SizedBox(height: AppSpacing.md),
              CarteTransverse(
                padding: EdgeInsets.zero,
                child: TableauTransverse(
                  colonnes: const [
                    (
                      titre: TextesSynchronisationPostes.colPoste,
                      alignement: TextAlign.left,
                    ),
                    (
                      titre: TextesSynchronisationPostes.colCompte,
                      alignement: TextAlign.left,
                    ),
                    (
                      titre: TextesSynchronisationPostes.colMontee,
                      alignement: TextAlign.left,
                    ),
                    (
                      titre: TextesSynchronisationPostes.colDescente,
                      alignement: TextAlign.left,
                    ),
                    (
                      titre: TextesSynchronisationPostes.colAttente,
                      alignement: TextAlign.left,
                    ),
                    (
                      titre: TextesSynchronisationPostes.colDemande,
                      alignement: TextAlign.left,
                    ),
                  ],
                  lignes: [
                    for (final p in postes)
                      [
                        Text(p.posteId, style: petit),
                        Text(
                          p.utilisateur ?? TextesSynchronisationPostes.jamais,
                          style: petit,
                        ),
                        Text(_jour(p.derniereMontee), style: petit),
                        Text(_jour(p.derniereDescente), style: petit),
                        Text(
                          p.enAttente?.toString() ??
                              TextesSynchronisationPostes.jamais,
                          style: petit,
                        ),
                        Text(
                          p.demandeSuivie
                              ? TextesSynchronisationPostes.demandeSuivie
                              : TextesSynchronisationPostes.demandeNonSuivie,
                          style: styleTransverse(
                            TaillesContenu.sm,
                            couleur: p.demandeSuivie
                                ? AppColors.succes
                                : AppColors.alerte,
                          ),
                        ),
                      ],
                  ],
                  vide: TextesSynchronisationPostes.aucunPoste,
                  cleVide: const Key('suivi-postes-vide'),
                ),
              ),
            ],
          ),
        },
        const SizedBox(height: AppSpacing.md),
        Text(
          TextesSynchronisationPostes.note,
          style: styleTransverse(TaillesContenu.t13, couleur: Ardoise.c500),
        ),
      ],
    );
  }

  static String _deux(int n) => n.toString().padLeft(2, '0');

  static String _horodatage(DateTime d) =>
      '${_deux(d.day)}/${_deux(d.month)}/${d.year} '
      '${_deux(d.hour)}:${_deux(d.minute)}:${_deux(d.second)}';

  static String _jour(DateTime? d) => d == null
      ? TextesSynchronisationPostes.jamais
      : '${_deux(d.day)}/${_deux(d.month)}/${d.year} '
            '${_deux(d.hour)}:${_deux(d.minute)}';
}

/// Les textes de la vue (`pwa.synchronisation_postes.*`), au mot.
abstract final class TextesSynchronisationPostes {
  static const String titre = 'Synchroniser les postes';
  static const String sousTitre =
      "Ce qui a été enregistré ici part vers les postes Windows à leur prochain passage. Le bouton les fait passer tout de suite (moins d'une minute) : chacun envoie sa file, puis reçoit tout ce que le serveur détient, tous modules.";
  static const String bouton = 'Synchroniser maintenant';
  static String demandeFaite(String date) =>
      'Demande envoyée le $date. Les postes allumés et connectés la suivent dans la minute.';
  static const String aucuneDemande =
      "Aucune demande de synchronisation n'a encore été faite depuis le serveur.";
  static String derniereDemande(String date) => 'Dernière demande : $date';
  static const String colPoste = 'Poste';
  static const String colCompte = 'Compte';
  static const String colMontee = 'Dernier envoi';
  static const String colDescente = 'Dernière réception';
  static const String colAttente = "En attente d'envoi";
  static const String colDemande = 'Dernière demande';
  static const String demandeSuivie = 'Reçue';
  static const String demandeNonSuivie = 'Pas encore reçue';
  static const String jamais = '—';
  static const String aucunPoste =
      "Aucun poste ne s'est encore synchronisé avec ce serveur.";
  static const String note =
      "Un poste éteint ou hors réseau suivra la demande à sa prochaine connexion : rien de ce qui a été enregistré n'est perdu.";
}
