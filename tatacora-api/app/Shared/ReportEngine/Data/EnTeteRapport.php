<?php

declare(strict_types=1);

namespace App\Shared\ReportEngine\Data;

/**
 * En-tête normalisée d'un état édité — RG-19, EF-M14-01.
 *
 * Objet immuable produit par le **seul** `ReportHeaderService`. Le rendre
 * immuable n'est pas décoratif : `DIRECTIVE_EXPORT_PDF.md` §3 et
 * `RESPECT_TABLEAU_RAPPORT.md` §4 identifient la régénération locale d'en-tête
 * comme la non-conformité la plus fréquente. Un objet qu'aucun contrôleur ne
 * peut modifier après coup rend la dérive visible à la construction, pas à la
 * relecture du PDF.
 *
 * @see RG-19 Entête normalisée obligatoire sur tout état édité
 * @see EF-M14-01
 */
final readonly class EnTeteRapport
{
    public function __construct(
        public ?string $logo,
        public string $raisonSociale,
        public string $sousTitre,
        public string $adresse,
        public string $telephone,
        public string $email,
        public string $siteWeb,
        /** Affiché seulement s'il est réellement renseigné — jamais un exemple de format. */
        public ?string $ifu,
        public ?string $rccm,
        public string $typeRapport,
        public string $periode,
        public string $auteur,
        public string $dateEdition,
        /**
         * Identité et fiscalité paramétrées (02/09/2026, onglets « Identité &
         * Légal » et « Communication » de Paramètres) — mêmes règles que
         * IFU/RCCM : affichés seulement si réellement renseignés, jamais un
         * repli inventé. `regimeFiscal` arrive déjà en LIBELLÉ du maître
         * (« Réel normal »), résolu par l'unique carte de
         * `DefinitionParametre::libelleDuChoix()`.
         */
        public ?string $promoteur = null,
        public ?string $whatsapp = null,
        public ?string $regimeFiscal = null,
        /**
         * L'enseigne, EN MINUSCULES (« gîte chez noël ») — directive PO du
         * 02/09/2026, dérivée par le seul `ReportHeaderService::identite()`
         * (séparation sur le tiret de la raison sociale paramétrée). Imprimée
         * sous la raison sociale sur TOUS les documents.
         */
        public string $enseigne = '',
    ) {
    }

    /**
     * Les mentions légales à imprimer, dans l'ordre, en n'incluant que ce qui
     * est renseigné.
     *
     * `DIRECTIVE_EXPORT_PDF.md` §1 : « jamais un placeholder du type "Ex. ..."
     * imprimé sur un document réel, ni une ligne vide visible ». Un IFU absent
     * doit donc faire **disparaître** la ligne, pas afficher « IFU : — ».
     *
     * @return array<string, string>
     */
    public function mentionsLegales(): array
    {
        return array_filter([
            'IFU' => $this->ifu,
            'RCCM' => $this->rccm,
            // Le régime fiscal paramétré (onglet « Identité & Légal », select
            // fermé aux trois valeurs du maître) : une mention d'identité
            // fiscale, imprimée avec IFU et RCCM quand elle est renseignée.
            'Régime fiscal' => $this->regimeFiscal,
        ], static fn (?string $valeur): bool => filled($valeur));
    }

    /**
     * L'IDENTITÉ imprimée UNE SEULE FOIS en tête de tout document (décision du PO du 10/11/2026 :
     * « trop de tautologie, trop de répétition ») — les cinq lignes, dans l'ordre, jamais autre
     * chose : « TATACORA AFRIQUE Gîte Chez Noël » / adresse / « Tél. … - courriel » / site /
     * « IFU : … - RCCM : … ». Plus de ligne d'enseigne répétée, de « Système de gestion Intégré… »,
     * de promoteur ni de WhatsApp dans l'en-tête. Une valeur absente fait disparaître sa ligne
     * (jamais un exemple de format). Le poste Flutter écrit la MÊME liste (`lignesA4`).
     *
     * @return list<string>
     */
    public function lignesIdentite(): array
    {
        $enseigne = mb_convert_case($this->enseigne, MB_CASE_TITLE, 'UTF-8');
        $contact = array_filter([
            filled($this->telephone) ? 'Tél. '.trim($this->telephone) : null,
            filled($this->email) ? trim($this->email) : null,
        ]);
        $mentions = [];
        foreach ($this->mentionsLegales() as $intitule => $valeur) {
            $mentions[] = $intitule.' : '.$valeur;
        }

        return array_values(array_filter([
            // Une raison sociale qui PORTE déjà l'enseigne (« TATACORA AFRIQUE Gîte Chez Noël ») ne la reçoit pas deux fois.
            $enseigne === '' || mb_stripos($this->raisonSociale, $enseigne, 0, 'UTF-8') !== false
                ? trim($this->raisonSociale)
                : trim($this->raisonSociale.' '.$enseigne),
            trim($this->adresse),
            $contact === [] ? null : implode(' - ', $contact),
            filled($this->siteWeb) ? rtrim(trim($this->siteWeb), '/') : null,
            $mentions === [] ? null : implode(' - ', $mentions),
        ], static fn (?string $l): bool => filled($l)));
    }

    /**
     * @return array<string, mixed>
     */
    public function toArray(): array
    {
        return [
            'logo' => $this->logo,
            'raison_sociale' => $this->raisonSociale,
            'sous_titre' => $this->sousTitre,
            'adresse' => $this->adresse,
            'telephone' => $this->telephone,
            'email' => $this->email,
            'site_web' => $this->siteWeb,
            'ifu' => $this->ifu,
            'rccm' => $this->rccm,
            'type_rapport' => $this->typeRapport,
            'periode' => $this->periode,
            'auteur' => $this->auteur,
            'date_edition' => $this->dateEdition,
            'promoteur' => $this->promoteur,
            'whatsapp' => $this->whatsapp,
            'regime_fiscal' => $this->regimeFiscal,
            'enseigne' => $this->enseigne,
        ];
    }
}
