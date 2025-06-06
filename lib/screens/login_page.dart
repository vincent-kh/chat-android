import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:chat/screens/chat_room.dart';
import 'package:chat/services/connection_service.dart';

// 移除 Web 相關的 WebSocket 實現
WebSocketChannel getWebSocketChannel(String url) {
  // 只使用移動平台的 IO 實現
  return IOWebSocketChannel.connect(
    Uri.parse(url),
    pingInterval: const Duration(seconds: 5),
  );
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _usernameController = TextEditingController();
  // 修改預設 IP，根據您的需求調整
  final TextEditingController _serverController = TextEditingController(text: '10.0.2.2');
  final TextEditingController _portController = TextEditingController(text: '8080');
  final _formKey = GlobalKey<FormState>();
  bool _isLoggingIn = false;
  String _errorMessage = '';
  
  // 預設伺服器列表，包含模擬器和實體設備地址
  final List<Map<String, String>> _serverPresets = [
    {'name': '本機伺服器 (模擬器)', 'address': '10.0.2.2', 'port': '8080'},
    {'name': '本機伺服器 (實體設備)', 'address': '192.168.1.5', 'port': '8080'}, // 替換為您的實際 IP
    {'name': 'localhost (僅限實體設備)', 'address': '127.0.0.1', 'port': '8080'},
  ];

  // 使用者名稱驗證的正規表達式
  static final RegExp _usernameRegex = RegExp(
    r'^[a-zA-Z0-9\u4e00-\u9fff_-]{2,20}$'
  );
  
  // 額外的禁用詞列表
  static final List<String> _forbiddenUsernames = [
    'admin', 'administrator', 'system', 'root', 'server', 'superuser', 'all', 'everyone'
  ];
  
  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('聊天室登入'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // App Logo or Icon
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Icon(
                    Icons.chat_rounded,
                    size: 80,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                Text(
                  'Socket 聊天室',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 32),
                
                // 使用者名稱欄位
                TextFormField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: '使用者名稱',
                    hintText: '請輸入使用者名稱',
                    prefixIcon: Icon(Icons.person),
                    helperText: '2-20個字符，支持中英文、數字、底線、連字號',
                  ),
                  keyboardType: TextInputType.name,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  enableSuggestions: false,
                  maxLength: 20,
                  enabled: !_isLoggingIn,
                  validator: (_) => _getUsernameError(),
                ),
                const SizedBox(height: 16),
                
                // 伺服器設定卡片
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.dns, color: Theme.of(context).colorScheme.secondary),
                            const SizedBox(width: 8),
                            const Text(
                              '伺服器設定',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            // 預設伺服器選擇按鈕
                            PopupMenuButton<Map<String, String>>(
                              icon: const Icon(Icons.more_vert),
                              tooltip: '選擇預設伺服器',
                              enabled: !_isLoggingIn,
                              onSelected: (Map<String, String> server) {
                                setState(() {
                                  _serverController.text = server['address']!;
                                  _portController.text = server['port']!;
                                });
                              },
                              itemBuilder: (context) {
                                return _serverPresets.map((server) {
                                  return PopupMenuItem<Map<String, String>>(
                                    value: server,
                                    child: Text(server['name']!),
                                  );
                                }).toList();
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        
                        // 伺服器地址
                        TextFormField(
                          controller: _serverController,
                          decoration: const InputDecoration(
                            labelText: '伺服器地址',
                            hintText: '127.0.0.1',
                            prefixIcon: Icon(Icons.wifi),
                          ),
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.next,
                          enabled: !_isLoggingIn,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return '請輸入伺服器地址';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        
                        // 伺服器端口
                        TextFormField(
                          controller: _portController,
                          decoration: const InputDecoration(
                            labelText: '伺服器端口',
                            hintText: '8080',
                            prefixIcon: Icon(Icons.numbers),
                          ),
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          enabled: !_isLoggingIn,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return '請輸入伺服器端口';
                            }
                            int? port = int.tryParse(value);
                            if (port == null || port <= 0 || port > 65535) {
                              return '端口必須在1-65535之間';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                
                // 錯誤訊息
                if (_errorMessage.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade300),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  ),
                
                const SizedBox(height: 16),
                
                // 登入按鈕
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoggingIn ? null : _submitForm,
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      disabledBackgroundColor: Colors.grey,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoggingIn
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 3,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                '連接中...',
                                style: TextStyle(
                                  color: isDarkMode ? Colors.white : Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          )
                        : const Text('進入聊天室', style: TextStyle(fontSize: 16)),
                  ),
                ),
                
                // 使用者名稱規則說明
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDarkMode 
                      ? Colors.blue.withValues(alpha: 0.2) 
                      : Colors.blue.withAlpha(26),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, 
                              color: isDarkMode ? Colors.blue[400] : Colors.blue[700], 
                              size: 20),
                          const SizedBox(width: 8),
                          Text(
                            '使用者名稱規則',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isDarkMode ? Colors.blue[400] : Colors.blue[700],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text('• 長度：2-20個字符'),
                      const Text('• 允許：中文、英文字母、數字、底線(_)、連字號(-)'),
                      const Text('• 不允許：特殊符號、空格'),
                      const Text('• 禁止：系統保留詞（如 admin、system 等）'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 獲取使用者名稱錯誤訊息
  String? _getUsernameError() {
    final username = _usernameController.text.trim();
    if (username.isEmpty) return null; // 空白時不顯示錯誤
    return _validateUsername(username);
  }

  // 使用者名稱驗證
  String? _validateUsername(String username) {
    if (username.isEmpty) {
      return '使用者名稱不能為空';
    }
    
    if (username.length < 2) {
      return '使用者名稱至少需要2個字符';
    }
    
    if (username.length > 20) {
      return '使用者名稱不能超過20個字符';
    }
    
    // 檢查格式
    if (!_usernameRegex.hasMatch(username)) {
      return '使用者名稱只能包含中文、英文字母、數字、底線或連字號';
    }
    
    // 檢查是否為禁用詞
    if (_forbiddenUsernames.contains(username.toLowerCase())) {
      return '此名稱為系統保留詞，請選擇其他名稱';
    }
    
    // 檢查是否全為數字
    if (RegExp(r'^\d+$').hasMatch(username)) {
      return '使用者名稱不能全為數字';
    }

    // 檢查是否以特殊字符開頭或結尾
    if (username.startsWith('_') || username.startsWith('-') ||
        username.endsWith('_') || username.endsWith('-')) {
      return '使用者名稱不能以底線或連字號開頭或結尾';
    }

    return null; // 驗證通過
  }
  
  // 提交表單
  void _submitForm() {
    if (_formKey.currentState!.validate()) {
      _login();
    }
  }

  Future<void> _login() async {
    final username = _usernameController.text.trim();
    final server = _serverController.text.trim();
    final portText = _portController.text.trim();
    
    // 驗證輸入（保持原有驗證邏輯）
    final usernameError = _validateUsername(username);
    if (usernameError != null) {
      setState(() {
        _errorMessage = usernameError;
      });
      return;
    }
    
    if (server.isEmpty) {
      setState(() {
        _errorMessage = '請輸入伺服器地址';
      });
      return;
    }
    
    if (portText.isEmpty) {
      setState(() {
        _errorMessage = '請輸入伺服器端口';
      });
      return;
    }
    
    int? port = int.tryParse(portText);
    if (port == null || port <= 0 || port > 65535) {
      setState(() {
        _errorMessage = '伺服器端口必須是1-65535之間的數字';
      });
      return;
    }
    
    setState(() {
      _isLoggingIn = true;
      _errorMessage = '';
    });
    
    try {
      final connectionService = ConnectionService();
      
      // 詳細的連接檢查流程
      debugPrint('=== 開始連接檢查 ===');
      
      // 1. 檢查基本網絡狀態
      debugPrint('1. 檢查網絡連接...');
      bool isConnected = await connectionService.isConnected();
      if (!isConnected) {
        throw Exception('沒有可用的網絡連接，請檢查 WiFi 或移動數據');
      }
      debugPrint('✓ 網絡連接正常');
      
      // 2. 測試主機連接性
      debugPrint('2. 測試伺服器連接性...');
      bool canReachHost = await connectionService.canReachHost(server, port);
      if (!canReachHost) {
        throw Exception('無法連接到伺服器 $server:$port\n請確認：\n1. 伺服器正在運行\n2. 端口 $port 已開放\n3. 防火牆設定正確');
      }
      debugPrint('✓ 伺服器可達');
      
      // 3. 建立 WebSocket 連接
      debugPrint('3. 建立 WebSocket 連接...');
      final wsChannel = await connectionService.connectWebSocket(server, port);
      debugPrint('✓ WebSocket 連接成功');
      
      // 4. 發送登入訊息
      debugPrint('4. 發送登入訊息...');
      final message = {
        'type': 'join',
        'username': username,
      };
      
      wsChannel.sink.add(jsonEncode(message));
      debugPrint('✓ 登入訊息已發送: $message');
      
      // 5. 等待一小段時間確保訊息發送
      await Future.delayed(const Duration(milliseconds: 500));
      
      // 6. 導航到聊天室
      if (mounted) {
        debugPrint('6. 導航到聊天室...');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ChatRoom(
              webSocket: wsChannel,
              username: username,
              useWebSocket: true,
              serverInfo: '$server:$port',
            ),
          ),
        );
      }
      
    } catch (e) {
      debugPrint('❌ 連接失敗: $e');
      
      if (mounted) {
        setState(() {
          _isLoggingIn = false;
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
        
        // 顯示詳細錯誤信息
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('連接失敗: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(8),
            duration: const Duration(seconds: 6), // 增加顯示時間
            action: SnackBarAction(
              label: '確定',
              textColor: Colors.white,
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
              },
            ),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _serverController.dispose();
    _portController.dispose();
    super.dispose();
  }
}