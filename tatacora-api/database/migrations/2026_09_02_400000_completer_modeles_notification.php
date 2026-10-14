<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * M12 — ce qui manquait a `modeles_notification` pour porter le maitre.
 *
 * Maitre : `prototype_v2/pages/m12-notifications-hub.html` et son moteur
 * `prototype_v2/assets/js/notifications-engine.js`.
 *
 * Trois manques, mesures contre le maitre le 31/08/2026 :
 *
 * 1. `objet` — le maitre le demande explicitement « (e-mail et push) »
 *    (`m12-notifications-hub.js`, modale d'edition). Un modele e-mail sans
 *    objet ne peut pas etre relu tel que le client le recevra, ce qui est la
 *    seule utilite du module tant qu'aucun canal n'est branche.
 *
 * 2. `actif` — le maitre bascule un modele entre « actif » et « desactive »,
 *    et compte les actifs en indicateur. Sans colonne, l'ecran ne pourrait
 *    ni le rendre ni l'ecrire : il inventerait un etat.
 *
 * 3. Le CANAL. `notifications-engine.js` l.52-61 pose QUATRE canaux
 *    (`whatsapp`, `email`, `android`, `sms`) ; l'enum n'en portait que deux.
 *    Restreindre les modeles a deux canaux aurait produit une limitation que
 *    rien a l'ecran n'explique — l'utilisateur aurait cherche pourquoi
 *    « Android (push) » figure au tableau des canaux mais pas au formulaire.
 *
 * ## Ce que cette migration N'AJOUTE PAS, et pourquoi
 *
 * Aucune colonne d'envoi, d'accuse de reception ou de compteur de diffusion.
 * `notifications_envoyees` existe deja et reste EN LECTURE : l'API WhatsApp
 * Business n'est pas contractee, aucun relais SMTP n'est configure, et RG-20
 * (diffusion automatique) est la seule des vingt regles de gestion non
 * implementee. Une colonne « derniere_diffusion » que rien n'ecrirait serait
 * PA-126 : une colonne rendue comme un fait que personne n'alimente.
 *
 * ## Le `down()` peut REFUSER, et c'est voulu
 *
 * Retrecir l'enum detruirait les modeles poses sur les deux canaux retires :
 * la migration inverse les supprime explicitement. La cle etrangere
 * `restrictOnDelete` de `notifications_envoyees` fait echouer l'operation si
 * un envoi les reference — un rollback qui casse bruyamment vaut mieux qu'un
 * rollback qui perd une trace d'envoi en silence.
 */
return new class () extends Migration {
    /** Les deux canaux que l'enum d'origine ne pouvait pas representer. */
    private const CANAUX_AJOUTES = ['android', 'sms'];

    public function up(): void
    {
        Schema::table('modeles_notification', function (Blueprint $table): void {
            // Nullable : un modele WhatsApp n'a pas d'objet, et lui en imposer
            // un ferait saisir une ligne qui ne sera jamais rendue.
            $table->string('objet')->nullable()->after('canal');

            // Un modele nait ACTIF : c'est l'etat que le maitre coche par
            // defaut a la creation (`m12-notifications-hub.js`, case a cocher
            // « Modele actif »).
            $table->boolean('actif')->default(true)->after('contenu_template');
        });

        DB::statement(
            "ALTER TABLE modeles_notification MODIFY canal ENUM('whatsapp','email','android','sms') NOT NULL",
        );
    }

    public function down(): void
    {
        // L'ordre compte : les lignes que le schema d'arrivee ne sait pas
        // representer partent AVANT le retrecissement, sans quoi MySQL rendrait
        // une erreur de troncature que personne ne saurait rattacher a une
        // donnee precise.
        DB::table('modeles_notification')->whereIn('canal', self::CANAUX_AJOUTES)->delete();

        DB::statement(
            "ALTER TABLE modeles_notification MODIFY canal ENUM('whatsapp','email') NOT NULL",
        );

        Schema::table('modeles_notification', function (Blueprint $table): void {
            $table->dropColumn(['objet', 'actif']);
        });
    }
};
