import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../services/chat_service.dart';
import '../../services/auth_service.dart';
import '../chat/chat_screen.dart';

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final chatService = context.watch<ChatService>();
    final authService = context.read<AuthService>();

    if (authService.currentUser == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final currentUserId = authService.currentUser!.id;
    final chats = chatService.chats;

    if (chats.isEmpty) {
      return const Center(
        child: Text(
          'Нет чатов.\nНажмите + чтобы начать общение',
          textAlign: TextAlign.center,
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => chatService.loadChats(),
      child: ListView.builder(
        itemCount: chats.length,
        itemBuilder: (context, index) {
          final chat = chats[index];
          final otherUser = chat.getOtherParticipant(currentUserId);
          final lastMessage = chat.lastMessage;

          return ListTile(
            leading: Stack(
              children: [
                CircleAvatar(
                  child: Text(otherUser.username[0].toUpperCase()),
                ),
                if (otherUser.online)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            title: Text(otherUser.username),
            subtitle: lastMessage != null
                ? Text(
                    lastMessage.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                : const Text('Нет сообщений'),
            trailing: lastMessage != null
                ? Text(
                    DateFormat('HH:mm').format(lastMessage.timestamp),
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                : null,
            onTap: () {
              // Передаём chatService напрямую
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatScreen(
                    chat: chat,
                    chatService: chatService,
                    currentUserId: currentUserId,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}