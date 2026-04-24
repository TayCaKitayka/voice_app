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
import '../search/user_search_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  SocketService? _socketService;

  @override
  void initState() {
    super.initState();
    // Откладываем до первого кадра — context уже готов
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _listenIncoming();
    });
  }

  @override
  void dispose() {
    // Отписываемся от события при уничтожении виджета
    _socketService?.socket?.off('call:incoming', _handleIncomingCall);
    super.dispose();
  }

  void _listenIncoming() {
    _socketService = context.read<SocketService>();
    _socketService?.socket?.on('call:incoming', _handleIncomingCall);
  }

  void _handleIncomingCall(dynamic data) {
    if (!mounted) return;

    final callId = data['callId']?.toString() ?? '';
    final callerId = data['callerId']?.toString() ?? '';
    final callerName = data['callerName']?.toString() ?? 'Собеседник';
    final isVideo = data['isVideo'] as bool? ?? true;
    final duration = data['duration'] as int? ?? 300;

    // Сохраняем callService до входа в builder
    final callService = context.read<CallService>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Входящий звонок'),
        content: Text(
          '$callerName ${isVideo ? '(видео)' : '(аудио)'}',
        ),
        actions: [
          TextButton(
            onPressed: () {
              callService.rejectCall(callId);
              Navigator.pop(dialogContext);
            },
            child: const Text(
              'Отклонить',
              style: TextStyle(color: Colors.red),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              if (!mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CallScreen(
                    otherUser: UserModel(
                      id: callerId,
                      username: callerName,
                      email: '',
                    ),
                    isIncoming: true,
                    isVideo: isVideo,
                    callId: callId,
                    durationSeconds: duration,
                  ),
                ),
              );
            },
            child: const Text('Принять'),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    final auth = context.read<AuthService>();
    final socket = context.read<SocketService>();
    final chat = context.read<ChatService>();
    final call = context.read<CallService>();
    final navigator = Navigator.of(context);

    socket.disconnect();
    chat.reset();
    call.reset();
    await auth.logout();

    if (!mounted) return;

    navigator.pushReplacement(
      MaterialPageRoute(
        builder: (_) => const LoginScreen(),
      ),
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
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Icon(
              Icons.circle,
              size: 12,
              color: socketService.isConnected
                  ? Colors.green
                  : Colors.red,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: 'Выйти',
          ),
        ],
      ),
      body: _currentIndex == 0
          ? const ChatListScreen()
          : const Center(child: Text('Profile')),
      floatingActionButton: _currentIndex == 0
          ? FloatingActionButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const UserSearchScreen(),
                  ),
                );
              },
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
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
    );
  }
}