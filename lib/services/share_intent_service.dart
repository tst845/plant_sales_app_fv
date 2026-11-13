// lib/services/share_intent_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

class ShareIntentService {
  static final ShareIntentService instance = ShareIntentService._internal();
  ShareIntentService._internal();

  StreamSubscription? _subscription;
  final _fileStreamController = StreamController<String>.broadcast();
  Stream<String> get fileStream => _fileStreamController.stream;

  /// Файл, полученный при холодном старте.
  /// Кэшируется, потому что broadcast-стрим теряет события,
  /// отправленные до появления подписчика.
  String? _pendingInitialFile;

  Future<void> initialize() async {
    // 1. ХОЛОДНЫЙ СТАРТ: приложение было закрыто
    try {
      final initialMedia =
          await ReceiveSharingIntent.instance.getInitialMedia();
      if (initialMedia.isNotEmpty) {
        final path = initialMedia.first.path;
        if (path != null && path.isNotEmpty) {
          _pendingInitialFile = path;        // ← кэшируем для позднего потребителя
          _fileStreamController.add(path);   // ← и пробуем доставить «живым» подписчикам
        }
      }
    } catch (e) {
      debugPrint('ShareIntentService: getInitialMedia error: $e');
    }

    // reset() в актуальных версиях плагина async — обязательно await.
    // Если не дождаться, следующее событие getMediaStream() может «потеряться».
    try {
      await ReceiveSharingIntent.instance.reset();
    } catch (e) {
      debugPrint('ShareIntentService: reset error: $e');
    }

    // 2. ГОРЯЧИЙ СТАРТ: приложение уже открыто
    _subscription =
        ReceiveSharingIntent.instance.getMediaStream().listen(
      (list) {
        if (list.isEmpty) return;
        final path = list.first.path;
        if (path != null && path.isNotEmpty) {
          _fileStreamController.add(path);
        }
      },
      onError: (e) => debugPrint('ShareIntentService stream error: $e'),
    );
  }

  /// Забирает файл, полученный при холодном старте (один раз).
  /// Возвращает null, если файла не было или его уже забрали.
  String? consumeInitialFile() {
    final f = _pendingInitialFile;
    _pendingInitialFile = null;
    return f;
  }

  void dispose() {
    _subscription?.cancel();
    _fileStreamController.close();
  }
}