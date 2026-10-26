import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Un VRAI petit serveur SMTP, sur une socket locale (127.0.0.1, port libre) :
/// il parle le protocole (220, EHLO, AUTH PLAIN/LOGIN, MAIL, RCPT, DATA, QUIT)
/// et note ce qu'il reçoit. Aucun octet ne sort de la machine : c'est le
/// moyen d'éprouver `mailer` ET la boîte d'envoi de bout en bout, là où un
/// transport factice ne prouve que la plomberie.
final class ServeurSmtpEssai {
  ServeurSmtpEssai._(
    this._serveur, {
    required this.utilisateur,
    required this.motDePasse,
  });

  final ServerSocket _serveur;
  final String utilisateur;
  final String motDePasse;

  /// Les courriels ACCEPTÉS (réponse 250 après le point final), en texte brut.
  final List<String> recus = [];

  /// Les destinataires (RCPT TO) de chaque courriel accepté.
  final List<List<String>> destinataires = [];

  /// Les authentifications refusées (535).
  int authentificationsRefusees = 0;

  /// Un code SMTP à servir à la place du 250 final de DATA (ex. 554), ou
  /// `null` : le courriel est accepté.
  String? refusDeData;

  final List<Socket> _clients = [];

  int get port => _serveur.port;

  /// Le corps TEXTE du courriel [i], décodé (`mailer` l'envoie en base64).
  String corpsTexte(int i) {
    final brut = recus[i];
    final coupe = brut.indexOf('\n\n');
    final corps = coupe < 0 ? '' : brut.substring(coupe + 2);
    return utf8.decode(base64.decode(corps.replaceAll('\n', '').trim()));
  }

  /// L'objet du courriel [i], décodé (`=?utf-8?B?...?=`).
  String sujet(int i) {
    final ligne = recus[i]
        .split('\n')
        .firstWhere((l) => l.toLowerCase().startsWith('subject:'));
    final valeur = ligne.substring('subject:'.length).trim();
    final m = RegExp(
      r'^=\?utf-8\?B\?(.*)\?=$',
      caseSensitive: false,
    ).firstMatch(valeur);
    return m == null ? valeur : utf8.decode(base64.decode(m.group(1)!));
  }

  static Future<ServeurSmtpEssai> demarrer({
    String utilisateur = 'contact@essai.local',
    String motDePasse = 'S3cret-Gite!',
    int port = 0,
  }) async {
    final serveur = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    final s = ServeurSmtpEssai._(
      serveur,
      utilisateur: utilisateur,
      motDePasse: motDePasse,
    );
    serveur.listen(s._servir);
    return s;
  }

  Future<void> arreter() async {
    await _serveur.close();
    for (final c in _clients) {
      c.destroy();
    }
  }

  void _servir(Socket socket) {
    _clients.add(socket);
    final tampon = StringBuffer();
    var enData = false;
    var etapeAuth =
        0; // 0 : aucune ; 1 : attend le b64 PLAIN ; 2 : login user ; 3 : login mdp
    var courant = <String>[];
    var rcpt = <String>[];
    String? utilisateurLogin;

    void repondre(String ligne) => socket.write('$ligne\r\n');

    bool identifiantsValides(String u, String p) =>
        u == utilisateur && p == motDePasse;

    void traiter(String ligne) {
      if (enData) {
        if (ligne == '.') {
          enData = false;
          if (refusDeData != null) {
            repondre(refusDeData!);
          } else {
            recus.add(courant.join('\n'));
            destinataires.add(List.of(rcpt));
            repondre('250 2.0.0 Ok: queued');
          }
          courant = <String>[];
          rcpt = <String>[];
        } else {
          courant.add(ligne.startsWith('..') ? ligne.substring(1) : ligne);
        }
        return;
      }
      if (etapeAuth == 1) {
        etapeAuth = 0;
        final brut = utf8.decode(base64.decode(ligne));
        final morceaux = brut.split('\u0000');
        final ok =
            morceaux.length == 3 &&
            identifiantsValides(morceaux[1], morceaux[2]);
        if (ok) {
          repondre('235 2.7.0 Authentication successful');
        } else {
          authentificationsRefusees++;
          repondre('535 5.7.8 Authentication credentials invalid');
        }
        return;
      }
      if (etapeAuth == 2) {
        utilisateurLogin = utf8.decode(base64.decode(ligne));
        etapeAuth = 3;
        repondre('334 ${base64.encode(utf8.encode('Password:'))}');
        return;
      }
      if (etapeAuth == 3) {
        etapeAuth = 0;
        final mdp = utf8.decode(base64.decode(ligne));
        if (identifiantsValides(utilisateurLogin ?? '', mdp)) {
          repondre('235 2.7.0 Authentication successful');
        } else {
          authentificationsRefusees++;
          repondre('535 5.7.8 Authentication credentials invalid');
        }
        return;
      }

      final maj = ligne.toUpperCase();
      if (maj.startsWith('EHLO') || maj.startsWith('HELO')) {
        socket.write(
          '250-localhost\r\n250-AUTH PLAIN LOGIN\r\n250 8BITMIME\r\n',
        );
      } else if (maj.startsWith('AUTH PLAIN')) {
        final reste = ligne.substring('AUTH PLAIN'.length).trim();
        if (reste.isEmpty) {
          etapeAuth = 1;
          repondre('334 ');
        } else {
          final morceaux = utf8.decode(base64.decode(reste)).split('\u0000');
          if (morceaux.length == 3 &&
              identifiantsValides(morceaux[1], morceaux[2])) {
            repondre('235 2.7.0 Authentication successful');
          } else {
            authentificationsRefusees++;
            repondre('535 5.7.8 Authentication credentials invalid');
          }
        }
      } else if (maj.startsWith('AUTH LOGIN')) {
        etapeAuth = 2;
        repondre('334 ${base64.encode(utf8.encode('Username:'))}');
      } else if (maj.startsWith('MAIL FROM')) {
        rcpt = <String>[];
        repondre('250 2.1.0 Ok');
      } else if (maj.startsWith('RCPT TO')) {
        rcpt.add(ligne.substring(ligne.indexOf(':') + 1).trim());
        repondre('250 2.1.5 Ok');
      } else if (maj == 'DATA') {
        enData = true;
        repondre('354 End data with <CR><LF>.<CR><LF>');
      } else if (maj == 'QUIT') {
        repondre('221 2.0.0 Bye');
        socket.close();
      } else if (maj == 'RSET' || maj == 'NOOP') {
        repondre('250 2.0.0 Ok');
      } else {
        repondre('502 5.5.2 Command not recognized');
      }
    }

    repondre('220 localhost ESMTP essai');
    socket.listen(
      (octets) {
        tampon.write(latin1.decode(octets));
        var texte = tampon.toString();
        int fin;
        while ((fin = texte.indexOf('\r\n')) >= 0) {
          traiter(texte.substring(0, fin));
          texte = texte.substring(fin + 2);
        }
        tampon
          ..clear()
          ..write(texte);
      },
      onError: (Object _) {},
      cancelOnError: true,
    );
  }
}
