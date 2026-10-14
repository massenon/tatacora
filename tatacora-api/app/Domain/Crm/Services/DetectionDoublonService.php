<?php

declare(strict_types=1);

namespace App\Domain\Crm\Services;

use App\Domain\Crm\Models\Client;
use Illuminate\Support\Collection;

/**
 * Détection de doublons à la création d'une fiche client — RG-18.
 *
 * **Avertissant, jamais bloquant.** La règle dit « recherche de doublon
 * (nom + téléphone approchants) proposée à la création, pas bloquante mais
 * avertissante » (01_BUSINESS_ANALYSIS_SPEC.md §RG-18). Bloquer serait pire
 * que le mal : deux personnes peuvent légitimement porter le même nom, et un
 * réceptionniste empêché de créer une fiche contournerait la règle en
 * saisissant une orthographe approximative — recréant exactement le doublon
 * que la règle cherche à éviter.
 *
 * Ce service est appelé par le FormRequest de création (avertissement retourné
 * à l'interface), jamais par un Observer qui refuserait l'enregistrement.
 */
class DetectionDoublonService
{
    /** Un numéro identique est le signal le plus fiable : il suffit seul. */
    private const SCORE_TELEPHONE = 100;

    /** Nom identique après normalisation — fort, mais pas décisif seul. */
    private const SCORE_NOM_EXACT = 60;

    /** Nom très proche (une ou deux lettres d'écart) — piste, pas preuve. */
    private const SCORE_NOM_PROCHE = 35;

    /** En dessous, le bruit dépasserait le signal et l'alerte serait ignorée. */
    private const SEUIL_SIGNALEMENT = 60;

    /**
     * Retourne les fiches existantes ressemblant assez à la saisie pour
     * mériter une confirmation humaine, les plus probables en premier.
     *
     * @return Collection<int, array{client: Client, score: int, motif: string}>
     */
    public function rechercherDoublons(string $nom, string $telephone, ?string $exclureId = null): Collection
    {
        $nomNormalise = $this->normaliser($nom);
        $telephoneNormalise = $this->normaliserTelephone($telephone);

        return Client::query()
            ->when($exclureId !== null, fn ($requete) => $requete->whereKeyNot($exclureId))
            ->get()
            ->map(fn (Client $candidat) => $this->evaluer($candidat, $nomNormalise, $telephoneNormalise))
            ->filter()
            ->sortByDesc('score')
            ->values();
    }

    /**
     * Confronte une fiche existante à la saisie et retourne son score de
     * ressemblance, ou null si l'écart est trop grand pour mériter une alerte.
     *
     * @return array{client: Client, score: int, motif: string}|null
     */
    private function evaluer(Client $candidat, string $nomNormalise, string $telephoneNormalise): ?array
    {
        $score = 0;
        $motifs = [];

        if ($telephoneNormalise !== '' && $this->normaliserTelephone($candidat->telephone) === $telephoneNormalise) {
            $score += self::SCORE_TELEPHONE;
            $motifs[] = 'même numéro de téléphone';
        }

        $nomCandidat = $this->normaliser($candidat->nom);

        if ($nomCandidat === $nomNormalise) {
            $score += self::SCORE_NOM_EXACT;
            $motifs[] = 'nom identique';
        } elseif ($this->nomsProches($nomCandidat, $nomNormalise)) {
            $score += self::SCORE_NOM_PROCHE;
            $motifs[] = 'nom très proche';
        }

        if ($score < self::SEUIL_SIGNALEMENT) {
            return null;
        }

        return [
            'client' => $candidat,
            'score' => $score,
            'motif' => implode(', ', $motifs),
        ];
    }

    /**
     * Message destiné à l'utilisateur — formulé comme une question, pas comme
     * un refus : c'est lui qui tranche, le système ne fait que signaler.
     *
     * @param  Collection<int, array{client: Client, score: int, motif: string}>  $doublons
     */
    public function messageAvertissement(Collection $doublons): ?string
    {
        if ($doublons->isEmpty()) {
            return null;
        }

        $noms = $doublons->take(3)
            ->map(fn (array $d): string => sprintf('%s (%s)', $d['client']->nomComplet(), $d['motif']))
            ->implode(' ; ');

        return sprintf(
            'Une fiche existante pourrait correspondre : %s. Vérifiez avant de créer un doublon (RG-18).',
            $noms,
        );
    }

    /**
     * Accents et casse retirés : « KORA », « Kora » et « Korá » désignent la
     * même personne pour un réceptionniste, donc pour cette détection aussi.
     */
    private function normaliser(string $valeur): string
    {
        $sansAccent = iconv('UTF-8', 'ASCII//TRANSLIT//IGNORE', $valeur);

        return preg_replace('/[^a-z0-9]/', '', mb_strtolower($sansAccent ?: $valeur)) ?? '';
    }

    /**
     * Les numéros béninois sont saisis avec des espaces variables
     * (« 01 97 35 59 74 », « 0197355974 ») : seuls les chiffres comptent.
     */
    private function normaliserTelephone(?string $telephone): string
    {
        return preg_replace('/\D/', '', $telephone ?? '') ?? '';
    }

    /**
     * Tolère une faute de frappe courte sur des chaînes assez longues pour que
     * la proximité soit significative — « Kora »/« Korra », pas « Ali »/« Ale ».
     */
    private function nomsProches(string $a, string $b): bool
    {
        if ($a === '' || $b === '' || min(strlen($a), strlen($b)) < 4) {
            return false;
        }

        return levenshtein($a, $b) <= 2;
    }
}
