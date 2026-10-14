<?php

declare(strict_types=1);

namespace App\Domain\Ventes\Services;

use App\Domain\Ventes\Models\Panier;
use App\Domain\Ventes\Models\TableSalle;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Espaces et tables du point de vente — l'UNIQUE auteur des règles du maître
 * (`prototype_v2/assets/js/tables-engine.js`), porté au serveur le 02/09/2026
 * (directive Product Owner, onglet « Espaces & tables » de Paramètres).
 *
 * ## Les règles, chacune avec sa raison (celle du maître)
 *
 * - **Les numéros ne sont pas codés dans le logiciel** : créer, renuméroter,
 *   activer/désactiver, sans intervention technique. Seuls les ESPACES sont
 *   un registre fermé — ajouter un espace change la convention de nommage et
 *   l'organisation du service.
 * - **Le Comptoir n'a pas de table, structurellement** : une vente au
 *   comptoir n'en exige aucune (`table_id` nul). Lui en inventer une créerait
 *   une table à ouvrir, fermer et compter, qui ne correspond à rien.
 * - **Jamais de suppression** : une table se désactive. La supprimer
 *   laisserait les ventes passées pointer un identifiant inexistant (RG-02).
 * - **Une table au panier OUVERT ne se désactive pas** : les consommations
 *   servies n'auraient plus de table pour les porter jusqu'à l'addition.
 *   L'occupation se LIT des paniers réels, jamais d'un drapeau.
 * - **Le libellé SUIT le numéro** (préfixe + numéro) : figé, une table « R3 »
 *   portant le numéro 5 rendrait la salle illisible.
 *
 * ## Refus : `RuntimeException` traduite
 *
 * Même contrat que `CanalReservationService` et `EnregistrerParametreService`,
 * les deux autres services d'écriture de l'écran Paramètres : le composant
 * attrape et affiche sous le champ.
 *
 * @see RG-02 aucune suppression
 * @see RG-10 paramétrage sans déploiement
 */
class TableSalleService
{
    /**
     * Le registre FERMÉ des espaces du maître (`tables-engine.js`, ESPACES).
     *
     * @var list<array{cle: string, libelle: string, prefixe: string, avecTables: bool}>
     */
    public const ESPACES = [
        ['cle' => 'restaurant', 'libelle' => 'Restaurant', 'prefixe' => 'R', 'avecTables' => true],
        ['cle' => 'jardin', 'libelle' => 'Jardin', 'prefixe' => 'J', 'avecTables' => true],
        ['cle' => 'plage', 'libelle' => 'Plage', 'prefixe' => 'P', 'avecTables' => true],
        ['cle' => 'comptoir', 'libelle' => 'Comptoir', 'prefixe' => '', 'avecTables' => false],
    ];

    /**
     * Le JEU INITIAL du maître (`tables-engine.js`, `jeuInitial()`) — treize
     * tables : six au restaurant, quatre au jardin, trois à la plage, quatre
     * places chacune. Valeurs de DÉMARRAGE, pas une vérité : l'exploitant les
     * ajuste depuis Paramètres. UN SEUL AUTEUR : `TablesSalleSeeder` sème par
     * `retablirJeuInitial()`, jamais par une seconde liste.
     *
     * @var array<string, int>
     */
    public const JEU_INITIAL = [
        'restaurant' => 6,
        'jardin' => 4,
        'plage' => 3,
    ];

    public const PLACES_PAR_DEFAUT = 4;

    /**
     * @return array{cle: string, libelle: string, prefixe: string, avecTables: bool}|null
     */
    public static function espace(string $cle): ?array
    {
        foreach (self::ESPACES as $espace) {
            if ($espace['cle'] === $cle) {
                return $espace;
            }
        }

        return null;
    }

    /**
     * Le plan de salle du POS : les tables ACTIVES, groupées par libellé
     * d'espace, triées par numéro — la forme exacte qu'attendait l'écran du
     * temps du registre codé en dur, pour que la vue n'ait rien à savoir.
     *
     * @return array<string, list<array{id: string, libelle: string, places: int}>>
     */
    public function planDeSalle(): array
    {
        $tables = TableSalle::query()
            ->where('actif', true)
            ->orderBy('numero')
            ->get()
            ->groupBy('espace');

        $plan = [];

        foreach (self::ESPACES as $espace) {
            if (! $espace['avecTables']) {
                continue;
            }

            $plan[$espace['libelle']] = $tables->get($espace['cle'], collect())
                ->map(static fn (TableSalle $table): array => [
                    'id' => $table->id,
                    'libelle' => $table->libelle,
                    'places' => $table->places,
                ])
                ->values()
                ->all();
        }

        return $plan;
    }

    /**
     * Toutes les tables, actives ET désactivées, groupées par clé d'espace —
     * l'écran Paramètres montre tout : une table absente laisserait croire
     * qu'elle n'existe pas, et un serveur la chercherait.
     *
     * @return array<string, \Illuminate\Support\Collection<int, TableSalle>>
     */
    public function parEspace(): array
    {
        $tables = TableSalle::query()->orderBy('numero')->get()->groupBy('espace');

        $resultat = [];

        foreach (self::ESPACES as $espace) {
            if ($espace['avecTables']) {
                $resultat[$espace['cle']] = $tables->get($espace['cle'], collect())->values();
            }
        }

        return $resultat;
    }

    public function creer(string $cleEspace, int $numero, ?int $places = null): TableSalle
    {
        $espace = self::espace($cleEspace);

        if ($espace === null) {
            throw new RuntimeException(__('ventes.table_espace_inconnu', ['espace' => $cleEspace]));
        }

        if (! $espace['avecTables']) {
            throw new RuntimeException(__('ventes.table_comptoir_sans_table'));
        }

        $this->refuserNumero($cleEspace, $numero, $espace['prefixe']);

        return TableSalle::create([
            'espace' => $cleEspace,
            'numero' => $numero,
            'libelle' => $espace['prefixe'] . $numero,
            'places' => $places ?? self::PLACES_PAR_DEFAUT,
            'actif' => true,
        ]);
    }

    public function renumeroter(string $id, int $numero): TableSalle
    {
        $table = $this->tableOuRefus($id);
        $espace = self::espace($table->espace);

        if ($espace === null) {
            throw new RuntimeException(__('ventes.table_espace_inconnu', ['espace' => $table->espace]));
        }

        if ($numero !== $table->numero) {
            $this->refuserNumero($table->espace, $numero, $espace['prefixe'], $table->id);
        }

        // Le libellé SUIT le numéro — jamais figé (tables-engine.js).
        $table->numero = $numero;
        $table->libelle = $espace['prefixe'] . $numero;
        $table->save();

        return $table;
    }

    /**
     * Active ou désactive — jamais de suppression, et le refus du maître :
     * une table au panier OUVERT ne se désactive pas.
     */
    public function basculer(string $id): TableSalle
    {
        $table = $this->tableOuRefus($id);

        if ($table->actif && $this->estOccupee($table->id)) {
            throw new RuntimeException(__('ventes.table_panier_ouvert', ['libelle' => $table->libelle]));
        }

        $table->actif = ! $table->actif;
        $table->save();

        return $table;
    }

    /**
     * L'occupation se DÉDUIT des paniers réels — jamais un drapeau stocké
     * (même raison que `tables-engine.js::estOccupee`, et PA-126).
     */
    public function estOccupee(string $tableId): bool
    {
        return Panier::query()
            ->where('statut', Panier::STATUT_OUVERT)
            ->where('table_id', $tableId)
            ->exists();
    }

    /**
     * « Rétablir le jeu initial » — les treize tables du seeder, SANS toucher
     * les ventes (maître : « Les ventes déjà enregistrées ne sont pas
     * touchées »). Transposition serveur, où rien ne se supprime :
     *
     * - une table du jeu initial absente est CRÉÉE ; présente, elle est
     *   réactivée et remise à quatre places ;
     * - une table HORS du jeu initial est DÉSACTIVÉE, jamais supprimée — ses
     *   ventes passées continuent de la citer ;
     * - une table au panier OUVERT fait refuser l'opération ENTIÈRE, avant
     *   toute écriture : la rétablir à moitié laisserait la salle dans un
     *   état que personne n'a demandé.
     */
    public function retablirJeuInitial(): void
    {
        DB::transaction(function (): void {
            $ouvertes = TableSalle::query()
                ->get()
                ->filter(fn (TableSalle $table): bool => $this->estOccupee($table->id));

            if ($ouvertes->isNotEmpty()) {
                throw new RuntimeException(__('ventes.table_jeu_initial_paniers_ouverts', [
                    'libelles' => $ouvertes->pluck('libelle')->implode(', '),
                ]));
            }

            $conservees = [];

            foreach (self::JEU_INITIAL as $cleEspace => $combien) {
                $espace = self::espace($cleEspace);

                if ($espace === null) {
                    continue;
                }

                for ($numero = 1; $numero <= $combien; $numero++) {
                    $table = TableSalle::query()
                        ->where('espace', $cleEspace)
                        ->where('numero', $numero)
                        ->first();

                    if ($table === null) {
                        $table = $this->creer($cleEspace, $numero);
                    } else {
                        $table->libelle = $espace['prefixe'] . $numero;
                        $table->places = self::PLACES_PAR_DEFAUT;
                        $table->actif = true;
                        $table->save();
                    }

                    $conservees[] = $table->id;
                }
            }

            TableSalle::query()
                ->whereNotIn('id', $conservees)
                ->where('actif', true)
                ->get()
                ->each(static function (TableSalle $table): void {
                    $table->actif = false;
                    $table->save();
                });
        });
    }

    private function tableOuRefus(string $id): TableSalle
    {
        $table = TableSalle::find($id);

        if ($table === null) {
            throw new RuntimeException(__('ventes.table_introuvable'));
        }

        return $table;
    }

    private function refuserNumero(string $cleEspace, int $numero, string $prefixe, ?string $saufId = null): void
    {
        if ($numero < 1) {
            throw new RuntimeException(__('ventes.table_numero_invalide'));
        }

        $doublon = TableSalle::query()
            ->where('espace', $cleEspace)
            ->where('numero', $numero)
            ->when($saufId !== null, static fn ($requete) => $requete->whereKeyNot($saufId))
            ->exists();

        if ($doublon) {
            throw new RuntimeException(__('ventes.table_existe_deja', ['libelle' => $prefixe . $numero]));
        }
    }
}
