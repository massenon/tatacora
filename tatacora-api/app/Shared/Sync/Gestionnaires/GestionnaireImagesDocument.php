<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Pwa\Livewire\Transverse\Parametres;
use App\Shared\Parametres\Models\DepotImageDocument;
use App\Shared\Parametres\Services\ApparenceEtablissementService;
use App\Shared\Sync\Support\ContexteSynchronisation;
use App\Shared\Sync\Support\EcritureSynchronisee;
use RuntimeException;

/**
 * La SIGNATURE et le CACHET des documents A4, déposés ou retirés DEPUIS UN POSTE
 * (décision du PO du 11/11/2026 : « téléverser la signature et le cachet depuis le poste,
 * comme au web »).
 *
 * ## Même service, mêmes règles que le web
 *
 * L'image est rangée par `ApparenceEtablissementService::enregistrerImageDocument` — le service
 * de l'écran web (Paramètres › Identité & Légal) : type lu des OCTETS, gardée telle quelle jusqu'à
 * 400 Ko, réduite en JPEG sinon, ancien fichier remplacé. Le retrait passe par
 * `retirerImageDocument`. En plus, la porte de la synchronisation est stricte : image PNG, JPEG ou
 * WebP (celles que l'écran annonce), type annoncé conforme au type lu, 400 Ko au plus (le poste
 * réduit avant d'envoyer).
 *
 * ## Une opération = un geste
 *
 * Création seule, sous un identifiant propre au geste (UUID du poste) : `{nature, action,
 * type_mime, octets_base64}`. Rejouée (réponse perdue), elle rend le résultat d'origine sans rien
 * réécrire. L'ordre des gestes est celui de la file du poste (`seq`) ; le dernier arrivé gagne,
 * comme entre deux administrateurs au web.
 *
 * ## Aucun droit du compte d'appairage (liste fermée `OperationsSensibles` inchangée)
 *
 * Le serveur ne juge pas le module du compte du jeton : l'écran du poste est réservé aux
 * administrateurs (RBAC local). Module `PARAM`, celui de l'écran, pour classer l'opération et
 * fonder le droit de CORRIGER au web.
 *
 * Les octets ne sont jamais conservés au journal de réception (`octets_base64` y est masqué) :
 * le fichier rangé est la seule copie côté serveur.
 */
final class GestionnaireImagesDocument extends GestionnaireAbstrait
{
    /** Les types que la porte de synchronisation admet (type lu des octets). */
    public const TYPES_ADMIS = ['image/png', 'image/jpeg', 'image/webp'];

    /** 400 Ko — la borne du web, `RecuDepenseService::TAILLE_MAX_KO`. */
    public const TAILLE_MAX_OCTETS = 400 * 1024;

    public function __construct(private readonly ApparenceEtablissementService $apparence)
    {
    }

    public function table(): string
    {
        return 'depots_images_document';
    }

    public function module(): string
    {
        return Parametres::MODULE;
    }

    public function serviceDomaine(): string
    {
        return ApparenceEtablissementService::class;
    }

    public function reprendreExistant(string $entiteId, ContexteSynchronisation $contexte): ?EcritureSynchronisee
    {
        $depot = DepotImageDocument::query()->find($entiteId);

        return $depot === null ? null : $this->resultat($depot);
    }

    public function creer(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $nature = (string) ($payload['nature'] ?? '');
        $action = (string) ($payload['action'] ?? '');

        if (! in_array($nature, ApparenceEtablissementService::IMAGES_DOCUMENT, true)) {
            throw new RuntimeException(__('sync.images_document.nature_inconnue'));
        }

        $empreinte = null;
        $mime = null;

        if ($action === DepotImageDocument::ACTION_RETIRER) {
            $this->apparence->retirerImageDocument($nature);
        } elseif ($action === DepotImageDocument::ACTION_DEPOSER) {
            $octets = $this->octets($payload);
            $mime = $this->typeLu($octets, $payload);
            // Le service du web : refus d'un fichier vide ou qui n'est pas une image.
            $this->apparence->enregistrerImageDocument($nature, $octets);
            $empreinte = $this->apparence->empreinteImageDocument($nature);
        } else {
            throw new RuntimeException(__('sync.images_document.action_inconnue'));
        }

        $depot = DepotImageDocument::query()->create([
            'id' => $entiteId,
            'nature' => $nature,
            'action' => $action,
            'type_mime' => $mime,
            'empreinte' => $empreinte,
            'poste_id' => $contexte->posteId,
            'auteur_id' => $contexte->utilisateur->id,
        ]);

        return $this->resultat($depot);
    }

    private function resultat(DepotImageDocument $depot): EcritureSynchronisee
    {
        return new EcritureSynchronisee($depot->id, complements: array_filter([
            'nature' => $depot->nature,
            'action' => $depot->action,
            'empreinte' => $depot->empreinte,
        ], static fn (mixed $v): bool => $v !== null));
    }

    /** @param  array<string, mixed>  $payload */
    private function octets(array $payload): string
    {
        $base64 = $payload['octets_base64'] ?? null;
        $octets = is_string($base64) && $base64 !== '' ? base64_decode($base64, true) : false;

        if ($octets === false || $octets === '') {
            throw new RuntimeException(__('sync.images_document.contenu_illisible'));
        }

        if (strlen($octets) > self::TAILLE_MAX_OCTETS) {
            throw new RuntimeException(__('sync.images_document.trop_lourde'));
        }

        return $octets;
    }

    /**
     * Le type LU des octets — jamais l'extension, jamais le type annoncé seul.
     *
     * @param  array<string, mixed>  $payload
     */
    private function typeLu(string $octets, array $payload): string
    {
        $reel = (string) (new \finfo(FILEINFO_MIME_TYPE))->buffer($octets);

        if (! in_array($reel, self::TYPES_ADMIS, true)) {
            throw new RuntimeException(__('sync.images_document.type_non_admis'));
        }

        $annonce = (string) ($payload['type_mime'] ?? '');

        if ($annonce !== '' && $annonce !== $reel) {
            throw new RuntimeException(__('sync.images_document.type_annonce_different', ['annonce' => $annonce, 'reel' => $reel]));
        }

        return $reel;
    }
}
