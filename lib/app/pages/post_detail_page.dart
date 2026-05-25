import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/firestore_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_radii.dart';

class PostDetailPage extends StatefulWidget {
  final String? postId;

  const PostDetailPage({super.key, this.postId});

  @override
  State<PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends State<PostDetailPage> {
  final FirestoreService _firestoreService = FirestoreService();

  bool isLoading = true;
  bool isFavorite = false;
  bool isRead = false;
  bool isEditingTitle = false;
  bool isEditingSummary = false;
  bool isOriginalExpanded = false;
  bool isCompactSummary = false;
  bool isCategoryLoading = true;

  Map<String, dynamic>? post;
  List<Map<String, dynamic>> categories = [];

  late TextEditingController titleController;
  late TextEditingController summaryController;
  late TextEditingController memoController;

  @override
  void initState() {
    super.initState();
    titleController = TextEditingController();
    summaryController = TextEditingController();
    memoController = TextEditingController();
    loadPost();
    loadCategories();
  }

  @override
  void dispose() {
    titleController.dispose();
    summaryController.dispose();
    memoController.dispose();
    super.dispose();
  }

  bool get isAnalysisCompleted {
    final status = (post?['status'] ?? 'ACTIVE').toString();
    return status == 'ACTIVE' || status == 'COMPLETED';
  }

  bool get isAnalyzing {
    final status = (post?['status'] ?? '').toString();
    return status == 'ANALYZING';
  }

  bool get isFailed {
    final status = (post?['status'] ?? '').toString();
    return status == 'FAILED';
  }

  Future<void> loadPost() async {
    final id = widget.postId;

    if (id == null || id.isEmpty) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
        post = null;
      });

      return;
    }

    final data = await _firestoreService.getPostById(id);

    if (!mounted) return;

    final detailSummary =
        (data?['detailSummary'] ?? data?['summary'] ?? '').toString().trim();

    setState(() {
      post = data;
      isLoading = false;
      isFavorite = data?['isFavorite'] ?? false;
      isRead = data?['isRead'] ?? false;
      titleController.text = (data?['title'] ?? '').toString();
      summaryController.text = detailSummary;
      memoController.text = (data?['memo'] ?? '').toString();
    });
  }

  Future<void> loadCategories() async {
    final data = await _firestoreService.getCategories();

    if (!mounted) return;

    setState(() {
      categories = data;
      isCategoryLoading = false;
    });
  }

  Future<List<Map<String, dynamic>>> refreshCategories() async {
    final data = await _firestoreService.getCategories();

    if (!mounted) return data;

    setState(() {
      categories = data;
      isCategoryLoading = false;
    });

    return data;
  }

  Future<void> toggleFavorite() async {
    if (post == null) return;

    final id = post!['id'].toString();
    final currentValue = post!['isFavorite'] ?? false;

    await _firestoreService.updateFavoriteStatus(id, !currentValue);
    await loadPost();
  }

  Future<void> toggleRead() async {
    if (post == null) return;

    final id = post!['id'].toString();
    final currentValue = post!['isRead'] ?? false;

    await _firestoreService.updateReadStatus(id, !currentValue);
    await loadPost();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(!currentValue ? '읽음으로 표시했습니다.' : '읽지 않음으로 표시했습니다.'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> togglePinned() async {
    if (post == null || !isAnalysisCompleted) return;

    final id = post!['id'].toString();
    final currentValue = post!['isPinned'] ?? false;

    await _firestoreService.updatePinnedStatus(id, !currentValue);
    await loadPost();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(!currentValue ? '홈에 고정했습니다.' : '홈 고정을 해제했습니다.'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> moveToTrash() async {
    if (post == null || !isAnalysisCompleted) return;

    final shouldMove = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('휴지통으로 이동할까요?'),
          content: const Text('이 콘텐츠는 휴지통에서 다시 복구할 수 있습니다.'),
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

    if (shouldMove != true) return;

    final id = post!['id'].toString();
    await _firestoreService.moveToTrash(id);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('휴지통으로 이동했습니다.'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );

    Navigator.pop(context);
  }

  Future<void> toggleMastered() async {
    if (post == null || !isAnalysisCompleted) return;

    final id = post!['id'].toString();
    final currentValue = post!['isCollected'] ?? false;

    await _firestoreService.updateCollectedStatus(id, !currentValue);
    await loadPost();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(!currentValue ? '마스터 완료했습니다.' : '마스터 완료를 취소했습니다.'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> saveTitle() async {
    if (post == null || !isAnalysisCompleted) return;

    final id = post!['id'].toString();
    final editedTitle = titleController.text.trim();

    if (editedTitle.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('제목을 입력해 주세요.'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    await _firestoreService.updateTitle(id, editedTitle);

    if (!mounted) return;

    setState(() {
      isEditingTitle = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('제목을 저장했습니다.'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );

    await loadPost();
  }

  Future<void> saveSummary() async {
    if (post == null || !isAnalysisCompleted) return;

    final id = post!['id'].toString();
    final editedSummary = summaryController.text.trim();

    await _firestoreService.updateSummary(id, editedSummary);

    if (!mounted) return;

    setState(() {
      isEditingSummary = false;
      isCompactSummary = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('AI 요약을 저장했습니다.'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );

    await loadPost();
  }

  Future<void> saveMemo() async {
    if (post == null || !isAnalysisCompleted) return;

    final id = post!['id'].toString();
    await _firestoreService.updateMemo(id, memoController.text.trim());

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('메모를 저장했습니다.'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );

    await loadPost();
  }

  Future<void> copyText(String text, String message) async {
    if (!isAnalysisCompleted) return;

    await Clipboard.setData(ClipboardData(text: text));

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> openOriginalLink() async {
    if (post == null) return;

    final url = (post!['url'] ?? '').toString().trim();

    if (url.isEmpty || url == 'uploaded_image' || url == 'uploaded_file') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('열 수 있는 원본 링크가 없습니다.'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final Uri uri = Uri.parse(url);

    final bool launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('링크를 열 수 없습니다.'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  List<String> buildCategoryNames(List<Map<String, dynamic>> categoryData) {
    final result = <String>[];
    final seen = <String>{};

    for (final item in categoryData) {
      final name = (item['name'] ?? '').toString().trim();

      if (name.isEmpty) continue;
      if (seen.contains(name)) continue;

      seen.add(name);
      result.add(name);
    }

    final currentCategory = (post?['category'] ?? '').toString().trim();

    if (currentCategory.isNotEmpty && !seen.contains(currentCategory)) {
      result.add(currentCategory);
      seen.add(currentCategory);
    }

    if (!seen.contains('기타')) {
      result.add('기타');
    }

    return result;
  }

  Future<void> showCategoryEditSheet() async {
    if (post == null || !isAnalysisCompleted) return;

    final latestCategories = await refreshCategories();

    if (!mounted) return;

    final currentCategory = (post!['category'] ?? '기타').toString();
    final categoryNames = buildCategoryNames(latestCategories);

    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 18),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '카테고리 수정',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.charcoal,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '카테고리 관리에서 추가한 항목도 여기에 반영됩니다.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: categoryNames.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final category = categoryNames[index];
                      final isSelected = category == currentCategory;

                      return ListTile(
                        title: Text(
                          category,
                          style: TextStyle(
                            fontWeight:
                                isSelected ? FontWeight.w800 : FontWeight.w500,
                            color: AppColors.charcoal,
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(
                                Icons.check,
                                color: AppColors.paleLavenderDark,
                              )
                            : null,
                        onTap: () => Navigator.pop(context, category),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selected == null || selected == currentCategory) return;

    final id = post!['id'].toString();
    await _firestoreService.updatePostCategory(id, selected);
    await loadPost();
    await loadCategories();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('카테고리를 수정했습니다.'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  DateTime? parseDate(dynamic value) {
    try {
      if (value == null) return null;

      if (value is DateTime) {
        return value;
      }

      return value.toDate();
    } catch (_) {
      return null;
    }
  }

  String formatDate(dynamic createdAt) {
    final date = parseDate(createdAt);

    if (date == null) return '날짜 없음';

    return '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
  }

  String getMasterBadgeText() {
    if (post == null) return '🏆 마스터 완료';

    final completedAt = parseDate(post!['completedAt']);

    if (completedAt == null) {
      return '🏆 마스터 완료';
    }

    final completedText =
        '${completedAt.year}.${completedAt.month.toString().padLeft(2, '0')}.${completedAt.day.toString().padLeft(2, '0')}';

    return '🏆 $completedText 마스터 완료';
  }

  Color getCategoryChipColor(String category) {
    for (final item in categories) {
      final name = (item['name'] ?? '').toString().trim();

      if (name != category) continue;

      final rawColor = item['color'];

      if (rawColor is int) {
        return Color(rawColor).withOpacity(0.24);
      }
    }

    switch (category) {
      case '자기계발':
        return const Color.fromRGBO(200, 182, 255, 0.2);
      case '운동':
        return const Color(0xFFDDEBE5);
      case '장소':
        return const Color(0xFFE8E4F4);
      case '쇼핑':
        return const Color(0xFFF7E5D9);
      case '다이어트':
        return const Color(0xFFE6F5EF);
      case '요리':
        return const Color(0xFFFFF1D6);
      case '투자':
        return const Color(0xFFE8F0FA);
      case '음악':
        return const Color(0xFFF3E8FF);
      default:
        return const Color(0xFFF1F1F1);
    }
  }

  String cleanSummaryLineForDisplay(String line) {
    var cleaned = line.trim();

    cleaned = cleaned.replaceFirst(RegExp(r'^[•●▪▫]\s*'), '');

    cleaned = cleaned.replaceFirstMapped(
      RegExp(r'^(\d+[\)\.]\s*)[○◯☐□]\s*'),
      (match) => match.group(1) ?? '',
    );

    cleaned = cleaned.replaceFirst(RegExp(r'^[○◯☐□]\s*'), '');

    if (cleaned.startsWith('-')) {
      cleaned = '- ${cleaned.substring(1).trim()}';
    }

    return cleaned.trim();
  }

  String removeDetailDescription(String line) {
    var cleaned = cleanSummaryLineForDisplay(line);

    if (cleaned.contains('▶')) {
      cleaned = cleaned.split('▶').first.trim();
    }

    if (cleaned.contains('➔')) {
      cleaned = cleaned.split('➔').first.trim();
    }

    if (cleaned.contains('→')) {
      cleaned = cleaned.split('→').first.trim();
    }

    if (cleaned.contains(':')) {
      final parts = cleaned.split(':');
      final head = parts.first.trim();

      if (cleaned.startsWith('-') ||
          RegExp(r'^\d+[\)\.]\s+').hasMatch(cleaned)) {
        if (head.length <= 40) {
          cleaned = head;
        }
      }
    }

    return cleaned.trim();
  }

  bool isSectionTitleLine(String line) {
    return RegExp(r'^\d+\)\s+').hasMatch(line.trim());
  }

  bool isDashLine(String line) {
    return line.trim().startsWith('-');
  }

  bool isDashSectionTitleLine(String line) {
    final trimmed = cleanSummaryLineForDisplay(line);

    if (!trimmed.startsWith('-')) return false;

    final text = trimmed.replaceFirst(RegExp(r'^-\s*'), '').trim();

    if (text.isEmpty) return false;
    if (text.length > 35) return false;

    return text.contains('루틴') ||
        text.contains('식단') ||
        text.contains('추천') ||
        text.contains('기준') ||
        text.contains('체크리스트') ||
        text.contains('주의할 점');
  }

  String removeNumberPrefix(String line) {
    return line.replaceFirst(RegExp(r'^\d+[\)\.]\s*'), '').trim();
  }

  List<String> normalizeSummaryLinesForDisplay(List<String> lines) {
    final result = <String>[];

    bool insideDashSection = false;
    int sectionCount = 0;

    for (final rawLine in lines) {
      final line = cleanSummaryLineForDisplay(rawLine);

      if (line.isEmpty) continue;

      if (isDashSectionTitleLine(line)) {
        sectionCount++;

        final title = line.replaceFirst(RegExp(r'^-\s*'), '').trim();
        result.add('$sectionCount) $title');

        insideDashSection = true;
        continue;
      }

      if (insideDashSection) {
        if (RegExp(r'^\d+[\)\.]\s*').hasMatch(line)) {
          final item = removeNumberPrefix(line);

          if (item.isNotEmpty) {
            result.add('- $item');
          }

          continue;
        }

        if (!line.startsWith('-') && !isSectionTitleLine(line)) {
          result.add('- $line');
          continue;
        }
      }

      result.add(line);
    }

    return result;
  }

  bool isIntroLine(String line) {
    final trimmed = line.trim();

    if (trimmed.isEmpty) return false;
    if (isSectionTitleLine(trimmed)) return false;
    if (isDashLine(trimmed)) return false;

    return true;
  }

  List<String> getSummaryList(String summary) {
    final title = ((post?['title'] ?? '').toString().trim().isNotEmpty)
        ? (post?['title'] ?? '').toString().trim()
        : '';

    final titleLine = title.isNotEmpty ? '<$title>' : '';

    final lines = summary
        .split('\n')
        .map((e) => cleanSummaryLineForDisplay(e))
        .where((e) => e.isNotEmpty)
        .where((e) => e != titleLine)
        .toList();

    final normalizedLines = normalizeSummaryLinesForDisplay(lines);

    if (normalizedLines.isNotEmpty) return normalizedLines;

    return ['요약 정보가 없습니다.'];
  }

  List<String> getCompactSummaryList() {
    final shortSummary = (post?['shortSummary'] ?? '').toString().trim();
    final detailSummary = summaryController.text.trim();

    final sourceText = shortSummary.isNotEmpty ? shortSummary : detailSummary;

    final rawLines = sourceText
        .split('\n')
        .map((e) => removeDetailDescription(e))
        .where((e) => e.isNotEmpty)
        .where((e) => !e.contains('대한 내용입니다'))
        .where((e) => !e.contains('나뉘어 있습니다'))
        .toList();

    final result = <String>[];

    final numberedLines = rawLines.where((line) {
      return RegExp(r'^\d+[\)\.]\s+').hasMatch(line.trim());
    }).toList();

    if (numberedLines.length >= 5) {
      return numberedLines.take(5).toList();
    }

    String? currentSection;
    int sectionItemCount = 0;

    for (final line in rawLines) {
      if (isSectionTitleLine(line)) {
        currentSection = line;
        sectionItemCount = 0;

        if (result.length < 9) {
          result.add(line);
        }

        continue;
      }

      if (currentSection != null && isDashLine(line)) {
        if (sectionItemCount < 2 && result.length < 9) {
          result.add(line);
          sectionItemCount++;
        }
      }

      if (result.length >= 9) break;
    }

    if (result.isNotEmpty) return result;

    return rawLines.take(5).toList();
  }

  String getCurrentSummaryTextForCopy() {
    final lines = isCompactSummary
        ? getCompactSummaryList()
        : getSummaryList(summaryController.text.trim());

    return lines.join('\n');
  }

  Widget buildSummaryLine(String line) {
    final trimmed = cleanSummaryLineForDisplay(line);

    if (trimmed.isEmpty) {
      return const SizedBox.shrink();
    }

    if (isSectionTitleLine(trimmed)) {
      return Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(
          trimmed,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: AppColors.charcoal,
            height: 1.5,
          ),
        ),
      );
    }

    if (isDashLine(trimmed)) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          trimmed,
          style: const TextStyle(
            fontSize: 16,
            color: AppColors.charcoal,
            fontWeight: FontWeight.w400,
            height: 1.65,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        trimmed,
        style: const TextStyle(
          fontSize: 16,
          color: AppColors.charcoal,
          fontWeight: FontWeight.w400,
          height: 1.65,
        ),
      ),
    );
  }

  Widget buildSummaryTitleText(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Text(
        '<$title>',
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: AppColors.charcoal,
          height: 1.45,
        ),
      ),
    );
  }

  Widget buildSummaryModeButton() {
    if (isEditingSummary) {
      return const SizedBox.shrink();
    }

    return TextButton.icon(
      onPressed: !isAnalysisCompleted
          ? null
          : () {
              setState(() {
                isCompactSummary = !isCompactSummary;
              });
            },
      icon: Icon(
        isCompactSummary ? Icons.notes : Icons.compress,
        size: 16,
      ),
      label: Text(
        isCompactSummary ? '자세히 보기' : '핵심만 보기',
        style: const TextStyle(
          fontWeight: FontWeight.w700,
        ),
      ),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.paleLavenderDark,
        disabledForegroundColor: AppColors.textDisabled,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
    );
  }

  List<String> getImageUrls() {
    final raw = post?['imageUrls'];

    if (raw is List) {
      return raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    return [];
  }

  void showImageViewer(List<String> imageUrls, int initialIndex) {
    final pageController = PageController(initialPage: initialIndex);
    int currentIndex = initialIndex;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.black,
              insetPadding: const EdgeInsets.all(16),
              child: Stack(
                children: [
                  PageView.builder(
                    controller: pageController,
                    itemCount: imageUrls.length,
                    onPageChanged: (index) {
                      setDialogState(() {
                        currentIndex = index;
                      });
                    },
                    itemBuilder: (context, index) {
                      final imageUrl = imageUrls[index];

                      return InteractiveViewer(
                        minScale: 0.5,
                        maxScale: 4,
                        child: Center(
                          child: Image.network(
                            imageUrl,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return const Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                  '이미지를 불러올 수 없습니다.',
                                  style: TextStyle(color: Colors.white),
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),
                  Positioned(
                    top: 12,
                    left: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: const Color.fromRGBO(0, 0, 0, 0.55),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${currentIndex + 1} / ${imageUrls.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                  ),
                  if (imageUrls.length > 1 && currentIndex > 0)
                    Positioned(
                      left: 8,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: IconButton(
                          onPressed: () {
                            pageController.previousPage(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOut,
                            );
                          },
                          icon: const Icon(
                            Icons.chevron_left,
                            color: Colors.white,
                            size: 42,
                          ),
                        ),
                      ),
                    ),
                  if (imageUrls.length > 1 &&
                      currentIndex < imageUrls.length - 1)
                    Positioned(
                      right: 8,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: IconButton(
                          onPressed: () {
                            pageController.nextPage(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOut,
                            );
                          },
                          icon: const Icon(
                            Icons.chevron_right,
                            color: Colors.white,
                            size: 42,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    ).then((_) {
      pageController.dispose();
    });
  }

  Widget buildMasterAction() {
    final bool isCollected = post?['isCollected'] ?? false;

    return ElevatedButton(
      onPressed: !isAnalysisCompleted ? null : toggleMastered,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.butterYellow,
        foregroundColor: AppColors.charcoal,
        disabledBackgroundColor: Colors.grey.shade300,
        disabledForegroundColor: Colors.grey.shade600,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(
            color: Color(0xFFE0D38A),
          ),
        ),
      ),
      child: Text(
        isCollected ? getMasterBadgeText() : '🏆 마스터 하기',
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget buildStatusChip(String status) {
    if (status == 'ANALYZING') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFEDE7F6),
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
              ),
            ),
            SizedBox(width: 8),
            Text(
              '분석 중',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.paleLavenderDark,
              ),
            ),
          ],
        ),
      );
    }

    if (status == 'FAILED') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFFFE8E8),
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Text(
          '분석 실패',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.error,
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget buildImageSection(List<String> imageUrls) {
    if (imageUrls.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        const SizedBox(height: 18),
        Row(
          children: [
            const Expanded(
              child: Text(
                '🖼 저장된 이미지',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.charcoal,
                  fontSize: 16,
                ),
              ),
            ),
            Text(
              '${imageUrls.length}장',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 140,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: imageUrls.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final imageUrl = imageUrls[index];

              return GestureDetector(
                onTap: () => showImageViewer(imageUrls, index),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    width: 140,
                    height: 140,
                    color: const Color(0xFFF3F4F4),
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const Center(
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: AppColors.textDisabled,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget buildDisabledNotice() {
    if (!isAnalyzing) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEDE7F6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Text(
        'AI 분석이 끝나면 마스터, 고정, 휴지통 이동, 카테고리 수정, 복사, 편집 기능을 사용할 수 있어요.',
        style: TextStyle(
          color: AppColors.paleLavenderDark,
          fontSize: 13,
          height: 1.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  PopupMenuButton<String> buildMoreMenu() {
    final bool isPinned = post?['isPinned'] ?? false;

    return PopupMenuButton<String>(
      enabled: isAnalysisCompleted,
      onSelected: (value) async {
        if (value == 'pin') {
          await togglePinned();
        } else if (value == 'category') {
          await showCategoryEditSheet();
        } else if (value == 'trash') {
          await moveToTrash();
        }
      },
      itemBuilder: (context) {
        return [
          PopupMenuItem(
            value: 'pin',
            child: Text(isPinned ? '홈 고정 해제' : '홈에 고정'),
          ),
          const PopupMenuItem(
            value: 'category',
            child: Text('카테고리 수정'),
          ),
          const PopupMenuItem(
            value: 'trash',
            child: Text('휴지통으로 이동'),
          ),
        ];
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (post == null) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Text('게시물을 찾을 수 없습니다.'),
        ),
      );
    }

    final category = (post!['category'] ?? '기타').toString();
    final status = (post!['status'] ?? 'ACTIVE').toString();

    final title = ((post!['title'] ?? '').toString().trim().isNotEmpty)
        ? (post!['title'] ?? '').toString()
        : (post!['url'] ?? '제목 없음').toString();

    final dateText = formatDate(post!['createdAt']);

    final detailSummaryText = summaryController.text.trim();
    final displayedSummaryList = isCompactSummary
        ? getCompactSummaryList()
        : getSummaryList(detailSummaryText);

    final imageUrls = getImageUrls();

    final rawUrl = (post!['url'] ?? '').toString().trim();
    final bool hasOriginalLink = rawUrl.isNotEmpty &&
        rawUrl != 'uploaded_image' &&
        rawUrl != 'uploaded_file';

    final originalText =
        ((post!['originalText'] ?? '').toString().trim().isNotEmpty)
            ? (post!['originalText'] ?? '').toString()
            : ((post!['summary'] ?? '').toString().trim().isNotEmpty)
                ? (post!['summary'] ?? '').toString()
                : rawUrl;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.charcoal,
        title: const Text(
          '상세 요약',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            tooltip: isRead ? '읽음' : '읽지 않음',
            onPressed: isAnalysisCompleted ? toggleRead : null,
            icon: Icon(
              isRead ? Icons.check_circle : Icons.check_circle_outline,
              color: isRead ? const Color(0xFF95DDB4) : AppColors.charcoal,
            ),
          ),
          IconButton(
            onPressed: isAnalysisCompleted ? toggleFavorite : null,
            icon: Icon(
              isFavorite ? Icons.star : Icons.star_border,
              color: isFavorite ? AppColors.star : AppColors.charcoal,
            ),
          ),
          buildMoreMenu(),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              InkWell(
                onTap: isAnalysisCompleted ? showCategoryEditSheet : null,
                borderRadius: BorderRadius.circular(AppRadii.chip),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: getCategoryChipColor(category),
                    borderRadius: BorderRadius.circular(AppRadii.chip),
                    border: Border.all(
                      color: const Color.fromRGBO(176, 159, 255, 0.35),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        category,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.charcoal,
                        ),
                      ),
                      if (isAnalysisCompleted) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.edit,
                          size: 13,
                          color: AppColors.textSecondary,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                dateText,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 8),
              buildStatusChip(status),
              const Spacer(),
              buildMasterAction(),
            ],
          ),
          buildDisabledNotice(),
          const SizedBox(height: 16),
          if (isEditingTitle)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: titleController,
                    autofocus: true,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      hintText: '제목을 입력하세요',
                      border: InputBorder.none,
                    ),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 24,
                      color: AppColors.charcoal,
                      height: 1.25,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: saveTitle,
                  icon: const Icon(
                    Icons.check,
                    color: AppColors.peachDustDark,
                  ),
                ),
                IconButton(
                  onPressed: () {
                    setState(() {
                      isEditingTitle = false;
                      titleController.text = title;
                    });
                  },
                  icon: const Icon(
                    Icons.close,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 24,
                      color: AppColors.charcoal,
                      height: 1.25,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '제목 수정',
                  onPressed: isAnalysisCompleted
                      ? () {
                          setState(() {
                            isEditingTitle = true;
                            titleController.text = title;
                          });
                        }
                      : null,
                  icon: const Icon(
                    Icons.edit,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 8),
          if (hasOriginalLink)
            Row(
              children: [
                Expanded(
                  child: Text(
                    rawUrl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: openOriginalLink,
                  icon: const Icon(
                    Icons.open_in_new,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                  label: const Text(
                    '원본 링크 이동',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            )
          else
            const Text(
              '이미지로 저장된 콘텐츠입니다.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          buildImageSection(imageUrls),
          const SizedBox(height: 16),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.card),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '✨ AI 요약',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.charcoal,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '요약 복사',
                        onPressed: isAnalysisCompleted
                            ? () => copyText(
                                  getCurrentSummaryTextForCopy(),
                                  '요약을 복사했습니다.',
                                )
                            : null,
                        icon: const Icon(
                          Icons.copy,
                          size: 18,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      buildSummaryModeButton(),
                      IconButton(
                        onPressed: !isAnalysisCompleted
                            ? null
                            : () async {
                                if (isEditingSummary) {
                                  await saveSummary();
                                } else {
                                  setState(() {
                                    isEditingSummary = true;
                                    isCompactSummary = false;
                                  });
                                }
                              },
                        icon: Icon(
                          isEditingSummary ? Icons.check : Icons.edit,
                          size: 18,
                          color: isEditingSummary
                              ? AppColors.peachDustDark
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  if (!isEditingSummary) ...[
                    const SizedBox(height: 4),
                    Text(
                      isCompactSummary
                          ? '세부 설명을 줄이고 핵심 행동만 보여드려요.'
                          : '기본은 자세히 보기예요. 원본을 다시 보지 않아도 되게 정리했어요.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  buildSummaryTitleText(title),
                  if (!isEditingSummary)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: displayedSummaryList
                          .map((line) => buildSummaryLine(line))
                          .toList(),
                    )
                  else
                    TextField(
                      controller: summaryController,
                      maxLines: 12,
                      decoration: const InputDecoration(
                        hintText: '엔터로 항목을 구분하세요',
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Expanded(
                child: Text(
                  '📄 원본 글',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.charcoal,
                  ),
                ),
              ),
              IconButton(
                tooltip: '원본 글 복사',
                onPressed: isAnalysisCompleted
                    ? () => copyText(originalText, '원본 글을 복사했습니다.')
                    : null,
                icon: const Icon(
                  Icons.copy,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    isOriginalExpanded = !isOriginalExpanded;
                  });
                },
                icon: Icon(
                  isOriginalExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 18,
                ),
                label: Text(isOriginalExpanded ? '접기' : '전체보기'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadii.card),
              border: Border.all(color: AppColors.divider),
            ),
            child: Text(
              originalText,
              maxLines: isOriginalExpanded ? null : 4,
              overflow: isOriginalExpanded
                  ? TextOverflow.visible
                  : TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                height: 1.7,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Expanded(
                child: Text(
                  '📝 내 메모',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.charcoal,
                  ),
                ),
              ),
              TextButton(
                onPressed: isAnalysisCompleted ? saveMemo : null,
                child: const Text('저장'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: const Color.fromRGBO(0, 0, 0, 0.02),
              borderRadius: BorderRadius.circular(AppRadii.card),
              border: Border.all(color: AppColors.divider),
            ),
            child: TextField(
              controller: memoController,
              enabled: isAnalysisCompleted,
              minLines: 5,
              maxLines: null,
              decoration: const InputDecoration(
                hintText: '여기에 나만의 생각이나 적용할 점을 기록해 보세요',
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(20),
              ),
            ),
          ),
        ],
      ),
    );
  }
}