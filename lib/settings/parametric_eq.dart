import 'dart:convert';
import 'dart:math' as math;

class EqFilter {
  const EqFilter(this.type, this.frequency, this.gain, this.q);
  final String type;
  final double frequency, gain, q;
  bool get valid =>
      const {'PK', 'LSC', 'HSC'}.contains(type) &&
      frequency.isFinite &&
      frequency >= 20 &&
      frequency <= 20000 &&
      gain.isFinite &&
      gain.abs() <= 24 &&
      q.isFinite &&
      q >= .1 &&
      q <= 30;
  Map<String, Object> toJson() => {
    'type': type,
    'frequency': frequency,
    'gain': gain,
    'q': q,
  };
  factory EqFilter.fromJson(Map<String, dynamic> json) {
    final filter = EqFilter(
      json['type'] as String,
      (json['frequency'] as num).toDouble(),
      (json['gain'] as num).toDouble(),
      (json['q'] as num).toDouble(),
    );
    if (!filter.valid) {
      throw const FormatException('Filtro fora dos limites permitidos.');
    }
    return filter;
  }
  String get native =>
      '${switch (type) {
        'LSC' => 'bass',
        'HSC' => 'treble',
        _ => 'equalizer',
      }}=f=$frequency:t=q:w=$q:r=f32:g=$gain';

  // RBJ biquad response, matching the Q-based native filters at 48 kHz.
  double responseDb(double hz) {
    final a = math.pow(10, gain / 40).toDouble();
    final w = 2 * math.pi * frequency / 48000;
    final c = math.cos(w), alpha = math.sin(w) / (2 * q);
    final beta = 2 * math.sqrt(a) * alpha;
    final List<double> b, d;
    if (type == 'LSC') {
      b = [
        a * ((a + 1) - (a - 1) * c + beta),
        2 * a * ((a - 1) - (a + 1) * c),
        a * ((a + 1) - (a - 1) * c - beta),
      ];
      d = [
        (a + 1) + (a - 1) * c + beta,
        -2 * ((a - 1) + (a + 1) * c),
        (a + 1) + (a - 1) * c - beta,
      ];
    } else if (type == 'HSC') {
      b = [
        a * ((a + 1) + (a - 1) * c + beta),
        -2 * a * ((a - 1) + (a + 1) * c),
        a * ((a + 1) + (a - 1) * c - beta),
      ];
      d = [
        (a + 1) - (a - 1) * c + beta,
        2 * ((a - 1) - (a + 1) * c),
        (a + 1) - (a - 1) * c - beta,
      ];
    } else {
      b = [1 + alpha * a, -2 * c, 1 - alpha * a];
      d = [1 + alpha / a, -2 * c, 1 - alpha / a];
    }
    final x = 2 * math.pi * hz / 48000;
    double power(List<double> v) =>
        math
            .pow(v[0] + v[1] * math.cos(x) + v[2] * math.cos(2 * x), 2)
            .toDouble() +
        math.pow(v[1] * math.sin(x) + v[2] * math.sin(2 * x), 2).toDouble();
    return 10 * math.log(power(b) / power(d)) / math.ln10;
  }
}

class ParametricEqProfile {
  ParametricEqProfile(this.name, this.preamp, List<EqFilter> filters)
    : filters = List.unmodifiable(filters) {
    if (name.trim().isEmpty ||
        name.length > 60 ||
        !preamp.isFinite ||
        preamp < -60 ||
        preamp > 12 ||
        filters.isEmpty ||
        filters.length > 20 ||
        filters.any((f) => !f.valid)) {
      throw const FormatException('Perfil de equalização inválido.');
    }
  }
  final String name;
  final double preamp;
  final List<EqFilter> filters;
  late final double effectivePreamp = _headroom();
  double _headroom() {
    double peak = 0;
    for (var i = 0; i <= 2048; i++) {
      final hz = (20 * math.pow(1000, i / 2048)).toDouble();
      final db = filters.fold<double>(0, (sum, f) => sum + f.responseDb(hz));
      peak = math.max(peak, db);
    }
    return math.min(preamp, peak > 0 ? -(peak + .2) : 0);
  }

  String get nativeChain =>
      'format=format=floatp:srate=48000,lavfi=[${filters.map((f) => f.native).join(',')}]';
  Map<String, Object> toJson() => {
    'name': name,
    'preamp': preamp,
    'filters': filters.map((f) => f.toJson()).toList(),
  };
  factory ParametricEqProfile.fromJson(Map<String, dynamic> json) =>
      ParametricEqProfile(
        json['name'] as String,
        (json['preamp'] as num).toDouble(),
        (json['filters'] as List)
            .map((f) => EqFilter.fromJson(Map<String, dynamic>.from(f as Map)))
            .toList(),
      );

  static ParametricEqProfile parse(String text, String name) {
    if (text.length > 65536) {
      throw const FormatException('O arquivo de perfil é muito grande.');
    }
    const number = r'([-+]?(?:\d+(?:\.\d*)?|\.\d+))';
    final preampPattern = RegExp(
      '^Preamp:\\s*$number\\s*dB\\s*\$',
      caseSensitive: false,
    );
    final filterPattern = RegExp(
      '^Filter\\s+\\d+:\\s+(ON|OFF)\\s+(PK|LSC|HSC|LS|HS)\\s+Fc\\s+$number\\s+Hz\\s+Gain\\s+$number\\s+dB\\s+Q\\s+$number\\s*\$',
      caseSensitive: false,
    );
    double? preamp;
    final filters = <EqFilter>[];
    for (final raw in const LineSplitter().convert(
      text.replaceAll('\uFEFF', ''),
    )) {
      final line = raw.split('#').first.trim();
      if (line.isEmpty) continue;
      final p = preampPattern.firstMatch(line);
      if (p != null) {
        if (preamp != null) {
          throw const FormatException(
            'O perfil contém mais de uma pré-amplificação.',
          );
        }
        preamp = double.parse(p[1]!);
        continue;
      }
      final f = filterPattern.firstMatch(line);
      if (f == null) {
        throw const FormatException(
          'Use o arquivo ParametricEQ.txt exportado pelo AutoEQ. Filtros não reconhecidos não serão ignorados.',
        );
      }
      if (f[1]!.toUpperCase() == 'OFF') continue;
      final type = switch (f[2]!.toUpperCase()) {
        'LS' => 'LSC',
        'HS' => 'HSC',
        final value => value,
      };
      filters.add(
        EqFilter(
          type,
          double.parse(f[3]!),
          double.parse(f[4]!),
          double.parse(f[5]!),
        ),
      );
    }
    if (preamp == null) {
      throw const FormatException('O perfil precisa informar Preamp em dB.');
    }
    return ParametricEqProfile(name.trim(), preamp, filters);
  }
}

Map<String, ParametricEqProfile> decodeParametricProfiles(String text) {
  final result = <String, ParametricEqProfile>{};
  try {
    final data = jsonDecode(text) as Map;
    if (data.length > 50) return result;
    for (final entry in data.entries) {
      try {
        final profile = ParametricEqProfile.fromJson(
          Map<String, dynamic>.from(entry.value as Map),
        );
        if (entry.key == profile.name) result[profile.name] = profile;
      } catch (_) {
        /* Preserve the other valid profiles. */
      }
    }
  } catch (_) {
    /* Older installations have no parametric profiles. */
  }
  return result;
}
