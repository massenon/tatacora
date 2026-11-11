// Vue Blade maîtresse (PA-183) : pwa/demarrage.blade.php
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/navigation/coquille_vue.dart';
import '../../../core/theme/app_assets.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_durations.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';

/// La ligne sous l'enseigne — `rapports.entete.localisation`, que la vue de
/// démarrage rend depuis le 13/10/2026 (décision du Product Owner, PA-208,
/// D385 : « LogiRestock », nom d'un autre produit, est remplacé ; seconde
/// décision du même jour, PA-209, D389 : la mention est « Système de gestion
/// Intégré », casse exacte du PO).
// Directive PO du 14/10/2026 : même libellé que la barre supérieure.
const String localisationDemarrage =
    'Système de gestion Intégré — Gîte Chez Noël, Natitingou (Bénin)';

/// Écran de démarrage — **traduction de `prototype_v2/pages/splash.html`**.
///
/// `DOCTRINE_PORTAGE_FIDELE_FLUTTER.md` §3.4 : « Splash — mêmes dégradés
/// (angles exacts), mêmes filigranes, mêmes durées d'animation, mêmes retards
/// en cascade. » Toutes les valeurs ci-dessous sont relevées dans le HTML.
///
/// ## L'interdit de cet écran
///
/// Le maître, l.68-75, **connecte automatiquement en Administrateur système**
/// si aucune session n'existe, « pour éviter de repasser par l'écran de
/// connexion à chaque ouverture ». C'est une **béquille de maquette**, et
/// `SECURITY_STRICT.md` §12bis l'interdit dans **tout** environnement, y
/// compris `demo` — au même titre que la grille de comptes cliquables de
/// l'écran de connexion (§12).
///
/// Une ouverture d'application qui donne l'accès complet sans mot de passe
/// annule le RBAC entier : les trois niveaux de RG-16 ne protègent plus rien si
/// le premier écran distribue le rôle le plus élevé.
///
/// **Ce qui est porté à la place** : le même écran, la même durée, la même
/// cascade — mais l'aiguillage final lit la **session réelle**. Si un jeton
/// valide est restauré, on entre ; sinon on va à la connexion. Le maître
/// simulait le résultat ; ici le résultat est vrai.
class EcranDemarrage extends ConsumerStatefulWidget {
  const EcranDemarrage({super.key});

  @override
  ConsumerState<EcranDemarrage> createState() => _EtatEcranDemarrage();
}

class _EtatEcranDemarrage extends ConsumerState<EcranDemarrage>
    with SingleTickerProviderStateMixin {
  /// `const etapes = [...]` du maître, l.51-57 — au caractère près, points de
  /// suspension compris.
  static const _etapes = [
    'Initialisation du système...',
    'Chargement de la charte graphique...',
    'Connexion au socle applicatif...',
    'Vérification de la session utilisateur...',
    'Prêt.',
  ];

  /// `setInterval(…, 60)` avec `progression += 4` : 25 pas de 60 ms, soit
  /// **1 500 ms**, puis `setTimeout(…, 300)` avant l'aiguillage.
  static const _pas = AppDurations.pasProgression;
  static const _increment = 4;
  static const _pauseAvantAiguillage = AppDurations.pauseAvantAiguillage;

  /// `@keyframes apparition` : `.6s ease`, retards `0 / .2s / .4s / .6s`.
  static const _dureeApparition = AppDurations.apparition;
  static const _retards = [0.0, 0.2, 0.4, 0.6];

  late final AnimationController _controleur;
  Timer? _minuteur;
  int _progression = 0;

  @override
  void initState() {
    super.initState();

    // Une seule horloge pour les quatre apparitions : les retards sont des
    // intervalles de CETTE horloge, ce qui garantit la cascade exacte du
    // maître. Quatre contrôleurs indépendants dériveraient les uns des autres.
    _controleur = AnimationController(
      vsync: this,
      // Le dernier bloc démarre à .6s et dure .6s : l'horloge couvre 1,2 s.
      duration: _dureeApparition + AppDurations.cascadeApparition.last,
    )..forward();

    _minuteur = Timer.periodic(_pas, (t) {
      setState(() => _progression += _increment);
      if (_progression >= 100) {
        t.cancel();
        Future<void>.delayed(_pauseAvantAiguillage, _aiguiller);
      }
    });
  }

  @override
  void dispose() {
    _minuteur?.cancel();
    _controleur.dispose();
    super.dispose();
  }

  /// L'aiguillage — là où cet écran s'écarte du maître, et le seul endroit.
  void _aiguiller() {
    if (!mounted) return;
    // On lit la session RÉELLE. Aucune session n'est fabriquée ici : c'est
    // exactement ce que §12bis interdit.
    final session = ref.read(sessionProvider);
    context.go(session == null ? '/connexion' : '/hebergement');
  }

  /// `.anim-N` : opacité 0 → 1 et `translateY(12px)` → 0, sur `.6s ease`.
  Widget _apparition(int rang, Widget enfant) {
    final debut = _retards[rang];
    final fin = debut + 0.5; // .6s sur une horloge de 1,2 s
    final courbe = CurvedAnimation(
      parent: _controleur,
      curve: Interval(debut, fin.clamp(0.0, 1.0), curve: Curves.ease),
    );

    return FadeTransition(
      opacity: courbe,
      child: AnimatedBuilder(
        animation: courbe,
        builder: (context, child) => Transform.translate(
          // `translateY(12px)` au départ, ramené à 0.
          offset: Offset(0, 12 * (1 - courbe.value)),
          child: child,
        ),
        child: enfant,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final large = MediaQuery.sizeOf(context).width >= 768; // `md:`
    final etape = _etapes[(_progression ~/ 22).clamp(0, _etapes.length - 1)];

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // `.fond-splash` : la photo, puis un dégradé à TROIS arrêts par
          // dessus — `linear-gradient(180deg, rgba(20,33,61,.55) 0%,
          // rgba(20,33,61,.88) 75%, #14213D 100%)`. Le troisième arrêt est
          // opaque : le bas de l'écran est du navy plein, pas de la photo
          // assombrie. Omettre l'arrêt à 75 % donnerait un dégradé linéaire
          // qui n'est pas celui-là.
          Image.asset('assets/img/gite-cover.jpg', fit: BoxFit.cover),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.0, 0.75, 1.0],
                colors: [
                  AppColors.navy.withValues(alpha: 0.55),
                  AppColors.navy.withValues(alpha: 0.88),
                  AppColors.navy,
                ],
              ),
            ),
          ),

          // `flex flex-col items-center justify-center`
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _apparition(
                  0,
                  // `w-24 h-24 rounded-2xl ring-4 ring-gold/60 object-contain
                  // shadow-2xl`. Décision du PO du 14/10/2026 (D392, PA-210) :
                  // le logo est un PNG PAYSAGE ; la vue garde le cadre carré
                  // et passe d'`object-cover` (qui le rognait) à
                  // `object-contain` — `BoxFit.contain`, jamais d'étirement.
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // `shadow-2xl` du maitre — l'ombre vit dans AppShadows,
                      // relue dans la table `boxShadow` du bundle Tailwind.
                      // Un `box-shadow` CSS n'est peint que HORS de la boîte ;
                      // une `BoxShadow` Flutter l'est aussi DESSOUS. Tant que
                      // l'image couvrait le cadre, rien ne se voyait ; avec
                      // `contain`, la bande libre sous le paysage montrerait
                      // l'ombre. Elle est donc découpée hors du cadre.
                      Positioned.fill(
                        child: ClipPath(
                          key: const Key('ombre-logo-demarrage'),
                          clipper: const _HorsDuCadre(
                            rayon: AppRadius.rounded2xl,
                            ombres: AppShadows.tailwind2xl,
                          ),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                AppRadius.rounded2xl,
                              ),
                              boxShadow: AppShadows.tailwind2xl,
                            ),
                          ),
                        ),
                      ),
                      // `alt="{{ __('pwa.alt_logo') }}"` : le texte de
                      // remplacement du logo, rendu en sémantique.
                      Semantics(
                        label: LibellesCoquille.altLogo,
                        image: true,
                        child: Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                              AppRadius.rounded2xl,
                            ),
                            border: Border.all(
                              color: AppColors.gold.withValues(alpha: 0.60),
                              width: 4, // ring-4
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Image.asset(
                            AppAssets.logo,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg), // mb-6

                _apparition(
                  1,
                  Column(
                    children: [
                      // `text-3xl md:text-4xl font-bold tracking-tight`
                      Text(
                        'TATACORA AFRIQUE',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.neutre0,
                          fontFamily: AppTextStyles.police,
                          fontSize: large ? 36 : Tailles.t30,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.4, // tracking-tight
                        ),
                      ),
                      const SizedBox(height: AppSpacing.unit), // mt-1
                      // `text-gold text-sm font-semibold tracking-wide`
                      Text(
                        'GÎTE CHEZ NOËL — AGENCE DE VOYAGES & HÉBERGEMENT',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.gold,
                          fontFamily: AppTextStyles.police,
                          fontSize: Tailles.t14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4, // tracking-wide
                        ),
                      ),
                      const SizedBox(height: AppSpacing.unit),
                      Text(
                        // La vue rend `rapports.entete.localisation`, la clé
                        // de la barre supérieure et de l'en-tête des états.
                        // DÉCISION DU PRODUCT OWNER DU 13/10/2026 (PA-208,
                        // D385) : la mention au nom d'un autre produit est
                        // remplacée, la vue d'abord, ce client ensuite.
                        // Constante locale plutôt que `LibellesCoquille` :
                        // importer la coquille ferait compter à cet écran
                        // ses libellés (comparateur, PA-196) sans qu'il les
                        // rende ; `ecran_demarrage_test` tient l'égalité
                        // avec la clé résolue par PHP ET avec la coquille.
                        localisationDemarrage,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.neutre0.withValues(alpha: 0.50),
                          fontFamily: AppTextStyles.police,
                          fontSize: Tailles.t15,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 40), // mt-10
                _apparition(
                  2,
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: Largeurs.maxXs, // max-w-xs
                    ),
                    child: Column(
                      children: [
                        // `h-1.5 bg-white/10 rounded-full overflow-hidden`
                        ClipRRect(
                          borderRadius: BorderRadius.circular(
                            AppRadius.roundedFull,
                          ),
                          child: LinearProgressIndicator(
                            value: (_progression / 100).clamp(0.0, 1.0),
                            minHeight: 6, // h-1.5
                            backgroundColor: AppColors.neutre0.withValues(
                              alpha: 0.10,
                            ),
                            valueColor: const AlwaysStoppedAnimation(
                              AppColors.gold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12), // mt-3
                        Text(
                          etape,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.neutre0.withValues(alpha: 0.50),
                            fontFamily: AppTextStyles.police,
                            fontSize: Tailles.t13,
                            letterSpacing: 0.4, // tracking-wide
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // `absolute bottom-8` — le bandeau institutionnel, hors du flux
          // centré : il reste collé au bas quelle que soit la hauteur.
          Positioned(
            left: 0,
            right: 0,
            bottom: AppSpacing.xl, // bottom-8
            child: _apparition(3, const _BandeauInstitutionnel()),
          ),
        ],
      ),
    );
  }
}

/// `pwa.demarrage.cadre` — la ligne au-dessus des sceaux PAEB et FAGUEZ SARL.
const String _cadre = 'Réalisé dans le cadre du';

/// `<div class="anim-4 absolute bottom-8 …">` — `splash.html` l.39-46.
class _BandeauInstitutionnel extends StatelessWidget {
  const _BandeauInstitutionnel();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // `text-white/30 text-[12px] uppercase tracking-widest`
        // `pwa.demarrage.cadre` (« Réalisé dans le cadre du »), que la vue met
        // en capitales par `uppercase` : la phrase est UN littéral, la casse
        // vient de la mise en forme, comme dans la feuille de style.
        Text(
          _cadre.toUpperCase(),
          style: TextStyle(
            color: AppColors.neutre0.withValues(alpha: 0.30),
            fontFamily: AppTextStyles.police,
            fontSize: Tailles.t12,
            letterSpacing: 2.0, // tracking-widest
          ),
        ),
        const SizedBox(height: AppSpacing.xs), // gap-2
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const _Sceau('PAEB'),
            const SizedBox(width: AppSpacing.md), // gap-4
            Text(
              '×',
              style: TextStyle(
                color: AppColors.neutre0.withValues(alpha: 0.30),
                fontFamily: AppTextStyles.police,
                fontSize: Tailles.t15,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            const _Sceau('FAGUEZ SARL'),
          ],
        ),
        const SizedBox(height: AppSpacing.unit), // mt-1
        Text(
          'Projet d\'Appui à l\'Entrepreneuriat au Bénin',
          style: TextStyle(
            color: AppColors.neutre0.withValues(alpha: 0.25),
            fontFamily: AppTextStyles.police,
            fontSize: Tailles.t12,
          ),
        ),
      ],
    );
  }
}

/// `<span class="text-white/70 text-[15px] font-bold border border-white/20
/// rounded-md px-3 py-1.5">`
class _Sceau extends StatelessWidget {
  const _Sceau(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Container(
      // `px-3 py-1.5` — 12 px et 6 px (`splash.html` l.42 et l.44).
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.neutre0.withValues(alpha: 0.20)),
        // CORRIGE le 26/08/2026 : le maitre ecrit `rounded-md`, soit 6 px, et
        // ce code posait `AppRadius.md` — un alias qui vaut 8 px, c'est-a-dire
        // `rounded-lg`. Le piege est dans le NOM : l'echelle courte de ce depot
        // ne s'aligne pas sur celle de Tailwind.
        borderRadius: BorderRadius.circular(AppRadius.roundedMd),
      ),
      child: Text(
        texte,
        style: TextStyle(
          color: AppColors.neutre0.withValues(alpha: 0.70),
          fontFamily: AppTextStyles.police,
          fontSize: Tailles.t15,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Garde tout SAUF l'intérieur du cadre arrondi — pour qu'une ombre se peigne
/// comme un `box-shadow` CSS : autour de la boîte, jamais dessous (D392).
///
/// La marge extérieure se DÉDUIT des ombres découpées (flou, étalement,
/// décalage) : une ombre plus large demain ne serait pas coupée net.
class _HorsDuCadre extends CustomClipper<Path> {
  const _HorsDuCadre({required this.rayon, required this.ombres});

  final double rayon;
  final List<BoxShadow> ombres;

  @override
  Path getClip(Size size) {
    final cadre = Offset.zero & size;
    final marge = ombres.fold<double>(
      0,
      (m, o) => math.max(
        m,
        o.blurRadius * 2 + o.spreadRadius.abs() + o.offset.distance,
      ),
    );
    return Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(cadre.inflate(marge))
      ..addRRect(RRect.fromRectAndRadius(cadre, Radius.circular(rayon)));
  }

  @override
  bool shouldReclip(_HorsDuCadre ancien) =>
      ancien.rayon != rayon || ancien.ombres != ombres;
}
