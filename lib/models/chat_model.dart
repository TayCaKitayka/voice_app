import 'user_model.dart';
import 'message_model.dart';

class ChatModel {
  final String id;
  final List<UserModel> participants;
  final bool isGroup;
  final String? groupName;
  final MessageModel? lastMessage;
  final DateTime createdAt;
  final DateTime updatedAt;

  ChatModel({
    required this.id,
    required this.participants,
    this.isGroup = false,
    this.groupName,
    this.lastMessage,
    required this.createdAt,
    required this.updatedAt,
  });

  ChatModel copyWith({
    String? id,
    List<UserModel>? participants,
    bool? isGroup,
    String? groupName,
    MessageModel? lastMessage,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ChatModel(
      id: id ?? this.id,
      participants: participants ?? this.participants,
      isGroup: isGroup ?? this.isGroup,
      groupName: groupName ?? this.groupName,
      lastMessage: lastMessage ?? this.lastMessage,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory ChatModel.fromJson(Map<String, dynamic> json) {
    return ChatModel(
      id: json['_id'] ?? json['id'] ?? '',
      participants: (json['participants'] as List?)
              ?.map((p) {
                if (p is Map<String, dynamic>) {
                  return UserModel.fromJson(p);
                }
                return null;
              })
              .whereType<UserModel>()
              .toList() ??
          [],
      isGroup: json['isGroup'] ?? false,
      groupName: json['groupName'],
      lastMessage: json['lastMessage'] != null && json['lastMessage'] is Map
          ? MessageModel.fromJson(json['lastMessage'] as Map<String, dynamic>)
          : null,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'])
          : DateTime.now(),
    );
  }

  UserModel getOtherParticipant(String currentUserId) {
    return participants.firstWhere(
      (p) => p.id != currentUserId,
      orElse: () => participants.first,
    );
  }
}