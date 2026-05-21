import 'package:flutter/material.dart';

import '../theme/app_categories.dart';
import '../routes/app_routes.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../theme/app_colors.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/category_tabs.dart';
import '../widgets/top_bar.dart';

class CollectionPage extends StatefulWidget {
  const CollectionPage({super.key});

  @override
  State<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<CollectionPage> {
  final AuthService _authService = AuthService();
  final FirestoreService _firestoreService = FirestoreService();

  int activeTab = 2;
  int categoryTab = 0;
  String searchQuery = '';
  String sortOrder = 'recent';

  String nickname = '사용자';

  List<Map<String, dynamic>> collectedPosts = [];
  List<String> mainCategoryNames = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    loadUserInfo();
    loadCollectedPosts();
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

  Future<void> loadCollectedPosts() async {
    final data = await _firestoreService.getCollectedPosts();
    final categories = await _firestoreService.getCategories();

    if (!mounted) return;

    final mains = categories
        .where((e) => (e['isMain'] ?? false) == true)
        .map((e) => (e['name'] ?? '').toString().trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList();

    setState(() {
      collectedPosts = data;
      mainCategoryNames = mains;
      isLoading = false;
    });
  }

  Future<void> toggleFavoriteStatus(String id, bool currentValue) async {
    await _firestoreService.updateFavoriteStatus(id, !currentValue);
    await loadCollectedPosts();
  }

  Future<void> togglePinnedStatus(String id, bool currentValue) async {
    await _firestoreService.updatePinnedStatus(id, !currentValue);
    await loadCollectedPosts();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(currentValue ? '고정을 해제했습니다.' : '홈에 고정했습니다.'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> moveToArchive(String id) async {
    await _firestoreService.updateCollectedStatus(id, false);
    await loadCollectedPosts();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('아카이브로 이동했습니다.'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> moveToTrash(String id) async {
    await _firestoreService.moveToTrash(id);
    await loadCollectedPosts();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('휴지통으로 이동했습니다.'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> showDeleteDialog(String id) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('휴지통 이동'),
          content: const Text('이 컬렉션을 휴지통으로 이동할까요?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('이동'),
            ),
          ],
        );
      },
    );

    if (result == true) {
      await moveToTrash(id);
    }
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
      loadCollectedPosts();
    }
  }

  int getPriority(Map<String, dynamic> post) {
    final bool isFavorite = post['isFavorite'] ?? false;
    final bool isPinned = post['isPinned'] ?? false;
    final bool isRead = post['isRead'] ?? false;

    if (isFavorite && isPinned) return 1;
    if (isFavorite && !isRead) return 2;
    if (isFavorite && isRead) return 3;
    if (!isFavorite && !isRead) return 4;
    return 5;
  }

  DateTime getCreatedAt(Map<String, dynamic> post) {
    final createdAt = post['createdAt'];

    if (createdAt == null) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    if (createdAt is DateTime) {
      return createdAt;
    }

    try {
      return createdAt.toDate();
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  String formatDate(dynamic createdAt) {
    try {
      if (createdAt == null) return '날짜 없음';

      if (createdAt is DateTime) {
        return '${createdAt.year}.${createdAt.month.toString().padLeft(2, '0')}.${createdAt.day.toString().padLeft(2, '0')}';
      }

      if (createdAt.toString().contains('Timestamp')) {
        final date = createdAt.toDate();
        return '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
      }

      return createdAt.toString();
    } catch (_) {
      return '날짜 없음';
    }
  }

  String getDisplayTitle(Map<String, dynamic> post) {
    final title = (post['title'] ?? '').toString().trim();
    final url = (post['url'] ?? '').toString().trim();

    if (title.isNotEmpty) return title;
    if (url.isNotEmpty) return url;
    return '제목 없음';
  }

  bool isNumberedLine(String line) {
    final numbers = ['①', '②', '③', '④', '⑤', '⑥', '⑦', '⑧', '⑨', '⑩'];
    return numbers.any((number) => line.trim().startsWith(number));
  }

  List<String> getSummaryLines(Map<String, dynamic> post) {
    final summary = (post['summary'] ?? '').toString().trim();
    final url = (post['url'] ?? '').toString().trim();

    if (summary.isNotEmpty) {
      return summary
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .map((e) {
            if (isNumberedLine(e)) {
              return e;
            }

            return e.replaceFirst(RegExp(r'^[•\-\*\.·]+\s*'), '');
          })
          .where((e) => e.isNotEmpty)
          .take(3)
          .toList();
    }

    if (url.isNotEmpty) {
      return [url];
    }

    return ['요약 정보가 없습니다.'];
  }

  List<String> getTags(Map<String, dynamic> post) {
    final rawTags = post['tags'];

    if (rawTags is List) {
      final parsed = rawTags
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .map((e) => e.startsWith('#') ? e : '#$e')
          .take(3)
          .toList();

      if (parsed.isNotEmpty) return parsed;
    }

    final category = (post['category'] ?? '기타').toString();

    switch (category) {
      case '자기계발':
        return ['#아침루틴', '#습관'];
      case '운동':
        return ['#헬스', '#기록'];
      case '장소':
        return ['#장소', '#저장'];
      case '쇼핑':
        return ['#쇼핑', '#구매'];
      default:
        return ['#링크', '#저장'];
    }
  }

  Color getCategoryChipColor(String category) {
    switch (category) {
      case '자기계발':
        return const Color(0xFFF6E5DF);
      case '운동':
        return const Color(0xFFDDEBE5);
      case '장소':
        return const Color(0xFFF5EFD9);
      case '쇼핑':
        return const Color(0xFFF7E5D9);
      default:
        return const Color(0xFFE8F0FA);
    }
  }

  String getEffectiveCategory(Map<String, dynamic> post) {
    final category = (post['category'] ?? '기타').toString().trim();

    if (category != '기타') return category;

    final tags = post['tags'];

    if (tags is List && tags.isNotEmpty) {
      final firstTag = tags.first.toString().replaceAll('#', '').trim();

      final knownCategories = {
        ...mainCategoryNames,
        '음악',
      };

      if (knownCategories.contains(firstTag)) {
        return firstTag;
      }
    }

    return category;
  }

  List<String> getImageUrls(Map<String, dynamic> post) {
    final List<String> result = [];

    final rawImageUrls = post['imageUrls'];
    if (rawImageUrls is List) {
      result.addAll(
        rawImageUrls
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .where((e) => e != 'uploaded_image')
            .where((e) => e != 'uploaded_file'),
      );
    }

    final rawImageUrlsSnake = post['image_urls'];
    if (rawImageUrlsSnake is List) {
      result.addAll(
        rawImageUrlsSnake
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .where((e) => e != 'uploaded_image')
            .where((e) => e != 'uploaded_file'),
      );
    }

    return result.toSet().toList();
  }

  String normalizeImageUrl(String imageUrl) {
    final url = imageUrl.trim();

    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }

    if (url.startsWith('/')) {
      return 'http://127.0.0.1:8000$url';
    }

    return 'http://127.0.0.1:8000/$url';
  }

  Widget buildThumbnail(String imageUrl) {
    final fixedUrl = normalizeImageUrl(imageUrl);

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        width: 116,
        height: 116,
        child: Image.network(
          fixedUrl,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  Widget buildSummaryLine(String line, {double height = 1.6}) {
    final trimmed = line.trim();

    if (isNumberedLine(trimmed)) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            trimmed,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              height: height,
              fontWeight: FontWeight.w500,
              color: AppColors.charcoal,
            ),
          ),
        ),
      );
    }

    final cleaned = trimmed.replaceFirst(RegExp(r'^[•\-\*\.·]+\s*'), '');

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '• ',
            style: TextStyle(fontSize: 14),
          ),
          Expanded(
            child: Text(
              cleaned,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                height: height,
                fontWeight: FontWeight.w500,
                color: AppColors.charcoal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildSummaryArea({
    required List<String> summaryLines,
    required List<String> imageUrls,
  }) {
    if (imageUrls.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: summaryLines.map((line) => buildSummaryLine(line)).toList(),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildThumbnail(imageUrls.first),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children:
                summaryLines.map((line) => buildSummaryLine(line)).toList(),
          ),
        ),
      ],
    );
  }

  String? getSelectedMainCategoryName() {
    final int dynamicIndex = categoryTab - AppCategories.fixedTabs.length;

    if (dynamicIndex < 0 || dynamicIndex >= mainCategoryNames.length) {
      return null;
    }

    return mainCategoryNames[dynamicIndex];
  }

  @override
  Widget build(BuildContext context) {
    final filteredPosts = collectedPosts.where((post) {
      final title = (post['title'] ?? '').toString().toLowerCase();
      final summary = (post['summary'] ?? '').toString().toLowerCase();
      final url = (post['url'] ?? '').toString().toLowerCase();
      final query = searchQuery.toLowerCase();
      final isFavorite = post['isFavorite'] ?? false;
      final isDeleted = post['isDeleted'] ?? false;
      final category = getEffectiveCategory(post);

      if (isDeleted == true) return false;

      final categoryText = category.toLowerCase();
      final memo = (post['memo'] ?? '').toString().toLowerCase();

      final matchesSearch = title.contains(query) ||
          summary.contains(query) ||
          url.contains(query) ||
          categoryText.contains(query) ||
          memo.contains(query) ||
          getTags(post).join(' ').toLowerCase().contains(query);

      if (!matchesSearch) return false;

      if (categoryTab == 0) return true;
      if (categoryTab == 1) return isFavorite == true;

      final selectedCategory = getSelectedMainCategoryName();
      if (selectedCategory != null) {
        return category == selectedCategory;
      }

      if (categoryTab ==
          AppCategories.fixedTabs.length + mainCategoryNames.length) {
        return category == '기타';
      }

      return true;
    }).toList();

    filteredPosts.sort((a, b) {
      final aPriority = getPriority(a);
      final bPriority = getPriority(b);

      if (aPriority != bPriority) {
        return aPriority.compareTo(bPriority);
      }

      final aDate = getCreatedAt(a);
      final bDate = getCreatedAt(b);

      if (sortOrder == 'oldest') {
        return aDate.compareTo(bDate);
      }

      return bDate.compareTo(aDate);
    });

    final String displayNickname =
        nickname.trim().isNotEmpty ? nickname.trim() : '사용자';

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
            CategoryTabs(
              value: categoryTab,
              onChange: (newValue) {
                setState(() {
                  categoryTab = newValue;
                });
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 34,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4CDC4),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Text(
                  '$displayNickname님의 이번 주 컬렉션이 ${filteredPosts.length}개 쌓였어요',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.charcoal,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
              child: Row(
                children: [
                  Text(
                    '총 ${filteredPosts.length}개의 컬렉션',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.charcoal,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        sortOrder = sortOrder == 'recent' ? 'oldest' : 'recent';
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F4),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        children: [
                          Text(
                            sortOrder == 'recent' ? '최근 저장순' : '오래된 순',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.sort,
                            size: 18,
                            color: AppColors.textSecondary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : filteredPosts.isEmpty
                      ? const Center(
                          child: Text(
                            '컬렉션이 없습니다.',
                            style: TextStyle(
                              fontSize: 16,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                          itemCount: filteredPosts.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 16),
                          itemBuilder: (context, index) {
                            final post = filteredPosts[index];
                            final String id = post['id'] ?? '';
                            final bool isFavorite = post['isFavorite'] ?? false;
                            final bool isPinned = post['isPinned'] ?? false;
                            final String category = getEffectiveCategory(post);
                            final String dateText =
                                formatDate(post['createdAt']);
                            final String title = getDisplayTitle(post);
                            final List<String> summaryLines =
                                getSummaryLines(post);
                            final List<String> tags = getTags(post);
                            final List<String> imageUrls = getImageUrls(post);

                            return GestureDetector(
                              onTap: () {
                                Navigator.pushNamed(
                                  context,
                                  AppRoutes.post,
                                  arguments: id,
                                );
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(30),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x12000000),
                                      blurRadius: 14,
                                      offset: Offset(0, 4),
                                    ),
                                  ],
                                ),
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color:
                                                getCategoryChipColor(category),
                                            borderRadius:
                                                BorderRadius.circular(16),
                                          ),
                                          child: Text(
                                            category,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.charcoal,
                                            ),
                                          ),
                                        ),
                                        const Spacer(),
                                        Text(
                                          dateText,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textDisabled,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        if (isPinned) ...[
                                          const SizedBox(width: 8),
                                          const Icon(
                                            Icons.push_pin,
                                            size: 18,
                                            color: AppColors.peachDust,
                                          ),
                                        ],
                                        const SizedBox(width: 8),
                                        GestureDetector(
                                          onTap: () async {
                                            await toggleFavoriteStatus(
                                              id,
                                              isFavorite,
                                            );
                                          },
                                          child: Icon(
                                            isFavorite
                                                ? Icons.star
                                                : Icons.star_border,
                                            size: 22,
                                            color: isFavorite
                                                ? Colors.amber
                                                : AppColors.textDisabled,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        PopupMenuButton<String>(
                                          icon: const Icon(
                                            Icons.more_horiz,
                                            color: AppColors.textDisabled,
                                          ),
                                          onSelected: (value) async {
                                            if (value == 'pin') {
                                              await togglePinnedStatus(
                                                id,
                                                isPinned,
                                              );
                                            } else if (value == 'archive') {
                                              await moveToArchive(id);
                                            } else if (value == 'delete') {
                                              await showDeleteDialog(id);
                                            }
                                          },
                                          itemBuilder: (context) => [
                                            PopupMenuItem(
                                              value: 'pin',
                                              child: Text(
                                                isPinned
                                                    ? '고정 해제'
                                                    : '홈에 고정',
                                              ),
                                            ),
                                            const PopupMenuItem(
                                              value: 'archive',
                                              child: Text('아카이브로 이동'),
                                            ),
                                            const PopupMenuItem(
                                              value: 'delete',
                                              child: Text('휴지통으로 이동'),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 18),
                                    Text(
                                      title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 19,
                                        fontWeight: FontWeight.w700,
                                        height: 1.35,
                                        color: AppColors.charcoal,
                                      ),
                                    ),
                                    const SizedBox(height: 18),
                                    buildSummaryArea(
                                      summaryLines: summaryLines,
                                      imageUrls: imageUrls,
                                    ),
                                    const SizedBox(height: 12),
                                    const Divider(color: AppColors.divider),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: tags.map((tag) {
                                              return Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 7,
                                                ),
                                                decoration: BoxDecoration(
                                                  color:
                                                      const Color(0xFFF3F3F3),
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                ),
                                                child: Text(
                                                  tag,
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: AppColors
                                                        .textSecondary,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              );
                                            }).toList(),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        const Row(
                                          children: [
                                            Text(
                                              '상세 보기',
                                              style: TextStyle(
                                                fontSize: 14,
                                                color:
                                                    AppColors.textSecondary,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            SizedBox(width: 4),
                                            Icon(
                                              Icons.arrow_forward,
                                              size: 16,
                                              color:
                                                  AppColors.textSecondary,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
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