# Contributing

Version 0.1.0 is in development. Author and maintainer organization: **Lofrano Tecnologia**. Contributions should be original and suitable for the MIT license. Do not submit private client code, real HAR exports, personal data, credentials or copied browser implementation code.

## Local checks

Use Dart 3.13–3.x. Preserve the real `pubspec.lock` and prepare the matching package cache before offline work:

```sh
dart pub get --enforce-lockfile
dart analyze --fatal-infos
dart test
dart run bin/har_budget_audit.dart demo
dart run bin/har_budget_audit.dart demo --format json
```

After locked setup:

```sh
dart pub get --offline --enforce-lockfile
dart test
```

Dependency updates must use the real package resolver and retain its generated lockfile; do not invent checksums. Formatting can be checked with `dart format --output=none --set-exit-if-changed lib bin test`; apply formatter changes locally as needed.

## Changes

Keep the public API small and update `docs/contract.md` for behavior/schema changes. Include independently calculated expected results, not only expectations copied from implementation formulas. Preserve unknown-byte semantics, safe-integer bounds, sensitive-data non-disclosure and deterministic ordering. Exercise both renderers and the CLI when decisions change. Add fixtures using reserved synthetic `.test` names only.

Explain rationale, limitations and compatibility impact in a proposed change and add an unreleased changelog entry. CI must retain read-only permissions and timeouts, and must not publish packages, create releases, deploy remotely or contact telemetry/model services. New runtime dependencies require a concrete necessity and security/reproducibility explanation.

Security issues follow [SECURITY.md](SECURITY.md), not a public issue containing an export. General contact uses the [official homepage](https://lofranotecnologia.com.br). No response-time commitment is implied.


## Português

Versão 0.1.0 em desenvolvimento, mantida por Lofrano Tecnologia. Contribua com código original compatível com MIT, exportações sintéticas e nomes `.test`. Não envie HAR real, segredos, dados pessoais, código privado ou implementações copiadas de navegadores.

Use Dart 3.13–3.x. Prepare `dart pub get --enforce-lockfile` com rede apenas para cache inicial; depois execute `dart pub get --offline --enforce-lockfile`, formato, `dart analyze --fatal-infos`, `dart test` e as duas saídas da demo. Não enfraqueça o analyzer, altere hashes manualmente ou elimine regressões para obter resultado verde.

Mudanças no subconjunto, esquema, limites, identidade de origem, percentis ou estados exigem contrato atualizado e expectativas calculadas independentemente. Preserve bytes desconhecidos, soma segura, privacidade e ordem determinística. Mantenha documentação bilíngue e CI somente leitura, sem deploy, publicação ou serviços externos em runtime. Segurança segue SECURITY.md e a via privada quando habilitada.
