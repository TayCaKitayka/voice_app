import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart' as dio_pkg;
import 'dart:io';
import '../../services/chat_service.dart';
import '../../services/call_service.dart';
import '../../services/auth_service.dart';
import '../../models/chat_model.dart';
import '../../models/message_model.dart';
import '../../config/api_config.dart';
import '../call/call_screen.dart';

class ChatScreen extends StatefulWidget {
  final ChatModel chat;
  final ChatService chatService;
  final String currentUserId;

  const ChatScreen({
    super.key,
    required this.chat,
    required this.chatService,
    required this.currentUserId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  int _callHours = 0;
  int _callMinutes = 5;
  int _callSeconds = 0;

  bool _callScreenOpened = false;

  late CallService _callService;

  @override
  void initState() {
    super.initState();
    _callService = context.read<CallService>();
    _callService.addListener(_callListener);
    _loadMessages();
  }

  void _callListener() {
    if (!mounted) return;
    final callService = _callService;

    if (callService.isInCall && !_callScreenOpened) {
      _callScreenOpened = true;

      final otherUser =
          widget.chat.getOtherParticipant(widget.currentUserId);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CallScreen(
            otherUser: otherUser,
            isIncoming: false,
          ),
        ),
      ).then((_) => _callScreenOpened = false);
    }
  }

  @override
  void dispose() {
    _callService.removeListener(_callListener);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    await widget.chatService.loadMessages(widget.chat.id);
    _scrollToBottom(immediate: true);
  }

  void _scrollToBottom({bool immediate = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        if (immediate) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        } else {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      }
    });
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    widget.chatService.sendMessage(
      chatId: widget.chat.id,
      senderId: widget.currentUserId,
      text: text,
    );

    _messageController.clear();
    _scrollToBottom();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      await widget.chatService.sendFile(
        chatId: widget.chat.id,
        senderId: widget.currentUserId,
        file: file,
      );
    }
  }

  void _startVideoCall() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Длительность звонка'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Выберите длительность'),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildTimeInput("Ч", (v) => _callHours = v),
                _buildTimeInput("М", (v) => _callMinutes = v),
                _buildTimeInput("С", (v) => _callSeconds = v),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final callService = context.read<CallService>();
              final authService = context.read<AuthService>();

              await callService.initiateCall(
                callerId: authService.currentUser!.id,
                receiverId: widget.chat
                    .getOtherParticipant(widget.currentUserId)
                    .id,
                isVideo: true,
                hours: _callHours,
                minutes: _callMinutes,
                seconds: _callSeconds,
              );
            },
            child: const Text('Позвонить'),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeInput(String label, Function(int) onChanged) {
    return SizedBox(
      width: 60,
      child: TextField(
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label),
        onChanged: (v) {
          int parsed = int.tryParse(v) ?? 0;
          onChanged(parsed);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final otherUser = widget.chat.getOtherParticipant(widget.currentUserId);

    return Scaffold(
      appBar: AppBar(
        title: Text(otherUser.username),
        actions: [
          IconButton(
            icon: const Icon(Icons.videocam),
            onPressed: _startVideoCall,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Selector<ChatService, List<MessageModel>>(
              selector: (_, service) => service.getMessages(widget.chat.id),
              shouldRebuild: (prev, next) {
                if (prev.length != next.length) return true;
                if (next.isEmpty) return false;
                return prev.last.id != next.last.id;
              },
              builder: (context, messages, _) {
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                  itemCount: messages.length,
                  cacheExtent: 1000, // Улучшает плавность скролла
                  itemBuilder: (_, index) {
                    return MessageBubble(
                      message: messages[index],
                      isMe: messages[index].senderId.toString() == widget.currentUserId.toString(),
                    );
                  },
                );
              },
            ),
          ),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.add_circle_outline, color: Colors.blue),
              onPressed: _pickFile,
            ),
            Expanded(
              child: TextField(
                controller: _messageController,
                textCapitalization: TextCapitalization.sentences,
                maxLines: null,
                decoration: const InputDecoration(
                  hintText: 'Сообщение',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.send, color: Colors.blue),
              onPressed: _sendMessage,
            )
          ],
        ),
      ),
    );
  }
}

class MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMe;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
  });

  Future<void> _handleFileTap(BuildContext context) async {
    if (message.type != 'file') return;

    final url = message.text.startsWith('http')
        ? message.text
        : '${ApiConfig.apiUrl}${message.text}';

    try {
      // Показываем индикатор подготовки
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Подготовка файла...'), duration: Duration(seconds: 1)),
      );

      final tempDir = await getTemporaryDirectory();
      final fileName = message.text.split('/').last;
      final filePath = '${tempDir.path}/$fileName';
      final file = File(filePath);

      // Скачиваем файл, если его нет
      if (!await file.exists()) {
        final dio = dio_pkg.Dio();
        await dio.download(url, filePath);
      }

      // Открываем Share Sheet (на iOS это позволит сохранить в Файлы или Фото)
      final xFile = XFile(filePath);
      await Share.shareXFiles([xFile], text: fileName);

    } catch (e) {
      debugPrint('❌ Ошибка при открытии файла: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось открыть файл: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: message.type == 'file' ? () => _handleFileTap(context) : null,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isMe ? Colors.blue : Colors.grey[300],
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isMe ? 16 : 0),
              bottomRight: Radius.circular(isMe ? 0 : 16),
            ),
          ),
          child: IntrinsicWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message.type == 'file')
                  _buildFileContent(context)
                else
                  Text(
                    message.text,
                    style: TextStyle(
                      color: isMe ? Colors.white : Colors.black87,
                      fontSize: 15,
                    ),
                  ),
                const SizedBox(height: 2),
                Align(
                  alignment: Alignment.bottomRight,
                  child: Text(
                    DateFormat('HH:mm').format(message.timestamp),
                    style: TextStyle(
                      fontSize: 10,
                      color: isMe ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFileContent(BuildContext context) {
    return Consumer<ChatService>(
      builder: (context, chatService, _) {
        final progress = chatService.getFileProgress(message.id);
        final isUploading = progress > 0 && progress < 1.0;

        return Column(
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.insert_drive_file,
                  color: isMe ? Colors.white : Colors.blue,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    message.text.split('/').last, // Показываем только имя файла
                    style: TextStyle(
                      color: isMe ? Colors.white : Colors.black87,
                      decoration: TextDecoration.underline,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (isUploading) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.white24,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isMe ? Colors.white : Colors.blue,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${(progress * 100).toInt()}%',
                style: TextStyle(fontSize: 10, color: isMe ? Colors.white70 : Colors.black54),
              ),
            ],
          ],
        );
      },
    );
  }
}
