<?php

declare(strict_types=1);

namespace Tests\Unit\Pwa;

use App\Pwa\Support\MenuLateral;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\TestCase;

/**
 * L'etat actif du menu lateral — exacte d'abord, FAMILLE en repli (audit du
 * 01/09/2026 : naviguer d'un onglet-route a l'autre eteignait la
 * surbrillance de la page active).
 *
 * Les deux garde-fous sont eprouves, pas seulement le cas nominal : une
 * entree exacte existante eteint le repli (jamais deux entrees allumees), et
 * une famille a deux entrees n'allume rien (jamais un choix arbitraire).
 */
final class MenuLateralActifTest extends TestCase
{
    #[Test]
    public function la_route_exacte_est_active(): void
    {
        $this->assertTrue(MenuLateral::estActif('pwa.paie', 'pwa.paie'));
    }

    #[Test]
    public function une_sous_route_allume_l_entree_de_sa_famille(): void
    {
        // /pwa/comptabilite/journal n'a pas d'entree : « Comptabilite »
        // (pwa.comptabilite.hub) reste allumee.
        $this->assertTrue(MenuLateral::estActif('pwa.comptabilite.hub', 'pwa.comptabilite.journal'));
        $this->assertTrue(MenuLateral::estActif('pwa.restaurant.carte', 'pwa.restaurant.plats'));
        $this->assertTrue(MenuLateral::estActif('pwa.etats.studio', 'pwa.etats.bibliotheque'));
    }

    #[Test]
    public function une_entree_exacte_existante_eteint_le_repli(): void
    {
        // « Inventaires & Fiches » a sa propre entree : « Stocks » ne
        // s'allume pas en meme temps qu'elle.
        $this->assertFalse(MenuLateral::estActif('pwa.stocks.liste', 'pwa.stocks.inventaires'));
    }

    #[Test]
    public function une_famille_a_deux_entrees_n_allume_rien(): void
    {
        // Le ticket thermique partage `pwa.pos` avec les DEUX POS : allumer
        // l'un des deux serait un choix arbitraire.
        $this->assertFalse(MenuLateral::estActif('pwa.pos.comptant', 'pwa.pos.ticket-thermique'));
        $this->assertFalse(MenuLateral::estActif('pwa.pos.heberges', 'pwa.pos.ticket-thermique'));
    }

    #[Test]
    public function une_famille_etrangere_n_allume_rien(): void
    {
        $this->assertFalse(MenuLateral::estActif('pwa.paie', 'pwa.comptabilite.journal'));
    }
}
