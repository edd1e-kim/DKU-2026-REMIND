import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../routes/app_routes.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../theme/app_colors.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/home_view.dart';
import '../widgets/top_bar.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final AuthService _authService = AuthService();
  final FirestoreService _firestoreService = FirestoreService();

  int activeTab = 1;
  String searchQuery = '';
  String nickname = '사용자';

  static const String dismissedCategoryPrefsKey =
      'dismissed_suggested_categories';

  final Set<String> dismissedSuggestedCategories = {};

  final Set<String> mainCategoryNames = {
    '자기계발',
    '운동',
    '장소',
    '쇼핑',
  };

  bool isLoadingSuggestion = true;
  String? suggestedCategoryName;
  int suggestedCategoryCount = 0;

  @override
  void initState() {
    super.initState();
    loadUserInfo();
    initializeSuggestion();
  }

  Future<void> loadUserInfo() async {
    final user = await _authService.reloadCurrentUser();

    if (!mounted) return;

    setState(() {
      nickname =
          user?.displayName != null && user!.displayName!.trim().isNotEmpty
              ? user.displayName!
              : '사용자';
    });
  }

  Future<void> initializeSuggestion() async {
    await loadDismissedCategories();
    await loadCategorySuggestion();
  }

  Future<void> loadDismissedCategories() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(dismissedCategoryPrefsKey) ?? <String>[];

    dismissedSuggestedCategories
      ..clear()
      ..addAll(saved);
  }

  Future<void> saveDismissedCategories() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      dismissedCategoryPrefsKey,
      dismissedSuggestedCategories.toList(),
    );
  }

  Future<void> loadCategorySuggestion() async {
    final data = await _firestoreService.getPosts();

    if (!mounted) return;

    final Map<String, int> tagCounts = {};

    for (final post in data) {
      final bool isDeleted = post['isDeleted'] ?? false;
      if (isDeleted) continue;

      final category = (post['category'] ?? '').toString().trim();

      if (mainCategoryNames.contains(category)) continue;
      if (category != '기타') continue;

      final rawTags = post['tags'];

      if (rawTags is! List || rawTags.isEmpty) continue;

      final firstTag = rawTags.first.toString().trim().replaceAll('#', '');

      if (firstTag.isEmpty) continue;
      if (mainCategoryNames.contains(firstTag)) continue;
      if (dismissedSuggestedCategories.contains(firstTag)) continue;

      tagCounts[firstTag] = (tagCounts[firstTag] ?? 0) + 1;
    }

    String? pickedCategory;
    int pickedCount = 0;

    for (final entry in tagCounts.entries) {
      if (entry.value >= 2 && entry.value > pickedCount) {
        pickedCategory = entry.key;
        pickedCount = entry.value;
      }
    }

    setState(() {
      suggestedCategoryName = pickedCategory;
      suggestedCategoryCount = pickedCount;
      isLoadingSuggestion = false;
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

  Future<void> dismissSuggestion() async {
    final category = suggestedCategoryName;
    if (category == null) return;

    dismissedSuggestedCategories.add(category);
    await saveDismissedCategories();

    if (!mounted) return;

    setState(() {
      suggestedCategoryName = null;
      suggestedCategoryCount = 0;
    });
  }

  Future<void> goToCategoryManage() async {
    final category = suggestedCategoryName;
    if (category != null) {
      dismissedSuggestedCategories.add(category);
      await saveDismissedCategories();
    }

    if (!mounted) return;

    setState(() {
      suggestedCategoryName = null;
      suggestedCategoryCount = 0;
    });

    Navigator.pushNamed(context, AppRoutes.categoryManage);
  }

  Widget buildGreetingCard() {
    final displayNickname = nickname.trim().isNotEmpty ? nickname.trim() : '사용자';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Color.fromRGBO(0, 0, 0, 0.04),
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: AppColors.peachDust,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  displayNickname[0].toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$displayNickname님, 반가워요',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppColors.charcoal,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '오늘도 저장한 콘텐츠를 다시 확인해볼까요?',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool showCategoryAlert =
        !isLoadingSuggestion &&
        suggestedCategoryName != null &&
        suggestedCategoryCount >= 2;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            TopBar(
              searchQuery: searchQuery,
              onSearchChange: (value) {
                setState(() {
                  searchQuery = value;
                });
              },
            ),
            buildGreetingCard(),
            if (showCategoryAlert)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDFF1FB),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(
                          Icons.category,
                          color: Color(0xFF2B8CCF),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$suggestedCategoryName 관련 글이 $suggestedCategoryCount개 이상입니다. 새로운 카테고리로 추가하시겠어요?',
                              style: const TextStyle(
                                fontSize: 15,
                                height: 1.45,
                                color: Color(0xFF0F3554),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: goToCategoryManage,
                                style: TextButton.styleFrom(
                                  backgroundColor: const Color(0xFFEAF4FD),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                                child: const Text(
                                  '생성하기',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                    color: Color(0xFF0F3554),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: dismissSuggestion,
                        icon: const Icon(
                          Icons.close,
                          color: Color(0xFF4E5968),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: HomeView(searchQuery: searchQuery),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNav(
        activeTab: activeTab,
        onTabChange: handleTabChange,
      ),
    );
  }
}