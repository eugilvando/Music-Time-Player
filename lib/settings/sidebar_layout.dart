const sidebarItems = [
  'home',
  'nowPlaying',
  'library',
  'artists',
  'albums',
  'favorites',
  'playlists',
  'history',
  'insights',
];

List<String> sidebarOrder(List<String> saved) => [
  ...saved.where(sidebarItems.contains).toSet(),
  ...sidebarItems.where((id) => !saved.contains(id)),
];

bool validSidebarItems(Object? value) =>
    value is List &&
    value.length <= sidebarItems.length &&
    value.toSet().length == value.length &&
    value.every(sidebarItems.contains);
