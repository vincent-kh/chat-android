import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:web_socket_channel/io.dart';
import 'package:flutter/foundation.dart';

class ConnectionService {
  static final ConnectionService _instance = ConnectionService._internal();
  factory ConnectionService() => _instance;
  ConnectionService._internal();
  
  final Connectivity _connectivity = Connectivity();
  
  // 檢查網絡連接
  Future<bool> isConnected() async {
    try {
      var connectivityResult = await _connectivity.checkConnectivity();
      debugPrint('網絡連接狀態: $connectivityResult');
      
      if (connectivityResult.contains(ConnectivityResult.none) || connectivityResult.isEmpty) {
        return false;
      }
      
      return true;
    } catch (e) {
      debugPrint('檢查網絡連接時出錯: $e');
      return false;
    }
  }
  
  // 測試特定主機的連接性
  Future<bool> canReachHost(String host, int port) async {
    try {
      debugPrint('測試連接到 $host:$port');
      
      final socket = await Socket.connect(host, port)
          .timeout(const Duration(seconds: 5));
      await socket.close();
      debugPrint('成功連接到 $host:$port');
      return true;
      
    } catch (e) {
      debugPrint('無法連接到 $host:$port - $e');
      return false;
    }
  }
  
  // 使用 IO WebSocketChannel 連接
  Future<IOWebSocketChannel> connectWebSocket(String server, int port) async {
    debugPrint('開始 WebSocket 連接流程');
    
    // 檢查基本網絡連接
    bool connected = await isConnected();
    if (!connected) {
      throw Exception('無網絡連接');
    }
    
    // 測試主機連接性
    bool canReach = await canReachHost(server, port);
    if (!canReach) {
      throw Exception('無法連接到伺服器 $server:$port，請檢查伺服器是否運行');
    }
    
    try {
      final wsUrl = 'ws://$server:$port';
      debugPrint('正在連接到 WebSocket: $wsUrl');
      
      final channel = IOWebSocketChannel.connect(
        Uri.parse(wsUrl),
        pingInterval: const Duration(seconds: 30),
      );
      
      // 等待連接建立
      await channel.ready.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          channel.sink.close();
          throw TimeoutException('WebSocket 連接超時', const Duration(seconds: 10));
        },
      );
      
      debugPrint('WebSocket 連接成功建立');
      return channel;
      
    } catch (e) {
      debugPrint('WebSocket 連接失敗: $e');
      
      if (e is SocketException) {
        if (e.osError?.errorCode == 61) {
          throw Exception('連接被拒絕，請確認伺服器正在運行並監聽端口 $port');
        } else if (e.osError?.errorCode == 64) {
          throw Exception('主機 $server 無法訪問');
        }
      } else if (e is TimeoutException) {
        throw Exception('連接超時，請檢查網絡連接或伺服器狀態');
      }
      
      throw Exception('無法連接到伺服器: ${e.toString()}');
    }
  }
}