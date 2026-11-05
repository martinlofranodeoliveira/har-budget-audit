# Changelog

## 0.1.0 — Unreleased

Initial development version.

- Add original Dart library and CLI for a documented HAR 1.2 analysis subset.
- Group HTTP(S) requests with Dart `Uri.origin`, excluding source URL components and metadata.
- Report request counts, checked known response bytes, unknown-entry counts and nearest-rank p50/p95.
- Evaluate explicit per-origin budgets with exceeded/indeterminate/passed precedence and documented exit codes.
- Add bounded UTF-8/JSON parsing, authority validation, sanitized diagnostics and deterministic JSON/Markdown output.
- Add three synthetic HAR fixtures, adversarial/regression tests and an in-memory offline demo.
- Add English/Portuguese usage documentation, contract, design, security guidance and read-only CI.
- Include the real resolved development lockfile, strict analyzer configuration and source-checkout CLI setup.


### Corrections

- Sanitize oversized numeric IPv4 components as indexed URL validation errors.
- Await stdout/stderr flush and handle asynchronous sink errors without raw exceptions.
- Bound growing-file reads to the byte ceiling plus one sentinel byte.
- Align the SDK requirement with the real locked dependency graph and enforce it in CI.

## Português — desenvolvimento 0.1.0

- Biblioteca/CLI Dart original para análise local de um recorte HAR 1.2.
- Origens sanitizadas, bytes conhecidos/desconhecidos, p50/p95 nearest rank e três estados de orçamento.
- Limites de JSON e inteiros seguros, diagnósticos privados e relatórios JSON/Markdown determinísticos.
- Lockfile real, analyzer estrito, testes adversariais e demo sintética sem rede.
- Correção de IPv4 numérico excessivo, falhas assíncronas de E/S e requisitos reais de SDK.
