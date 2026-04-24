const express = require('express');
const http = require('http');
const socketIO = require('socket.io');
const mongoose = require('mongoose');
const cors = require('cors');
const dotenv = require('dotenv');
const { v4: uuidv4 } = require('uuid');
const multer = require('multer');
const path = require('path');
const fs = require('fs');

dotenv.config();

const app = express();

// Создаем папку uploads, если её нет
const uploadDir = path.join(__dirname, 'uploads');
if (!fs.existsSync(uploadDir)) {
  fs.mkdirSync(uploadDir);
}

// Настройка хранилища для файлов
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    cb(null, 'uploads/');
  },
  filename: (req, file, cb) => {
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
    cb(null, uniqueSuffix + path.extname(file.originalname));
  }
});

const upload = multer({ storage: storage });

const server = http.createServer(app);
const io = socketIO(server, {
  cors: { origin: '*', methods: ['GET', 'POST'] },
  pingTimeout: 60000,
  pingInterval: 25000,
});

app.use(cors());
app.use(express.json());
app.use('/uploads', express.static(path.join(__dirname, 'uploads')));

mongoose.connect(process.env.MONGODB_URI)
  .then(() => console.log('✅ MongoDB подключена'))
  .catch(err => console.error('❌ MongoDB ошибка:', err));

const User = require('./models/User');
const Message = require('./models/Message');
const Chat = require('./models/Chat');

app.use('/api/auth', require('./routes/auth'));
app.use('/api/chat', require('./routes/chat'));
app.use('/api/user', require('./routes/user'));

// Эндпоинт для загрузки файлов
app.post('/api/chat/upload', upload.single('file'), (req, res) => {
  if (!req.file) {
    return res.status(400).json({ error: 'Файл не выбран' });
  }

  const fileUrl = `/uploads/${req.file.filename}`;
  res.json({
    url: fileUrl,
    filename: req.file.originalname,
    mimetype: req.file.mimetype,
    size: req.file.size
  });
});

app.get('/', (req, res) => {
  res.json({
    message: '✅ Messenger API работает!',
    activeUsers: activeUsers.size,
    activeCalls: activeCalls.size
  });
});

const activeUsers = new Map();
const activeCalls = new Map();

io.on('connection', (socket) => {
  console.log('🔌 Подключение:', socket.id);

  socket.on('user:online', async (userId) => {
    activeUsers.set(userId, socket.id);
    socket.userId = userId;
    await User.findByIdAndUpdate(userId, {
      online: true,
      lastSeen: new Date()
    });
    io.emit('user:status', { userId, online: true });
    console.log(`👤 Онлайн: ${userId}`);
  });

  socket.on('message:send', async (data) => {
    try {
      const { chatId, senderId, text, type = 'text' } = data;

      const message = new Message({
        chatId,
        sender: senderId,
        text,
        type,
      });
      await message.save();

      await Chat.findByIdAndUpdate(chatId, {
        lastMessage: message._id,
        updatedAt: new Date()
      });

      const chat = await Chat.findById(chatId).populate('participants');

      chat.participants.forEach(p => {
        if (p._id.toString() !== senderId) {
          const sid = activeUsers.get(p._id.toString());
          if (sid) {
            io.to(sid).emit('message:received', {
              _id: message._id,
              chatId,
              sender: senderId,
              text,
              type,
              timestamp: message.createdAt
            });
          }
        }
      });

      socket.emit('message:sent', {
        _id: message._id,
        chatId,
        senderId,
        text,
        type,
        tempId: data.tempId,
        timestamp: message.createdAt
      });

    } catch (error) {
      console.error('❌ Ошибка сообщения:', error);
    }
  });

  socket.on('call:initiate', (data) => {
    const { callerId, receiverId, isVideo, duration } = data;
    const callId = uuidv4();

    activeCalls.set(callId, {
      callerId,
      receiverId,
      isVideo,
      duration,
      status: 'calling'
    });

    const receiverSid = activeUsers.get(receiverId);
    if (receiverSid) {
      io.to(receiverSid).emit('call:incoming', {
        callId, callerId, isVideo, duration
      });
    } else {
      socket.emit('call:error', { message: 'Пользователь не в сети' });
    }
  });

  socket.on('call:accept', (data) => {
    const { callId } = data;
    const call = activeCalls.get(callId);
    if (!call) return;

    call.status = 'active';
    const callerSid = activeUsers.get(call.callerId);
    if (callerSid) {
      io.to(callerSid).emit('call:accepted', { callId });
    }

    setTimeout(() => endCall(callId), call.duration * 1000);
  });

  socket.on('call:reject', (data) => {
    const call = activeCalls.get(data.callId);
    if (!call) return;
    const callerSid = activeUsers.get(call.callerId);
    if (callerSid) {
      io.to(callerSid).emit('call:rejected', { callId: data.callId });
    }
    activeCalls.delete(data.callId);
  });

  socket.on('call:end', (data) => endCall(data.callId));

  socket.on('webrtc:offer', (data) => {
    const call = activeCalls.get(data.callId);
    if (!call) return;
    const sid = activeUsers.get(call.receiverId);
    if (sid) io.to(sid).emit('webrtc:offer', data);
  });

  socket.on('webrtc:answer', (data) => {
    const call = activeCalls.get(data.callId);
    if (!call) return;
    const sid = activeUsers.get(call.callerId);
    if (sid) io.to(sid).emit('webrtc:answer', data);
  });

  socket.on('webrtc:ice-candidate', (data) => {
    const { targetUserId } = data;
    const sid = activeUsers.get(targetUserId);
    if (sid) io.to(sid).emit('webrtc:ice-candidate', data);
  });

  socket.on('disconnect', async () => {
    if (socket.userId) {
      activeUsers.delete(socket.userId);
      await User.findByIdAndUpdate(socket.userId, {
        online: false,
        lastSeen: new Date()
      });
      io.emit('user:status', { userId: socket.userId, online: false });
      console.log(`👤 Оффлайн: ${socket.userId}`);
    }
  });
});

function endCall(callId) {
  const call = activeCalls.get(callId);
  if (!call) return;

  const callerSid = activeUsers.get(call.callerId);
  const receiverSid = activeUsers.get(call.receiverId);

  if (callerSid) io.to(callerSid).emit('call:ended', { callId });
  if (receiverSid) io.to(receiverSid).emit('call:ended', { callId });

  activeCalls.delete(callId);
  console.log(`📞 Звонок завершён: ${callId}`);
}

const PORT = process.env.PORT || 8080;
server.listen(PORT, () => {
  console.log(`🚀 Сервер запущен на порту ${PORT}`);
});
