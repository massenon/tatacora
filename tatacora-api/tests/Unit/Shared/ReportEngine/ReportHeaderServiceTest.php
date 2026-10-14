<?php

declare(strict_types=1);

namespace Tests\Unit\Shared\ReportEngine;

use App\Shared\Parametres\Services\ParametreSystemeService;
use App\Shared\ReportEngine\Services\ReportHeaderService;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * En-tête normalisée — RG-19, `DIRECTIVE_EXPORT_PDF.md`.
 *
 * Unitaire : la composition de l'en-tête ne dépend que de `parametres_systeme`
 * et de l'utilisateur. Aucune base n'est nécessaire, un double en mémoire
 * suffit — ce qui rend praticable la vérification des cas de bord qui comptent
 * vraiment ici : IFU absent, RCCM présent seul, compte sans fiche employé.
 */
final class ReportHeaderServiceTest extends TestCase
{
    /**
     * @param  array<string, string>  $parametres
     */
    private function service(array $parametres = []): ReportHeaderService
    {
        $double = new class ($parametres) extends ParametreSystemeService {
            /**
             * @param  array<string, string>  $valeurs
             */
            public function __construct(private readonly array $valeurs)
            {
            }

            public function get(string $cle, ?string $defaut = null): ?string
            {
                return $this->valeurs[$cle] ?? $defaut;
            }

            public function estRenseigne(string $cle): bool
            {
                return isset($this->valeurs[$cle]);
            }
        };

        return new ReportHeaderService($double);
    }

    // ------------------------------------------------- Données d'entreprise

    /**
     * Valeurs vérifiées contre `parametres.html` du prototype
     * (`DIRECTIVE_EXPORT_PDF.md` §1, tableau « Confirmé »).
     */
    #[Test]
    public function les_coordonnees_confirmees_sont_celles_du_prototype(): void
    {
        $entete = $this->service()->genererEnTete('État des stocks', 'Août 2026', null);

        $this->assertSame('TATACORA AFRIQUE', $entete->raisonSociale);
        $this->assertSame('Quartier Sountichirantikou, Natitingou, Bénin', $entete->adresse);
        $this->assertSame('+229 01 97 35 59 74', $entete->telephone);
        $this->assertSame('nabogounoel@yahoo.fr', $entete->email);
        $this->assertSame('www.tatacora.com', $entete->siteWeb);
        // Directive PO du 02/09/2026 : l'enseigne s'imprime EN MINUSCULES,
        // sous la raison sociale, sur tous les documents.
        $this->assertSame('gîte chez noël', $entete->enseigne);
        $this->assertStringContainsString('gîte chez noël', $entete->sousTitre);
        $this->assertStringNotContainsString('Gîte Chez Noël', $entete->sousTitre);
    }

    /**
     * Directive PO du 02/09/2026 : une raison sociale paramétrée qui porte
     * l'enseigne après un tiret est DÉRIVÉE (séparation sur le tiret), jamais
     * réécrite en dur — ligne 1 la raison, ligne d'enseigne en minuscules.
     */
    #[Test]
    public function une_raison_sociale_a_tiret_derive_la_raison_et_l_enseigne_en_minuscules(): void
    {
        $entete = $this->service([
            ReportHeaderService::CLE_RAISON_SOCIALE => 'TATACORA AFRIQUE — Gîte Chez Noël',
        ])->genererEnTete('État des stocks', 'Août 2026', null);

        $this->assertSame('TATACORA AFRIQUE', $entete->raisonSociale);
        $this->assertSame('gîte chez noël', $entete->enseigne);
    }

    /**
     * Une adresse ou un numéro qui change ne doit pas exiger un redéploiement.
     */
    #[Test]
    public function les_coordonnees_restent_surchargeables_par_parametrage(): void
    {
        $entete = $this->service([
            ReportHeaderService::CLE_TELEPHONE => '+229 00 00 00 00',
            ReportHeaderService::CLE_ADRESSE => 'Nouvelle adresse, Natitingou',
        ])->genererEnTete('État des stocks', 'Août 2026', null);

        $this->assertSame('+229 00 00 00 00', $entete->telephone);
        $this->assertSame('Nouvelle adresse, Natitingou', $entete->adresse);
        // Non surchargée : conserve la valeur confirmée.
        $this->assertSame('TATACORA AFRIQUE', $entete->raisonSociale);
    }

    // --------------------------------------------------- Mentions fiscales

    /**
     * Le point le plus sensible de la directive : « jamais un placeholder du
     * type "Ex. ..." imprimé sur un document réel, ni une ligne vide visible ».
     *
     * L'IFU et le RCCM n'ont **aucune valeur par défaut** — le prototype ne
     * montre qu'un exemple de format, jamais une vraie valeur.
     */
    #[Test]
    public function une_mention_fiscale_non_renseignee_disparait_du_document(): void
    {
        $entete = $this->service()->genererEnTete('État des stocks', 'Août 2026', null);

        $this->assertNull($entete->ifu);
        $this->assertNull($entete->rccm);
        $this->assertSame([], $entete->mentionsLegales());
    }

    #[Test]
    public function une_mention_fiscale_renseignee_est_imprimee(): void
    {
        $entete = $this->service([
            ReportHeaderService::CLE_IFU => '3202612345678',
            ReportHeaderService::CLE_RCCM => 'RB/NAT/23 B 0456',
        ])->genererEnTete('État des stocks', 'Août 2026', null);

        $this->assertSame(
            ['IFU' => '3202612345678', 'RCCM' => 'RB/NAT/23 B 0456'],
            $entete->mentionsLegales(),
        );
    }

    /**
     * Cas réel du déploiement : l'IFU arrive après inscription DGI (PA-17), le
     * RCCM peut être connu avant. L'en-tête doit rester correcte entre les deux.
     */
    #[Test]
    public function une_seule_mention_renseignee_n_entraine_pas_de_ligne_vide(): void
    {
        $entete = $this->service([
            ReportHeaderService::CLE_RCCM => 'RB/NAT/23 B 0456',
        ])->genererEnTete('État des stocks', 'Août 2026', null);

        $this->assertSame(['RCCM' => 'RB/NAT/23 B 0456'], $entete->mentionsLegales());
        $this->assertArrayNotHasKey('IFU', $entete->mentionsLegales());
    }

    /**
     * Une chaîne vide en base doit se comporter comme une absence, sinon
     * l'en-tête imprimerait « IFU :  ».
     */
    #[Test]
    public function une_mention_vide_en_base_equivaut_a_une_absence(): void
    {
        $entete = $this->service([
            ReportHeaderService::CLE_IFU => '',
        ])->genererEnTete('État des stocks', 'Août 2026', null);

        $this->assertNull($entete->ifu);
    }

    // --------------------------------------------------------------- Auteur

    /**
     * `RESPECT_TABLEAU_RAPPORT.md` §4 : « Auteur affiché = "Administrateur"
     * par défaut au lieu du vrai utilisateur connecté », d'origine « valeur de
     * test laissée en dur ». Sans utilisateur, on le dit — on n'invente pas.
     */
    #[Test]
    public function sans_utilisateur_aucun_nom_n_est_fabrique(): void
    {
        $entete = $this->service()->genererEnTete('État des stocks', 'Août 2026', null);

        $this->assertSame(__('rapports.entete.auteur_inconnu'), $entete->auteur);
        $this->assertStringNotContainsStringIgnoringCase('administrateur', $entete->auteur);
    }

    // ---------------------------------------------------------- Bloc titre

    #[Test]
    public function le_type_de_rapport_et_la_periode_sont_repris_tels_quels(): void
    {
        $entete = $this->service()->genererEnTete(
            'État des stocks — Magasin général',
            'Arrêté au 16/08/2026',
            null,
        );

        // Verbatim de DIRECTIVE_EXPORT_PDF.md §2 : « libellé exact de l'état
        // généré, jamais un intitulé technique de route/contrôleur ».
        $this->assertSame('État des stocks — Magasin général', $entete->typeRapport);
        $this->assertSame('Arrêté au 16/08/2026', $entete->periode);
    }

    /**
     * Grille `RESPECT_TABLEAU_RAPPORT.md` : « Pied de page institutionnel :
     * mention PAEB/FAGUEZ SARL + date/heure d'édition présentes ».
     */
    #[Test]
    public function la_mention_institutionnelle_et_la_date_d_edition_sont_presentes(): void
    {
        $entete = $this->service()->genererEnTete('État des stocks', 'Août 2026', null);

        $this->assertStringContainsString('PAEB', $entete->mentionInstitutionnelle);
        $this->assertStringContainsString('FAGUEZ', $entete->mentionInstitutionnelle);
        $this->assertMatchesRegularExpression('#^\d{2}/\d{2}/\d{4} à \d{2}:\d{2}$#', $entete->dateEdition);
    }
}
