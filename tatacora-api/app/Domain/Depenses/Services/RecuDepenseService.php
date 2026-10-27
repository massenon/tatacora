<?php

declare(strict_types=1);

namespace App\Domain\Depenses\Services;

use App\Domain\Depenses\Exceptions\RefusRecuDepense;
use App\Domain\Depenses\Models\Depense;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Str;

/**
 * Le REÇU en image d'une dépense (lot L4, décision du PO du 27/10/2026).
 *
 * Deux portes, une seule règle :
 *
 *  * l'écran web (`Depenses::enregistrerDepense`) range le fichier choisi à la
 *    saisie (`photoRecu`, règle `nullable|image|max:400`) ;
 *  * le poste le DÉPOSE par `PUT /api/v1/sync/depenses/{depense}/recu`, après
 *    que la dépense est arrivée par `POST /sync` (un reçu ne précède jamais sa
 *    dépense).
 *
 * ## Les bornes sont CELLES DU WEB, par la même règle
 *
 * Le contenu est jugé par le validateur de Laravel sur un `UploadedFile`, avec
 * les règles `image` et `max:400` de l'écran : mêmes types (jpg, jpeg, png,
 * gif, bmp, webp — jamais svg), même taille maximale, MÊMES PHRASES. Le type
 * est lu du CONTENU (`finfo`), jamais du nom du fichier.
 *
 * ## Idempotent par empreinte
 *
 * Le dépôt rend l'empreinte SHA-256 du fichier. Le même fichier redéposé
 * (réponse perdue, coupure entre le traitement et l'accusé) n'écrit RIEN et
 * rend `rejeu`. Un AUTRE fichier sur une dépense qui porte déjà un reçu est
 * refusé (409) : un reçu ne se remplace pas, il appuie une pièce déjà passée.
 *
 * ## Sérialisé
 *
 * La ligne de la dépense est verrouillée pendant l'écriture : deux dépôts
 * simultanés du même fichier n'écrivent qu'une fois. Si l'enregistrement en
 * base échoue, le fichier rangé est retiré.
 */
final class RecuDepenseService
{
    /** Taille maximale du reçu, en kilo-octets — celle de l'écran web. */
    public const TAILLE_MAX_KO = 400;

    /** Le dossier du disque public (`storage/app/public`), comme le web. */
    public const DOSSIER = 'recus_depenses';

    /**
     * Dépose [octets] comme reçu de la dépense [depenseId].
     *
     * @return array{depense: Depense, rejeu: bool}
     *
     * @throws RefusRecuDepense
     */
    public function deposer(string $depenseId, string $octets, ?string $empreinteAnnoncee = null): array
    {
        $contenu = $this->controler($octets, $empreinteAnnoncee);

        return DB::transaction(function () use ($depenseId, $octets, $contenu): array {
            $depense = Depense::query()->whereKey($depenseId)->lockForUpdate()->first();

            if ($depense === null) {
                throw new RefusRecuDepense('depense_inconnue', __('depenses.recu_depense_inconnue'), 404);
            }

            $disque = Storage::disk('public');

            if ($depense->recu_path !== null) {
                if ($depense->recu_sha256 !== $contenu['sha256']) {
                    throw new RefusRecuDepense('recu_deja_rattache', __('depenses.recu_deja_rattache'), 409);
                }

                if ($disque->exists($depense->recu_path)) {
                    return ['depense' => $depense, 'rejeu' => true];
                }

                // Même empreinte, fichier disparu du disque : on le remet à sa place.
                $disque->put($depense->recu_path, $octets);

                return ['depense' => $depense, 'rejeu' => false];
            }

            $chemin = self::DOSSIER.'/'.Str::uuid()->toString().'.'.$contenu['extension'];
            $disque->put($chemin, $octets);

            try {
                $depense->update([
                    'recu_path' => $chemin,
                    'recu_sha256' => $contenu['sha256'],
                    'recu_taille' => strlen($octets),
                    'recu_type' => $contenu['type'],
                ]);
            } catch (\Throwable $e) {
                $disque->delete($chemin);

                throw $e;
            }

            return ['depense' => $depense->refresh(), 'rejeu' => false];
        });
    }

    /**
     * Le fichier du reçu : octets, type et empreinte, ou `null` sans reçu (ou
     * fichier introuvable). L'empreinte d'un reçu joint avant la migration
     * (colonnes vides) est calculée ici, jamais devinée.
     *
     * @return array{octets: string, type: string, sha256: string}|null
     */
    public function lire(Depense $depense): ?array
    {
        if ($depense->recu_path === null) {
            return null;
        }

        $disque = Storage::disk('public');

        if (! $disque->exists($depense->recu_path)) {
            return null;
        }

        $octets = (string) $disque->get($depense->recu_path);

        return [
            'octets' => $octets,
            'type' => $depense->recu_type ?? $this->typeDe($octets),
            'sha256' => $depense->recu_sha256 ?? hash('sha256', $octets),
        ];
    }

    /**
     * Juge le contenu avec les règles de l'écran web.
     *
     * @return array{sha256: string, type: string, extension: string}
     *
     * @throws RefusRecuDepense
     */
    public function controler(string $octets, ?string $empreinteAnnoncee = null): array
    {
        if ($octets === '') {
            throw new RefusRecuDepense('recu_invalide', __('depenses.recu_vide'));
        }

        $sha256 = hash('sha256', $octets);

        if ($empreinteAnnoncee !== null && ! hash_equals($sha256, strtolower($empreinteAnnoncee))) {
            throw new RefusRecuDepense('recu_empreinte', __('depenses.recu_empreinte'));
        }

        $temporaire = tempnam(sys_get_temp_dir(), 'recu');

        if ($temporaire === false) {
            throw new \RuntimeException('Fichier temporaire impossible.');
        }

        try {
            file_put_contents($temporaire, $octets);
            $fichier = new UploadedFile($temporaire, 'recu', null, null, true);

            $validateur = Validator::make(
                ['photoRecu' => $fichier],
                ['photoRecu' => ['required', 'image', 'max:'.self::TAILLE_MAX_KO]],
            );

            if ($validateur->fails()) {
                $trop = array_key_exists('Max', $validateur->failed()['photoRecu'] ?? []);

                throw new RefusRecuDepense(
                    $trop ? 'recu_trop_lourd' : 'recu_invalide',
                    (string) $validateur->errors()->first('photoRecu'),
                    $trop ? 413 : 422,
                );
            }

            return [
                'sha256' => $sha256,
                'type' => (string) $fichier->getMimeType(),
                'extension' => (string) ($fichier->guessExtension() ?? 'jpg'),
            ];
        } finally {
            @unlink($temporaire);
        }
    }

    private function typeDe(string $octets): string
    {
        $type = (new \finfo(FILEINFO_MIME_TYPE))->buffer($octets);

        return is_string($type) ? $type : 'application/octet-stream';
    }
}
