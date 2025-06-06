class ChatMessage {
  final String sender;
  final String text;
  final bool isSystem;
  final DateTime timestamp;
  bool isRead;

  ChatMessage({
    required this.sender,
    required this.text,
    this.isSystem = false,
    DateTime? timestamp,
    this.isRead = false,
  }) : timestamp = timestamp ?? DateTime.now();
}