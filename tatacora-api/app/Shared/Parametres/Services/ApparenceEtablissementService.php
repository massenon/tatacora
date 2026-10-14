<?php

declare(strict_types=1);

namespace App\Shared\Parametres\Services;

use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;

/**
 * Logo et favicon de l'établissement — téléversement RÉEL de l'onglet
 * « Logo & Apparence » (maître `parametres.html` l.103-131, porté le
 * 02/09/2026 sur directive Product Owner).
 *
 * ## Où vivent les fichiers, et pourquoi PAS dans `public/`
 *
 * Le disque `public` (`storage/app/public/apparence/`) — le même que les
 * justificatifs de dépense (`Depenses`). PAS `public/assets/img/` : ce
 * répertoire porte les actifs LIVRÉS du dépôt, et un fichier téléversé qui
 * écraserait `logo.png` réécrirait un fichier versionné depuis l'écran.
 *
 * ⚠ Aucun lien symbolique `storage:link` n'est requis — il n'est pas garanti
 * sur cPanel mutualisé (docs/CPANEL_DEPLOYMENT.md) et ce dépôt n'en pose pas :
 * les fichiers sont SERVIS par la route `pwa.apparence`
 * ({@see \App\Pwa\Http\Controllers\ApparenceController}), qui les lit du
 * disque. `Storage::url()` n'est jamais employé ici.
 *
 * ## Remplacé, jamais accumulé
 *
 * Un seul fichier par usage, au nom FIXE (`logo.<ext>`, `favicon.<ext>`) :
 * `enregistrer*()` supprime d'abord toute variante existante (l'ancien
 * `logo.png` quand on téléverse un `logo.jpg`), sinon le répertoire
 * accumulerait des fichiers morts et `chemin*()` pourrait rendre l'ancien.
 *
 * ## Qui lit
 *
 * - la barre supérieure de la PWA et le favicon du gabarit (`tete.blade.php`),
 *   par `urlLogo()` / `urlFavicon()` — l'actif livré reste le repli tant que
 *   rien n'est téléversé, ce qui laisse le rendu par défaut au pixel près ;
 * - l'en-tête des états (`ReportHeaderService::logo()`), par `cheminLogo()`.
 */
class ApparenceEtablissementService
{
    public const DISQUE = 'public';

    public const REPERTOIRE = 'apparence';

    /** Extensions admises — celles que le maître nomme (PNG/JPG, plus ICO pour le favicon). */
    public const EXTENSIONS_LOGO = ['png', 'jpg', 'jpeg'];

    public const EXTENSIONS_FAVICON = ['png', 'jpg', 'jpeg', 'ico'];

    /**
     * L'actif LIVRÉ du dépôt — le repli de toutes les surfaces tant que rien
     * n'est téléversé : barre supérieure, favicon, `ApparenceController`.
     *
     * Décision du Product Owner du 14/10/2026 (ticket D392) : nouveau logo,
     * PNG paysage 735 × 403 à fond blanc, qui remplace `logo.jpg` (rond,
     * carré). UN seul auteur de ce chemin côté serveur : les vues qui ne
     * passent pas par ce service l'écrivent en `asset(...)`, et
     * `LogoEtablissementTest` refuse toute référence restante à l'ancien.
     */
    public const ACTIF_LIVRE = 'assets/img/logo.png';

    public function enregistrerLogo(UploadedFile $fichier): void
    {
        $this->remplacer('logo', $fichier);
    }

    public function enregistrerFavicon(UploadedFile $fichier): void
    {
        $this->remplacer('favicon', $fichier);
    }

    /** Chemin ABSOLU du logo téléversé, ou `null` — pour dompdf (états). */
    public function cheminLogo(): ?string
    {
        $relatif = $this->fichierDe('logo');

        return $relatif === null ? null : Storage::disk(self::DISQUE)->path($relatif);
    }

    /** URL du logo à afficher : le téléversé s'il existe, sinon l'actif livré. */
    public function urlLogo(): string
    {
        return $this->fichierDe('logo') === null
            ? asset(self::ACTIF_LIVRE)
            : route('pwa.apparence', ['type' => 'logo', 'v' => $this->versionDe('logo')]);
    }

    public function urlFavicon(): string
    {
        return $this->fichierDe('favicon') === null
            ? asset(self::ACTIF_LIVRE)
            : route('pwa.apparence', ['type' => 'favicon', 'v' => $this->versionDe('favicon')]);
    }

    /** Le chemin RELATIF (disque `public`) du fichier téléversé de ce type, ou `null`. */
    public function fichierDe(string $type): ?string
    {
        foreach (Storage::disk(self::DISQUE)->files(self::REPERTOIRE) as $fichier) {
            if (pathinfo($fichier, PATHINFO_FILENAME) === $type) {
                return $fichier;
            }
        }

        return null;
    }

    private function remplacer(string $type, UploadedFile $fichier): void
    {
        $disque = Storage::disk(self::DISQUE);

        // L'ancien fichier part AVANT que le nouveau n'arrive : deux
        // extensions différentes cohabiteraient sinon, et `fichierDe()`
        // rendrait l'une des deux au hasard de l'ordre du répertoire.
        $existant = $this->fichierDe($type);

        if ($existant !== null) {
            $disque->delete($existant);
        }

        $extension = strtolower($fichier->getClientOriginalExtension() ?: (string) $fichier->extension());

        $fichier->storeAs(self::REPERTOIRE, $type . '.' . $extension, self::DISQUE);
    }

    /**
     * Horodatage du fichier, pour casser le cache navigateur au remplacement :
     * sans lui, l'ancien logo resterait affiché jusqu'au vidage manuel du
     * cache — et l'écran dirait le téléversement sans effet.
     */
    private function versionDe(string $type): int
    {
        $fichier = $this->fichierDe($type);

        return $fichier === null ? 0 : (int) Storage::disk(self::DISQUE)->lastModified($fichier);
    }
}
