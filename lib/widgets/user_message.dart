import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import '../models/user.dart';
import 'markdown_message.dart';

class UserMessageWidget extends StatelessWidget {
  final ChatMessage message;
  final bool isMe;
  final bool isDarkMode;
  final User sender;
  final String timeString;

  const UserMessageWidget({
    super.key,
    required this.message,
    required this.isMe,
    required this.isDarkMode,
    required this.sender,
    required this.timeString,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: sender.isAdmin ? Colors.amber : Colors.blue,
              child: sender.isAdmin
                  ? const Icon(Icons.star, color: Colors.white, size: 16)
                  : Text(
                      sender.name.isEmpty 
                          ? '?' 
                          : sender.name.substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white, 
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMe 
                  ? CrossAxisAlignment.end 
                  : CrossAxisAlignment.start,
              children: [
                if (!isMe)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4.0, left: 8.0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (sender.isAdmin) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4, 
                              vertical: 1
                            ),
                            decoration: BoxDecoration(
                              color: Colors.amber,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              '管理員',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          sender.name,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: sender.isAdmin 
                                ? Colors.amber
                                : (isDarkMode ? Colors.white70 : Colors.black54),
                          ),
                        ),
                      ],
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12.0, 
                    vertical: 8.0
                  ),
                  decoration: BoxDecoration(
                    color: isMe
                        ? Theme.of(context).colorScheme.primary
                        : (isDarkMode ? Colors.grey[700] : Colors.grey[200]),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 使用 Markdown 組件顯示訊息
                      MarkdownMessageWidget(
                        text: message.text,
                        isDarkMode: isDarkMode,
                        isMe: isMe,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            timeString,
                            style: TextStyle(
                              fontSize: 10,
                              color: isMe
                                  ? Colors.white70
                                  : (isDarkMode ? Colors.white54 : Colors.black45),
                            ),
                          ),
                          if (isMe) ...[
                            const SizedBox(width: 4),
                            Icon(
                              message.isRead ? Icons.done_all : Icons.done,
                              size: 12,
                              color: message.isRead ? Colors.blue[300] : Colors.white70,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 16,
              backgroundColor: sender.isAdmin ? Colors.amber : Colors.blue,
              child: sender.isAdmin
                  ? const Icon(Icons.star, color: Colors.white, size: 16)
                  : Text(
                      sender.name.isEmpty 
                          ? '?' 
                          : sender.name.substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white, 
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}