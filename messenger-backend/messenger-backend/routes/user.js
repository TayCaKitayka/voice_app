const express = require('express');
const router = express.Router();
const User = require('../models/User');
const auth = require('../middleware/auth');

router.get('/search', auth, async (req, res) => {
  try {
    const { query } = req.query;

    if (!query || query.length < 2) {
      return res.json([]);
    }

    const users = await User.find({
      $and: [
        { _id: { $ne: req.userId } },
        {
          $or: [
            { username: { $regex: query, $options: 'i' } },
            { email: { $regex: query, $options: 'i' } }
          ]
        }
      ]
    })
    .select('username email avatar online lastSeen')
    .limit(20);

    res.json(users);
  } catch (error) {
    console.error('Ошибка поиска:', error);
    res.status(500).json({ error: 'Ошибка сервера' });
  }
});

router.get('/:userId', auth, async (req, res) => {
  try {
    const user = await User.findById(req.params.userId).select('-password');

    if (!user) {
      return res.status(404).json({ error: 'Пользователь не найден' });
    }

    res.json(user);
  } catch (error) {
    console.error('Ошибка профиля:', error);
    res.status(500).json({ error: 'Ошибка сервера' });
  }
});

module.exports = router;
