<?php

declare(strict_types=1);

namespace App\Domain\Facturation\Support;

use App\Domain\Facturation\Models\Facture;
use App\Domain\Facturation\Models\LigneFacture;
use App\Domain\Facturation\Models\Paiement;
use App\Domain\Facturation\Services\ModeFacturation;
use App\Domain\Ventes\Models\LigneVente;
use App\Domain\Ventes\Models\Vente;
use App\Domain\Ventes\Services\VenteService;
use App\Pwa\Livewire\Facturation\Facturation;
use App\Shared\Parametres\Services\ApparenceEtablissementService;
use App\Shared\Parametres\Services\ParametreSystemeService;
use App\Shared\ReportEngine\Data\EnTeteRapport;
use App\Shared\ReportEngine\Services\ReportHeaderService;
use Barryvdh\DomPDF\Facade\Pdf;
use Illuminate\Support\Collection;
use RuntimeException;

/**
 * Génère les documents ÉCHANTILLONS du dossier `presentation/` à partir des VRAIS gabarits du
 * serveur (`pdf.facture-mecef`, `pwa.pos.ticket-thermique`) et de données FICTIVES.
 *
 * ## Ce qui garantit qu'un échantillon ne passe jamais pour un vrai document
 *
 *  - les gabarits ne sont PAS modifiés : le filigrane et le bandeau « ÉCHANTILLON — SANS VALEUR
 *    FISCALE » sont injectés dans le HTML RENDU par ce générateur, le seul à le faire. Rien dans
 *    les contrôleurs ni dans les vues de production ne sait les produire ;
 *  - aucune base n'est lue : les paramètres sont ceux de {@see ParametresEchantillon}, les modèles
 *    ne sont jamais enregistrés ;
 *  - le contenu du QR est manifestement factice (`F;ECHANTILLON;…`) ;
 *  - la génération est refusée en production.
 */
final class GenerateurEchantillons
{
    public const MENTION = 'ÉCHANTILLON — SANS VALEUR FISCALE';

    public const FICHIER_SIMPLE = '01_facture_simple_A4.pdf';

    public const FICHIER_NORMALISEE = '02_facture_normalisee_A4.pdf';

    public const FICHIER_TICKET_WEB_SIMPLE = '03_ticket_thermique_web_simple.html';

    public const FICHIER_TICKET_WEB_MECEF = '03_ticket_thermique_web_mecef.html';

    /** Le QR de l'échantillon : cinq champs comme le vrai, mais sans aucun sens fiscal. */
    public const QR_FACTICE = 'F;ECHANTILLON;ECHA-NTIL-LON0-FAUX-0000-0000;0000000000000;20261107120000';

    public const NIM_TC_FACTICE = 'ECHANTILLON-1';

    public const CODE_FACTICE = 'ECHA-NTIL-LON0-FAUX-0000-0000';

    /**
     * Écrit les échantillons serveur dans [$dossier] (créé au besoin) et rend leurs chemins.
     *
     * @return array<string, string> nom de fichier => chemin
     */
    public function generer(string $dossier): array
    {
        if (app()->isProduction()) {
            throw new RuntimeException('La génération d\'échantillons est interdite en production.');
        }

        if (! is_dir($dossier) && ! mkdir($dossier, 0775, true) && ! is_dir($dossier)) {
            throw new RuntimeException('Dossier impossible à créer : '.$dossier);
        }

        $dossier = rtrim($dossier, '/');
        $ecrits = [];

        $documents = [
            self::FICHIER_SIMPLE => fn (): string => $this->pdf($this->htmlFactureA4(normalisee: false)),
            self::FICHIER_NORMALISEE => fn (): string => $this->pdf($this->htmlFactureA4(normalisee: true)),
            self::FICHIER_TICKET_WEB_SIMPLE => fn (): string => $this->htmlTicketWeb(ModeFacturation::Desactive),
            self::FICHIER_TICKET_WEB_MECEF => fn (): string => $this->htmlTicketWeb(ModeFacturation::Boitier),
        ];

        foreach ($documents as $nom => $rendre) {
            $chemin = $dossier.'/'.$nom;
            file_put_contents($chemin, $rendre());
            $ecrits[$nom] = $chemin;
        }

        return $ecrits;
    }

    /** Le HTML de la facture A4 (utile aux tests : on y cherche le QR dessiné). */
    public function htmlFactureA4(bool $normalisee): string
    {
        return $this->souslesParametresFictifs(
            $normalisee ? ModeFacturation::Boitier : ModeFacturation::Desactive,
            function () use ($normalisee): string {
                $facture = $this->factureFictive($normalisee);

                $html = view('pdf.facture-mecef', [
                    'facture' => $facture,
                    'client' => null,
                    'activites' => Facturation::ACTIVITES,
                    'modesPaiement' => VenteService::MODES_PAIEMENT,
                    'totalAvoirs' => '0.00',
                    'net' => (string) $facture->montant_ttc,
                    'resteDu' => '0.00',
                    'auteur' => 'Réception (exemple)',
                    'entete' => $this->enteteFictive(),
                ])->render();

                return $this->marquerEchantillon($html, '<body>', a4: true);
            },
        );
    }

    /** Le HTML du ticket web 80 mm (celui que le navigateur imprime), sans son script d'impression. */
    public function htmlTicketWeb(ModeFacturation $mode): string
    {
        return $this->souslesParametresFictifs($mode, function (): string {
            $html = view('pwa.pos.ticket-thermique', [
                'vente' => $this->venteFictive(),
                'quand' => '07/11/2026 12:00',
                'entete' => $this->enteteFictive(),
            ])->render();

            // Le script d'impression automatique n'a pas sa place dans un échantillon.
            $html = (string) preg_replace('#<script>.*?</script>#s', '', $html);

            return $this->marquerEchantillon($html, '<body>', a4: false);
        });
    }

    private function pdf(string $html): string
    {
        return Pdf::loadHTML($html)->setPaper('a4', 'portrait')->output();
    }

    /**
     * Pose le filigrane et le bandeau, UNIQUEMENT dans le document rendu ici.
     */
    private function marquerEchantillon(string $html, string $balise, bool $a4): string
    {
        $mention = e(self::MENTION);

        if ($a4) {
            $marque = '<div style="position: fixed; top: -11mm; left: 0; right: 0; text-align: center; '
                .'background: #C62828; color: #ffffff; font-weight: bold; font-size: 10pt; padding: 3px 0;">'
                .$mention.'</div>'
                .'<div style="position: fixed; top: 45%; left: 0; right: 0; text-align: center; '
                .'font-size: 27pt; font-weight: bold; color: #C62828; opacity: 0.14; letter-spacing: 2px;">'
                .$mention.'</div>';
        } else {
            $marque = '<div style="border: 2px solid #111827; padding: 2mm; margin-bottom: 2mm; text-align: center; '
                .'font-weight: bold; font-size: 11px;">'.$mention.'</div>';
        }

        if (! str_contains($html, $balise)) {
            throw new RuntimeException('Gabarit inattendu : balise '.$balise.' introuvable.');
        }

        $html = (string) preg_replace('#'.preg_quote($balise, '#').'#', $balise.$marque, $html, 1);

        if (! $a4) {
            // Le ticket web se rend aussi à la fin : un bandeau en haut ET en bas.
            $html = (string) preg_replace('#</body>#', $marque.'</body>', $html, 1);
        }

        return $html;
    }

    /**
     * Exécute [$rendu] avec des paramètres fictifs (aucune lecture de la base), puis restaure.
     *
     * @template T
     *
     * @param callable(): T $rendu
     *
     * @return T
     */
    private function souslesParametresFictifs(ModeFacturation $mode, callable $rendu): mixed
    {
        $anciennes = app()->bound(ParametreSystemeService::class)
            ? app(ParametreSystemeService::class)
            : null;
        $langue = app()->getLocale();

        app()->instance(ParametreSystemeService::class, new ParametresEchantillon([
            ModeFacturation::CLE => $mode->value,
            ReportHeaderService::CLE_IFU => ParametresEchantillon::IFU_FICTIF,
        ]));
        app()->setLocale('fr');

        try {
            return $rendu();
        } finally {
            app()->setLocale($langue);

            if ($anciennes === null) {
                app()->forgetInstance(ParametreSystemeService::class);
            } else {
                app()->instance(ParametreSystemeService::class, $anciennes);
            }
        }
    }

    /**
     * L'en-tête : l'identité par DÉFAUT du dépôt (Gîte Chez Noël) + l'IFU fictif ; le logo est
     * celui livré dans `public/assets/img/logo.png`, jamais un logo téléversé.
     */
    private function enteteFictive(): EnTeteRapport
    {
        $e = app(ReportHeaderService::class, ['parametres' => app(ParametreSystemeService::class)])
            ->genererEnTete('Facture', '', null);
        $logo = public_path(ApparenceEtablissementService::ACTIF_LIVRE);

        return new EnTeteRapport(
            logo: is_file($logo) ? $logo : null,
            raisonSociale: $e->raisonSociale,
            sousTitre: $e->sousTitre,
            adresse: $e->adresse,
            telephone: $e->telephone,
            email: $e->email,
            siteWeb: $e->siteWeb,
            ifu: $e->ifu,
            rccm: null,
            typeRapport: $e->typeRapport,
            periode: '',
            auteur: 'Réception (exemple)',
            dateEdition: '07/11/2026 à 12:00',
            mentionInstitutionnelle: $e->mentionInstitutionnelle,
            promoteur: null,
            whatsapp: null,
            regimeFiscal: null,
            enseigne: $e->enseigne,
        );
    }

    /**
     * La facture FICTIVE du Gîte, jamais enregistrée : 2 nuitées, repas, jus, taxe de séjour.
     * Montants TTC en FCFA entiers ; aucune TVA calculée (le poste n'en calcule aucune).
     */
    private function factureFictive(bool $normalisee): Facture
    {
        $attributs = [
            'id' => '00000000-0000-4000-8000-000000000001',
            'numero' => 'F-2026-00001',
            'origine' => 'pos_sejour',
            'client_id' => null,
            'date_emission' => '2026-11-07',
            'montant_ht' => '33500.00',
            'montant_tva' => '0.00',
            'montant_ttc' => '33500.00',
            'statut' => 'certifiee',
            'acheteur_nom' => 'Client Exemple',
            'acheteur_ifu' => '1234567890123',
        ];

        if ($normalisee) {
            $attributs += [
                'numero_mecef' => self::NIM_TC_FACTICE,
                'code_mecef' => self::CODE_FACTICE,
                'qr_code_fiscal' => self::QR_FACTICE,
                'normalisation_statut' => 'normalisee',
                'normalisation_mode' => 'boitier',
                'normalisation_compteur' => '1',
                'normalisee_le' => '2026-11-07 12:00:00',
            ];
        }

        $facture = new Facture($attributs);

        $lignes = [
            ['M1', 'Chambre ventilée, nuitée', 2, 12000],
            ['M4', 'Repas du soir : poulet braisé, igname', 2, 3500],
            ['M5', 'Jus de bissap', 3, 500],
            ['M1', 'Taxe de séjour', 2, 500],
        ];
        $objets = [];
        foreach ($lignes as $i => [$module, $libelle, $quantite, $prix]) {
            $objets[] = new LigneFacture([
                'id' => sprintf('00000000-0000-4000-8000-0000000001%02d', $i),
                'facture_id' => $attributs['id'],
                'source_module' => $module,
                'libelle' => $libelle,
                'quantite' => (string) $quantite,
                'prix_unitaire' => (string) $prix,
                'montant' => (string) ($quantite * $prix),
            ]);
        }

        $paiements = [];
        foreach ([['especes', 20000], ['mobile_money', 13500]] as $i => [$mode, $montant]) {
            $paiements[] = new Paiement([
                'id' => sprintf('00000000-0000-4000-8000-0000000002%02d', $i),
                'facture_id' => $attributs['id'],
                'mode_paiement' => $mode,
                'montant' => (string) $montant,
                'date_paiement' => '2026-11-07 12:00:00',
                'statut' => 'actif',
            ]);
        }

        $facture->setRelation('lignes', new Collection($objets));
        $facture->setRelation('avoirs', new Collection());
        $facture->setRelation('paiements', new Collection($paiements));

        return $facture;
    }

    /** Une vente de comptoir fictive, jamais enregistrée. */
    private function venteFictive(): Vente
    {
        $vente = new Vente([
            'id' => '00000000-0000-4000-8000-000000000003',
            'numero' => 'V-2026-00001',
            'point_vente' => 'Bar',
            'client_mention' => 'Client Exemple',
            'montant_total' => '3500.00',
            'mode_paiement' => 'especes',
            'encaisse' => true,
            'statut' => 'validee',
        ]);

        $lignes = [['Bière locale 65 cl', 2, 1000], ['Jus de bissap', 3, 500]];
        $objets = [];
        foreach ($lignes as $i => [$nom, $quantite, $prix]) {
            $objets[] = new LigneVente([
                'id' => sprintf('00000000-0000-4000-8000-0000000003%02d', $i),
                'nom' => $nom,
                'quantite' => $quantite,
                'prix_unitaire' => (string) $prix,
                'montant' => (string) ($quantite * $prix),
            ]);
        }
        $vente->setRelation('lignes', new Collection($objets));

        return $vente;
    }
}
