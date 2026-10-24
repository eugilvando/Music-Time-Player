# Music Time — Ubuntu preview 2.2.1

Pacote experimental para **Ubuntu Desktop 24.04 x64 (amd64)**. Não instala nem modifica a versão Windows. Não é uma declaração de suporte Linux completo.

## Instalar na máquina virtual

Copie o `.deb` para a VM e abra um terminal na pasta do arquivo:

```sh
sudo apt update
sudo apt install ./music-time-preview_2.2.1-0ubuntu1~preview1_amd64.deb
music-time-preview
```

O apt instala as dependências. É necessário acesso à internet para isso. Abra também pelo menu **Music Time (Ubuntu Preview)**. Use uma sessão gráfica Ubuntu normal, com GNOME Keyring desbloqueado para guardar sessões das fontes. Não execute o aplicativo com sudo.

Se a VM apresentar uma janela preta, tente `LIBGL_ALWAYS_SOFTWARE=1 music-time-preview` e confira o suporte gráfico da VM. Para capturar um diagnóstico: `music-time-preview > ~/music-time-preview.log 2>&1`. Revise o arquivo antes de compartilhar, pois erros de fontes podem conter caminhos da sua biblioteca.

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

A remoção do pacote preserva seus dados de usuário e músicas originais. A versão Windows 2.2.1 permanece independente.

## Build

Ubuntu 24.04, Flutter 3.47.7 / Dart 3.13 e dependências GTK3/X11/Xi, libsecret, mpv e SQLite. Executar `flutter pub get`, `flutter analyze`, `flutter build linux --release` e `bash scripts/package-ubuntu.sh`. A compilação remota de teste e seus logs ficam na aba Actions da branch `codex/ubuntu-preview-2.2.1` do repositório público. Nenhuma credencial de fonte é necessária para compilar.
