<?php

declare(strict_types=1);

namespace App\Shared\ImportExport\Services;

use App\Shared\ImportExport\Data\ColonneImport;
use App\Shared\ImportExport\Data\ModuleImport;
use App\Shared\ImportExport\Data\RapportControle;
use Illuminate\Support\Facades\DB;

/**
 * Contrôle de cohérence d'un fichier CSV d'import — la transcription serveur
 * d'`import-export-engine.js` §2 (`controler`), 02/09/2026.
 *
 * ## Erreur et avertissement ne sont pas la même chose (règle du maître)
 *
 *  - **Erreur** — la ligne est inexploitable (obligatoire vide, valeur hors
 *    liste, montant illisible, référence inconnue, doublon interne au
 *    fichier). Rien n'est importé tant qu'il en reste une.
 *  - **Avertissement** — la ligne est exploitable mais mérite un regard
 *    (doublon avec l'existant, colonne inconnue ignorée).
 *
 * ## Ce que la correspondance d'en-têtes tolère, et ce qu'elle ne tolère pas
 *
 * Casse et accents sont tolérés — exiger « Équipements » avec sa majuscule
 * rejetterait un fichier par ailleurs correct. Le SENS ne l'est jamais : une
 * colonne inconnue reste inconnue, elle n'est pas rapprochée « au plus
 * proche ».
 *
 * ## Le type `reference` est une vraie clé étrangère
 *
 * La cellule porte le libellé EXACT d'une fiche existante ; elle est résolue
 * en identifiant AU CONTRÔLE, et une fiche introuvable est une ERREUR — la
 * créer en silence transformerait une faute de frappe en doublon de
 * référentiel (PA-160/161), le défaut exact que « FK réelle, jamais texte
 * libre » interdit. Sélection par libellé exact, jamais un `LIKE`.
 */
class ControleImportService
{
    /**
     * @param  list<list<string>>  $tableau  lignes brutes, la première étant l'en-tête
     */
    public function controler(ModuleImport $module, array $tableau): RapportControle
    {
        if ($tableau === []) {
            return $this->refusGlobal(__('imports.controle.fichier_vide'));
        }

        $erreurs = [];
        $avertissements = [];

        [$carte, $inconnues, $manquantes] = $this->correspondance($module, $tableau[0]);

        foreach ($manquantes as $libelle) {
            $erreurs[] = ['ligne' => 1, 'colonne' => $libelle, 'message' => __('imports.controle.colonne_manquante', ['libelle' => $libelle, 'trouvees' => $this->entetesTrouvees($tableau[0])])];
        }

        // Une colonne en trop n'empêche pas l'import : ignorée, et on le dit.
        foreach ($inconnues as $libelle) {
            $avertissements[] = ['ligne' => 1, 'colonne' => $libelle, 'message' => __('imports.controle.colonne_inconnue', ['libelle' => $libelle])];
        }

        $corps = [];
        foreach (array_slice($tableau, 1) as $indice => $brute) {
            if (array_filter($brute, static fn ($v): bool => trim((string) $v) !== '') !== []) {
                // +2 : l'en-tête est la ligne 1, l'utilisateur compte comme Excel.
                if (app(TableurService::class)->estLigneExemple($brute)) {
                    $avertissements[] = ['ligne' => $indice + 2, 'colonne' => null, 'message' => __('imports.controle.ligne_exemple_ignoree')];

                    continue;
                }

                $corps[$indice + 2] = $brute;
            }
        }

        if ($manquantes !== []) {
            return new RapportControle(false, $erreurs, $avertissements, [], [
                'total' => count($corps), 'valides' => 0, 'en_erreur' => count($corps),
            ]);
        }

        $existants = $this->identifiantsExistants($module);
        $colonneIdentifiant = $module->colonne($module->identifiant);
        $libelleIdentifiant = $colonneIdentifiant !== null ? $colonneIdentifiant->libelle : $module->identifiant;
        $vusDansFichier = [];
        $lignesValides = [];
        $lignesEnErreur = [];

        foreach ($corps as $numero => $brute) {
            $objet = [];

            foreach ($module->colonnes as $colonne) {
                $valeur = isset($carte[$colonne->champ]) ? (string) ($brute[$carte[$colonne->champ]] ?? '') : '';
                $probleme = $this->controlerCellule($colonne, $valeur);

                if ($probleme !== null) {
                    $erreurs[] = ['ligne' => $numero, 'colonne' => $colonne->libelle, 'message' => $probleme];
                    $lignesEnErreur[$numero] = true;

                    continue;
                }

                $objet[$colonne->champ] = $this->convertir($colonne, $valeur);
            }

            $identifiant = $this->normaliser((string) ($objet[$module->identifiant] ?? ''));

            if ($identifiant !== '') {
                if (isset($vusDansFichier[$identifiant])) {
                    // Doublon INTERNE au fichier : erreur — importer deux fois
                    // la même ligne créerait deux fiches identiques d'un coup.
                    $erreurs[] = ['ligne' => $numero, 'colonne' => $libelleIdentifiant, 'message' => __('imports.controle.doublon_fichier', ['valeur' => (string) $objet[$module->identifiant]])];
                    $lignesEnErreur[$numero] = true;
                } else {
                    $vusDansFichier[$identifiant] = true;
                }

                if (in_array($identifiant, $existants, true)) {
                    if ($module->doublonExistantBloquant) {
                        $erreurs[] = ['ligne' => $numero, 'colonne' => $libelleIdentifiant, 'message' => __('imports.controle.doublon_existant_bloquant', ['valeur' => (string) $objet[$module->identifiant]])];
                        $lignesEnErreur[$numero] = true;
                    } else {
                        // Doublon avec l'EXISTANT : avertissement — souvent un
                        // rechargement volontaire, bloquer interdirait de
                        // recharger un référentiel corrigé.
                        $avertissements[] = ['ligne' => $numero, 'colonne' => $libelleIdentifiant, 'message' => __('imports.controle.doublon_existant', ['valeur' => (string) $objet[$module->identifiant]])];
                    }
                }
            }

            if (! isset($lignesEnErreur[$numero])) {
                $objet['_ligne'] = $numero;
                $lignesValides[] = $objet;
            }
        }

        return new RapportControle(
            ok: $erreurs === [],
            erreurs: $erreurs,
            avertissements: $avertissements,
            lignes: $erreurs === [] ? $lignesValides : [],
            resume: [
                'total' => count($corps),
                'valides' => count($lignesValides),
                'en_erreur' => count($lignesEnErreur),
            ],
        );
    }

    /**
     * Découpe un flux CSV — séparateur point-virgule, virgule OU tabulation
     * (celui que la première ligne emploie le plus), BOM UTF-8, UTF-16 ou
     * Windows-1252 : voir `TableurService::lireCsv()`.
     *
     * @return list<list<string>>
     */
    public function analyserCsv(string $contenu): array
    {
        return app(TableurService::class)->lireCsv($contenu);
    }

    /**
     * Lit un fichier déposé — `.xlsx` d'abord, CSV en secours — et rend les
     * lignes brutes, l'en-tête en premier. LÈVE avec un message français si
     * le fichier est illisible.
     *
     * @return list<list<string>>
     *
     * @throws \RuntimeException
     */
    public function analyserFichier(string $chemin, string $nomOriginal = ''): array
    {
        return app(TableurService::class)->lire($chemin, $nomOriginal);
    }

    // ------------------------------------------------------------- interne

    /**
     * @param  list<string>  $entetes
     * @return array{0: array<string, int>, 1: list<string>, 2: list<string>}
     *                                                                        carte champ => index, colonnes inconnues, obligatoires manquantes
     */
    private function correspondance(ModuleImport $module, array $entetes): array
    {
        $carte = [];
        $inconnues = [];

        foreach ($entetes as $index => $entete) {
            $normalise = $this->normaliser((string) $entete);

            if ($normalise === '') {
                continue;
            }

            $trouvee = null;
            foreach ($module->colonnes as $colonne) {
                if ($this->normaliser($colonne->libelle) === $normalise || $this->normaliser($colonne->champ) === $normalise) {
                    $trouvee = $colonne;
                    break;
                }
            }

            if ($trouvee !== null) {
                $carte[$trouvee->champ] = (int) $index;
            } else {
                $inconnues[] = (string) $entete;
            }
        }

        $manquantes = [];
        foreach ($module->colonnes as $colonne) {
            if ($colonne->requis && ! isset($carte[$colonne->champ])) {
                $manquantes[] = $colonne->libelle;
            }
        }

        return [$carte, $inconnues, $manquantes];
    }

    /**
     * Les en-têtes lus, pour que le message dise ce que le fichier contient
     * VRAIMENT — une seule « colonne » à rallonge trahit un séparateur perdu.
     *
     * @param  list<string>  $entetes
     */
    private function entetesTrouvees(array $entetes): string
    {
        $lues = array_values(array_filter(array_map(static fn ($v): string => trim((string) $v), $entetes), static fn (string $v): bool => $v !== ''));

        return $lues === [] ? __('imports.controle.aucune_entete') : implode(' ; ', $lues);
    }

    /** Vérifie une cellule contre le type déclaré — `null` : rien à redire. */
    private function controlerCellule(ColonneImport $colonne, string $valeur): ?string
    {
        $brut = trim($valeur);

        if ($brut === '') {
            return $colonne->requis ? __('imports.controle.valeur_obligatoire') : null;
        }

        if ($colonne->type === 'liste') {
            $valeurs = $colonne->valeurs ?? [];
            foreach ($valeurs as $attendue) {
                if ($this->normaliser($attendue) === $this->normaliser($brut)) {
                    return null;
                }
            }

            return __('imports.controle.valeur_hors_liste', ['valeur' => $brut, 'attendu' => implode(', ', $valeurs)]);
        }

        if ($colonne->type === 'nombre' || $colonne->type === 'montant') {
            $nettoye = $this->nettoyerNombre($brut);

            if (preg_match('/^-?\d+(\.\d+)?$/', $nettoye) !== 1) {
                return __('imports.controle.valeur_non_numerique', ['valeur' => $brut]);
            }

            // `bccomp`, jamais une comparaison flottante (règle du dépôt).
            if ($colonne->type === 'montant' && bccomp($nettoye, '0', 4) < 0) {
                return __('imports.controle.montant_negatif', ['valeur' => $brut]);
            }

            return null;
        }

        if ($colonne->type === 'texte' && $colonne->longueurMax !== null && mb_strlen($brut) > $colonne->longueurMax) {
            return __('imports.controle.texte_trop_long', ['colonne' => $colonne->libelle, 'maximum' => $colonne->longueurMax]);
        }

        if ($colonne->type === 'reference') {
            return $this->resoudreReference($colonne, $brut) === null
                ? __('imports.controle.reference_inconnue', [
                    'valeur' => $brut,
                    'referentiel' => $colonne->libelle,
                ])
                : null;
        }

        return null;
    }

    private function convertir(ColonneImport $colonne, string $valeur): mixed
    {
        $brut = trim($valeur);

        if ($brut === '') {
            return null;
        }

        if ($colonne->type === 'nombre' || $colonne->type === 'montant') {
            return $this->nettoyerNombre($brut);
        }

        if ($colonne->type === 'liste') {
            // Graphie CANONIQUE : « LOCALE » saisi en capitales devient
            // `locale`. Sans cela, un filtre par catégorie afficherait deux
            // entrées pour la même chose (règle du maître, engine l.219-224).
            foreach ($colonne->valeurs ?? [] as $attendue) {
                if ($this->normaliser($attendue) === $this->normaliser($brut)) {
                    return $attendue;
                }
            }

            return $brut;
        }

        if ($colonne->type === 'reference') {
            return $this->resoudreReference($colonne, $brut);
        }

        return $brut;
    }

    /**
     * Résout un libellé EXACT en identifiant — `null` : fiche introuvable.
     *
     * Égalité stricte, jamais `LIKE` : « une référence choisie par
     * `LIKE '%motif%'` sans `ORDER BY` » est le troisième piège de PA-161 —
     * MySQL remontait la 33 cl à la place de la 66 cl.
     */
    private function resoudreReference(ColonneImport $colonne, string $libelle): ?string
    {
        [$table, $champ] = explode('.', (string) $colonne->reference, 2);

        $identifiant = DB::table($table)->where($champ, $libelle)->value('id');

        return is_string($identifiant) ? $identifiant : null;
    }

    /**
     * @return list<string> identifiants existants, normalisés
     */
    private function identifiantsExistants(ModuleImport $module): array
    {
        [$table, $champ] = match ($module->cle) {
            'm3-clients' => ['clients', 'nom'],
            'm1-hebergement' => ['unites_hebergement', 'numero'],
            'm5-bar' => ['cartes_boisson', 'libelle'],
            'm4-restaurant' => ['plats', 'libelle'],
            'm6-stocks' => ['articles', 'libelle'],
            'm7-achats' => ['fournisseurs', 'raison_sociale'],
            'm8-vehicules' => ['vehicules', 'immatriculation'],
            'm9-tourisme' => ['circuits', 'nom'],
            default => [null, null],
        };

        if ($table === null) {
            return [];
        }

        return DB::table($table)->pluck($champ)
            ->map(fn ($v): string => $this->normaliser((string) $v))
            ->all();
    }

    /** Excel sème espaces fines et virgules décimales — tolérées, jamais devinées. */
    private function nettoyerNombre(string $brut): string
    {
        return str_replace([' ', "\u{202F}", "\u{00A0}", ','], ['', '', '', '.'], $brut);
    }

    /** Casse et accents neutralisés — le SENS, jamais (voir l'entête). */
    private function normaliser(string $texte): string
    {
        return app(TableurService::class)->normaliser($texte);
    }

    private function refusGlobal(string $message): RapportControle
    {
        return new RapportControle(false, [['ligne' => 0, 'colonne' => null, 'message' => $message]], [], [], [
            'total' => 0, 'valides' => 0, 'en_erreur' => 0,
        ]);
    }
}
