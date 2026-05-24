import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class AnalysisService {
  static const String baseUrl = 'http://127.0.0.1:8000';

  Future<List<String>> uploadImages(
    List<Uint8List> imageBytesList,
    List<String> fileNames,
  ) async {
    final uri = Uri.parse('$baseUrl/upload/images');
    final request = http.MultipartRequest('POST', uri);

    for (int i = 0; i < imageBytesList.length; i++) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'files',
          imageBytesList[i],
          filename: fileNames[i],
        ),
      );
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    print('이미지 업로드 상태코드: ${response.statusCode}');
    print('이미지 업로드 응답: ${utf8.decode(response.bodyBytes)}');

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final rawUrls = decoded['imageUrls'];

      if (rawUrls is List) {
        return rawUrls.map((e) => e.toString()).toList();
      }

      return [];
    }

    throw Exception('이미지 업로드 실패: ${response.statusCode}');
  }

  Future<Map<String, dynamic>> analyzeUrl(String url) async {
    try {
      final uri = Uri.parse('$baseUrl/analyze').replace(
        queryParameters: {
          'url': url,
        },
      );

      final response = await http.post(
        uri,
        headers: {
          'accept': 'application/json',
        },
      );

      print('AI 응답 상태코드: ${response.statusCode}');
      print('AI 응답 body: ${utf8.decode(response.bodyBytes)}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        return _normalizeResult(decoded, fallbackUrl: url);
      }

      throw Exception('AI 분석 실패: ${response.statusCode}');
    } catch (e) {
      throw Exception('AI 분석 요청 실패: $e');
    }
  }

  Future<Map<String, dynamic>> analyzeImageFiles(
    List<Uint8List> imageBytesList,
    List<String> fileNames,
  ) async {
    try {
      final uri = Uri.parse('$baseUrl/analyze/image');
      final request = http.MultipartRequest('POST', uri);

      for (int i = 0; i < imageBytesList.length; i++) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'files',
            imageBytesList[i],
            filename: fileNames[i],
          ),
        );
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      print('이미지 AI 응답 상태코드: ${response.statusCode}');
      print('이미지 AI 응답 body: ${utf8.decode(response.bodyBytes)}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        return _normalizeResult(decoded, fallbackUrl: 'uploaded_image');
      }

      throw Exception('이미지 분석 실패: ${response.statusCode}');
    } catch (e) {
      throw Exception('이미지 분석 요청 실패: $e');
    }
  }

  Future<Map<String, dynamic>> analyzeComplex({
    required String url,
    required List<Uint8List> imageBytesList,
    required List<String> fileNames,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/analyze/complex').replace(
        queryParameters: {
          'url': url,
        },
      );

      final request = http.MultipartRequest('POST', uri);

      for (int i = 0; i < imageBytesList.length; i++) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'files',
            imageBytesList[i],
            filename: fileNames[i],
          ),
        );
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      print('복합 AI 응답 상태코드: ${response.statusCode}');
      print('복합 AI 응답 body: ${utf8.decode(response.bodyBytes)}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        return _normalizeResult(decoded, fallbackUrl: url);
      }

      throw Exception('복합 분석 실패: ${response.statusCode}');
    } catch (e) {
      throw Exception('복합 분석 요청 실패: $e');
    }
  }

  Future<List<Map<String, dynamic>>> analyzeImageGroups(
    List<Uint8List> imageBytesList,
    List<String> fileNames,
  ) async {
    try {
      final uri = Uri.parse('$baseUrl/analyze/image-groups');
      final request = http.MultipartRequest('POST', uri);

      for (int i = 0; i < imageBytesList.length; i++) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'files',
            imageBytesList[i],
            filename: fileNames[i],
          ),
        );
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      print('이미지 그룹 분석 상태코드: ${response.statusCode}');
      print('이미지 그룹 분석 응답: ${utf8.decode(response.bodyBytes)}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));

        final rawGroups = decoded['groups'];

        if (rawGroups is List) {
          return rawGroups.map((group) {
            if (group is Map<String, dynamic>) {
              return _normalizeGroupResult(group);
            }

            return _normalizeGroupResult({});
          }).toList();
        }

        final fallback = _normalizeResult(
          decoded,
          fallbackUrl: 'uploaded_image',
        );

        return [fallback];
      }

      throw Exception('이미지 그룹 분석 실패: ${response.statusCode}');
    } catch (e) {
      throw Exception('이미지 그룹 분석 요청 실패: $e');
    }
  }

  Map<String, dynamic> _normalizeResult(
    Map<String, dynamic> decoded, {
    required String fallbackUrl,
  }) {
    return {
      'url': (decoded['url'] ?? fallbackUrl).toString(),
      'title': (decoded['title'] ?? '제목 없음').toString(),
      'summary': (decoded['summary'] ?? '').toString(),
      'category': (decoded['category'] ?? '기타').toString(),
      'tags': _parseTags(decoded['tags']),
      'thumbnail': (decoded['thumbnail'] ?? '').toString(),
      'status': (decoded['status'] ?? 'COMPLETED').toString(),
      'originalText': (decoded['originalText'] ??
              decoded['original_text'] ??
              decoded['content'] ??
              '')
          .toString(),
      'imageIndexes': _parseIntList(decoded['imageIndexes']),
    };
  }

  Map<String, dynamic> _normalizeGroupResult(Map<String, dynamic> decoded) {
    return {
      'url': (decoded['url'] ?? 'uploaded_image').toString(),
      'title': (decoded['title'] ?? '스크린샷 분석 결과').toString(),
      'summary': (decoded['summary'] ?? '').toString(),
      'category': (decoded['category'] ?? '기타').toString(),
      'tags': _parseTags(decoded['tags']),
      'thumbnail': (decoded['thumbnail'] ?? '').toString(),
      'status': (decoded['status'] ?? 'COMPLETED').toString(),
      'originalText': (decoded['originalText'] ??
              decoded['original_text'] ??
              decoded['content'] ??
              '')
          .toString(),
      'imageIndexes': _parseIntList(decoded['imageIndexes']),
    };
  }

  List<String> _parseTags(dynamic rawTags) {
    if (rawTags is List) {
      return rawTags
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    if (rawTags is String && rawTags.trim().isNotEmpty) {
      return rawTags
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    return <String>[];
  }

  List<int> _parseIntList(dynamic rawList) {
    if (rawList is List) {
      return rawList
          .map((e) => int.tryParse(e.toString()))
          .whereType<int>()
          .toList();
    }

    return <int>[];
  }
}