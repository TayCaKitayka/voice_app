import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/api_config.dart';
import '../models/chat_model.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';
import 'socket_service.dart';

class ChatService extends ChangeNotifier {
  SocketService? _socketService;
  String _authToken = '';

  List<ChatModel> _chats = [];
  final Map<String, List<MessageModel>> _messages = {};

  List<ChatModel> get chats => _chats;

  void init({
    required String token,
    required SocketService socketService,
  }) {
    _authToken = token;
    _socketService = socketService;
    _listenToMessages();
    debugPrint('✅ ChatService инициализирован');
    notifyListeners();
  }

  void reset() {
    _authToken = '';
    _socketService = null;
    _chats = [];
    _messages.clear();
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
    if (_authToken.isEmpty) {
      debugPrint('⚠️ Нет токена для загрузки чатов');
      return;
    }

    try {
      debugPrint('📥 Загрузка чатов...');
      final response = await http.get(
        Uri.parse('${ApiConfig.apiUrl}/chat/list'),
        headers: _getHeaders(),
      );

      debugPrint('📊 Статус ответа: ${response.statusCode}');
      debugPrint('📄 Тело ответа: ${response.body}');

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        _chats = data.map((json) => ChatModel.fromJson(json)).toList();
        debugPrint('✅ Загружено ${_chats.length} чатов');
        notifyListeners();
      }
    } catch (e) {
      debugPrint('❌ Ошибка загрузки чатов: $e');
    }
  }

  Future<ChatModel?> createOrGetChat(String participantId) async {
    try {
      debugPrint('📝 Создание чата с $participantId');
      final response = await http.post(
        Uri.parse('${ApiConfig.apiUrl}/chat/create'),
        headers: _getHeaders(),
        body: jsonEncode({'participantId': participantId}),
      );

      debugPrint('📊 Статус ответа: ${response.statusCode}');
      debugPrint('📄 Тело ответа: ${response.body}');

      if (response.statusCode == 200) {
        final chat = ChatModel.fromJson(jsonDecode(response.body));
        final index = _chats.indexWhere((c) => c.id == chat.id);
        if (index >= 0) {
          _chats[index] = chat;
        } else {
          _chats.insert(0, chat);
        }
        debugPrint('✅ Чат создан/получен: ${chat.id}');
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
      debugPrint('📥 Загрузка сообщений для чата $chatId');
      final response = await http.get(
        Uri.parse('${ApiConfig.apiUrl}/chat/$chatId/messages'),
        headers: _getHeaders(),
      );

      debugPrint('📊 Статус: ${response.statusCode}');

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final messages =
            data.map((json) => MessageModel.fromJson(json)).toList();
        _messages[chatId] = messages;
        debugPrint('✅ Загружено ${messages.length} сообщений');
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
      debugPrint('❌ Socket не подключен!');
      return;
    }

    debugPrint('📤 Отправка сообщения в чат $chatId: $text');

    _socketService!.socket!.emit('message:send', {
      'chatId': chatId,
      'senderId': senderId,
      'text': text,
      'type': 'text',
    });

    final tempMessage = MessageModel(
      id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
      chatId: chatId,
      senderId: senderId,
      text: text,
      timestamp: DateTime.now(),
    );

    _messages[chatId] ??= [];
    _messages[chatId]!.add(tempMessage);
    notifyListeners();

    debugPrint('✅ Временное сообщение добавлено');
  }

  void _listenToMessages() {
    debugPrint('👂 Начало прослушивания сообщений...');

    _socketService?.socket?.on('message:received', (data) {
      debugPrint('📩 Получено сообщение: $data');
      try {
        final message = MessageModel.fromJson(data);
        _messages[message.chatId] ??= [];
        _messages[message.chatId]!.add(message);
        notifyListeners();
        debugPrint('✅ Сообщение добавлено в чат ${message.chatId}');
      } catch (e) {
        debugPrint('❌ Ошибка парсинга сообщения: $e');
      }
    });

    _socketService?.socket?.on('message:sent', (data) {
      debugPrint('✉️ Сообщение отправлено: $data');
      try {
        final chatId = data['chatId'];
        final tempMessages = _messages[chatId];

        if (tempMessages != null && tempMessages.isNotEmpty) {
          final lastMessage = tempMessages.last;
          if (lastMessage.id.startsWith('temp_')) {
            tempMessages.removeLast();
            tempMessages.add(MessageModel(
              id: data['_id'],
              chatId: chatId,
              senderId: lastMessage.senderId,
              text: lastMessage.text,
              timestamp: DateTime.parse(data['timestamp']),
            ));
            notifyListeners();
            debugPrint('✅ Временное сообщение заменено на реальное');
          }
        }
      } catch (e) {
        debugPrint('❌ Ошибка обработки отправленного сообщения: $e');
      }
    });

    _socketService?.socket?.on('user:status', (data) {
      debugPrint('👤 Статус пользователя: $data');
      try {
        final userId = data['userId'];
        final online = data['online'] ?? false;

        for (var chat in _chats) {
          for (int i = 0; i < chat.participants.length; i++) {
            if (chat.participants[i].id == userId) {
              chat.participants[i] =
                  chat.participants[i].copyWith(online: online);
              debugPrint('✅ Обновлен статус пользователя $userId: $online');
            }
          }
        }
        notifyListeners();
      } catch (e) {
        debugPrint('❌ Ошибка обновления статуса: $e');
      }
    });
  }

  Future<List<UserModel>> searchUsers(String query) async {
    if (query.length < 2) return [];

    try {
      debugPrint('🔍 Поиск пользователей: $query');
      final response = await http.get(
        Uri.parse('${ApiConfig.apiUrl}/user/search?query=$query'),
        headers: _getHeaders(),
      );

      debugPrint('📊 Статус: ${response.statusCode}');

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final users = data.map((json) => UserModel.fromJson(json)).toList();
        debugPrint('✅ Найдено ${users.length} пользователей');
        return users;
      }
    } catch (e) {
      debugPrint('❌ Ошибка поиска: $e');
    }
    return [];
  }
}