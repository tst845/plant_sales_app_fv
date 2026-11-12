import 'dart:async';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

class ShareIntentService {
  static final ShareIntentService instance = ShareIntentService._internal();
  ShareIntentService._internal();

  StreamSubscription? _subscription;
  
  // Поток, который будет отдавать путь к файлу
  final _fileStreamController = StreamController<String>.broadcast();
  Stream<String> get fileStream => _fileStreamController.stream;

  /// Инициализация (вызывается один раз при старте приложения)
  Future<void> initialize() async {
    // 1. Приложение было закрыто, пользователь нажал "Поделиться"
    final initialMedia = await ReceiveSharingIntent.instance.getInitialMedia();
    if (initialMedia.isNotEmpty) {
      final path = initialMedia.first.path;
      if (path != null) _fileStreamController.add(path);
    }
    ReceiveSharingIntent.instance.reset();

    // 2. Приложение уже открыто, пользователь нажал "Поделиться"
    _subscription = ReceiveSharingIntent.instance.getMediaStream().listen((list) {
      if (list.isNotEmpty) {
        final path = list.first.path;
        if (path != null) _fileStreamController.add(path);
      }
    });
  }

  void dispose() {
    _subscription?.cancel();
    _fileStreamController.close();
  }
}