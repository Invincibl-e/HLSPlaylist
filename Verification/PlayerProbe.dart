// Optional comparison with the sibling player clone; this is not evidence
// for Swift HLSPlaylist. Imports the actual production Dart mapper.
import 'dart:convert';
import 'dart:io';
import '../../player/lib/src/ios/source/playlist.dart';

Future<void> main() async {
  await for (final line in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    final row = jsonDecode(line) as Map<String, dynamic>;
    final result = <String, dynamic>{'name': row['name']};
    try {
      final roles = <String>[];
      result['text'] = rewritePlaylist(
        row['text'] as String,
        Uri.parse('https://fixture.test/path/master.m3u8'),
        (uri, role) {
          roles.add(role.name);
          return Uri.https('routed.test', '/resource', {'url': uri.toString()});
        },
      );
      result['roles'] = roles;
      result['status'] = 'accepted';
    } catch (error) {
      result['status'] = 'rejected';
      result['error'] = error.toString();
    }
    stdout.writeln(jsonEncode(result));
  }
}
