import 'package:flutter/material.dart';

/// Renders the Figma symbol family without changing action identifiers.
class MtIcon extends Icon {
  const MtIcon(
    super.icon, {
    super.key,
    super.size,
    super.color,
    super.semanticLabel,
    super.textDirection,
    super.shadows,
    super.applyTextScaling,
    super.fill,
    super.weight,
    super.grade,
    super.opticalSize,
    super.blendMode,
    super.fontWeight,
  });

  static final symbols = <IconData, IconData>{
    Icons.add: const IconData(0xe145, fontFamily: 'Material Symbols Rounded'),
    Icons.bar_chart: const IconData(
      0xe26b,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.album: const IconData(0xe019, fontFamily: 'Material Symbols Rounded'),
    Icons.arrow_back: const IconData(
      0xe5c4,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.arrow_downward: const IconData(
      0xe5db,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.arrow_forward: const IconData(
      0xe5c8,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.arrow_upward: const IconData(
      0xe5d8,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.auto_awesome: const IconData(
      0xe65f,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.backup_outlined: const IconData(
      0xe864,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.cached: const IconData(
      0xe86a,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.calendar_month: const IconData(
      0xebcc,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.check_circle: const IconData(
      0xf0be,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.check_circle_outline: const IconData(
      0xf0be,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.checklist: const IconData(
      0xe6b1,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.chevron_left: const IconData(
      0xe5cb,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.chevron_right: const IconData(
      0xe5cc,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.circle: const IconData(
      0xef4a,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.close: const IconData(0xe5cd, fontFamily: 'Material Symbols Rounded'),
    Icons.cloud: const IconData(0xf15c, fontFamily: 'Material Symbols Rounded'),
    Icons.cloud_done: const IconData(
      0xe2bf,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.cloud_outlined: const IconData(
      0xf15c,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.computer: const IconData(
      0xe31e,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.crop_square: const IconData(
      0xe3c6,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.dashboard_customize: const IconData(
      0xe99b,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.dashboard_customize_outlined: const IconData(
      0xe99b,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.delete_forever: const IconData(
      0xe92b,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.delete_outline: const IconData(
      0xe92e,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.download: const IconData(
      0xf090,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.downloading: const IconData(
      0xf001,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.drag_handle: const IconData(
      0xe25d,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.edit: const IconData(0xf097, fontFamily: 'Material Symbols Rounded'),
    Icons.error_outline: const IconData(
      0xf8b6,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.expand_less: const IconData(
      0xe5ce,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.expand_more: const IconData(
      0xe5cf,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.explore: const IconData(
      0xe87a,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.extension_outlined: const IconData(
      0xe87b,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.favorite: const IconData(
      0xe87e,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.favorite_border: const IconData(
      0xe87e,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.file_open: const IconData(
      0xeaf3,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.filter_alt: const IconData(
      0xef4f,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.folder: const IconData(
      0xe2c7,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.folder_open: const IconData(
      0xe2c8,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.fullscreen: const IconData(
      0xe5d0,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.graphic_eq: const IconData(
      0xe1b8,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.grid_view: const IconData(
      0xe9b0,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.history: const IconData(
      0xf2c1,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.home: const IconData(0xe9b2, fontFamily: 'Material Symbols Rounded'),
    Icons.library_music: const IconData(
      0xe030,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.library_music_outlined: const IconData(
      0xe030,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.link_off: const IconData(
      0xe16f,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.login: const IconData(0xea77, fontFamily: 'Material Symbols Rounded'),
    Icons.lyrics: const IconData(
      0xec0b,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.menu: const IconData(0xe5d2, fontFamily: 'Material Symbols Rounded'),
    Icons.more_horiz: const IconData(
      0xe5d3,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.music_note: const IconData(
      0xe405,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.offline_pin: const IconData(
      0xe90a,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.open_in_full: const IconData(
      0xf1ce,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.open_in_new: const IconData(
      0xe89e,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.palette_outlined: const IconData(
      0xe40a,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.pause: const IconData(0xe034, fontFamily: 'Material Symbols Rounded'),
    Icons.people: const IconData(
      0xe01a,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.person: const IconData(
      0xf0d3,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.photo_library_outlined: const IconData(
      0xe413,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.piano: const IconData(0xe521, fontFamily: 'Material Symbols Rounded'),
    Icons.play_arrow: const IconData(
      0xe037,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.play_circle: const IconData(
      0xe1c4,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.playlist_play: const IconData(
      0xe05f,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.queue_music: const IconData(
      0xe03d,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.refresh: const IconData(
      0xe5d5,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.remove: const IconData(
      0xe15b,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.remove_circle_outline: const IconData(
      0xf08f,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.repeat: const IconData(
      0xe040,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.repeat_one: const IconData(
      0xe041,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.restore: const IconData(
      0xe8b3,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.save: const IconData(0xe161, fontFamily: 'Material Symbols Rounded'),
    Icons.save_alt: const IconData(
      0xf090,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.search: const IconData(
      0xef7a,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.settings: const IconData(
      0xe8b8,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.settings_outlined: const IconData(
      0xe8b8,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.shuffle: const IconData(
      0xe043,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.skip_next: const IconData(
      0xe044,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.skip_previous: const IconData(
      0xe045,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.stop: const IconData(0xe047, fontFamily: 'Material Symbols Rounded'),
    Icons.storage: const IconData(
      0xe1db,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.storage_outlined: const IconData(
      0xe1db,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.swap_horiz: const IconData(
      0xe8d4,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.sync: const IconData(0xe627, fontFamily: 'Material Symbols Rounded'),
    Icons.tune: const IconData(0xe429, fontFamily: 'Material Symbols Rounded'),
    Icons.view_agenda_outlined: const IconData(
      0xe8e9,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.view_carousel_outlined: const IconData(
      0xe8eb,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.view_list: const IconData(
      0xe8ef,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.view_list_outlined: const IconData(
      0xe8ef,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.view_module_outlined: const IconData(
      0xe8f0,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.visibility: const IconData(
      0xe8f4,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.visibility_off: const IconData(
      0xe8f5,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.volume_off: const IconData(
      0xe04f,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.volume_up: const IconData(
      0xe050,
      fontFamily: 'Material Symbols Rounded',
    ),
    Icons.warning_amber: const IconData(
      0xf083,
      fontFamily: 'Material Symbols Rounded',
    ),
  };

  @override
  Widget build(BuildContext context) => Icon(
    symbols[icon] ?? icon,
    size: size,
    color: color,
    semanticLabel: semanticLabel,
    textDirection: textDirection,
    shadows: shadows,
    applyTextScaling: applyTextScaling,
    fill: fill ?? 1,
    weight: weight ?? 400,
    grade: grade ?? 0,
    opticalSize: opticalSize ?? 24,
    blendMode: blendMode,
    fontWeight: fontWeight,
  );
}
