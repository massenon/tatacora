<?php

declare(strict_types=1);

return [

    /*
     * MECeF / DGI Benin — MECEF_INTEGRATION_SPEC.md §7.1.
     * La cle API est un SECRET : elle vit ici (donc en .env), jamais dans
     * parametres_systeme, qui est lisible par tout Administrateur.
     * Le n° contribuable, lui, est un identifiant et vit en base.
     */
    'mecef' => [
        'base_url' => env('MECEF_BASE_URL'),
        'api_key' => env('MECEF_API_KEY'),
        'environnement' => env('MECEF_ENVIRONNEMENT', 'test'),
    ],

    'whatsapp' => [
        'phone_number_id' => env('WHATSAPP_PHONE_NUMBER_ID'),
        'access_token' => env('WHATSAPP_ACCESS_TOKEN'),
        'verify_token' => env('WHATSAPP_VERIFY_TOKEN'),
    ],


    /*
    |--------------------------------------------------------------------------
    | Third Party Services
    |--------------------------------------------------------------------------
    |
    | This file is for storing the credentials for third party services such
    | as Mailgun, Postmark, AWS and more. This file provides the de facto
    | location for this type of information, allowing packages to have
    | a conventional file to locate the various service credentials.
    |
    */

    'postmark' => [
        'key' => env('POSTMARK_API_KEY'),
    ],

    'resend' => [
        'key' => env('RESEND_API_KEY'),
    ],

    'ses' => [
        'key' => env('AWS_ACCESS_KEY_ID'),
        'secret' => env('AWS_SECRET_ACCESS_KEY'),
        'region' => env('AWS_DEFAULT_REGION', 'us-east-1'),
    ],

    'slack' => [
        'notifications' => [
            'bot_user_oauth_token' => env('SLACK_BOT_USER_OAUTH_TOKEN'),
            'channel' => env('SLACK_BOT_USER_DEFAULT_CHANNEL'),
        ],
    ],

];
