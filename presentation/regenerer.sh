#!/usr/bin/env bash
# Régénère TOUS les échantillons de presentation/ (serveur puis poste). À lancer depuis la racine du dépôt.
# Prérequis : PHP + dépendances Composer de tatacora-api ; Flutter (poste). Refusé si APP_ENV=production.
set -euo pipefail
racine="$(cd "$(dirname "$0")/.." && pwd)"

(cd "$racine/tatacora-api" && php artisan tatacora:generer-echantillons "$racine/presentation")
(cd "$racine/tatacora-flutter" && PRESENTATION_DIR="$racine/presentation" flutter test tool/generer_echantillons_poste_test.dart)
