import 'package:flutter/painting.dart';

/// Les mesures du VOILE DE VERROUILLAGE — `pwa/livewire/verrou-session.blade.php`
/// (monté par `layouts/pwa`, HORS `<main>` : les tailles sont celles de
/// [Tailles], jamais le remappage de [TaillesContenu]).
abstract final class MesuresVerrouSession {
  /// `style="background:rgba(15,23,42,0.72)"` — `slate-900` à 72 % (0xB8 = 184).
  static const Color voile = Color(0xB80F172A);

  /// `backdrop-filter:blur(2px)`.
  static const double flou = 2;

  /// `max-w-[380px]`.
  static const double largeurCarte = 380;

  /// `w-14 h-14` — le disque de l'icône (14 × 4 px).
  static const double disqueIcone = 56;

  /// `width="26" height="26"` — le cadenas.
  static const double cadenas = 26;

  /// `width="17" height="17"` — l'œil du champ.
  static const double oeil = 17;

  /// `pr-11` — la place de l'œil à droite du champ (11 × 4 px).
  static const double retraitChamp = 44;

  /// Le tracé du cadenas de la vue (`viewBox="0 0 24 24"`, trait de 2). La vue pose
  /// `stroke-linecap`/`stroke-linejoin` `round` sur le `<svg>` ; le lecteur de
  /// tracés ne les lit que par élément, d'où leur répétition.
  static const String traceCadenas =
      '<rect x="3" y="11" width="18" height="11" rx="2" stroke-linecap="round" stroke-linejoin="round"/>'
      '<path d="M7 11V7a5 5 0 0110 0v4" stroke-linecap="round" stroke-linejoin="round"/>';

  /// L'œil ouvert — `x-show="!motDePasseVisible"`.
  static const String traceOeilOuvert =
      '<path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z" stroke-linecap="round" stroke-linejoin="round"/>'
      '<circle cx="12" cy="12" r="3" stroke-linecap="round" stroke-linejoin="round"/>';

  /// L'œil barré — `x-show="motDePasseVisible"`.
  static const String traceOeilBarre =
      '<path d="M17.94 17.94A10.94 10.94 0 0112 20c-7 0-11-8-11-8a21.62 21.62 0 015.06-6.94M9.9 4.24A10.94 10.94 0 0112 4c7 0 11 8 11 8a21.6 21.6 0 01-2.66 3.94M14.12 14.12a3 3 0 11-4.24-4.24" stroke-linecap="round" stroke-linejoin="round"/>'
      '<path d="M1 1l22 22" stroke-linecap="round" stroke-linejoin="round"/>';
}
