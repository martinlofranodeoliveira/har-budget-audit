# Contract: development 0.1.0

This is the input/output contract for development version 0.1.0 and report schema v1. It describes an analysis subset, not full HAR validation or browser standards certification.

## Public library

Import `package:har_budget_audit/har_budget_audit.dart`.

- `HarSummary analyzeHarBytes(List<int> bytes)` validates, groups and aggregates.
- `Budget parseBudgetBytes(List<int> bytes)` validates explicit rules.
- `AuditReport audit(HarSummary summary, Budget budget)` evaluates rules.
- Summary: immutable `origins` map, `requests`, `knownResponseBytes`, `unknownResponseEntries`.
- Origin metrics: `requests`, `knownResponseBytes`, `unknownResponseEntries`, nullable `p50Ms` and `p95Ms`, and fresh `toJson()` maps. `OriginMetrics.empty` represents no requests.
- Budget: immutable `origins` map of immutable `OriginBudget` values with nullable `maxRequests`, `maxKnownResponseBytes`, `maxP95Ms`.
- Report: `status`, `exitCode`, fresh `toJson()`, `toJsonString()`, `toMarkdown()`.
- Validation failures: `AuditException.code`, optional zero-based `entryIndex`, sanitized `toString()`.
- `AuditLimits` exposes the documented constants. Internal `src` helpers are not public API.

The library does not read files, write reports, or perform network access. Caller-owned lists must not be modified concurrently during synchronous parsing. Returned JSON containers are fresh and may be modified without changing the report. Summary and budget maps cannot be modified.

## Byte/JSON envelope

Each input is UTF-8, at most **8,388,608 bytes**, inclusive. Invalid UTF-8 is rejected; a leading UTF-8 BOM is accepted by the Dart decoder. There must be exactly one JSON value, followed only by JSON whitespace. Duplicate decoded object keys are rejected everywhere, including ignored metadata; escaped key aliases also count as duplicates.

Maximum container nesting is **64**: root object/array counts as level 1. Scalars do not add container depth. Maximum JSON values is **500,000**, including the root and each array element/object value, excluding object keys. These limits apply to both documents and precede full decoding. They constrain stack use and object amplification even in ignored metadata.

## HAR subset

Root must be an object containing object `log`, string `log.version` exactly `"1.2"`, and array `log.entries` with at most **20,000** entries. Empty exports are valid. Unrelated root/log/entry/request/response metadata is accepted subject to the JSON envelope and never reproduced.

Each entry requires:

| Field | Requirement |
| --- | --- |
| `request.url` | String, at most 8,192 UTF-16 code units, absolute HTTP(S) URL with valid supported authority |
| `time` | JSON number, finite and nonnegative, in elapsed milliseconds |
| `response.bodySize` | JSON integer from -1 through 2^53−1 |
| `response.headersSize` | JSON integer from -1 through 2^53−1 |

Integer fields reject fractional/exponent-form numbers decoded as doubles, including `1.0`, booleans, null, strings and oversized integers. Exactly `-1` means unknown. Other negative sizes fail. Even when one size is unknown, the other must independently validate. Time accepts finite fractional values; timing phases are neither required nor reconstructed. There is no duration sum or page-load estimate.

### URL authority subset

HTTP and HTTPS are case-insensitive. Raw ASCII whitespace/control characters, DEL and backslashes are rejected anywhere in the URL. Authority must contain a host. Supported hosts are ASCII DNS labels (letters/digits with interior hyphens, 1–63 characters per label, total host at most 253 characters including an optional trailing dot), decimal dotted IPv4 with four components in 0–255, and bracketed IPv6 accepted by `Uri.parseIPv6Address`. Single-label hosts and punycode labels are allowed. Numeric four-label hosts must be valid IPv4. Unicode and percent-escaped DNS hosts and IPv6 zone identifiers are not supported. Explicit ports require digits and a value in 0–65535; empty, negative, oversized or nonnumeric ports fail.

After validation, grouping uses **Dart `Uri.origin`**, lowercased. It normalizes scheme/host case and default HTTP/HTTPS ports and excludes userinfo, path, query and fragment. Trailing DNS dots and distinct textual IPv6 spellings are not additionally collapsed beyond Dart's behavior. DNS is never resolved. At most **1,000** observed origins are allowed. URL diagnostics use only the entry index and a static code, never the URL, host or offending value.

### Aggregation

Requests count every entry. An entry contributes `bodySize + headersSize` only if both are nonnegative. If either is -1, it contributes **zero to the known lower bound** and increments `unknown_response_entries` once. This is not an estimate of its actual size. Even a known component is not counted separately. `response.content.size`, compression fields and cache metadata are ignored.

Each integer size and each checked pair, origin and global byte sum must be at most **9,007,199,254,740,991** (2^53−1). Overflow rejects the export, not truncates it. This portable cap avoids precision loss for downstream JSON consumers. There are no unchecked duration sums.

For each observed origin, sort elapsed durations ascending. For percentile p, choose the sample at one-based index `ceil(p * n)`. Implemented p values are 0.50 and 0.95, calculated with integer rank arithmetic. One sample supplies both percentiles. No interpolation. Configured but absent origins have zero requests/bytes/unknown entries and null percentiles.

## Budget schema

Root has exactly `version` (integer 1) and `origins` (nonempty object with at most 1,000 rules). Every origin key must exactly equal its canonical origin string: no URL suffixes, userinfo, uppercase aliases or explicit default ports. Unsupported origins fail. No wildcards, implicit defaults, regular expressions, DNS lookup, or inheritance.

Each rule is a nonempty object containing only any combination of:

- `max_requests`: integer 0 through 2^53−1, count.
- `max_known_response_bytes`: integer 0 through 2^53−1, bytes.
- `max_p95_ms`: finite nonnegative JSON number, milliseconds.

Unknown properties, explicit nulls, empty rules and numeric impostors are configuration errors. Threshold equality passes. Non-present dimensions are not evaluated.

## Decision rules

Rows are the sorted union of observed and configured origins (at most 2,000 rows).

| Condition | Dimension status | Reason |
| --- | --- | --- |
| Observed origin without rule | indeterminate | `no_budget_rule` on `coverage` |
| Request count or observed p95 above limit | exceeded | `limit_exceeded` |
| Known bytes above byte limit, regardless of unknown entries | exceeded | `limit_exceeded` |
| Known bytes at/below byte limit and unknown entries exist | indeterminate | `unknown_response_bytes` |
| Value at/below limit, without uncertainty in that dimension | passed | `within_limit` |
| p95 rule for an absent origin | passed | `no_requests` |

The absent-origin duration rule is vacuously satisfied, not a fabricated zero latency: p50/p95 remain null. Unknown sizes do not affect duration/request checks. Per-origin and overall precedence is **exceeded > indeterminate > passed**. With no observed requests, all configured rules pass. A report cannot silently pass because an observed origin lacks coverage.

## CLI

```
dart run bin/har_budget_audit.dart check <file.har> --budget <budget.json> [--format json|markdown]
dart run bin/har_budget_audit.dart demo [--format json|markdown]
dart run bin/har_budget_audit.dart --help
```

No stdin, directory recursion, traffic capture, implicit file discovery, output files or remote URLs. `check` defaults to JSON; `demo` defaults to Markdown. Options may appear in either order after the HAR filename; duplicates, missing values and unknown arguments fail. `--help` is accepted alone. Files must be regular files; symlinks to regular files are followed. Paths are used only to open explicitly requested files and are not output. Reads are bounded to the byte limit plus one sentinel byte even if a file grows after the initial stat. Stable local paths are required: stat/open is not a defense against hostile concurrent replacement with special files.

Reports go to stdout with a trailing newline. The CLI handles asynchronous sink errors and awaits flush before reporting success. Output I/O failure returns 2 and may leave partial output; diagnostics are best effort if stderr fails. Failures go to stderr as `audit: CODE` or `audit: entry[INDEX]: CODE`. Failed checks do not produce a report when input validation fails. Exit codes: 0 passed/help/successful demo, 1 exceeded, 3 indeterminate, 2 malformed/configuration/I/O/internal error. The demo deliberately includes exceeded and indeterminate scenarios but returns 0 only after verifying all expected states.

### Report schema v1

Top-level fields:

- `schema_version`: integer 1.
- `status`: `passed`, `exceeded` or `indeterminate`.
- `units`: `requests: count`, `response_bytes: bytes`, `latency: ms`.
- `totals`: `requests`, `known_response_bytes`, `unknown_response_entries`, `observed_origins`.
- `origins`: lexically sorted rows with `origin`, `status`, `metrics`, `thresholds`, `checks`.

Metrics: `requests`, `known_response_bytes`, `unknown_response_entries`, `p50_ms`, `p95_ms`. Thresholds contain only configured dimension names. Checks have `dimension`, `threshold` (null for coverage), `status`, `reason`; their order is requests, bytes, p95, or the sole coverage check. The JSON serializer uses two-space indentation and fixed insertion order. Identical semantic numeric inputs and records yield deterministic ordering; numeric lexical spellings are not preserved. Markdown uses the same internal rows and checks, explicitly labels units, and renders null as `n/a`.

No filenames, complete source URLs, request/response headers, cookies, bodies, queries, fragments or content are emitted. Normalized origin names are intentionally emitted and can themselves disclose infrastructure. This is minimization, not anonymization.

### Diagnostic codes

Envelope: `input_too_large`, `invalid_utf8`, `invalid_json`, `duplicate_json_key`, `json_depth_limit`, `json_values_limit`.

HAR: `invalid_har`, `invalid_har_version`, `invalid_entries`, `entries_limit`, `invalid_entry`, `invalid_url`, `url_too_long`, `invalid_time`, `invalid_response`, `invalid_response_size`, `origins_limit`, `integer_overflow`. Entry-related field errors and overflow include the entry index. Aggregate resource-limit errors need not include an index.

Budgets: `invalid_budget`, `invalid_budget_rules`, `budget_origins_limit`, `invalid_budget_origin`, `noncanonical_budget_origin`, `invalid_budget_rule`, `invalid_budget_threshold`.

CLI/demo: `invalid_arguments`, `input_not_regular_file`, `io_error`, `internal_error`, `demo_expectation_failed`. Raw platform/parser exception messages are never output. When multiple faults exist, the first diagnostic follows validation order; callers should not rely on one fault masking another.


## Português — contrato 0.1.0 em desenvolvimento

A biblioteca exporta `analyzeHarBytes`, `parseBudgetBytes` e `audit`. Os resultados e mapas de orçamento são imutáveis; `toJson()` devolve estruturas novas. Erros de validação usam `AuditException`, código estático e índice opcional de entrada, sem valores ou caminhos. A biblioteca não faz E/S ou rede.

Cada documento UTF-8 aceita até 8 MiB, 64 níveis de contêineres e 500.000 valores JSON, incluindo metadados ignorados. Chaves duplicadas decodificadas são rejeitadas antes de construir a árvore completa. HAR exige `log.version="1.2"`, até 20.000 entradas e os campos `request.url`, `time`, `response.bodySize` e `response.headersSize`. Demais campos não são reproduzidos.

URLs HTTP(S) têm até 8.192 unidades UTF-16 e autoridades validadas no recorte explícito acima. O agrupamento usa [Dart Uri.origin](https://api.dart.dev/dart-core/Uri/origin.html), com esquema/host minúsculos e porta normalizada, sem credenciais, caminho, consulta ou fragmento. Até 1.000 origens observadas. DNS não é consultado.

`time` deve ser número finito não negativo em ms. p50/p95 usam nearest rank: índice inteiro de base 1 igual a `ceil(p*n)`, sem interpolação. Origens configuradas sem requisições têm percentis nulos. Os tempos não são somados nem tratados como duração de carregamento da página.

Tamanhos são inteiros de -1 a 2^53−1. Apenas -1 significa desconhecido; se qualquer componente for desconhecido, a entrada incrementa a contagem de desconhecidos e não contribui para o limite inferior de bytes conhecidos. Não se usa `content.size` como substituto. Soma de par, origem e total é verificada contra 2^53−1; overflow rejeita a entrada.

Orçamento JSON estrito: versão inteira 1 e `origins` não vazio, com até 1.000 chaves já canônicas. Cada regra contém ao menos um dos campos `max_requests`, `max_known_response_bytes`, `max_p95_ms`. Contagem/bytes são inteiros não negativos seguros; p95 é número finito não negativo. Chaves desconhecidas, aliases, nulos e impostores numéricos são rejeitados. Igualdade passa.

Precedência: `exceeded` > `indeterminate` > `passed`. Bytes conhecidos acima do limite falham mesmo com desconhecidos; em caso contrário, desconhecidos tornam apenas o orçamento de bytes indeterminado. Origem observada sem regra é indeterminada. Regra de duração sem requisições passa com motivo `no_requests` e percentil nulo.

A CLI lê somente os arquivos nomeados, sem captura de tráfego ou requisições HTTP. Aceita arquivo regular local estável; segue symlinks para regulares, mas não protege contra substituição concorrente hostil. Escrita/flush são verificados. Saídas: 0 passou/ajuda/demo verificada; 1 excedeu; 3 indeterminado; 2 entrada, configuração, E/S ou erro interno. Falha de saída pode deixar relatório parcial.

JSON e Markdown usam os mesmos dados/decisões, com unidades, limites, contagens e códigos de motivo; nunca notas arbitrárias. O JSON de esquema 1 está detalhado acima. Somente origens normalizadas e agregados são expostos; nomes de origem também podem ser sensíveis. Este é um recorte de análise, sem alegação de conformidade HAR completa ou certificação de desempenho.
