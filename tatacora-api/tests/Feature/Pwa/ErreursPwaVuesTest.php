<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use Illuminate\Support\Facades\Lang;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Balayage de TOUS les fichiers `resources/views/errors/*.blade.php` :
 * gabarit commun, aucune chaîne en dur, toutes les clés de langue présentes.
 *
 * Le balayage lit le dossier, il ne récite pas une liste : une vue d'erreur
 * ajoutée demain est contrôlée sans toucher ce fichier. Un PLANCHER évite
 * qu'un dossier renommé rende le balayage vert à vide.
 *
 * Mutations éprouvées le 09/11/2026 :
 *  - `errors/403.blade.php` réduit à `<h1>Accès refusé</h1>` fait rougir
 *    `toutes_les_pages_utilisent_le_gabarit_commun` ET
 *    `aucune_vue_d_erreur_ne_contient_de_texte_en_dur` ;
 *  - un titre de `layout.blade.php` remplacé par du français en dur fait
 *    rougir `aucune_vue_d_erreur_ne_contient_de_texte_en_dur` ;
 *  - la clé `erreurs.419.aide` retirée de `lang/fr/erreurs.php` fait rougir
 *    `chaque_code_a_ses_cles_de_langue` ;
 *  — restaurés ensuite.
 */
final class ErreursPwaVuesTest extends TestCase
{
    private const PLANCHER = 19;

    /** @return list<string> */
    private function vues(): array
    {
        $vues = glob(resource_path('views/errors/*.blade.php')) ?: [];
        $this->assertGreaterThanOrEqual(self::PLANCHER, count($vues), 'Moins de vues d\'erreur que prévu.');

        return $vues;
    }

    #[Test]
    public function toutes_les_pages_utilisent_le_gabarit_commun(): void
    {
        foreach ($this->vues() as $vue) {
            if (basename($vue) === 'layout.blade.php') {
                continue;
            }
            $this->assertStringContainsString("@extends('errors.layout'", (string) file_get_contents($vue), basename($vue) . ' n\'utilise pas errors.layout.');
        }
    }

    #[Test]
    public function aucune_vue_d_erreur_ne_contient_de_texte_en_dur(): void
    {
        foreach ($this->vues() as $vue) {
            $source = (string) file_get_contents($vue);

            // On retire ce qui n'est pas du texte affiché : commentaires,
            // blocs PHP, feuille de style, dessins, expressions et directives.
            $nu = preg_replace('/\{\{--.*?--\}\}/s', '', $source) ?? '';
            $nu = preg_replace('#<style.*?</style>#s', '', $nu) ?? '';
            $nu = preg_replace('#<svg.*?</svg>#s', '', $nu) ?? '';
            $nu = preg_replace('/@php.*?@endphp/s', '', $nu) ?? '';
            $nu = preg_replace('/\{\{.*?\}\}|\{!!.*?!!\}/s', '', $nu) ?? '';
            $nu = preg_replace('/@(extends|isset|endisset|if|elseif|else|endif|foreach|endforeach|switch|case|break|default|endswitch)\b(\s*\((?:[^()]|\((?:[^()]|\([^()]*\))*\))*\))?/', '', $nu) ?? '';
            $attributs = $nu;
            $nu = preg_replace('/<[^>]*>/s', '', $nu) ?? '';

            $this->assertSame('', trim($nu), basename($vue) . ' : texte en dur « ' . trim($nu) . ' ».');

            foreach (['alt', 'title', 'aria-label', 'placeholder', 'content'] as $attribut) {
                preg_match_all('/\s' . $attribut . '="([^"]*)"/', $attributs, $valeurs);
                foreach ($valeurs[1] as $valeur) {
                    $this->assertMatchesRegularExpression(
                        '/^(\{\{.*\}\}|[0-9#A-Za-z,. =-]*)$/s',
                        $valeur,
                        basename($vue) . " : attribut {$attribut} en dur « {$valeur} ».",
                    );
                    $this->assertDoesNotMatchRegularExpression('/[éèàùçêôî]|\s(le|la|les|de|du|votre|une?)\s/u', $valeur);
                }
            }
        }
    }

    #[Test]
    public function chaque_code_a_ses_cles_de_langue(): void
    {
        $codes = [];
        foreach ($this->vues() as $vue) {
            if (preg_match('/^(\d{3})\.blade\.php$/', basename($vue), $m) === 1) {
                $codes[] = $m[1];
            }
        }
        $this->assertGreaterThanOrEqual(17, count($codes));

        foreach ([...$codes, 'generique_4xx', 'generique_5xx'] as $cle) {
            foreach (['titre', 'message'] as $champ) {
                $this->assertNotSame("erreurs.{$cle}.{$champ}", __("erreurs.{$cle}.{$champ}"), "Clé manquante erreurs.{$cle}.{$champ}");
                $this->assertNotSame('', trim((string) __("erreurs.{$cle}.{$champ}")));
            }
            $aide = Lang::get("erreurs.{$cle}.aide");
            $this->assertIsArray($aide, "erreurs.{$cle}.aide absente.");
            $this->assertNotEmpty($aide);
        }

        // Réciproque : toute entrée numérique de la langue a sa vue.
        foreach (array_keys((array) Lang::get('erreurs')) as $cle) {
            if (ctype_digit((string) $cle)) {
                $this->assertContains((string) $cle, $codes, "erreurs.{$cle} n'a pas de vue errors/{$cle}.blade.php.");
            }
        }
    }

    #[Test]
    public function toutes_les_cles_citees_par_le_gabarit_existent(): void
    {
        $source = (string) file_get_contents(resource_path('views/errors/layout.blade.php'));
        preg_match_all("/erreurs\.([a-z_]+(?:\.[a-z_]+)?)(?=['\"])/", $source, $trouvees);
        $this->assertNotEmpty($trouvees[0]);

        foreach (array_unique($trouvees[0]) as $cle) {
            $this->assertNotSame($cle, __($cle), "Clé manquante {$cle}.");
        }
        $this->assertNotSame('pwa.alt_logo', __('pwa.alt_logo'));
    }

    #[Test]
    public function chaque_vue_de_code_nomme_son_propre_code(): void
    {
        foreach ($this->vues() as $vue) {
            if (preg_match('/^(\d{3})\.blade\.php$/', basename($vue), $m) === 1) {
                $this->assertStringContainsString("'code' => {$m[1]},", (string) file_get_contents($vue), basename($vue));
            }
        }
    }
}
