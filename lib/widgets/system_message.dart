import 'package:flutter/material.dart';
import 'package:chat/models/chat_message.dart';

class SystemMessageWidget extends StatelessWidget {
  final ChatMessage message;
  final bool isDarkMode;

  const SystemMessageWidget({
    super.key,
    required this.message,
    required this.isDarkMode,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8.0),
        padding: const EdgeInsets.symmetric(
          horizontal: 16.0,
          vertical: 8.0,
        ),
        decoration: BoxDecoration(
          color: isDarkMode ? Colors.grey[800] : Colors.grey[200],
          borderRadius: BorderRadius.circular(16.0),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: isDarkMode ? Colors.white70 : Colors.black54,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }
}