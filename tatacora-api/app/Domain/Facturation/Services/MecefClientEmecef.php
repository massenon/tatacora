<?php

declare(strict_types=1);

namespace App\Domain\Facturation\Services;

use App\Domain\Comptabilite\Services\CalculTvaService;
use App\Domain\Facturation\Exceptions\EmecefConfigurationIncomplete;
use App\Domain\Facturation\Exceptions\EmecefDonneesInvalides;
use App\Domain\Facturation\Exceptions\EmecefIndisponible;
use App\Domain\Facturation\Exceptions\EmecefJetonRefuse;
use App\Domain\Facturation\Exceptions\EmecefLimiteAtteinte;
use App\Domain\Facturation\Exceptions\EmecefRefus;
use App\Domain\Facturation\Exceptions\EmecefReponseInvalide;
use App\Domain\Facturation\Exceptions\EmecefUidExpire;
use App\Domain\Facturation\Models\Avoir;
use App\Domain\Facturation\Models\Facture;
use App\Shared\Secrets\Services\SecretsConfigurationService;
use DateTimeImmutable;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Http\Client\Response;
use Illuminate\Support\Facades\Http;
use Throwable;

/**
 * Le client e-MECeF : la normalisation EN LIGNE, par l'API de la DGI
 * (docs/SPEC_FACTURATION_NORMALISEE_MECEF.md §5). Réécrit au minimum d'après le
 * contrat du paquet `laraSgmefQR` (lu, jamais copié).
 *
 * ## Deux appels, dans la foulée
 *
 * `POST /invoice` crée la facture à la DGI (un `uid`, des totaux, PAS de QR) ;
 * `PUT /invoice/{uid}/confirm` la confirme (`codeMECeFDGI`, `qrCode`, `dateTime`,
 * `counters`, `nim`). Une facture non confirmée EXPIRE après 2 minutes : les deux
 * appels se font dans le même passage. Le `uid` d'une création réussie est conservé
 * sur la pièce : si la confirmation échoue (réseau), le rejeu confirme CE `uid` tant
 * qu'il est valide, au lieu de créer une seconde facture à la DGI.
 *
 * ## Jamais deux fois
 *
 * Une pièce déjà normalisée n'est JAMAIS retransmise (garde dans
 * {@see EmissionFactureService}) ; un verrou par pièce interdit deux passages
 * simultanés.
 *
 * ## Le jeton
 *
 * Lu ICI SEUL ({@see SecretsConfigurationService::lire()}), posé en `Authorization:
 * Bearer`, jamais journalisé, jamais cité dans un message : les erreurs sont
 * reconstruites en phrases fixes.
 */
final class MecefClientEmecef implements CertifieLesAvoirsInterface, MecefClientInterface
{
    /** Au-delà de 100 s, le `uid` est tenu pour expiré (la DGI l'expire à 120 s). */
    private const VALIDITE_UID_SECONDES = 100;

    private const DELAI_REQUETE = 30;

    public function __construct(
        private readonly ReglagesMecef $reglages,
        private readonly SecretsConfigurationService $secrets,
        private readonly CalculTvaService $tva,
    ) {
    }

    public function estModeReel(): bool
    {
        return true;
    }

    public function certifier(Facture $facture): CertificationMecefResultat
    {
        $facture->loadMissing('lignes', 'client');
        [$ifuClient, $nomClient] = EmissionFactureService::acheteurPourNormalisation($facture);

        return $this->normaliser(
            $facture,
            'FV',
            $this->articlesDe($facture),
            $this->paiementsDe($facture),
            null,
            $nomClient,
            $ifuClient,
        );
    }

    public function certifierAvoir(Avoir $avoir): CertificationMecefResultat
    {
        $facture = $avoir->facture()->with('lignes', 'client')->firstOrFail();

        if (! $facture->estNormalisee() || blank($facture->code_mecef)) {
            throw new EmecefDonneesInvalides(__('facturation.emecef.avoir_sans_origine'));
        }

        $total = $this->entier((string) $facture->montant_ttc);
        $montant = $this->entier((string) $avoir->montant);
        $articles = $montant === $total
            ? $this->articlesDe($facture)
            : [[
                'name' => mb_substr(__('facturation.libelle_avoir', ['numero' => (string) $facture->numero]), 0, 100),
                'price' => $montant,
                'quantity' => 1,
                'taxGroup' => $this->tva->estActive() ? 'B' : 'A',
            ]];

        return $this->normaliser(
            $avoir,
            'FA',
            $articles,
            [['name' => $this->modePrincipal($facture), 'amount' => $montant]],
            (string) $facture->code_mecef,
            EmissionFactureService::acheteurPourNormalisation($facture)[1],
            EmissionFactureService::acheteurPourNormalisation($facture)[0],
        );
    }

    /**
     * @param  list<array<string, mixed>>  $articles
     * @param  list<array{name: string, amount: int|float}>  $paiements
     */
    private function normaliser(
        Facture|Avoir $document,
        string $type,
        array $articles,
        array $paiements,
        ?string $reference,
        string $clientNom,
        ?string $clientIfu = null,
    ): CertificationMecefResultat {
        $manques = $this->reglages->manquantsEmecef();

        if ($manques !== []) {
            throw new EmecefConfigurationIncomplete($manques);
        }

        $jeton = $this->secrets->lire(SecretsConfigurationService::MECEF_JETON);

        if ($jeton === null) {
            throw new EmecefConfigurationIncomplete([__('parametres.mecef_manque_jeton')]);
        }

        $verrou = cache()->lock('emecef:' . $document->getTable() . ':' . $document->getKey(), 150);

        if (! $verrou->get()) {
            throw EmecefIndisponible::reseau();
        }

        try {
            return $this->executer($document, $jeton, [
                'ifu' => $this->reglages->ifu(),
                'type' => $type,
                // IFU du client : facultatif (13 chiffres) ; vide = client sans IFU, la clé n'est pas envoyée.
                'client' => ['name' => mb_substr($clientNom, 0, 100), ...($clientIfu !== null ? ['ifu' => $clientIfu] : [])],
                'operator' => ['id' => $this->reglages->operateurId(), 'name' => $this->reglages->operateurNom()],
                'items' => $articles,
                'payment' => $paiements,
                ...($reference !== null ? ['reference' => $reference] : []),
            ]);
        } finally {
            $verrou->release();
        }
    }

    /** @param array<string, mixed> $demande */
    private function executer(Facture|Avoir $document, string $jeton, array $demande): CertificationMecefResultat
    {
        $uid = $this->uidValide($document);

        // Deux tours au plus : un `uid` expiré (404 à la confirmation) se recrée UNE fois.
        for ($tour = 0; $tour < 2; $tour++) {
            if ($uid === null) {
                $uid = $this->creer($jeton, $demande);
                $document->update(['emecef_uid' => $uid, 'emecef_uid_le' => now()]);
            }

            try {
                return $this->confirmer($jeton, $uid, $document);
            } catch (EmecefUidExpire) {
                $document->update(['emecef_uid' => null, 'emecef_uid_le' => null]);
                $uid = null;
            }
        }

        throw EmecefIndisponible::reseau();
    }

    private function uidValide(Facture|Avoir $document): ?string
    {
        $uid = (string) $document->emecef_uid;
        $le = $document->emecef_uid_le;

        if ($uid === '' || $le === null || $le->lt(now()->subSeconds(self::VALIDITE_UID_SECONDES))) {
            return null;
        }

        return $uid;
    }

    /** @param array<string, mixed> $demande */
    private function creer(string $jeton, array $demande): string
    {
        $reponse = $this->appeler('POST', '/invoice', $jeton, $demande);
        $json = $this->corps($reponse);
        $this->exigerSansErreur($json);
        $uid = trim((string) ($json['uid'] ?? ''));

        if ($uid === '') {
            throw new EmecefReponseInvalide(false);
        }

        return $uid;
    }

    private function confirmer(string $jeton, string $uid, Facture|Avoir $document): CertificationMecefResultat
    {
        $reponse = $this->appeler('PUT', '/invoice/' . rawurlencode($uid) . '/confirm', $jeton, null, confirmation: true);
        $json = $this->corps($reponse, confirmation: true);
        $this->exigerSansErreur($json);

        $code = trim((string) ($json['codeMECeFDGI'] ?? ''));
        $qr = trim((string) ($json['qrCode'] ?? ''));
        $nim = trim((string) ($json['nim'] ?? ''));

        if ($code === '' || $qr === '' || $nim === '') {
            throw new EmecefReponseInvalide(true);
        }

        $compteur = $this->compteurDe((string) ($json['counters'] ?? ''));

        return new CertificationMecefResultat(
            // Identité fiscale « NIM-TC » ; sans compteur lisible, le code MECeF (unique) la porte.
            nim: $compteur !== null ? $nim . '-' . $compteur : $code,
            cachetFiscal: $qr,
            dateCertification: $this->dateDe((string) ($json['dateTime'] ?? '')),
            codeMecef: $code,
            compteur: $compteur,
        );
    }

    /**
     * @param  array<string, mixed>|null  $corps
     */
    private function appeler(string $methode, string $chemin, string $jeton, ?array $corps, bool $confirmation = false): Response
    {
        $requete = Http::withToken($jeton)->acceptJson()->timeout(self::DELAI_REQUETE);

        try {
            $reponse = match ($methode) {
                'POST' => $requete->post($this->reglages->urlApi() . $chemin, $corps ?? []),
                default => $requete->put($this->reglages->urlApi() . $chemin),
            };
        } catch (ConnectionException) {
            // La requête est peut-être partie sans réponse : après une confirmation, l'issue est incertaine.
            throw $confirmation ? new EmecefReponseInvalide(true) : EmecefIndisponible::reseau();
        } catch (Throwable) {
            throw EmecefIndisponible::reseau();
        }

        $this->classer($reponse, $confirmation);

        return $reponse;
    }

    private function classer(Response $reponse, bool $confirmation): void
    {
        $code = $reponse->status();

        if (in_array($code, [401, 403], true)) {
            throw new EmecefJetonRefuse();
        }

        if ($code === 429) {
            $attente = (int) $reponse->header('Retry-After');

            throw new EmecefLimiteAtteinte($attente > 0 ? $attente : 60);
        }

        if ($confirmation && $code === 404) {
            throw new EmecefUidExpire();
        }

        if ($code >= 500) {
            throw $confirmation ? new EmecefReponseInvalide(true) : EmecefIndisponible::serveur($code);
        }

        if ($code >= 400) {
            $json = $reponse->json();

            throw EmecefRefus::depuis(is_array($json) ? (string) ($json['errorDesc'] ?? $json['message'] ?? '') : '');
        }
    }

    /** @return array<string, mixed> */
    private function corps(Response $reponse, bool $confirmation = false): array
    {
        $json = $reponse->json();

        if (! is_array($json)) {
            throw new EmecefReponseInvalide($confirmation);
        }

        return $json;
    }

    /** @param array<string, mixed> $json */
    private function exigerSansErreur(array $json): void
    {
        $code = trim((string) ($json['errorCode'] ?? ''));

        if ($code !== '' && strtoupper($code) !== 'OK') {
            throw EmecefRefus::depuis((string) ($json['errorDesc'] ?? ''));
        }
    }

    /** « 12/45 FV » → 12 (le compteur de la facture) ; `null` si illisible. */
    private function compteurDe(string $counters): ?string
    {
        return preg_match('/^\s*(\d+)\s*\//', $counters, $m) === 1 ? $m[1] : null;
    }

    private function dateDe(string $iso): DateTimeImmutable
    {
        try {
            return $iso === '' ? new DateTimeImmutable() : new DateTimeImmutable($iso);
        } catch (Throwable) {
            return new DateTimeImmutable();
        }
    }

    /**
     * Les articles en prix TTC unitaires entiers (FCFA), groupe de taxe d'après la
     * configuration : TVA active → B, sinon A ; « taxe de séjour » → F.
     *
     * @return list<array<string, mixed>>
     */
    private function articlesDe(Facture $facture): array
    {
        $articles = [];
        $total = 0;

        foreach ($facture->lignes as $ligne) {
            // Hors TVA, HT = TTC ; avec la TVA, le TTC unitaire est celui du service (un seul auteur).
            $unitaireTtc = $this->entier($this->tva->estActive()
                ? $this->tva->htVersTtc((string) $ligne->prix_unitaire)
                : (string) $ligne->prix_unitaire);
            $quantite = (float) $ligne->quantite;
            $total += (int) round($unitaireTtc * $quantite);

            $sejour = str_contains($this->sansAccents(mb_strtolower((string) $ligne->libelle)), 'taxe de sejour');

            $articles[] = [
                'name' => $sejour ? 'TAXE DE SEJOUR' : mb_substr((string) $ligne->libelle, 0, 100),
                'price' => $unitaireTtc,
                'quantity' => $quantite == (int) $quantite ? (int) $quantite : $quantite,
                'taxGroup' => $sejour ? 'F' : ($this->tva->estActive() ? 'B' : 'A'),
            ];
        }

        // Les totaux de la facture et de ses lignes doivent concorder (arrondi d'un franc toléré).
        $ecart = abs($total - $this->entier((string) $facture->montant_ttc));

        if ($ecart > 1) {
            throw new EmecefDonneesInvalides(__('facturation.emecef.totaux_incoherents', ['ecart' => $ecart]));
        }

        return $articles;
    }

    /**
     * Les règlements ACTIFS ; le reste dû part en `CREDIT` (e-MECeF le sait, le boîtier non).
     *
     * @return list<array{name: string, amount: int|float}>
     */
    private function paiementsDe(Facture $facture): array
    {
        $total = $this->entier((string) $facture->montant_ttc);
        $paiements = [];
        $verse = 0;

        foreach ($facture->paiements()->where('statut', 'actif')->get() as $paiement) {
            $montant = $this->entier((string) $paiement->montant);
            $verse += $montant;
            $paiements[] = ['name' => $this->nomPaiement((string) $paiement->mode_paiement), 'amount' => $montant];
        }

        if ($verse < $total) {
            $paiements[] = ['name' => 'CREDIT', 'amount' => $total - $verse];
        }

        return $paiements;
    }

    private function modePrincipal(Facture $facture): string
    {
        $principal = $facture->paiements()->where('statut', 'actif')->orderByDesc('montant')->first();

        return $principal === null ? 'AUTRE' : $this->nomPaiement((string) $principal->mode_paiement);
    }

    private function nomPaiement(string $mode): string
    {
        return match ($mode) {
            'especes' => 'ESPECES',
            'mobile_money' => 'MOBILEMONEY',
            'carte' => 'CARTEBANCAIRE',
            'virement' => 'VIREMENT',
            default => 'AUTRE',
        };
    }

    /** Un montant décimal en francs ENTIERS (le XOF n'a pas de sous-unité). */
    private function entier(string $montant): int
    {
        return (int) round((float) $montant);
    }

    private function sansAccents(string $texte): string
    {
        return strtr($texte, ['é' => 'e', 'è' => 'e', 'ê' => 'e', 'ë' => 'e', 'à' => 'a', 'â' => 'a', 'ô' => 'o', 'î' => 'i', 'ï' => 'i', 'ù' => 'u', 'û' => 'u', 'ç' => 'c']);
    }
}
