$ErrorActionPreference = 'Stop'
$s = "$env:TEMP\claude\C--Projects-tatacora-laravel\a7bdfba9-ec6a-45de-97aa-d5d54a0f649f\scratchpad"
$sortie = 'C:\Projects\tatacora_laravel\tatacora_flutter\lib\core\dev\donnees_demonstration.dart'

function Esc($v) {
  if ($null -eq $v) { return '' }
  $t = [string]$v
  $t = $t.Replace('\', '\\')
  $t = $t.Replace("'", "\'")
  $t = $t -replace "[\r\n]+", ' '
  return $t
}
function Nombre($v) {
  if ($null -eq $v -or "$v" -eq '') { return '0' }
  return [string]([double](("$v").Replace(',', '.')))
}
function Entier($v) {
  if ($null -eq $v -or "$v" -eq '') { return '0' }
  return [string][int][math]::Round([double](("$v").Replace(',', '.')))
}

$parc = (Get-Content "$s\demo_parc.json" -Raw -Encoding UTF8 | ConvertFrom-Json).data[0]
$clients = (Get-Content "$s\demo_clients.json" -Raw -Encoding UTF8 | ConvertFrom-Json).data
$boissons = (Get-Content "$s\demo_boissons.json" -Raw -Encoding UTF8 | ConvertFrom-Json).data
$circuits = (Get-Content "$s\demo_circuits.json" -Raw -Encoding UTF8 | ConvertFrom-Json).data
$vehicules = (Get-Content "$s\demo_vehicules.json" -Raw -Encoding UTF8 | ConvertFrom-Json).data
$reservations = (Get-Content "$s\demo_reservations.json" -Raw -Encoding UTF8 | ConvertFrom-Json).data

$l = New-Object System.Collections.Generic.List[string]
$l.Add('// GENERE - ne pas editer a la main.')
$l.Add('//')
$l.Add('// Releve sur la base de demonstration Laravel (DatabaseSeeder), par les')
$l.Add('// routes que le client appelle lui-meme : parc, clients, boissons,')
$l.Add('// circuits, vehicules, reservations. Regenerer par')
$l.Add('// tool/demo/generer_donnees_demo.ps1 apres un migrate:fresh --seed.')
$l.Add('library;')
$l.Add('')
$l.Add("import '../../features/crm/domain/entities/client.dart';")
$l.Add("import '../../features/hebergement/data/dto/reservation_dto.dart';")
$l.Add("import '../../features/hebergement/data/parc_api.dart';")
$l.Add("import '../../features/pos/data/catalogue_api.dart';")
$l.Add('')
$l.Add('/// Le parc : ' + @($parc.categories).Count + ' categories, ' + @($parc.unites).Count + ' unites.')
$l.Add('const parcDemonstration = ParcDistant(')
$l.Add('  categories: [')
foreach ($c in $parc.categories) {
  $l.Add('    CategorieDistante(')
  $l.Add("      id: '" + (Esc $c.id) + "',")
  $l.Add("      libelle: '" + (Esc $c.libelle) + "',")
  $l.Add('      capaciteMax: ' + (Entier $c.capacite_max) + ',')
  $l.Add('      tarifBase: ' + (Nombre $c.tarif_base) + ',')
  $l.Add('    ),')
}
$l.Add('  ],')
$l.Add('  unites: [')
foreach ($u in $parc.unites) {
  $l.Add('    UniteDistante(')
  $l.Add("      id: '" + (Esc $u.id) + "',")
  $l.Add("      categorieId: '" + (Esc $u.categorie_id) + "',")
  $l.Add("      numero: '" + (Esc $u.numero) + "',")
  $l.Add("      statut: '" + (Esc $u.statut) + "',")
  $l.Add('    ),')
}
$l.Add('  ],')
$l.Add(');')
$l.Add('')
$l.Add('/// Les ' + @($clients).Count + ' clients du jeu de demonstration.')
$l.Add('const clientsDemonstration = <Client>[')
foreach ($c in $clients) {
  $prenom = if ([string]::IsNullOrWhiteSpace("$($c.prenom)")) { 'null' } else { "'" + (Esc $c.prenom) + "'" }
  $email = if ([string]::IsNullOrWhiteSpace("$($c.email)")) { 'null' } else { "'" + (Esc $c.email) + "'" }
  $type = if ("$($c.type_client)" -ne '') { "$($c.type_client)" } else { 'particulier' }
  $l.Add('  Client(')
  $l.Add("    id: '" + (Esc $c.id) + "',")
  $l.Add("    nom: '" + (Esc $c.nom) + "',")
  $l.Add('    prenom: ' + $prenom + ',')
  $l.Add("    telephone: '" + (Esc $c.telephone) + "',")
  $l.Add('    email: ' + $email + ',')
  $l.Add('    type: TypeClientReferentiel.' + $type + ',')
  $l.Add('  ),')
}
$l.Add('];')
$l.Add('')
$l.Add('/// Les ' + @($boissons).Count + ' boissons de la carte du bar.')
$l.Add('///')
$l.Add('/// stockDisponible vaut null : le stock est CALCULE par le serveur')
$l.Add('/// (PA-129), et ce flavor n en a aucun. La carte dira non consulte -')
$l.Add('/// un chiffre fige ici serait faux des la premiere vente.')
$l.Add('const boissonsDemonstration = <BoissonDistante>[')
foreach ($b in $boissons) {
  $article = if ([string]::IsNullOrWhiteSpace("$($b.article_id)")) { 'null' } else { "'" + (Esc $b.article_id) + "'" }
  $l.Add('  BoissonDistante(')
  $l.Add("    id: '" + (Esc $b.id) + "',")
  $l.Add('    articleId: ' + $article + ',')
  $l.Add("    libelle: '" + (Esc $b.libelle) + "',")
  $l.Add("    categorie: '" + (Esc $b.categorie) + "',")
  $l.Add('    prixVente: ' + (Nombre $b.prix_vente) + ',')
  $l.Add('    stockDisponible: null,')
  $l.Add('  ),')
}
$l.Add('];')
$l.Add('')
$l.Add('/// Les ' + @($circuits).Count + ' circuits de M9.')
$l.Add('const circuitsDemonstration = <CircuitDistant>[')
foreach ($c in $circuits) {
  $l.Add('  CircuitDistant(')
  $l.Add("    id: '" + (Esc $c.id) + "',")
  $l.Add("    nom: '" + (Esc $c.nom) + "',")
  $l.Add("    theme: '" + (Esc $c.theme) + "',")
  $l.Add("    zone: '" + (Esc $c.zone) + "',")
  $l.Add('    prix: ' + (Nombre $c.prix) + ',')
  $l.Add('    capaciteMax: ' + (Entier $c.capacite_max) + ',')
  $l.Add('  ),')
}
$l.Add('];')
$l.Add('')
$l.Add('/// Les ' + @($vehicules).Count + ' vehicules de M8.')
$l.Add('const vehiculesDemonstration = <VehiculeDistant>[')
foreach ($v in $vehicules) {
  $l.Add('  VehiculeDistant(')
  $l.Add("    id: '" + (Esc $v.id) + "',")
  $l.Add("    categorie: '" + (Esc $v.categorie) + "',")
  $l.Add("    immatriculation: '" + (Esc $v.immatriculation) + "',")
  $l.Add('    tarifJour: ' + (Nombre $v.tarif_jour) + ',')
  $l.Add("    statut: '" + (Esc $v.statut) + "',")
  $l.Add('  ),')
}
$l.Add('];')
$l.Add('')
$l.Add('/// Les ' + @($reservations).Count + ' reservations du jeu de demonstration.')
$l.Add('///')
$l.Add('/// Elles referencent les clients et les unites ci-dessus : un identifiant')
$l.Add('/// invente ferait echouer la cle etrangere, et l ecran serait vide sans')
$l.Add('/// dire pourquoi.')
$l.Add('final reservationsDemonstration = <ReservationDto>[')
foreach ($r in $reservations) {
  $nom = if ($r.client -and "$($r.client.nom_complet)" -ne '') { "'" + (Esc $r.client.nom_complet) + "'" } else { 'null' }
  $a = ("$($r.date_arrivee)".Split('T')[0]).Split('-')
  $d = ("$($r.date_depart)".Split('T')[0]).Split('-')
  $l.Add('  ReservationDto(')
  $l.Add("    id: '" + (Esc $r.id) + "',")
  $l.Add("    clientId: '" + (Esc $r.client_id) + "',")
  $l.Add("    uniteId: '" + (Esc $r.unite_id) + "',")
  $l.Add('    dateArrivee: DateTime.utc(' + [int]$a[0] + ', ' + [int]$a[1] + ', ' + [int]$a[2] + '),')
  $l.Add('    dateDepart: DateTime.utc(' + [int]$d[0] + ', ' + [int]$d[1] + ', ' + [int]$d[2] + '),')
  $l.Add('    nbNuitees: ' + (Entier $r.nb_nuitees) + ',')
  $l.Add("    statut: '" + (Esc $r.statut) + "',")
  $l.Add('    acompte: ' + (Entier $r.acompte) + ',')
  $l.Add('    clientNom: ' + $nom + ',')
  $l.Add('  ),')
}
$l.Add('];')
$l.Add('')

$enc = New-Object System.Text.UTF8Encoding $false
[IO.File]::WriteAllText($sortie, ($l -join "`r`n"), $enc)
'ecrit : ' + $sortie + ' (' + $l.Count + ' lignes)'
