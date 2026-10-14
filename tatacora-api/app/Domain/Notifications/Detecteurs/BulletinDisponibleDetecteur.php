<?php

declare(strict_types=1);

namespace App\Domain\Notifications\Detecteurs;

use App\Domain\Notifications\Contracts\DetecteurDeclencheurInterface;
use App\Domain\Notifications\Support\MontantNotification;
use App\Domain\Rh\Models\BulletinPaie;
use Illuminate\Support\Carbon;

/**
 * Déclencheur `bulletin_disponible` — maître : `notifications-engine.js`
 * l.196-206.
 *
 * ⚠ ÉCART DÉLIBÉRÉ face au maître : celui-ci ne filtre que `statut !==
 * 'annule'`, donc un BROUILLON compterait comme « disponible ». Ici, seul un
 * bulletin `validee` déclenche l'information au salarié — un brouillon est
 * encore modifiable par le service RH, et prévenir un salarié d'un montant
 * susceptible de changer serait la même famille de défaut que MECeF en
 * démonstration : une affirmation avant qu'elle soit vraie.
 */
final class BulletinDisponibleDetecteur implements DetecteurDeclencheurInterface
{
    /**
     * @return list<array{reference: string, destinataire: string, variables: array<string, string>}>
     */
    public function detecter(): array
    {
        $periode = Carbon::now()->format('Y-m');

        return BulletinPaie::query()
            ->with('employe')
            ->where('periode', $periode)
            ->where('statut', BulletinPaie::STATUT_VALIDEE)
            ->get()
            ->map(static function (BulletinPaie $bulletin) use ($periode) {
                $employe = $bulletin->employe;
                $nom = trim(($employe->prenom ?? '') . ' ' . $employe->nom);

                return [
                    'reference' => $bulletin->id,
                    'destinataire' => $nom,
                    'variables' => [
                        'employe' => $nom,
                        'periode' => $periode,
                        'net' => MontantNotification::format((string) $bulletin->net_a_payer),
                    ],
                ];
            })
            ->values()
            ->all();
    }
}
