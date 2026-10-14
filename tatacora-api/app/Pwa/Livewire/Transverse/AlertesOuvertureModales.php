<?php

declare(strict_types=1);

namespace App\Pwa\Livewire\Transverse;

use App\Domain\Crm\Services\RelanceClientService;
use App\Domain\Hebergement\Models\Sejour;
use App\Domain\Hebergement\Services\SejourService;
use App\Pwa\Support\AlertesOuverture;
use App\Pwa\Support\MenuLateral;
use App\Shared\Parametres\Services\OptionsSystemeService;
use Illuminate\Contracts\View\View;
use RuntimeException;

/**
 * Les DEUX modales d'ouverture de session — maître :
 * `prototype_v2/assets/js/alertes-ouverture.js` (vérifiées manquantes par le
 * Product Owner le 02/09/2026 : la cloche existait, pas les modales, et le
 * maître les distingue lui-même — « une modale coûte un clic pour être
 * écartée, c'est précisément ce qui garantit qu'elle a été vue »).
 *
 * ## Enchaînement du maître, transposé
 *
 *  1. **Stock critique** — articles au niveau ou sous leur seuil (RG-07,
 *     `VerificationSeuilService`), ruptures en rouge et en tête.
 *  2. **Opérations du jour** — départs arrivés à échéance (départ du jour, ou
 *     dépassé sans check-out — en rouge) avec le geste **Check-out** inline,
 *     et créances à relancer (règle du maître : plus de 30 jours d'ancienneté
 *     ET aucune relance depuis 14 jours) avec le geste **Relancer** (canal au
 *     choix). Une créance relancée récemment reste listée SANS action.
 *
 * Séquentiel : la seconde n'apparaît qu'à la fermeture de la première. Un
 * bloc vide ne se rend pas ; si tout est vide, rien ne s'ouvre — « une modale
 * "tout va bien" quotidienne apprend à cliquer sans lire ».
 *
 * ## Une fois par CONNEXION, jamais par page
 *
 * Le maître se repère à l'horodatage de connexion. Côté serveur, c'est un
 * drapeau de SESSION posé par `Connexion::seConnecter()` et consommé ici :
 * rouvrir un onglet ne réaffiche rien, une nouvelle connexion, si. Le drapeau
 * est consommé même quand il n'y a rien à montrer — on ne recalcule pas à
 * chaque page.
 *
 * ## RBAC par BLOC, même source que le menu
 *
 * Le maître le dit : « elles ne s'adressent pas aux mêmes mains ». Le stock
 * ne se montre qu'avec un accès M6, les départs M1, les créances M3 — via
 * `MenuLateral::moduleAccessible()`, jamais un second calcul. Les GESTES
 * exigent le niveau C de LEUR module : ce composant porte deux écritures de
 * modules différents, déclarées au registre multi-modules de
 * `PwaEcritureAutoriseeTest`.
 *
 * ## Gouverné par la bascule du maître
 *
 * `OptionsSystemeService::CLE_ALERTES_OUVERTURE` — la même qui gouverne la
 * cloche : fermée, aucune des deux surfaces ne dérive d'alerte.
 */
class AlertesOuvertureModales extends \Livewire\Component
{
    /** Le drapeau de session posé à la connexion. */
    public const CLE_SESSION = 'alertes_ouverture_en_attente';

    /** Étape courante (1-based) dans la liste des étapes NON VIDES. */
    public int $etape = 1;

    /** Le geste `Relancer` a besoin d'un canal — celui du maître par défaut. */
    public string $canalRelance = 'telephone';

    /**
     * Les lignes déjà traitées dans CETTE modale (check-out faits, relances
     * tracées) : la ligne reste affichée estompée avec « Fait »/« Tracée »,
     * comme au maître — jamais retirée sous les yeux de l'opérateur.
     *
     * @var list<string>
     */
    public array $traites = [];

    public function avancer(): void
    {
        $this->etape++;

        if ($this->etape > count($this->etapes())) {
            session()->forget(self::CLE_SESSION);
        }
    }

    /**
     * Check-out inline — même service et même règle que l'écran Hébergement :
     * l'unité passe en NETTOYAGE, jamais directement libre (EF-M1-04).
     */
    public function effectuerCheckOutOuverture(string $sejourId, SejourService $sejours): void
    {
        $this->exigerEcriture('M1');

        $sejour = Sejour::query()->find($sejourId);

        if ($sejour === null) {
            $this->addError('alerte_ouverture', __('pwa.alertes_ouverture.sejour_introuvable'));

            return;
        }

        try {
            $sejours->checkout($sejour);
            $this->traites[] = 'sejour:' . $sejourId;
        } catch (RuntimeException $refus) {
            $this->addError('alerte_ouverture', $refus->getMessage());
        }
    }

    /**
     * Relance TRACÉE — le mot est celui du maître : aucune promesse d'envoi.
     * Le montant réclamé est le reste dû réel du client, jamais une saisie.
     */
    public function tracerRelanceOuverture(string $clientId, RelanceClientService $relances): void
    {
        $this->exigerEcriture('M3');

        $creance = collect(AlertesOuverture::creancesModale())
            ->firstWhere('client_id', $clientId);

        if ($creance === null || ! $creance['relance_requise']) {
            $this->addError('alerte_ouverture', __('pwa.alertes_ouverture.relance_indisponible'));

            return;
        }

        try {
            $relances->enregistrer([
                'client_id' => $clientId,
                'canal' => $this->canalRelance,
                'montant_reclame' => $creance['reste'],
                'commentaire' => __('pwa.alertes_ouverture.relance_commentaire'),
            ]);
            $this->traites[] = 'client:' . $clientId;
        } catch (RuntimeException $refus) {
            $this->addError('alerte_ouverture', $refus->getMessage());
        }
    }

    public function render(): View
    {
        if (! $this->doitAfficher()) {
            return view('pwa.transverse.alertes-ouverture-modales', ['etapes' => []]);
        }

        $etapes = $this->etapes();

        // Rien à signaler : le drapeau se consomme quand même — on ne
        // recalcule pas à chaque page (règle du maître).
        if ($etapes === [] || $this->etape > count($etapes)) {
            session()->forget(self::CLE_SESSION);

            return view('pwa.transverse.alertes-ouverture-modales', ['etapes' => []]);
        }

        return view('pwa.transverse.alertes-ouverture-modales', [
            'etapes' => $etapes,
            'courante' => $etapes[$this->etape - 1],
            'total' => count($etapes),
            'canaux' => \App\Domain\Crm\Models\RelanceClient::CANAUX,
        ]);
    }

    private function doitAfficher(): bool
    {
        // Egalite stricte a true, jamais has() : un drapeau pose a false par un
        // autre chemin (revue, outillage) serait sinon lu comme une alerte en
        // attente -- constate en revue navigateur le 02/09/2026.
        return auth()->check()
            && session()->get(self::CLE_SESSION) === true
            && app(OptionsSystemeService::class)->actif(OptionsSystemeService::CLE_ALERTES_OUVERTURE);
    }

    /**
     * Les étapes NON VIDES, sous le RBAC de leur bloc.
     *
     * @return list<array{nom: string, stock?: list<array<string, mixed>>, departs?: list<array<string, mixed>>, creances?: list<array<string, mixed>>}>
     */
    private function etapes(): array
    {
        $utilisateur = auth()->user();
        $etapes = [];

        if (MenuLateral::moduleAccessible($utilisateur, 'M6')) {
            $stock = AlertesOuverture::stockCritiqueModale();
            if ($stock !== []) {
                $etapes[] = ['nom' => 'stock', 'stock' => $stock];
            }
        }

        $departs = MenuLateral::moduleAccessible($utilisateur, 'M1')
            ? AlertesOuverture::departsAEcheance()
            : [];
        $creances = MenuLateral::moduleAccessible($utilisateur, 'M3')
            ? AlertesOuverture::creancesModale()
            : [];

        if ($departs !== [] || $creances !== []) {
            $etapes[] = ['nom' => 'operations', 'departs' => $departs, 'creances' => $creances];
        }

        return $etapes;
    }

    /**
     * Le niveau C exigé sur le module du GESTE — deux modules distincts sur
     * ce composant, déclarés au registre multi-modules de la garde.
     */
    private function exigerEcriture(string $module): void
    {
        $utilisateur = auth()->user();

        abort_if(
            $utilisateur === null || $utilisateur->niveauSurModule($module) !== 'C',
            403,
            __('pwa.alertes_ouverture.droit_manquant'),
        );
    }
}
