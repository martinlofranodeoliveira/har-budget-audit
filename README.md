# HAR Budget Audit

**Development version 0.1.0.** Original Dart source by **Lofrano Tecnologia**. Repository: `martinlofranodeoliveira/har-budget-audit`.

[Português](README.pt-BR.md)

A local library and CLI that group a documented HAR 1.2 analysis subset by HTTP(S) origin, count requests and known response bytes, calculate nearest-rank latency percentiles, and check explicit budgets. No traffic capture, performance score, telemetry, model, API, or runtime package dependency.

## Setup and checks

Use Dart **3.13 or later, below Dart 4**. The included development lockfile requires this SDK range; local checks use SDK 3.13.7. CI uses the mutable `dart:stable` tag.

Run the CLI from a source checkout:

```sh
git clone https://github.com/martinlofranodeoliveira/har-budget-audit.git
cd har-budget-audit
dart --disable-analytics
dart pub get --enforce-lockfile
dart run bin/har_budget_audit.dart --help
```

SDK installation and filling the package cache are preparation steps that may access the package registry. There are no runtime package dependencies. The real `pubspec.lock` records `test: 1.25.15` and the resolver's transitive versions/content hashes; keep it unchanged during normal checks. After preparing that cache, run offline:

```sh
dart pub get --offline --enforce-lockfile
dart format --output=none --set-exit-if-changed lib bin test
dart analyze --fatal-infos
dart test
dart run bin/har_budget_audit.dart demo
dart run bin/har_budget_audit.dart demo --format json
```

The offline demo constructs data in memory and makes no HTTP requests. A prepared Docker run can set `PUB_CACHE=/work/build/.pub-cache`; cache/build output is excluded from source control. Container tags are mutable, so record the concrete SDK/image when comparing results.

## Check an explicit export

```sh
dart run bin/har_budget_audit.dart check examples/site.har --budget examples/budgets.json --format json
dart run bin/har_budget_audit.dart check examples/site.har --budget examples/budgets.json --format markdown
```

The fixture passes at exact threshold equality. Its JSON report contains these values:

```json
{
  "status": "passed",
  "totals": {
    "requests": 3,
    "known_response_bytes": 420,
    "unknown_response_entries": 0,
    "observed_origins": 2
  }
}
```

This is a selected-fields example, not the complete report schema. Full output also includes units, per-origin counts, p50/p95, thresholds, checks and reason codes. For `https://app.example.test`, two durations 10 and 30 ms yield p50 10 and p95 30 ms, with 350 known bytes. The single CDN request has both percentiles 50 ms and 70 known bytes.

```sh
dart run bin/har_budget_audit.dart check examples/exceeded.har --budget examples/budgets.json --format markdown
dart run bin/har_budget_audit.dart check examples/unknown.har --budget examples/budgets.json --format json
```

These intentionally return 1 and 3 respectively. Exit codes: **0 passed, 1 exceeded, 3 indeterminate, 2 malformed/configuration/I/O/internal error**. `--help` exits 0. Errors go to stderr without source values or paths; reports go to stdout.

Budget example:

```json
{
  "version": 1,
  "origins": {
    "https://example.test": {
      "max_requests": 20,
      "max_known_response_bytes": 100000,
      "max_p95_ms": 250.5
    }
  }
}
```

Keys must already equal the canonical `Uri.origin`: no trailing slash, default port, credentials, path, query, or fragment. At least one threshold per rule is required. Unconfigured observed origins are indeterminate, not silently ignored.

## Library

```dart
import 'dart:io';
import 'package:har_budget_audit/har_budget_audit.dart';

void main() {
  final summary = analyzeHarBytes(File('examples/site.har').readAsBytesSync());
  final budget = parseBudgetBytes(File('examples/budgets.json').readAsBytesSync());
  final result = audit(summary, budget);
  print(result.status);
  print(result.toMarkdown());
}
```

Library decoding rejects over-limit byte lists, but callers should also bound their own file reads. The CLI does so both before reading and during streaming. Library failures are `AuditException` with a stable code and optional zero-based entry index.

## Offline demo

The demo constructs three synthetic exports and one budget in memory. It checks expected outcomes before exiting 0; an expectation mismatch exits 2. It reads/writes no persistent files and makes no external calls. Human-readable output includes:

```text
Scenario: passing; expected: passed.
Status: **passed**
Scenario: violation; expected: exceeded.
Status: **exceeded**
Scenario: unknown_transfer; expected: indeterminate.
Status: **indeterminate**
Demo expectations: passed.
```

These lines are excerpts from the full Markdown reports. JSON mode returns `demo_status: "passed"` and three cases, each with its expected state and full report.

## Interpretation, safety and limits

- `entry.time` is elapsed request milliseconds, not a reconstructed timing waterfall. Summed request durations are **not page-load duration**; this tool deliberately does not sum them.
- Nearest rank is `ceil(p * n)` using 1-based sorted samples. No interpolation, fabricated grades, or statistical confidence claim.
- Known bytes require both `bodySize` and `headersSize` to be nonnegative integers. Either `-1` makes the whole entry's transfer unknown. `content.size` is never a transfer fallback.
- A byte threshold with unknown entries is indeterminate unless known bytes already exceed it. Other conclusive violations still make the report exceeded. Duration-only rules are unaffected by unknown sizes.
- HAR can contain credentials, cookies, tokens, bodies and personal data. Keep it local and access-controlled. Reports omit all source metadata except normalized origins and derived metrics, but origins themselves may be sensitive. Do not commit real exports.
- Files are limited to 8 MiB each, 20,000 entries, 1,000 observed origins, 1,000 budget rules, 8,192 URL UTF-16 code units, 64 JSON container levels, and 500,000 JSON values. Integer byte/count thresholds and byte totals are capped at 2^53−1, with checked sums.
- Only a required analysis subset is validated. Synthetic fixtures are intentionally not complete browser exports. HAR is an interoperable browser-export format; the abandoned historical W3C draft is not a conformance authority. This tool does not certify web performance or browser standards compliance.

See [contract](docs/contract.md), [design](docs/design.md), [contributing](CONTRIBUTING.md), and [security reporting](SECURITY.md). General contact: [official homepage](https://lofranotecnologia.com.br). MIT, copyright 2026 Lofrano Tecnologia.
