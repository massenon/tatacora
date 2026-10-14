import 'entities/session_caisse.dart';

/// L'état de l'indicateur de caisse de la barre supérieure —
/// `App\Pwa\Support\IndicateurCaisse::pour()`, répliqué (12/10/2026, lot 1
/// « coquille »).
///
/// Trois états, comme le serveur : aucune session ouverte (« Caisse fermée »),
/// une session ouverte, une session ouverte depuis 24 h ou plus (« tardive »,
/// pastille rouge — « une caisse ouverte depuis plus d'une journée est une
/// clôture oubliée, pas une session »).
enum EtatCaisse { fermee, ouverte, tardive }

/// L'état et le point de vente affiché en infobulle (`null` si fermée).
final class IndicateurCaisse {
  const IndicateurCaisse({required this.etat, this.point});

  final EtatCaisse etat;
  final PointDeVenteCaisse? point;
}

/// Le seuil du serveur : `diffInHours(now()) >= 24`.
const Duration seuilCaisseTardive = Duration(hours: 24);

/// Dérive l'indicateur de la session ouverte LA PLUS RÉCENTE, tous points
/// confondus (`whereNull('date_cloture')->orderByDesc('date_ouverture')`) —
/// c'est `SessionsCaisseRepository.sessionOuverteLaPlusRecente`.
///
/// Pure : l'heure est passée, jamais lue (un test qui lit l'horloge réelle
/// échoue un jour sur mille).
IndicateurCaisse indicateurCaisse(SessionCaisse? session, DateTime maintenant) {
  if (session == null) return const IndicateurCaisse(etat: EtatCaisse.fermee);
  final tardive =
      maintenant.difference(session.dateOuverture) >= seuilCaisseTardive;
  return IndicateurCaisse(
    etat: tardive ? EtatCaisse.tardive : EtatCaisse.ouverte,
    point: session.point,
  );
}
