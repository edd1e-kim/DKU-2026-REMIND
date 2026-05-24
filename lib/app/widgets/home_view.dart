import 'dart:math';
import 'package:flutter/material.dart';

import '../routes/app_routes.dart';
import '../services/firestore_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_radii.dart';

class HomeView extends StatefulWidget {
  final String searchQuery;

  const HomeView({
    super.key,
    this.searchQuery = '',
  });

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  final FirestoreService _firestoreService = FirestoreService();

  List<Map<String, dynamic>> posts = [];
  List<Map<String, dynamic>> randomPosts = [];
  final Set<String> hiddenToday = {};

  bool isLoading = true;
  String sortOrder = 'random';

  @override
  void initState() {
    super.initState();
    loadPosts();
  }

  Future<void> loadPosts() async {
    try {
      final data = await _firestoreService.getPosts();

      if (!mounted) return;

      setState(() {
        posts = data
            .where((post) => (post['isDeleted'] ?? false) == false)
            .toList();
        isLoading = false;
      });

      refreshRandomPosts();
    } catch (e) {
      print('HomeView loadPosts error: $e');

      if (!mounted) return;

      setState(() {
        posts = [];
        randomPosts = [];
        isLoading = false;
      });
    }
  }

  Future<void> togglePinnedStatus(String id, bool currentValue) async {
    await _firestoreService.updatePinnedStatus(id, !currentValue);
    await loadPosts();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          currentValue ? '고정을 해제했습니다.' : '홈에 고정했습니다.',
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> toggleFavoriteStatus(String id, bool currentValue) async {
    await _firestoreService.updateFavoriteStatus(id, !currentValue);
    await loadPosts();
  }

  Future<void> toggleReadStatus(String id, bool currentValue) async {
    await _firestoreService.updateReadStatus(id, !currentValue);
    await loadPosts();
  }

  bool matchesSearch(Map<String, dynamic> post, String query) {
    if (query.trim().isEmpty) return true;

    final q = query.toLowerCase().trim();

    final title = (post['title'] ?? '').toString().toLowerCase();
    final summary = (post['summary'] ?? '').toString().toLowerCase();
    final shortSummary = (post['shortSummary'] ?? '').toString().toLowerCase();
    final detailSummary =
        (post['detailSummary'] ?? '').toString().toLowerCase();
    final url = (post['url'] ?? '').toString().toLowerCase();
    final category = getEffectiveCategory(post).toLowerCase();
    final memo = (post['memo'] ?? '').toString().toLowerCase();

    final tags = (post['tags'] is List)
        ? (post['tags'] as List)
            .map((e) => e.toString().toLowerCase())
            .join(' ')
        : getTags(post).join(' ').toLowerCase();

    return title.contains(q) ||
        summary.contains(q) ||
        shortSummary.contains(q) ||
        detailSummary.contains(q) ||
        url.contains(q) ||
        category.contains(q) ||
        memo.contains(q) ||
        tags.contains(q);
  }

  void refreshRandomPosts() {
    final availablePosts = posts.where((post) {
      final id = (post['id'] ?? '').toString();
      final bool isDeleted = post['isDeleted'] ?? false;

      if (isDeleted) return false;
      if (hiddenToday.contains(id)) return false;
      if (!matchesSearch(post, widget.searchQuery)) return false;

      return true;
    }).toList();

    final selected = [...availablePosts];

    if (sortOrder == 'recent') {
      selected.sort((a, b) => getCreatedAt(b).compareTo(getCreatedAt(a)));
    } else if (sortOrder == 'oldest') {
      selected.sort((a, b) => getCreatedAt(a).compareTo(getCreatedAt(b)));
    } else {
      selected.shuffle(Random());
    }

    if (!mounted) return;

    setState(() {
      randomPosts = selected.take(2).toList();
    });
  }

  void sortRandomPosts(String type) {
    setState(() {
      sortOrder = type;
    });

    refreshRandomPosts();
  }

  void handleHideToday(String postId) {
    setState(() {
      hiddenToday.add(postId);
    });

    refreshRandomPosts();
  }

  @override
  void didUpdateWidget(covariant HomeView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.searchQuery != widget.searchQuery) {
      refreshRandomPosts();
    }
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
        return ['#기록', '#습관'];
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

  String getEffectiveCategory(Map<String, dynamic> post) {
    final category = (post['category'] ?? '기타').toString().trim();

    if (category != '기타') return category;

    final tags = post['tags'];

    if (tags is List && tags.isNotEmpty) {
      final firstTag = tags.first.toString().replaceAll('#', '').trim();

      final knownCategories = {
        '자기계발',
        '운동',
        '장소',
        '쇼핑',
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

  Color getCategoryChipColor(String category) {
    switch (category) {
      case '자기계발':
        return const Color(0xFFF2E6E1);
      case '운동':
        return const Color(0xFFDDEBE5);
      case '장소':
        return const Color(0xFFE8E4F4);
      case '쇼핑':
        return const Color(0xFFF7E5D9);
      default:
        return const Color(0xFFF1F1F1);
    }
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
      padding: const EdgeInsets.only(bottom: 8),
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

  Widget buildEmptyReviewCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFFFFE7E0),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: AppColors.peachDust,
              size: 32,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            '아직 되돌아볼 카드가 없어요',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.charcoal,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '아카이브에 저장한 콘텐츠가 생기면\nAI가 오늘 다시 보면 좋을 카드를 추천해드려요.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {
              Navigator.pushNamed(context, AppRoutes.add);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.peachDust,
              foregroundColor: AppColors.charcoal,
              elevation: 0,
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 14,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            child: const Text(
              '콘텐츠 저장하러 가기',
              style: TextStyle(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildPostCard(
    Map<String, dynamic> post, {
    bool showReadIcon = true,
    bool allowHideToday = false,
  }) {
    final String id = (post['id'] ?? '').toString();
    final bool isRead = post['isRead'] ?? false;
    final bool isFavorite = post['isFavorite'] ?? false;
    final bool isPinned = post['isPinned'] ?? false;
    final String category = getEffectiveCategory(post);
    final String dateText = formatDate(post['createdAt']);
    final String title = getDisplayTitle(post);
    final List<String> summaryLines = getSummaryLines(post);
    final List<String> tags = getTags(post);
    final List<String> imageUrls = getImageUrls(post);

    final Color cardBackgroundColor =
        isRead ? const Color(0xFFF6F6F6) : AppColors.surface;

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
          color: cardBackgroundColor,
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 16,
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
                    color: getCategoryChipColor(category),
                    borderRadius: BorderRadius.circular(16),
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
                if (showReadIcon) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () async {
                      await toggleReadStatus(id, isRead);
                    },
                    child: Icon(
                      isRead ? Icons.check_circle : Icons.check_circle_outline,
                      size: 20,
                      color: isRead ? AppColors.success : AppColors.textDisabled,
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () async {
                    await toggleFavoriteStatus(id, isFavorite);
                  },
                  child: Icon(
                    isFavorite ? Icons.star : Icons.star_border,
                    size: 20,
                    color: isFavorite ? Colors.amber : AppColors.textDisabled,
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  icon: const Icon(
                    Icons.more_horiz,
                    color: AppColors.textDisabled,
                  ),
                  onSelected: (value) async {
                    if (value == 'pin') {
                      await togglePinnedStatus(id, isPinned);
                    } else if (value == 'hide' && allowHideToday) {
                      handleHideToday(id);
                    } else if (value == 'refresh' && allowHideToday) {
                      refreshRandomPosts();
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'pin',
                      child: Text(isPinned ? '고정 해제' : '홈에 고정'),
                    ),
                    if (allowHideToday)
                      const PopupMenuItem(
                        value: 'hide',
                        child: Text('오늘은 그만 보기'),
                      ),
                    if (allowHideToday)
                      const PopupMenuItem(
                        value: 'refresh',
                        child: Text('다른 카드 추천받기'),
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
                fontWeight: FontWeight.w700,
                fontSize: 18,
                height: 1.4,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 16),
            buildSummaryArea(
              summaryLines: summaryLines,
              imageUrls: imageUrls,
            ),
            const SizedBox(height: 14),
            const Divider(color: AppColors.divider),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: tags.map((tag) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F3F3),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          tag,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
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
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> visiblePosts = posts.where((post) {
      return matchesSearch(post, widget.searchQuery);
    }).toList();

    final pinnedPostsList = visiblePosts
        .where((post) => (post['isPinned'] ?? false) == true)
        .toList()
      ..sort((a, b) => getCreatedAt(b).compareTo(getCreatedAt(a)));

    final pinnedPreview = pinnedPostsList.take(2).toList();

    final unreadPosts = visiblePosts.where((post) {
      return (post['isRead'] ?? false) == false &&
          (post['isCollected'] ?? false) == false;
    }).toList();

    final visibleRandomPosts = randomPosts.where((post) {
      final id = (post['id'] ?? '').toString();

      if (hiddenToday.contains(id)) return false;

      return matchesSearch(post, widget.searchQuery);
    }).toList();

    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        if (unreadPosts.isNotEmpty)
          GestureDetector(
            onTap: () {
              Navigator.pushNamed(context, AppRoutes.unread);
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 24),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.butterYellow,
                borderRadius: BorderRadius.circular(AppRadii.card),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '놓친 요약 ${unreadPosts.length}개 보러가기',
                          style: const TextStyle(
                            color: AppColors.charcoal,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '아직 확인하지 않은 카드가 있어요',
                          style: TextStyle(
                            color: Color(0xFF495057),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward,
                    color: AppColors.charcoal,
                    size: 24,
                  ),
                ],
              ),
            ),
          ),
        if (pinnedPostsList.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(
                    Icons.push_pin_outlined,
                    color: AppColors.peachDust,
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Text(
                    '내가 고정한 카드',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              if (pinnedPostsList.length > 2)
                TextButton(
                  onPressed: () {
                    Navigator.pushNamed(context, AppRoutes.pinned);
                  },
                  child: const Text('전체 보기'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          ...pinnedPreview.map(
            (post) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: buildPostCard(post),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: const [
                Icon(
                  Icons.auto_awesome,
                  color: AppColors.star,
                  size: 20,
                ),
                SizedBox(width: 8),
                Text(
                  '오늘의 되돌아보기',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'recent') {
                  sortRandomPosts('recent');
                } else if (value == 'oldest') {
                  sortRandomPosts('oldest');
                } else {
                  sortRandomPosts('random');
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'recent', child: Text('최근 등록 순')),
                PopupMenuItem(value: 'oldest', child: Text('오래된 순')),
                PopupMenuItem(value: 'random', child: Text('랜덤')),
              ],
              icon: const Icon(Icons.more_vert),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (visibleRandomPosts.isEmpty)
          buildEmptyReviewCard()
        else
          ...visibleRandomPosts.map(
            (post) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: buildPostCard(
                post,
                allowHideToday: true,
              ),
            ),
          ),
      ],
    );
  }
}