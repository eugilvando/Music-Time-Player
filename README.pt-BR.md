# Music Time

**Sua música, sua biblioteca, seu tempo.** Player pessoal para Windows, com arquivos locais, nuvens e servidores de mídia. Flutter/Dart, MediaKit/libmpv e SQLite, sem backend próprio.

[Baixar para Windows x64](https://github.com/eugilvando/Music-Time-Player/releases/latest) · [English / documentação completa das funcionalidades](README.md) · [Configurar fontes](docs/provider-setup.md)

**Versão atual: 2.0.0+44.** Este repositório começa com uma cópia da versão atual. Não inclui o histórico do repositório de desenvolvimento, banco pessoal, credenciais, playlists pessoais, backups nem logs internos.

![Home do Music Time com biblioteca fictícia](docs/images/home.png)

## Novidades da 2.0

Design por **Gilvando Souza**, com Home e os cinco modelos Now Playing preservados, configurações reorganizadas, ícones arredondados, tamanhos do Figma, seleção de colunas e backup seletivo com criptografia opcional.

## Instalação

1. Baixe `MusicTime-Setup-2.0.0.exe` na [release 2.0.0](https://github.com/eugilvando/Music-Time-Player/releases/tag/v2.0.0).
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
- **Downloads e offline:** tarefas por faixa/coleção/seleção, retry, remoção individual dos permanentes e referências compartilhadas. Abas de permanentes/cache, listas compactas recolhíveis e informações de espaço. Cache padrão 10 GB, cinco próximas faixas e 30 dias sem uso. Offline global usa apenas arquivos presentes e válidos; placeholders OneDrive não contam.
- **Configurações e dados:** nove categorias redesenhadas pelo Figma, cards e busca, resumo da coleção, cache/downloads separados e colunas selecionáveis. Backup `.mtbackup` seletivo, importação apenas de playlists, capas opcionais e fontes/IDs. Credenciais/sessões são opcionais e exigem criptografia por senha. Músicas/downloads físicos não entram no backup.
- **Windows:** bandeja, comportamento ao fechar/minimizar e controles de mídia nativos com capa, metadados, play/pause, navegação e seek.

Editar informações, mesclar entidades ou remover uma ocorrência de playlist **não altera ou apaga suas músicas originais**.

## Capturas

As capturas usam os componentes reais da versão atual e uma biblioteca fictícia isolada, com capas e textos criados para demonstração. Não são contas conectadas nem músicas incluídas no download.

| Biblioteca | Tocando agora e fila |
| --- | --- |
| ![Biblioteca](docs/images/library.png) | ![Tocando agora](docs/images/now-playing.png) |

Mais capturas estão no [README em inglês](README.md#screenshots).

## Limitações atuais

- Esta release é para Windows x64; Ubuntu/Linux, Android e macOS não são entregues/validados.
- Google Drive, WebDAV, Jellyfin, Emby, SMB e envios Last.fm têm implementação/testes controlados, mas ainda precisam de aceites reais mais amplos. Testes não equivalem a certificação por serviço.
- Sincronização manual/completa; não há política geral automática/incremental. Google oferece um seletor visual de pastas. Não há transcodificação Jellyfin/Emby.
- Agrupamentos de artistas/álbuns ainda não são integralmente paginados em SQL. Coleções grandes exigem medição na máquina real.
- Não há matriz exaustiva de formatos/codecs/dispositivos. Leitura remota MP3/FLAC é mais completa que outros containers.
- Letras, retratos, biografias e similaridade dependem de terceiros e podem não encontrar o item ou confundir homônimos.
- Sem regras AND/OR de playlists inteligentes, etiquetas, várias filas nomeadas ou posição independente por álbum/playlist.
- Sem atualização automática da seleção offline de playlists, downloads por regras, retomada de bytes ou diretório/concorrência gerais configuráveis.
- Sem timer, ReplayGain, controles de gapless/crossfade, AutoEQ/perfis de fone, saída avançada, início com Windows e sistema completo de atalhos/notificações configuráveis.
- Backup limitado a 128 MiB descompactados, com capas opcionais até 64 MiB. Credenciais exigem senha; sessões podem expirar. Versões antigas não leem o novo arquivo `.mtbackup`.

Consulte [dados e privacidade](docs/privacy-and-data.md), [compilação](docs/building.md), [release](docs/release-2.0.0.md) e [avisos de terceiros](THIRD_PARTY_NOTICES.md). O código próprio do Music Time usa [MIT](LICENSE); as dependências mantêm suas licenças.
