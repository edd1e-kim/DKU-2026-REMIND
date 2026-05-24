import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme/app_categories.dart';
import '../services/firestore_service.dart';
import '../theme/app_colors.dart';

class CategoryTabs extends StatefulWidget {
  final int value;
  final ValueChanged<int> onChange;

  const CategoryTabs({
    super.key,
    required this.value,
    required this.onChange,
  });

  @override
  State<CategoryTabs> createState() => _CategoryTabsState();
}

class _CategoryTabsState extends State<CategoryTabs> {
  final FirestoreService _firestoreService = FirestoreService();
  final ScrollController _scrollController = ScrollController();

  List<String> tabLabels = [
    ...AppCategories.fixedTabs,
    AppCategories.etc,
  ];

  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    loadTabs();
  }

  @override
  void didUpdateWidget(covariant CategoryTabs oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.value != widget.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        scrollToSelectedTab();
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> loadTabs() async {
    final categories = await _firestoreService.getCategories();

    if (!mounted) return;

    final mainCategoryNames = categories
        .where((e) => (e['isMain'] ?? false) == true)
        .map((e) => (e['name'] ?? '').toString().trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList();

    setState(() {
      tabLabels = [
        ...AppCategories.fixedTabs,
        ...mainCategoryNames,
        AppCategories.etc,
      ];
      isLoading = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      scrollToSelectedTab();
    });
  }

  void scrollToSelectedTab() {
    if (!_scrollController.hasClients) return;

    const double estimatedTabWidth = 104;
    final double targetOffset = (widget.value * estimatedTabWidth) - 32;

    final double safeOffset = targetOffset.clamp(
      0,
      _scrollController.position.maxScrollExtent,
    );

    _scrollController.animateTo(
      safeOffset,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void handleMouseWheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (!_scrollController.hasClients) return;

    final double nextOffset =
        _scrollController.offset + event.scrollDelta.dy + event.scrollDelta.dx;

    final double safeOffset = nextOffset.clamp(
      0,
      _scrollController.position.maxScrollExtent,
    );

    _scrollController.jumpTo(safeOffset);
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const SizedBox(
        height: 52,
        child: Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return SizedBox(
      height: 52,
      child: Listener(
        onPointerSignal: handleMouseWheel,
        child: ScrollConfiguration(
          behavior: const _HorizontalDragScrollBehavior(),
          child: ListView.separated(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: tabLabels.length,
            separatorBuilder: (_, __) => const SizedBox(width: 24),
            itemBuilder: (context, index) {
              final isSelected = widget.value == index;
              final label = tabLabels[index];

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => widget.onChange(index),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (label == AppCategories.favorite)
                      Row(
                        children: [
                          Icon(
                            Icons.star,
                            size: 16,
                            color: isSelected
                                ? AppColors.textSecondary
                                : AppColors.textDisabled,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: isSelected
                                  ? AppColors.textSecondary
                                  : AppColors.textDisabled,
                            ),
                          ),
                        ],
                      )
                    else
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w600,
                          color: isSelected
                              ? AppColors.textSecondary
                              : AppColors.textDisabled,
                        ),
                      ),
                    const SizedBox(height: 10),
                    Container(
                      width: 68,
                      height: 3,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.peachDust
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _HorizontalDragScrollBehavior extends MaterialScrollBehavior {
  const _HorizontalDragScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.unknown,
      };
}