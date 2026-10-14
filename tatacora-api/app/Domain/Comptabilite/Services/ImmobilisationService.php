<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Services;

use App\Domain\Comptabilite\Models\CompteComptable;
use App\Domain\Comptabilite\Models\Immobilisation;
use App\Domain\Comptabilite\ReadModels\LigneAmortissement;
use App\Domain\Comptabilite\ReadModels\LigneTableauImmobilisations;
use App\Domain\Comptabilite\ReadModels\PlanAmortissement;
use App\Domain\Comptabilite\ReadModels\TableauImmobilisations;
use App\Domain\Numerotation\Services\SequenceDocumentService;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Immobilisations et amortissement linéaire — onglet « Immobilisations » du
 * hub SYSCOHADA, maître `m10-syscohada-etats.js` (`creerImmobilisation()`,
 * `planAmortissement()`, `tableauImmobilisations()`).
 *
 * @see EF-M10-06 Édition des états réglementaires SYSCOHADA
 *
 * ## Le plan d'amortissement est CALCULÉ, jamais stocké
 *
 * Aucune table ne porte d'annuité : `planAmortissement()` la recalcule à
 * chaque appel depuis `valeur_origine` et `duree_annees`, comme le stock
 * théorique (`03_DATABASE_ENGINEERING.md` §7) ou le plan d'amortissement du
 * maître lui-même. C'est ce qui garantit qu'une VNC affichée aujourd'hui et
 * une VNC affichée demain, sur la même immobilisation, sortent toujours de la
 * MÊME formule.
 *
 * ## Prorata temporis en MOIS ENTAMÉS — la convention du maître
 *
 * `CONVENTION_PRORATA = 'mois_entames'` (`comptabilite-engine.js` l.61) :
 * une mise en service le 20 mars compte MARS comme un mois entier, pas
 * comme 11 jours sur 31. La première annuité couvre donc
 * `13 - mois_de_mise_en_service` douzièmes de l'annuité théorique.
 *
 * ## La dernière annuité absorbe l'arrondi
 *
 * Sans cela, la somme des annuités arrondies s'écarterait de la valeur
 * d'origine et la VNC finale ne tomberait jamais exactement à zéro — défaut
 * que le maître nomme lui-même dans son commentaire de fonction.
 *
 * ## AUCUNE écriture comptable de dotation n'est passée ici — nommé, pas oublié
 *
 * Comptabiliser une dotation suppose un débit sur un compte de classe 68
 * (dotations aux amortissements) et un crédit sur un compte d'amortissement
 * de classe 28 correspondant à la classe 2 de l'immobilisation — ni l'un ni
 * l'autre n'a été vérifié au plan comptable de ce dépôt dans ce lot. Le
 * router aujourd'hui déclencherait une écriture sur un compte peut-être
 * inexistant, ou pire, existant mais faux. Le geste « comptabiliser les
 * dotations de l'exercice » reste donc À FAIRE, sous l'arbitrage du
 * Comptable — ce service ne rend que la LECTURE du plan.
 *
 * ## `compte_immobilisation` — un varchar, jamais une clé étrangère
 *
 * Voir le docblock de la migration `create_immobilisations` : la colonne ne
 * sert aujourd'hui aucune jointure, mais reste validée à la création contre
 * `plan_comptable.numero_compte` quand elle est fournie.
 */
class ImmobilisationService
{
    private const PRECISION = 2;

    public function __construct(
        private readonly SequenceDocumentService $sequences,
    ) {
    }

    /**
     * Crée une immobilisation — la durée d'utilité est OBLIGATOIRE et SANS
     * valeur par défaut : sous SYSCOHADA révisé, c'est une estimation propre
     * à l'entité (AUDCIF art. 45), jamais un barème que ce service devinerait
     * à sa place.
     *
     * Les clés sont volontairement `mixed` : l'appelant (le composant
     * Livewire) transmet un tableau non typé au runtime, et ce service
     * revalide chaque valeur lui-même plutôt que de faire confiance à un
     * type PHPDoc qu'aucune signature ne garantit réellement.
     *
     * @param  array{libelle?: mixed, valeur_origine?: mixed, duree_annees?: mixed, date_mise_service?: mixed, compte_immobilisation?: mixed}  $donnees
     *
     * @throws RuntimeException libellé absent, valeur ou durée non positive, date absente, compte inconnu
     */
    public function creer(array $donnees): Immobilisation
    {
        $libelle = trim((string) ($donnees['libelle'] ?? ''));

        if ($libelle === '') {
            throw new RuntimeException(__('comptabilite.immobilisation_libelle_requis'));
        }

        $valeur = bcadd((string) ($donnees['valeur_origine'] ?? '0'), '0', self::PRECISION);

        if (bccomp($valeur, '0', self::PRECISION) <= 0) {
            throw new RuntimeException(__('comptabilite.immobilisation_valeur_invalide'));
        }

        $duree = (int) ($donnees['duree_annees'] ?? 0);

        if ($duree <= 0) {
            throw new RuntimeException(__('comptabilite.immobilisation_duree_requise'));
        }

        $dateMiseService = (string) ($donnees['date_mise_service'] ?? '');

        if ($dateMiseService === '' || ! preg_match('/^\d{4}-\d{2}-\d{2}$/', $dateMiseService)) {
            throw new RuntimeException(__('comptabilite.immobilisation_date_invalide'));
        }

        $compte = isset($donnees['compte_immobilisation']) && $donnees['compte_immobilisation'] !== ''
            ? (string) $donnees['compte_immobilisation']
            : null;

        if ($compte !== null && ! CompteComptable::query()->where('numero_compte', $compte)->exists()) {
            throw new RuntimeException(__('comptabilite.compte_inconnu', ['numero' => $compte]));
        }

        return DB::transaction(function () use ($libelle, $valeur, $duree, $dateMiseService, $compte): Immobilisation {
            $code = $this->sequences->suivant(
                'immobilisations',
                'IMMO',
                (int) substr($dateMiseService, 0, 4),
                'code',
            );

            return Immobilisation::create([
                'code' => $code,
                'libelle' => $libelle,
                'valeur_origine' => $valeur,
                'duree_annees' => $duree,
                'date_mise_service' => $dateMiseService,
                'compte_immobilisation' => $compte,
            ]);
        });
    }

    /**
     * Le plan d'amortissement linéaire complet — une ligne par annuité,
     * mise en service comprise.
     */
    public function planAmortissement(Immobilisation $immobilisation): PlanAmortissement
    {
        $valeur = (string) $immobilisation->valeur_origine;
        $duree = $immobilisation->duree_annees;
        $anneeDebut = (int) $immobilisation->date_mise_service->format('Y');
        // Mois entamés, mise en service comprise : janvier (mois 1) laisse
        // 12 douzièmes, décembre (mois 12) n'en laisse qu'un seul.
        $moisRestants = 13 - (int) $immobilisation->date_mise_service->format('n');

        $annuiteTheorique = bcdiv($valeur, (string) $duree, 10);

        $lignes = [];
        $cumul = '0.00';

        for ($i = 0; $i <= $duree; $i++) {
            $annee = $anneeDebut + $i;

            if ($i === 0) {
                $dotation = $this->arrondir(bcdiv(bcmul($annuiteTheorique, (string) $moisRestants, 10), '12', 10));
            } elseif ($i === $duree) {
                // Solde exact : absorbe l'arrondi cumulé des annuités
                // précédentes.
                $dotation = bcsub($valeur, $cumul, self::PRECISION);
            } else {
                $dotation = $this->arrondir($annuiteTheorique);
            }

            if (bccomp($dotation, '0', self::PRECISION) <= 0) {
                continue;
            }

            if (bccomp(bcadd($cumul, $dotation, self::PRECISION), $valeur, self::PRECISION) > 0) {
                $dotation = bcsub($valeur, $cumul, self::PRECISION);
            }

            $cumul = bcadd($cumul, $dotation, self::PRECISION);

            $lignes[] = new LigneAmortissement(
                annee: $annee,
                base: $valeur,
                dotation: $dotation,
                cumul: $cumul,
                vnc: bcsub($valeur, $cumul, self::PRECISION),
                prorata: $i === 0 ? $moisRestants.'/12' : null,
            );

            if (bccomp($cumul, $valeur, self::PRECISION) >= 0) {
                break;
            }
        }

        return new PlanAmortissement($immobilisation, $lignes, $cumul);
    }

    /**
     * Le tableau des immobilisations pour un exercice donné — brut, dotation
     * DE l'exercice, cumul JUSQU'À l'exercice, VNC.
     */
    /**
     * @param  string|null  $recherche  Filtre PWA (barre de recherche par table,
     *      décision du Product Owner du 01/09/2026) — sur le code ou le libellé
     *      de l'immobilisation. Contrairement à la Balance ou au Grand Livre,
     *      filtrer ici est sûr : les totaux du pied sont une SOMME des lignes
     *      affichées (pas une équilibre à préserver ni un cumul séquentiel), le
     *      même comportement qu'un tableur qu'on filtre.
     */
    public function tableauPourExercice(int $annee, ?string $recherche = null): TableauImmobilisations
    {
        $lignes = [];
        $totalBrut = '0.00';
        $totalDotation = '0.00';
        $totalCumul = '0.00';
        $totalVnc = '0.00';

        /** @var Collection<int, Immobilisation> $immobilisations */
        $immobilisations = Immobilisation::query()
            ->when(
                $recherche !== null && $recherche !== '',
                fn ($requete) => $requete->where(
                    fn ($sous) => $sous->where('code', 'like', '%'.$recherche.'%')
                        ->orWhere('libelle', 'like', '%'.$recherche.'%'),
                ),
            )
            ->orderBy('code')->get();

        foreach ($immobilisations as $immobilisation) {
            $plan = $this->planAmortissement($immobilisation);

            $cumul = '0.00';
            $dotationDeLAnnee = '0.00';

            foreach ($plan->lignes as $ligne) {
                if ($ligne->annee <= $annee) {
                    $cumul = $ligne->cumul;
                }

                if ($ligne->annee === $annee) {
                    $dotationDeLAnnee = $ligne->dotation;
                }
            }

            $brut = (string) $immobilisation->valeur_origine;
            $vnc = bcsub($brut, $cumul, self::PRECISION);

            $lignes[] = new LigneTableauImmobilisations($immobilisation, $brut, $dotationDeLAnnee, $cumul, $vnc);

            $totalBrut = bcadd($totalBrut, $brut, self::PRECISION);
            $totalDotation = bcadd($totalDotation, $dotationDeLAnnee, self::PRECISION);
            $totalCumul = bcadd($totalCumul, $cumul, self::PRECISION);
            $totalVnc = bcadd($totalVnc, $vnc, self::PRECISION);
        }

        return new TableauImmobilisations($annee, $lignes, $totalBrut, $totalDotation, $totalCumul, $totalVnc);
    }

    /**
     * Arrondi au centime le plus proche, moitié vers le haut — `bcmath` ne
     * fait que tronquer, jamais arrondir.
     */
    private function arrondir(string $valeur): string
    {
        $ajustement = bccomp($valeur, '0', 10) < 0 ? '-0.005' : '0.005';

        return bcadd($valeur, $ajustement, self::PRECISION);
    }
}
