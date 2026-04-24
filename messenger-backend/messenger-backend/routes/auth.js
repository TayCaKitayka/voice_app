const express = require('express');
const router = express.Router();
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');
const User = require('../models/User');

router.post('/register', async (req, res) => {
  try {
    const { username, email, password } = req.body;

    if (!username || !email || !password) {
      return res.status(400).json({
        error: 'Необходимо заполнить все поля'
      });
    }

    const existingUser = await User.findOne({
      $or: [{ email }, { username }]
    });

    if (existingUser) {
      return res.status(400).json({
        error: 'Пользователь с таким email или именем уже существует'
      });
    }

    const user = new User({
      username,
      email,
      password
    });

    await user.save();

    const token = jwt.sign(
      { userId: user._id },
      process.env.JWT_SECRET,
      { expiresIn: '30d' }
    );

    res.status(201).json({
      message: 'Регистрация успешна',
      token,
      user: {
        id: user._id,
        username: user.username,
        email: user.email,
        avatar: user.avatar,
        online: user.online
      }
    });

  } catch (error) {
    console.error('Ошибка регистрации:', error);
    res.status(500).json({ error: 'Ошибка сервера' });
  }
});

router.post('/login', async (req, res) => {
  try {
    const { email, password } = req.body;

    if (!email || !password) {
      return res.status(400).json({
        error: 'Введите email и пароль'
      });
    }

    const user = await User.findOne({ email });
    if (!user) {
      return res.status(401).json({ error: 'Неверный email или пароль' });
    }

    // Проверяем пароль - может быть открытый текст ИЛИ хеш
    let isMatch = false;
    
    // Если пароль в БД выглядит как хеш bcrypt (начинается с $2a$ или $2b$)
    if (user.password.startsWith('$2a$') || user.password.startsWith('$2b$')) {
      isMatch = await bcrypt.compare(password, user.password);
    } else {
      // Иначе сравниваем как открытый текст
      isMatch = password === user.password;
    }

    if (!isMatch) {
      return res.status(401).json({ error: 'Неверный email или пароль' });
    }

    const token = jwt.sign(
      { userId: user._id },
      process.env.JWT_SECRET,
      { expiresIn: '30d' }
    );

    res.json({
      message: 'Вход выполнен',
      token,
      user: {
        id: user._id,
        username: user.username,
        email: user.email,
        avatar: user.avatar,
        online: user.online,
        lastSeen: user.lastSeen
      }
    });

  } catch (error) {
    console.error('Ошибка входа:', error);
    res.status(500).json({ error: 'Ошибка сервера' });
  }
});

module.exports = router;
