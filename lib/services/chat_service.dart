import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart' as dio_pkg;
import 'dart:convert';
import 'dart:io';
import '../config/api_config.dart';
import '../models/chat_model.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';
import 'socket_service.dart';

class ChatService extends ChangeNotifier {
  SocketService? _socketService;
  String _authToken = '';
  String _currentUserId = '';

  List<ChatModel> _chats = [];
  final Map<String, List<MessageModel>> _messages = {};
  bool _isListening = false;

  // Хранение прогресса загрузки: {tempId: progress (0.0 to 1.0)}
  final Map<String, double> _uploadProgress = {};

  List<ChatModel> get chats => _chats;
  Map<String, double> get uploadProgress => _uploadProgress;

  double getFileProgress(String messageId) => _uploadProgress[messageId] ?? 0.0;

  void init({
    required String token,
    required SocketService socketService,
    String? userId,
  }) {
    _authToken = token;
    _socketService = socketService;
    if (userId != null) _currentUserId = userId;

    _listenToMessages();
    debugPrint('✅ ChatService инициализирован (User: $_currentUserId)');
    notifyListeners();
  }

  void reset() {
    _authToken = '';
    _socketService = null;
    _currentUserId = '';
    _chats = [];
    _messages.clear();
    _isListening = false;
    debugPrint('🔄 ChatService сброшен');
    notifyListeners();
  }

  Map<String, String> _getHeaders() {
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $_authToken',
    };
  }

  Future<void> loadChats() async {
    if (_authToken.isEmpty) return;

    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.apiUrl}/chat/list'),
        headers: _getHeaders(),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        _chats = data.map((json) => ChatModel.fromJson(json)).toList();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('❌ Ошибка загрузки чатов: $e');
    }
  }

  Future<ChatModel?> createOrGetChat(String participantId) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.apiUrl}/chat/create'),
        headers: _getHeaders(),
        body: jsonEncode({'participantId': participantId}),
      );

      if (response.statusCode == 200) {
        final chat = ChatModel.fromJson(jsonDecode(response.body));
        final index = _chats.indexWhere((c) => c.id == chat.id);
        if (index >= 0) {
          _chats[index] = chat;
        } else {
          _chats.insert(0, chat);
        }
        notifyListeners();
        return chat;
      }
    } catch (e) {
      debugPrint('❌ Ошибка создания чата: $e');
    }
    return null;
  }

  Future<List<MessageModel>> loadMessages(String chatId) async {
    if (_authToken.isEmpty) return [];

    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.apiUrl}/chat/$chatId/messages'),
        headers: _getHeaders(),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final messages = data.map((json) => MessageModel.fromJson(json)).toList();
        _messages[chatId] = messages;
        notifyListeners();
        return messages;
      }
    } catch (e) {
      debugPrint('❌ Ошибка загрузки сообщений: $e');
    }
    return [];
  }

  List<MessageModel> getMessages(String chatId) {
    return _messages[chatId] ?? [];
  }

  void sendMessage({
    required String chatId,
    required String senderId,
    required String text,
  }) {
    if (_socketService?.socket == null) {
      debugPrint('⚠️ Не удается отправить сообщение: сокет не подключен');
      return;
    }

    final String tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    debugPrint('📤 Отправка сообщения: tempId=$tempId, text=$text');

    _socketService!.socket!.emit('message:send', {
      'chatId': chatId,
      'senderId': senderId,
      'text': text,
      'type': 'text',
      'tempId': tempId,
    });

    final tempMessage = MessageModel(
      id: tempId,
      chatId: chatId,
      senderId: senderId,
      text: text,
      timestamp: DateTime.now(),
    );

    _messages[chatId] ??= [];
    _messages[chatId] = List.from(_messages[chatId]!)..add(tempMessage);
    notifyListeners();
  }

  Future<void> sendFile({
    required String chatId,
    required String senderId,
    required File file,
  }) async {
    final String tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final String fileName = file.path.split('/').last;

    // 1. Создаем временное сообщение
    final tempMessage = MessageModel(
      id: tempId,
      chatId: chatId,
      senderId: senderId,
      text: 'Файл: $fileName',
      type: 'file',
      timestamp: DateTime.now(),
    );

    _messages[chatId] ??= [];
    _messages[chatId] = List.from(_messages[chatId]!)..add(tempMessage);
    _uploadProgress[tempId] = 0.01; // Начало загрузки
    notifyListeners();

    try {
      final dio = dio_pkg.Dio();
      final formData = dio_pkg.FormData.fromMap({
        'file': await dio_pkg.MultipartFile.fromFile(file.path, filename: fileName),
      });

      final response = await dio.post(
        '${ApiConfig.apiUrl}/chat/upload',
        data: formData,
        options: dio_pkg.Options(
          headers: {'Authorization': 'Bearer $_authToken'},
        ),
        onSendProgress: (sent, total) {
          if (total != -1) {
            _uploadProgress[tempId] = sent / total;
            notifyListeners();
          }
        },
      );

      if (response.statusCode == 200) {
        final data = response.data;
        final fileUrl = data['url'];

        // 2. После загрузки отправляем сообщение через сокет
        _socketService!.socket!.emit('message:send', {
          'chatId': chatId,
          'senderId': senderId,
          'text': fileUrl, // Ссылка на файл
          'type': 'file',
          'tempId': tempId,
        });

        debugPrint('✅ Файл загружен: $fileUrl');
      }
    } catch (e) {
      debugPrint('❌ Ошибка загрузки файла: $e');
      _uploadProgress.remove(tempId);
      // Можно пометить сообщение как ошибочное
      notifyListeners();
    }
  }

  void _listenToMessages() {
    if (_isListening || _socketService?.socket == null) return;
    _isListening = true;

    final socket = _socketService!.socket!;

    // Удаляем старые слушатели перед добавлением новых
    socket.off('message:received');
    socket.off('message:sent');
    socket.off('user:status');

    socket.on('message:received', (data) {
      try {
        debugPrint('📩 Получено message:received: ${jsonEncode(data)}');
        final message = MessageModel.fromJson(data);
        // Если сообщение от нас самих, игнорируем его в received,
        // так как оно придет в message:sent или уже есть как temp
        if (message.senderId.isNotEmpty && message.senderId.toString() == _currentUserId.toString()) {
          debugPrint('ℹ️ Игнорирую broadcast собственного сообщения в received');
          return;
        }
        _handleMessageUpdate(message, tempId: data['tempId']?.toString());
      } catch (e) {
        debugPrint('❌ Ошибка парсинга сообщения (received): $e');
      }
    });

    socket.on('message:sent', (data) {
      try {
        debugPrint('📨 Получено message:sent: ${jsonEncode(data)}');
        final message = MessageModel.fromJson(data);
        _handleMessageUpdate(message, tempId: data['tempId']?.toString());
      } catch (e) {
        debugPrint('❌ Ошибка подтверждения сообщения (sent): $e');
      }
    });

    socket.on('user:status', (data) {
      try {
        final userId = data['userId'];
        final online = data['online'] ?? false;
        bool changed = false;
        for (var chat in _chats) {
          for (int i = 0; i < chat.participants.length; i++) {
            if (chat.participants[i].id == userId) {
              chat.participants[i] = chat.participants[i].copyWith(online: online);
              changed = true;
            }
          }
        }
        if (changed) notifyListeners();
      } catch (e) {
        debugPrint('❌ Ошибка обновления статуса: $e');
      }
    });
  }

  void _handleMessageUpdate(MessageModel message, {String? tempId}) {
    final chatId = message.chatId;
    _messages[chatId] ??= [];

    final list = List<MessageModel>.from(_messages[chatId]!);

    // 1. Ищем по реальному ID
    int existingIndex = list.indexWhere(
      (m) => m.id.toString() == message.id.toString()
    );

    if (existingIndex >= 0) {
      // Сообщение уже есть (возможно, подтверждение temp или просто дубль)
      // Обновляем только если оно было временным или изменилось
      if (list[existingIndex].id.startsWith('temp_') || list[existingIndex].text != message.text) {
        list[existingIndex] = message;
        debugPrint('📝 Обновлено существующее сообщение: ${message.id}');
      } else {
        // Сообщение идентично, ничего не делаем
        return;
      }
    } else {
      // 2. Ищем по tempId
      int tempIndex = -1;
      if (tempId != null) {
        tempIndex = list.indexWhere((m) => m.id == tempId);
      }

      // 3. Если по tempId не нашли, ищем по контенту или просто последнее временное сообщение от нас
      if (tempIndex == -1) {
        tempIndex = list.lastIndexWhere(
          (m) => m.id.startsWith('temp_') &&
                 (message.text.isEmpty || m.text == message.text || message.text == 'О')
        );
      }

      if (tempIndex >= 0) {
        // Если пришло подтверждение без текста, сохраняем старый текст
        final finalMessage = message.text.isEmpty
            ? MessageModel(
                id: message.id,
                chatId: message.chatId,
                senderId: _currentUserId, // Мы знаем, что это наше сообщение
                text: list[tempIndex].text,
                timestamp: message.timestamp,
                type: message.type,
                read: message.read,
              )
            : message;

        debugPrint('✅ Замена временного сообщения на постоянное (${finalMessage.id})');
        list[tempIndex] = finalMessage;
      } else {
        // Это действительно новое сообщение
        debugPrint('🆕 Добавлено новое сообщение от ${message.senderId}: ${message.id}');
        list.add(message);
      }
    }

    _messages[chatId] = list;
    _updateChatInList(message);
    notifyListeners();
  }

  void _updateChatInList(MessageModel message) {
    final chatIndex = _chats.indexWhere((c) => c.id == message.chatId);
    if (chatIndex >= 0) {
      final updatedChat = _chats[chatIndex].copyWith(lastMessage: message);
      _chats.removeAt(chatIndex);
      _chats.insert(0, updatedChat);
    } else {
      loadChats();
    }
  }

  Future<List<UserModel>> searchUsers(String query) async {
    if (query.length < 2) return [];
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.apiUrl}/user/search?query=$query'),
        headers: _getHeaders(),
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((json) => UserModel.fromJson(json)).toList();
      }
    } catch (e) {
      debugPrint('❌ Ошибка поиска: $e');
    }
    return [];
  }
}
