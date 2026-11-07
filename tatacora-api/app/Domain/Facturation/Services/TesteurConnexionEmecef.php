<?php

declare(strict_types=1);

namespace App\Domain\Facturation\Services;

use App\Shared\Secrets\Services\SecretsConfigurationService;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Support\Facades\Http;
use Throwable;

/**
 * « Tester la connexion » : `GET <API>/info/status` avec le jeton, résultat en
 * français. Ne retourne ni ne journalise JAMAIS le jeton, ni l'en-tête, ni le
 * corps brut de la réponse : seules des phrases construites ici sortent.
 */
final class TesteurConnexionEmecef
{
    public function __construct(
        private readonly ReglagesMecef $reglages,
        private readonly SecretsConfigurationService $secrets,
    ) {
    }

    /** @return array{succes: bool, detail: string} */
    public function tester(): array
    {
        $url = $this->reglages->urlApi();

        if (! str_starts_with(strtolower($url), 'https://')) {
            return ['succes' => false, 'detail' => __('parametres.mecef_manque_https')];
        }

        $jeton = $this->secrets->lire(SecretsConfigurationService::MECEF_JETON);

        if ($jeton === null) {
            return ['succes' => false, 'detail' => __('parametres.mecef_test_sans_jeton')];
        }

        try {
            $reponse = Http::withToken($jeton)->acceptJson()->timeout(15)->get($url . '/info/status');
        } catch (ConnectionException) {
            return ['succes' => false, 'detail' => __('parametres.mecef_test_injoignable')];
        } catch (Throwable) {
            return ['succes' => false, 'detail' => __('parametres.mecef_test_injoignable')];
        }

        if (in_array($reponse->status(), [401, 403], true)) {
            return ['succes' => false, 'detail' => __('parametres.mecef_test_jeton_refuse')];
        }

        if ($reponse->status() === 429) {
            return ['succes' => false, 'detail' => __('parametres.mecef_test_limite')];
        }

        if (! $reponse->successful()) {
            return ['succes' => false, 'detail' => __('parametres.mecef_test_code', ['code' => $reponse->status()])];
        }

        $donnees = $reponse->json();
        $donnees = is_array($donnees) ? $donnees : [];

        // `tokenValid` : la DGI dit elle-même si le jeton est périmé.
        if (($donnees['tokenValid'] ?? null) !== null && filter_var($donnees['tokenValid'], FILTER_VALIDATE_BOOLEAN) === false) {
            return ['succes' => false, 'detail' => __('parametres.mecef_test_jeton_perime')];
        }

        $ifuCompte = trim((string) ($donnees['ifu'] ?? ''));

        if ($ifuCompte !== '' && $this->reglages->ifu() !== '' && $ifuCompte !== $this->reglages->ifu()) {
            return ['succes' => false, 'detail' => __('parametres.mecef_test_ifu_different', [
                'compte' => $ifuCompte, 'reglage' => $this->reglages->ifu(),
            ])];
        }

        return ['succes' => true, 'detail' => __('parametres.mecef_test_ok')];
    }
}
