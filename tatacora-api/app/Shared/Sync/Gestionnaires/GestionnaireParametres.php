<?php

declare(strict_types=1);

namespace App\Shared\Sync\Gestionnaires;

use App\Domain\Comptabilite\Support\FormeJuridique;
use App\Domain\Facturation\Services\ReglagesDocuments;
use App\Domain\Facturation\Services\ReglagesMecef;
use App\Models\User;
use App\Pwa\Livewire\Transverse\Parametres;
use App\Shared\Parametres\Data\RegistreParametres;
use App\Shared\Parametres\Models\ParametreSysteme;
use App\Shared\Parametres\Services\ControleValeurParametre;
use App\Shared\Parametres\Services\EnregistrerParametreService;
use App\Shared\Sync\Support\ContexteSynchronisation;
use App\Shared\Sync\Support\EcritureSynchronisee;
use Carbon\Carbon;
use Illuminate\Support\Facades\Validator;
use RuntimeException;

/**
 * Les paramètres du système enregistrés sur un poste — audit de couverture
 * du 18/10/2026 (lot 10e, « tous les modules »).
 *
 * ## Un ENREGISTREMENT, pas une clé
 *
 * L'opération porte le LOT soumis par l'écran Paramètres du poste
 * (`valeurs`, clé → valeur), sous un identifiant propre à ce geste : c'est la
 * forme que `EnregistrerParametreService` exige, la cohérence se jugeant sur
 * l'état RÉSULTANT (activer la TVA et saisir son taux dans le même envoi).
 * Clé par clé, l'activation arriverait seule et serait refusée.
 *
 * ## Dernier écrit gagnant, clé par clé
 *
 * Une clé modifiée au serveur APRÈS la saisie du poste (horodatage client)
 * garde la valeur du serveur : elle est rendue dans `cles_conservees`, et la
 * descente la rapporte au poste. Les autres passent par le service, lui
 * seul — registre fermé, normalisation, gardes PA-61/PA-62, audit.
 *
 * ## Les clés RÉSERVÉES aux administrateurs (09/11/2026, décision du PO)
 *
 * Le mode de la facturation normalisée, l'adresse de l'API de la DGI,
 * l'identifiant et le nom de l'opérateur, et la forme juridique se règlent
 * AUSSI depuis un poste (« le poste fait ce que le web fait »), à une condition :
 * le compte du JETON D'APPAIRAGE est un administrateur — la règle de l'écran web,
 * qui cache « Modifier » aux autres (même règle que la suppression d'un compte).
 * Sinon l'opération entière est rejetée `droit_manquant` avec la phrase de l'écran
 * (`refusDeDroit`), lisible dans « À traiter » ; la valeur reste modifiée sur le
 * poste. Acceptées, ces clés passent par le même service que l'écran
 * (`EnregistrerParametreService` : mode valide, https, 30 caractères, forme
 * juridique refusée tant qu'une affectation est active, cohérence du mode) et
 * suivent le dernier écrit gagnant comme toute clé.
 *
 * Le JETON e-MECeF n'est pas un paramètre : il ne passe jamais par ici (ni
 * l'envoi d'un poste, ni la descente).
 *
 * Module `PARAM`, celui de l'écran (RG-16 : un module transverse est un
 * module).
 */
final class GestionnaireParametres extends GestionnaireAbstrait
{
    /**
     * Les clés que seul un administrateur règle — l'écran web les montre avec
     * « Modifier » aux administrateurs seulement. Source UNIQUE : le script de parité
     * `rejouer_regles_communes.php` l'exporte, le poste la confronte à son registre.
     *
     * @var list<string>
     */
    public const CLES_ADMINISTRATEUR = [
        ...ReglagesMecef::CLES_ADMINISTRATEUR,
        FormeJuridique::CLE,
    ];

    /**
     * Les clés ouvertes aux postes le 09/11/2026 — dont la forme est rejouée au serveur.
     *
     * @var list<string>
     */
    public const CLES_CONTROLEES = [
        ...self::CLES_ADMINISTRATEUR,
        ...ReglagesDocuments::CLES,
    ];

    public function __construct(private readonly EnregistrerParametreService $parametres)
    {
    }

    public function table(): string
    {
        return 'parametres_systeme';
    }

    public function module(): string
    {
        return Parametres::MODULE;
    }

    public function serviceDomaine(): string
    {
        return EnregistrerParametreService::class;
    }

    public function refusDeDroit(array $payload, User $utilisateur): ?string
    {
        $valeurs = is_array($payload['valeurs'] ?? null) ? array_keys($payload['valeurs']) : [];
        $reservees = array_values(array_intersect(array_map('strval', $valeurs), self::CLES_ADMINISTRATEUR));

        if ($reservees === [] || $utilisateur->estAdministrateur()) {
            return null;
        }

        // La phrase de l'écran : celle de la forme juridique si c'est la seule clé réservée.
        return $reservees === [FormeJuridique::CLE]
            ? __('parametres.forme_juridique_reservee_administrateur')
            : __('parametres.mecef_reserve_administrateur');
    }

    public function creer(string $entiteId, array $payload, ContexteSynchronisation $contexte): EcritureSynchronisee
    {
        $validateur = Validator::make($payload, [
            'valeurs' => ['required', 'array', 'min:1'],
        ]);
        $nonScalaires = array_filter(
            is_array($payload['valeurs'] ?? null) ? $payload['valeurs'] : [],
            static fn (mixed $v): bool => $v !== null && ! is_scalar($v),
        );

        if ($validateur->fails() || $nonScalaires !== []) {
            throw new RuntimeException($validateur->fails()
                ? (string) $validateur->errors()->first()
                : __('sync.parametres.valeur_non_scalaire', ['cles' => implode(', ', array_keys($nonScalaires))]));
        }

        /** @var array<string, scalar|null> $valeurs */
        $valeurs = $payload['valeurs'];
        $retenues = [];
        $conservees = [];

        foreach ($valeurs as $cle => $valeur) {
            $stocke = ParametreSysteme::query()->where('cle', (string) $cle)->first();

            if ($stocke !== null && $this->plusRecentAuServeur($stocke, $contexte->horodatageClient)) {
                $conservees[] = (string) $cle;

                continue;
            }

            $retenues[(string) $cle] = $valeur;
        }

        // Les clés ouvertes aux postes le 09/11/2026 : la FORME de chaque valeur est rejouée
        // (mode admis, https, 30 caractères…) — l'écran web le fait par `validerEcriture`.
        foreach ($retenues as $cle => $valeur) {
            $definition = RegistreParametres::definition($cle);
            $refus = $definition !== null && in_array($cle, self::CLES_CONTROLEES, true)
                ? ControleValeurParametre::refus($definition, $valeur)
                : null;

            if ($refus !== null) {
                throw new RuntimeException($refus);
            }
        }

        $modifiees = $retenues === [] ? [] : $this->parametres->enregistrer($retenues);

        return new EcritureSynchronisee($entiteId, complements: [
            'cles_modifiees' => $modifiees,
            'cles_conservees' => $conservees,
        ]);
    }

    private function plusRecentAuServeur(ParametreSysteme $stocke, Carbon $saisie): bool
    {
        $serveur = $stocke->updated_at ?? $stocke->created_at;

        return $serveur !== null && Carbon::parse($serveur)->greaterThan($saisie);
    }
}
