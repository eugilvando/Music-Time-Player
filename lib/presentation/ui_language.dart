import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

class UiLanguage {
  const UiLanguage(this.code);
  final String code;
}

class UiLanguageDelegate extends LocalizationsDelegate<UiLanguage> {
  const UiLanguageDelegate();
  @override
  bool isSupported(Locale locale) => {'pt', 'en'}.contains(locale.languageCode);
  @override
  Future<UiLanguage> load(Locale locale) =>
      SynchronousFuture(UiLanguage(locale.languageCode));
  @override
  bool shouldReload(UiLanguageDelegate old) => false;
}

/// Only interface labels use this catalog. Music metadata is displayed verbatim.
String ui(BuildContext context, String value) =>
    switch (Localizations.of<UiLanguage>(context, UiLanguage)?.code) {
      'en' => englishLabel(value),
      'pt' => portugueseLabel(value),
      _ => value,
    };

final _portugueseLabels = <String, String>{
  for (final pair in englishLabels.entries) pair.value: pair.key,
  'Musics': 'Músicas',
  'Artist mix': 'Mix de artista',
};
final _portugueseCaseLabels = {
  for (final pair in _portugueseLabels.entries)
    pair.key.toLowerCase(): pair.value,
};
String portugueseLabel(String value) {
  final exact =
      _portugueseLabels[value] ?? _portugueseCaseLabels[value.toLowerCase()];
  if (exact != null) return exact;
  final indexed = RegExp(r'^(\d+) tracks indexed$').firstMatch(value);
  if (indexed != null) return '${indexed[1]} faixas indexadas';
  final updated = RegExp(r'^(\d+) tracks · Updated (.+)$').firstMatch(value);
  if (updated != null) return '${updated[1]} faixas · Atualizado ${updated[2]}';
  final failed = RegExp(r'^The source request failed \(HTTP (\d+)\)\.$')
      .firstMatch(value);
  if (failed != null) {
    return 'A solicitação da fonte falhou (HTTP ${failed[1]}).';
  }
  return value;
}

String uiSourceFolder(BuildContext context, String value) =>
    const {
      'Nenhuma pasta selecionada',
      'Raiz do OneDrive (todas as pastas)',
      'Raiz do OneDrive',
    }.contains(value)
    ? ui(context, value)
    : value;

String uiFormat(BuildContext context, String portuguese, String english) =>
    Localizations.of<UiLanguage>(context, UiLanguage)?.code == 'en'
    ? english
    : portuguese;

String englishLabel(String value) {
  final exact = englishLabels[value];
  if (exact != null) return exact;
  final searchProgress = RegExp(
    r'^Atualizando busca: (\d+) faixas processadas…$',
  ).firstMatch(value);
  if (searchProgress != null) {
    return 'Updating search: ${searchProgress[1]} tracks processed…';
  }
  final migration = RegExp(
    r'^Atualizando o catálogo da versão (\d+) para (\d+)…$',
  ).firstMatch(value);
  if (migration != null) {
    return 'Updating catalog from version ${migration[1]} to ${migration[2]}…';
  }
  if (value.startsWith('Atualizando Last.fm: ')) {
    return 'Updating Last.fm: ${englishLabel(value.substring('Atualizando Last.fm: '.length))}';
  }
  for (final pair in const {
    'Mix · ': 'Genre mix · ',
    'Quantidade de itens: ': 'Item count: ',
    'Faixas: ': 'Tracks: ',
    'Selecionada: ': 'Selected: ',
    'Navegando: ': 'Browsing: ',
    'Repetir: ': 'Repeat: ',
    'Restaurando conexão Last.fm…': 'Restoring Last.fm connection…',
  }.entries) {
    if (value.startsWith(pair.key)) {
      return '${pair.value}${value.substring(pair.key.length)}';
    }
  }
  return value;
}

class UiText extends StatelessWidget {
  const UiText(
    this.data, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
    this.softWrap,
    this.semanticsLabel,
  });
  final String data;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  final bool? softWrap;
  final String? semanticsLabel;
  @override
  Widget build(BuildContext context) => Text(
    ui(context, data),
    style: style,
    maxLines: maxLines,
    overflow: overflow,
    textAlign: textAlign,
    softWrap: softWrap,
    semanticsLabel: semanticsLabel,
  );
}

const englishLabels = <String, String>{
  'Estatísticas de escuta': 'Listening Insights',
  'Somente capa': 'Cover Only',
  'Somente letras': 'Lyrics Only',
  'Espaçamento entre seções': 'Section spacing',
  'Faixas em destaque': 'Top Tracks',
  'Ordenadas pelas reproduções na sua biblioteca.':
      'Ordered by plays in your library.',
  'Prévia dos textos, menus e campos.': 'Preview of text, menus and fields.',
  'Fonte primária': 'Primary font',
  'Fonte secundária': 'Secondary font',
  'A fonte primária é usada nos títulos; a secundária, nos textos, menus e campos.': 'The primary font is used for headings; the secondary font is used for text, menus and fields.',
  'Inter e Bricolage Grotesque estão incluídas no app. As demais fontes dependem do sistema.': 'Inter and Bricolage Grotesque are bundled with the app. Other fonts depend on your system.',
  'Selecione biblioteca ou playlists para incluir capas.':
      'Select library or playlists to include artwork.',
  'Imagem compartilhada inválida.': 'Invalid shared artwork.',
  'Backup excede 128 MB.': 'Backup exceeds 128 MB.',
  'Duração desconhecida': 'Unknown duration',
  'Faixas a adicionar': 'Tracks to add',
  'Limite': 'Limit',
  "Geral e aparência": "General and appearance",
  "Cache e offline": "Cache and offline",
  "Backup e avançado": "Backup and advanced",
  "Restaurar configurações gerais": "Reset general settings",
  "Restaurar interface e player": "Reset interface and player",
  "Espaçamento dos ícones": "Icon spacing",
  "Limpeza de cache": "Cache cleanup",
  "Extrapequeno": "Extra Small",
  'Faixas aguardando pré-carregamento': 'Preloaded tracks',
  'Retenção': 'Retention',
  '30 dias': '30 days',
  "Fontes e IDs de aplicativo": "Sources and application IDs",
  "Credenciais e sessões": "Credentials and sessions",
  "Senha do backup": "Backup password",
  "Confirmar senha": "Confirm password",
  "Importar dados do backup": "Import backup data",
  "Criptografar com senha": "Encrypt with password",
  "Escolha o conteúdo. Músicas e downloads físicos não são incluídos.": "Choose the content. Music files and physical downloads are not included.",
  "Os itens selecionados serão importados sem apagar os demais dados. Playlists serão adicionadas como cópias.": "Selected items will be imported without deleting other data. Playlists will be added as copies.",
  "Capas são opcionais para reduzir o tamanho. Sessões podem expirar; reconexão pode ser necessária em outro computador.": "Artwork is optional to reduce size. Sessions may expire; another computer may require reconnection.",
  "Use pelo menos 12 caracteres. A senha não é salva e não pode ser recuperada.": "Use at least 12 characters. The password is not saved and cannot be recovered.",
  "Backup exportado. Guarde o arquivo e a senha em um local seguro.":
      "Backup exported. Keep the file and password in a safe place.",
  "Escolha biblioteca, playlists, favoritos, histórico, fila, preferências e fontes. Capas são opcionais. Credenciais exigem um backup criptografado com senha. Músicas e downloads físicos não são incluídos.": "Choose your library, playlists, favorites, history, queue, preferences and sources. Artwork is optional. Credentials require a password-encrypted backup. Music files and physical downloads are not included.",
  "Credenciais exigem fontes e senha de pelo menos 12 caracteres.": "Credentials require source settings and a password of at least 12 characters.",
  "Capas excedem 64 MB. Exporte sem capas; elas podem ser coletadas novamente.": "Artwork exceeds 64 MB. Export without artwork; images can be collected again.",
  "Backup excede 128 MB. Exporte sem capas.":
      "Backup exceeds 128 MB. Export without artwork.",
  "Senha incorreta ou backup danificado.":
      "Incorrect password or damaged backup.",
  "Cabeçalho de backup inválido.": "Invalid backup header.",
  "Backup expandido excede 128 MB.": "Expanded backup exceeds 128 MB.",
  "Configuração de fonte inválida.": "Invalid source configuration.",
  "Formato de backup inválido.": "Invalid backup format.",
  "Restaure fontes junto com as credenciais.":
      "Restore sources together with credentials.",
  "Configuração de criptografia incompatível ou senha ausente.":
      "Unsupported encrypted backup or missing password.",
  "Credenciais inválidas ou sem criptografia.":
      "Unencrypted or invalid credentials.",
  "Seção de backup indisponível.": "Unavailable backup section.",
  "Referências de backup inválidas.": "Invalid backup references.",

  'Prévia de design': 'Design review',
  'Perfil temporário com coleção de demonstração':
      'Temporary profile with a demonstration collection',
  'Todas as músicas': 'All music',
  'Somente offline': 'Offline only',
  "Remover esta fonte?": "Remove this source?",
  "A remoção exclui as faixas da fonte do catálogo, seus favoritos, histórico, downloads e cache. As entradas das playlists ficam pendentes de correção. Faixas compartilhadas com outra fonte e arquivos originais são preservados.": "Removing this source deletes its catalog tracks, favorites, history, downloads and cache. Playlist entries become missing references. Tracks shared with another source and original music files are preserved.",
  "Somente áudios da pasta selecionada e das subpastas serão analisados.":
      "Only audio in the selected folder and its subfolders will be scanned.",
  "Não foi possível carregar as pastas. Confira a conexão e tente novamente.":
      "Could not load folders. Check the connection and retry.",
  "Nenhuma subpasta. Você pode selecionar esta pasta.":
      "No subfolders. You can select this folder.",
  "Aguarde o fim da sincronização.": "Wait for synchronization to finish.",
  "Selecione uma pasta musical.": "Select a music folder.",
  "Pause a reprodução antes de remover esta fonte.":
      "Pause playback before removing this source.",
  "Pare a reprodução e aguarde os downloads antes de remover esta fonte.":
      "Stop playback and wait for downloads before removing this source.",
  'Meu Drive': 'My Drive',
  'Mix de artista': 'Artist mix',
  'Rádio do artista': 'Artist radio',
  'Mixes e rádios': 'Mixes and radios',
  'Tamanho do mix de artista': 'Artist mix size',
  'Tamanho da rádio do artista': 'Artist radio size',
  'Informe um número de 1 a 500': 'Enter a number from 1 to 500',
  'Seleções finitas, de 1 a 500 faixas. Alterações afetam apenas novas gerações. Play contínuo é independente.': 'Finite selections, from 1 to 500 tracks. Changes apply to new generations only. Continuous play is separate.',
  'Somente faixas elegíveis da biblioteca. Inclui participações e créditos de artista de álbum.': 'Only eligible library tracks. Guests and album-artist credits are included.',
  'Sem artistas similares com faixas elegíveis na biblioteca. Confira o Last.fm ou use Mix de artista.': 'No similar artists with eligible library tracks. Check Last.fm or use Artist mix.',
  'Sem faixas elegíveis deste artista.': 'No eligible tracks for this artist.',
  'Usar Mix de artista': 'Use Artist mix',
  'Não foi possível gerar a seleção. Tente novamente.':
      'Cannot generate selection. Try again.',
  'Artistas da biblioteca, ordenados por favoritos e histórico quando disponíveis.': 'Library artists, ordered by favorites and listening history when available.',
  'Pesquisar artistas': 'Search artists',
  'solicitadas': 'requested',
  'Resumo da importação': 'Import summary',
  'Importadas': 'Imported',
  'Importadas com pendências': 'Imported with pending items',
  'Falhas': 'Failures',
  'Não foi possível ler o arquivo': 'Cannot read file',
  'Playlist inválida ou não suportada': 'Invalid or unsupported playlist',
  'localizados': 'found',
  'itens não encontrados': 'items not found',
  'resolvidos': 'resolved',
  'Item pendente': 'Unresolved item',
  'Item não encontrado': 'Item not found',
  'Referência original': 'Original reference',
  'Localizar na biblioteca': 'Find in library',
  'Itens ausentes': 'Missing items',
  'Tentar resolver novamente': 'Retry resolution',
  'Sem faixas reproduzíveis. Os itens pendentes foram preservados.':
      'No playable tracks. Pending items are preserved.',
  'Nenhum item pendente': 'No pending items',
  'Adicione faixas a esta playlist.': 'Add tracks to this playlist.',
  'Gerar novamente': 'Regenerate',
  'Salvar como playlist': 'Save as playlist',
  'Visualizar seleção': 'Preview selection',
  'Ações da seleção de artista': 'Selection actions',
  'Lendo arquivo': 'Reading file',
  'Salvando playlist': 'Saving playlist',
  'Concluído': 'Completed',
  'Não foi possível salvar a playlist': 'Cannot save playlist',
  'Vincule as referências remotas não suportadas a faixas da biblioteca antes de exportar.':
      'Link unsupported remote references to library tracks before exporting.',
  'URLs temporárias não podem ser exportadas.':
      'Temporary URLs cannot be exported.',
  'Um item pendente não tem referência exportável.':
      'An unresolved item has no exportable reference.',
  'Referência remota não suportada. Localize uma faixa da biblioteca.':
      'Unsupported remote reference. Link a library track.',
  'Há tarefas em andamento': 'Background tasks are running',
  'Não foi possível concluir o salvamento': 'Saving could not be completed',
  'A fila ou posição mais recente pode não ser salva. Deseja sair mesmo assim?':
      'The latest queue or playback position may not be saved. Exit anyway?',
  'Sair interrompe as tarefas em andamento. Downloads incompletos poderão ser tentados novamente; sincronizações poderão ser retomadas. Deseja sair mesmo assim?': 'Exiting interrupts background tasks. Incomplete downloads can be retried and synchronization can be resumed. Exit anyway?',
  'Manter aberto': 'Keep open',
  'Sair mesmo assim': 'Exit anyway',
  'Carregando biblioteca': 'Loading library',
  'Sincronização local': 'Local synchronization',
  'Sincronização ou conexão de fontes': 'Source synchronization or connection',
  'Pré-carregamento de áudio': 'Audio preloading',
  'Salvando configurações': 'Saving settings',
  'Otimização de capas': 'Artwork optimization',
  'Armazenamento das capas': 'Artwork storage',
  'Otimizar armazenamento das capas?': 'Optimize artwork storage?',
  'Capas idênticas serão compartilhadas sem perder qualidade. A conversão é feita em lotes e pode ser interrompida. Ao final, a compactação reduz o arquivo do banco e precisa de espaço temporário em disco, que pode chegar a duas vezes o tamanho do banco atual. Músicas originais e preferências são preservadas.': 'Identical covers will be shared without losing quality. Conversion runs in batches and can be interrupted. Final compaction shrinks the database file and requires temporary disk space, which may be as large as twice the current database. Original music and preferences are preserved.',
  'Novas capas idênticas são armazenadas uma única vez. Otimize para converter as capas antigas e recuperar espaço no banco.': 'New identical covers are stored once. Optimize to convert older covers and reclaim database space.',
  'Aguarde as tarefas de sincronização e downloads antes de otimizar.':
      'Wait for synchronization and download tasks before optimizing.',
  'Otimizar': 'Optimize',
  'Otimizar capas e compactar banco': 'Optimize artwork and compact database',
  'Interromper após este lote': 'Stop after this batch',
  'Compactando banco…': 'Compacting database…',
  'Otimizando capas…': 'Optimizing artwork…',
  'Otimização interrompida. Você pode continuar depois; capas já convertidas foram preservadas.': 'Optimization stopped. You can continue later; converted covers have been preserved.',
  'Capas compartilhadas e banco compactado.':
      'Covers shared and database compacted.',
  'Não foi possível concluir a otimização. Confira o espaço livre e tente novamente. As capas já convertidas foram preservadas.': 'Optimization could not be completed. Check free disk space and try again. Converted covers have been preserved.',
  'Minimalista': 'Minimalist',
  'Galeria': 'Gallery',
  'Foco': 'Focus',
  'Página inicial': 'Home page',
  'Avançado': 'Advanced',
  'Conexão': 'Connection',
  'Importação': 'Import',
  'Progresso': 'Progress',
  'Ações': 'Actions',

  'Sincronização e índices': 'Synchronization and indexes',
  'Pendências': 'Pending submissions',

  'Aparência e acessibilidade': 'Appearance and accessibility',
  'Interface e player': 'Interface and player',
  'Reprodução e áudio': 'Playback and audio',
  'Biblioteca e metadados': 'Library and metadata',
  'Fontes de música': 'Music sources',
  'Offline e armazenamento': 'Offline and storage',

  'Backup e manutenção': 'Backup and maintenance',
  'Janela e bandeja': 'Window and tray',
  'Tipografia': 'Typography',
  'Movimento e acessibilidade': 'Motion and accessibility',
  'Informações e painéis': 'Information and panels',
  'Barra do player': 'Player bar',
  'Letras — apresentação': 'Lyrics — presentation',
  'Fontes conectadas': 'Connected sources',
  'Visão geral': 'Overview',

  'Limpeza': 'Cleanup',
  'Provedores de letras': 'Lyrics providers',
  'Buscar nas configurações': 'Search settings',
  'Restaurar apenas aparência e acessibilidade':
      'Reset appearance and accessibility only',
  'Restaurar Now Playing': 'Reset Now Playing',
  'Ao fechar a janela': 'When closing the window',
  'Ao minimizar a janela': 'When minimizing the window',
  'Manter na bandeja': 'Keep in tray',
  'Encerrar aplicativo': 'Exit application',
  'Manter na barra de tarefas': 'Keep in taskbar',
  'Identificação': 'Identification',
  'Controles': 'Controls',
  'Painéis e serviços': 'Panels and services',
  'Áudio e estrutura': 'Audio and structure',
  'Tamanho dos cards': 'Card size',
  'Pequeno': 'Small',
  'Médio': 'Medium',
  'Grande': 'Large',
  'Extra grande': 'Extra Large',
  'Maior': 'Larger',

  'Todos / Favoritos': 'All / Favorites',

  'Não foi possível pesquisar. Tente novamente.':
      'Could not search. Try again.',
  'Capas muito grandes': 'Extra large covers',
  'Em reprodução': 'Now playing',
  'Disponibilidade da faixa': 'Track availability',
  'Download permanente': 'Permanent download',
  'Em cache': 'Cached',
  'Disponível por streaming': 'Available for streaming',
  'Ativar mudo': 'Mute',
  'Desativar mudo': 'Unmute',
  'Separador 1': 'Separator 1',
  'Separador 2': 'Separator 2',
  'Separador 3': 'Separator 3',
  'Resultados na biblioteca': 'Library results',
  'Abrir na biblioteca': 'Open in library',
  'Nenhum resultado.': 'No results.',

  'Não foi possível remover o download. A faixa pode estar em uso.':
      'Could not remove the download. The track may be in use.',
  'Remove esta cópia permanente de todas as seleções offline. A faixa continua no catálogo e nas playlists; originais e cache automático são preservados.': 'Removes this permanent copy from all offline selections. The track stays in your catalog and playlists; originals and automatic cache are preserved.',
  'Remover download desta faixa': 'Remove this track download',
  'Mix iniciado.': 'Mix started.',
  'Não há faixas similares disponíveis na biblioteca.':
      'No similar tracks are available in your library.',
  'Criando mix...': 'Creating mix...',
  'Iniciar mix a partir deste item': 'Start mix from this item',
  'Português (Brasil)': 'Portuguese (Brazil)',
  'Inglês': 'English',
  'Reconectar': 'Reconnect',
  'Sem faixas correspondentes': 'No matching tracks',
  'Restaurar e reiniciar': 'Restore and restart',
  'Resetar e reiniciar': 'Reset and restart',
  'Renomear playlist': 'Rename playlist',
  'Recolher barra lateral': 'Collapse sidebar',
  'Nenhuma faixa retornada pelo Last.fm': 'No tracks returned by Last.fm',
  'Mesclar com outro artista': 'Merge with another artist',
  'Informe um nome.': 'Enter a name.',
  'Imagens personalizadas': 'Custom images',
  'Fotos de artistas': 'Artist photos',
  'Expandir barra lateral': 'Expand sidebar',
  'Exibir lista': 'Show list',
  'Exibir grade': 'Show grid',
  'Downloads incompletos': 'Incomplete downloads',
  'Banco da biblioteca': 'Library database',
  'Arquivos locais': 'Local files',
  'Ano mais recente': 'Newest year',
  'Caminho de imagem inseguro': 'Unsafe image path',
  'Redirecionamento inválido': 'Invalid redirect',
  'Imagem inválida': 'Invalid image',
  'Imagem muito grande': 'Image too large',
  'A fonte redirecionou para fora da origem autorizada.':
      'Source redirected outside its authorized origin.',
  'Compartilhamento indisponível. Abra este caminho UNC no Windows e configure o Gerenciador de Credenciais do Windows; depois tente novamente.': 'Share unavailable. Open this UNC path in Windows and configure Windows Credential Manager, then retry.',
  'Reconecte este servidor.': 'Reconnect this server.',
  'Desative o modo offline para sincronizar fontes.':
      'Turn off offline mode to synchronize sources.',
  'Reconecte esta fonte antes de sincronizar.':
      'Reconnect this source before synchronizing.',
  'Cancele a sincronização e aguarde antes de remover esta fonte.':
      'Cancel synchronization and wait before removing this source.',
  'A origem da mídia não corresponde à fonte.': 'Media origin mismatch.',
  'Caminho de arquivo WebDAV inválido.': 'Invalid WebDAV file path.',
  'Caminho de compartilhamento inválido.': 'Invalid share path.',
  'Sincronize esta fonte novamente.': 'Synchronize this source again.',
  'Esta fonte não está disponível no modo offline.':
      'This source is unavailable in offline mode.',
  'Reconecte a fonte original desta faixa.':
      'Reconnect the original source for this track.',
  'A sessão da fonte mudou. Tente novamente.':
      'The source session changed. Retry.',
  'Fonte desconectada.': 'Source disconnected.',
  'Reconecte o Google Drive.': 'Reconnect Google Drive.',
  'O login do Google expirou ou foi rejeitado. Confira o registro OAuth para desktop e reconecte.': 'Google login expired or was rejected. Check the desktop OAuth registration and reconnect.',
  'O Google não retornou acesso offline. Autorize novamente.':
      'Google did not return offline access. Authorize again.',
  'Não foi possível abrir o navegador do sistema.':
      'Could not open the system browser.',
  'A autorização do Google foi recusada.': 'Google authorization was declined.',
  'Informe um Client ID OAuth do Google para desktop.':
      'Enter a Google OAuth desktop client ID.',
  'Reconecte este servidor de mídia.': 'Reconnect this media server.',
  'Não foi possível salvar a configuração da fonte.':
      'Could not save source configuration.',
  'Acesso negado. Reconecte esta fonte ou confira suas permissões.':
      'Access denied. Reconnect this source or check its permissions.',
  'Cancelado. Catálogo existente preservado.':
      'Cancelled. Existing catalog preserved.',
  'Conectando…': 'Connecting…',
  'Fonte indisponível. Confira o endereço, as permissões da conta e a conexão e tente novamente.': 'Source unavailable. Check the address, account permissions and connection, then retry.',
  'Pronto. Sincronize para verificar a conexão e atualizar o catálogo.':
      'Ready. Synchronize to check this connection and update the catalog.',
  'Desconectado. Reconecte para restaurar o acesso à biblioteca e às playlists.': 'Disconnected. Reconnect to restore access to your library and playlists.',
  'Não foi possível conectar. Confira endereço, credenciais e registro do provedor e tente novamente.': 'Could not connect. Check the address, credentials and provider registration, then retry.',
  'Deixe vazio para incluir a biblioteca de áudio acessível a este usuário.':
      'Leave empty to include the audio library accessible to this user.',
  'Consulta título, artista, álbum e duração quando suas letras não estão disponíveis. Desativado no modo offline.': 'Looks up the track title, artist, album and duration when your own lyrics are unavailable. Disabled in offline mode.',
  'Buscar uma breve biografia do artista no TheAudioDB. Descrições em cache ficam disponíveis offline.': 'Fetch a short artist biography from TheAudioDB. Cached descriptions are available offline.',
  'Client ID OAuth para desktop': 'Desktop OAuth client ID',
  'Abrindo o Music Time': 'Opening Music Time',
  'Não foi possível iniciar o Music Time': 'Could not start Music Time',
  'Mostrar biblioteca': 'Show library',
  'Ocultar biblioteca': 'Hide library',
  'Salvar conexão': 'Save connection',
  'Nome da fonte': 'Source name',
  'Número da faixa': 'Track number',
  'Escolha um artista': 'Choose an artist',
  'Escolha um período': 'Choose a period',
  'Cache de letras': 'Lyrics cache',
  'Biografias de artistas': 'Artist biographies',
  'Tamanho dos downloads': 'Download size',
  'Tamanho do cache': 'Cache size',
  'Faixas em cache': 'Cached tracks',
  'Downloads disponíveis': 'Available downloads',
  'Downloads permanentes': 'Permanent downloads',
  'Duração total': 'Total duration',
  'Faixas catalogadas': 'Catalogued tracks',
  'Integrações': 'Integrations',
  'Personalização': 'Customization',
  'Geral': 'General',
  'Origem': 'Origin',
  'Arquivo local': 'Local file',
  'Começar novamente e reiniciar': 'Start again and restart',
  'Fonte indisponível. Verifique o status e tente novamente.':
      'Source unavailable. Check its status and retry.',
  'Registre um aplicativo OAuth para desktop no Google Cloud, ative a API Drive e permita sua conta na tela de consentimento. O Music Time solicita acesso somente para leitura pelo navegador.': 'Register an OAuth desktop application in Google Cloud, enable the Drive API and allow your account on the consent screen. Music Time requests read-only access through your browser.',
  'Atualizar resumo': 'Refresh summary',
  'Nenhum artista similar encontrado na sua biblioteca.':
      'No similar artists found in your library.',
  'Mais deste artista': 'More by this artist',
  'Entendo que os dados do app, as sessões e os downloads gerenciados serão removidos. As músicas originais serão preservadas.': 'I understand that app data, sessions and managed downloads will be removed. Original music files will be preserved.',
  'HTTP envia credenciais e áudio sem criptografia. Use apenas em uma rede confiável.': 'HTTP sends credentials and audio without encryption. Use only on a trusted network.',
  'Configuração OAuth do Google para desktop': 'Google desktop OAuth setup',
  'Desconectar esta fonte?': 'Disconnect this source?',
  'As credenciais serão removidas e o catálogo será ocultado. A definição da conexão é mantida para que Reconectar restaure as mesmas faixas e playlists. As músicas originais são preservadas.': 'Credentials will be removed and the catalog hidden. The connection definition is kept so Reconnect can restore the same track IDs and playlists. Original music files are preserved.',
  'As credenciais ficam no cofre do sistema e não entram no backup. A sincronização lê a fonte sem modificar suas músicas.': 'Credentials are stored in the system vault and excluded from backups. Synchronization reads the source without modifying your music files.',
  'Não foi possível calcular o resumo da coleção.':
      'Could not calculate collection summary.',
  'Verifique se outra instância ainda está fechando e se há espaço em disco. Seus arquivos originais são preservados.': 'Check whether another instance is still closing and that disk space is available. Your original files are preserved.',
  'Permitir HTTP para este servidor': 'Allow HTTP for this server',
  'Lista': 'List',
  'Cards pequenos': 'Small cards',
  '5 linhas': '5 lines',
  '3 linhas': '3 lines',
  'Cards': 'Cards',
  'Detalhada': 'Detailed',
  'Cards compactos': 'Compact cards',
  'Grade de cards compacta': 'Compact Card Grid',
  'Grade de cards': 'Card Grid',
  'faixas disponíveis': 'available tracks',
  'Tipo de visualização': 'View type',
  'Digite a palavra de confirmação': 'Type the confirmation word',
  'Inicie uma faixa para continuar ouvindo aqui.':
      'Start a track to keep listening here.',
  'Selecionar': 'Select',
  'Favoritar playlist': 'Favorite playlist',
  'Remover playlist dos favoritos': 'Remove playlist favorite',
  'Abrir playlist': 'Open playlist',
  'Ainda não há itens disponíveis nesta seção.':
      'No items available for this section yet.',
  'Nenhum arquivo': 'No files',
  'Reproduções globais': 'Global plays',
  'Revisão final · 3 de 3': 'Final review · 3 of 3',
  'Favorite playlists na página Playlists para exibi-las aqui.':
      'Favorite playlists in Playlists to show them here.',
  'Ouvintes na comunidade': 'Community listeners',
  'Reproduções do álbum na comunidade': 'Community album plays',
  'Limpa os dados do Music Time e desconecta as contas. Os arquivos de música originais são preservados. São necessárias três confirmações.': 'Clears Music Time data and disconnects accounts. Original music files are preserved. Three confirmations are required.',
  'Biografia · TheAudioDB': 'Biography · TheAudioDB',
  'Cache automático': 'Automatic cache',
  'Ativar disponíveis offline': 'Activate Available Offline',
  'Ouvindo agora': 'Now listening',
  'Artistas mais ouvidos': 'Most played artists',
  'Álbuns adicionados recentemente': 'Recently Added Albums',
  'Artistas adicionados recentemente': 'Recently Added Artists',
  'Descobrir artistas': 'Discover Artists',
  'Descobrir álbuns': 'Discover Albums',
  'Artistas favoritos': 'Favorite Artists',
  'Faixas favoritas': 'Favorite Tracks',
  'Playlists favoritas': 'Favorite Playlists',
  'Informações': 'Information',
  'Fontes locais': 'Local sources',
  'Sessão Last.fm salva no cofre': 'Last.fm session stored in the system vault',
  'Last.fm desconectado': 'Last.fm disconnected',
  'Preparando o Music Time…': 'Preparing Music Time…',
  'Preparando o motor de áudio…': 'Preparing the audio engine…',
  'Carregando preferências…': 'Loading preferences…',
  'Abrindo sua biblioteca…': 'Opening your library…',
  'Abrindo o banco da biblioteca…': 'Opening the library database…',
  'OneDrive conectado': 'OneDrive connected',
  'OneDrive desconectado': 'OneDrive disconnected',
  'Aguardando autorização no navegador…':
      'Waiting for authorization in your browser…',
  'Nenhuma pasta selecionada': 'No folder selected',
  'Raiz do OneDrive (todas as pastas)': 'OneDrive root (all folders)',
  'Raiz do OneDrive': 'OneDrive root',
  'Last.fm ativo': 'Last.fm active',
  'Last.fm inativo': 'Last.fm inactive',
  'Registro Microsoft de aplicativo desktop. Não use senha ou segredo.': 'Microsoft desktop app registration. Do not enter a password or client secret.',
  'Salvo no cofre do sistema': 'Stored in the system credential vault',
  'API key Last.fm': 'Last.fm API key',
  'API secret Last.fm': 'Last.fm API secret',
  'Animações da reprodução': 'Playback animations',
  'Preserva edições/identificadores diferentes e os arquivos originais. Requer numeração e duração conhecidas.': 'Preserves different editions, identifiers and original files. Requires known track numbers and durations.',
  'Escolha uma música': 'Choose a track',
  'Sua coleção aparece na Biblioteca': 'Your collection appears in Library',
  '0 músicas': '0 tracks',
  'Não foi possível atualizar a biblioteca. Tente novamente.':
      'Could not refresh the library. Try again.',
  'Disponível': 'Available',
  'Indisponível': 'Unavailable',
  'Gênero': 'Genre',
  'Ano de lançamento': 'Release year',
  'Não ouvidas': 'Unplayed',
  'Álbuns favoritos': 'Favorite Albums',
  'Sessão atual': 'Current session',
  'A sessão mudou durante o login. Tente novamente.':
      'The session changed during sign-in. Try again.',
  'O login não identificou um OneDrive válido.':
      'Sign-in did not identify a valid OneDrive.',
  'A sessão Microsoft salva está inválida. Reconecte pelo navegador.':
      'The saved Microsoft session is invalid. Reconnect in your browser.',
  'A sessão Microsoft mudou durante a operação. Tente novamente.':
      'The Microsoft session changed during this action. Try again.',
  'O OneDrive retornado não corresponde à sessão salva. Reconecte a conta pelo navegador.': 'This OneDrive does not match the saved session. Reconnect the account in your browser.',
  'O login Microsoft não está configurado corretamente nesta instalação do Music Time.':
      'Microsoft sign-in is not configured correctly in this installation.',
  'O registro Microsoft não permite este login. Confira o Client ID, o suporte a contas pessoais e habilite fluxos de cliente público em Autenticação.': 'The Microsoft app registration does not allow this sign-in. Check the client ID, personal account support and public client flows under Authentication.',
  'O registro Microsoft precisa da permissão delegada Files.Read do Microsoft Graph.': 'The Microsoft registration needs the delegated Microsoft Graph Files.Read permission.',
  'A autorização foi recusada. Inicie novamente e permita a leitura dos seus arquivos.': 'Authorization was declined. Start again and allow read access to your files.',
  'O código expirou. Clique em Conectar para gerar outro.':
      'The code expired. Click Connect to generate another.',
  'O código não é mais válido. Inicie uma nova conexão.':
      'The code is no longer valid. Start a new connection.',
  'A sessão expirou ou foi revogada. Conecte novamente a conta.':
      'The session expired or was revoked. Reconnect the account.',
  'A Microsoft exige uma nova autorização. Conecte novamente pelo navegador.':
      'Microsoft requires new authorization. Reconnect in your browser.',
  'A Microsoft está temporariamente indisponível. Tente novamente mais tarde.':
      'Microsoft is temporarily unavailable. Try again later.',
  'A Microsoft não concluiu o login. Confira o registro do aplicativo e tente novamente.': 'Microsoft did not complete sign-in. Check the app registration and try again.',
  'O retorno do navegador não corresponde ao registro. Registre http://localhost:42813/oauth em Aplicativos móveis e desktop.': 'The browser callback does not match the registration. Register http://localhost:42813/oauth under Mobile and desktop applications.',
  'O registro do Music Time não foi encontrado. Confira a configuração do aplicativo.': 'The Music Time app registration was not found. Check the app configuration.',
  'Este registro não aceita a conta escolhida. Use uma conta Microsoft pessoal e um registro que aceite contas pessoais.': 'This registration does not accept the selected account. Use a personal Microsoft account and a registration supporting personal accounts.',
  'Uma política da organização bloqueou o acesso. Use a conta pessoal ou consulte o administrador.': 'An organization policy blocked access. Use your personal account or contact the administrator.',
  'O registro exige segredo de cliente. Configure o Music Time como aplicativo público/nativo.': 'The registration requires a client secret. Configure Music Time as a public/native application.',
  'A Microsoft retornou uma resposta inválida. Tente novamente.':
      'Microsoft returned an invalid response. Try again.',
  'A Microsoft não retornou um código válido. Tente novamente.':
      'Microsoft did not return a valid code. Try again.',
  'Não foi possível receber o retorno do navegador. A porta local pode estar em uso. Feche outras tentativas de conexão e tente novamente pelo navegador.': 'Could not receive the browser callback. The local port may be in use. Close other sign-in attempts and try again.',
  'Não foi possível abrir o navegador. Feche outras tentativas de conexão e tente novamente pelo navegador.':
      'Could not open the browser. Close other sign-in attempts and try again.',
  'O login demorou demais. Feche outras tentativas de conexão e tente novamente pelo navegador.': 'Sign-in timed out. Close other sign-in attempts and try again in your browser.',
  'Microsoft não retornou uma sessão válida.':
      'Microsoft did not return a valid session.',
  'A sessão Microsoft mudou. A renovação anterior foi descartada; tente novamente.': 'The Microsoft session changed. The earlier refresh was discarded; try again.',
  'Conecte o OneDrive pelo navegador em Configurações → Fontes.':
      'Connect OneDrive in your browser through Settings → Sources.',
  'A conta Microsoft mudou durante a operação. Tente novamente.':
      'The Microsoft account changed during this action. Try again.',
  'O endereço do arquivo musical não é válido. Tente novamente.':
      'The music file address is invalid. Try again.',
  'O servidor não aceitou a leitura parcial. O teste foi interrompido para evitar baixar o arquivo inteiro; a reprodução ainda pode funcionar.': 'The server did not accept partial reading. The check stopped to avoid downloading the entire file; playback may still work.',
  'A leitura parcial retornou uma resposta inválida. Tente novamente.':
      'Partial reading returned an invalid response. Try again.',
  'O arquivo musical não retornou a amostra esperada. Tente novamente.':
      'The music file did not return the expected sample. Try again.',
  'O endereço do arquivo musical não pôde ser acessado. Tente novamente.':
      'The music file address could not be accessed. Try again.',
  'O OneDrive retornou uma identificação inválida. Tente novamente.':
      'OneDrive returned an invalid identifier. Try again.',
  'O OneDrive negou a leitura. Confira o consentimento Files.Read e as permissões da pasta.': 'OneDrive denied read access. Check Files.Read consent and folder permissions.',
  'Esta conta não possui um OneDrive disponível. Abra o OneDrive no navegador para configurar o drive.': 'This account has no available OneDrive. Open OneDrive in your browser to set it up.',
  'A pasta ou arquivo não foi encontrado. Escolha novamente a pasta musical.':
      'The folder or file was not found. Select your music folder again.',
  'O OneDrive não respondeu corretamente. Tente novamente mais tarde.':
      'OneDrive did not respond correctly. Try again later.',
  'Chave Last.fm inválida ou suspensa. Consulte suas chaves no site e atualize a configuração.': 'The Last.fm API key is invalid or suspended. Check your keys on the website and update the configuration.',
  'Perfil Last.fm não encontrado. Confira o nome de usuário.':
      'Last.fm profile not found. Check the username.',
  'Sessão Last.fm expirada. Autorize novamente pelo navegador.':
      'The Last.fm session expired. Authorize again in your browser.',
  'Sem conexão. Confira a internet e tente novamente.':
      'No connection. Check your internet connection and try again.',
  'Falha de conexão. Confira a internet e tente novamente.':
      'Connection failed. Check your internet connection and try again.',
  'A conexão demorou demais. Tente novamente.':
      'The connection timed out. Try again.',
  'Operação não concluída. Confira a configuração e a conexão; tente novamente.': 'The action did not finish. Check the configuration and connection, then try again.',
  'Não foi possível salvar o Client ID. Tente novamente.':
      'Could not save the client ID. Try again.',
  'Outra conta está fazendo login. Conclua ou cancele antes de iniciar novamente.':
      'Another account is signing in. Finish or cancel it before trying again.',
  'A conta não retornou um OneDrive válido.':
      'The account did not return a valid OneDrive.',
  'Sessão Microsoft e OneDrive: acesso confirmado.':
      'Microsoft session and OneDrive: access confirmed.',
  'Escolha a pasta musical para verificar a leitura de músicas.':
      'Select your music folder to check read access.',
  'A seleção não corresponde a uma pasta. Escolha novamente a pasta musical.':
      'The selection is not a folder. Select your music folder again.',
  'A pasta não pertence ao OneDrive desta sessão. Escolha novamente a pasta musical.': 'The folder does not belong to this session’s OneDrive. Select your music folder again.',
  'Nenhuma música indexada nesta pasta. Sincronize e repita a verificação.': 'No tracks are indexed in this folder. Synchronize it and repeat the check.',
  'Agora teste reproduzir e avançar na música. Repita após fechar e abrir o aplicativo.': 'Now test playback and seeking. Repeat after closing and reopening the app.',
  'Now playing não foi enviado. Confira a sessão Last.fm.':
      'Now playing was not sent. Check your Last.fm session.',
  'Não foi possível registrar scrobble localmente.':
      'Could not save the scrobble locally.',
  'Serviço temporariamente indisponível.': 'Service temporarily unavailable.',
  'Resposta desconhecida. Envio não será repetido automaticamente.':
      'Unknown response. The submission will not be retried automatically.',
  'Fila Last.fm não processada. Confira conexão e sessão.':
      'The Last.fm queue was not processed. Check the connection and session.',
  'A conta desta música não está conectada. Reconecte a fonte correspondente; downloads locais continuam disponíveis.': 'This track’s account is not connected. Reconnect its source; local downloads remain available.',
  'Esta música pertence a outra conta OneDrive. Conecte a conta correspondente para reproduzi-la; os downloads locais continuam disponíveis.': 'This track belongs to another OneDrive account. Connect that account to play it; local downloads remain available.',
  'Download não concluído. Confira rede e espaço disponível.':
      'Download incomplete. Check the network and available disk space.',
  'Esta faixa não está disponível offline. Desative o modo offline para acessar a nuvem.': 'This track is not available offline. Turn off offline mode to access its source.',
  'O modo offline está ativo. Escolha uma faixa disponível neste dispositivo.':
      'Offline mode is on. Choose a track available on this device.',
  'Não foi possível reproduzir este arquivo.': 'Could not play this file.',
  'Formato ou versão de backup incompatível.':
      'Incompatible backup format or version.',
  'Não foi possível salvar preferências.': 'Could not save preferences.',
  'Backup restaurado. Reconecte fontes quando necessário; a reprodução permanece pausada.':
      'Backup restored. Reconnect sources if needed; playback remains paused.',
  'Music Time resetado. Adicione suas fontes para começar novamente.':
      'Music Time was reset. Add your sources to start again.',
  'Preparando leitura rápida de metadados sem capas…':
      'Preparing a fast metadata read without artwork…',
  'Use uma imagem PNG ou JPEG de até 4 MB.':
      'Use a PNG or JPEG image up to 4 MB.',
  'Ordenação deve conter todas as ocorrências da playlist.':
      'The order must contain every playlist occurrence.',
  'Aguardando inicialização': 'Waiting for startup',
  'Informe seu usuário Last.fm para atualizar os índices.':
      'Enter your Last.fm username to refresh indexes.',
  'Atualização automática desativada': 'Automatic refresh is off',
  'Atualização agendada após a inicialização':
      'Refresh scheduled after startup',
  'Atualização adiada: modo offline ativo':
      'Refresh postponed: offline mode is on',
  'Índices preservados; modo offline ativo.':
      'Indexes preserved; offline mode is on.',
  'Informe seu usuário Last.fm.': 'Enter your Last.fm username.',
  'Atualizando índices Last.fm…': 'Refreshing Last.fm indexes…',
  'Índices Last.fm atualizados': 'Last.fm indexes updated',
  'Não foi possível atualizar os índices Last.fm. Confira usuário, chave e conexão; os dados anteriores foram preservados.': 'Could not refresh Last.fm indexes. Check your username, API key and connection. Previous data was preserved.',
  'favoritos': 'loved tracks',
  'recentes': 'recent plays',
  'mais ouvidas': 'top tracks',
  'último mês': 'last month',
  'reproduções': 'plays',
  'faixas': 'tracks',
  'às': 'at',
  'Não informado': 'Not provided',
  'faixas aguardando cache': 'tracks waiting for caching',
  'arquivos disponíveis. Não expiram automaticamente.':
      'files available. They do not expire automatically.',
  'arquivos completos. Removidos após 30 dias sem uso ou ao atingir o limite.': 'complete files. Removed after 30 days without use or when the size limit is reached.',
  'arquivos': 'files',
  'Downloads ativos': 'Active downloads',
  'Arquivos baixados · permanentes': 'Downloaded files · permanent',
  'Grade': 'Grid',
  'Tamanho dos mixes': 'Mix size',
  'Criar e reproduzir mix': 'Create and play mix',
  'Tentar novamente': 'Retry',
  'Use um número de 1 a 9999': 'Enter a whole number from 1 to 9999',
  'Repetir': 'Repeat',
  'Fila': 'Queue',
  'Nome': 'Name',
  'Importar': 'Import',
  'Zerar ajuste': 'Reset offset',
  'Data indisponível': 'Date unavailable',
  'Não foi possível abrir este arquivo.': 'Could not open this file.',
  'Não foi possível carregar esta página. Tente novamente.':
      'Could not load this page. Try again.',
  'Não foi possível preparar esta visualização. Tente novamente.':
      'Could not prepare this view. Try again.',
  'Não foi possível preparar o início. Tente novamente.':
      'Could not prepare Home. Try again.',
  'Não foi possível calcular o armazenamento. Tente novamente.':
      'Could not calculate storage usage. Try again.',
  'Não foi possível concluir a limpeza. Tente novamente.':
      'Could not finish cleanup. Try again.',
  'Escolher arquivo': 'Choose file',
  'Usar link HTTPS': 'Use HTTPS link',
  'Remover imagem personalizada': 'Remove custom image',
  'Link da imagem': 'Image URL',
  'Usar imagem': 'Use image',
  'Verificar arquivos offline': 'Verify offline files',
  'Pausar download': 'Pause download',
  'Remover do cache': 'Remove from cache',
  'Regenerar mixes': 'Regenerate mixes',
  'Nenhuma faixa correspondente no ranking retornado.':
      'No matching tracks in the returned chart.',
  'Restaurar tags originais': 'Restore original tags',
  'Mesclar': 'Merge',
  'Alternar tela cheia': 'Toggle full screen',
  'Nome da playlist': 'Playlist name',
  'Minimizar': 'Minimize',
  'Maximizar/restaurar': 'Maximize / restore',
  'Informe um título': 'Enter a title',
  'Informe um número inteiro válido': 'Enter a valid whole number',
  'Consultar seu perfil': 'Look up your profile',
  'faixas da biblioteca': 'library tracks',
  'desligado': 'off',
  'fila': 'queue',
  'faixa': 'track',
  'Não foi possível ler a sessão Last.fm no cofre':
      'Could not read the Last.fm session from the vault',
  'Last.fm não conectado': 'Last.fm is not connected',
  'Filtros': 'Filters',
  'Fonte': 'Source',
  'Conta': 'Account',
  'Pasta (inclui subpastas)': 'Folder (including subfolders)',
  'Pré-carregamento automático': 'Automatic preloading',
  'Cache automático · 30 dias': 'Automatic cache · 30 days',
  'Remover seleção offline': 'Remove offline selection',
  'Alterações aplicadas em tempo real':
      'Changes apply live. Scroll Home to preview your edits.',
  'Não foi possível criar o mix. Confira os filtros e a configuração Last.fm.':
      'Could not create the mix. Check the filters and Last.fm setup.',
  'Ações da seleção': 'Selection actions',
  'Dados Last.fm indisponíveis. Confira a chave e a conexão.':
      'Last.fm data is unavailable. Check the API key and connection.',
  'Editar informações no catálogo': 'Edit catalog information',
  'Filtros da página': 'Page filters',
  'Ações da fonte': 'Source actions',
  'Editar informações no Music Time': 'Edit information in Music Time',
  'Salvar no catálogo': 'Save to catalog',
  'Escolha o destino. Apenas os metadados do catálogo serão unificados; arquivos e referências serão preservados.': 'Choose a destination. Only catalog metadata is merged; files and references are preserved.',
  'Nenhuma playlist corresponde à busca.': 'No playlists match your search.',
  'Client ID público do Music Time': 'Music Time public client ID',
  'Importe favoritos e até 200 reproduções recentes usando a chave da API e seu nome de usuário. Não exige conexão para scrobbling; perfis privados podem restringir a consulta.': 'Import loved tracks and up to 200 recent plays using your API key and username. Scrobbling authorization is not required; private profiles may restrict access.',
  'Usuário Last.fm': 'Last.fm username',
  'Favoritos, recentes e rankings ficam disponíveis para consulta. A importação para favoritos e playlists continua separada.': 'Loved tracks, recent plays and charts can be viewed. Importing favorites and playlists is a separate action.',
  'Não foi possível atualizar a fonte.': 'Could not update this source.',
  'Confira se outra instância ainda está encerrando e se há espaço disponível no disco. Seus arquivos originais não são alterados.': 'Check whether another instance is still closing and that disk space is available. Your original files are preserved.',
  'Capas fazem parte do banco; seu tamanho está incluído no banco da biblioteca. Downloads explícitos são removidos em Downloads; cache automático é separado. Arquivos originais e credenciais não são limpos.': 'Artwork is included in the library database size. Manage permanent downloads in Downloads; automatic cache is separate. Original files and credentials are preserved.',
  'Downloads explícitos, músicas originais e faixa em reprodução são preservados.': 'Permanent downloads, original files and the currently playing track are preserved.',
  'Mixes por década': 'Period mix',
  'Mixes por artista': 'Artist mix',
  'Mixes por gênero': 'Genre mixes',
  'Last.fm · Mais ouvidas': 'Last.fm · Top tracks',
  'Last.fm · Último mês': 'Last.fm · Last month',
  'Mix de favoritos': 'Favorites mix',
  'Descobertas da biblioteca': 'Library discoveries',
  'Redescobertas': 'Rediscoveries',
  'Mix offline': 'Offline mix',
  'Mix pessoal': 'Personal mix',
  'Ajuste': 'Offset',
  'Artistas similares · Last.fm': 'Similar artists · Last.fm',
  'Popularidade do álbum · Last.fm': 'Album popularity · Last.fm',
  'Somente arquivos completos. Cache automático é limpo após 30 dias sem uso, respeitando o limite. Downloads explícitos são permanentes até você removê-los.': 'Only completed files are available. Automatic cache expires after 30 unused days within its size limit. Explicit downloads remain until you remove them.',
  'Remove biblioteca, fontes, playlists, favoritos, histórico, fila, preferências, sessões e downloads gerenciados pelo app. As músicas originais no computador e nas nuvens são preservadas. Exporte um backup antes se quiser guardar seu catálogo. O app será reiniciado.': 'Remove the library, sources, playlists, favorites, history, queue, preferences, sessions and app-managed downloads. Original music on your computer and in the cloud is preserved. Export a backup first to keep your catalog. The app will restart.',
  'RESETAR': 'RESET',
  'RESTAURAR': 'RESTORE',
  'Selecione uma faixa para ver a letra.': 'Select a track to see its lyrics.',
  'Adiantar letra em 250 ms': 'Move lyrics forward by 250 ms',
  'Atrasar letra em 250 ms': 'Delay lyrics by 250 ms',
  'Letra sem sincronização': 'Unsynchronized lyrics',
  'Voltar à letra atual': 'Back to the current lyric',
  'Personalizar imagem do artista': 'Customize artist image',
  'Imagem do artista': 'Artist image',
  'Ir para artista': 'Go to artist',
  'Ir para álbum': 'Go to album',
  'Pausados ou com falha': 'Paused or failed',
  'Selecionar faixas': 'Select tracks',
  'Seleções de downloads explícitos': 'Explicit download selections',
  'Limpar cache de áudio': 'Clear audio cache',
  'Limpar cache de áudio?': 'Clear audio cache?',
  'Remover arquivos gerenciados?': 'Remove managed files?',
  'Resetar todo o Music Time?': 'Reset all Music Time data?',
  'Restaurar backup?': 'Restore backup?',
  'Confirmar mesclagem no catálogo?': 'Confirm catalog merge?',
  'Pesquisar destino': 'Search destination',
  'Carregando músicas…': 'Loading tracks…',
  'Adicione uma fonte para começar sua biblioteca.':
      'Add a source to start your library.',
  'Nenhum resultado. Ajuste a busca e os filtros.':
      'No results. Adjust your search and filters.',
  'Mostrar bibliotecas por fonte': 'Show libraries by source',
  'Selecionar esta pasta': 'Select this folder',
  'Selecionar todas as pastas': 'Select all folders',
  'Gêneros · nenhum selecionado usa todos':
      'Genres · no selection includes all',
  'Deixe vazio para manter a chave salva': 'Leave empty to keep the saved key',
  'Faixas presentes neste álbum entre as mais ouvidas do artista':
      'Tracks on this album among the artist’s most popular',
  'Contagens globais por faixa; não representam suas reproduções locais ou uma edição específica.': 'Global track counts; these are not your local plays or counts for a specific edition.',
  'Exibe e reproduz somente músicas locais acessíveis, downloads completos e cache válido.': 'Show and play only accessible local music, completed downloads and valid cache.',
  'Ocultar afeta a visualização; não remove fontes, arquivos, playlists ou downloads.': 'Hiding changes visibility; it does not remove sources, files, playlists or downloads.',
  'Normaliza somente caixa e espaços. Não divide nomes por vírgula, ponto ou &. Use mesclar para correções explícitas.': 'Normalize only letter case and spaces. Names are not split on commas, periods or &. Use merge for explicit corrections.',
  'Não foi possível usar esta imagem. Use PNG, JPEG ou WebP de até 5 MB e link HTTPS acessível.': 'Could not use this image. Choose PNG, JPEG or WebP up to 5 MB, or an accessible HTTPS link.',
  'Ao terminar a fila, acrescenta faixas do mesmo gênero da sua biblioteca, sem reproduzir músicas externas.':
      'When the queue ends, add tracks of the same genre from your library.',
  'Salvo apenas no catálogo. Artistas aceitam ; , : & feat. e ft. como separadores. Gêneros usam ;. A barra / é preservada.': 'Saved only in the catalog. Artist separators: ; , : & feat. and ft. Genres use ;. The slash / is preserved.',
  'Organizar barra de reprodução': 'Organize playback bar',
  'Arraste para ordenar. Ative ou desative cada item; a barra muda imediatamente.':
      'Drag to reorder. Show or hide each item; the bar updates immediately.',
  'Título e informações da faixa': 'Track title and information',
  'Reproduzir / pausar': 'Play / pause',
  'Status Last.fm': 'Last.fm status',
  'Tempo decorrido': 'Elapsed time',
  'Duração da faixa': 'Track duration',
  'Mover item': 'Move item',
  'Mover para a esquerda': 'Move left',
  'Mover para a direita': 'Move right',
  'Arrastar para ordenar': 'Drag to reorder',
  'Restaurar barra padrão': 'Restore default bar',
  'Usar cor de destaque do Windows': 'Use Windows accent color',
  'Se a cor do sistema estiver indisponível, será usada a cor manual.':
      'If the system color is unavailable, the manual color is used.',
  'Acompanha as alterações de cor do Windows.':
      'Follows Windows accent color changes.',
  'Comportamento': 'Behavior',
  'Textos': 'Text',
  'Play contínuo': 'Continuous play',
  'Cache e pré-carregamento': 'Cache and preloading',
  'Cache automático de áudio': 'Automatic audio cache',
  'Informações da barra': 'Player bar information',
  'Primeira linha: título. Escolha os campos da segunda linha:':
      'First line: title. Choose the fields for the second line:',
  'Modo offline': 'Offline mode',
  'Agrupamento visual': 'Visual grouping',
  'Agrupar variações de nomes de artistas': 'Group artist name variants',
  'Agrupar cópias de álbuns por tags e faixas':
      'Group album copies by tags and tracks',
  'Disponibilidade': 'Availability',
  'Fontes visíveis': 'Visible sources',
  'Textos e espaçamento das letras': 'Lyrics text and spacing',
  'Visualização e ordenação': 'View and sorting',
  'Mesclar no catálogo': 'Merge in the catalogue',
  'Ações da playlist': 'Playlist actions',
  'Revisar importação': 'Review import',
  'faixas localizadas': 'matched tracks',
  'referências pendentes': 'unresolved references',
  'Localize as referências não encontradas ou remova-as somente desta importação. Os arquivos originais são preservados.': 'Match missing references or remove them from this import only. Original files are preserved.',
  'Referência remota não suportada': 'Unsupported remote reference',
  'Removida da importação': 'Removed from import',
  'Referência ambígua': 'Ambiguous reference',
  'Faixa não encontrada': 'Track not found',
  'Localizar faixa': 'Find track',
  'Restaurar referência': 'Restore reference',
  'Remover da importação': 'Remove from import',
  'Importar faixas revisadas': 'Import reviewed tracks',
  'Sugestões pelo nome do arquivo. Pesquise para localizar outras faixas.':
      'Suggestions by filename. Search to find other tracks.',
  'Mostrar esta fonte na biblioteca': 'Show this source in the library',
  'Ocultar não remove músicas, playlists ou downloads.':
      'Hiding does not remove songs, playlists or downloads.',
  'Filtros e visualização': 'Filters and view',
  'músicas na biblioteca': 'songs in the library',
  'músicas': 'songs',
  'Ano não informado': 'Year not provided',

  'Não informada': 'Not provided',
  'Sem álbum': 'Unknown album',
  'Nenhuma faixa selecionada': 'No track selected',
  'Ativar letras': 'Enable lyrics',
  'Desativar letras': 'Disable lyrics',
  'Controles de reprodução': 'Playback controls',
  'Limpar busca': 'Clear search',
  'Buscar músicas, artistas, álbuns e playlists':
      'Search songs, artists, albums and playlists',

  'Clássico': 'Classic',
  'Vinil': 'Vinyl',
  'Cassete': 'Cassette',
  'Recolher sidebar': 'Collapse sidebar',
  'Expandir sidebar': 'Expand sidebar',
  'Repetição': 'Repeat',
  'Favoritar': 'Favorite',
  'Remover favorito': 'Unfavorite',
  'Ações da faixa': 'Track actions',
  'Fechar fila': 'Close queue',
  'Anterior': 'Previous',
  'Próxima': 'Next',
  'Próxima página': 'Next page',
  'Página anterior': 'Previous page',
  'Por página: ': 'Per page: ',
  'Selecionar todas': 'Select all',
  'Limpar seleção': 'Clear selection',
  'Álbuns do artista': 'Artist albums',
  'Colunas da lista detalhada': 'Detailed list columns',
  'Capa e título sempre visíveis.': 'Artwork and title are always visible.',
  'Aplicar': 'Apply',
  'Tudo': 'All',
  'Filtros da biblioteca': 'Library filters',
  'Somente favoritos': 'Favorites only',
  'Somente disponíveis offline': 'Available offline only',
  'Aplicar filtros': 'Apply filters',
  'Nenhuma playlist encontrada. Crie ou importe na página Playlists.':
      'No playlists found. Create or import one on the Playlists page.',
  'Nome A–Z': 'Name A–Z',
  'Nome Z–A': 'Name Z–A',
  'Nenhuma coleção encontrada. Adicione músicas em Configurações ou ajuste os filtros.':
      'No collections found. Add music in Settings or adjust the filters.',
  'Confirmação final': 'Final confirmation',
  'Backup e dados': 'Backup and data',
  'Backup versionado do catálogo, capas, playlists, favoritos, histórico, fila e preferências, até 128 MB. Credenciais, músicas e downloads físicos não entram no arquivo.': 'Versioned backup of the catalog, artwork, playlists, favorites, history, queue and preferences, up to 128 MB. Credentials, music files and downloaded files are excluded.',
  'Exportar backup': 'Export backup',
  'Restaurar backup': 'Restore backup',
  'Começar novamente': 'Start again',
  'Limpa os dados do Music Time e desconecta as contas. Músicas originais são preservadas. Duas confirmações são obrigatórias.': 'Clears Music Time data and disconnects accounts. Original music files are preserved. Two confirmations are required.',
  'Resetar todo o aplicativo': 'Reset the entire app',
  'Remover download?': 'Remove download?',
  'Remove esta seleção offline. Arquivos usados por outras seleções e músicas originais são preservados.': 'Removes this offline selection. Files used by other selections and original music files are preserved.',
  'Selecione músicas ou coleções para disponibilizar offline.':
      'Select songs or collections to make available offline.',
  'Processar pendentes': 'Process pending downloads',
  'Cinco bandas; redução automática de ganho para compensar reforços.':
      'Five bands; automatic gain reduction to compensate for boosts.',
  'Tentar carregar o histórico novamente': 'Retry loading history',
  'Ouça músicas para preencher o histórico.':
      'Listen to music to build your history.',
  'Personalizar início': 'Customize home',
  'Restaurar padrões': 'Restore defaults',
  'Ver tudo': 'See all',
  'Voltar ao início': 'Back to home',
  'Sua biblioteca reunida em um só lugar': 'Your library in one place',
  'Sua música, em todo lugar': 'Your music, everywhere',
  'Fontes e filtros': 'Sources and filters',
  'Continue ouvindo': 'Keep listening',
  'Seleções da sua coleção; diversidade de artistas, sem análise sonora.': 'Selections from your collection with a variety of artists, without audio analysis.',
  'Explore sua biblioteca': 'Explore your library',
  'Ouça músicas para preencher o histórico e as seções Mais ouvidos e Ouça novamente.':
      'Listen to music to populate your history, Most played and Listen again.',
  'Backup exportado sem credenciais ou arquivos musicais.':
      'Backup exported without credentials or music files.',
  'Não foi possível adicionar arquivos.': 'Could not add files.',
  'Crie uma playlist na página Playlists.':
      'Create a playlist on the Playlists page.',
  'Não foi possível concluir a ação.': 'Could not complete the action.',
  'Não foi possível salvar favorito.': 'Could not save favorite.',
  'Selecione uma música para iniciar a fila.':
      'Select a song to start the queue.',
  'Limpar fila': 'Clear queue',
  'Adicionar seleção à playlist': 'Add selection to playlist',
  'Criar playlist com a seleção': 'Create playlist from selection',
  'Não foi possível concluir a ação da seleção.':
      'Could not complete the selection action.',
  'Salvar seleção como playlist manual': 'Save selection as a manual playlist',
  'Criar': 'Create',
  'Remover fonte local?': 'Remove local source?',
  'As faixas desta fonte sairão da biblioteca. Arquivos originais, favoritos e referências em playlists serão preservados.': 'Tracks from this source will leave the library. Original files, favorites and playlist references are preserved.',
  'Fontes ativas': 'Active sources',
  'Adicione pastas ou grupos de arquivos deste computador.':
      'Add folders or groups of files from this computer.',
  'Cancelar sincronização local': 'Cancel local sync',
  'Sincronizar tags e capas': 'Sync tags and artwork',
  'Linhas anteriores': 'Previous lines',
  'Letra da faixa': 'Track lyrics',
  'Próximas linhas': 'Next lines',
  'Adicionar música': 'Add song',
  'Adicione músicas em Configurações primeiro.': 'Add music in Settings first.',
  'Fonte OneDrive da playlist': 'Playlist OneDrive source',
  'Excluir playlist?': 'Delete playlist?',
  'As músicas e os arquivos originais serão preservados.':
      'Songs and original files are preserved.',
  'Crie sua primeira playlist.': 'Create your first playlist.',
  'Adicione músicas a esta playlist.': 'Add songs to this playlist.',
  'Remover da playlist': 'Remove from playlist',
  'Importar playlist': 'Import playlist',
  'Todas as playlists': 'All playlists',
  'Renomear': 'Rename',
  'Exportar playlist': 'Export playlist',
  'Excluir playlist': 'Delete playlist',
  'Letras locais LRC/TXT e letras embutidas quando legíveis. Ajuste de sincronização por faixa em Tocando agora → Letras. Nenhum serviço externo de letras está conectado.': 'Local LRC/TXT and readable embedded lyrics. Adjust track timing in Now playing → Lyrics. No external lyrics service is connected.',
  'Selecionar pasta musical': 'Select music folder',
  'Só arquivos de áudio desta pasta e de suas subpastas.':
      'Only audio files from this folder and its subfolders.',
  'Esta pasta não contém subpastas.': 'This folder has no subfolders.',
  'Pasta selecionada': 'Selected folder',
  'Subpasta incluída na seleção': 'Subfolder included in selection',
  'Voltar': 'Back',
  'Envios Last.fm': 'Last.fm submissions',
  'Nenhum envio registrado.': 'No submissions recorded.',
  'Nome da fonte OneDrive': 'OneDrive source name',
  'Conecte seu OneDrive pessoal': 'Connect your personal OneDrive',
  'Entre na sua conta Microsoft pelo navegador e autorize o acesso às músicas. Depois, escolha a pasta musical. A conexão será concluída automaticamente no Music Time.': 'Sign in to Microsoft in your browser and authorize access to music. Then choose your music folder. Music Time completes the connection automatically.',
  'O login Microsoft ainda precisa ser configurado nesta instalação do Music Time.': 'Microsoft sign-in still needs to be configured in this installation of Music Time.',
  'Conectar pelo navegador': 'Connect in browser',
  'Cancelar conexão': 'Cancel connection',
  'Pasta musical': 'Music folder',
  'Escolher pasta': 'Choose folder',
  'Sincronizar músicas': 'Sync music',
  'Verificar conexão, pasta e leitura': 'Check connection, folder and reading',
  'Desconectar remove apenas a sessão desta conta. Catálogo e downloads locais são preservados.': 'Disconnecting removes only this account session. Catalog and local downloads are preserved.',
  'Inclui todas as subpastas. Lê tags e capas MP3/FLAC em trechos limitados da nuvem, sem baixar músicas inteiras.': 'Includes all subfolders. Reads MP3/FLAC tags and artwork in limited cloud ranges, without downloading entire songs.',
  'Cancelar sincronização': 'Cancel sync',
  'Sincronização interrompida por erro. Tente novamente; o último resumo concluído permanece abaixo.': 'Sync stopped due to an error. Retry; the last completed summary remains below.',
  'Sincronização cancelada. Algumas páginas podem ter sido catalogadas; execute novamente para concluir.':
      'Sync canceled. Some pages may have been cataloged; run again to finish.',
  'Autorizar Last.fm': 'Authorize Last.fm',
  'Concluir após autorizar no navegador':
      'Complete after authorizing in browser',
  'Enviar música atual': 'Submit current song',
  'Ativar scrobbling': 'Enable scrobbling',
  'Registra as reproduções elegíveis e processa a fila offline.':
      'Records eligible plays and processes the offline queue.',
  'Consultar fila de envios': 'View submission queue',
  'Pasta deste computador': 'Folder on this computer',
  'Arquivos deste computador': 'Files on this computer',
  'Idioma': 'Language',
  'Idioma do aplicativo': 'App language',
  'Início': 'Home',
  'Biblioteca': 'Library',
  'Tocando agora': 'Now playing',
  'Artistas': 'Artists',
  'Álbuns': 'Albums',
  'Favoritos': 'Favorites',
  'Histórico': 'History',
  'Configurações': 'Settings',
  'Aparência': 'Appearance',
  'Reprodução': 'Playback',
  'Fontes': 'Sources',
  'Dados': 'Data',
  'Navegação e início': 'Navigation and home',
  'Tema e cores': 'Theme and colors',
  'Visual da reprodução': 'Now playing design',
  'Capas e fundo': 'Artwork and background',
  'Informações e acessibilidade': 'Information and accessibility',
  'Tipografia e letras': 'Typography and lyrics',
  'Restaurar aparência': 'Reset appearance',
  'Página inicial · personalizar seções': 'Home · customize sections',
  'Personalize o Music Time': 'Customize Music Time',
  'Tema': 'Theme',
  'Escuro': 'Dark',
  'Claro': 'Light',
  'Sistema': 'System',
  'Cor de destaque': 'Accent color',
  'Azul': 'Blue',
  'Verde': 'Green',
  'Violeta': 'Violet',
  'Rosa': 'Pink',
  'Âmbar': 'Amber',
  'Formato da capa': 'Artwork shape',
  'Arredondada': 'Rounded',
  'Quadrada': 'Square',
  'Circular': 'Circle',
  'Posição da capa': 'Artwork position',
  'À esquerda': 'Left',
  'À direita': 'Right',
  'Acima das informações': 'Above information',
  'Tamanho da capa': 'Artwork size',
  'Fundo': 'Background',
  'Sólido': 'Solid',
  'Cores da capa': 'Artwork colors',
  'Capa desfocada': 'Blurred artwork',
  'Intensidade do fundo': 'Background intensity',
  'Mostrar fila lateral': 'Show side queue',
  'No Now Playing quando houver espaço suficiente.':
      'In Now Playing when enough space is available.',
  'Mostrar álbum nas informações': 'Show album information',
  'Animações de vinil e cassete': 'Vinyl and cassette animations',
  'Reduzir movimento': 'Reduce motion',
  'A preferência de acessibilidade do sistema também é respeitada.':
      'The system accessibility preference is also respected.',
  'Textos da interface': 'Interface text',
  'Títulos': 'Headings',
  'Textos e campos': 'Text and fields',
  'Informações secundárias': 'Secondary information',
  'Menu lateral': 'Sidebar',
  'Letras': 'Lyrics',
  'Espaçamento das letras': 'Lyrics spacing',
  'Restaurar padrões visuais': 'Restore visual defaults',
  'Equalizador': 'Equalizer',
  'Controles e letras': 'Controls and lyrics',
  'Mostrar shuffle e repetição': 'Show shuffle and repeat',
  'Mostrar controle de volume': 'Show volume control',
  'Mostrar barra de progresso': 'Show progress bar',
  'Mostrar tempos da faixa': 'Show track times',
  'Rolagem automática das letras': 'Auto-scroll lyrics',
  'Sua coleção': 'Your collection',
  'Baixar fotos de artistas automaticamente':
      'Automatically download artist photos',
  'Consulta o nome do artista no TheAudioDB e salva a foto neste dispositivo. Fotos já baixadas funcionam offline.': 'Looks up the artist in TheAudioDB and saves the photo on this device. Saved photos work offline.',
  'Os arquivos originais são preservados. Biblioteca e fila ficam salvas neste dispositivo.': 'Original files are preserved. Your library and queue are saved on this device.',
  'Janela e segundo plano': 'Window and background',
  'Ao fechar, manter na bandeja': 'Keep in tray when closing',
  'Use Sair no menu da bandeja para encerrar o aplicativo.':
      'Use Exit in the tray menu to quit the app.',
  'Minimizar para a bandeja': 'Minimize to tray',
  'A reprodução continua com a janela oculta.':
      'Playback continues while the window is hidden.',
  'Os controles de mídia do Windows funcionam enquanto o app estiver aberto, inclusive na bandeja.': 'Windows media controls work while the app is open, including in the tray.',
  'Provedor indisponível.': 'Provider unavailable.',
  'Downloads indisponíveis.': 'Downloads unavailable.',
  'Gestão de dados indisponível.': 'Data management unavailable.',
  'Músicas': 'Songs',
  'Artistas de álbum': 'Album artists',
  'Gêneros': 'Genres',
  'Anos': 'Years',
  'Décadas': 'Decades',
  'Pastas': 'Folders',
  'Disponíveis offline': 'Available offline',
  'Título': 'Title',
  'Artista': 'Artist',
  'Álbum': 'Album',
  'Duração': 'Duration',
  'Faixa / disco': 'Track / disc',
  'Ano': 'Year',
  'Formato': 'Format',
  'Fonte / conta': 'Source / account',
  'Favorito': 'Favorite',
  'Reproduções': 'Play count',
  'Última reprodução': 'Last played',
  'Inclusão': 'Date added',

  'Visualização': 'View',
  'Lista compacta': 'Compact list',
  'Carrossel': 'Carousel',
  'Grade compacta': 'Compact grid',
  'Lista detalhada': 'Detailed list',
  'Escolher colunas': 'Choose columns',
  'Alternar grade / lista de coleções': 'Toggle collection grid / list',
  'Densidade confortável': 'Comfortable density',
  'Densidade compacta': 'Compact density',
  'Capas pequenas': 'Small artwork',
  'Capas grandes': 'Large artwork',
  'Ordem decrescente': 'Descending order',
  'Ordem crescente': 'Ascending order',
  'Atualizar biblioteca e offline': 'Refresh library and offline status',
  'Reproduzir': 'Play',
  'Reproduzir agora': 'Play now',
  'Aleatório': 'Shuffle',
  'Reproduzir aleatoriamente': 'Shuffle play',
  'Tocar a seguir': 'Play next',
  'Adicionar à fila': 'Add to queue',
  'Favoritar faixas': 'Favorite tracks',
  'Remover favoritos das faixas': 'Unfavorite tracks',
  'Favoritar coleção': 'Favorite collection',
  'Remover favorito da coleção': 'Unfavorite collection',
  'Ações da coleção': 'Collection actions',
  'Adicionar à playlist': 'Add to playlist',
  'Salvar seleção como playlist': 'Save selection as playlist',
  'Disponibilizar offline': 'Make available offline',
  'Discografia': 'Discography',
  'Faixas': 'Tracks',
  'Participações': 'Appearances',
  'Voltar aos artistas': 'Back to artists',
  'Voltar às coleções': 'Back to collections',
  'Limpar filtros': 'Clear filters',
  'Cancelar': 'Cancel',
  'Salvar': 'Save',
  'Fechar': 'Close',
  'Remover': 'Remove',
  'Confirmar': 'Confirm',
  'Adicionar': 'Add',
  'Continuar': 'Continue',
  'Sim': 'Yes',
  'Não': 'No',
  'Excluir': 'Delete',
  'Selecionar tudo': 'Select all',
  'Adicionar fonte': 'Add source',
  'OneDrive pessoal': 'Personal OneDrive',
  'Conectar Microsoft': 'Connect Microsoft',
  'Desconectar': 'Disconnect',
  'Sincronizar': 'Sync',
  'Remover fonte': 'Remove source',
  'Renomear fonte': 'Rename source',
  'Selecionar pasta': 'Select folder',
  'Detalhes da faixa': 'Track details',
  'Remover da fila': 'Remove from queue',
  'Criar playlist': 'Create playlist',
  'Importar M3U8': 'Import M3U8',
  'Exportar M3U8': 'Export M3U8',
  'Ouça novamente': 'Listen again',
  'Adicionados recentemente': 'Recently added',
  'Mais ouvidos': 'Most played',
  'Últimas reproduções': 'Last Played',
  'Feito para você': 'Made for you',
  'Fila de reprodução': 'Playback queue',
  'Pausar': 'Pause',
  'Próxima faixa': 'Next track',
  'Faixa anterior': 'Previous track',
  'Recolher menu lateral': 'Collapse sidebar',
  'Expandir menu lateral': 'Expand sidebar',
  'Obter chave da API Last.fm': 'Get a Last.fm API key',
  'Consultar minhas chaves': 'View my API keys',
  'Dados do perfil': 'Profile data',
  'Importar favoritos': 'Import loved tracks',
  'Importar últimas tocadas': 'Import recent tracks',
  'Importar dados do Last.fm?': 'Import Last.fm data?',
  'Armazenamento e cache': 'Storage and cache',
  'Atualizar tamanhos': 'Refresh sizes',
  'Limpar fotos de artistas': 'Clear artist photos',
  'Limpar downloads incompletos': 'Clear incomplete downloads',
  'Limpar fotos de artistas?': 'Clear artist photos?',
  'Limpar downloads incompletos?': 'Clear incomplete downloads?',
  'Limpar': 'Clear',
  'Neutro': 'Flat',
  'Reforço de graves': 'Bass boost',
  'Reforço de agudos': 'Treble boost',
  'Voz': 'Voice',
  'Clássica': 'Classical',
  'Eletrônica': 'Electronic',
  'Preset do equalizador': 'Equalizer preset',
  'Ajuste manual': 'Manual adjustment',
  'Salvar preset': 'Save preset',
  'Excluir preset': 'Delete preset',
  'Nome do preset': 'Preset name',
  'Personalizado': 'Custom',
  'Atualizar índices após iniciar': 'Refresh indexes after startup',
  'Atualizar índices agora': 'Refresh indexes now',
  'Atualizando índices': 'Refreshing indexes',
  'Faixa confirmada': 'Track confirmed',
  'Alterar faixa confirmada': 'Change confirmed track',
  'Recolher faixa confirmada': 'Collapse confirmed track',
  'Escolher modelos': 'Choose templates',
  'Modelos do Feito para você': 'Made for you templates',
  'Marque os modelos desejados e arraste para mudar a ordem.':
      'Select templates and drag to reorder.',

  'Escolher capa da playlist': 'Choose playlist cover',
  'Remover capa personalizada': 'Remove custom cover',
  'Quantidade de faixas': 'Track count',
};
