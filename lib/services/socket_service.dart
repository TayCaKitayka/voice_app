import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as socket_io;
import '../config/api_config.dart';

class SocketService extends ChangeNotifier {
  socket_io.Socket? _socket;
  bool _isConnected = false;

  socket_io.Socket? get socket => _socket;
  bool get isConnected => _isConnected;

  void connect(String userId) {
    if (_socket != null && _isConnected) {
      debugPrint('⚠️ Socket уже подключен');
      return;
    }

    debugPrint('🔌 Подключение к ${ApiConfig.socketUrl}...');

    _socket = socket_io.io(
      ApiConfig.socketUrl,
      socket_io.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(5)
          .setReconnectionDelay(1000)
          .build(),
    );

    _socket!.onConnect((_) {
      debugPrint('✅ Socket подключен');
      _isConnected = true;
      _socket!.emit('user:online', userId);
      debugPrint('📡 Отправлен статус онлайн для $userId');
      notifyListeners();
    });

    _socket!.onDisconnect((_) {
      debugPrint('❌ Socket отключен');
      _isConnected = false;
      notifyListeners();
    });

    _socket!.onError((error) {
      debugPrint('❌ Socket ошибка: $error');
    });

    _socket!.on('user:status', (data) {
      debugPrint('👤 Получен статус пользователя: $data');
    });

    _socket!.connect();
  }

  void disconnect() {
    debugPrint('🔌 Отключение Socket...');
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _isConnected = false;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}