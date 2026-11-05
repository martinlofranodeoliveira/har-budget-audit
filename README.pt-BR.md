# HAR Budget Audit

**Versão 0.1.0 em desenvolvimento.** Código original em Dart de **Lofrano Tecnologia**. Repositório: `martinlofranodeoliveira/har-budget-audit`.

[English](README.md)

Biblioteca e CLI locais para analisar um subconjunto documentado de HAR 1.2 por origem HTTP(S), contar requisições e bytes de resposta conhecidos, calcular percentis por posto mais próximo e comparar orçamentos explícitos. Não captura tráfego, não inventa pontuações e não usa telemetria, modelos, APIs ou pacotes de execução.

## Instalação e verificações

Use Dart **3.13 ou superior, abaixo de Dart 4**. O lockfile de desenvolvimento incluído exige essa faixa; as verificações locais usam SDK 3.13.7. A CI usa a tag mutável `dart:stable`.

Execute a CLI a partir do checkout:

```sh
git clone https://github.com/martinlofranodeoliveira/har-budget-audit.git
cd har-budget-audit
dart --disable-analytics
dart pub get --enforce-lockfile
dart run bin/har_budget_audit.dart --help
```

Instalar o SDK e preencher o cache de pacotes são etapas de preparação que podem acessar o registro. Não há pacotes de runtime. O `pubspec.lock` real contém `test: 1.25.15` e as versões/hashes transitivos gerados pelo resolvedor. Preserve-o nas verificações normais. Com o cache preparado:

```sh
dart pub get --offline --enforce-lockfile
dart format --output=none --set-exit-if-changed lib bin test
dart analyze --fatal-infos
dart test
dart run bin/har_budget_audit.dart demo
dart run bin/har_budget_audit.dart demo --format json
```

A demonstração constrói dados em memória e não faz requisições HTTP. No contêiner preparado, pode-se usar `PUB_CACHE=/work/build/.pub-cache`; artefatos/cache ficam fora do controle de versão. Registre SDK/imagem concretos para comparar resultados, pois tags são mutáveis.

## Uso da CLI

```sh
dart run bin/har_budget_audit.dart check examples/site.har --budget examples/budgets.json --format json
dart run bin/har_budget_audit.dart check examples/site.har --budget examples/budgets.json --format markdown
```

A amostra passa exatamente nos limites. A saída JSON contém os valores abaixo:

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

O exemplo mostra campos selecionados; o relatório completo também inclui unidades, contagens por origem, p50/p95, limites, verificações e códigos de motivo. Em `https://app.example.test`, os tempos 10 e 30 ms resultam em p50 de 10 e p95 de 30 ms, com 350 bytes conhecidos. A requisição única do CDN tem ambos os percentis em 50 ms e 70 bytes conhecidos.

```sh
dart run bin/har_budget_audit.dart check examples/exceeded.har --budget examples/budgets.json --format markdown
dart run bin/har_budget_audit.dart check examples/unknown.har --budget examples/budgets.json --format json
```

Esses casos retornam intencionalmente 1 e 3. Códigos de saída: **0 passou, 1 excedeu, 3 indeterminado, 2 entrada/configuração/E/S/erro interno**. `--help` retorna 0. Relatórios usam stdout; erros sanitizados usam stderr, sem caminhos ou valores de entrada.

Exemplo de orçamento:

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

As chaves precisam ser iguais à origem canônica de `Uri.origin`: sem barra final, porta padrão, credenciais, caminho, consulta ou fragmento. Cada regra exige ao menos um limite. Uma origem observada sem regra fica indeterminada, em vez de ser ignorada.

## Biblioteca

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

A biblioteca rejeita listas de bytes acima do limite; quem a chama também deve limitar a leitura inicial. A CLI verifica o tamanho antes e durante a leitura. Falhas da biblioteca são `AuditException`, com código estável e índice opcional de entrada, iniciado em zero.

## Demonstração offline

A demonstração cria em memória três exportações sintéticas e um orçamento. Confere os resultados esperados e retorna 0; divergência retorna 2. Não lê nem grava arquivos persistentes e não acessa serviços externos. Trechos da saída Markdown:

```text
Scenario: passing; expected: passed.
Status: **passed**
Scenario: violation; expected: exceeded.
Status: **exceeded**
Scenario: unknown_transfer; expected: indeterminate.
Status: **indeterminate**
Demo expectations: passed.
```

Os relatórios completos aparecem entre essas linhas. O modo JSON retorna `demo_status: "passed"` e três casos, cada um com estado esperado e relatório completo. Códigos e rótulos de máquina permanecem em inglês nos dois formatos.

## Interpretação, segurança e limites

- `entry.time` representa milissegundos decorridos da requisição, sem reconstrução das fases. A soma de durações de requisições **não é o tempo de carregamento da página**; a ferramenta não calcula essa soma.
- Posto mais próximo: `ceil(p * n)` sobre amostras ordenadas, com posições iniciadas em 1. Não há interpolação, notas inventadas ou garantia estatística.
- Bytes conhecidos exigem `bodySize` e `headersSize` inteiros não negativos. Se qualquer um for `-1`, a transferência inteira da entrada é desconhecida. `content.size` nunca substitui bytes transferidos.
- Com bytes desconhecidos, o limite de bytes é indeterminado, salvo se a soma conhecida já exceder o limite. Qualquer violação conclusiva prevalece. Regras apenas de duração não são invalidadas por tamanhos desconhecidos.
- HAR pode conter credenciais, cookies, tokens, corpos e dados pessoais. Mantenha-o local e protegido. Relatórios omitem metadados, preservando apenas origens normalizadas e métricas derivadas; as próprias origens podem ser sensíveis. Não versione exportações reais.
- Limites: 8 MiB por arquivo, 20.000 entradas, 1.000 origens observadas, 1.000 regras, 8.192 unidades UTF-16 por URL, 64 níveis de contêineres JSON e 500.000 valores JSON. Inteiros de bytes/contagens e somas de bytes ficam até 2^53−1, com soma verificada.
- Só o subconjunto necessário à análise é validado. As amostras sintéticas não são exportações completas de navegador. HAR é um formato interoperável de exportação; o antigo rascunho abandonado do W3C não é autoridade de conformidade. A ferramenta não certifica desempenho web nem conformidade com padrões de navegador.

Consulte o [contrato](docs/contract.md), [projeto](docs/design.md), [contribuições](CONTRIBUTING.md) e [segurança](SECURITY.md). Contato geral: [site oficial](https://lofranotecnologia.com.br). Licença MIT, copyright 2026 Lofrano Tecnologia.
