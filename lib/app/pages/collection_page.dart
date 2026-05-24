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

  bool isSelectionMode = false;
  Set<String> selectedPostIds = {};

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

  void startSelection(String id) {
    setState(() {
      isSelectionMode = true;
      selectedPostIds.add(id);
    });
  }

  void toggleSelection(String id) {
    setState(() {
      if (selectedPostIds.contains(id)) {
        selectedPostIds.remove(id);
      } else {
        selectedPostIds.add(id);
      }

      if (selectedPostIds.isEmpty) {
        isSelectionMode = false;
      }
    });
  }

  void clearSelection() {
    setState(() {
      isSelectionMode = false;
      selectedPostIds.clear();
    });
  }

  Future<void> deleteSelectedPosts() async {
    if (selectedPostIds.isEmpty) return;

    final ids = selectedPostIds.toList();

    for (final id in ids) {
      await _firestoreService.moveToTrash(id);
    }

    clearSelection();
    await loadCollectedPosts();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${ids.length}개를 휴지통으로 이동했습니다.'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
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
    if (isSelectionMode) {
      clearSelection();
      return;
    }

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

    if (url.isNotEmpty && url != 'uploaded_image' && url != 'uploaded_file') {
      return url;
    }

    return '제목 없음';
  }

  bool isNumberedLine(String line) {
    final numbers = [
      '①',
      '②',
      '③',
      '④',
      '⑤',
      '⑥',
      '⑦',
      '⑧',
      '⑨',
      '⑩',
      '⑪',
      '⑫',
      '⑬',
      '⑭',
      '⑮',
      '⑯',
      '⑰',
      '⑱',
      '⑲',
      '⑳',
    ];

    return numbers.any((number) => line.trim().startsWith(number));
  }

  bool isSectionTitleLine(String line) {
    return RegExp(r'^\d+\)\s+').hasMatch(line.trim());
  }

  bool isDashLine(String line) {
    return line.trim().startsWith('-');
  }

  String cleanPreviewLine(String line) {
    var cleaned = line.trim();

    cleaned = cleaned.replaceFirst(RegExp(r'^[•●▪▫]\s*'), '');

    if (cleaned.startsWith('-')) {
      cleaned = '- ${cleaned.substring(1).trim()}';
    }

    if (cleaned.contains('▶')) {
      cleaned = cleaned.split('▶').first.trim();
    }

    if (cleaned.contains('➔')) {
      cleaned = cleaned.split('➔').first.trim();
    }

    if (cleaned.contains('→')) {
      cleaned = cleaned.split('→').first.trim();
    }

    if (cleaned.contains(':') && cleaned.startsWith('-')) {
      final parts = cleaned.split(':');
      if (parts.first.trim().length <= 20) {
        cleaned = parts.first.trim();
      }
    }

    return cleaned.trim();
  }

  List<String> getSummaryLines(Map<String, dynamic> post) {
    final shortSummary = (post['shortSummary'] ?? '').toString().trim();
    final summary = (post['summary'] ?? '').toString().trim();
    final detailSummary = (post['detailSummary'] ?? '').toString().trim();
    final url = (post['url'] ?? '').toString().trim();

    final sourceText = shortSummary.isNotEmpty
        ? shortSummary
        : summary.isNotEmpty
            ? summary
            : detailSummary;

    if (sourceText.isNotEmpty) {
      final rawLines = sourceText
          .split('\n')
          .map((e) => cleanPreviewLine(e))
          .where((e) => e.isNotEmpty)
          .where((e) => !e.contains('대한 내용입니다'))
          .where((e) => !e.contains('나뉘어 있습니다'))
          .toList();

      final result = <String>[];

      for (final line in rawLines) {
        if (isSectionTitleLine(line)) {
          result.add(line);
          continue;
        }

        if (isDashLine(line)) {
          result.add(line);
        }

        if (result.length >= 3) break;
      }

      if (result.isNotEmpty) {
        return result.take(3).toList();
      }

      return rawLines.take(3).toList();
    }

    if (url.isNotEmpty && url != 'uploaded_image' && url != 'uploaded_file') {
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
        rawImageUrls.map((e) => e.toString().trim()).where((e) {
          return e.isNotEmpty && e != 'uploaded_image' && e != 'uploaded_file';
        }),
      );
    }

    final rawImageUrlsSnake = post['image_urls'];
    if (rawImageUrlsSnake is List) {
      result.addAll(
        rawImageUrlsSnake.map((e) => e.toString().trim()).where((e) {
          return e.isNotEmpty && e != 'uploaded_image' && e != 'uploaded_file';
        }),
      );
    }

    final thumbnail = (post['thumbnail'] ?? '').toString().trim();
    if (thumbnail.isNotEmpty &&
        thumbnail != 'uploaded_image' &&
        thumbnail != 'uploaded_file') {
      result.add(thumbnail);
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

  Widget buildSelectionBar() {
    if (!isSelectionMode) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: Color(0x12000000),
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Text(
              '${selectedPostIds.length}개 선택됨',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.charcoal,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: clearSelection,
              child: const Text('취소'),
            ),
            TextButton.icon(
              onPressed: deleteSelectedPosts,
              icon: const Icon(Icons.delete_outline),
              label: const Text('삭제'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.redAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildThumbnail(String imageUrl) {
    final fixedUrl = normalizeImageUrl(imageUrl);

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Image.network(
        fixedUrl,
        width: 116,
        height: 116,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget buildSummaryLine(String line, {double height = 1.6}) {
    final trimmed = cleanPreviewLine(line);

    if (trimmed.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
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
      final shortSummary = (post['shortSummary'] ?? '').toString().toLowerCase();
      final detailSummary =
          (post['detailSummary'] ?? '').toString().toLowerCase();
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
          shortSummary.contains(query) ||
          detailSummary.contains(query) ||
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
                if (isSelectionMode) {
                  clearSelection();
                }

                setState(() {
                  categoryTab = newValue;
                });
              },
            ),
            buildSelectionBar(),
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
                    onTap: isSelectionMode
                        ? null
                        : () {
                            setState(() {
                              sortOrder =
                                  sortOrder == 'recent' ? 'oldest' : 'recent';
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
                            final bool isSelected =
                                selectedPostIds.contains(id);

                            final String category = getEffectiveCategory(post);
                            final String dateText =
                                formatDate(post['createdAt']);
                            final String title = getDisplayTitle(post);
                            final List<String> summaryLines =
                                getSummaryLines(post);
                            final List<String> tags = getTags(post);
                            final List<String> imageUrls = getImageUrls(post);

                            final Color cardBackgroundColor = isSelected
                                ? const Color(0xFFFFF2EE)
                                : AppColors.surface;

                            return GestureDetector(
                              onLongPress: () {
                                startSelection(id);
                              },
                              onTap: () {
                                if (isSelectionMode) {
                                  toggleSelection(id);
                                  return;
                                }

                                Navigator.pushNamed(
                                  context,
                                  AppRoutes.post,
                                  arguments: id,
                                );
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: cardBackgroundColor,
                                  borderRadius: BorderRadius.circular(30),
                                  border: Border.all(
                                    color: isSelected
                                        ? AppColors.peachDust
                                        : Colors.transparent,
                                    width: 1.5,
                                  ),
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
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        if (isSelectionMode) ...[
                                          GestureDetector(
                                            onTap: () => toggleSelection(id),
                                            child: Icon(
                                              isSelected
                                                  ? Icons.check_circle
                                                  : Icons.radio_button_unchecked,
                                              size: 24,
                                              color: isSelected
                                                  ? AppColors.peachDust
                                                  : AppColors.textDisabled,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                        ],
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
                                        if (!isSelectionMode) ...[
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
                                                    fontWeight:
                                                        FontWeight.w500,
                                                  ),
                                                ),
                                              );
                                            }).toList(),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        if (!isSelectionMode)
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