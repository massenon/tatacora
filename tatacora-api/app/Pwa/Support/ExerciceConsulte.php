<?php

declare(strict_types=1);

namespace App\Pwa\Support;

use App\Domain\Comptabilite\Models\ExerciceComptable;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\Route;

/**
 * L'EXERCICE CONSULTÉ — le sélecteur d'exercice global de la barre
 * supérieure (`docs/SPEC_SELECTEUR_EXERCICE.md`, décisions du PO du
 * 20/10/2026). UN point de vérité, la session de l'utilisateur : tout écran
 * qui suit le sélecteur le lit ici, jamais une copie.
 *
 * ## Il ne déplace AUCUNE écriture (R4)
 *
 * L'exercice consulté borne ce qui se LIT. Une vente, une dépense, un
 * encaissement s'enregistre toujours dans l'exercice de SA date
 * (`PasserEcritureService`) : rien ici n'est lu par un chemin d'écriture.
 *
 * ## La date de référence
 *
 * Les périodes relatives (« ce mois », « ce trimestre », « exercice entier »)
 * se calculent à partir d'une date de référence : AUJOURD'HUI quand l'exercice
 * consulté le contient, son DERNIER JOUR sinon. Consulter 2025 en 2026, c'est
 * donc voir décembre 2025 sous « ce mois » — jamais un mois hors de l'année
 * consultée.
 */
final class ExerciceConsulte
{
    public const CLE_SESSION = 'pwa.exercice_consulte';

    /**
     * Les écrans qui SUIVENT le sélecteur (préfixes de nom de route) — R2,
     * étendu par le PO le 20/10/2026 aux factures, aux achats et à la paie.
     * Le sélecteur n'est affiché que sur eux : un écran du jour (planning,
     * caisse, POS) n'a pas d'année à consulter.
     *
     * @var list<string>
     */
    public const ROUTES = [
        'pwa.comptabilite.',
        'pwa.accueil',
        'pwa.etats.',
        'pwa.depenses',
        'pwa.facturation',
        'pwa.achats.',
        'pwa.paie',
    ];

    /** L'exercice consulté : celui choisi s'il existe encore, sinon le défaut. */
    public static function exercice(): ?ExerciceComptable
    {
        $id = session(self::CLE_SESSION);

        if (is_string($id) && $id !== '') {
            $choisi = ExerciceComptable::query()->find($id);

            if ($choisi !== null) {
                return $choisi;
            }

            // Exercice disparu (réinitialisation) : le choix est oublié.
            session()->forget(self::CLE_SESSION);
        }

        return self::defaut();
    }

    /** L'exercice OUVERT le plus récent, à défaut le plus récent. */
    public static function defaut(): ?ExerciceComptable
    {
        return ExerciceComptable::query()->where('statut', 'ouvert')->orderByDesc('annee')->first()
            ?? ExerciceComptable::query()->orderByDesc('annee')->first();
    }

    /** Retient l'exercice choisi ; un identifiant inconnu est ignoré. */
    public static function choisir(string $exerciceId): void
    {
        if ($exerciceId === '' || ! ExerciceComptable::query()->whereKey($exerciceId)->exists()) {
            return;
        }

        $defaut = self::defaut();
        $defaut !== null && $defaut->id === $exerciceId
            ? session()->forget(self::CLE_SESSION)
            : session([self::CLE_SESSION => $exerciceId]);
    }

    public static function revenirAuDefaut(): void
    {
        session()->forget(self::CLE_SESSION);
    }

    /** L'exercice consulté est-il un autre que celui par défaut ? */
    public static function estAutreQueDefaut(): bool
    {
        $consulte = self::exercice();
        $defaut = self::defaut();

        return $consulte !== null && $defaut !== null && $consulte->id !== $defaut->id;
    }

    /**
     * La date de référence des périodes relatives : aujourd'hui si l'exercice
     * consulté le contient, son dernier jour sinon. Sans exercice : aujourd'hui.
     */
    public static function reference(?ExerciceComptable $exercice = null): CarbonImmutable
    {
        $exercice ??= self::exercice();
        $maintenant = CarbonImmutable::now();

        if ($exercice === null) {
            return $maintenant;
        }

        $debut = CarbonImmutable::parse($exercice->date_debut)->startOfDay();
        $fin = CarbonImmutable::parse($exercice->date_fin)->startOfDay();

        if ($maintenant->lt($debut)) {
            return $debut->setTimeFrom($maintenant);
        }

        return $maintenant->gte($fin->addDay()) ? $fin->setTime(12, 0) : $maintenant;
    }

    /**
     * Les bornes de l'exercice consulté, `[début, fin)` (fin EXCLUE), ou
     * `null` sans exercice.
     *
     * @return array{0: CarbonImmutable, 1: CarbonImmutable}|null
     */
    public static function bornes(?ExerciceComptable $exercice = null): ?array
    {
        $exercice ??= self::exercice();

        return $exercice === null ? null : [
            CarbonImmutable::parse($exercice->date_debut)->startOfDay(),
            CarbonImmutable::parse($exercice->date_fin)->startOfDay()->addDay(),
        ];
    }

    /**
     * Les dates d'un filtre « du / au » ramenées dans l'exercice consulté :
     * une borne vide prend celle de l'exercice, une borne saisie hors de
     * l'exercice y est ramenée. Sans exercice, rien ne change.
     *
     * @return array{0: string, 1: string}
     */
    public static function datesDansLExercice(string $du, string $au): array
    {
        $bornes = self::bornes();
        if ($bornes === null) {
            return [$du, $au];
        }

        $premier = $bornes[0]->toDateString();
        $dernier = $bornes[1]->subDay()->toDateString();
        $borner = static fn (string $date, string $vide): string => $date === ''
            ? $vide
            : max($premier, min($dernier, $date));

        return [$borner($du, $premier), $borner($au, $dernier)];
    }

    /**
     * Borne une requête à l'exercice consulté sur la colonne de DATE du
     * document (émission d'une facture, date d'une commande…). Sans exercice,
     * la requête est rendue telle quelle.
     *
     * @template T of \Illuminate\Database\Eloquent\Builder<*>|\Illuminate\Database\Query\Builder
     *
     * @param  T  $requete
     * @return T
     */
    public static function borner(mixed $requete, string $colonne): mixed
    {
        $bornes = self::bornes();

        if ($bornes !== null) {
            $requete->where($colonne, '>=', $bornes[0]->toDateString())
                ->where($colonne, '<', $bornes[1]->toDateString());
        }

        return $requete;
    }

    /** « Exercice 2026 » — la portée qu'un écran et son export DISENT. */
    public static function libelle(): string
    {
        $exercice = self::exercice();

        return $exercice === null ? '' : __('pwa.coquille.exercice_portee', [
            'annee' => $exercice->annee,
            'statut' => __('pwa.coquille.exercice_statuts.'.$exercice->statut),
        ]);
    }

    /** L'écran de cette route suit-il le sélecteur ? */
    public static function suitLeSelecteur(?string $route = null): bool
    {
        $route ??= Route::currentRouteName();

        if ($route === null) {
            return false;
        }

        foreach (self::ROUTES as $prefixe) {
            if ($route === rtrim($prefixe, '.') || str_starts_with($route, $prefixe)) {
                return true;
            }
        }

        return false;
    }
}
