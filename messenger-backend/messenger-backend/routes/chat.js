const express = require('express');
const router = express.Router();
const Chat = require('../models/Chat');
const Message = require('../models/Message');
const auth = require('../middleware/auth');

router.get('/list', auth, async (req, res) => {
  try {
    const chats = await Chat.find({
      participants: req.userId
    })
    .populate('participants', 'username email avatar online lastSeen')
    .populate({
      path: 'lastMessage',
      populate: { path: 'sender', select: 'username' }
    })
    .sort({ updatedAt: -1 });

    res.json(chats);
  } catch (error) {
    console.error('Ошибка получения чатов:', error);
    res.status(500).json({ error: 'Ошибка сервера' });
  }
});

router.post('/create', auth, async (req, res) => {
  try {
    const { participantId } = req.body;

    let chat = await Chat.findOne({
      isGroup: false,
      participants: { $all: [req.userId, participantId] }
    }).populate('participants', 'username email avatar online lastSeen');

    if (!chat) {
      chat = new Chat({
        participants: [req.userId, participantId],
        isGroup: false
      });
      await chat.save();
      await chat.populate('participants', 'username email avatar online lastSeen');
    }

    res.json(chat);
  } catch (error) {
    console.error('Ошибка создания чата:', error);
    res.status(500).json({ error: 'Ошибка сервера' });
  }
});

router.get('/:chatId/messages', auth, async (req, res) => {
  try {
    const { chatId } = req.params;
    const { limit = 50, skip = 0 } = req.query;

    const messages = await Message.find({ chatId })
      .sort({ createdAt: -1 })
      .limit(parseInt(limit))
      .skip(parseInt(skip))
      .populate('sender', 'username avatar');

    res.json(messages.reverse());
  } catch (error) {
    console.error('Ошибка получения сообщений:', error);
    res.status(500).json({ error: 'Ошибка сервера' });
  }
});

module.exports = router;
