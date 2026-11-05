import 'dart:io';
import 'dart:typed_data';

import 'package:har_budget_audit/har_budget_audit.dart';

import 'src/demo.dart';

const _usage =
    'Usage: dart run bin/har_budget_audit.dart '
    'check <file.har> --budget <budget.json> [--format json|markdown]\n'
    '       dart run bin/har_budget_audit.dart demo [--format json|markdown]';

Future<List<int>> _readBounded(String path) async {
  final file = File(path);
  final stat = await file.stat();
  if (stat.type != FileSystemEntityType.file) {
    throw const AuditException('input_not_regular_file');
  }
  if (stat.size > AuditLimits.inputBytes) {
    throw const AuditException('input_too_large');
  }
  final builder = BytesBuilder(copy: false);
  var count = 0;
  await for (final chunk in file.openRead(0, AuditLimits.inputBytes + 1)) {
    if (chunk.length > AuditLimits.inputBytes - count) {
      throw const AuditException('input_too_large');
    }
    count += chunk.length;
    builder.add(chunk);
  }
  return builder.takeBytes();
}

class _Arguments {
  final bool demo;
  final String? harPath;
  final String? budgetPath;
  final String format;

  const _Arguments(this.demo, this.harPath, this.budgetPath, this.format);
}

_Arguments _parse(List<String> args) {
  if (args.isEmpty) throw const AuditException('invalid_arguments');
  final demo = args[0] == 'demo';
  if (!demo && args[0] != 'check') {
    throw const AuditException('invalid_arguments');
  }
  var offset = 1;
  String? path;
  if (!demo) {
    if (args.length < 2 || args[1].startsWith('--') || args[1].isEmpty) {
      throw const AuditException('invalid_arguments');
    }
    path = args[1];
    offset++;
  }
  String? budget;
  String? format;
  while (offset < args.length) {
    if (offset + 1 >= args.length) {
      throw const AuditException('invalid_arguments');
    }
    final flag = args[offset];
    final value = args[offset + 1];
    if (flag == '--budget' &&
        !demo &&
        budget == null &&
        value.isNotEmpty &&
        !value.startsWith('--')) {
      budget = value;
    } else if (flag == '--format' &&
        format == null &&
        (value == 'json' || value == 'markdown')) {
      format = value;
    } else {
      throw const AuditException('invalid_arguments');
    }
    offset += 2;
  }
  if (!demo && budget == null) throw const AuditException('invalid_arguments');
  return _Arguments(demo, path, budget, format ?? (demo ? 'markdown' : 'json'));
}

Future<void> _diagnose(String message) async {
  try {
    stderr.writeln(message);
    await stderr.flush();
  } catch (_) {
    // Diagnostics are best effort if stderr itself has failed.
  }
}

Future<void> main(List<String> args) async {
  // Sink errors also complete done; handle that future before queued writes.
  stdout.done.ignore();
  stderr.done.ignore();
  try {
    if (args.length == 1 && args[0] == '--help') {
      stdout.writeln(_usage);
      await stdout.flush();
      return;
    }
    final options = _parse(args);
    if (options.demo) {
      stdout.writeln(demoOutput(options.format));
      await stdout.flush();
      return;
    }
    final summary = analyzeHarBytes(await _readBounded(options.harPath!));
    final budget = parseBudgetBytes(await _readBounded(options.budgetPath!));
    final report = audit(summary, budget);
    stdout.writeln(
      options.format == 'json' ? report.toJsonString() : report.toMarkdown(),
    );
    await stdout.flush();
    exitCode = report.exitCode;
  } on AuditException catch (error) {
    exitCode = 2;
    await _diagnose(
      error.code == 'invalid_arguments' ? '$error\n$_usage' : '$error',
    );
  } on FileSystemException {
    exitCode = 2;
    await _diagnose('audit: io_error');
  } on IOException {
    exitCode = 2;
    await _diagnose('audit: io_error');
  } catch (_) {
    // No exception text or stack trace: those may contain source data or paths.
    exitCode = 2;
    await _diagnose('audit: internal_error');
  }
}
