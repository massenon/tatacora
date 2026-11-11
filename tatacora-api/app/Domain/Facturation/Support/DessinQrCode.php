<?php

declare(strict_types=1);

namespace App\Domain\Facturation\Support;

use BaconQrCode\Renderer\Image\SvgImageBackEnd;
use BaconQrCode\Renderer\ImageRenderer;
use BaconQrCode\Renderer\RendererStyle\RendererStyle;
use BaconQrCode\Writer;

/**
 * Dessine le QR code d'une facture NORMALISÉE (SVG intégré à la page).
 *
 * Il ne COMPOSE jamais le contenu : il dessine, tel quel, le texte que le boîtier
 * ou la DGI a RENDU (`qr_code_fiscal`). Un contenu vide ne dessine rien (null) : le
 * PDF n'invente pas de QR (PA-61).
 */
final class DessinQrCode
{
    /** Côté du dessin, en points (le PDF le redimensionne par `width`/`height`). */
    private const COTE = 240;

    /** Le QR en `data:` URI (image SVG), ou null si le contenu est vide. */
    public static function enDataUri(?string $contenu): ?string
    {
        if ($contenu === null || trim($contenu) === '') {
            return null;
        }

        $svg = (new Writer(new ImageRenderer(
            new RendererStyle(self::COTE, 1),
            new SvgImageBackEnd(),
        )))->writeString($contenu);

        return 'data:image/svg+xml;base64,'.base64_encode($svg);
    }
}
