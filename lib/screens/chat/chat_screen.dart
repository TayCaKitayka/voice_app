import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/chat_service.dart';
import '../../models/chat_model.dart';
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

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    await widget.chatService.loadMessages(widget.chat.id);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() {
    if (_messageController.text.trim().isEmpty) return;

    widget.chatService.sendMessage(
      chatId: widget.chat.id,
      senderId: widget.currentUserId,
      text: _messageController.text.trim(),
    );

    _messageController.clear();
    _scrollToBottom();
  }

  void _startVideoCall() {
    final otherUser = widget.chat.getOtherParticipant(widget.currentUserId);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen(
          otherUser: otherUser,
          isIncoming: false,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final otherUser = widget.chat.getOtherParticipant(widget.currentUserId);

    return AnimatedBuilder(
      animation: widget.chatService,
      builder: (context, _) {
        final messages = widget.chatService.getMessages(widget.chat.id);

        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                CircleAvatar(
                  child: Text(otherUser.username[0].toUpperCase()),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        otherUser.username,
                        style: const TextStyle(fontSize: 16),
                      ),
                      Text(
                        otherUser.online ? '🟢 В сети' : '⚫ Не в сети',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.videocam),
                onPressed: _startVideoCall,
                tooltip: 'Видеозвонок',
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: messages.isEmpty
                    ? const Center(
                        child: Text(
                          'Нет сообщений\nНачните разговор',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(8),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final message = messages[index];
                          final isMe =
                              message.senderId == widget.currentUserId;

                          return Align(
                            alignment: isMe
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.7,
                              ),
                              decoration: BoxDecoration(
                                color: isMe
                                    ? Colors.blue
                                    : Colors.grey[300],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: isMe
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    message.text,
                                    style: TextStyle(
                                      color: isMe
                                          ? Colors.white
                                          : Colors.black,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    DateFormat('HH:mm')
                                        .format(message.timestamp),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: isMe
                                          ? Colors.white70
                                          : Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        decoration: InputDecoration(
                          hintText: 'Сообщение...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                        maxLines: null,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FloatingActionButton(
                      mini: true,
                      onPressed: _sendMessage,
                      child: const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}