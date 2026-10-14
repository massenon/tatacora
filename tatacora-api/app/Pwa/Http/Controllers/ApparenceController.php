<?php

declare(strict_types=1);

namespace App\Pwa\Http\Controllers;

use App\Shared\Parametres\Services\ApparenceEtablissementService;
use Illuminate\Support\Facades\Storage;
use Symfony\Component\HttpFoundation\Response;

/**
 * Sert le logo ou le favicon TÉLÉVERSÉS (onglet « Logo & Apparence »,
 * 02/09/2026) depuis le disque `public`, SANS lien symbolique `storage:link` —
 * non garanti sur cPanel mutualisé, voir
 * {@see ApparenceEtablissementService}.
 *
 * ## Hors du groupe `auth`, délibérément
 *
 * Le favicon est demandé par le navigateur sur TOUTES les pages, écran de
 * connexion compris — derrière `auth`, chaque onglet non connecté afficherait
 * l'icône cassée. Le logo d'un établissement est son identité publique (il
 * figure sur chaque document remis), pas un secret : servir ces deux fichiers
 * sans session n'expose rien que la façade du Gîte n'affiche déjà.
 *
 * `{type}` est contraint par la route à `logo|favicon` : aucun chemin
 * arbitraire ne peut être demandé, le service résout lui-même le fichier.
 */
class ApparenceController
{
    public function __invoke(string $type, ApparenceEtablissementService $apparence): Response
    {
        $fichier = $apparence->fichierDe($type);

        if ($fichier === null) {
            // Rien de téléversé : l'actif livré du dépôt, comme les vues.
            return redirect(asset(ApparenceEtablissementService::ACTIF_LIVRE));
        }

        return Storage::disk(ApparenceEtablissementService::DISQUE)->response($fichier);
    }
}
