@extends('errors.layout', ['code' => 419, 'pictogramme' => 'horloge', 'actions' => ($versConnexion ?? false) ? ['reconnexion', 'recharger'] : ['recharger', 'reconnexion']])
