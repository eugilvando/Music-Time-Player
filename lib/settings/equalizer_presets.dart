import 'dart:convert';

const equalizerPresets = <String, List<double>>{
  'Neutro': [0, 0, 0, 0, 0],
  'Reforço de graves': [6, 4, 0, -1, -2],
  'Reforço de agudos': [-2, -1, 0, 4, 6],
  'Voz': [-3, -1, 4, 3, -2],
  'Rock': [4, 2, -2, 3, 4],
  'Pop': [-1, 2, 4, 2, -1],
  'Jazz': [3, 1, 0, 2, 3],
  'Clássica': [3, 1, -1, 1, 3],
  'Eletrônica': [5, 3, -1, 2, 4],
};

bool validEqualizerPresets(Object? value) =>
    value is Map &&
    value.length <= 50 &&
    value.entries.every(
      (entry) =>
          entry.key is String &&
          (entry.key as String).trim().isNotEmpty &&
          (entry.key as String).length <= 60 &&
          entry.value is List &&
          (entry.value as List).length == 5 &&
          (entry.value as List).every(
            (gain) => gain is num && gain.isFinite && gain >= -12 && gain <= 12,
          ),
    );

Map<String, List<double>> decodeEqualizerPresets(String raw) {
  try {
    final value = jsonDecode(raw);
    if (!validEqualizerPresets(value)) return {};
    return (value as Map).map(
      (key, gains) => MapEntry(
        key as String,
        (gains as List).map((v) => (v as num).toDouble()).toList(),
      ),
    );
  } catch (_) {
    return {};
  }
}
