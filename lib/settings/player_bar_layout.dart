import 'app_settings.dart';

/// Stable IDs used by the bar, organizer and portable preferences.
const playerBarItems = <String, String>{
  'cover': 'Capa',
  'info': 'Título e informações da faixa',
  'previous': 'Anterior',
  'play': 'Reproduzir / pausar',
  'next': 'Próxima',
  'shuffle': 'Aleatório',
  'repeat': 'Repetição',
  'favorite': 'Favorito',
  'actions': 'Ações da faixa',
  'lastfm': 'Status Last.fm',
  'elapsed': 'Tempo decorrido',
  'progress': 'Barra de progresso',
  'duration': 'Duração da faixa',
  'volume': 'Volume',
  'offline': 'Disponibilidade da faixa',
  'continuous': 'Play contínuo',
  'lyrics': 'Letras',
  'queue': 'Fila',
  'expand': 'Tocando agora',
  'separator1': 'Separador 1',
  'separator2': 'Separador 2',
  'separator3': 'Separador 3',
};

List<String> playerBarOrder(AppSettings settings) => {
  ...settings
      .visualList('bar_item_order', playerBarItems.keys.toList())
      .where(playerBarItems.containsKey),
  ...playerBarItems.keys,
}.toList();

Set<String> playerBarVisible(AppSettings settings) => settings
    .visualList(
      'bar_items',
      playerBarItems.keys
          .where(
            (id) => switch (id) {
              'separator1' || 'separator2' || 'separator3' => false,
              'shuffle' ||
              'repeat' => settings.visualBool('secondary_controls'),
              'progress' => settings.visualBool('show_progress'),
              'elapsed' || 'duration' =>
                settings.visualBool('show_progress') &&
                    settings.visualBool('show_times'),
              'volume' => settings.visualBool('show_volume'),
              _ => true,
            },
          )
          .toList(),
    )
    .where(playerBarItems.containsKey)
    .toSet();

bool validPlayerBarItems(Object? value) =>
    value is List &&
    value.every((id) => id is String && playerBarItems.containsKey(id)) &&
    value.toSet().length == value.length;
