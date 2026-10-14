/// Un guide — `guides_local`.
///
/// ⚠ **`reservations_tour.guide_id` est NOT NULL** (PA-51) : une prestation ne
/// peut pas exister sans guide. Deux conséquences que tout le module porte :
///
/// 1. le guide est **obligatoire dès la création** d'une réservation ;
/// 2. UC-39 « affecter un guide » est en réalité une **RÉaffectation** — le
///    champ ne peut jamais être vidé, seulement remplacé.
final class Guide {
  const Guide({required this.id, required this.nom, this.zoneCompetence});

  final String id;
  final String nom;
  final String? zoneCompetence;
}
