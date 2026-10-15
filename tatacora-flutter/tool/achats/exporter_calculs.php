<?php

declare(strict_types=1);

/*
| Rejoue, en PHP, les calculs de M7 du SERVEUR sur des cas donnes — pour que
| les tests Flutter confrontent `calcul_achats.dart` a la SOURCE, jamais a une
| formule recopiee (09/10/2026).
|
| Aucune base : `conformiteLigne()` et `ecartPourcentage()` sont purs,
| `evaluerConformite()` ne lit que `$commande->lignes()->pluck()` (rendu ici
| par un double) et la tolerance (rendue par une sous-classe), et
| `montant()` ne lit que deux attributs de la ligne.
|
| Entree (stdin, JSON) :
|   { "montants":  [["12.50","3.33"], ...],              // quantite, prix
|     "ecarts":    [["4.50","5.00"], ...],               // recue, commandee
|     "lignes":    [["4.50","5.00","10.00"], ...],       // recue, commandee, tolerance %
|     "evaluer":   [{"commandees":{"a":"5.00"},"recues":{"a":"4.00"},"tolerance":"10.00"}, ...],
|     "rapprocher":[{"commandees":{"a":"5.00"},"recues":{"a":"4.00"}}, ...] }
| Sortie (stdout, JSON) : les resultats dans le meme ordre, plus les phrases
| de refus et les gabarits de lang/fr/*.php.
|
| Usage : php tool/achats/exporter_calculs.php < cas.json
*/

$api = realpath(__DIR__ . '/../../../tatacora-api');

if ($api === false || ! is_file($api . '/vendor/autoload.php')) {
    fwrite(STDERR, "tatacora-api/vendor/autoload.php introuvable.\n");
    exit(2);
}

require $api . '/vendor/autoload.php';

use App\Domain\Achats\Models\CommandeAchat;
use App\Domain\Achats\Models\LigneCommandeAchat;
use App\Domain\Achats\Services\ReceptionService;
use App\Domain\Stocks\Services\MouvementStockService;
use App\Shared\Parametres\Services\ParametreSystemeService;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Support\Collection;

$cas = json_decode((string) stream_get_contents(STDIN), true);

if (! is_array($cas)) {
    fwrite(STDERR, "Entree JSON invalide.\n");
    exit(3);
}

/*
| Un ReceptionService dont la tolerance est fournie par le cas, sans base.
| `evaluerConformite()` est la methode REELLE du serveur, non recopiee.
*/
$serviceAvecTolerance = static function (string $tolerance): ReceptionService {
    $mouvements = (new ReflectionClass(MouvementStockService::class))->newInstanceWithoutConstructor();
    $parametres = (new ReflectionClass(ParametreSystemeService::class))->newInstanceWithoutConstructor();

    return new class ($mouvements, $parametres, $tolerance) extends ReceptionService {
        public function __construct(
            MouvementStockService $mouvements,
            ParametreSystemeService $parametres,
            private readonly string $toleranceFixee,
        ) {
            parent::__construct($mouvements, $parametres);
        }

        public function tolerancePourcentage(): string
        {
            return $this->toleranceFixee;
        }
    };
};

/*
| Une commande dont `lignes()->pluck()` rend les quantites du cas.
*/
$commandeAvec = static function (array $commandees): CommandeAchat {
    $relation = new class ($commandees) extends HasMany {
        /** @param array<string, string> $commandees */
        public function __construct(private readonly array $commandees)
        {
        }

        public function pluck($column, $key = null)
        {
            return new Collection($this->commandees);
        }
    };

    return new class ($relation) extends CommandeAchat {
        public function __construct(private readonly object $relationFixe)
        {
        }

        public function lignes(): HasMany
        {
            /** @var HasMany $relation */
            $relation = $this->relationFixe;

            return $relation;
        }
    };
};

$service = $serviceAvecTolerance('0.00');

$montants = [];
foreach ($cas['montants'] ?? [] as [$quantite, $prix]) {
    $ligne = new LigneCommandeAchat();
    $ligne->setRawAttributes(['quantite_commandee' => $quantite, 'prix_unitaire' => $prix]);
    $montants[] = $ligne->montant();
}

$ecarts = [];
foreach ($cas['ecarts'] ?? [] as [$recue, $commandee]) {
    $ecarts[] = $service->ecartPourcentage($recue, $commandee);
}

$lignes = [];
foreach ($cas['lignes'] ?? [] as [$recue, $commandee, $tolerance]) {
    $lignes[] = $service->conformiteLigne($recue, $commandee, $tolerance);
}

$evaluer = [];
foreach ($cas['evaluer'] ?? [] as $c) {
    $evaluer[] = $serviceAvecTolerance((string) $c['tolerance'])
        ->evaluerConformite($commandeAvec($c['commandees']), $c['recues']);
}

$rapprocher = [];
foreach ($cas['rapprocher'] ?? [] as $c) {
    $lignesRapprochees = [];
    foreach ($c['commandees'] as $article => $commandee) {
        $recue = $c['recues'][$article] ?? '0.00';
        $ecart = bcsub($recue, $commandee, 2);
        $cmp = bccomp($ecart, '0.00', 2);
        $lignesRapprochees[] = [
            'ecart' => $ecart,
            'concordance' => match (true) {
                $cmp === 0 => 'conforme',
                $cmp < 0 => 'manquant',
                default => 'excedent',
            },
        ];
    }
    $rapprocher[] = $lignesRapprochees;
}

$achats = require $api . '/lang/fr/achats.php';
$achatsPwa = require $api . '/lang/fr/achats_pwa.php';
$stocks = require $api . '/lang/fr/stocks.php';

echo json_encode([
    'montants' => $montants,
    'ecarts' => $ecarts,
    'lignes' => $lignes,
    'evaluer' => $evaluer,
    'rapprocher' => $rapprocher,
    'ecart_incalculable' => ReceptionService::ECART_INCALCULABLE,
    'statuts_saisissables' => \App\Domain\Achats\Services\CommandeAchatService::STATUTS_SAISISSABLES,
    'statuts' => CommandeAchat::STATUTS,
    'conformites' => \App\Domain\Achats\Models\BonReception::CONFORMITES,
    'evaluations' => \App\Domain\Achats\Models\Fournisseur::EVALUATIONS,
    'phrases' => [
        'commande_cloturee' => $achats['commande_cloturee'],
        'reception_vide' => $achats['reception_vide'],
        'cloture_impossible' => $achats['cloture_impossible'],
        'tolerance_absente' => $achats['tolerance_absente'],
        'motif_reception' => $achats['motif_reception'],
        'envoi_impossible' => $achats['envoi_impossible'],
        'facture_absente' => $achats['rapprochement']['facture_absente'],
        'fournisseur_inexistant' => $achats['validation']['fournisseur_inexistant'],
        'raison_sociale_obligatoire' => $achats['validation']['raison_sociale_obligatoire'],
        'evaluation_inconnue' => $achats['validation']['evaluation_inconnue'],
        'lignes_obligatoires' => $achats['validation']['lignes_obligatoires'],
        'article_inexistant' => $achats['validation']['article_inexistant'],
        'article_en_double' => $achats['validation']['article_en_double'],
        'quantite_positive' => $achats['validation']['quantite_positive'],
        'point_inexistant' => $achats['validation']['point_inexistant'],
        'prix_obligatoire' => $achatsPwa['appro']['prix_obligatoire'],
        'commande_creee' => $achatsPwa['appro']['commande_creee'],
        'reception_enregistree' => $achatsPwa['appro']['reception_enregistree'],
        'aucun_point' => $achatsPwa['appro']['aucun_point'],
        'aucun_fournisseur' => $achatsPwa['appro']['aucun_fournisseur'],
        'fournisseur_cree' => $achatsPwa['achats']['cree'],
        'fournisseur_modifie' => $achatsPwa['achats']['modifie'],
        'point_introuvable' => $stocks['point_introuvable'],
    ],
], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
