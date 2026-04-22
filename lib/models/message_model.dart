class MessageModel {
  final String id;
  final String chatId;
  final String senderId;
  final String text;
  final String type;
  final bool read;
  final DateTime timestamp;

  MessageModel({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.text,
    this.type = 'text',
    this.read = false,
    required this.timestamp,
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    String senderId;
    if (json['sender'] is String) {
      senderId = json['sender'];
    } else if (json['sender'] is Map) {
      senderId = json['sender']['_id'] ?? json['sender']['id'] ?? '';
    } else {
      senderId = '';
    }

    return MessageModel(
      id: json['_id'] ?? json['id'] ?? '',
      chatId: json['chatId'] ?? '',
      senderId: senderId,
      text: json['text'] ?? '',
      type: json['type'] ?? 'text',
      read: json['read'] ?? false,
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'])
          : (json['createdAt'] != null
              ? DateTime.parse(json['createdAt'])
              : DateTime.now()),
    );
  }
}