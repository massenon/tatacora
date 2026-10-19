<?php

declare(strict_types=1);

namespace Tests\Feature\Sync;

use App\Domain\Caisse\Models\SessionCaisse;
use App\Domain\Comptabilite\Models\EcritureComptable;
use App\Domain\Depenses\Models\Depense;
use App\Domain\Ventes\Models\Vente;
use App\Models\User;
use App\Shared\Sync\Models\AnomalieSynchronisation;
use App\Shared\Sync\Models\ConflitSynchronisation;
use App\Shared\Sync\Models\SessionSynchronisation;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\Feature\Sync\Concerns\PrepareLesDocuments;
use Tests\TestCase;

/**
 * Une JOURNÉE hors connexion poussée d'un bloc, dans l'ordre de la file du
 * poste — lot S3, décisions du Product Owner du 15/10/2026.
 *
 * Ouverture de caisse → trois ventes (espèces, Mobile Money, ticket mixte bar
 * + restaurant) → une dépense → clôture. Tout se synchronise, sans conflit ;
 * le théorique recalculé par le serveur compte les seules ventes en espèces
 * de la session ; chaque document a sa pièce, à la date du 14/10.
 */
final class FinDeJourneeSynchronisationTest extends TestCase
{
    use PrepareLesDocuments;
    use RefreshDatabase;

    private User $gerant;

    protected function setUp(): void
    {
        parent::setUp();
        $this->preparerLeDecor();

        $this->gerant = $this->creerUtilisateur('gerant');
    }

    #[Test]
    public function une_journee_entiere_se_synchronise_dans_l_ordre_du_poste(): void
    {
        $session = $this->uuid();
        $ventes = [$this->uuid(), $this->uuid(), $this->uuid()];
        $depense = $this->uuid();

        $lot = [
            $this->a('sessions_caisse', 'creation', $session, '07:00', [
                'point_vente' => 'bar', 'date_ouverture' => '2026-10-14 07:00:00', 'montant_fond_centimes' => 2000000,
            ]),
            $this->vente($ventes[0], $session, '11:15', 'especes', [$this->biere(3)]),
            $this->vente($ventes[1], $session, '13:40', 'mobile_money', [$this->biere(2)]),
            $this->vente($ventes[2], $session, '20:05', 'especes', [$this->biere(1), $this->plat(2)]),
            $this->a('depenses', 'creation', $depense, '15:00', [
                'date_transaction' => '2026-10-14', 'tresorerie' => 'caisse', 'libelle' => 'Glace pour le bar',
                'centre_libelle' => 'Bar',
                'lignes' => [['libelle' => 'Pains de glace', 'compte_charge' => '6011', 'nature' => 'Glace', 'famille' => 'Marché', 'montant' => 3000]],
            ]),
            // Fond 20 000 + espèces 3 000 + 6 000 = 29 000 au théorique ; le
            // poste a compté et calculé la même chose.
            $this->a('sessions_caisse', 'modification', $session, '22:00', [
                'date_cloture' => '2026-10-14 22:00:00',
                'montant_constate_centimes' => 2900000,
                'montant_theorique_centimes' => 2900000,
            ]),
        ];

        $reponse = $this->pousser($lot, $this->gerant);

        foreach (range(0, 5) as $rang) {
            $reponse->assertJsonPath("resultats.{$rang}.statut", 'synchronise');
        }

        $reponse->assertJsonPath('resultats.1.numero', 'V-2026-00001')
            ->assertJsonPath('resultats.2.numero', 'V-2026-00002')
            ->assertJsonPath('resultats.3.numero', 'V-2026-00003')
            ->assertJsonPath('resultats.3.montant_total', '6000.00')
            ->assertJsonPath('resultats.4.numero', 'DEP-2026-00001')
            ->assertJsonPath('resultats.5.montant_theorique', '29000.00')
            ->assertJsonPath('resultats.5.ecart', '0.00')
            ->assertJsonMissingPath('resultats.5.ecart_theorique');

        $this->assertSame('succes', SessionSynchronisation::sole()->statut);
        $this->assertSame(0, ConflitSynchronisation::count());
        $this->assertSame(0, AnomalieSynchronisation::count());

        $this->assertSame(3, Vente::where('session_id', $session)->count());
        $this->assertNotNull(SessionCaisse::findOrFail($session)->date_cloture);
        $this->assertSame('2026-10-14', Depense::findOrFail($depense)->date_transaction->toDateString());

        // Quatre pièces (trois ventes, une dépense), toutes datées du 14/10.
        $this->assertSame(4, EcritureComptable::query()->distinct()->count('numero_piece'));
        $this->assertSame(['2026-10-14'], EcritureComptable::query()->get()
            ->map(fn (EcritureComptable $e): string => $e->date_ecriture->toDateString())->unique()->values()->all());

        // Le lot entier rejoué (coupure avant la réponse) ne change rien.
        $this->pousser($lot, $this->gerant);
        $this->assertSame(3, Vente::count());
        $this->assertSame(1, Depense::count());
        $this->assertSame(4, EcritureComptable::query()->distinct()->count('numero_piece'));
    }

    /**
     * @param  array<string, mixed>  $payload
     * @return array<string, mixed>
     */
    private function a(string $table, string $type, string $id, string $heure, array $payload): array
    {
        return $this->operationDatee($table, $type, $id, $payload, '2026-10-14T' . $heure . ':00+00:00');
    }

    /**
     * @param  list<array<string, mixed>>  $lignes
     * @return array<string, mixed>
     */
    private function vente(string $id, string $session, string $heure, string $mode, array $lignes): array
    {
        $total = array_sum(array_map(static fn (array $l): int => $l['prix_unitaire'] * $l['quantite'], $lignes));

        return $this->a('ventes', 'creation', $id, $heure, [
            'type_vente' => 'comptant', 'mode_paiement' => $mode, 'session_encaissement_id' => $session,
            'cloture_le' => '2026-10-14 ' . $heure . ':00', 'point_vente' => 'Bar', 'montant_cloture' => $total,
            'lignes' => $lignes,
        ]);
    }

    /**
     * @return array<string, mixed>
     */
    private function biere(int $quantite): array
    {
        return ['module_source' => 'M5', 'code_article' => $this->biere->id, 'prix_unitaire' => 1000, 'quantite' => $quantite];
    }

    /**
     * @return array<string, mixed>
     */
    private function plat(int $quantite): array
    {
        return ['module_source' => 'M4', 'code_article' => $this->platRiz->id, 'prix_unitaire' => 2500, 'quantite' => $quantite];
    }
}
