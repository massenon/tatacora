import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/fichiers/zip_stocke.dart';

/// Le ZIP « stocké » de l'archive de clôture (26/10/2026), relu par le VRAI
/// `ZipArchive` de PHP — le format qui écrit l'archive du serveur.
void main() {
  test('le CRC-32 est celui de la norme (vecteur « 123456789 »)', () {
    expect(crc32(ascii.encode('123456789')), 0xCBF43926);
    expect(crc32(const []), 0);
    expect(crc32([0]), 0xD202EF8D);
  });

  test('PHP relit le ZIP : mêmes noms, mêmes octets, CRC vérifiés', () async {
    final accentue = [
      0xEF,
      0xBB,
      0xBF,
      ...utf8.encode('Clôture — écritures\n'),
    ];
    final grand = List<int>.generate(70000, (i) => i % 251);
    final octets = zipStocke({
      'ecritures.csv': accentue,
      'etats-cloture.pdf': grand,
      'vide.txt': const [],
    }, le: DateTime(2031, 12, 31, 23, 58, 59));

    final dossier = await Directory.systemTemp.createTemp('zip_stocke_');
    addTearDown(() => dossier.delete(recursive: true));
    final fichier = File('${dossier.path}/archive.zip')
      ..writeAsBytesSync(octets);

    final sortie = await Process.run('php', [
      '-r',
      r'''
$z = new ZipArchive();
if ($z->open($argv[1], ZipArchive::CHECKCONS) !== true) { fwrite(STDERR, "ouverture impossible\n"); exit(2); }
$r = ['n' => $z->numFiles, 'fichiers' => []];
for ($i = 0; $i < $z->numFiles; $i++) {
    $s = $z->statIndex($i);
    $r['fichiers'][$s['name']] = [
        'taille' => $s['size'], 'crc' => $s['crc'],
        'sha1' => sha1((string) $z->getFromIndex($i)),
        'mtime' => date('Y-m-d H:i:s', $s['mtime']),
    ];
}
echo json_encode($r);
''',
      fichier.path,
    ]);
    expect(sortie.exitCode, 0, reason: '${sortie.stderr}');
    final lu = jsonDecode(sortie.stdout as String) as Map<String, dynamic>;
    expect(lu['n'], 3);
    final f = (lu['fichiers'] as Map).cast<String, Map<String, dynamic>>();
    expect(f.keys, ['ecritures.csv', 'etats-cloture.pdf', 'vide.txt']);
    expect(f['etats-cloture.pdf']!['taille'], 70000);
    expect(f['etats-cloture.pdf']!['crc'], crc32(grand));
    expect(f['etats-cloture.pdf']!['sha1'], sha1.convert(grand).toString());
    expect(f['ecritures.csv']!['sha1'], sha1.convert(accentue).toString());
    expect(f['vide.txt']!['taille'], 0);
    // La date DOS tient à deux secondes près.
    expect(f['ecritures.csv']!['mtime'], startsWith('2031-12-31 23:58:5'));
  });
}
