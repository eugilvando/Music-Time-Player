# Music Time

**Sua música, sua biblioteca, seu tempo.** Player pessoal para Windows, com arquivos locais, nuvens e servidores de mídia. Flutter/Dart, MediaKit/libmpv e SQLite, sem backend próprio.

[Baixar para Windows x64](https://github.com/eugilvando/Music-Time-Player/releases/latest) · [English / documentação completa das funcionalidades](README.md) · [Configurar fontes](docs/provider-setup.md)

**Versão atual: 2.5.2+54.** Este repositório começa com uma cópia da versão atual. Não inclui o histórico do repositório de desenvolvimento, banco pessoal, credenciais, playlists pessoais, backups nem logs internos.

![Home do Music Time com biblioteca fictícia](docs/images/home.png)

Design: **Gilvando Souza**.

## Novidades da 2.5.2

Desativar shuffle restaura a ordem original, preservando a ocorrência atual e a posição da música. O fundo da capa passa a ser global em todas as seções. Configurações ganha Sobre, com versão, autoria, licenças e links; o organizador da sidebar fica abaixo de Navegação e início. [Detalhes e validação](docs/release-2.5.2.md).

## Novidades da 2.5.1

A Home reaproveita a composição ao retornar durante a sessão e mantém o conteúdo compatível visível enquanto prepara uma atualização em segundo plano. A troca acontece ao concluir. Fontes ocultas e filtros offline são respeitados; a primeira carga grande continua usando skeleton. [Escopo e validação](docs/release-2.5.1.md).

## Novidades da 2.5.0

Shuffle reorganiza a fila visível, mantendo a faixa atual. Barra adaptativa em janelas estreitas, volume com 8 px e Last.fm ativo vermelho. Home com skeleton e navegação A–Z nas listas ordenadas por nome, incluindo faixas paginadas em SQL. Insights mantém cache e conteúdo durante atualização em segundo plano, uma vez por seleção por sessão; atualização manual disponível. Conta e atualização ficam junto aos períodos. [Notas e validação](docs/release-2.5.0.md).

## Novidades da 2.4.1

Salvar fila como playlist e Limpar fila ficam no menu de ações junto ao título da fila. Os organizadores da sidebar e da barra de reprodução são recolhíveis e começam fechados, preservando suas preferências. [Notas da revisão](docs/release-2.4.1.md).

## Novidades da 2.4.0

Insights ganha rádio do artista, mais ouvidas do artista no período e mais populares globais do Last.fm cruzadas com a biblioteca. A revisão exibe o nome esperado e sugestões de substituição para confirmação. Salve a fila como playlist com ordem e repetições; organize/oculte itens da barra lateral e amplie o vinil e as letras, com menor espaçamento. Insights reutiliza as imagens da biblioteca. [Detalhes e limites](docs/release-2.4.0.md).

## Novidades da 2.3.0

Revisão de metadados do álbum inteiro e escolha de capa, inclusive em álbuns sem imagem. Somente campos marcados são aplicados; títulos, artistas de faixa e números de disco/faixa são preservados. Capas manuais resistem à sincronização e podem integrar backups com imagens. Decodificação de miniaturas e caches limitados reduzem o uso de memória por imagens. [Detalhes, medições e compatibilidade](docs/release-2.3.0.md).

## Novidades da 2.2.1

Álbuns com vários discos passam a exibir seções por disco e reproduzir na ordem disco/faixa. Leitura MP3 TPOS e FLAC DISCNUMBER, com faixas na mesma pasta ou em subpastas CD1/CD2. IDs, playlists e favoritos existentes preservados. [Detalhes e compatibilidade](docs/release-2.2.1.md).

## Novidades desde a 2.0

**Listening Insights / Estatísticas de escuta**, abaixo de Histórico: rankings pessoais Last.fm, períodos exatos/personalizados, gráfico de atividade, comparação e resumos semanais/mensais/anuais, CSV e geração revisada de playlist manual ou fila. Cache offline e cobertura parcial explícita, sem alterar o histórico local.

Inclui fontes primária/secundária independentes, refinamentos de Home/capas/ações, Top Tracks em artistas, painéis Queue/Lyrics redimensionáveis e restauração da janela pela bandeja sem perder dimensões. Modelos: Classic, Vinyl, Minimalist, Cover Only e Lyrics Only.

## Instalação

1. Baixe `MusicTime-Setup-2.5.2.exe` na [release 2.4.0](https://github.com/eugilvando/Music-Time-Player/releases/tag/v2.5.2).
2. Instale no seu usuário do Windows. Não é necessário instalar Flutter/Dart para usar o player.
3. Em **Settings → Music sources**, adicione arquivos/pastas locais ou configure uma fonte. A reprodução local não exige uma conta.
4. Sincronize o catálogo e reproduza músicas, álbuns ou playlists.
5. O idioma inicial é inglês. Para português, selecione **General and appearance → Language** nas configurações. Alguns textos dinâmicos e diagnósticos ainda podem manter o idioma original.

O instalador Windows x64 inclui aplicação, motor de áudio, SQLite e bibliotecas necessárias. Não possui assinatura digital: o Windows pode identificar um editor desconhecido. Confira o SHA256 da release e não altere configurações de segurança para instalar algo em que não confia.

Fechar a janela normalmente mantém o app na bandeja. Use **bandeja → Sair** para encerrar; tarefas em segundo plano podem gerar um aviso. A sessão é restaurada pausada.

## Importante: Google Drive e OneDrive

**Cada usuário precisa registrar o próprio aplicativo OAuth e informar seu Client ID.** Esta distribuição não fornece um registro compartilhado nem usa códigos de outros aplicativos. É possível configurar pelo próprio Music Time, sem recompilar.

- **OneDrive pessoal:** crie um registro Microsoft para contas pessoais, cliente público, permissão delegada `Files.Read` e retorno `http://localhost:42813/oauth`. Copie o **Application (client) ID**, não o Object ID ou tenant ID. Não há Client Secret no fluxo Microsoft. Contas corporativas/escolares não são anunciadas como suportadas.
- **Google Drive:** crie um projeto Google Cloud, ative a Drive API, configure o consentimento e gere um **OAuth Client ID do tipo Desktop app**. Informe também o segredo desktop se o Google exigir. Em modo de teste, autorize sua conta como usuário de teste.
- O Google usa `drive.readonly`, um escopo restrito. Pode exigir verificação, limitar usuários e exibir avisos. Tokens de renovação de projetos externos em Testing podem expirar em sete dias. Criar um Client ID não contorna políticas, restrições administrativas ou cotas.
- A pasta selecionada limita a indexação do Music Time, mas não reduz a permissão OAuth do provedor a essa pasta.

O [guia de configuração](docs/provider-setup.md) traz as etapas e links oficiais. Senhas Microsoft/Google são informadas somente nos sites dos provedores. Não publique JSON de credenciais, tokens ou Client Secrets em issues.

## Fontes

| Fonte | Requisitos |
| --- | --- |
| Arquivos locais | Arquivos/pastas acessíveis no Windows. |
| OneDrive pessoal | Registro OAuth próprio, conta pessoal, navegador e seleção de pastas; várias contas/pastas implementadas. |
| Google Drive | Registro OAuth desktop próprio; My Drive ou pasta escolhida no seletor visual, com subpastas. |
| WebDAV | URL HTTPS completa da pasta musical e credenciais do servidor. |
| Jellyfin / Emby | URL, usuário e senha; áudio direto, sem negociação de transcodificação. |
| SMB | Caminho UNC acessível na sessão de rede do Windows; autenticação pelo Windows. |

## Funcionalidades da versão atual

- **Home:** 12 seções configuráveis — mixes, ouvindo agora, playlists/faixas/álbuns/artistas favoritos, descobrir álbuns/artistas, artistas/álbuns recentes, artistas mais ouvidos e últimas reproduções. Ordem, visibilidade, quantidade, estilo e tamanho independentes por seção, com prévia ao editar.
- **Navegação e visualizações:** sidebar recolhível, fila lateral elevada, grades/listas/carrosséis, cards compactos horizontais, colunas detalhadas e cinco tamanhos de cards. Tema claro/escuro/sistema, acento manual ou do Windows, fontes, movimento e fundos personalizáveis.
- **Biblioteca e pesquisa:** músicas, álbuns, artistas, artistas de álbum, gêneros, anos, décadas e pastas; busca geral ou contextual, tolerante a caixa/acentos, limpeza com Esc/X, filtros combináveis, ordenação e seleção Ctrl/Shift com ações em lote.
- **Favoritos:** índices independentes de faixas, álbuns, artistas e playlists, filtros rápidos e indicadores na cor de destaque. A mídia em reprodução fica identificada na biblioteca. Clique direito abre as ações do item.
- **Artistas e álbuns:** discografia por ano, play direto do álbum, navegação entre artista/álbum, ano e gêneros conhecidos, numeração por disco/faixa, mais álbuns do artista e similares presentes na coleção. Retratos/biografias opcionais e imagens personalizadas.
- **Metadados e capas:** leitura local e complementação remota pertinente, edição manual e mesclagem somente no catálogo, restauração das tags originais, múltiplos artistas e agrupamento conservador. `/` é preservado em nomes como AC/DC. Capas iguais compartilham armazenamento por SHA256.
- **Player:** controles completos, mudo pelo volume, shuffle, repeat, fila editável com repetições, estado/posição persistidos e restauração pausada. Cinco modelos de Now Playing, capa ampliada e fundos desfocados.
- **Barra de reprodução:** organizador de ordem e visibilidade de itens, três separadores opcionais, campos de informações, tempos/progresso e status local/cache/permanente.
- **Mixes e rádio:** seleção relacionada a faixa/álbum, mix somente com créditos do artista e rádio com similares da coleção. Mix e rádio de artista têm tamanhos independentes, padrão 40 e intervalo 1–500, prévia e regeneração. Iniciam uma fila; salvar playlist é uma ação separada. Play contínuo opcional usa músicas da própria biblioteca.
- **Áudio e letras:** equalizador de cinco bandas com presets/compensação de ganho; letras LRC/TXT ao lado, MP3 embutidas suportadas, recuperação OneDrive e fallback opcional LRCLIB. Rolagem, seek, offset e apresentação configuráveis; palavras sincronizadas apenas com timestamps reais.
- **Playlists:** criar, renomear, excluir, favoritar, reordenar e preservar repetições; capa própria ou colagem de quatro capas. Importação/exportação M3U8 UTF-8 e referências OneDrive/Symfonium. Importação em lote continua após falhas, mantém pendências e permite revisar/vincular/remover. A barra de correção some quando as pendências terminam.
- **Histórico e Last.fm:** histórico local com contagens reais; Last.fm opcional com autorização, now playing/scrobbling, outbox, favoritos/recentes/rankings e similaridade. Importar recentes não inventa contagens locais.
- **Listening Insights:** estatísticas Last.fm por período e resumos semanais/mensais/anuais, CSV, cache offline e prévia de playlist com associação conservadora. Salvar playlist e tocar somente uma fila são ações distintas. Requer usuário e chave Last.fm em Integrações. [Guia](docs/listening-insights.md).
- **Downloads e offline:** tarefas por faixa/coleção/seleção, retry, remoção individual dos permanentes e referências compartilhadas. Abas de permanentes/cache, listas compactas recolhíveis e informações de espaço. Cache padrão 10 GB, cinco próximas faixas e 30 dias sem uso. Offline global usa apenas arquivos presentes e válidos; placeholders OneDrive não contam.
- **Configurações e dados:** nove categorias redesenhadas pelo Figma, cards e busca, resumo da coleção, cache/downloads separados e colunas selecionáveis. Backup `.mtbackup` seletivo, importação apenas de playlists, capas opcionais e fontes/IDs. Credenciais/sessões são opcionais e exigem criptografia por senha. Músicas/downloads físicos não entram no backup.
- **Windows:** bandeja, comportamento ao fechar/minimizar e controles de mídia nativos com capa, metadados, play/pause, navegação e seek.

Editar informações, mesclar entidades ou remover uma ocorrência de playlist **não altera ou apaga suas músicas originais**.

## Capturas

A galeria de interface foi capturada na 2.0 e a tela Listening Insights na 2.2, usando componentes reais e uma biblioteca fictícia isolada, com capas e textos criados para demonstração. Não são contas conectadas nem músicas incluídas no download.

| Biblioteca | Tocando agora e fila |
| --- | --- |
| ![Biblioteca](docs/images/library.png) | ![Tocando agora](docs/images/now-playing.png) |

![Estatísticas de escuta com dados fictícios](docs/images/listening-insights.png)

Mais capturas estão no [README em inglês](README.md#screenshots).

## Limitações atuais

- A release estável é para Windows x64. Há uma prévia experimental separada para Ubuntu 24.04 x64; Android e macOS não são entregues/validados.
- Google Drive, WebDAV, Jellyfin, Emby, SMB e envios Last.fm têm implementação/testes controlados, mas ainda precisam de aceites reais mais amplos. Testes não equivalem a certificação por serviço.
- Sincronização manual/completa; não há política geral automática/incremental. Google oferece um seletor visual de pastas. Não há transcodificação Jellyfin/Emby.
- Agrupamentos de artistas/álbuns ainda não são integralmente paginados em SQL. Coleções grandes exigem medição na máquina real.
- Não há matriz exaustiva de formatos/codecs/dispositivos. Leitura remota MP3/FLAC é mais completa que outros containers.
- Letras, retratos, biografias e similaridade dependem de terceiros e podem não encontrar o item ou confundir homônimos.
- Sem regras AND/OR de playlists inteligentes, etiquetas, várias filas nomeadas ou posição independente por álbum/playlist.
- Sem atualização automática da seleção offline de playlists, downloads por regras, retomada de bytes ou diretório/concorrência gerais configuráveis.
- Sem timer, ReplayGain, controles de gapless/crossfade, AutoEQ/perfis de fone, saída avançada, início com Windows e sistema completo de atalhos/notificações configuráveis.
- Backup limitado a 128 MiB descompactados, com capas opcionais até 64 MiB. Credenciais exigem senha; sessões podem expirar. Versões antigas não leem o novo arquivo `.mtbackup`.

Consulte [dados e privacidade](docs/privacy-and-data.md), [compilação](docs/building.md), [release](docs/release-2.4.0.md) e [avisos de terceiros](THIRD_PARTY_NOTICES.md). O código próprio do Music Time usa [MIT](LICENSE); as dependências mantêm suas licenças.

## Prévia Ubuntu atualizada

[Baixar Ubuntu 2.4.1 Preview 1](https://github.com/eugilvando/Music-Time-Player/releases/tag/v2.4.1-ubuntu-preview.1). Pacote experimental separado, com 41 testes direcionados e abertura gráfica verificados; áudio, contas e VM reais seguem pendentes. [Instalação e limites](docs/ubuntu-preview.md). A release estável Windows permanece independente.
