import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../routes/app_routes.dart';
import '../theme/app_colors.dart';
import '../theme/app_radii.dart';
import '../services/firestore_service.dart';
import '../services/analysis_service.dart';

class AddLinkPage extends StatefulWidget {
  const AddLinkPage({super.key});

  @override
  State<AddLinkPage> createState() => _AddLinkPageState();
}

class _AddLinkPageState extends State<AddLinkPage> {
  static const int maxImageCount = 15;

  final TextEditingController urlController = TextEditingController();

  final FirestoreService _firestoreService = FirestoreService();
  final AnalysisService _analysisService = AnalysisService();

  bool isSaving = false;

  List<Uint8List> selectedImageBytesList = [];
  List<String> selectedImageFileNames = [];

  @override
  void dispose() {
    urlController.dispose();
    super.dispose();
  }

  Future<void> pickImages() async {
    final picker = ImagePicker();

    final images = await picker.pickMultiImage();

    if (images.isEmpty) return;

    if (images.length > maxImageCount) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('스크린샷은 최대 15장까지 선택할 수 있어요.'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final bytesList = <Uint8List>[];
    final fileNames = <String>[];

    for (final image in images) {
      final bytes = await image.readAsBytes();

      bytesList.add(bytes);
      fileNames.add(image.name);
    }

    setState(() {
      selectedImageBytesList = bytesList;
      selectedImageFileNames = fileNames;
    });
  }

  void removeImage(int index) {
    setState(() {
      selectedImageBytesList.removeAt(index);
      selectedImageFileNames.removeAt(index);
    });
  }

  Future<void> handleSubmit() async {
    final inputUrl = urlController.text.trim();

    final bool hasUrl = inputUrl.isNotEmpty;
    final bool hasImages = selectedImageBytesList.isNotEmpty;

    if (!hasUrl && !hasImages) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('링크나 사진 중 하나 이상 추가해주세요.'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (selectedImageBytesList.length > maxImageCount) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('스크린샷은 최대 15장까지 저장할 수 있어요.'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (isSaving) return;

    setState(() {
      isSaving = true;
    });

    try {
      final imageBytesCopy = List<Uint8List>.from(selectedImageBytesList);
      final imageFileNamesCopy = List<String>.from(selectedImageFileNames);

      final docId = await _firestoreService.addPost(
        url: hasUrl ? inputUrl : 'uploaded_image',
        title: hasImages ? '스크린샷 AI 분석 중' : 'AI 요약 분석 중',
        summary: 'AI가 내용을 정리하고 있어요. 잠시 후 다시 확인해주세요.',
        shortSummary: 'AI가 내용을 정리하고 있어요.',
        detailSummary: 'AI가 내용을 정리하고 있어요. 잠시 후 다시 확인해주세요.',
        tags: hasImages ? ['이미지'] : ['링크'],
        category: '기타',
        thumbnail: '',
        status: 'ANALYZING',
        originalText: '',
        imageUrls: const [],
        sourceType: hasImages && hasUrl
            ? 'complex'
            : hasImages
                ? 'screenshots'
                : 'link',
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('저장되었어요. AI가 분석 중입니다.'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );

      Future.microtask(() {
        _uploadAnalyzeAndUpdatePost(
          docId: docId,
          inputUrl: inputUrl,
          imageBytesList: imageBytesCopy,
          imageFileNames: imageFileNamesCopy,
        );
      });

      Navigator.pushNamedAndRemoveUntil(
        context,
        AppRoutes.archive,
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isSaving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('저장 중 오류가 발생했습니다: $e'),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _uploadAnalyzeAndUpdatePost({
    required String docId,
    required String inputUrl,
    required List<Uint8List> imageBytesList,
    required List<String> imageFileNames,
  }) async {
    final bool hasUrl = inputUrl.trim().isNotEmpty;
    final bool hasImages = imageBytesList.isNotEmpty;

    try {
      List<String> imageUrls = [];

      if (hasImages) {
        imageUrls = await _analysisService.uploadImages(
          imageBytesList,
          imageFileNames,
        );

        await _firestoreService.updatePostImageUrls(
          id: docId,
          imageUrls: imageUrls,
        );
      }

      if (hasImages && !hasUrl) {
        final groups = await _analysisService.analyzeImageGroups(
          imageBytesList,
          imageFileNames,
        );

        if (groups.isEmpty) {
          throw Exception('이미지 그룹 분석 결과가 없습니다.');
        }

        final firstGroup = groups.first;
        final firstGroupSummary = (firstGroup['summary'] ?? '').toString();
        final firstGroupShortSummary =
            (firstGroup['shortSummary'] ?? '').toString();
        final firstGroupDetailSummary =
            (firstGroup['detailSummary'] ?? firstGroupSummary).toString();

        final firstGroupImageUrls = _getGroupImageUrls(
          firstGroup,
          imageUrls,
        );

        await _firestoreService.updatePostImageUrls(
          id: docId,
          imageUrls: firstGroupImageUrls,
        );

        await _firestoreService.updatePostAnalysis(
          id: docId,
          url: (firstGroup['url'] ?? 'uploaded_image').toString(),
          title: (firstGroup['title'] ?? '스크린샷 분석 결과').toString(),
          summary: firstGroupSummary,
          shortSummary: firstGroupShortSummary,
          detailSummary: firstGroupDetailSummary,
          tags: _safeTags(
            _parseStringList(firstGroup['tags']),
            hasImages: true,
          ),
          category: (firstGroup['category'] ?? '기타').toString(),
          thumbnail:
              firstGroupImageUrls.isNotEmpty ? firstGroupImageUrls.first : '',
          status: 'COMPLETED',
          originalText: (firstGroup['originalText'] ?? '').toString(),
        );

        for (int i = 1; i < groups.length; i++) {
          final group = groups[i];
          final groupSummary = (group['summary'] ?? '').toString();
          final groupShortSummary = (group['shortSummary'] ?? '').toString();
          final groupDetailSummary =
              (group['detailSummary'] ?? groupSummary).toString();

          final groupImageUrls = _getGroupImageUrls(
            group,
            imageUrls,
          );

          await _firestoreService.addPost(
            url: (group['url'] ?? 'uploaded_image').toString(),
            title: (group['title'] ?? '스크린샷 분석 결과').toString(),
            summary: groupSummary,
            shortSummary: groupShortSummary,
            detailSummary: groupDetailSummary,
            tags: _safeTags(
              _parseStringList(group['tags']),
              hasImages: true,
            ),
            category: (group['category'] ?? '기타').toString(),
            thumbnail: groupImageUrls.isNotEmpty ? groupImageUrls.first : '',
            status: 'COMPLETED',
            originalText: (group['originalText'] ?? '').toString(),
            imageUrls: groupImageUrls,
            sourceType: 'screenshots',
          );
        }

        return;
      }

      Map<String, dynamic> analyzedData;

      if (hasUrl && hasImages) {
        analyzedData = await _analysisService.analyzeComplex(
          url: inputUrl.trim(),
          imageBytesList: imageBytesList,
          fileNames: imageFileNames,
        );
      } else {
        analyzedData = await _analysisService.analyzeUrl(inputUrl.trim());
      }

      final analyzedSummary = (analyzedData['summary'] ?? '').toString();
      final analyzedShortSummary =
          (analyzedData['shortSummary'] ?? '').toString();
      final analyzedDetailSummary =
          (analyzedData['detailSummary'] ?? analyzedSummary).toString();

      await _firestoreService.updatePostAnalysis(
        id: docId,
        url: (analyzedData['url'] ?? inputUrl).toString(),
        title: (analyzedData['title'] ?? '제목 없음').toString(),
        summary: analyzedSummary,
        shortSummary: analyzedShortSummary,
        detailSummary: analyzedDetailSummary,
        tags: _safeTags(
          _parseStringList(analyzedData['tags']),
          hasImages: hasImages,
        ),
        category: (analyzedData['category'] ?? '기타').toString(),
        thumbnail: imageUrls.isNotEmpty
            ? imageUrls.first
            : (analyzedData['thumbnail'] ?? '').toString(),
        status: 'COMPLETED',
        originalText: (analyzedData['originalText'] ?? '').toString(),
      );
    } catch (e) {
      await _firestoreService.updatePostAnalysis(
        id: docId,
        url: inputUrl.trim().isNotEmpty ? inputUrl.trim() : 'uploaded_image',
        title: 'AI 요약 실패',
        summary: 'AI 요약에 실패했습니다. 원본은 저장되었습니다.',
        shortSummary: 'AI 요약에 실패했습니다.',
        detailSummary: 'AI 요약에 실패했습니다. 원본은 저장되었습니다.',
        tags: hasImages ? const ['이미지'] : const ['링크'],
        category: '기타',
        thumbnail: '',
        status: 'FAILED',
        originalText: e.toString(),
      );
    }
  }

  List<String> _parseStringList(dynamic value) {
    if (value is List) {
      return value
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    if (value is String && value.trim().isNotEmpty) {
      return value
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    return <String>[];
  }

  List<String> _safeTags(
    List<String> tags, {
    required bool hasImages,
  }) {
    final blocked = {
      '분석실패',
      '실패',
      '에러',
      '오류',
      '분석오류',
      '요약실패',
      '확인필요',
    };

    final cleaned = tags
        .map((e) => e.replaceAll('#', '').trim())
        .where((e) => e.isNotEmpty)
        .where((e) => !blocked.contains(e))
        .take(3)
        .toList();

    if (cleaned.isNotEmpty) return cleaned;

    return hasImages ? ['이미지'] : ['링크'];
  }

  List<String> _getGroupImageUrls(
    Map<String, dynamic> group,
    List<String> allImageUrls,
  ) {
    final rawIndexes = group['imageIndexes'];

    if (rawIndexes is! List) {
      return allImageUrls;
    }

    final indexes = rawIndexes
        .map((e) => int.tryParse(e.toString()))
        .whereType<int>()
        .where((index) => index >= 0 && index < allImageUrls.length)
        .toList();

    if (indexes.isEmpty) {
      return allImageUrls;
    }

    return indexes.map((index) => allImageUrls[index]).toList();
  }

  Widget buildSelectedImageList() {
    if (selectedImageFileNames.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '선택된 스크린샷 ${selectedImageFileNames.length}/$maxImageCount장',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 10),
        ...List.generate(selectedImageFileNames.length, (index) {
          final name = selectedImageFileNames[index];

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F4),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.image,
                  size: 18,
                  color: Color(0xFF6E56CF),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.charcoal,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: isSaving ? null : () => removeImage(index),
                  icon: const Icon(
                    Icons.close,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget buildLogoHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(
          color: AppColors.peachDustLight,
          width: 2,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Image.asset(
            'assets/images/resee_app_icon.png',
            width: 100,
            height: 100,
            fit: BoxFit.contain,
          ),
          const SizedBox(width: 18),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '콘텐츠를 저장하고\nAI 요약을 받아보세요',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    color: AppColors.charcoal,
                    height: 1.35,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '스크린샷 여러 장도 AI가 흐름에 맞게 정리해드려요',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inputUrl = urlController.text.trim();

    final bool hasUrl = inputUrl.isNotEmpty;
    final bool hasImages = selectedImageBytesList.isNotEmpty;
    final bool isDisabled = !hasUrl && !hasImages;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.charcoal,
        title: const Text(
          '콘텐츠 추가',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 22,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: isSaving ? null : () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        children: [
          buildLogoHeader(),
          const SizedBox(height: 28),
          const Text(
            '링크 붙여넣기',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.charcoal,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: urlController,
            enabled: !isSaving,
            onChanged: (_) {
              setState(() {});
            },
            minLines: 3,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'https://www.instagram.com/...',
              hintStyle: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 15,
              ),
              filled: true,
              fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.all(20),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: const BorderSide(
                  color: Color(0xFF6E56CF),
                  width: 1.5,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: const BorderSide(
                  color: Color(0xFF6E56CF),
                  width: 1.5,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: const BorderSide(
                  color: Color(0xFF6E56CF),
                  width: 2,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '링크와 사진을 같이 넣으면 하나의 카드로 통합 분석됩니다.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            '스크린샷 추가',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.charcoal,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFF6E56CF),
                width: 1.5,
              ),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.image_outlined,
                  size: 42,
                  color: Color(0xFF6E56CF),
                ),
                const SizedBox(height: 12),
                const Text(
                  '여러 장의 스크린샷을 올리면 AI가 핵심을 정리해요',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '최대 15장까지 한 번에 올릴 수 있어요',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: isSaving ? null : pickImages,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF6E56CF),
                    side: const BorderSide(color: Color(0xFF6E56CF)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('사진 여러 장 선택'),
                ),
                buildSelectedImageList(),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            '저장하면 먼저 아카이브로 이동하고, AI가 뒤에서 분석해요. 이미지가 많으면 분석 시간이 조금 걸릴 수 있어요.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: isDisabled || isSaving ? null : handleSubmit,
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  isDisabled ? Colors.grey.shade300 : AppColors.peachDust,
              foregroundColor:
                  isDisabled ? Colors.grey.shade600 : AppColors.charcoal,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 20),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
            ),
            child: Text(
              isSaving ? '저장 중...' : '저장하고 요약받기',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}