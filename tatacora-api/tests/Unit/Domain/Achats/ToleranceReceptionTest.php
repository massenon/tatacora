<?php

declare(strict_types=1);

namespace Tests\Unit\Domain\Achats;

use App\Domain\Achats\Services\ReceptionService;
use App\Domain\Stocks\Services\MouvementStockService;
use App\Shared\Parametres\Services\ParametreSystemeService;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Arithmétique de tolérance de réception — RG-10, EF-M7-03.
 *
 * ## Ce que ce calcul décide
 *
 * « Une commande ne peut être clôturée que si la quantité réceptionnée
 * correspond, dans une tolérance paramétrable, à la quantité commandée. »
 * Trois issues, aux conséquences très différentes :
 *
 * - `totale` → la commande devient clôturable, la créance est soldée ;
 * - `partielle` → la créance sur le fournisseur reste ouverte ;
 * - `non_conforme` → excédent facturable non commandé.
 *
 * Se tromper de sens sur la comparaison solderait une créance de 5 sacs de riz
 * sur un fournisseur qui ne les a jamais livrés.
 *
 * ## Pourquoi unitaire
 *
 * `evaluerConformite()` exige un `CommandeAchat` avec ses lignes persistées :
 * chaque cas de bord coûtait une commande, un fournisseur, un utilisateur et
 * 23 migrations. Les cas qui comptent — **pile sur la tolérance**, un centième
 * en deçà, un centième au-delà — n'étaient donc pas écrits. Ils le sont ici.
 */
final class ToleranceReceptionTest extends TestCase
{
    private function service(): ReceptionService
    {
        // Aucune des deux dépendances n'est sollicitée par le calcul pur.
        return new ReceptionService(
            $this->createStub(MouvementStockService::class),
            $this->createStub(ParametreSystemeService::class),
        );
    }

    // --------------------------------------------------------- Le pourcentage

    /**
     * @param  string  $recue  quantité réellement livrée
     * @param  string  $commandee  quantité de la commande
     * @param  string  $attendu  écart en pourcentage, signé
     */
    #[Test]
    #[DataProvider('ecarts')]
    public function l_ecart_est_relatif_a_la_quantite_commandee(
        string $recue,
        string $commandee,
        string $attendu,
    ): void {
        $this->assertSame($attendu, $this->service()->ecartPourcentage($recue, $commandee));
    }

    /**
     * @return array<string, array{string, string, string}>
     */
    public static function ecarts(): array
    {
        return [
            'livraison exacte' => ['30.00', '30.00', '0.00'],
            'manquant de 5 sacs sur 30' => ['25.00', '30.00', '-16.66'],
            'excédent de 1 sur 30' => ['31.00', '30.00', '3.33'],
            'rien livré' => ['0.00', '30.00', '-100.00'],
            'double livraison' => ['60.00', '30.00', '100.00'],
            'écart au centième' => ['49.99', '50.00', '-0.02'],
        ];
    }

    /**
     * Division par zéro : une ligne commandée à 0 qui recevrait de la
     * marchandise ferait entrer du stock sans commande en face.
     */
    #[Test]
    public function une_quantite_commandee_nulle_ne_produit_pas_une_conformite_silencieuse(): void
    {
        $service = $this->service();

        // Rien commandé, rien reçu : cohérent.
        $this->assertSame('0.00', $service->ecartPourcentage('0.00', '0.00'));
        $this->assertSame('totale', $service->conformiteLigne('0.00', '0.00', '2.00'));

        // Rien commandé, 50 sacs reçus : aucune tolérance ne peut l'absorber.
        $this->assertSame(ReceptionService::ECART_INCALCULABLE, $service->ecartPourcentage('50.00', '0.00'));
        $this->assertSame('non_conforme', $service->conformiteLigne('50.00', '0.00', '2.00'));
        $this->assertSame('non_conforme', $service->conformiteLigne('50.00', '0.00', '99.00'));
    }

    // ------------------------------------------------------------- Le verdict

    /**
     * Les trois cas de bord exacts autour du seuil, que seul un test unitaire
     * rend praticables à écrire.
     */
    #[Test]
    public function la_tolerance_est_inclusive_a_ses_deux_bornes(): void
    {
        $service = $this->service();

        // Tolérance 2 % sur 100 unités → la bande [98 ; 102] est conforme.
        $this->assertSame('totale', $service->conformiteLigne('98.00', '100.00', '2.00'));
        $this->assertSame('totale', $service->conformiteLigne('102.00', '100.00', '2.00'));

        // Un centième au-delà de chaque borne bascule.
        $this->assertSame('partielle', $service->conformiteLigne('97.99', '100.00', '2.00'));
        $this->assertSame('non_conforme', $service->conformiteLigne('102.01', '100.00', '2.00'));
    }

    /**
     * Le manquant et l'excédent ne sont pas symétriques dans leurs
     * conséquences : un manquant laisse une créance ouverte (`partielle`,
     * rattrapable par une réception complémentaire), un excédent est une
     * facture non commandée (`non_conforme`, à faire acter).
     */
    #[Test]
    public function manquant_et_excedent_ne_recoivent_pas_le_meme_verdict(): void
    {
        $service = $this->service();

        $this->assertSame('partielle', $service->conformiteLigne('25.00', '30.00', '2.00'));
        $this->assertSame('non_conforme', $service->conformiteLigne('35.00', '30.00', '2.00'));
    }

    /**
     * La tolérance vient de `parametres_systeme` : la faire varier doit
     * changer le verdict sur des quantités identiques, sans quoi une valeur
     * serait codée en dur quelque part.
     */
    #[Test]
    public function le_verdict_suit_la_tolerance_configuree(): void
    {
        $service = $this->service();

        // 29 sur 30 = −3,33 %.
        $this->assertSame('partielle', $service->conformiteLigne('29.00', '30.00', '2.00'));
        $this->assertSame('totale', $service->conformiteLigne('29.00', '30.00', '5.00'));
    }

    /**
     * Tolérance nulle : seule l'exactitude passe. C'est une configuration
     * légitime pour un article sensible, elle ne doit pas se comporter comme
     * une tolérance absente.
     */
    #[Test]
    public function une_tolerance_nulle_n_accepte_que_la_livraison_exacte(): void
    {
        $service = $this->service();

        $this->assertSame('totale', $service->conformiteLigne('30.00', '30.00', '0.00'));
        $this->assertSame('partielle', $service->conformiteLigne('29.99', '30.00', '0.00'));
        $this->assertSame('non_conforme', $service->conformiteLigne('30.01', '30.00', '0.00'));
    }

    /**
     * Le cas réel qui a motivé une tolérance paramétrable : un fournisseur
     * livrant 99,5 % d'un sac de riz de 50 kg n'est pas en défaut.
     */
    #[Test]
    public function le_cas_documente_du_sac_de_riz_est_bien_tolere(): void
    {
        // 49,75 kg sur 50 = −0,50 %, sous une tolérance de 2 %.
        $this->assertSame('totale', $this->service()->conformiteLigne('49.75', '50.00', '2.00'));
    }
}
