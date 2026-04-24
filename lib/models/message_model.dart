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

    String senderId = '';

    if (json['senderId'] != null) {
      if (json['senderId'] is Map) {
        senderId = (json['senderId']['\$oid'] ?? json['senderId']['_id'] ?? json['senderId']['id'] ?? '').toString();
      } else {
        senderId = json['senderId'].toString();
      }
    } else if (json['sender'] != null) {
      if (json['sender'] is String) {
        senderId = json['sender'];
      } else if (json['sender'] is Map) {
        senderId = (json['sender']['\$oid'] ?? json['sender']['_id'] ?? json['sender']['id'] ?? '').toString();
      }
    }

    // Если всё еще пусто, попробуем поискать в корне как userId (иногда бывает в сокетах)
    if (senderId.isEmpty && json['userId'] != null) {
      senderId = json['userId'].toString();
    }

    return MessageModel(
      id: id,
      chatId: (json['chatId'] ?? '').toString(),
      senderId: senderId,
      text: json['text'] ?? '',
      type: json['type'] ?? 'text',
      read: json['read'] ?? false,
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'].toString())
          : (json['createdAt'] != null
              ? DateTime.parse(json['createdAt'].toString())
              : DateTime.now()),
    );
  }
}