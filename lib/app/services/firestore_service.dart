import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get _currentUserId {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('로그인이 필요합니다.');
    }

    return user.uid;
  }

  DateTime _parseDate(dynamic value) {
    try {
      if (value == null) {
        return DateTime.fromMillisecondsSinceEpoch(0);
      }

      if (value is DateTime) {
        return value;
      }

      return value.toDate();
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  Future<String> addPost({
    required String url,
    required String title,
    required String summary,
    required List<String> tags,
    required String category,
    required String thumbnail,
    String status = 'ACTIVE',
    String originalText = '',
    List<String> imageUrls = const [],
    String sourceType = 'link',
    String shortSummary = '',
    String detailSummary = '',
  }) async {
    final userId = _currentUserId;

    final savedDetailSummary =
        detailSummary.trim().isNotEmpty ? detailSummary.trim() : summary.trim();

    final docRef = await _db.collection('posts').add({
      'userId': userId,
      'url': url,
      'title': title,
      'summary': summary,
      'shortSummary': shortSummary,
      'detailSummary': savedDetailSummary,
      'tags': tags,
      'category': category,
      'thumbnail': thumbnail,
      'status': status,
      'memo': '',
      'originalText': originalText,
      'imageUrls': imageUrls,
      'sourceType': sourceType,
      'imageCount': imageUrls.length,
      'isRead': false,
      'isFavorite': false,
      'isPinned': false,
      'isDeleted': false,
      'isCollected': false,
      'createdAt': FieldValue.serverTimestamp(),
      'completedAt': null,
    });

    return docRef.id;
  }

  Future<List<String>> addGroupedImagePosts({
    required List<Map<String, dynamic>> groups,
    required List<String> imageUrls,
  }) async {
    final userId = _currentUserId;
    final batch = _db.batch();
    final List<String> createdIds = [];

    for (final group in groups) {
      final docRef = _db.collection('posts').doc();
      createdIds.add(docRef.id);

      final rawIndexes = group['imageIndexes'];
      final List<int> imageIndexes = rawIndexes is List
          ? rawIndexes
              .map((e) => int.tryParse(e.toString()))
              .whereType<int>()
              .toList()
          : <int>[];

      final List<String> groupImageUrls = imageIndexes.isEmpty
          ? imageUrls
          : imageIndexes
              .where((index) => index >= 0 && index < imageUrls.length)
              .map((index) => imageUrls[index])
              .toList();

      final String summary = (group['summary'] ?? '').toString();
      final String shortSummary = (group['shortSummary'] ?? '').toString();
      final String detailSummary =
          (group['detailSummary'] ?? summary).toString();

      batch.set(docRef, {
        'userId': userId,
        'url': (group['url'] ?? 'uploaded_image').toString(),
        'title': (group['title'] ?? '스크린샷 분석 결과').toString(),
        'summary': summary,
        'shortSummary': shortSummary,
        'detailSummary':
            detailSummary.trim().isNotEmpty ? detailSummary : summary,
        'tags': _parseStringList(group['tags']),
        'category': (group['category'] ?? '기타').toString(),
        'thumbnail': groupImageUrls.isNotEmpty
            ? groupImageUrls.first
            : (group['thumbnail'] ?? '').toString(),
        'status': (group['status'] ?? 'COMPLETED').toString(),
        'memo': '',
        'originalText': (group['originalText'] ?? '').toString(),
        'imageUrls': groupImageUrls,
        'sourceType': 'screenshots',
        'imageCount': groupImageUrls.length,
        'isRead': false,
        'isFavorite': false,
        'isPinned': false,
        'isDeleted': false,
        'isCollected': false,
        'createdAt': FieldValue.serverTimestamp(),
        'completedAt': null,
      });
    }

    await batch.commit();

    return createdIds;
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

  Future<void> updatePostAnalysis({
    required String id,
    required String url,
    required String title,
    required String summary,
    required List<String> tags,
    required String category,
    required String thumbnail,
    required String status,
    required String originalText,
    String shortSummary = '',
    String detailSummary = '',
  }) async {
    final savedDetailSummary =
        detailSummary.trim().isNotEmpty ? detailSummary.trim() : summary.trim();

    await _db.collection('posts').doc(id).update({
      'url': url,
      'title': title,
      'summary': summary,
      'shortSummary': shortSummary,
      'detailSummary': savedDetailSummary,
      'tags': tags,
      'category': category,
      'thumbnail': thumbnail,
      'status': status,
      'originalText': originalText,
      'completedAt': status == 'COMPLETED' ? FieldValue.serverTimestamp() : null,
    });
  }

  Future<void> updatePostImageUrls({
    required String id,
    required List<String> imageUrls,
  }) async {
    await _db.collection('posts').doc(id).update({
      'imageUrls': imageUrls,
      'imageCount': imageUrls.length,
      'thumbnail': imageUrls.isNotEmpty ? imageUrls.first : '',
    });
  }

  Future<List<Map<String, dynamic>>> getPosts() async {
    final userId = _currentUserId;

    final snapshot = await _db
        .collection('posts')
        .where('userId', isEqualTo: userId)
        .get();

    final posts = snapshot.docs.map((doc) {
      final data = doc.data();

      return {
        'id': doc.id,
        ...data,
        'detailSummary':
            (data['detailSummary'] ?? data['summary'] ?? '').toString(),
        'shortSummary': (data['shortSummary'] ?? '').toString(),
      };
    }).toList();

    posts.sort((a, b) {
      final aDate = _parseDate(a['createdAt']);
      final bDate = _parseDate(b['createdAt']);
      return bDate.compareTo(aDate);
    });

    return posts;
  }

  Future<Map<String, dynamic>?> getPostById(String id) async {
    final userId = _currentUserId;

    final doc = await _db.collection('posts').doc(id).get();

    if (!doc.exists) return null;

    final data = doc.data()!;

    if (data['userId'] != userId) {
      return null;
    }

    return {
      'id': doc.id,
      ...data,
      'detailSummary':
          (data['detailSummary'] ?? data['summary'] ?? '').toString(),
      'shortSummary': (data['shortSummary'] ?? '').toString(),
    };
  }

  Future<List<Map<String, dynamic>>> getTrashPosts() async {
    final posts = await getPosts();

    return posts.where((post) {
      return (post['isDeleted'] ?? false) == true;
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getCollectedPosts() async {
    final posts = await getPosts();

    return posts.where((post) {
      final bool isCollected = post['isCollected'] ?? false;
      final bool isDeleted = post['isDeleted'] ?? false;

      return isCollected == true && isDeleted == false;
    }).toList();
  }

  Future<void> updateReadStatus(String id, bool isRead) async {
    await _db.collection('posts').doc(id).update({
      'isRead': isRead,
    });
  }

  Future<void> updateFavoriteStatus(String id, bool isFavorite) async {
    await _db.collection('posts').doc(id).update({
      'isFavorite': isFavorite,
    });
  }

  Future<void> updatePinnedStatus(String id, bool isPinned) async {
    await _db.collection('posts').doc(id).update({
      'isPinned': isPinned,
    });
  }

  Future<void> updateCollectedStatus(String id, bool isCollected) async {
    await _db.collection('posts').doc(id).update({
      'isCollected': isCollected,
      'completedAt': isCollected ? FieldValue.serverTimestamp() : null,
    });
  }

  Future<void> updateSummary(String id, String summary) async {
    await _db.collection('posts').doc(id).update({
      'summary': summary,
      'detailSummary': summary,
    });
  }

  Future<void> updateDetailSummary(String id, String detailSummary) async {
    await _db.collection('posts').doc(id).update({
      'summary': detailSummary,
      'detailSummary': detailSummary,
    });
  }

  Future<void> updateShortSummary(String id, String shortSummary) async {
    await _db.collection('posts').doc(id).update({
      'shortSummary': shortSummary,
    });
  }

  Future<void> updateMemo(String id, String memo) async {
    await _db.collection('posts').doc(id).update({
      'memo': memo,
    });
  }

  Future<void> updatePostCategory(String id, String category) async {
    await _db.collection('posts').doc(id).update({
      'category': category,
    });

    await syncCategoryCounts();
  }

  Future<void> moveToTrash(String id) async {
    await _db.collection('posts').doc(id).update({
      'isDeleted': true,
    });

    await syncCategoryCounts();
  }

  Future<void> restoreFromTrash(String id) async {
    await _db.collection('posts').doc(id).update({
      'isDeleted': false,
    });

    await syncCategoryCounts();
  }

  Future<void> deletePostPermanently(String id) async {
    await _db.collection('posts').doc(id).delete();

    await syncCategoryCounts();
  }

  Future<void> seedDefaultCategoriesIfNeeded() async {
    final snapshot = await _db.collection('categories').get();

    if (snapshot.docs.isNotEmpty) return;

    final batch = _db.batch();

    final defaultCategories = [
      {
        'name': '자기계발',
        'originalName': '자기계발',
        'count': 0,
        'color': 0xFFC2D6CF,
        'isMain': true,
        'sortOrder': 0,
      },
      {
        'name': '운동',
        'originalName': '운동',
        'count': 0,
        'color': 0xFFD8B4FE,
        'isMain': true,
        'sortOrder': 1,
      },
      {
        'name': '장소',
        'originalName': '장소',
        'count': 0,
        'color': 0xFFFBBF24,
        'isMain': true,
        'sortOrder': 2,
      },
      {
        'name': '쇼핑',
        'originalName': '쇼핑',
        'count': 0,
        'color': 0xFFF87171,
        'isMain': true,
        'sortOrder': 3,
      },
      {
        'name': '영화',
        'originalName': '영화',
        'count': 0,
        'color': 0xFF9ED0F6,
        'isMain': false,
        'sortOrder': 100,
      },
      {
        'name': '음악',
        'originalName': '음악',
        'count': 0,
        'color': 0xFFF2B8B5,
        'isMain': false,
        'sortOrder': 101,
      },
      {
        'name': '요리',
        'originalName': '요리',
        'count': 0,
        'color': 0xFFA7E3D3,
        'isMain': false,
        'sortOrder': 102,
      },
    ];

    for (final item in defaultCategories) {
      final ref = _db.collection('categories').doc();
      batch.set(ref, item);
    }

    await batch.commit();
  }

  Future<Map<String, int>> _getPostCountsByCategory() async {
    final posts = await getPosts();
    final Map<String, int> counts = {};

    for (final post in posts) {
      final bool isDeleted = post['isDeleted'] ?? false;
      if (isDeleted) continue;

      final String category = (post['category'] ?? '').toString().trim();
      if (category.isEmpty) continue;

      counts[category] = (counts[category] ?? 0) + 1;
    }

    return counts;
  }

  Future<void> syncCategoryCounts() async {
    await seedDefaultCategoriesIfNeeded();

    final categorySnapshot = await _db.collection('categories').get();
    final counts = await _getPostCountsByCategory();

    final batch = _db.batch();

    for (final doc in categorySnapshot.docs) {
      final data = doc.data();
      final String name = (data['name'] ?? '').toString().trim();
      final String originalName = (data['originalName'] ?? '').toString().trim();

      final int count = counts[name] ?? counts[originalName] ?? 0;

      batch.update(doc.reference, {
        'count': count,
      });
    }

    await batch.commit();
  }

  Future<List<Map<String, dynamic>>> getCategories() async {
    try {
      await seedDefaultCategoriesIfNeeded();
      await syncCategoryCounts();

      final snapshot =
          await _db.collection('categories').orderBy('sortOrder').get();

      final categories = snapshot.docs.map((doc) {
        return {
          'id': doc.id,
          ...doc.data(),
        };
      }).toList();

      categories.sort((a, b) {
        final bool aMain = a['isMain'] ?? false;
        final bool bMain = b['isMain'] ?? false;

        if (aMain != bMain) {
          return aMain ? -1 : 1;
        }

        final int aOrder = (a['sortOrder'] ?? 0) as int;
        final int bOrder = (b['sortOrder'] ?? 0) as int;

        return aOrder.compareTo(bOrder);
      });

      return categories;
    } catch (_) {
      return [];
    }
  }

  Future<void> addCategory({
    required String name,
    bool isMain = false,
    int? color,
  }) async {
    final snapshot = await _db.collection('categories').get();

    await _db.collection('categories').add({
      'name': name,
      'originalName': name,
      'count': 0,
      'color': color ?? 0xFF9ED0F6,
      'isMain': isMain,
      'sortOrder': snapshot.docs.length,
    });

    await syncCategoryCounts();
  }

  Future<void> updateCategoryName({
    required String id,
    required String name,
  }) async {
    final categoryDoc = await _db.collection('categories').doc(id).get();
    if (!categoryDoc.exists) return;

    final data = categoryDoc.data()!;
    final String oldName = (data['name'] ?? '').toString().trim();
    final String originalName = (data['originalName'] ?? '').toString().trim();

    if (oldName.isEmpty) return;

    await _db.collection('categories').doc(id).update({
      'name': name,
    });

    final userId = _currentUserId;

    final postsSnapshot = await _db
        .collection('posts')
        .where('userId', isEqualTo: userId)
        .get();

    final batch = _db.batch();

    for (final doc in postsSnapshot.docs) {
      final postData = doc.data();
      final String postCategory = (postData['category'] ?? '').toString().trim();

      if (postCategory == oldName || postCategory == originalName) {
        batch.update(doc.reference, {
          'category': name,
        });
      }
    }

    await batch.commit();
    await syncCategoryCounts();
  }

  Future<void> deleteCategory(String id) async {
    await _db.collection('categories').doc(id).delete();

    await syncCategoryCounts();
  }

  Future<void> updateCategoryMainStatus({
    required String id,
    required bool isMain,
  }) async {
    await _db.collection('categories').doc(id).update({
      'isMain': isMain,
    });

    await syncCategoryCounts();
  }

  Future<void> updateCategorySortOrder({
    required String id,
    required int sortOrder,
  }) async {
    await _db.collection('categories').doc(id).update({
      'sortOrder': sortOrder,
    });
  }

  Future<void> reorderCategories(List<Map<String, dynamic>> categories) async {
    final batch = _db.batch();

    for (int i = 0; i < categories.length; i++) {
      final id = (categories[i]['id'] ?? '').toString();

      if (id.isEmpty) continue;

      final ref = _db.collection('categories').doc(id);

      batch.update(ref, {
        'sortOrder': i,
      });
    }

    await batch.commit();
  }

  Future<void> promoteCategoryToMain({
    required String id,
    required int sortOrder,
  }) async {
    await _db.collection('categories').doc(id).update({
      'isMain': true,
      'sortOrder': sortOrder,
    });

    await syncCategoryCounts();
  }

  Future<void> demoteCategoryToEtc({
    required String id,
    required int sortOrder,
  }) async {
    await _db.collection('categories').doc(id).update({
      'isMain': false,
      'sortOrder': sortOrder,
    });

    await syncCategoryCounts();
  }
}