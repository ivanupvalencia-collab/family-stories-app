import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// C-6: las consultas de lista de lib/ deben ir acotadas (.range/.limit) o ser
// de una sola fila (.single/.maybeSingle). Sin tope, cualquier tabla que
// crezca se descarga entera en cada carga de la app.
void main() {
  Directory repoRoot() {
    var dir = Directory.current;
    while (!File('${dir.path}/pubspec.yaml').existsSync()) {
      final parent = dir.parent;
      if (parent.path == dir.path) {
        fail('No se encontró la raíz del repositorio.');
      }
      dir = parent;
    }
    return dir;
  }

  // La cadena de una consulta va de .from(...) hasta el ';' que la cierra.
  // Una cadena sin .select() es una escritura que no devuelve filas.
  bool chainIsBounded(String chain) {
    if (!chain.contains('.select(')) return true;
    return chain.contains('.range(') ||
        chain.contains('.limit(') ||
        chain.contains('.single()') ||
        chain.contains('.maybeSingle()');
  }

  List<({File file, int line, String table, String chain})> fromChains(
    Directory lib,
  ) {
    final fromPattern = RegExp(r"\.from\(\s*'([a-z_]+)'\s*\)");
    final chains = <({File file, int line, String table, String chain})>[];
    final files = lib
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final file in files) {
      final source = file.readAsStringSync();
      for (final match in fromPattern.allMatches(source)) {
        final rest = source.substring(match.end);
        final end = rest.indexOf(';');
        final chain = end == -1 ? rest : rest.substring(0, end);
        final line = source.substring(0, match.start).split('\n').length;
        chains.add((
          file: file,
          line: line,
          table: match.group(1)!,
          chain: chain,
        ));
      }
    }
    return chains;
  }

  test('toda consulta de lista en lib/ está acotada (C-6)', () {
    final root = repoRoot();
    final chains = fromChains(Directory('${root.path}/lib'));
    expect(chains, isNotEmpty, reason: 'El gate perdió su alcance (C-6).');

    final violations = <String>[
      for (final entry in chains)
        if (!chainIsBounded(entry.chain))
          '${entry.file.path}:${entry.line} (${entry.table})',
    ];
    expect(
      violations,
      isEmpty,
      reason:
          'Consultas de lista sin tope en lib/: $violations — añade '
          '.range(0, 499) o una guarda de una sola fila (C-6).',
    );

    // Política del hallazgo: las lecturas ordenadas (las 4 de C-6) llevan el
    // tope de 500 filas; cambiar el cap obliga a actualizar este gate.
    final cap = RegExp(r'\.range\(\s*0\s*,\s*499\s*\)');
    final ordered = [
      for (final entry in chains)
        if (entry.chain.contains('.order(') &&
            !entry.chain.contains('.single()') &&
            !entry.chain.contains('.maybeSingle()'))
          entry,
    ];
    expect(
      ordered,
      isNotEmpty,
      reason: 'Ninguna lectura ordenada en lib/: el gate perdió su alcance (C-6).',
    );
    for (final entry in ordered) {
      expect(
        cap.hasMatch(entry.chain),
        isTrue,
        reason:
            '${entry.file.path}:${entry.line} (${entry.table}) es una lista '
            'ordenada sin .range(0, 499) (C-6).',
      );
    }
  });

  test('el clasificador detecta lecturas sin tope (negativo C-6)', () {
    expect(
      chainIsBounded(".from('stories').select('id').eq('a', b).order('x');"),
      isFalse,
      reason: 'Una lectura ordenada sin tope debe fallar el gate.',
    );
    expect(
      chainIsBounded(".from('stories').select('id').range(0, 499);"),
      isTrue,
    );
    expect(chainIsBounded(".from('t').select('id').single();"), isTrue);
    expect(chainIsBounded(".from('t').select('id').maybeSingle();"), isTrue);
    expect(chainIsBounded(".from('t').insert({'a': 1});"), isTrue);
  });
}
