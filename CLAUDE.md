# TATACORA — monorepo

- `tatacora-api/` : serveur Laravel ; `tatacora-flutter/` : poste Windows (voir son `CLAUDE.md`) ; `docs/` : spécifications, journal des lots, mise en production ; `manuel_utilisation/` : manuel.

## Procédure de test fiable

1. Serveur : `cd tatacora-api && DB_DATABASE=tatacora_test php artisan migrate:fresh --force` (effectif : environ 2 700 tests PHP).
2. Poste : `cd tatacora-flutter && flutter test --concurrency=1` (5 831 tests + 24 ignorés au 11/11/2026).

Les tests `*_contre_serveur_*` supposent une base vide et se gênent en parallèle.

## Faits à ne pas contredire (11/11/2026)

- Schéma du poste : v59 (v58 `reservations_local.auteur_annulation_login`, v59 `articles_local.cmp_reference`).
- Synchronisation automatique toutes les minutes ; demande lue toutes les 30 s.
- Comptable = droits du gérant ; barman = socle du seeder ; `php artisan roles:realigner-socle --role=… --dry-run`.
- Mise en production : `docs/MISE_EN_PRODUCTION.md`. Reste à faire : `docs/RESTE_A_FAIRE.md`.
