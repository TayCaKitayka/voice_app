import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../config/api_config.dart';
import '../models/user_model.dart';

class AuthService extends ChangeNotifier {
  UserModel? _currentUser;
  String? _token;
  bool _isLoading = false;

  UserModel? get currentUser => _currentUser;
  String? get token => _token;
  bool get isAuthenticated => _token != null && _currentUser != null;
  bool get isLoading => _isLoading;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token');
    
    if (_token != null) {
      final userJson = prefs.getString('user');
      if (userJson != null) {
        _currentUser = UserModel.fromJson(jsonDecode(userJson));
      }
    }
    notifyListeners();
  }

  Future<String?> register({
    required String username,
    required String email,
    required String password,
  }) async {
    try {
      _isLoading = true;
      notifyListeners();

      debugPrint('📝 Отправляю регистрацию на ${ApiConfig.apiUrl}/auth/register');
      debugPrint('📋 Данные: username=$username, email=$email');

      final response = await http.post(
        Uri.parse('${ApiConfig.apiUrl}/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'email': email,
          'password': password,
        }),
      );

      debugPrint('📊 Ответ сервера: ${response.statusCode}');
      debugPrint('📄 Тело: ${response.body}');

      _isLoading = false;

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        _token = data['token'];
        _currentUser = UserModel.fromJson(data['user']);

        await _saveAuthData();
        notifyListeners();
        debugPrint('✅ Регистрация успешна');
        return null; // Успех
      } else {
        final error = jsonDecode(response.body);
        final errorMsg = error['error'] ?? 'Ошибка регистрации';
        debugPrint('❌ Ошибка: $errorMsg');
        return errorMsg;
      }
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      debugPrint('❌ Исключение при регистрации: $e');
      return 'Ошибка подключения: $e';
    }
  }

  Future<String?> login({
    required String email,
    required String password,
  }) async {
    try {
      _isLoading = true;
      notifyListeners();

      debugPrint('🔐 Отправляю логин на ${ApiConfig.apiUrl}/auth/login');
      debugPrint('📋 Email: $email');

      final response = await http.post(
        Uri.parse('${ApiConfig.apiUrl}/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      );

      debugPrint('📊 Ответ сервера: ${response.statusCode}');
      debugPrint('📄 Тело: ${response.body}');

      _isLoading = false;
      notifyListeners();

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _token = data['token'];
        _currentUser = UserModel.fromJson(data['user']);

        await _saveAuthData();
        notifyListeners();
        debugPrint('✅ Логин успешен');
        return null; // Успех
      } else {
        final error = jsonDecode(response.body);
        final errorMsg = error['error'] ?? 'Неверный email или пароль';
        debugPrint('❌ Ошибка: $errorMsg');
        return errorMsg;
      }
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      debugPrint('❌ Исключение при логине: $e');
      return 'Ошибка подключения: $e';
    }
  }

  Future<void> logout() async {
    _token = null;
    _currentUser = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    notifyListeners();
    debugPrint('👋 Выход выполнен');
  }

  Future<void> _saveAuthData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', _token!);
    await prefs.setString('user', jsonEncode(_currentUser!.toJson()));
    debugPrint('💾 Данные сохранены в SharedPreferences');
  }

  Map<String, String> getAuthHeaders() {
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $_token',
    };
  }
}