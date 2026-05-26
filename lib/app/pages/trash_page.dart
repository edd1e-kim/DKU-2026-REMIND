import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../theme/app_colors.dart';

class TrashPage extends StatefulWidget {
  const TrashPage({super.key});

  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  final FirestoreService _firestoreService = FirestoreService();

  List<Map<String, dynamic>> trashPosts = [];
  Set<String> selectedIds = {};

  bool isLoading = true;
  bool isSelectionMode = false;
  bool isProcessing = false;

  @override
  void initState() {
    super.initState();
    loadTrashPosts();
  }

  Future<void> loadTrashPosts() async {
    final data = await _firestoreService.getTrashPosts();

    if (!mounted) return;

    setState(() {
      trashPosts = data;
      isLoading = false;

      final currentIds = trashPosts
          .map((post) => (post['id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet();

      selectedIds = selectedIds.where((id) => currentIds.contains(id)).toSet();

      if (selectedIds.isEmpty) {
        isSelectionMode = false;
      }
    });
  }

  void enterSelectionMode(String id) {
    if (id.isEmpty) return;

    setState(() {
      isSelectionMode = true;
      selectedIds.add(id);
    });
  }

  void toggleSelection(String id) {
    if (id.isEmpty) return;

    setState(() {
      if (selectedIds.contains(id)) {
        selectedIds.remove(id);
      } else {
        selectedIds.add(id);
      }

      if (selectedIds.isEmpty) {
        isSelectionMode = false;
      }
    });
  }

  void selectAllPosts() {
    final ids = trashPosts
        .map((post) => (post['id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toSet();

    setState(() {
      isSelectionMode = true;
      selectedIds = ids;
    });
  }

  void clearSelection() {
    setState(() {
      selectedIds.clear();
      isSelectionMode = false;
    });
  }

  Future<void> restorePost(String id) async {
    await _firestoreService.restoreFromTrash(id);
    await loadTrashPosts();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('복구되었습니다.'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> deletePostPermanently(String id) async {
    await _firestoreService.deletePostPermanently(id);
    await loadTrashPosts();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('완전히 삭제되었습니다.'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> restoreSelectedPosts() async {
    if (selectedIds.isEmpty || isProcessing) return;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('선택 항목 복구'),
          content: Text('선택한 ${selectedIds.length}개 항목을 복구할까요?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('복구'),
            ),
          ],
        );
      },
    );

    if (result != true) return;

    setState(() {
      isProcessing = true;
    });

    final ids = selectedIds.toList();

    for (final id in ids) {
      await _firestoreService.restoreFromTrash(id);
    }

    if (!mounted) return;

    setState(() {
      selectedIds.clear();
      isSelectionMode = false;
      isProcessing = false;
    });

    await loadTrashPosts();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${ids.length}개 항목을 복구했습니다.'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> deleteSelectedPostsPermanently() async {
    if (selectedIds.isEmpty || isProcessing) return;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('선택 항목 완전 삭제'),
          content: Text(
            '선택한 ${selectedIds.length}개 항목을 완전히 삭제할까요?\n삭제 후에는 되돌릴 수 없습니다.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('삭제'),
            ),
          ],
        );
      },
    );

    if (result != true) return;

    setState(() {
      isProcessing = true;
    });

    final ids = selectedIds.toList();

    for (final id in ids) {
      await _firestoreService.deletePostPermanently(id);
    }

    if (!mounted) return;

    setState(() {
      selectedIds.clear();
      isSelectionMode = false;
      isProcessing = false;
    });

    await loadTrashPosts();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${ids.length}개 항목을 완전히 삭제했습니다.'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> restoreAllPosts() async {
    if (trashPosts.isEmpty || isProcessing) return;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('전체 복구'),
          content: Text('휴지통의 ${trashPosts.length}개 항목을 모두 복구할까요?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('전체 복구'),
            ),
          ],
        );
      },
    );

    if (result != true) return;

    setState(() {
      isProcessing = true;
    });

    final ids = trashPosts
        .map((post) => (post['id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toList();

    for (final id in ids) {
      await _firestoreService.restoreFromTrash(id);
    }

    if (!mounted) return;

    setState(() {
      selectedIds.clear();
      isSelectionMode = false;
      isProcessing = false;
    });

    await loadTrashPosts();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${ids.length}개 항목을 모두 복구했습니다.'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> deleteAllPostsPermanently() async {
    if (trashPosts.isEmpty || isProcessing) return;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('휴지통 전체 삭제'),
          content: Text(
            '휴지통의 ${trashPosts.length}개 항목을 모두 완전히 삭제할까요?\n삭제 후에는 되돌릴 수 없습니다.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('전체 삭제'),
            ),
          ],
        );
      },
    );

    if (result != true) return;

    setState(() {
      isProcessing = true;
    });

    final ids = trashPosts
        .map((post) => (post['id'] ?? '').toString())
        .where((id) => id.isNotEmpty)
        .toList();

    for (final id in ids) {
      await _firestoreService.deletePostPermanently(id);
    }

    if (!mounted) return;

    setState(() {
      selectedIds.clear();
      isSelectionMode = false;
      isProcessing = false;
    });

    await loadTrashPosts();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${ids.length}개 항목을 모두 삭제했습니다.'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> showRestoreDialog(String id) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('복구'),
          content: const Text('이 링크를 복구할까요?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('복구'),
            ),
          ],
        );
      },
    );

    if (result == true) {
      await restorePost(id);
    }
  }

  Future<void> showPermanentDeleteDialog(String id) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('완전 삭제'),
          content: const Text('이 링크를 완전히 삭제할까요?\n삭제 후에는 되돌릴 수 없습니다.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('삭제'),
            ),
          ],
        );
      },
    );

    if (result == true) {
      await deletePostPermanently(id);
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

  List<String> getSummaryLines(Map<String, dynamic> post) {
    final summary = (post['summary'] ?? '').toString().trim();
    final url = (post['url'] ?? '').toString().trim();

    if (summary.isNotEmpty) {
      return summary
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .map((e) => e.replaceFirst(RegExp(r'^[•\-\*\.·]+\s*'), ''))
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

  PreferredSizeWidget buildNormalAppBar() {
    return AppBar(
      title: const Text('휴지통'),
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.charcoal,
      elevation: 0,
      actions: [
        if (trashPosts.isNotEmpty)
          TextButton(
            onPressed: isProcessing ? null : selectAllPosts,
            child: const Text(
              '전체 선택',
              style: TextStyle(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        PopupMenuButton<String>(
          enabled: trashPosts.isNotEmpty && !isProcessing,
          onSelected: (value) async {
            if (value == 'restoreAll') {
              await restoreAllPosts();
            } else if (value == 'deleteAll') {
              await deleteAllPostsPermanently();
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: 'restoreAll',
              child: Text('전체 복구'),
            ),
            PopupMenuItem(
              value: 'deleteAll',
              child: Text('전체 삭제'),
            ),
          ],
        ),
      ],
    );
  }

  PreferredSizeWidget buildSelectionAppBar() {
    return AppBar(
      title: Text('${selectedIds.length}개 선택됨'),
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.charcoal,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: isProcessing ? null : clearSelection,
      ),
      actions: [
        TextButton(
          onPressed: isProcessing ? null : selectAllPosts,
          child: const Text(
            '전체 선택',
            style: TextStyle(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        IconButton(
          tooltip: '선택 복구',
          onPressed:
              selectedIds.isEmpty || isProcessing ? null : restoreSelectedPosts,
          icon: const Icon(Icons.restore),
        ),
        IconButton(
          tooltip: '선택 삭제',
          onPressed: selectedIds.isEmpty || isProcessing
              ? null
              : deleteSelectedPostsPermanently,
          icon: const Icon(Icons.delete_forever),
        ),
      ],
    );
  }

  Widget buildBulkActionBar() {
    if (trashPosts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              isSelectionMode
                  ? '${selectedIds.length}개 선택됨'
                  : '휴지통 ${trashPosts.length}개 항목',
              style: const TextStyle(
                color: AppColors.charcoal,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
          if (isSelectionMode) ...[
            TextButton(
              onPressed:
                  selectedIds.isEmpty || isProcessing ? null : restoreSelectedPosts,
              child: const Text('선택 복구'),
            ),
            TextButton(
              onPressed: selectedIds.isEmpty || isProcessing
                  ? null
                  : deleteSelectedPostsPermanently,
              child: const Text('선택 삭제'),
            ),
          ] else ...[
            TextButton(
              onPressed: isProcessing ? null : restoreAllPosts,
              child: const Text('전체 복구'),
            ),
            TextButton(
              onPressed: isProcessing ? null : deleteAllPostsPermanently,
              child: const Text('전체 삭제'),
            ),
          ],
        ],
      ),
    );
  }

  Widget buildTrashCard(Map<String, dynamic> post) {
    final String id = (post['id'] ?? '').toString();
    final String category = (post['category'] ?? '기타').toString();
    final String dateText = formatDate(post['createdAt']);
    final String title = getDisplayTitle(post);
    final List<String> summaryLines = getSummaryLines(post);
    final List<String> tags = getTags(post);
    final bool isSelected = selectedIds.contains(id);

    return GestureDetector(
      onLongPress: isProcessing ? null : () => enterSelectionMode(id),
      onTap: isSelectionMode && !isProcessing ? () => toggleSelection(id) : null,
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? const Color.fromRGBO(110, 86, 207, 0.08)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(28),
          border: isSelected
              ? Border.all(
                  color: const Color(0xFF6E56CF),
                  width: 1.5,
                )
              : null,
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
                if (isSelectionMode) ...[
                  Icon(
                    isSelected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: isSelected
                        ? const Color(0xFF6E56CF)
                        : AppColors.textDisabled,
                  ),
                  const SizedBox(width: 10),
                ],
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
                const SizedBox(width: 8),
                if (!isSelectionMode)
                  PopupMenuButton<String>(
                    icon: const Icon(
                      Icons.more_horiz,
                      color: AppColors.textDisabled,
                    ),
                    onSelected: (value) async {
                      if (value == 'restore') {
                        await showRestoreDialog(id);
                      } else if (value == 'delete') {
                        await showPermanentDeleteDialog(id);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'restore',
                        child: Text('복구'),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text('완전삭제'),
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
            ...summaryLines.map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '• ',
                      style: TextStyle(fontSize: 14),
                    ),
                    Expanded(
                      child: Text(
                        line,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.6,
                          fontWeight: FontWeight.w500,
                          color: AppColors.charcoal,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
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
                if (!isSelectionMode)
                  Row(
                    children: [
                      TextButton(
                        onPressed: isProcessing
                            ? null
                            : () async {
                                await showRestoreDialog(id);
                              },
                        child: const Text('복구'),
                      ),
                      TextButton(
                        onPressed: isProcessing
                            ? null
                            : () async {
                                await showPermanentDeleteDialog(id);
                              },
                        child: const Text('완전삭제'),
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

  Widget buildBody() {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (trashPosts.isEmpty) {
      return const Center(
        child: Text(
          '휴지통이 비어 있습니다.',
          style: TextStyle(
            fontSize: 16,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    return Column(
      children: [
        buildBulkActionBar(),
        if (isProcessing)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(),
          ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: trashPosts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 16),
            itemBuilder: (context, index) {
              return buildTrashCard(trashPosts[index]);
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: isSelectionMode ? buildSelectionAppBar() : buildNormalAppBar(),
      body: buildBody(),
    );
  }
}