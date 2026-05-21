import 'package:flutter/material.dart';

import '../routes/app_routes.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_radii.dart';
import '../widgets/bottom_nav.dart';

class MyPage extends StatefulWidget {
  const MyPage({super.key});

  @override
  State<MyPage> createState() => _MyPageState();
}

class _MyPageState extends State<MyPage> {
  final AuthService _authService = AuthService();

  int activeTab = 1;

  String nickname = '사용자';
  String email = '';

  @override
  void initState() {
    super.initState();
    loadUserInfo();
  }

  Future<void> loadUserInfo() async {
    final user = await _authService.reloadCurrentUser();

    if (!mounted) return;

    setState(() {
      nickname =
          user?.displayName != null && user!.displayName!.trim().isNotEmpty
              ? user.displayName!
              : '사용자';

      email = user?.email ?? '';
    });
  }

  void handleTabChange(int tab) {
    setState(() {
      activeTab = tab;
    });

    if (tab == 0) {
      Navigator.pushNamed(context, AppRoutes.archive);
    } else if (tab == 1) {
      Navigator.pushNamed(context, AppRoutes.home);
    } else if (tab == 2) {
      Navigator.pushNamed(context, AppRoutes.collection);
    }
  }

  String getProfileLetter() {
    final trimmedNickname = nickname.trim();
    final trimmedEmail = email.trim();

    if (trimmedNickname.isNotEmpty) {
      return trimmedNickname[0].toUpperCase();
    }

    if (trimmedEmail.isNotEmpty) {
      return trimmedEmail[0].toUpperCase();
    }

    return 'MY';
  }

  Future<void> goToAccountSettings() async {
    final result = await Navigator.pushNamed(
      context,
      AppRoutes.accountSettings,
    );

    if (result == true) {
      await loadUserInfo();
    }
  }

  @override
  Widget build(BuildContext context) {
    final String profileLetter = getProfileLetter();
    final String displayNickname =
        nickname.trim().isNotEmpty ? nickname.trim() : '사용자';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.charcoal,
        title: const Text(
          'MY',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 22,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 120),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F0FA),
              borderRadius: BorderRadius.circular(AppRadii.card),
              boxShadow: const [
                BoxShadow(
                  color: Color.fromRGBO(0, 0, 0, 0.04),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    color: AppColors.peachDust,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      profileLetter,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 28,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$displayNickname님',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 22,
                          color: AppColors.charcoal,
                          height: 1.35,
                        ),
                      ),
                      if (email.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadii.card),
              boxShadow: const [
                BoxShadow(
                  color: Color.fromRGBO(0, 0, 0, 0.04),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                ListTile(
                  title: const Text(
                    '계정 설정',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: goToAccountSettings,
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text(
                    '카테고리 관리',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pushNamed(context, AppRoutes.categoryManage);
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text(
                    '휴지통',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pushNamed(context, AppRoutes.trash);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNav(
        activeTab: activeTab,
        onTabChange: handleTabChange,
      ),
    );
  }
}