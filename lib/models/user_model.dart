class UserModel {
  final String id;
  final String username;
  final String email;
  final String? avatar;
  final bool online;

  UserModel({
    required this.id,
    required this.username,
    required this.email,
    this.avatar,
    this.online = false,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    String id = '';
    if (json['id'] != null) {
      id = json['id'].toString();
    } else if (json['_id'] != null) {
      if (json['_id'] is Map) {
        id = (json['_id']['\$oid'] ?? json['_id']['_id'] ?? json['_id']['id'] ?? json['_id'].toString()).toString();
      } else {
        id = json['_id'].toString();
      }
    }

    return UserModel(
      id: id,
      username: json['username'] ?? 'Unknown',
      email: json['email'] ?? '',
      avatar: json['avatar'],
      online: json['online'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'avatar': avatar,
      'online': online,
    };
  }

  UserModel copyWith({
    String? id,
    String? username,
    String? email,
    String? avatar,
    bool? online,
  }) {
    return UserModel(
      id: id ?? this.id,
      username: username ?? this.username,
      email: email ?? this.email,
      avatar: avatar ?? this.avatar,
      online: online ?? this.online,
    );
  }
}