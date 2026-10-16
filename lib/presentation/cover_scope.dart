import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../persistence/library_store.dart';

class CatalogCoverCache {
  CatalogCoverCache(this.store);
  final LibraryStore store;
  final values = <String, Uint8List?>{};
  final pending = <String, Future<Uint8List?>>{};
  int bytes = 0, epoch = 0;
  void clear() {
    epoch++;
    pending.clear();
    values.clear();
    bytes = 0;
  }

  Future<Uint8List?> load(String id) {
    if (values.containsKey(id)) {
      final value = values.remove(id);
      values[id] = value;
      return Future.value(value);
    }
    final requestEpoch = epoch;
    return pending.putIfAbsent(
      id,
      () => store
          .trackCover(id)
          .then(
            (value) {
              if (requestEpoch != epoch) return value;
              pending.remove(id);
              values[id] = value;
              bytes += value?.length ?? 0;
              while (values.length > 128 || bytes > 16 * 1024 * 1024) {
                bytes -= values.remove(values.keys.first)?.length ?? 0;
              }
              return value;
            },
            onError: (Object _) {
              if (requestEpoch == epoch) pending.remove(id);
              return null;
            },
          ),
    );
  }
}

class CatalogCoverScope extends InheritedWidget {
  const CatalogCoverScope({
    super.key,
    required this.cache,
    required this.revision,
    required super.child,
  });
  final CatalogCoverCache cache;
  final int revision;
  @override
  bool updateShouldNotify(CatalogCoverScope old) =>
      revision != old.revision || cache != old.cache;
}

class LazyCatalogCover extends StatefulWidget {
  const LazyCatalogCover({
    super.key,
    required this.id,
    required this.cache,
    required this.revision,
    required this.fallback,
  });
  final String id;
  final int revision;
  final CatalogCoverCache cache;
  final Widget fallback;
  @override
  State<LazyCatalogCover> createState() => _LazyCatalogCoverState();
}

class _LazyCatalogCoverState extends State<LazyCatalogCover> {
  late Future<Uint8List?> value = widget.cache.load(widget.id);
  @override
  void didUpdateWidget(LazyCatalogCover old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id ||
        old.revision != widget.revision ||
        old.cache != widget.cache) {
      value = widget.cache.load(widget.id);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: value,
    builder: (context, snapshot) => snapshot.data == null
        ? widget.fallback
        : Image.memory(
            snapshot.data!,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, __, ___) => widget.fallback,
          ),
  );
}
