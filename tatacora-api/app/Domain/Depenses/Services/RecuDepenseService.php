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
 * les règles `image` et `max:400` : mêmes types (jpg, jpeg, png, gif, bmp,
 * webp — jamais svg), même taille maximale, MÊMES PHRASES. Le type est lu du
 * CONTENU (`finfo`), jamais du nom du fichier. [controler] est la porte de
 * DÉPÔT (synchronisation) : elle reste stricte, 400 Ko au plus.
 *
 * ## Une image trop lourde est RÉDUITE, jamais refusée (PO, 28/10/2026)
 *
 * À la SAISIE — l'écran web et le poste —, le poids n'est plus une cause de
 * refus : [preparer] réduit l'image au lieu de la refuser. Seuls un fichier qui
 * n'est pas une image (mêmes phrases que le validateur) ou qu'on ne peut pas
 * lire comme une image ([RECU_ILLISIBLE]) sont refusés. La règle, IDENTIQUE
 * sur le poste (`reduction_recu.dart`) — mêmes constantes, confrontées par
 * `depenses_recu_contre_serveur_test.dart` :
 *
 *  1. un fichier de 400 Ko au plus est gardé TEL QUEL (octets, type et
 *     empreinte d'origine) — la réduction ne touche que l'excès ;
 *  2. sinon l'image est décodée, remise à l'endroit (orientation EXIF), mise
 *     sur fond BLANC (un JPEG n'a pas de transparence), ramenée à
 *     [COTE_MAX_PX] pixels sur son grand côté, puis encodée en JPEG à la
 *     première qualité de [QUALITES] qui tient en 400 Ko ;
 *  3. si aucune qualité ne suffit, les dimensions sont multipliées par
 *     [FACTEUR_REDUCTION] et on recommence, jusqu'à [COTE_MIN_PX] — plancher
 *     théorique : une image de 64 px tient toujours en 400 Ko.
 *
 * Le résultat est donc toujours un JPEG de 400 Ko au plus : c'est aussi ce que
 * le poste dépose, et que [controler] accepte à la synchronisation. Les
 * octets produits ne sont pas identiques d'un côté et de l'autre (deux
 * encodeurs) ; la RÈGLE l'est : même décision, même type, même borne.
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

    /** Grand côté maximal, en pixels, d'une image RÉDUITE. */
    public const COTE_MAX_PX = 2048;

    /** Qualités JPEG essayées, de la meilleure à la plus faible. */
    public const QUALITES = [85, 75, 65, 55, 45, 35];

    /** Facteur appliqué aux dimensions quand aucune qualité ne suffit. */
    public const FACTEUR_REDUCTION = 0.8;

    /** Plancher du grand côté : en dessous, on s'arrête (tient en 400 Ko). */
    public const COTE_MIN_PX = 64;

    /** Code de refus d'un fichier de type image qu'on ne sait pas décoder. */
    public const RECU_ILLISIBLE = 'recu_illisible';

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
    public function controler(string $octets, ?string $empreinteAnnoncee = null, bool $verifierPoids = true): array
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
                ['photoRecu' => ['required', 'image', ...($verifierPoids ? ['max:'.self::TAILLE_MAX_KO] : [])]],
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

    /**
     * Prépare le reçu SAISI (écran web) : le garde tel quel s'il tient en
     * 400 Ko, le RÉDUIT sinon. Refuse seulement un fichier vide, qui n'est pas
     * une image, ou illisible.
     *
     * @return array{octets: string, sha256: string, type: string, extension: string, reduit: bool, taille_origine: int}
     *
     * @throws RefusRecuDepense
     */
    public function preparer(string $octets): array
    {
        $origine = strlen($octets);

        // Le type d'abord, SANS le poids : un fichier lourd qui n'est pas une
        // image reste refusé par la phrase du validateur.
        $contenu = $this->controler($octets, null, false);

        if ($origine <= self::TAILLE_MAX_KO * 1024) {
            return [...$contenu, 'octets' => $octets, 'reduit' => false, 'taille_origine' => $origine];
        }

        $reduit = $this->reduire($octets);
        // Filet : ce qu'on remet passe la porte de dépôt, 400 Ko compris.
        $apres = $this->controler($reduit);

        return [...$apres, 'octets' => $reduit, 'reduit' => true, 'taille_origine' => $origine];
    }

    /**
     * Réduit une image trop lourde en JPEG de 400 Ko au plus (règle en tête de
     * classe).
     *
     * @throws RefusRecuDepense `recu_illisible` si le fichier n'est pas décodable
     */
    public function reduire(string $octets): string
    {
        $illisible = new RefusRecuDepense(self::RECU_ILLISIBLE, __('depenses.recu_illisible'));

        if (! function_exists('imagecreatefromstring')) {
            throw new \RuntimeException(__('depenses.recu_gd_requise'));
        }

        // Une photo de 24 Mpx décodée pèse ~100 Mo : le plafond par défaut de
        // PHP (128 Mo) ne suffit pas, le relever le temps de la réduction.
        $plafond = ini_get('memory_limit');
        if ($plafond !== '-1' && $this->enOctets((string) $plafond) < 768 * 1024 * 1024) {
            @ini_set('memory_limit', '768M');
        }

        $taille = @getimagesizefromstring($octets);
        $source = $taille === false ? false : @imagecreatefromstring($octets);

        if ($source === false) {
            throw $illisible;
        }

        try {
            $source = $this->remettreADroit($source, $octets);
            $largeur = imagesx($source);
            $hauteur = imagesy($source);

            $echelle = min(1.0, self::COTE_MAX_PX / max($largeur, $hauteur));
            $l = max(1, (int) round($largeur * $echelle));
            $h = max(1, (int) round($hauteur * $echelle));

            while (true) {
                $toile = imagecreatetruecolor($l, $h);
                // Fond BLANC : un JPEG n'a pas de transparence.
                imagefill($toile, 0, 0, (int) imagecolorallocate($toile, 255, 255, 255));
                imagecopyresampled($toile, $source, 0, 0, 0, 0, $l, $h, $largeur, $hauteur);

                $dernier = '';
                foreach (self::QUALITES as $qualite) {
                    ob_start();
                    imagejpeg($toile, null, $qualite);
                    $dernier = (string) ob_get_clean();

                    if (strlen($dernier) <= self::TAILLE_MAX_KO * 1024) {
                        return $dernier;
                    }
                }

                if (max($l, $h) <= self::COTE_MIN_PX) {
                    return $dernier;
                }

                $l = max(1, (int) floor($l * self::FACTEUR_REDUCTION));
                $h = max(1, (int) floor($h * self::FACTEUR_REDUCTION));
            }
        } finally {
            unset($source, $toile);
        }
    }

    /**
     * Applique l'orientation EXIF d'un JPEG (photo de téléphone prise en
     * portrait) : sans elle, la réduction — qui perd l'EXIF — coucherait l'image.
     */
    private function remettreADroit(\GdImage $image, string $octets): \GdImage
    {
        if (! function_exists('exif_read_data') || ! str_starts_with($octets, "\xFF\xD8")) {
            return $image;
        }

        $exif = @exif_read_data('data://image/jpeg;base64,'.base64_encode($octets));
        $orientation = is_array($exif) ? (int) ($exif['Orientation'] ?? 1) : 1;

        $angle = [3 => 180, 6 => -90, 8 => 90][$orientation] ?? 0;

        if ($angle === 0) {
            return $image;
        }

        $tournee = imagerotate($image, $angle, 0);

        return $tournee === false ? $image : $tournee;
    }

    private function enOctets(string $valeur): int
    {
        $n = (int) $valeur;

        return match (strtoupper(substr(trim($valeur), -1))) {
            'G' => $n * 1024 ** 3,
            'M' => $n * 1024 ** 2,
            'K' => $n * 1024,
            default => $n,
        };
    }

    private function typeDe(string $octets): string
    {
        $type = (new \finfo(FILEINFO_MIME_TYPE))->buffer($octets);

        return is_string($type) ? $type : 'application/octet-stream';
    }
}
