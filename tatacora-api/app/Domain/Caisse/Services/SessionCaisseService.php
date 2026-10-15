<?php

declare(strict_types=1);

namespace App\Domain\Caisse\Services;

use App\Domain\Caisse\Models\SessionCaisse;
use App\Domain\Ventes\Models\Vente;
use Carbon\CarbonInterface;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Ouverture et clôture d'une session de caisse — SEUL auteur de
 * `sessions_caisse` (lot S3 de synchronisation, 15/10/2026).
 *
 * ## Pourquoi ce service existe maintenant
 *
 * Jusqu'au 15/10/2026, l'ouverture et la clôture vivaient dans le composant
 * `PosComptant` (`ouvrirCaisse`, `cloturerCaisse`) : aucun service de
 * domaine. La décision du Product Owner du 15/10/2026 fait monter les
 * sessions des postes hors connexion par la synchronisation : un second
 * auteur aurait recopié le calcul du théorique et le contrôle « une seule
 * caisse ouverte par point » — et les deux copies auraient divergé au premier
 * changement (un mode de paiement ajouté aux espèces du tiroir, par exemple).
 * Le composant et le gestionnaire de synchronisation appellent désormais ce
 * service, et lui seul.
 *
 * ## Le théorique est TOUJOURS recalculé ici
 *
 * Fond + ventes en espèces VALIDÉES de la session (maître `caisse-ui.js`
 * l.134-137) — sur les ventes que le SERVEUR connaît. Un poste qui annonce
 * son propre théorique ne le fait pas écrire : l'écart éventuel est signalé
 * par la synchronisation, jamais substitué (décision PO du 15/10/2026).
 *
 * ## Dates
 *
 * Les dates d'ouverture et de clôture sont des dates MÉTIER : `null` (l'écran
 * en ligne) vaut maintenant ; la synchronisation passe l'instant saisi au
 * poste (D246).
 *
 * @see EF-M5-06 Vente au comptoir du bar (la session de caisse)
 */
class SessionCaisseService
{
    /** L'enum `sessions_caisse.point_vente`. */
    public const POINTS = ['reception', 'restaurant', 'bar'];

    private const PRECISION = 2;

    /** La session ouverte la plus récente d'un point — celle qui encaisse. */
    public function sessionOuverte(string $point): ?SessionCaisse
    {
        return SessionCaisse::query()
            ->where('point_vente', $point)
            ->whereNull('date_cloture')
            ->latest('date_ouverture')
            ->first();
    }

    /**
     * Ce qui est REELLEMENT dans le tiroir en espèces : les ventes en
     * espèces, validées, de la session. Mobile Money, carte, virement et note
     * de chambre en sont exclus — seuls des billets remplissent un tiroir ;
     * une vente annulée n'y est pas.
     */
    public function especesDeLaSession(string $sessionId): string
    {
        return bcadd((string) Vente::query()
            ->where('session_id', $sessionId)
            ->where('statut', 'validee')
            ->where('mode_paiement', 'especes')
            ->sum('montant_total'), '0', self::PRECISION);
    }

    /**
     * Fond + espèces encaissées — la SEULE source du théorique : le
     * récapitulatif de la modale, la clôture en ligne et la clôture
     * synchronisée l'appellent tous.
     */
    public function theorique(SessionCaisse $session): string
    {
        return bcadd((string) $session->montant_fond, $this->especesDeLaSession($session->id), self::PRECISION);
    }

    /**
     * Ouvre une session.
     *
     * `$id` : l'UUID posé par un poste hors connexion — une session qui existe
     * déjà sous cet identifiant est rendue telle quelle (rejeu).
     *
     * @throws RuntimeException point inconnu, fond invalide, ou caisse déjà ouverte sur ce point
     */
    public function ouvrir(
        string $point,
        string $fond,
        string $utilisateurId,
        ?CarbonInterface $dateOuverture = null,
        ?string $id = null,
    ): SessionCaisse {
        if ($id !== null && ($existante = SessionCaisse::find($id)) !== null) {
            return $existante;
        }

        if (! in_array($point, self::POINTS, true)) {
            throw new RuntimeException(__('caisse.point_inconnu', ['point' => $point]));
        }

        $this->exigerMontant($fond);

        return DB::transaction(function () use ($point, $fond, $utilisateurId, $dateOuverture, $id): SessionCaisse {
            // Sous verrou : deux ouvertures simultanées (un poste qui rejoue,
            // un caissier en ligne) liraient toutes deux « aucune caisse
            // ouverte ».
            $ouverte = SessionCaisse::query()
                ->where('point_vente', $point)
                ->whereNull('date_cloture')
                ->lockForUpdate()
                ->exists();

            if ($ouverte) {
                // La phrase de l'écran en ligne, à l'identique : le poste
                // affiche le même refus que la PWA.
                throw new RuntimeException(__('pos_pwa.comptant.refus_caisse_deja_ouverte'));
            }

            return SessionCaisse::create([
                ...($id !== null ? ['id' => $id] : []),
                'point_vente' => $point,
                'utilisateur_ouverture_id' => $utilisateurId,
                'date_ouverture' => $dateOuverture ?? now(),
                'montant_fond' => bcadd($fond, '0', self::PRECISION),
            ]);
        });
    }

    /**
     * Clôture une session : théorique recalculé, constaté enregistré.
     *
     * @throws RuntimeException session déjà close, montant invalide, ou clôture antérieure à l'ouverture
     */
    public function cloturer(SessionCaisse $session, string $constate, ?CarbonInterface $dateCloture = null): SessionCaisse
    {
        $this->exigerMontant($constate);

        return DB::transaction(function () use ($session, $constate, $dateCloture): SessionCaisse {
            $session = SessionCaisse::query()->whereKey($session->id)->lockForUpdate()->firstOrFail();

            if ($session->date_cloture !== null) {
                throw new RuntimeException(__('caisse.deja_cloturee'));
            }

            $date = $dateCloture ?? now();

            if ($date->lessThan($session->date_ouverture)) {
                throw new RuntimeException(__('caisse.cloture_avant_ouverture'));
            }

            $session->update([
                'date_cloture' => $date,
                'montant_theorique' => $this->theorique($session),
                'montant_constate' => bcadd($constate, '0', self::PRECISION),
            ]);

            return $session->refresh();
        });
    }

    /** Constaté − théorique : positif = excédent, négatif = manquant. */
    public static function ecart(string $constate, string $theorique): string
    {
        return bcsub($constate, $theorique, self::PRECISION);
    }

    private function exigerMontant(string $montant): void
    {
        if (! is_numeric($montant) || bccomp($montant, '0', self::PRECISION) < 0) {
            throw new RuntimeException(__('caisse.montant_invalide'));
        }
    }
}
