<?php

declare(strict_types=1);

namespace App\Shared\Sync\Services;

use App\Shared\Sync\Models\CorrespondanceSynchronisation;

/**
 * Traduction des identifiants de poste en identifiants serveur — décision du
 * Product Owner du 15/10/2026 (référentiels créés hors connexion, fusion sur
 * clé naturelle).
 *
 * ## Le seul lecteur, le seul auteur
 *
 * Tout gestionnaire qui reçoit un identifiant CITÉ (le `fournisseur_id` d'une
 * commande d'achat, le `client_id` d'une réservation) le passe par
 * `resoudre()` avant d'écrire. Le jour où un document arrive avec l'UUID d'un
 * fournisseur que le serveur a fusionné, la clé étrangère pointe ainsi sur
 * l'élément serveur — et non sur un UUID qui n'existe nulle part, ce qui
 * ferait rejeter le document pour une raison que l'utilisateur ne peut pas
 * comprendre (« fournisseur introuvable », alors qu'il l'a saisi).
 *
 * ## Identité par défaut
 *
 * Sans correspondance, l'identifiant est rendu TEL QUEL : c'est le cas
 * nominal (élément créé côté serveur et téléchargé, ou créé hors connexion et
 * accepté sans fusion — l'UUID du poste EST alors l'UUID serveur).
 */
class ResolveurCorrespondances
{
    /**
     * Correspondances déjà lues, pour ne pas interroger la base à chaque
     * référence d'un lot qui en compte cinquante.
     *
     * Seules les correspondances TROUVÉES sont gardées : une absence peut
     * cesser d'être vraie dans le même lot (la création fusionnée du
     * fournisseur précède sa commande), la mémoriser ferait traduire la
     * commande à tort.
     *
     * @var array<string, string>
     */
    private array $connues = [];

    /**
     * L'identifiant serveur désigné par `$id` — lui-même à défaut de
     * correspondance.
     */
    public function resoudre(string $table, string $id): string
    {
        $cle = $table . '|' . $id;

        if (isset($this->connues[$cle])) {
            return $this->connues[$cle];
        }

        $idServeur = CorrespondanceSynchronisation::query()
            ->where('table_concernee', $table)
            ->where('id_poste', $id)
            ->value('id_serveur');

        if ($idServeur === null) {
            return $id;
        }

        return $this->connues[$cle] = (string) $idServeur;
    }

    /**
     * Retient que l'UUID du poste désigne désormais l'élément serveur.
     *
     * Idempotent : la même fusion rejouée (nouvelle tentative, même UUID de
     * poste) ne crée pas de seconde ligne. Une correspondance existante n'est
     * JAMAIS réorientée — un UUID de poste ne change pas de cible en cours de
     * route, sinon les documents déjà traduits et ceux à venir pointeraient
     * sur deux éléments différents.
     */
    public function enregistrer(string $posteId, string $table, string $idPoste, string $idServeur): void
    {
        if ($idPoste === $idServeur) {
            return;
        }

        CorrespondanceSynchronisation::query()->firstOrCreate(
            ['table_concernee' => $table, 'id_poste' => $idPoste],
            ['poste_id' => $posteId, 'id_serveur' => $idServeur],
        );

        $this->connues[$table . '|' . $idPoste] = $this->resoudre($table, $idPoste);
    }
}
