<?php

declare(strict_types=1);

namespace App\Domain\Rh\Services;

use App\Domain\Rh\Models\Employe;
use App\Domain\Rh\Models\Service as ServiceRh;
use App\Shared\Mail\Support\AdresseEmailFacultative;
use Illuminate\Database\Eloquent\Collection as EloquentCollection;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Le dossier du personnel — UNIQUE point d'écriture sur `employes`.
 *
 * Maître : `prototype_v2/pages/m13-paie.html`, onglet « Personnel », et sa
 * modale « Nouvel employé » (`m13-paie.js`).
 *
 * ## Le service est une VRAIE clé étrangère, jamais un texte libre
 *
 * Le prototype d'origine posait « Employé » en texte libre à QUATRE endroits
 * (paie, présences, congés, départs). Chaque occurrence produirait des
 * enregistrements orphelins invisibles dans le dossier du bon salarié. Ici,
 * `service_id` pointe `services` et l'écran offre la liste réelle.
 *
 * ## Le matricule est ALLOUÉ, jamais dérivé d'une position dans une liste
 *
 * `EMP-AAAA-NNNNN`, alloué sous verrou pessimiste dans la transaction qui
 * crée l'employé. Un matricule calculé à l'affichage (« le 3ᵉ de la liste »)
 * changerait dès qu'un employé est ajouté avant lui — et c'est ce numéro que
 * le bulletin de paie imprime.
 *
 * ⚠ `SequenceDocumentService` fait exactement cela pour les ventes et les
 * dépenses, mais il lit la colonne `numero` en dur ; `employes` porte
 * `matricule`. L'allocation est donc reprise ici, sous la même garantie
 * (`lockForUpdate` dans la transaction appelante). C'est une duplication
 * mesurée, pas ignorée : le jour où ce service transverse acceptera un nom de
 * colonne, cette méthode disparaît.
 *
 * ## Aucune suppression
 *
 * `BasePolicy::delete()` rend `false` pour les vingt policies du dépôt, et
 * RG-15 l'exige : un bulletin doit continuer de porter le nom de qui l'a
 * touché. Un départ se marque par `statut = 'parti'` — le dossier reste.
 *
 * @see EF-M13-01 Dossier du personnel
 * @see RG-15 Journalisation des opérations
 */
class EmployeService
{
    private const PREFIXE_MATRICULE = 'EMP';

    private const LARGEUR_MATRICULE = 5;

    /**
     * Crée un salarié et lui alloue son matricule, dans la même transaction.
     *
     * @param  array{nom?: string, prenom?: string, email?: string|null, poste?: string, service_id?: string, date_embauche?: string, numero_cnss?: string|null, type_contrat?: string|null, date_fin_contrat?: string|null, salaire_base?: string, statut?: string}  $donnees
     *
     * @throws RuntimeException service inconnu, type de contrat ou statut hors registre
     */
    public function creerEmploye(array $donnees, ?string $id = null): Employe
    {
        $this->exigerRegistres($donnees);

        return DB::transaction(function () use ($donnees, $id): Employe {
            return Employe::create([
                // Audit de couverture (18/10/2026) : l'UUID du poste.
                ...($id !== null ? ['id' => $id] : []),
                'matricule' => $this->matriculeSuivant(),
                'nom' => trim((string) ($donnees['nom'] ?? '')),
                'prenom' => trim((string) ($donnees['prenom'] ?? '')),
                'email' => AdresseEmailFacultative::normaliser($donnees['email'] ?? null),
                'poste' => trim((string) ($donnees['poste'] ?? '')),
                'service_id' => (string) ($donnees['service_id'] ?? ''),
                'date_embauche' => (string) ($donnees['date_embauche'] ?? now()->toDateString()),
                'numero_cnss' => $this->videEnNull($donnees['numero_cnss'] ?? null),
                'type_contrat' => $this->videEnNull($donnees['type_contrat'] ?? null),
                'date_fin_contrat' => $this->videEnNull($donnees['date_fin_contrat'] ?? null),
                'salaire_base' => (string) ($donnees['salaire_base'] ?? '0'),
                'statut' => (string) ($donnees['statut'] ?? 'actif'),
            ]);
        });
    }

    /**
     * Met à jour un salarié. Le matricule n'est jamais réattribué : il est
     * imprimé sur les bulletins déjà remis.
     *
     * @param  array{nom?: string, prenom?: string, email?: string|null, poste?: string, service_id?: string, date_embauche?: string, numero_cnss?: string|null, type_contrat?: string|null, date_fin_contrat?: string|null, salaire_base?: string, statut?: string}  $donnees
     *
     * @throws RuntimeException service inconnu, type de contrat ou statut hors registre
     */
    public function mettreAJourEmploye(Employe $employe, array $donnees): Employe
    {
        $this->exigerRegistres($donnees);

        return DB::transaction(function () use ($employe, $donnees): Employe {
            $employe->update([
                'nom' => trim((string) ($donnees['nom'] ?? $employe->nom)),
                'prenom' => trim((string) ($donnees['prenom'] ?? $employe->prenom)),
                // Absent de la charge (un poste d'avant la v45) = inchangé ; présent et vide = effacé.
                'email' => array_key_exists('email', $donnees)
                    ? AdresseEmailFacultative::normaliser($donnees['email'])
                    : $employe->email,
                'poste' => trim((string) ($donnees['poste'] ?? $employe->poste)),
                'service_id' => (string) ($donnees['service_id'] ?? $employe->service_id),
                'date_embauche' => (string) ($donnees['date_embauche']
                    ?? $employe->date_embauche->toDateString()),
                'numero_cnss' => $this->videEnNull($donnees['numero_cnss'] ?? null),
                'type_contrat' => $this->videEnNull($donnees['type_contrat'] ?? null),
                'date_fin_contrat' => $this->videEnNull($donnees['date_fin_contrat'] ?? null),
                'salaire_base' => (string) ($donnees['salaire_base'] ?? $employe->salaire_base),
                'statut' => (string) ($donnees['statut'] ?? $employe->statut),
            ]);

            return $employe->refresh();
        });
    }

    /**
     * Archive un employe — « supprimer = archiver » (directive PO du
     * 02/09/2026, meme famille que `hors_service` sur le parc M1/M8).
     *
     * Le statut passe a `parti` : JAMAIS une suppression — RG-15, ses
     * bulletins continuent de porter son nom — et la generation de bulletins
     * l'ignore desormais (`estActif()`). Reversible par la fiche (champ
     * statut), et la transition est consignee au journal (trait Auditable).
     *
     * Aucun verrou d'engagement, et c'est un choix documente : rien ne
     * reference l'activite FUTURE d'un employe — bulletins et plannings
     * passes restent lisibles sous leurs ecrans. Le piege reel (partir
     * avant le bulletin du mois : la generation le sauterait sans un mot)
     * est porte a l'ECRAN, dans la modale d'archivage, qui nomme les
     * employes sans bulletin sur la periode courante.
     *
     * @see EF-M13-01 Dossier du personnel
     * @see RG-15 Journalisation des opérations
     *
     * @throws RuntimeException employe deja parti
     */
    public function archiver(Employe $employe): void
    {
        if ($employe->statut === 'parti') {
            throw new RuntimeException(__('rh.archivage.deja_parti', [
                'nom' => $employe->nomComplet(),
            ]));
        }

        $employe->update(['statut' => 'parti']);
    }

    // ------------------------------------------------------------- lectures

    /**
     * Les salariés qui portent déjà les mêmes nom et prénom — RG-18 appliquée
     * au personnel : AVERTIR, jamais bloquer.
     *
     * Deux homonymes réels existent dans un village ; refuser la saisie
     * obligerait à contourner le contrôle par une faute d'orthographe
     * volontaire, et le doublon serait alors indétectable.
     *
     * @return EloquentCollection<int, Employe>
     */
    public function homonymes(string $nom, string $prenom, ?string $exclureId = null): EloquentCollection
    {
        $nom = trim($nom);
        $prenom = trim($prenom);

        if ($nom === '') {
            return new EloquentCollection();
        }

        return Employe::query()
            ->where('nom', $nom)
            ->when($prenom !== '', fn ($q) => $q->where('prenom', $prenom))
            ->when($exclureId !== null, fn ($q) => $q->whereKeyNot($exclureId))
            ->orderBy('matricule')
            ->get();
    }

    /**
     * @return EloquentCollection<int, ServiceRh>
     */
    public function services(): EloquentCollection
    {
        return ServiceRh::query()->orderBy('libelle')->get();
    }

    // ------------------------------------------------------------- internes

    /**
     * Alloue le prochain matricule de l'année.
     *
     * À appeler DANS une transaction : hors transaction, le verrou est
     * relâché aussitôt et deux créations concurrentes rendent le même numéro.
     */
    private function matriculeSuivant(): string
    {
        $motif = sprintf('%s-%d-', self::PREFIXE_MATRICULE, (int) now()->format('Y'));

        $dernier = DB::table('employes')
            ->where('matricule', 'like', $motif.'%')
            ->orderByDesc('matricule')
            ->lockForUpdate()
            ->value('matricule');

        // Le rang est le SUFFIXE, pas le matricule entier : `EMP-2026-00042`
        // lu comme un entier vaudrait 2026.
        $rang = $dernier === null ? 0 : (int) substr((string) $dernier, strlen($motif));

        return $motif.str_pad((string) ($rang + 1), self::LARGEUR_MATRICULE, '0', STR_PAD_LEFT);
    }

    /**
     * @param  array<string, mixed>  $donnees
     *
     * @throws RuntimeException
     */
    private function exigerRegistres(array $donnees): void
    {
        $serviceId = $donnees['service_id'] ?? null;

        if (is_string($serviceId) && $serviceId !== ''
            && ! ServiceRh::query()->whereKey($serviceId)->exists()) {
            throw new RuntimeException(__('rh_pwa.service_inconnu'));
        }

        $contrat = $donnees['type_contrat'] ?? null;

        if (is_string($contrat) && $contrat !== ''
            && ! in_array($contrat, Employe::TYPES_CONTRAT, true)) {
            throw new RuntimeException(__('rh_pwa.contrat_inconnu', ['code' => $contrat]));
        }

        $statut = $donnees['statut'] ?? null;

        if (is_string($statut) && $statut !== '' && ! in_array($statut, Employe::STATUTS, true)) {
            throw new RuntimeException(__('rh_pwa.statut_inconnu', ['code' => $statut]));
        }
    }

    private function videEnNull(?string $valeur): ?string
    {
        $propre = trim((string) $valeur);

        return $propre === '' ? null : $propre;
    }
}
