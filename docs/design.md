# Design and independent review notes

## Scope and status

Development version 0.1.0, owned by Lofrano Tecnologia. The implementation, tests and synthetic fixtures are original. The project retains the package resolver-generated lockfile and supports locked offline checks after cache preparation.

The product answers a narrow question: what does this local HAR say about per-origin request counts, known response bytes and observed elapsed-time percentiles, compared with explicit limits? It does not answer whether a site is fast, compliant or production-ready.

## Architecture

1. `json_input.dart` bounds byte count, validates UTF-8, checks nesting/value count and duplicate decoded keys, then delegates JSON syntax/tree construction to `dart:convert`.
2. `url_origin.dart` restricts ambiguous/malformed authorities, then uses Dart's `Uri.origin`. It never resolves DNS or exposes parser exception text.
3. `har.dart` validates the required subset, groups sanitized origins, checks integer sums and sorts per-origin durations.
4. `budget.dart` enforces a strict, typo-resistant versioned schema and canonical origin keys.
5. `report.dart` evaluates dimensions once and renders the same rows in JSON or Markdown.
6. The CLI performs explicit bounded file reads and maps sanitized failures/statuses to exit codes. The independent demo constructs three in-memory scenarios and verifies their expected outcomes.

The exported API has no filesystem dependency; it uses only Dart libraries. Immutable summary/budget objects cannot acquire unchecked data through public aggregate constructors. Reporting returns fresh containers rather than mutable internal storage.

## Deliberate decisions

- **Origin getter, not URL stripping.** Dart documents `Uri.origin` for HTTP(S) with scheme, host and normalized port only. Raw authority validation rejects unsupported host forms rather than allowing URL parser normalization to make a malformed host appear acceptable. Credentials are accepted in HAR URLs but never retained in aggregates.
- **Subset rather than conformance.** Requiring unrelated HAR fields would reject useful synthetic tests and exports without improving these calculations. Ignored metadata still obeys structural safety limits.
- **Unknown is not zero.** Both byte components must be known. The known total is a lower bound. Above-budget known bytes are conclusive even with unknown entries; otherwise a byte threshold is indeterminate. Missing rules are also visible uncertainty.
- **No invented latency score.** Nearest rank is easy to reproduce by hand. Every entry's own elapsed time is used. Concurrent requests, redirects, cache behavior and browser critical paths are not reconstructed.
- **No duration totals.** Summing request durations would be easy to misread as page-load time and could overflow floating-point ranges. It is not part of the output.
- **Portable integer cap.** Checked byte sums are capped at 2^53−1 even on a VM with larger integers. This avoids silently handing downstream JavaScript consumers imprecise JSON totals. Exponent/fraction syntax decoded as double is not accepted for byte/count integers.
- **Strict budget keys.** Canonical keys eliminate alias collisions and prevent paths, queries or credentials in budget keys from being echoed. Empty rules and unknown properties cannot silently disable checks.
- **No environment-driven configuration.** Results depend only on the two explicit documents, not time, locale, network, user settings or environment secrets.

## Bounds and complexity

The CLI checks regular-file metadata and then independently counts stream bytes, so a growing file cannot bypass the 8 MiB cap. The library checks input byte lists before decoding. The JSON guard scans linearly, with bounded container recursion and sets for duplicate keys; `dart:convert` performs final syntax validation. Whole-document parsing is an intentional simplicity tradeoff, not streaming HAR parsing.

HAR aggregation stores at most 20,000 durations and 1,000 origin accumulators. Sorting costs at most O(n log n) across all groups. Budget rows are at most 1,000 and the report union at most 2,000. Input size, value count and depth bound parser memory amplification; these are logical bounds, not a claimed resident-memory benchmark or hard process-memory sandbox. The public library cannot stop a caller allocating an oversized list before invoking it. File access may still block on filesystem faults; there is no wall-clock deadline or OS sandbox.

## Threat model

Treat HAR, budgets and paths as untrusted. Risks include nested JSON stack exhaustion, duplicate-key ambiguity, byte overflows, numeric booleans/fractions, unknown-byte false passes, malformed URL authority normalization, secret-bearing exceptions and Markdown/terminal injection. Static diagnostics, strict ASCII host authority rules, preflight bounds, checked sums and shared report decisions address these risks.

Origin output is an intentional information disclosure to the local report recipient, not anonymization. A hostname may itself contain an identifier. No source metadata is sent anywhere; no crash reports or stack traces are emitted. OS-level process arguments, memory, terminal history, filesystem logs, and the Dart package manager are outside this library's control. CLI paths are explicit and may follow symlinks to regular files; the tool is not a filesystem authorization boundary.

## Regression/adversarial strategy

- Hand-calculated 10/30/50 ms fixtures and 20/21-sample distributions distinguish nearest rank from interpolation and off-by-one variants.
- Equality and known-byte lower-bound cases distinguish passed, exceeded and indeterminate, including precedence across dimensions/origins.
- URL tests cover default/nondefault ports, scheme/host case, IPv6 and secret-bearing credentials/path/query/fragment data.
- Synthetic cookie/header/content/body sentinels must not occur in either renderer or URL failure diagnostics.
- Malformed URL authorities, missing fields, negative/fractional/boolean/oversized sizes and nonfinite duration spellings must fail.
- Every declared resource boundary has inclusive and exclusive tests, including structural limits in ignored JSON data.
- CLI subprocess tests check output parsing, deterministic repeated output, exit codes, missing-file/config errors, strict arguments and a demo run outside the project working directory.

No tests are relaxed to suppress unsupported behavior. Static analysis, formatting, tests and the offline demo are separate checks. Linux tests also exercise special-file rejection and failed stdout/stderr devices.

## Packaging and reproducibility

There are no runtime packages. `package:test` is pinned to 1.25.15 and `pubspec.lock` contains the real resolver-generated transitive graph and hosted content hashes. Its SDK range requires Dart 3.13 or later below 4; local validation uses 3.13.7. CI uses `dart pub get --enforce-lockfile`; offline checks add `--offline` against a prepared cache. SDK/container acquisition and registry cache preparation are distinct from application execution.

CI has read-only permissions and timeouts, runs formatting/analyzer/tests/demo, and performs no deployment or publication. The official `dart:stable` container tag is mutable; validation reports record the concrete image ID. Do not hand-edit dependency checksums or weaken strict analyzer settings to hide a diagnostic.

## Source fact-check references

- Dart `Uri.origin`: https://api.dart.dev/dart-core/Uri/origin.html
- Browser HAR implementation context, not a complete conformance authority: https://github.com/ChromeDevTools/devtools-frontend/blob/main/front_end/models/har/Log.ts
- Browser HAR writing context: https://github.com/ChromeDevTools/devtools-frontend/blob/main/front_end/models/har/Writer.ts
- Official Dart container project: https://github.com/dart-lang/dart-docker

HAR is an interoperable browser-export format. The abandoned historical W3C draft is not treated as a current Recommendation or certification basis. No copied browser implementation is included.


## Português — decisões de projeto

Versão 0.1.0 em desenvolvimento. A implementação usa somente bibliotecas Dart em runtime. O guard JSON limita bytes, profundidade e valores e rejeita chaves duplicadas antes do decoder da plataforma. A validação da autoridade antecede `Uri.origin`; credenciais e demais partes da URL não são retidas. Não há DNS ou cliente HTTP.

O agregador conta requisições, bytes conhecidos e entradas desconhecidas por origem; ordena tempos para nearest-rank p50/p95. Não reconstrói fases ausentes, critical path ou duração de página. O avaliador preserva os três estados e compartilha decisões entre os dois renderizadores. Objetos de domínio imutáveis impedem injeção de agregados não validados por construtores públicos.

Inteiros e somas usam o teto 2^53−1. Erros são códigos estáticos, sem caminhos, conteúdo ou exceções de plataforma. A CLI verifica arquivo regular, limita o stream a bytes restantes/sentinela e trata erros assíncronos de saída, aguardando flush. A checagem stat/open não é sandbox contra filesystem hostil.

Os testes combinam contas manuais, distribuições de 20/21 amostras, limites inclusivos, sentinelas privadas, formatos adversariais e subprocessos da CLI. `pubspec.lock` real fixa a resolução de `test: 1.25.15`; o grafo requer Dart 3.13+. Cache e SDK são preparados antes dos checks sem rede. A CI verifica formato, analyzer estrito, testes e demo, com permissões de leitura e sem publicação.

HAR é formato interoperável de exportação de navegadores. O rascunho histórico abandonado do W3C não é tratado como recomendação atual ou autoridade de conformidade. As fontes primárias acima contextualizam as decisões; nenhum código de navegador foi copiado.
