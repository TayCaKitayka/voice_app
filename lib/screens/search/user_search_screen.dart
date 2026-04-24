import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/chat_service.dart';
import '../../services/auth_service.dart';
import '../../models/user_model.dart';
import '../chat/chat_screen.dart';

class UserSearchScreen extends StatefulWidget {
  const UserSearchScreen({super.key});

  @override
  State<UserSearchScreen> createState() => _UserSearchScreenState();
}

class _UserSearchScreenState extends State<UserSearchScreen> {
  final _searchController = TextEditingController();
  List<UserModel> _searchResults = [];
  bool _isLoading = false;

  Future<void> _performSearch(String query) async {
    if (query.length < 2) {
      setState(() => _searchResults = []);
      return;
    }

    setState(() => _isLoading = true);
    final results = await context.read<ChatService>().searchUsers(query);
    if (mounted) {
      setState(() {
        _searchResults = results;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chatService = context.read<ChatService>();
    final authService = context.read<AuthService>();
    final currentUserId = authService.currentUser?.id ?? '';

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Поиск пользователей...',
            border: InputBorder.none,
            hintStyle: TextStyle(color: Colors.white70),
          ),
          style: const TextStyle(color: Colors.white),
          onChanged: _performSearch,
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _searchResults.length,
              itemBuilder: (context, index) {
                final user = _searchResults[index];
                if (user.id == currentUserId) return const SizedBox.shrink();

                return ListTile(
                  leading: CircleAvatar(
                    child: Text(user.username[0].toUpperCase()),
                  ),
                  title: Text(user.username),
                  subtitle: Text(user.email),
                  onTap: () async {
                    final chat = await chatService.createOrGetChat(user.id);
                    if (chat != null && mounted) {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            chat: chat,
                            chatService: chatService,
                            currentUserId: currentUserId,
                          ),
                        ),
                      );
                    }
                  },
                );
              },
            ),
    );
  }
}
