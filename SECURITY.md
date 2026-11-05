# Security policy

## Reporting

Use GitHub private vulnerability reporting for this repository, when enabled:

https://github.com/martinlofranodeoliveira/har-budget-audit/security/advisories/new

Do not disclose a suspected vulnerability or sensitive HAR in a public issue. General contact is through the [official Lofrano Tecnologia homepage](https://lofranotecnologia.com.br). No email address or response-time SLA is specified.

Provide a minimal **synthetic** reproducer, Dart version, relevant limits and expected versus observed behavior. Never attach real cookies, authorization headers, URLs containing secrets, request bodies, personal data or client exports. If private reporting is not enabled, do not post secrets publicly; use general contact only to ask how to arrange a private report.

## Scope and handling

Version 0.1.0 is in development. Relevant risks include input-bound bypasses, excessive parsing resources, false passing results with unknown bytes, arithmetic errors and source-data leakage through reports or diagnostics.

The tool performs no traffic capture, network requests, telemetry or remote execution. Runtime code uses only Dart libraries. Development dependency resolution and CI container acquisition are separate network-enabled setup activities. The real dependency lockfile is included; prepare its matching package cache before locked offline checks.

HAR files can contain credentials and personal information. Keep input and output local with appropriate filesystem permissions. Only normalized origins and aggregate metrics are reported, but origins may themselves be sensitive. This tool is not an anonymizer, sandbox or access-control mechanism. It follows explicitly supplied paths, including symlinks to regular files. Process memory, filesystem behavior, terminal history and package-manager behavior are outside its protection boundary.

Malformed input diagnostics deliberately omit parser/platform exception text and paths. Inputs have byte, entry, origin, URL-length, JSON-depth and JSON-value limits. These mitigate denial-of-service inputs but do not constitute a hard memory quota or filesystem read deadline. See [contract](docs/contract.md) and [design](docs/design.md).


## Português

Versão 0.1.0 em desenvolvimento. Relate vulnerabilidades pelo mecanismo privado do GitHub somente se estiver habilitado; não publique HAR, segredos ou detalhes em issues públicas. O [site oficial](https://lofranotecnologia.com.br) é contato geral para combinar uma via privada quando necessário. Não há e-mail inventado ou SLA de resposta. Use reprodução sintética, versão Dart e resultados esperados/observados.

Não há captura de tráfego, cliente HTTP, telemetria da aplicação ou execução remota. Pacotes de teste/cache e SDK são preparados separadamente. Entradas e relatórios ficam locais; origens normalizadas também podem revelar infraestrutura. A ferramenta não anonimiza dados nem controla permissões do filesystem.

Diagnósticos não reproduzem caminhos, valores privados, stack traces ou mensagens brutas de parser/E/S. Limites estruturais e numéricos reduzem trabalho por entrada, sem oferecer quota de memória ou prazo de leitura. Forneça caminhos locais estáveis; stat/open não impede substituição hostil por arquivos especiais. Falha de saída retorna 2, mas pode deixar saída parcial; confira o status antes de consumir um relatório.
