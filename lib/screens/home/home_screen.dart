import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/socket_service.dart';
import '../../services/chat_service.dart';
import '../../services/call_service.dart';
import '../../models/user_model.dart';
import '../auth/login_screen.dart';
import '../call/call_screen.dart';
import 'chat_list_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _listenForIncomingCalls();
  }

  void _listenForIncomingCalls() {
    final socketService = context.read<SocketService>();

    socketService.socket?.on('call:incoming', (data) {
      debugPrint('📞 Входящий звонок: $data');
      _showIncomingCallDialog(data);
    });
  }

  void _showIncomingCallDialog(Map<String, dynamic> callData) {
    final callId = callData['callId'];
    final callerId = callData['callerId'];
    final isVideo = callData['isVideo'] ?? true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('📞 Входящий звонок'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam, size: 64, color: Colors.blue),
            const SizedBox(height: 16),
            Text(
              isVideo ? 'Видеозвонок' : 'Аудиозвонок',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              context.read<CallService>().rejectCall(callId);
              Navigator.pop(context);
            },
            child: const Text(
              'Отклонить',
              style: TextStyle(color: Colors.red),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);

              final callerUser = UserModel(
                id: callerId,
                username: 'Собеседник',
                email: '',
              );

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CallScreen(
                    otherUser: callerUser,
                    isIncoming: true,
                    callId: callId,
                  ),
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Принять'),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    final socketService = context.read<SocketService>();
    final authService = context.read<AuthService>();
    final chatService = context.read<ChatService>();
    final callService = context.read<CallService>();
    final navigator = Navigator.of(context);

    socketService.disconnect();
    chatService.reset();
    callService.reset();
    await authService.logout();

    if (!mounted) return;

    navigator.pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  void _showSearchDialog() {
    final chatService = context.read<ChatService>();

    showDialog(
      context: context,
      builder: (_) => SearchUsersDialog(chatService: chatService),
    );
  }

  @override
  Widget build(BuildContext context) {
    final socketService = context.watch<SocketService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messenger'),
        actions: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Center(
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: socketService.isConnected
                      ? Colors.green
                      : Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: _currentIndex == 0
          ? const ChatListScreen()
          : const ProfileTab(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.chat),
            label: 'Чаты',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Профиль',
          ),
        ],
      ),
      floatingActionButton: _currentIndex == 0
          ? FloatingActionButton(
              onPressed: _showSearchDialog,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}

class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 60,
            child: Text(
              user?.username[0].toUpperCase() ?? 'U',
              style: const TextStyle(fontSize: 40),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            user?.username ?? '',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            user?.email ?? '',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class SearchUsersDialog extends StatefulWidget {
  final ChatService chatService;

  const SearchUsersDialog({
    super.key,
    required this.chatService,
  });

  @override
  State<SearchUsersDialog> createState() => _SearchUsersDialogState();
}

class _SearchUsersDialogState extends State<SearchUsersDialog> {
  final _searchController = TextEditingController();
  List<UserModel> _users = [];
  bool _isLoading = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.length < 2) {
      setState(() => _users = []);
      return;
    }

    setState(() => _isLoading = true);

    final users = await widget.chatService.searchUsers(query);

    if (!mounted) return;

    setState(() {
      _users = users;
      _isLoading = false;
    });
  }

  Future<void> _openChat(UserModel user) async {
    await widget.chatService.createOrGetChat(user.id);
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Найти пользователя',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Введите имя или email...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: _search,
            ),
            const SizedBox(height: 16),
            if (_isLoading)
              const CircularProgressIndicator()
            else if (_users.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('Начните вводить имя пользователя'),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _users.length,
                  itemBuilder: (context, index) {
                    final user = _users[index];
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(user.username[0].toUpperCase()),
                      ),
                      title: Text(user.username),
                      subtitle: Text(user.email),
                      trailing: Icon(
                        Icons.circle,
                        size: 12,
                        color: user.online ? Colors.green : Colors.grey,
                      ),
                      onTap: () => _openChat(user),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}