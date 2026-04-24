import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/auth_service.dart';
import 'services/socket_service.dart';
import 'services/chat_service.dart';
import 'services/call_service.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/home_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => SocketService()),
        ChangeNotifierProvider(create: (_) => ChatService()),
        ChangeNotifierProvider(create: (_) => CallService()),
      ],
      child: MaterialApp(
        title: 'Messenger',
        theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
        darkTheme: ThemeData.dark(useMaterial3: true),
        themeMode: ThemeMode.system,
        home: const SplashScreen(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // ✅ Откладываем до первого кадра
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _init();
    });
  }

  Future<void> _init() async {
    final authService = context.read<AuthService>();
    await authService.init();
    await Future.delayed(const Duration(seconds: 1));

    if (!mounted) return;

    final isAuth = authService.isAuthenticated;

    if (isAuth) {
      final socketService = context.read<SocketService>();
      final chatService = context.read<ChatService>();
      final callService = context.read<CallService>();
      final userId = authService.currentUser!.id; // ✅ Получаем userId

      socketService.connect(userId);
      chatService.init(
        token: authService.token!,
        socketService: socketService,
        userId: userId, // ✅ Передаем userId для фильтрации собственных сообщений
      );
      callService.init(
        socketService: socketService,
        currentUserId: userId,
      );

      await chatService.loadChats();
    }

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => isAuth ? const HomeScreen() : const LoginScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.message_rounded, size: 100, color: Colors.blue),
            SizedBox(height: 24),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}