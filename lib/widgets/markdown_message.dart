import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

class MarkdownMessageWidget extends StatelessWidget {
  final String text;
  final bool isDarkMode;
  final bool isMe;

  const MarkdownMessageWidget({
    super.key,
    required this.text,
    required this.isDarkMode,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    return MarkdownBody(
      data: text,
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        // 基本文字樣式
        p: TextStyle(
          fontSize: 16.0,
          color: isDarkMode 
              ? (isMe ? Colors.white : Colors.white)
              : (isMe ? Colors.white : Colors.black87),
        ),
        
        // 標題樣式
        h1: TextStyle(
          fontSize: 20.0,
          fontWeight: FontWeight.bold,
          color: isDarkMode 
              ? (isMe ? Colors.white : Colors.white)
              : (isMe ? Colors.white : Colors.black87),
        ),
        h2: TextStyle(
          fontSize: 18.0,
          fontWeight: FontWeight.bold,
          color: isDarkMode 
              ? (isMe ? Colors.white : Colors.white)
              : (isMe ? Colors.white : Colors.black87),
        ),
        h3: TextStyle(
          fontSize: 16.0,
          fontWeight: FontWeight.bold,
          color: isDarkMode 
              ? (isMe ? Colors.white : Colors.white)
              : (isMe ? Colors.white : Colors.black87),
        ),
        
        // 粗體和斜體
        strong: TextStyle(
          fontWeight: FontWeight.bold,
          color: isDarkMode 
              ? (isMe ? Colors.white : Colors.white)
              : (isMe ? Colors.white : Colors.black87),
        ),
        em: TextStyle(
          fontStyle: FontStyle.italic,
          color: isDarkMode 
              ? (isMe ? Colors.white : Colors.white)
              : (isMe ? Colors.white : Colors.black87),
        ),
        
        // 程式碼樣式
        code: TextStyle(
          backgroundColor: isMe 
              ? Colors.black.withAlpha(51)
              : (isDarkMode ? Colors.grey[800] : Colors.grey[200]),
          color: isDarkMode 
              ? Colors.lightBlue[300]
              : Colors.red[700],
          fontFamily: 'monospace',
          fontSize: 14.0,
        ),
        codeblockDecoration: BoxDecoration(
          color: isMe 
              ? Colors.black.withAlpha(51)
              : (isDarkMode ? Colors.grey[800] : Colors.grey[200]),
          borderRadius: BorderRadius.circular(8.0),
        ),
        
        // 連結樣式
        a: TextStyle(
          color: isDarkMode 
              ? Colors.lightBlue[300]
              : Colors.blue[700],
          decoration: TextDecoration.underline,
        ),
        
        // 引用樣式
        blockquote: TextStyle(
          color: isDarkMode 
              ? Colors.grey[400]
              : Colors.grey[600],
          fontStyle: FontStyle.italic,
        ),
        blockquoteDecoration: BoxDecoration(
          color: isMe 
              ? Colors.black.withAlpha(26)
              : (isDarkMode ? Colors.grey[800] : Colors.grey[100]),
          borderRadius: BorderRadius.circular(4.0),
          border: Border(
            left: BorderSide(
              color: isDarkMode ? Colors.grey[600]! : Colors.grey[400]!,
              width: 4.0,
            ),
          ),
        ),
        
        // 列表樣式
        listBullet: TextStyle(
          color: isDarkMode 
              ? (isMe ? Colors.white : Colors.white)
              : (isMe ? Colors.white : Colors.black87),
        ),
      ),
      onTapLink: (text, href, title) {
        if (href != null) {
          _launchUrl(href);
        }
      },
    );
  }

  Future<void> _launchUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (e) {
      print('無法開啟連結: $url, 錯誤: $e');
    }
  }
}