import 'package:shared_preferences/shared_preferences.dart';

/// 用户资料：当前仅维护昵称，后续可扩展头像与偏好。
class UserProfile {
  const UserProfile({required this.nickname});

  final String nickname;
}

/// 个人信息本地存储：首启自动生成随机昵称，支持后续修改。
class ProfileStore {
  static const _nicknameKey = 'profile_nickname_v1';

  static const List<String> _adjectives = <String>[
    '热血',
    '轻松',
    '稳准',
    '节拍',
    '旋律',
    '和弦',
    '清音',
    '追光',
  ];

  static const List<String> _nouns = <String>[
    '吉他手',
    '练习者',
    '节奏控',
    '扫弦侠',
    '音阶客',
    '木吉他',
    '即兴者',
    '弹唱家',
  ];

  /// 读取资料；若无昵称则按时间生成一个随机昵称并持久化。
  Future<UserProfile> loadOrCreate() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_nicknameKey);
    if (saved != null && saved.trim().isNotEmpty) {
      return UserProfile(nickname: saved.trim());
    }
    final nickname = _generateRandomNickname(
      DateTime.now().millisecondsSinceEpoch,
    );
    await prefs.setString(_nicknameKey, nickname);
    return UserProfile(nickname: nickname);
  }

  /// 保存昵称；空白输入会回退为随机昵称，避免出现空展示。
  Future<UserProfile> saveNickname(String raw) async {
    final value = raw.trim();
    final next = value.isEmpty
        ? _generateRandomNickname(DateTime.now().millisecondsSinceEpoch)
        : value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nicknameKey, next);
    return UserProfile(nickname: next);
  }

  String _generateRandomNickname(int seed) {
    final adjective = _adjectives[seed % _adjectives.length];
    final noun = _nouns[(seed ~/ 13) % _nouns.length];
    final suffix = (seed % 900 + 100).toString();
    return '$adjective$noun$suffix';
  }
}
