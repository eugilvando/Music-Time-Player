# Music Time — Ubuntu preview 2.4.1 / Preview 1

**Build atualizada em preparação — 26/10/2026:** base 2.4.1+51, SQLite18, backup17/contêiner2. Inclui melhorias de memória, revisão de álbuns, modelos de playlists Insights, menu da fila e organizadores recolhíveis. Mantém o identificador/perfil Ubuntu e a compatibilidade gráfica da Preview 2 anterior. A instalação Windows 2.4.1 não muda. O pacote desta build será entregue para teste separado; não há nova release pública anunciada.

## Histórico e comportamento preservado

[Baixar Preview 2 pública](https://github.com/eugilvando/Music-Time-Player/releases/tag/v2.2.1-ubuntu-preview.2). Build, análise, 24 testes, instalação via apt e capturas Home/Settings/redimensionamento aprovados em CI nos modos compatibility/software; confirmação na VM VMware do titular ainda pendente.

Pacote experimental para **Ubuntu Desktop 24.04 x64 (amd64)**. Não instala nem modifica a versão Windows. Não é uma declaração de suporte Linux completo.

Preview 2 corrige o caminho de renderização usado na prévia anterior: Impeller desativado no runner release e launcher padrão com Skia/OpenGL via Mesa por CPU. O titular relatou triângulos/textos distorcidos no VMware com aceleração 3D ativa. Isso sugere incompatibilidade gráfica; ainda precisa de reteste nessa VM. A versão Windows não é alterada.

A [Preview 1 publicada](https://github.com/eugilvando/Music-Time-Player/releases/tag/v2.2.1-ubuntu-preview.1) permanece histórica. O GitHub normaliza `~` para `.` no nome dos downloads Debian. O ZIP local usa o nome original com `~`; use o nome efetivo do arquivo ao instalar. A versão interna desta build é `2.4.1-0ubuntu1~preview1` e mantém o mesmo identificador/perfil para permitir atualização sem reset.

## Instalar na máquina virtual

Copie o `.deb` para a VM e abra um terminal na pasta do arquivo:

```sh
sudo apt update
sudo apt install ./music-time-preview_2.4.1-0ubuntu1*preview1_amd64.deb
music-time-preview
```

O apt instala as dependências. É necessário acesso à internet para isso. Abra também pelo menu **Music Time (Ubuntu Preview)**. Use uma sessão gráfica Ubuntu normal, com GNOME Keyring desbloqueado para guardar sessões das fontes. Não execute o aplicativo com sudo.

## Compatibilidade gráfica

Feche a instância anterior antes de testar outro modo. O menu e `music-time-preview` usam **compatibility**: Skia sem Impeller, OpenGL por CPU e X11 por padrão, evitando o driver 3D virtual. Pode consumir mais CPU e reduzir a fluidez; não é garantia de correção em todo hypervisor.

Se ainda houver artefatos, teste o caminho alternativo do Flutter por software:

```sh
MUSIC_TIME_RENDERER=software music-time-preview
```

Esse modo é uma alternativa de diagnóstico e pode ter limitações gráficas. Para testar o driver acelerado com Skia, de forma explícita:

```sh
MUSIC_TIME_RENDERER=hardware music-time-preview
```

Não é necessário desligar a aceleração 3D da VM para usar o modo padrão. Como comparação adicional, desligue a VM antes de mudar a configuração gráfica no VMware. Impeller permanece desativado nesta prévia em todos os modos, pela [API oficial Flutter Linux](https://docs.flutter.dev/perf/impeller#linux).

Para capturar um diagnóstico: `music-time-preview > ~/music-time-preview.log 2>&1`. O runner informa apenas modo gráfico, Impeller e software GL no início; revise os demais erros antes de compartilhar, pois podem conter caminhos de arquivos. O comando `LIBGL_ALWAYS_SOFTWARE=1` sozinho na Preview 1 não desativava Impeller, por isso a nova revisão altera o runner compilado.

## Testar

1. Adicionar uma pequena pasta local; conferir tags, capas, duração e ordem de discos.
2. Reproduzir MP3/FLAC, pausar, avançar, buscar posição e testar o equalizador.
3. Criar uma playlist, marcar favoritos, reiniciar e conferir persistência/restauração pausada.
4. Conferir seletores de arquivos, letras e layouts nas dimensões da VM.
5. Depois, testar uma fonte de nuvem e downloads. OneDrive/Google Drive continuam exigindo seu próprio Client ID e reconexão na VM. Credenciais do cofre Windows não são portáveis automaticamente para o cofre Linux.

O perfil usa o identificador próprio `app.musictime.preview`, em um diretório de suporte retornado pelo Linux, separado do Windows. Não copie seu banco Windows como único exemplar de teste. Comece com um perfil novo e arquivos acessíveis pela VM.

## Limites desta prévia

A integração atual de bandeja, teclas de mídia/SMTC, acento do Windows e inicialização com Windows não é ativada no Linux. Fechar a janela encerra esta prévia; não há promessa de continuar na bandeja. SMB deve ser montado pelo Ubuntu e adicionado como pasta local: a integração de compartilhamentos Windows não é portada nesta etapa. APIs/contas e áudio real devem ser conferidos na VM; a compilação e os testes controlados não substituem esse aceite.

```sh
sudo apt remove music-time-preview
```

A remoção do pacote preserva seus dados de usuário e músicas originais. A versão Windows 2.4.1 permanece independente.

## Build

Ubuntu 24.04, Flutter 3.47.7 / Dart 3.13 e dependências GTK3/X11/Xi, libsecret, mpv e SQLite. Executar `flutter pub get`, `flutter analyze`, `flutter build linux --release` e `bash scripts/package-ubuntu.sh`. A compilação remota de teste e seus logs ficam na aba Actions da branch `codex/ubuntu-preview-2.4.1` do repositório público. Nenhuma credencial de fonte é necessária para compilar.
