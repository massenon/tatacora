<?php

declare(strict_types=1);

namespace App\Shared\Sync\Http\Controllers;

use App\Models\User;
use App\Shared\Parametres\Services\ApparenceEtablissementService;
use App\Shared\Sync\Support\PosteDuJeton;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Descente de la SIGNATURE et du CACHET des documents commerciaux vers un poste (PO, 07/11/2026).
 *
 * Les images (400 Ko au plus chacune, réduites au dépôt) ne voyagent pas dans la descente des
 * paramètres (texte) : le poste les demande ICI, à la demande, avec l'empreinte qu'il possède déjà
 * (`?signature=<empreinte>&cachet=<empreinte>`) — une image inchangée n'est pas renvoyée.
 * Lecture libre pour tout compte actif dont le poste concorde (comme `parametres_systeme`).
 */
class ImagesDocumentController
{
    public function __invoke(Request $request, ApparenceEtablissementService $apparence): JsonResponse
    {
        $utilisateur = $request->user();

        if (! $utilisateur instanceof User || ! $utilisateur->estActif()) {
            return response()->json(['message' => __('sync.referentiels.compte_inactif')], 401);
        }

        $poste = (string) $request->query('poste_id', '');

        if ($poste === '') {
            return response()->json(['message' => 'Le poste est obligatoire.', 'errors' => ['poste_id' => ['Le champ poste id est obligatoire.']]], 422);
        }

        if (! PosteDuJeton::concorde($request, $poste)) {
            return response()->json(['message' => __('sync.poste_non_reconnu')], 403);
        }

        $reponse = [];

        foreach (ApparenceEtablissementService::IMAGES_DOCUMENT as $type) {
            $octets = $apparence->octetsImageDocument($type);

            if ($octets === null) {
                $reponse[$type] = null;

                continue;
            }

            $empreinte = (string) $apparence->empreinteImageDocument($type);
            $reponse[$type] = [
                'empreinte' => $empreinte,
                'type' => (string) (new \finfo(FILEINFO_MIME_TYPE))->buffer($octets),
                // Inchangée côté poste : l'empreinte suffit, pas d'octets.
                'octets_base64' => $request->query($type) === $empreinte ? null : base64_encode($octets),
            ];
        }

        return response()->json(['data' => $reponse]);
    }
}
