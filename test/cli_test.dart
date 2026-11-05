import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

Future<ProcessResult> cli(List<String> args) => Process.run(
  Platform.resolvedExecutable,
  ['bin/har_budget_audit.dart', ...args],
).timeout(const Duration(seconds: 30));

void main() {
  test('CLI checks return 0/1/3 with parseable deterministic JSON', () async {
    for (final scenario in {
      'site': (0, 'passed'),
      'exceeded': (1, 'exceeded'),
      'unknown': (3, 'indeterminate'),
    }.entries) {
      final args = [
        'check',
        'examples/${scenario.key}.har',
        '--budget',
        'examples/budgets.json',
        '--format',
        'json',
      ];
      final result = await cli(args);
      expect(result.exitCode, scenario.value.$1);
      expect(result.stderr, '');
      final data = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      expect(data['status'], scenario.value.$2);
      expect(result.stdout, isNot(contains('sentinel')));
      expect((await cli(args)).stdout, result.stdout);
    }
  });

  test('Markdown uses same deliberate unknown outcome', () async {
    final result = await cli([
      'check',
      'examples/unknown.har',
      '--budget',
      'examples/budgets.json',
      '--format',
      'markdown',
    ]);
    expect(result.exitCode, 3);
    expect(result.stdout, contains('Status: **indeterminate**'));
    expect(result.stdout, contains('unknown_response_bytes'));
    expect(result.stdout, contains('| unknown_response_entries | 1 | count |'));
    expect(result.stdout, isNot(contains('sentinel')));
  });

  test(
    'argument and I/O failures return 2 without echoing paths or values',
    () async {
      final badArguments = <List<String>>[
        [],
        ['secret-sentinel'],
        ['check'],
        ['demo', '--budget', 'secret-sentinel'],
        ['demo', '--format', 'secret-sentinel'],
        ['demo', '--format', 'json', '--format', 'json'],
        ['check', 'examples/site.har', '--budget'],
        [
          'check',
          'examples/site.har',
          '--budget',
          'examples/budgets.json',
          'extra',
        ],
      ];
      for (final args in badArguments) {
        final result = await cli(args);
        expect(result.exitCode, 2);
        expect(result.stdout, '');
        expect(result.stderr, contains('invalid_arguments'));
        expect(result.stderr, isNot(contains('sentinel')));
      }
      for (final path in ['missing-secret-sentinel.har', 'examples']) {
        final result = await cli([
          'check',
          path,
          '--budget',
          'examples/budgets.json',
        ]);
        expect(result.exitCode, 2);
        expect(result.stdout, '');
        expect(result.stderr, isNot(contains(path)));
      }
      final missingBudget = await cli([
        'check',
        'examples/site.har',
        '--budget',
        'missing-secret-sentinel.json',
      ]);
      expect(missingBudget.exitCode, 2);
      expect(missingBudget.stderr, isNot(contains('sentinel')));
    },
  );

  test(
    'demo asserts all three outcomes, exits zero, and needs no fixture cwd',
    () async {
      final result = await cli(['demo', '--format', 'json']);
      expect(result.exitCode, 0);
      expect(result.stderr, '');
      final data = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      expect(data['demo_status'], 'passed');
      final cases = data['cases'] as List<dynamic>;
      expect(cases.length, 3);
      expect(
        cases.map((Object? item) {
          final row = item as Map<String, dynamic>;
          final report = row['report'] as Map<String, dynamic>;
          expect(report['status'], row['expected']);
          return report['status'];
        }).toList(),
        ['passed', 'exceeded', 'indeterminate'],
      );
      final second = await cli(['demo', '--format', 'json']);
      expect(second.stdout, result.stdout);
      final human = await cli(['demo']);
      expect(human.exitCode, 0);
      expect(human.stdout, contains('Demo expectations: passed.'));
      // Absolute script and package configuration keep the demo independent of cwd.
      final elsewhere = await Process.run(Platform.resolvedExecutable, [
        '--packages=${File('.dart_tool/package_config.json').absolute.path}',
        File('bin/har_budget_audit.dart').absolute.path,
        'demo',
        '--format',
        'json',
      ], workingDirectory: Directory.systemTemp.path);
      expect(elsewhere.exitCode, 0);
      expect(elsewhere.stdout, result.stdout);
    },
  );

  test(
    'stdout and stderr device failures return 2 without raw exceptions',
    () async {
      final executable = Platform.resolvedExecutable;
      final script = File('bin/har_budget_audit.dart').absolute.path;
      for (final command in [
        r'exec "$1" "$2" --help > /dev/full',
        r'exec "$1" "$2" invalid-sentinel 2> /dev/full',
        r'exec "$1" "$2" --help > /dev/full 2> /dev/full',
      ]) {
        // Pass paths as positional arguments, never as shell source.
        final result = await Process.run('bash', [
          '-c',
          command,
          'io-test',
          executable,
          script,
        ]).timeout(const Duration(seconds: 30));
        expect(result.exitCode, 2);
        expect(result.stdout, '');
        expect(result.stderr, isNot(contains('Unhandled exception')));
        expect(result.stderr, isNot(contains('FileSystemException')));
        expect(result.stderr, isNot(contains('sentinel')));
      }
    },
    skip: !Platform.isLinux,
  );

  test(
    'known FIFO input is rejected before opening and diagnostics stay private',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'har-audit-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/private-sentinel.har';
      final made = await Process.run('mkfifo', [path]);
      expect(made.exitCode, 0);
      final result = await cli([
        'check',
        path,
        '--budget',
        'examples/budgets.json',
      ]);
      expect(result.exitCode, 2);
      expect(result.stdout, '');
      expect(result.stderr, 'audit: input_not_regular_file\n');
      expect(result.stderr, isNot(contains('sentinel')));
    },
    skip: !Platform.isLinux,
  );
}
