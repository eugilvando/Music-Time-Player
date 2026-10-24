import 'package:flutter/material.dart';

enum AppSection {
  home('Início', Icons.home),
  nowPlaying('Tocando agora', Icons.play_circle),
  library('Biblioteca', Icons.library_music),
  artists('Artistas', Icons.people),
  albums('Álbuns', Icons.album),
  favorites('Favoritos', Icons.favorite),
  playlists('Playlists', Icons.playlist_play),
  downloads('Downloads', Icons.download),
  history('Histórico', Icons.history),
  insights('Estatísticas de escuta', Icons.bar_chart),
  settings('Configurações', Icons.settings);

  const AppSection(this.label, this.icon);
  final String label;
  final IconData icon;
}
