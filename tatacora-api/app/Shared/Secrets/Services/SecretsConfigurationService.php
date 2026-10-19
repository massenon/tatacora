<?php

declare(strict_types=1);

namespace App\Shared\Secrets\Services;

use App\Models\User;
use App\Shared\Audit\Models\JournalAudit;
use App\Shared\Secrets\Models\SecretConfiguration;
use Illuminate\Contracts\Encryption\DecryptException;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;
use RuntimeException;

/**
 * Les secrets techniques saisis à l'écran — décision du Product Owner du
 * 19/10/2026 : le mot de passe SMTP du serveur se saisit dans Paramètres →
 * Email (SMTP), et se range CHIFFRÉ en base (`secrets_configuration`).
 *
 * Règles :
 *  - registre FERMÉ (`CLES`) : aucune clé libre ;
 *  - écriture réservée aux deux rôles d'administration ;
 *  - la valeur ne se RÉAFFICHE jamais : l'écran ne connaît que l'état
 *    (renseigné ou non, quand, par qui) ;
 *  - l'audit trace le geste, jamais la valeur ;
 *  - une valeur qui ne se déchiffre plus (`APP_KEY` changée) est traitée
 *    comme absente — le repli `.env` reprend — et le journal le dit.
 */
class SecretsConfigurationService
{
    public const SMTP_MOT_DE_PASSE = 'smtp_mot_de_passe';

    /** @var list<string> */
    public const CLES = [self::SMTP_MOT_DE_PASSE];

    public const LONGUEUR_MAX = 255;

    public function enregistrer(string $cle, string $valeur, User $auteur): void
    {
        $this->exiger($cle, $auteur);

        if ($valeur === '' || mb_strlen($valeur) > self::LONGUEUR_MAX) {
            throw new RuntimeException(__('pwa.parametres.secret_invalide', ['max' => self::LONGUEUR_MAX]));
        }

        DB::transaction(function () use ($cle, $valeur, $auteur): void {
            SecretConfiguration::query()->updateOrCreate(
                ['cle' => $cle],
                ['valeur' => $valeur, 'utilisateur_id' => $auteur->id],
            );
            $this->tracer('secret_enregistre', $cle, $auteur);
        });
    }

    public function effacer(string $cle, User $auteur): void
    {
        $this->exiger($cle, $auteur);

        DB::transaction(function () use ($cle, $auteur): void {
            SecretConfiguration::query()->where('cle', $cle)->delete();
            $this->tracer('secret_efface', $cle, $auteur);
        });
    }

    /** La valeur en clair, pour l'usage technique SEUL (l'envoi d'un courriel). */
    public function lire(string $cle): ?string
    {
        try {
            $secret = SecretConfiguration::query()->where('cle', $cle)->first();
        } catch (QueryException) {
            // Code déployé, migration pas encore jouée : l'envoi de courriel
            // ne doit pas tomber pour autant — le `.env` s'applique.
            Log::warning('Table secrets_configuration absente (migration non jouée ?) : le repli .env s\'applique.');

            return null;
        }

        if ($secret === null) {
            return null;
        }

        try {
            return $secret->valeur;
        } catch (DecryptException) {
            Log::warning("Secret « {$cle} » indéchiffrable (APP_KEY changée ?) : le repli .env s'applique.");

            return null;
        }
    }

    /** @return array{renseigne: bool, modifie_le: ?\Illuminate\Support\Carbon, par: ?string} */
    public function etat(string $cle): array
    {
        $secret = SecretConfiguration::query()->with('utilisateur')->where('cle', $cle)->first();

        return [
            'renseigne' => $secret !== null,
            'modifie_le' => $secret?->updated_at,
            'par' => $secret?->utilisateur?->login,
        ];
    }

    private function exiger(string $cle, User $auteur): void
    {
        if (! in_array($cle, self::CLES, true)) {
            throw new RuntimeException(__('pwa.parametres.secret_inconnu', ['cle' => $cle]));
        }

        if (! $auteur->estAdministrateur()) {
            throw new RuntimeException(__('pwa.parametres.secret_reserve'));
        }
    }

    private function tracer(string $action, string $cle, User $auteur): void
    {
        JournalAudit::create([
            'id' => (string) Str::uuid(),
            'utilisateur_id' => $auteur->id,
            'action' => $action,
            'entite_concernee' => 'secrets_configuration',
            'entite_id' => (string) SecretConfiguration::query()->where('cle', $cle)->value('id') ?: (string) Str::uuid(),
            'valeur_avant' => null,
            // La VALEUR n'est jamais tracée : le journal est consultable.
            'valeur_apres' => ['cle' => $cle],
            'adresse_poste' => request()->ip(),
        ]);
    }
}
