<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Services;

use App\Domain\Comptabilite\Models\CompteComptable;
use App\Domain\Comptabilite\Support\RolesCorrespondance;
use App\Shared\Parametres\Services\ParametreSystemeService;
use InvalidArgumentException;
use RuntimeException;

/**
 * La correspondance rôle -> compte comptable, MODIFIABLE — décision du PO du
 * 26/10/2026 (« on peut impérativement modifier les comptes sur poste et le
 * web »).
 *
 * ## Un rôle vaut sa valeur choisie, sinon son défaut
 *
 * Chaque rôle de {@see RolesCorrespondance::ROLES} a un paramètre
 * `compte_<rôle>` (registre fermé des paramètres, donc dernier écrit gagnant,
 * synchronisé avec les postes). Absent ou vide : le rôle vaut la constante de
 * `ComptesSyscohada`. Les services qui passent une pièce appellent
 * {@see self::compte()} AU MOMENT de la passer — jamais la constante.
 *
 * ## Une pièce déjà passée n'est JAMAIS réécrite (RG-11)
 *
 * Changer un rôle vaut pour les pièces FUTURES. Les états qui relisent un
 * compte sur une période (déclaration de TVA, résultat) lisent donc AUSSI
 * l'ancien : {@see self::comptesLus()} rend le compte choisi et le défaut. Les
 * valeurs intermédiaires d'un rôle changé plusieurs fois ne sont retrouvées que
 * dans le journal d'audit (écart assumé).
 *
 * ## La validation est UNE : ici
 *
 * {@see self::verifier()} est appelée par `EnregistrerParametreService` pour
 * toute clé de ce groupe, donc par l'écran du web ET par la synchronisation
 * d'un poste : aucun chemin ne la contourne. Quatre refus, dans cet ordre :
 * format (`PlanComptableService::NUMERO_COMPTE_FORMAT`, la règle unique),
 * existence au plan, classe cohérente avec le rôle, compte imputable (pas une division).
 *
 * @see RG-10 paramétrage sans déploiement
 * @see RG-11 immutabilité des pièces validées
 */
class CorrespondanceComptesService
{
    public const PREFIXE_CLE = 'compte_';

    public function __construct(
        private readonly ParametreSystemeService $parametres,
    ) {
    }

    /** La clé de paramètre d'un rôle : `compte_produit_locations`. */
    public static function cle(string $role): string
    {
        return self::PREFIXE_CLE . strtolower($role);
    }

    /** Le rôle d'une clé de paramètre, ou null si ce n'est pas une clé de rôle. */
    public static function roleDeCle(string $cle): ?string
    {
        if (! str_starts_with($cle, self::PREFIXE_CLE)) {
            return null;
        }

        $role = strtoupper(substr($cle, strlen(self::PREFIXE_CLE)));

        return RolesCorrespondance::existe($role) ? $role : null;
    }

    /**
     * Le compte d'un rôle, à l'instant de passer une pièce : le compte choisi,
     * à défaut le défaut du rôle.
     */
    public function compte(string $role): string
    {
        $this->exigerRole($role);

        $choisi = trim((string) $this->parametres->get(self::cle($role)));

        return $choisi !== '' ? $choisi : RolesCorrespondance::defaut($role);
    }

    /**
     * Les comptes qu'un ÉTAT doit relire pour ce rôle : le compte choisi ET le
     * défaut (les pièces d'avant le changement y sont restées).
     *
     * @return list<string>
     */
    public function comptesLus(string $role): array
    {
        return array_values(array_unique([$this->compte($role), RolesCorrespondance::defaut($role)]));
    }

    /**
     * Le compte désigné par un rôle de TRÉSORERIE du registre des dépenses
     * (`caisse`, `momo`, `banque`).
     */
    public function compteDeTresorerie(string $code): string
    {
        return $this->compte(self::roleDeTresorerie($code));
    }

    /**
     * Le rôle d'une trésorerie du registre des dépenses (`caisse`, `momo`,
     * `banque`).
     */
    public static function roleDeTresorerie(string $code): string
    {
        return match ($code) {
            'caisse' => 'CAISSE',
            'momo' => 'MOBILE_MONEY',
            'banque' => 'BANQUE',
            default => throw new InvalidArgumentException("Unknown treasury code: {$code}"),
        };
    }

    /**
     * Les trois refus de la correspondance, dans l'ordre.
     *
     * @throws RuntimeException format, compte absent du plan, classe incohérente
     */
    public function verifier(string $role, string $numero): void
    {
        $this->exigerRole($role);

        if (! preg_match(PlanComptableService::NUMERO_COMPTE_FORMAT, $numero)) {
            throw new RuntimeException(__('comptabilite.compte_numero_invalide', ['numero' => $numero]));
        }

        $compte = CompteComptable::query()->where('numero_compte', $numero)->first();

        if ($compte === null) {
            throw new RuntimeException(__('comptes_correspondance.compte_absent', ['numero' => $numero]));
        }

        $prefixes = RolesCorrespondance::ROLES[$role]['prefixes'];
        $coherent = false;

        foreach ($prefixes as $prefixe) {
            if (str_starts_with($numero, $prefixe)) {
                $coherent = true;
            }
        }

        if (! $coherent) {
            throw new RuntimeException(__('comptes_correspondance.compte_incoherent', [
                'numero' => $numero,
                'role' => RolesCorrespondance::ROLES[$role]['libelle'],
                'attendu' => self::attendu($prefixes),
            ]));
        }

        // Même règle que `PasserEcritureService::compte()` : une DIVISION ne
        // reçoit aucun mouvement — la choisir ferait refuser chaque pièce.
        if (strlen($numero) < 4
            && CompteComptable::query()->where('numero_compte', 'like', $numero . '%')->where('numero_compte', '!=', $numero)->exists()) {
            throw new RuntimeException(__('comptabilite.compte_division', ['numero' => $numero]));
        }
    }

    /**
     * Ce qu'un rôle attend, en mots — « est de la classe 7 » / « commence par 443 ».
     *
     * @param  list<string>  $prefixes
     */
    public static function attendu(array $prefixes): string
    {
        $morceaux = array_map(
            static fn (string $p): string => strlen($p) === 1
                ? __('comptes_correspondance.attendu_classe', ['classe' => $p])
                : __('comptes_correspondance.attendu_prefixe', ['prefixe' => $p]),
            $prefixes,
        );

        return implode(__('comptes_correspondance.attendu_ou'), $morceaux);
    }

    /**
     * Les lignes de l'écran « Correspondance des comptes » : tous les rôles,
     * dans l'ordre des groupes, avec le compte ACTUEL, son libellé au plan et
     * le défaut.
     *
     * @return list<array{role: string, cle: string, groupe: string, libelle: string, aide: string, actuel: string, libelleActuel: string|null, defaut: string, personnalise: bool, prefixes: list<string>}>
     */
    public function lignes(): array
    {
        $lignes = [];

        foreach (RolesCorrespondance::GROUPES as $groupe) {
            foreach (RolesCorrespondance::ROLES as $role => $definition) {
                if ($definition['groupe'] !== $groupe) {
                    continue;
                }

                $actuel = $this->compte($role);
                $defaut = RolesCorrespondance::defaut($role);

                $lignes[] = [
                    'role' => $role,
                    'cle' => self::cle($role),
                    'groupe' => $groupe,
                    'libelle' => $definition['libelle'],
                    'aide' => $definition['aide'],
                    'actuel' => $actuel,
                    'libelleActuel' => CompteComptable::query()->where('numero_compte', $actuel)->value('libelle'),
                    'defaut' => $defaut,
                    'personnalise' => $actuel !== $defaut,
                    'prefixes' => $definition['prefixes'],
                ];
            }
        }

        return $lignes;
    }

    private function exigerRole(string $role): void
    {
        if (! RolesCorrespondance::existe($role)) {
            throw new InvalidArgumentException("Unknown accounting role: {$role}");
        }
    }
}
