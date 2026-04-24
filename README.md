# Messenger App (Flutter + Node.js)

Мессенджер на Flutter с чатами, отправкой файлов и видео/аудио-звонками (WebRTC). Бэкенд на Node.js/Express + MongoDB, realtime через Socket.IO.

## Возможности

- Регистрация/логин по JWT
- Список чатов и история сообщений
- Realtime-сообщения через Socket.IO
- Поиск пользователей
- Отправка файлов (upload на сервер + сообщение-ссылка)
- Видео/аудио-звонки (WebRTC signalling через Socket.IO, таймер длительности)
- Статусы онлайн/оффлайн и `lastSeen`

## Структура

- `lib/` — Flutter-приложение (экраны, сервисы, модели)
- `messenger-backend/messenger-backend/` — Node.js бэкенд (Express, Socket.IO, Mongoose)

## Требования

- Flutter SDK (Dart >= 3.0)
- Node.js (рекомендуется LTS) и npm
- MongoDB (локально или удалённо)

## Быстрый старт (Backend)

1. Перейдите в папку бэкенда:

```bash
cd messenger-backend/messenger-backend
```

2. Установите зависимости:

```bash
npm install
```

3. Создайте `.env` на основе примера:

```bash
cp .env.example .env
```

4. Запустите MongoDB и сервер:

```bash
node server.js
```

По умолчанию сервер стартует на `PORT=8080`.

Проверка здоровья:

- `GET http://localhost:8080/` — вернет JSON со статусом и метриками `activeUsers/activeCalls`.

## Быстрый старт (Flutter-клиент)

1. Установите зависимости:

```bash
flutter pub get
```

2. Укажите адрес сервера в `lib/config/api_config.dart`.

Важно:
- На реальном устройстве `localhost` не сработает, нужно указать IP машины, где запущен бэкенд (например `http://192.168.0.10:8080`).
- Для Android Emulator можно использовать `http://10.0.2.2:8080`.

3. Запуск:

```bash
flutter run
```

## API (кратко)

Базовый префикс: `/api`.

### Auth
- `POST /api/auth/register` — `{ username, email, password }`
- `POST /api/auth/login` — `{ email, password }`

Ответ содержит `token` и `user`.

### Users
- `GET /api/user/search?query=...` — поиск по username/email (минимум 2 символа)
- `GET /api/user/:userId` — профиль пользователя

### Chats
- `GET /api/chat/list` — список чатов текущего пользователя
- `POST /api/chat/create` — `{ participantId }` (создает 1-1 чат или возвращает существующий)
- `GET /api/chat/:chatId/messages?limit=50&skip=0` — сообщения
- `POST /api/chat/upload` — multipart `file`, ответ: `{ url, filename, mimetype, size }`

Авторизация:
- Для защищенных маршрутов нужен заголовок `Authorization: Bearer <token>`.

## Socket.IO события (кратко)

Клиент подключается к `ApiConfig.socketUrl`.

- `user:online` (client -> server): `userId`
- `user:status` (server -> all): `{ userId, online }`

Сообщения:
- `message:send` (client -> server): `{ chatId, senderId, text, type: "text"|"file", tempId }`
- `message:received` (server -> receiver): данные сообщения
- `message:sent` (server -> sender): подтверждение отправителю (включая `tempId`)

Звонки:
- `call:initiate` (client -> server): `{ callerId, receiverId, isVideo, duration }`
- `call:incoming` (server -> receiver): `{ callId, callerId, isVideo, duration }`
- `call:accept` / `call:reject` / `call:end`

WebRTC signalling:
- `webrtc:offer`, `webrtc:answer`, `webrtc:ice-candidate`

## Файлы и загрузки

Сервер сохраняет файлы в `messenger-backend/messenger-backend/uploads/` и раздаёт их по маршруту `/uploads`.
Сообщение типа `file` содержит `text` как URL вида `/uploads/<filename>`.

## Заметки и ограничения

- Для продакшена WebRTC обычно требует TURN-сервер (STUN может быть недостаточно за NAT).
- Для iOS/macOS плагины (`flutter_webrtc`, `permission_handler`, `open_filex`) могут требовать настройки Pod’ов; при проблемах попробуйте:

```bash
cd ios
pod install
```

## License

Проект учебный/проектный; лицензия не задана (по умолчанию “all rights reserved”).
