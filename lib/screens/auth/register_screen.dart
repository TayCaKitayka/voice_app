import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/socket_service.dart';
import '../../services/chat_service.dart';
import '../../services/call_service.dart';
import '../home/home_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _validateUsername(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Введите имя пользователя';
    }
    if (value.trim().length < 3) {
      return 'Минимум 3 символа';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Введите email';
    }
    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
    if (!emailRegex.hasMatch(value.trim())) {
      return 'Некорректный email';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Введите пароль';
    }
    if (value.length < 6) {
      return 'Минимум 6 символов';
    }
    return null;
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    final authService = context.read<AuthService>();
    final socketService = context.read<SocketService>();
    final chatService = context.read<ChatService>();
    final callService = context.read<CallService>();
    final navigator = Navigator.of(context);

    final error = await authService.register(
      username: _usernameController.text.trim(),
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );

    if (!mounted) return;

    if (error == null) {
      final userId = authService.currentUser!.id;

      socketService.connect(userId);
      chatService.init(
        token: authService.token!,
        socketService: socketService,
      );
      callService.init(
        socketService: socketService,
        currentUserId: userId,
      );

      await chatService.loadChats();

      if (!mounted) return;

      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();

    return Scaffold(
      appBar: AppBar(title: const Text('Регистрация')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                const Icon(Icons.person_add, size: 80, color: Colors.blue),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _usernameController,
                  keyboardType: TextInputType.name,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Имя пользователя',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                  validator: _validateUsername,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
                  ),
                  validator: _validateEmail,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Пароль',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                  validator: _validatePassword,
                  onFieldSubmitted: (_) => _register(),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: authService.isLoading ? null : _register,
                    child: authService.isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            'Зарегистрироваться',
                            style: TextStyle(fontSize: 16),
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
}