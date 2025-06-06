import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/html.dart';

// 連接狀態
enum ConnectionState {
  connecting,
  connected,
  disconnected,
}

// Socket服務
class SocketService {
  WebSocketChannel? _webSocket;
  String? _serverInfo;
  String? _username;
  bool _isConnected = false;
  final _messageStreamController = StreamController<Map<String, dynamic>>.broadcast();

  // 公開串流供外部監聽
  Stream<Map<String, dynamic>> get messageStream => _messageStreamController.stream;
  bool get isConnected => _isConnected;

  // 連接到伺服器
  Future<bool> connect(String server, int port, String username) async {
    try {
      final wsUrl = 'ws://$server:$port';
      _serverInfo = '$server:$port';
      _username = username;
      
      if (kIsWeb) {
        _webSocket = HtmlWebSocketChannel.connect(wsUrl);
      } else {
        _webSocket = IOWebSocketChannel.connect(
          Uri.parse(wsUrl),
          pingInterval: const Duration(seconds: 5),
        );
      }
      
      _isConnected = true;
      _setupListener();
      
      // 發送登入訊息
      sendMessage({
        'type': 'join',
        'username': username,
      });
      
      return true;
    } catch (e) {
      print('連接失敗: $e');
      _isConnected = false;
      return false;
    }
  }
  
  // 重新連接
  Future<bool> reconnect() async {
    if (_serverInfo == null || _username == null) return false;
    
    final parts = _serverInfo!.split(':');
    if (parts.length != 2) return false;
    
    final server = parts[0];
    final port = int.tryParse(parts[1]);
    if (port == null) return false;
    
    return connect(server, port, _username!);
  }
  
  // 發送訊息
  void sendMessage(Map<String, dynamic> message) {
    if (!_isConnected || _webSocket == null) return;
    
    try {
      _webSocket!.sink.add(jsonEncode(message));
    } catch (e) {
      print('發送訊息失敗: $e');
      _isConnected = false;
    }
  }
  
  // 設置監聽
  void _setupListener() {
    _webSocket?.stream.listen(
      (data) {
        if (data is String) {
          try {
            final jsonData = jsonDecode(data);
            _messageStreamController.add(jsonData);
          } catch (e) {
            print('解析訊息失敗: $e');
          }
        }
      },
      onError: (error) {
        print('連線錯誤: $error');
        _isConnected = false;
        _messageStreamController.add({
          'type': 'connectionError',
          'message': error.toString(),
        });
      },
      onDone: () {
        print('連線已關閉');
        _isConnected = false;
        _messageStreamController.add({
          'type': 'connectionClosed',
        });
      },
    );
  }
  
  // 關閉連接
  void disconnect() {
    _webSocket?.sink.close();
    _isConnected = false;
  }
  
  // 釋放資源
  void dispose() {
    disconnect();
    _messageStreamController.close();
  }
}