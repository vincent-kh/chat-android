import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:chat/models/chat_message.dart';
import 'package:chat/models/user.dart';
import 'package:chat/screens/login_page.dart';
import 'package:chat/widgets/system_message.dart';
import 'package:chat/widgets/user_message.dart';

class ChatRoom extends StatefulWidget {
  final Socket? socket;
  final WebSocketChannel? webSocket;
  final String username;
  final bool useWebSocket;
  final String? serverInfo;
  
  const ChatRoom({
    super.key, 
    this.socket, 
    this.webSocket,
    required this.username,
    required this.useWebSocket,
    this.serverInfo,
  }) : assert((socket != null && !useWebSocket) || (webSocket != null && useWebSocket), 
      "必須提供 socket 或 webSocket 其中之一");
  
  @override
  State<ChatRoom> createState() => _ChatRoomState();
}

class _ChatRoomState extends State<ChatRoom> with WidgetsBindingObserver {
  final TextEditingController _messageController = TextEditingController();
  final List<ChatMessage> _messages = [];
  final List<User> _users = [];
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _pendingMessages = [];
  StreamSubscription? _subscription;
  Timer? _typingTimer;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer; // 保持以便未來使用
  bool _isAdmin = false;
  bool _isRoot = false; // 新增 Root 狀態
  bool _connected = true;
  bool _isTyping = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _messageController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });

    _users.add(User(
      id: widget.username, // 假設 User model 有 id 欄位
      name: widget.username,
      isAdmin: false, // 將由伺服器更新
      isRoot: false, // 將由伺服器更新
    ));

    _setupListener();
    _requestUserList();
    _startHeartbeat(); // 如果要啟用心跳
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      if (!_connected) _tryReconnect();
      _markAllMessagesAsRead();
    }
  }

  void _markAllMessagesAsRead() {
    if (mounted) {
      setState(() {
        for (var message in _messages) {
          message.isRead = true;
        }
      });
    }

    if (_connected) {
      _sendToServer({'type': 'markRead'});
    }
  }

  void _sendToServer(Map<String, dynamic> data) {
    if (_connected) {
      final jsonData = jsonEncode(data);
      if (widget.useWebSocket) {
        widget.webSocket?.sink.add(jsonData);
      } else {
        widget.socket?.add(utf8.encode(jsonData));
      }
      debugPrint('Sent to server: $jsonData');
    } else {
      _pendingMessages.add(data);
      debugPrint('Connection lost. Message queued: ${jsonEncode(data)}');
      if (_reconnectTimer == null || !_reconnectTimer!.isActive) {
        _tryReconnect();
      }
    }
  }

  void _tryReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (_connected) {
        timer.cancel();
        return;
      }
      try {
        if (!widget.useWebSocket) {
          if (widget.socket != null) {
            final socket = await Socket.connect(
                    widget.socket!.remoteAddress.address, widget.socket!.remotePort)
                .timeout(const Duration(seconds: 5));

            _setupSocketListener(socket);
            if (mounted) {
              setState(() => _connected = true);
            }
            debugPrint('Reconnected via Socket.');
            for (var msg in _pendingMessages) {
              socket.add(utf8.encode(jsonEncode(msg)));
            }
            _pendingMessages.clear();

            socket.add(utf8.encode(jsonEncode({
              'type': 'login', // or 'rejoin' if your server supports it
              'username': widget.username,
            })));
            _requestUserList(); // Request user list after reconnecting
            _startHeartbeat(); // Restart heartbeat
            timer.cancel();
          }
        } else {
          if (widget.serverInfo != null) {
            final wsUrl = 'ws://${widget.serverInfo}';
            final wsChannel = IOWebSocketChannel.connect(
              Uri.parse(wsUrl),
              pingInterval: const Duration(seconds: 5),
            );

            _setupWebSocketListener(wsChannel);
            if (mounted) {
              setState(() => _connected = true);
            }
            debugPrint('Reconnected via WebSocket.');
            for (var msg in _pendingMessages) {
              wsChannel.sink.add(jsonEncode(msg));
            }
            _pendingMessages.clear();

            wsChannel.sink.add(jsonEncode({
              'type': 'join', // or 'rejoin'
              'username': widget.username,
            }));
            _requestUserList(); // Request user list after reconnecting
            _startHeartbeat(); // Restart heartbeat
            timer.cancel();
          }
        }
      } catch (e) {
        debugPrint('Reconnect failed: $e');
        // Keep timer running to try again
      }
    });
  }

  void _setupListener() {
    if (widget.useWebSocket) {
      _setupWebSocketListener(widget.webSocket!);
    } else {
      _setupSocketListener(widget.socket!);
    }
  }

  void _requestUserList() {
    if (_connected) {
      _sendToServer({
        'type': 'get_user_list',
      });
      debugPrint('已請求用戶列表');
    }
  }

  void _setupSocketListener(Socket socket) {
    _subscription?.cancel(); // Cancel any existing subscription
    _subscription = socket
        .asBroadcastStream() // Use asBroadcastStream if you might have multiple listeners (though usually not for the primary socket)
        .map((data) => utf8.decode(data))
        .listen(
          _handleMessage,
          onError: (error) {
            debugPrint('Socket error: $error');
            _handleDisconnect();
          },
          onDone: _handleDisconnect,
          cancelOnError: false, // Set to false to keep listening after an error if desired, though disconnect usually means stop.
        );
  }

  void _setupWebSocketListener(WebSocketChannel wsChannel) {
    _subscription?.cancel(); // Cancel any existing subscription
    _subscription = wsChannel.stream.listen(
      (data) {
        if (data is String) {
          _handleMessage(data);
        } else {
          debugPrint('Received non-string data from WebSocket: $data');
        }
      },
      onError: (error) {
        debugPrint('WebSocket error: $error');
        _handleDisconnect();
      },
      onDone: _handleDisconnect,
      cancelOnError: false,
    );
  }

  void _handleDisconnect() {
    if (!mounted) return;
    debugPrint('Disconnected from server.');
    if (mounted) {
      setState(() {
        _connected = false;
      });
    }
    _heartbeatTimer?.cancel(); // Stop heartbeat on disconnect
    // Don't show SnackBar immediately, _tryReconnect will handle UI updates or show errors if it fails repeatedly.
    _tryReconnect(); // Attempt to reconnect
  }

  void _handleMessage(String data) {
    try {
      debugPrint('收到訊息: $data');
      if (!mounted) return;

      final jsonData = jsonDecode(data);

      if (jsonData.containsKey('type')) {
        final type = jsonData['type'];

        switch (type) {
          case 'system':
            _handleSystemMessage(jsonData);
            break;
          case 'chat':
            _handleChatMessage(jsonData);
            break;
          case 'user_list':
            _handleUserList(jsonData);
            break;
          case 'error':
            _handleErrorMessage(jsonData);
            break;
          case 'pong':
            _handlePongMessage(jsonData);
            break;
          default:
            debugPrint('未知訊息類型: $type');
        }
      } else {
        debugPrint('收到無類型訊息: $data');
      }
    } catch (e) {
      debugPrint('處理訊息時出錯: $e');
    }
  }

  void _handleErrorMessage(Map<String, dynamic> jsonData) {
    if (!mounted) return;
    final errorMessage = jsonData['message']?.toString() ?? '來自伺服器的未知錯誤。';
    debugPrint('Server error: $errorMessage');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(errorMessage),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _handlePongMessage(Map<String, dynamic> jsonData) {
    debugPrint('Received pong: $jsonData');
    // You can add logic here, e.g., calculate latency
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients && mounted) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  void _sendTypingNotification() {
    _typingTimer?.cancel();
    if (!mounted || !_connected) return;

    if (_messageController.text.isNotEmpty) {
      if (!_isTyping) {
        _isTyping = true;
        _sendToServer({
          'type': 'typing',
          'username': widget.username,
          'is_typing': true,
        });
      }
      _typingTimer = Timer(const Duration(seconds: 2), () {
        if (mounted && _isTyping) {
          _sendToServer({
            'type': 'typing',
            'username': widget.username,
            'is_typing': false,
          });
          _isTyping = false;
        }
      });
    } else {
      if (_isTyping) {
        _sendToServer({
          'type': 'typing',
          'username': widget.username,
          'is_typing': false,
        });
        _isTyping = false;
      }
    }
  }

  void _sendMessage() {
    if (_messageController.text.trim().isEmpty || !_connected || !mounted) return;

    final messageText = _messageController.text.trim();
    final now = DateTime.now();

    final chatMessage = ChatMessage(
      sender: widget.username,
      text: messageText,
      timestamp: now,
      isSystem: false,
      // senderIsAdmin: _isAdmin, // Assuming current user's admin status for optimistic update
      // senderIsRoot: _isRoot,   // Assuming current user's root status for optimistic update
    );

    if (mounted) {
      setState(() {
        _messages.add(chatMessage);
      });
    }
    _messageController.clear();
    _scrollToBottom();

    _sendToServer({
      'type': 'chat',
      'content': messageText,
      // 'username': widget.username, // Server should identify sender by connection
    });

    _typingTimer?.cancel();
    if (_isTyping) {
      _sendToServer({
        'type': 'typing',
        'username': widget.username,
        'is_typing': false,
      });
      if (mounted) {
        _isTyping = false;
      }
    }
  }


  // 處理系統訊息
  void _handleSystemMessage(Map<String, dynamic> jsonData) {
    final content = jsonData['content']?.toString() ?? '';
    final action = jsonData['action']?.toString() ?? '';
    final userId = jsonData['userId']?.toString();

    bool shouldDisplayMessage = true;

    // 檢查是否為針對目前使用者的權限更新 (來自歡迎訊息或特定權限變更訊息)
    if (userId == widget.username) {
      bool updated = false;
      if (jsonData.containsKey('isAdmin') && _isAdmin != jsonData['isAdmin']) {
        _isAdmin = jsonData['isAdmin'] ?? _isAdmin;
        updated = true;
      }
      if (jsonData.containsKey('isRoot') && _isRoot != jsonData['isRoot']) {
        _isRoot = jsonData['isRoot'] ?? _isRoot;
        updated = true;
      }
      if (updated && mounted) {
        setState(() {});
        debugPrint('使用者 ${widget.username} 權限更新: isAdmin: $_isAdmin, isRoot: $_isRoot');
      }
    }

    // 處理使用者被踢出的通知 (發給被踢者)
    if (action == 'kicked' && content.contains("您已被管理員踢出")) {
      shouldDisplayMessage = false; // 不在聊天室顯示此訊息，改用對話框
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('通知'),
            content: Text(content),
            actions: [
              TextButton(
                child: const Text('確定'),
                onPressed: () {
                  Navigator.pop(context); // 關閉對話框
                  _cleanupAndExit(); // 使用統一的清理並退出邏輯
                },
              ),
            ],
          ),
        );
      }
      return;
    }

    // 處理伺服器關閉通知
    if (action == 'shutdown') {
      // 訊息會由下面的通用邏輯添加
      if (mounted) {
        //延遲執行以確保訊息顯示
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _cleanupAndExit(); // 使用統一的清理並退出邏輯
          }
        });
      }
    }
    
    // 決定是否顯示系統訊息 (例如，可以選擇不顯示 "XXX 加入了聊天室")
    // 根據 Python client，大部分系統訊息都會顯示
    // if (content.contains('歡迎') || content.contains('加入了聊天室')) {
    //   debugPrint('忽略特定系統訊息: $content');
    //   shouldDisplayMessage = false; // 或 true，取決於是否想顯示
    // }

    if (shouldDisplayMessage && content.isNotEmpty) {
      if (mounted) {
        setState(() {
          _messages.add(ChatMessage(
            sender: 'System',
            text: content,
            isSystem: true,
            timestamp: DateTime.now(),
            // 假設 User model 有 isRoot, ChatMessage model 也有對應欄位
            // senderIsAdmin: false, // 系統訊息無此概念
            // senderIsRoot: false,  // 系統訊息無此概念
          ));
        });
        _scrollToBottom();
      }
    }
  }

  // 處理聊天訊息
  void _handleChatMessage(Map<String, dynamic> jsonData) {
    final senderName = jsonData['sender_name']?.toString() ?? 'Unknown';
    final senderId = jsonData['sender_id']?.toString() ?? ''; // 仍然獲取 senderId，可能用於其他邏輯或 User 物件
    final content = jsonData['content']?.toString() ?? '';
    final senderIsAdmin = jsonData['is_admin'] as bool? ?? false;
    final senderIsRoot = jsonData['is_root'] as bool? ?? false;
    final timestamp = jsonData['timestamp'];
    
    debugPrint('處理聊天訊息 - 發送者: $senderName (ID: $senderId, Admin: $senderIsAdmin, Root: $senderIsRoot), 內容: $content, 自己: ${widget.username}');
    
    // 修正 isMe 的判斷邏輯：主要比較 senderName 和 widget.username
    // Server should ideally send back a unique identifier for the sender, not rely on username string comparison for "isMe"
    // However, if the server echoes back messages including those from the sender,
    // and we are optimistically adding them, we need a way to avoid duplicates or update status.
    // For now, if server sends back our own messages, we might ignore them if already added.
    // A better approach: server sends a unique message ID, client sends it, server confirms it.
    // Or, server doesn't echo back messages to the original sender.

    // If server echoes messages and we optimistically add, we might get duplicates.
    // Let's assume for now the server does NOT echo back the sender's own messages,
    // or if it does, they have a way to be identified (e.g., a temporary client-side ID matched with a server ID).
    // The current logic `if (isMe) return;` implies server echoes back.
    final isMeByUsername = senderName.trim().toLowerCase() == widget.username.trim().toLowerCase();
    if (isMeByUsername) {
       debugPrint('收到自己發送的訊息回傳 (判斷依據：名稱)，檢查是否已樂觀添加。');
       // This simple check might not be robust enough if multiple identical messages are sent quickly.
       // Consider using message IDs or more sophisticated optimistic update handling.
       bool alreadyExists = _messages.any((msg) =>
           msg.sender.trim().toLowerCase() == widget.username.trim().toLowerCase() &&
           msg.text == content &&
           (DateTime.now().difference(msg.timestamp).inSeconds < 5)); // crude way to check recent optimistic add

       if (alreadyExists) {
           debugPrint('訊息已樂觀添加，忽略伺服器回傳。');
           return;
       }
    }
    
    // User object for sender details (not directly used in ChatMessage constructor here)
    // final senderUser = User(
    //   id: senderId, 
    //   name: senderName,
    //   isAdmin: senderIsAdmin,
    //   isRoot: senderIsRoot,
    // );
    
    DateTime messageTime;
    if (timestamp is num) {
      messageTime = DateTime.fromMillisecondsSinceEpoch((timestamp * 1000).round());
    } else {
      messageTime = DateTime.now();
    }
    
    if (mounted) {
      setState(() {
        _messages.add(ChatMessage(
          sender: senderName, 
          text: content,
          isSystem: false,
          timestamp: messageTime,
          // Pass admin/root status if ChatMessage supports it
          // senderIsAdmin: senderIsAdmin,
          // senderIsRoot: senderIsRoot,
        ));
      });
      _scrollToBottom();
    }
  }

  // 處理用戶列表
  void _handleUserList(Map<String, dynamic> jsonData) {
    if (jsonData.containsKey('users') && jsonData['users'] is List) {
      final usersList = jsonData['users'] as List;
      bool selfStatusUpdated = false;
      if (mounted) {
        setState(() {
          _users.clear();
          for (var userData in usersList) {
            if (userData is Map) {
              final user = User(
                id: userData['id']?.toString() ?? '',
                name: userData['username']?.toString() ?? 'Unknown',
                isAdmin: userData['is_admin'] as bool? ?? false,
                isRoot: userData['is_root'] as bool? ?? false,
              );
              _users.add(user);

              if (user.name.trim().toLowerCase() == widget.username.trim().toLowerCase()) {
                if (_isAdmin != user.isAdmin || _isRoot != user.isRoot) {
                  _isAdmin = user.isAdmin;
                  _isRoot = user.isRoot;
                  selfStatusUpdated = true;
                }
              }
            }
          }
        });
      }
      if (selfStatusUpdated) {
        debugPrint('通過用戶列表更新自身權限: isAdmin: $_isAdmin, isRoot: $_isRoot');
      }
      debugPrint('更新使用者列表，共 ${_users.length} 人');
    }
  }

  // 確保踢人功能發送正確的用戶ID
  void _kickUser(String userId) {
    if (!_isAdmin && !_isRoot) {
       if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('您沒有權限執行此操作。'),
            backgroundColor: Colors.red,
          ),
        );
       }
      return;
    }
    
    if (!_connected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('未連接到伺服器，無法執行操作。'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    
    final targetUser = _users.firstWhere(
      (user) => user.id == userId,
      orElse: () => User(id: userId, name: '未知用戶'),
    );
    
    try {
      _sendToServer({
        'type': 'command',
        'command': 'kick',
        'target_id': userId, 
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('正在踢出用戶 ${targetUser.name}...'),
            backgroundColor: Colors.blue,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      debugPrint('已發送踢出用戶命令: $userId (${targetUser.name})');
    } catch (e) {
      debugPrint('踢出用戶時發生錯誤: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('踢出用戶時發生錯誤: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // 新增：提升用戶為管理員
  void _promoteUser(String userId) {
    if (!_isAdmin && !_isRoot) { // Root can also promote
       if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('您沒有權限提升用戶。'), backgroundColor: Colors.red),
        );
       }
      return;
    }
     if (!_connected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未連接到伺服器。'), backgroundColor: Colors.orange),
        );
      }
      return;
    }
    _sendToServer({
        'type': 'command',
        'command': 'op', 
        'target_id': userId,
      });
  }

  // 新增：降級用戶的管理員權限
  void _demoteUser(String userId) {
    if (!_isRoot) { 
       if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('您沒有超級管理員權限降級用戶。'), backgroundColor: Colors.red),
        );
       }
      return;
    }
    if (!_connected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未連接到伺服器。'), backgroundColor: Colors.orange),
        );
      }
      return;
    }
    _sendToServer({
      'type': 'command',
      'command': 'deop', 
      'target_id': userId,
    });
  }
  
  // 關閉聊天室
  void _closeRoom() {
    if (!_isAdmin && !_isRoot) { // Root can also close room
       if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('您沒有權限關閉聊天室。'), backgroundColor: Colors.red),
        );
       }
      return;
    }
    if (!_connected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未連接到伺服器。'), backgroundColor: Colors.orange),
        );
      }
      return;
    }
    
    _sendToServer({
      'type': 'command',
      'command': 'shutdown',
    });
  }
  
  String _formatTime(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(
      timestamp.year,
      timestamp.month,
      timestamp.day,
    );
    
    if (messageDate == today) {
      return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    } else if (messageDate == yesterday) {
      return '昨天 ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    } else {
      return '${timestamp.month}/${timestamp.day} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    }
  }
  
  void _showUsersDialog(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
      ),
      builder: (context) => _buildUserListWidget(context, isDarkMode),
    );
  }
  
  Widget _buildUserListWidget(BuildContext context, bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildUserListHeader(context),
          const Divider(),
          Expanded(
            child: _users.isEmpty
                ? _buildEmptyUserList(isDarkMode)
                : _buildUserListView(context, isDarkMode),
          ),
        ],
      ),
    );
  }
  
  Widget _buildUserListHeader(BuildContext context) {
    final adminCount = _users.where((user) => user.isAdmin).length;
    final totalCount = _users.length;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(
                  Icons.people,
                  size: 24.0,
                  color: Theme.of(context).iconTheme.color,
                ),
                const SizedBox(width: 8.0),
                Text(
                  '聊天室成員 ($totalCount)',
                  style: const TextStyle(
                    fontSize: 18.0,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            IconButton(
              icon: Icon(
                Icons.refresh,
                color: Theme.of(context).iconTheme.color,
              ),
              onPressed: () {
                _requestUserList();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('正在更新使用者列表...')),
                  );
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const Icon(
              Icons.shield,
              size: 16,
              color: Colors.amber,
            ),
            const SizedBox(width: 4),
            Text(
              '管理員: $adminCount 位',
              style: const TextStyle(
                fontSize: 14,
                color: Colors.amber,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 16),
            const Icon(
              Icons.person,
              size: 16,
              color: Colors.grey,
            ),
            const SizedBox(width: 4),
            Text(
              '一般成員: ${totalCount - adminCount} 位',
              style: const TextStyle(
                fontSize: 14,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }
  
  Widget _buildEmptyUserList(bool isDarkMode) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.person_off,
            size: 48,
            color: isDarkMode ? Colors.white30 : Colors.grey,
          ),
          const SizedBox(height: 16),
          const Text('沒有使用者'),
        ],
      ),
    );
  }
  
  Widget _buildUserListView(BuildContext context, bool isDarkMode) {
    return ListView.builder(
      shrinkWrap: true,
      itemCount: _users.length,
      itemBuilder: (context, index) {
        final user = _users[index];
        final isCurrentUser = user.name.trim().toLowerCase() == widget.username.trim().toLowerCase();
        
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: user.isRoot
                ? Colors.red
                : user.isAdmin
                    ? Colors.amber
                    : isDarkMode
                        ? Colors.grey[700]
                        : Colors.grey[300],
            child: Text(
              user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
              style: TextStyle(
                color: user.isRoot || user.isAdmin
                    ? Colors.white
                    : isDarkMode
                        ? Colors.white
                        : Colors.black,
              ),
            ),
          ),
          title: Row(
            children: [
              Text(
                user.name,
                style: TextStyle(
                  fontWeight: isCurrentUser ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              if (isCurrentUser)
                const Padding(
                  padding: EdgeInsets.only(left: 8.0),
                  child: Text(
                    '(你)',
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: Colors.grey,
                    ),
                  ),
                ),
            ],
          ),
          subtitle: Row(
            children: [
              if (user.isRoot)
                const Text(
                  'Root',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                )
              else if (user.isAdmin)
                const Text(
                  'Admin',
                  style: TextStyle(
                    color: Colors.amber,
                    fontWeight: FontWeight.bold,
                  ),
                )
              else
                const Text(
                  '用戶',
                  style: TextStyle(
                    color: Colors.grey,
                  ),
                ),
            ],
          ),
          trailing: _buildUserActions(context, user, isCurrentUser),
        );
      },
    );
  }
  
  Widget? _buildUserActions(BuildContext context, User user, bool isCurrentUser) {
    if (isCurrentUser) return null;
    if (!_isAdmin && !_isRoot) return null;
    
    List<Widget> actions = [];
    
    if (user.isRoot && !_isRoot) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(
            Icons.admin_panel_settings,
            color: Colors.red, // Simplified, direct color
            size: 20,
          ),
          SizedBox(width: 4),
          Text(
            'Root',
            style: TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      );
    }
    
    if (user.isAdmin && !user.isRoot) {
      if (_isRoot) {
        actions.addAll([
          IconButton(
            icon: const Icon(Icons.arrow_downward, color: Colors.orange, size: 18),
            onPressed: () => _showDemoteUserDialog(context, user),
            tooltip: '降級為普通用戶',
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle, color: Colors.red, size: 18),
            onPressed: () => _showKickUserDialog(context, user),
            tooltip: '踢出用戶',
          ),
        ]);
      } else {
        return const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shield, color: Colors.amber, size: 20),
            SizedBox(width: 4),
            Text(
              'Admin',
              style: TextStyle(
                color: Colors.amber,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        );
      }
    } else if (!user.isAdmin && !user.isRoot) { // Ensure not to show actions for Root if current user is not Root
      // For normal users, Admin and Root can operate
      if (_isAdmin || _isRoot) { // Check if current user has rights
          actions.addAll([
            IconButton(
              icon: const Icon(Icons.arrow_upward, color: Colors.green, size: 18),
              onPressed: () => _showPromoteUserDialog(context, user),
              tooltip: '提升為管理員',
            ),
            IconButton(
              icon: const Icon(Icons.remove_circle, color: Colors.red, size: 18),
              onPressed: () => _showKickUserDialog(context, user),
              tooltip: '踢出用戶',
            ),
          ]);
      }
    }
    
    if (actions.isEmpty) return null;
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: actions,
    );
  }
  
  void _showKickUserDialog(BuildContext context, User user) {
    Navigator.pop(context); 
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('踢出用戶'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('確定要將 ${user.name} 踢出聊天室嗎？'),
            const SizedBox(height: 8),
            if (user.isAdmin)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning, color: Colors.orange, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '注意：此用戶是管理員',
                        style: TextStyle(
                          color: Colors.orange[800],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _kickUser(user.id);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('踢出'),
          ),
        ],
      ),
    );
  }
  
  void _showPromoteUserDialog(BuildContext context, User user) {
    Navigator.pop(context); 
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.arrow_upward, color: Colors.green),
            SizedBox(width: 8),
            Text('提升用戶'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('確定要將 ${user.name} 提升為管理員嗎？'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info, color: Colors.blue, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '管理員將獲得踢出普通用戶和提升用戶的權限',
                      style: TextStyle(
                        color: Colors.blue[800],
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _promoteUser(user.id);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('提升'),
          ),
        ],
      ),
    );
  }
  
  void _showDemoteUserDialog(BuildContext context, User user) {
    Navigator.pop(context); 
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.arrow_downward, color: Colors.orange),
            SizedBox(width: 8),
            Text('降級用戶'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('確定要將管理員 ${user.name} 降級為普通用戶嗎？'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning, color: Colors.orange, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '降級後該用戶將失去所有管理員權限',
                      style: TextStyle(
                        color: Colors.orange[800],
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _demoteUser(user.id);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('降級'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text('聊天室 ${widget.useWebSocket ? "(WebSocket)" : "(Socket)"}'),
            const SizedBox(width: 8),
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: _connected ? Colors.green : Colors.red,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        actions: _buildAppBarActions(context),
      ),
      body: Column(
        children: [
          if (_users.any((user) => user.id != widget.username && user.isTyping)) // Assuming User model has isTyping
            _buildTypingIndicator(isDarkMode),
          
          Expanded(
            child: _buildMessageList(isDarkMode),
          ),
          
          _buildMessageInput(context, isDarkMode),
        ],
      ),
    );
  }
  
  List<Widget> _buildAppBarActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.people),
        onPressed: () => _showUsersDialog(context),
      ),
      if (_isAdmin || _isRoot) // Allow Root to also close room
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _showCloseRoomDialog(context),
        ),
      
      IconButton(
        icon: const Icon(Icons.exit_to_app),
        onPressed: () => _showLeaveRoomDialog(context),
        tooltip: '退出聊天室',
      ),
    ];
  }

  void _showLeaveRoomDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.exit_to_app,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            const Text('退出聊天室'),
          ],
        ),
        content: const Text('確定要離開聊天室嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog first
              _leaveRoom();
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('離開'),
          ),
        ],
      ),
    );
  }

  void _leaveRoom() {
    try {
      if (_connected) {
        _sendToServer({
          'type': 'leave',
          'username': widget.username,
        });
        
        Future.delayed(const Duration(milliseconds: 300), () { // Shorter delay
          _cleanupAndExit();
        });
      } else {
        _cleanupAndExit();
      }
    } catch (e) {
      debugPrint('退出聊天室時發生錯誤: $e');
      _cleanupAndExit(); // Ensure cleanup even on error
    }
  }

  void _cleanupAndExit() {
    if (!mounted) return; 

    debugPrint("執行清理並退出...");
    
    // No need to send 'leave' again if _leaveRoom already did
    _connected = false; 

    _typingTimer?.cancel();
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    _subscription?.cancel();
    _subscription = null;
    
    try {
      if (widget.useWebSocket) {
        widget.webSocket?.sink.close();
      } else {
        widget.socket?.destroy(); 
      }
    } catch (e) {
      debugPrint("關閉 socket/websocket 時出錯: $e");
    }
    
    if (mounted) { // Double check mounted before UI operations
      // Clear local state
      setState(() {
        _messages.clear();
        _users.clear();
        _pendingMessages.clear();
      });

      // Navigate and remove all previous routes
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
        (route) => false,
      );
      
      // Showing SnackBar after navigation is tricky.
      // It's better if LoginPage shows a confirmation if needed.
      // For example, pass a parameter to LoginPage or use a global event.
      // The GlobalKey approach for ScaffoldMessenger is fragile here.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    debugPrint("ChatRoom dispose 開始");
    
    if (_connected && mounted) { // Check mounted here too
      try {
        _sendToServer({ // This might not send if dispose is too quick
          'type': 'leave',
          'username': widget.username,
        });
         debugPrint("已嘗試發送離開訊息 during dispose");
      } catch (e) {
        debugPrint('dispose 中發送離開通知時出錯: $e');
      }
    }
    
    _typingTimer?.cancel();
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    _subscription?.cancel();
    _subscription = null; 
    
    try {
      if (widget.useWebSocket) {
        widget.webSocket?.sink.close();
         debugPrint("WebSocket sink closed in dispose");
      } else {
        widget.socket?.destroy();
         debugPrint("Socket destroyed in dispose");
      }
    } catch (e) {
       debugPrint("dispose 中關閉連接時出錯: $e");
    }
    
    _messageController.dispose();
    _scrollController.dispose();
    _connected = false; // Ensure connected is false
    debugPrint("ChatRoom dispose 完成");
    super.dispose();
  }
  
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_connected && mounted) { // Check mounted
        _sendToServer({
          'type': 'ping',
          'timestamp': DateTime.now().millisecondsSinceEpoch / 1000,
        });
        debugPrint("Sent ping");
      } else {
        timer.cancel(); 
      }
    });
  }
  
  Widget _buildTypingIndicator(bool isDarkMode) {
    // Assuming User model has 'isTyping' and 'name'
    final typingUser = _users.firstWhere(
        (user) => user.id != widget.username && user.isTyping, // Ensure User model has isTyping
        orElse: () => User(id: '', name: '', isTyping: false) // Provide a default non-typing user
    );

    if (!typingUser.isTyping || typingUser.name.isEmpty) { // Don't show if no one is typing or name is empty
        return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      color: isDarkMode ? Colors.grey[800] : Colors.grey[200],
      child: Row(
        children: [
          Text(
            '${typingUser.name} 正在輸入...',
            style: TextStyle(
              color: isDarkMode ? Colors.white70 : Colors.black54,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildMessageList(bool isDarkMode) {
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 64,
              color: isDarkMode ? Colors.white30 : Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              '尚無訊息，開始對話吧！',
              style: TextStyle(
                color: isDarkMode ? Colors.white54 : Colors.black45,
              ),
            ),
          ],
        ),
      );
    }
    
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(8.0),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        
        if (message.isSystem) {
          return SystemMessageWidget(
            message: message,
            isDarkMode: isDarkMode,
          );
        }
        
        final isMe = message.sender.trim().toLowerCase() == widget.username.trim().toLowerCase();
        // debugPrint('訊息 #$index: ${message.text} - 發送者=${message.sender}, 自己=${widget.username}, isMe=$isMe');
        
        User sender;
        try {
          sender = _users.firstWhere(
            (user) => user.name.trim().toLowerCase() == message.sender.trim().toLowerCase() || 
                       user.id == message.sender, // Also check by ID if sender might be an ID
            orElse: () => User(id: message.sender, name: message.sender) // Fallback
          );
        } catch (e) {
          // debugPrint('查找用戶出錯 for message sender ${message.sender}: $e');
          sender = User(id: message.sender, name: message.sender); // Fallback
        }
        
        // debugPrint('為訊息 #$index 找到發送者: ${sender.name} (ID=${sender.id})');

        return UserMessageWidget(
          message: message,
          isMe: isMe,
          isDarkMode: isDarkMode,
          sender: sender, // Pass the found or fallback user object
          timeString: _formatTime(message.timestamp),
        );
      },
    );
  }
  
  Widget _buildMessageInput(BuildContext context, bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(26),
            blurRadius: 4.0,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              onPressed: _connected ? () {
                _showMobileAttachmentsMenu(context);
              } : null,
              icon: Icon(
                Icons.add_circle_outline,
                color: _connected 
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey,
              ),
            ),
            
            Expanded(
              child: TextField(
                controller: _messageController,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: '輸入訊息... ',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 10.0,
                  ),
                  filled: true,
                  fillColor: isDarkMode ? Colors.grey[800] : Colors.grey[200],
                ),
                maxLines: null,
                minLines: 1,
                enabled: _connected,
                onChanged: (_) => _sendTypingNotification(),
                onSubmitted: (value) {
                  if (value.trim().isNotEmpty && _connected) { // Check connected here too
                    _sendMessage();
                  }
                },
                scrollPhysics: const BouncingScrollPhysics(),
                style: TextStyle(
                  fontSize: 16.0,
                  color: isDarkMode ? Colors.white : Colors.black,
                ),
              ),
            ),
            const SizedBox(width: 8.0),
            
            IconButton(
              onPressed: _connected && _messageController.text.trim().isNotEmpty 
                  ? _sendMessage 
                  : null,
              icon: Icon(
                Icons.send_rounded,
                color: _connected && _messageController.text.trim().isNotEmpty 
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  void _showCloseRoomDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('關閉聊天室'),
        content: const Text('確定要關閉整個聊天室嗎？此操作無法復原。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _closeRoom();
            },
            child: const Text('確定'),
          ),
        ],
      ),
    );
  }
  
  void _showMobileAttachmentsMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo),
            title: const Text('圖片'),
            onTap: () {
              Navigator.pop(context);
              debugPrint("圖片選擇功能待實現");
            },
          ),
          ListTile(
            leading: const Icon(Icons.mic),
            title: const Text('語音'),
            onTap: () {
              Navigator.pop(context);
              debugPrint("語音功能待實現");
            },
          ),
          ListTile(
            leading: const Icon(Icons.insert_drive_file),
            title: const Text('檔案'),
            onTap: () {
              Navigator.pop(context);
              debugPrint("檔案選擇功能待實現");
            },
          ),
        ],
      ),
    );
  }
}