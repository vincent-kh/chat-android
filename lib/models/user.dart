class User {
  final String id;
  final String name;
  bool isAdmin;
  bool isRoot; // 新增
  bool isTyping; // 如果您也追蹤這個
  String? avatarUrl; // Added avatarUrl field

  User({
    required this.id,
    required this.name,
    this.isAdmin = false,
    this.isRoot = false, // 新增
    this.isTyping = false,
    this.avatarUrl,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? json['user_id'] ?? '',
      name: json['name'] ?? json['username'] ?? json['id'] ?? '',
      isAdmin: json['isAdmin'] ?? json['is_admin'] ?? false,
      avatarUrl: json['avatarUrl'] ?? json['avatar_url'],
      isTyping: json['isTyping'] ?? json['is_typing'] ?? false,
    );
  }
}