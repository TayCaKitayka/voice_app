const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');

const userSchema = new mongoose.Schema({
  username: {
    type: String,
    required: true,
    unique: true,
    trim: true,
    minlength: 3
  },
  email: {
    type: String,
    required: true,
    unique: true,
    lowercase: true,
    trim: true
  },
  password: {
    type: String,
    required: true,
    minlength: 6
  },
  avatar: {
    type: String,
    default: null
  },
  bio: {
    type: String,
    default: ''
  },
  online: {
    type: Boolean,
    default: false
  },
  lastSeen: {
    type: Date,
    default: Date.now
  }
}, { timestamps: true });

userSchema.pre('save', function(next) {
  const user = this;
  
  if (!user.isModified('password')) {
    return next();
  }

  bcrypt.hash(user.password, 10).then(hash => {
    user.password = hash;
    next();
  }).catch(err => next(err));
});

userSchema.methods.comparePassword = function(candidatePassword, callback) {
  bcrypt.compare(candidatePassword, this.password).then(isMatch => {
    callback(null, isMatch);
  }).catch(err => callback(err));
};

module.exports = mongoose.model('User', userSchema);
