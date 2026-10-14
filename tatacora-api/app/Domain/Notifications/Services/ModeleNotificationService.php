<?php

declare(strict_types=1);

namespace App\Domain\Notifications\Services;

use App\Domain\Notifications\Models\ModeleNotification;
use App\Domain\Notifications\Models\NotificationEnvoyee;
use Illuminate\Database\Eloquent\Collection as EloquentCollection;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Le referentiel des modeles de message — UNIQUE point d'ecriture de M12.
 *
 * Maitre : `prototype_v2/pages/m12-notifications-hub.html` et son moteur
 * `prototype_v2/assets/js/notifications-engine.js` (registres, vocabulaire).
 *
 * ## Ce service ENVOIE-t-il ? Non, et il n'expose meme pas le geste
 *
 * Le moteur du maitre porte `envoyer()`, `marquerTraite()`, `abandonner()` et
 * une file d'attente. Aucun des quatre n'est porte, et l'omission est
 * declaree a l'ecran plutot que rendue en bouton inerte
 * (`docs/DIRECTIVE_CONFORMITE_100.md` Article 3.3 refuse l'entree inerte ;
 * il ne demande pas d'inventer la fonction).
 *
 * **La raison, datee et verifiee le 31/08/2026** : l'API WhatsApp Business
 * n'est pas contractee, aucun relais SMTP n'est configure, et l'application
 * Flutter qui porterait le canal Android n'enregistre aucun appareil. RG-20
 * (diffusion automatique) est la seule des vingt regles de gestion du projet
 * qui reste non implementee, et c'est une dependance externe — un contrat et
 * des decisions, pas un developpement.
 *
 * Le maitre ecrit lui-meme la consequence en tete de son moteur : « un
 * message marque "envoye" alors que rien n'est parti est pire que pas de
 * module du tout : le Gerant croit son client prevenu, et il ne l'est pas ».
 * C'est la meme famille que PA-59/60/61 — un indicateur qui affirme un etat
 * que rien n'a verifie.
 *
 * ⚠ Le jour ou un canal sera branche, l'ecriture de `notifications_envoyees`
 * appartiendra au client du canal, pas a ce service : ce qui doit apparaitre
 * au journal, c'est ce qu'un transport a REELLEMENT accepte, jamais ce qu'un
 * ecran a demande.
 *
 * ## Ce qu'il ecrit, et pourquoi c'est reel
 *
 * Le referentiel : creer, modifier, activer ou desactiver un modele. Ces
 * gestes ne promettent aucun envoi — ils preparent le texte exact que le
 * client recevra, ce qui est precisement la valeur du module tant que les
 * canaux ne sont pas contractes : le Product Owner relit et corrige les
 * formulations pendant que c'est encore gratuit.
 *
 * ## Deux registres FERMES gardent les deux cles
 *
 * `evenement` doit appartenir a `RegistreDeclencheurs`, `canal` a
 * `RegistreCanaux`. Un code inconnu est refuse, jamais cree : un modele pose
 * sur un evenement que rien ne declenche serait un modele que l'ecran
 * afficherait comme actif et que personne n'emprunterait — meme forme que la
 * cle `mecef_actif` qu'un ecran confirmerait et que rien ne lit (PA-124).
 *
 * @see RG-20 Diffusion automatique des notifications (non implementee)
 * @see EF-M12-01 Modeles de notification parametrables par evenement et canal
 */
class ModeleNotificationService
{
    /**
     * Cree un modele. L'evenement et le canal viennent des registres fermes.
     *
     * @param  array{evenement?: string, canal?: string, objet?: string|null, contenu_template?: string, actif?: bool}  $donnees
     *
     * @throws RuntimeException evenement ou canal hors registre, contenu vide,
     *                          ou modele deja pose sur ce couple
     */
    public function creerModele(array $donnees): ModeleNotification
    {
        $evenement = (string) ($donnees['evenement'] ?? '');
        $canal = (string) ($donnees['canal'] ?? '');

        $this->exigerRegistres($evenement, $canal);
        $contenu = $this->exigerContenu($donnees['contenu_template'] ?? null);

        return DB::transaction(function () use ($evenement, $canal, $contenu, $donnees): ModeleNotification {
            // L'unicite est aussi posee au schema (`unique(evenement, canal)`).
            // Ce controle-ci sert a NOMMER le refus : une violation de
            // contrainte remonterait un message SQL que personne ne rattache
            // au couple concerne.
            $existe = ModeleNotification::query()
                ->where('evenement', $evenement)
                ->where('canal', $canal)
                ->lockForUpdate()
                ->exists();

            if ($existe) {
                throw new RuntimeException(__('notifications_pwa.modele_deja_pose'));
            }

            return ModeleNotification::create([
                'evenement' => $evenement,
                'canal' => $canal,
                'objet' => $this->objetOuNull($donnees['objet'] ?? null),
                'contenu_template' => $contenu,
                'actif' => (bool) ($donnees['actif'] ?? true),
            ]);
        });
    }

    /**
     * Modifie un modele existant.
     *
     * L'EVENEMENT n'est pas modifiable, et le maitre fait le meme choix (son
     * champ « Declencheur » est `disabled` a l'edition) : changer l'evenement
     * d'un modele reviendrait a en creer un autre, en perdant la trace du
     * premier. Le canal, lui, se change — un texte relu pour WhatsApp reste
     * valable en e-mail.
     *
     * @param  array{canal?: string, objet?: string|null, contenu_template?: string, actif?: bool}  $donnees
     *
     * @throws RuntimeException canal hors registre, contenu vide, ou couple deja pris
     */
    public function modifierModele(ModeleNotification $modele, array $donnees): ModeleNotification
    {
        $canal = (string) ($donnees['canal'] ?? $modele->canal);

        if (! RegistreCanaux::existe($canal)) {
            throw new RuntimeException(__('notifications_pwa.canal_inconnu', ['code' => $canal]));
        }

        $contenu = $this->exigerContenu($donnees['contenu_template'] ?? $modele->contenu_template);

        return DB::transaction(function () use ($modele, $canal, $contenu, $donnees): ModeleNotification {
            $collision = ModeleNotification::query()
                ->where('evenement', $modele->evenement)
                ->where('canal', $canal)
                ->whereKeyNot($modele->getKey())
                ->lockForUpdate()
                ->exists();

            if ($collision) {
                throw new RuntimeException(__('notifications_pwa.modele_deja_pose'));
            }

            $modele->update([
                'canal' => $canal,
                'objet' => $this->objetOuNull($donnees['objet'] ?? $modele->objet),
                'contenu_template' => $contenu,
                'actif' => (bool) ($donnees['actif'] ?? $modele->actif),
            ]);

            return $modele->refresh();
        });
    }

    /**
     * Active ou desactive un modele — le geste « Activer / Desactiver » du
     * maitre.
     *
     * Un modele desactive n'est PAS supprime : `BasePolicy::delete()` rend
     * `false` pour les vingt policies du depot, et la correction passe par le
     * geste metier. Ici, le geste metier est la desactivation.
     */
    public function basculerActivationModele(ModeleNotification $modele): ModeleNotification
    {
        return DB::transaction(function () use ($modele): ModeleNotification {
            $modele->update(['actif' => ! $modele->actif]);

            return $modele->refresh();
        });
    }

    // ------------------------------------------------------------- lectures

    /**
     * Les modeles, tries par evenement puis canal.
     *
     * @return EloquentCollection<int, ModeleNotification>
     */
    public function modeles(): EloquentCollection
    {
        return ModeleNotification::query()
            ->orderBy('evenement')
            ->orderBy('canal')
            ->get();
    }

    /**
     * Les modeles rattaches a un declencheur : total et actifs.
     *
     * @param  EloquentCollection<int, ModeleNotification>  $modeles
     * @return array{total: int, actifs: int}
     */
    public function comptageParDeclencheur(EloquentCollection $modeles, string $evenement): array
    {
        $duDeclencheur = $modeles->where('evenement', $evenement);

        return [
            'total' => $duDeclencheur->count(),
            'actifs' => $duDeclencheur->where('actif', true)->count(),
        ];
    }

    /**
     * Le journal des envois — REEL, et vide tant que rien ne part.
     *
     * Lire la table plutot que rendre une liste vide en dur : le jour ou un
     * canal ecrira, le journal se remplira sans qu'on touche a cet ecran. Un
     * `return []` code en dur resterait vide ce jour-la, et personne ne
     * saurait pourquoi.
     *
     * @return EloquentCollection<int, NotificationEnvoyee>
     */
    public function journal(): EloquentCollection
    {
        return NotificationEnvoyee::query()
            ->with('modele')
            ->orderByDesc('date_envoi')
            ->get();
    }

    /**
     * Le nombre de messages REELLEMENT partis — compte en base, jamais ecrit.
     *
     * Il vaut zero aujourd'hui parce que rien n'ecrit `notifications_envoyees`,
     * pas parce qu'une constante le dit. La nuance est celle de PA-61 : un
     * chiffre pose a la main resterait juste jusqu'au jour ou il compterait.
     */
    public function nombreEnvoisReels(): int
    {
        return NotificationEnvoyee::query()->count();
    }

    /**
     * Substitue les variables d'un modele — maitre : `notifications-engine.js`
     * `composer()`, l.373-392.
     *
     * Refuse TOUJOURS un message dont une variable resterait litterale : un
     * client ne doit jamais lire « vous devez {montant} FCFA ». C'est un
     * refus de COMPOSITION, jamais un envoi tronque — rien n'est mis en file
     * dans ce cas (voir `DetectionNotificationsService`).
     *
     * @param  array<string, string>  $variables
     * @return array{objet: string|null, contenu: string, longueur: int}
     *
     * @throws RuntimeException si une variable reste non resolue
     */
    public function composerMessage(ModeleNotification $modele, array $variables): array
    {
        $substituer = function (?string $texte) use ($variables): string {
            return (string) preg_replace_callback(
                '/\{([a-z_]+)\}/',
                static function (array $trouve) use ($variables): string {
                    $cle = $trouve[1];

                    return array_key_exists($cle, $variables) && $variables[$cle] !== ''
                        ? $variables[$cle]
                        : $trouve[0];
                },
                (string) $texte,
            );
        };

        $contenu = $substituer($modele->contenu_template);
        $objet = $modele->objet === null ? null : $substituer($modele->objet);

        $texteAVerifier = $contenu . ' ' . (string) $objet;
        if (preg_match_all('/\{([a-z_]+)\}/', $texteAVerifier, $restantes) > 0) {
            throw new RuntimeException(__('notifications_pwa.variables_non_resolues', [
                'variables' => implode(', ', array_map(
                    static fn (string $v): string => '{' . $v . '}',
                    array_values(array_unique($restantes[1])),
                )),
            ]));
        }

        return ['objet' => $objet, 'contenu' => $contenu, 'longueur' => mb_strlen($contenu)];
    }

    /**
     * Les variables `{nom}` du modele qui n'appartiennent pas a son
     * declencheur — elles resteraient litterales dans le message.
     *
     * Le maitre le signale en rouge sous l'apercu : « le message serait
     * refuse ». Ici, aucun message ne part, mais l'anomalie doit se voir a la
     * relecture — c'est le seul moment ou elle est corrigeable gratuitement.
     *
     * @return list<string>
     */
    public function variablesInconnues(ModeleNotification $modele): array
    {
        $declencheur = RegistreDeclencheurs::declencheur($modele->evenement);

        if ($declencheur === null) {
            return $modele->variablesCitees();
        }

        return array_values(array_diff($modele->variablesCitees(), $declencheur['variables']));
    }

    // ------------------------------------------------------------- internes

    /**
     * @throws RuntimeException
     */
    private function exigerRegistres(string $evenement, string $canal): void
    {
        if (! RegistreDeclencheurs::existe($evenement)) {
            throw new RuntimeException(__('notifications_pwa.declencheur_inconnu', ['code' => $evenement]));
        }

        if (! RegistreCanaux::existe($canal)) {
            throw new RuntimeException(__('notifications_pwa.canal_inconnu', ['code' => $canal]));
        }
    }

    /**
     * @throws RuntimeException
     */
    private function exigerContenu(?string $contenu): string
    {
        $propre = trim((string) $contenu);

        if ($propre === '') {
            throw new RuntimeException(__('notifications_pwa.contenu_vide'));
        }

        return $propre;
    }

    private function objetOuNull(?string $objet): ?string
    {
        $propre = trim((string) $objet);

        return $propre === '' ? null : $propre;
    }
}
