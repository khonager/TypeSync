/// Storage Service
///
/// Manages cloud storage quota and subscription tiers.
/// Handles file uploads to Firebase Storage with size tracking.
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firedart/firedart.dart' as fd;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user.dart';
import '../../firebase_options.dart';
import 'diagnostics_service.dart';

String? resolveStorageObjectPath(
  String path, {
  required String userId,
}) {
  if (path.startsWith('gs://')) {
    final uri = Uri.parse(path);
    final objectPath =
        uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
    return objectPath.isEmpty ? null : objectPath;
  }

  if (!path.startsWith('http://') && !path.startsWith('https://')) {
    if (path.startsWith('users/')) {
      return path;
    }
    return 'users/$userId/$path';
  }

  final uri = Uri.tryParse(path);
  if (uri == null) return null;
  final segments = uri.pathSegments;
  final objectIndex = segments.indexOf('o');
  if (objectIndex == -1 || objectIndex + 1 >= segments.length) {
    return null;
  }
  return Uri.decodeComponent(segments[objectIndex + 1]);
}

/// Service for managing cloud storage and subscriptions
///
/// Tracks storage usage against subscription limits and handles
/// file upload/download operations to Firebase Storage.
class StorageService extends ChangeNotifier {
  static const String _storageUsagePrefsPrefix = 'cloud_storage_usage_';

  // Lazy Firebase instances
  FirebaseStorage? _storage;
  FirebaseFirestore? _firestore;
  final DiagnosticsService _diagnostics = DiagnosticsService.instance;
  final http.Client _httpClient = http.Client();

  FirebaseStorage get _firebaseStorage {
    try {
      _storage ??= FirebaseStorage.instance;
      return _storage!;
    } catch (e) {
      debugPrint('Firebase Storage not available: $e');
      rethrow;
    }
  }

  FirebaseFirestore get _firebaseFirestore {
    try {
      _firestore ??= FirebaseFirestore.instance;
      return _firestore!;
    } catch (e) {
      debugPrint('Firebase Firestore not available: $e');
      rethrow;
    }
  }

  fd.Firestore? get _firedartFirestore {
    if (defaultTargetPlatform == TargetPlatform.linux && !kIsWeb) {
      if (fd.Firestore.initialized) {
        return fd.Firestore.instance;
      }
    }
    return null;
  }

  // Current user subscription info
  SubscriptionTier _currentTier = SubscriptionTier.free;
  int _storageUsedBytes = 0;
  int _cloudContentBytes = 0;
  int _cloudAttachmentBytes = 0;
  int _cloudRecordedBytes = 0;
  int _cloudNoteCount = 0;
  int _cloudAttachmentCount = 0;
  int _cloudStoredFileBytes = 0;
  int _cloudStoredFileCount = 0;
  bool _isLoading = false;
  bool _hasLoadedStorageInfo = false;
  bool _hasAuditedStorageInfo = false;
  String? _errorMessage;

  // ===========================================
  // GETTERS
  // ===========================================

  SubscriptionTier get currentTier => _currentTier;
  int get storageUsedBytes => _storageUsedBytes;
  int get cloudContentBytes => _cloudContentBytes;
  int get cloudAttachmentBytes => _cloudAttachmentBytes;
  int get cloudRecordedBytes => _cloudRecordedBytes;
  int get cloudNoteCount => _cloudNoteCount;
  int get cloudAttachmentCount => _cloudAttachmentCount;
  int get cloudStoredFileBytes => _cloudStoredFileBytes;
  int get cloudStoredFileCount => _cloudStoredFileCount;
  int get cloudFileCount =>
      _cloudStoredFileCount > 0 ? _cloudStoredFileCount : _cloudAttachmentCount;
  int get storageLimitBytes => _currentTier.storageLimitBytes;
  double get usagePercent => _storageUsedBytes / storageLimitBytes;
  int get storageRemainingBytes => storageLimitBytes - _storageUsedBytes;
  bool get isStorageFull => _storageUsedBytes >= storageLimitBytes;
  bool get isLoading => _isLoading;
  bool get hasLoadedStorageInfo => _hasLoadedStorageInfo;
  bool get hasAuditedStorageInfo => _hasAuditedStorageInfo;
  String? get errorMessage => _errorMessage;

  /// Formatted storage usage string
  String get usageFormatted =>
      '${_formatBytes(_storageUsedBytes)} / ${_currentTier.storageLimitFormatted}';

  // ===========================================
  // SUBSCRIPTION PRICING
  // ===========================================

  /// Get all available subscription tiers with pricing
  static List<SubscriptionInfo> get subscriptionPlans => [
        const SubscriptionInfo(
          tier: SubscriptionTier.free,
          name: 'Free',
          storage: '5 MB',
          priceEuros: 0,
          features: [
            'Unlimited local notes',
            'Small cloud trial',
            'Core productivity tools',
          ],
        ),
        const SubscriptionInfo(
          tier: SubscriptionTier.basic,
          name: 'TypeSync Lite',
          storage: '1 GB',
          priceEuros: 2.99,
          features: [
            'Unlimited synced notes',
            '1 GB cloud storage',
            'Cloud attachments',
          ],
        ),
        const SubscriptionInfo(
          tier: SubscriptionTier.standard,
          name: 'Plus',
          storage: '25 GB',
          priceEuros: 5.99,
          features: [
            'Everything in TypeSync Lite',
            '25 GB cloud storage',
            'More room for documents and media',
          ],
        ),
        const SubscriptionInfo(
          tier: SubscriptionTier.premium,
          name: 'Pro',
          storage: '100 GB',
          priceEuros: 11.99,
          features: [
            'Everything in Plus',
            '100 GB cloud storage',
            'For large course and project archives',
          ],
        ),
      ];

  // ===========================================
  // PUBLIC METHODS
  // ===========================================

  /// Load storage info for a user
  ///
  /// Loads the saved account storage total, with an optional full audit.
  Future<void> loadStorageInfo(
    String userId, {
    User? fallbackUser,
    bool runAudit = false,
  }) async {
    _isLoading = true;
    if (fallbackUser != null) {
      _currentTier = fallbackUser.subscriptionTier;
      _storageUsedBytes = fallbackUser.storageUsedBytes;
      _cloudRecordedBytes = fallbackUser.storageUsedBytes;
      _hasLoadedStorageInfo = true;
    }
    notifyListeners();

    var loadFailed = false;

    try {
      final cachedBytes = await _readCachedStorageUsage(userId);
      if (cachedBytes != null && cachedBytes > _storageUsedBytes) {
        _applyRecordedUsage(cachedBytes);
        notifyListeners();
      }

      var recordedBytes = fallbackUser?.storageUsedBytes ?? _storageUsedBytes;
      final userSnapshot = await _loadUserStorageSnapshot(
        userId,
        fallbackTier: _currentTier,
        fallbackRecordedBytes: recordedBytes,
      );

      _currentTier = userSnapshot.tier;
      recordedBytes = [
        userSnapshot.recordedBytes,
        cachedBytes ?? 0,
      ].reduce((max, value) => value > max ? value : max);
      _storageUsedBytes = recordedBytes;
      _cloudRecordedBytes = recordedBytes;
      _hasLoadedStorageInfo = true;

      if (runAudit) {
        final notesMetricsFuture = _loadNoteStorageMetrics(userId);
        final objectMetricsFuture = _auditStorageUsageViaFunction(userId);
        _StorageUsageTotals? noteTotals;
        _AttachmentMetrics? objectMetrics;

        try {
          noteTotals = await notesMetricsFuture;
        } catch (e) {
          loadFailed = true;
          debugPrint('StorageService.loadStorageInfo notes error: $e');
        }

        try {
          objectMetrics = await objectMetricsFuture;
        } catch (e) {
          loadFailed = true;
          debugPrint('StorageService.loadStorageInfo object listing error: $e');
        }

        final totalBytes = noteTotals?.totalBytes ?? 0;
        final contentBytes = noteTotals?.contentBytes ?? 0;
        final attachmentBytes = noteTotals?.attachmentBytes ?? 0;
        final noteCount = noteTotals?.noteCount ?? 0;
        final attachmentCount = noteTotals?.attachmentCount ?? 0;
        final storedFileBytes = objectMetrics?.bytes ?? 0;
        final storedFileCount = objectMetrics?.count ?? 0;
        final effectiveRecordedBytes = [
          recordedBytes,
          storedFileBytes,
        ].reduce((max, value) => value > max ? value : max);

        _storageUsedBytes = [
          totalBytes,
          effectiveRecordedBytes,
          storedFileBytes,
        ].reduce((max, value) => value > max ? value : max);
        _cloudContentBytes = contentBytes;
        _cloudAttachmentBytes = attachmentBytes;
        _cloudRecordedBytes = effectiveRecordedBytes;
        _cloudNoteCount = noteCount;
        _cloudAttachmentCount = attachmentCount;
        _cloudStoredFileBytes = storedFileBytes;
        _cloudStoredFileCount = storedFileCount;
        _hasAuditedStorageInfo = true;
      }

      _errorMessage = loadFailed
          ? 'Loaded partial storage info; using best available data.'
          : null;
      await _persistCachedStorageUsage(userId, _storageUsedBytes);
    } catch (e) {
      _errorMessage = 'Failed to load storage info: $e';
      debugPrint('StorageService.loadStorageInfo error: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Upload a file to Firebase Storage
  ///
  /// Returns the download URL if successful, null if failed or over quota.
  Future<String?> uploadFile({
    required String userId,
    required String filePath,
    required String destinationPath,
    String? contentType,
  }) async {
    final file = File(filePath);
    final fileSize = await file.length();

    _isLoading = true;
    notifyListeners();

    try {
      if (_shouldUseFunctionStorageUploads) {
        final uploadResult = await _uploadDataViaFunction(
          userId: userId,
          destinationPath: destinationPath,
          data: await file.readAsBytes(),
          contentType: contentType,
        );
        _applyRecordedUsage(uploadResult.storageUsedBytes);
        await _persistCachedStorageUsage(userId, _storageUsedBytes);
        _errorMessage = null;
        _isLoading = false;
        _diagnostics.info(
          'StorageService',
          'Uploaded users/$userId/$destinationPath (${_formatBytes(fileSize)})',
        );
        notifyListeners();
        return uploadResult.downloadUrl;
      }

      // Upload to Firebase Storage
      final ref =
          _firebaseStorage.ref().child('users/$userId/$destinationPath');
      final metadata = contentType == null
          ? null
          : SettableMetadata(contentType: contentType);
      final uploadTask = ref.putFile(file, metadata);

      // Wait for upload to complete
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      // Update storage usage in Firestore
      _storageUsedBytes += fileSize;
      if (defaultTargetPlatform == TargetPlatform.linux && !kIsWeb) {
        final fdFirestore = _firedartFirestore;
        if (fdFirestore != null) {
          await fdFirestore.collection('users').document(userId).update({
            'storageUsedBytes': _storageUsedBytes,
          });
        }
      } else {
        await _firebaseFirestore.collection('users').doc(userId).update({
          'storageUsedBytes': _storageUsedBytes,
        });
      }

      _errorMessage = null;
      _isLoading = false;
      _diagnostics.info(
        'StorageService',
        'Uploaded users/$userId/$destinationPath (${_formatBytes(fileSize)})',
      );
      notifyListeners();

      return downloadUrl;
    } catch (e, stackTrace) {
      final detail = _describeStorageError(e);
      _errorMessage = 'Failed to upload file: $detail';
      _diagnostics.error(
        'StorageService',
        'Upload failed for users/$userId/$destinationPath: $detail',
      );
      debugPrintStack(
        label: 'StorageService.uploadFile failed',
        stackTrace: stackTrace,
      );
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  /// Upload in-memory bytes to Firebase Storage.
  ///
  /// Returns the download URL if successful, null if failed or over quota.
  Future<String?> uploadData({
    required String userId,
    required Uint8List data,
    required String destinationPath,
    String? contentType,
  }) async {
    final fileSize = data.length;

    _isLoading = true;
    notifyListeners();

    try {
      if (_shouldUseFunctionStorageUploads) {
        final uploadResult = await _uploadDataViaFunction(
          userId: userId,
          destinationPath: destinationPath,
          data: data,
          contentType: contentType,
        );
        _applyRecordedUsage(uploadResult.storageUsedBytes);
        await _persistCachedStorageUsage(userId, _storageUsedBytes);
        _errorMessage = null;
        _isLoading = false;
        _diagnostics.info(
          'StorageService',
          'Uploaded users/$userId/$destinationPath (${_formatBytes(fileSize)})',
        );
        notifyListeners();
        return uploadResult.downloadUrl;
      }

      final ref =
          _firebaseStorage.ref().child('users/$userId/$destinationPath');
      final metadata = contentType == null
          ? null
          : SettableMetadata(contentType: contentType);
      final snapshot = await ref.putData(data, metadata);
      final downloadUrl = await snapshot.ref.getDownloadURL();

      _storageUsedBytes += fileSize;
      if (defaultTargetPlatform == TargetPlatform.linux && !kIsWeb) {
        final fdFirestore = _firedartFirestore;
        if (fdFirestore != null) {
          await fdFirestore.collection('users').document(userId).update({
            'storageUsedBytes': _storageUsedBytes,
          });
        }
      } else {
        await _firebaseFirestore.collection('users').doc(userId).update({
          'storageUsedBytes': _storageUsedBytes,
        });
      }

      _errorMessage = null;
      _isLoading = false;
      _diagnostics.info(
        'StorageService',
        'Uploaded users/$userId/$destinationPath (${_formatBytes(fileSize)})',
      );
      notifyListeners();

      return downloadUrl;
    } catch (e, stackTrace) {
      final detail = _describeStorageError(e);
      _errorMessage = 'Failed to upload file: $detail';
      _diagnostics.error(
        'StorageService',
        'Upload failed for users/$userId/$destinationPath: $detail',
      );
      debugPrintStack(
        label: 'StorageService.uploadData failed',
        stackTrace: stackTrace,
      );
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  /// Delete a file from Firebase Storage
  Future<bool> deleteFile({
    required String userId,
    required String filePath,
  }) async {
    try {
      final normalizedObjectPath = resolveStorageObjectPath(
        filePath,
        userId: userId,
      );
      if (normalizedObjectPath == null || normalizedObjectPath.isEmpty) {
        throw Exception('Could not resolve storage object path');
      }

      _diagnostics.info(
        'StorageService',
        'ATTACHMENT_DELETE resolved delete target user=$userId input=$filePath object=$normalizedObjectPath linuxRest=$_shouldUseLinuxStorageRest',
      );

      if (_shouldUseFunctionStorageUploads) {
        final deleteResult = await _deleteObjectViaFunction(
          userId: userId,
          objectPath: normalizedObjectPath,
        );
        _applyRecordedUsage(deleteResult.storageUsedBytes);
        await _persistCachedStorageUsage(userId, _storageUsedBytes);
        notifyListeners();
        return true;
      }

      final ref = _firebaseStorage.ref().child(normalizedObjectPath);

      // Get file size before deleting
      final metadata = await ref.getMetadata();
      final fileSize = metadata.size ?? 0;

      await ref.delete();

      // Update storage usage
      _storageUsedBytes =
          (_storageUsedBytes - fileSize).clamp(0, storageLimitBytes);
      if (defaultTargetPlatform == TargetPlatform.linux && !kIsWeb) {
        final fdFirestore = _firedartFirestore;
        if (fdFirestore != null) {
          await fdFirestore.collection('users').document(userId).update({
            'storageUsedBytes': _storageUsedBytes,
          });
        }
      } else {
        await _firebaseFirestore.collection('users').doc(userId).update({
          'storageUsedBytes': _storageUsedBytes,
        });
      }

      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to delete file';
      notifyListeners();
      return false;
    }
  }

  /// Download a file from Firebase Storage
  Future<File?> downloadFile({
    required String userId,
    required String remotePath,
    required String localPath,
  }) async {
    try {
      if (_shouldUseLinuxStorageRest) {
        final file = File(localPath);
        final response = await _httpClient.get(
          Uri.parse(_buildDownloadUrl(_storageObjectPath(userId, remotePath))),
        );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception(_extractHttpError(response));
        }
        await file.writeAsBytes(response.bodyBytes);
        return file;
      }

      final ref = _firebaseStorage.ref().child('users/$userId/$remotePath');
      final file = File(localPath);

      await ref.writeToFile(file);
      return file;
    } catch (e) {
      _errorMessage = 'Failed to download file';
      notifyListeners();
      return null;
    }
  }

  /// Upgrade subscription tier
  ///
  /// Legacy prototype method. Paid entitlements are now granted only through
  /// RevenueCat webhooks, never by direct client writes.
  Future<bool> upgradeSubscription(
    String userId,
    SubscriptionTier newTier,
  ) async {
    _errorMessage =
        'Plan changes are handled by RevenueCat checkout and webhooks.';
    notifyListeners();
    return false;
  }

  /// Calculate total storage used by recalculating from Firestore note sizes
  Future<void> recalculateStorage(String userId) async {
    await loadStorageInfo(userId, runAudit: true);
  }

  // ===========================================
  // PRIVATE METHODS
  // ===========================================

  Future<_UserStorageSnapshot> _loadUserStorageSnapshot(
    String userId, {
    required SubscriptionTier fallbackTier,
    required int fallbackRecordedBytes,
  }) async {
    if (defaultTargetPlatform == TargetPlatform.linux && !kIsWeb) {
      final fdFirestore = _firedartFirestore;
      if (fdFirestore == null) {
        throw Exception('Firedart is not initialized');
      }

      final userDoc =
          await fdFirestore.collection('users').document(userId).get();
      if (userDoc.map.isEmpty) {
        return _UserStorageSnapshot(
          tier: fallbackTier,
          recordedBytes: fallbackRecordedBytes,
        );
      }

      return _UserStorageSnapshot(
        tier: _subscriptionTierFromUserData(
          userDoc.map,
          fallback: fallbackTier,
        ),
        recordedBytes: _intFromDynamic(
              userDoc.map['storageUsedBytes'],
              fallback: fallbackRecordedBytes,
            ) ??
            fallbackRecordedBytes,
      );
    }

    final userDoc =
        await _firebaseFirestore.collection('users').doc(userId).get();
    if (!userDoc.exists) {
      return _UserStorageSnapshot(
        tier: fallbackTier,
        recordedBytes: fallbackRecordedBytes,
      );
    }

    final data = userDoc.data()!;
    return _UserStorageSnapshot(
      tier: _subscriptionTierFromUserData(
        data,
        fallback: fallbackTier,
      ),
      recordedBytes: _intFromDynamic(
            data['storageUsedBytes'],
            fallback: fallbackRecordedBytes,
          ) ??
          fallbackRecordedBytes,
    );
  }

  Future<_StorageUsageTotals> _loadNoteStorageMetrics(String userId) async {
    int totalBytes = 0;
    int contentBytes = 0;
    int attachmentBytes = 0;
    int noteCount = 0;
    int attachmentCount = 0;

    if (defaultTargetPlatform == TargetPlatform.linux && !kIsWeb) {
      final fdFirestore = _firedartFirestore;
      if (fdFirestore == null) {
        throw Exception('Firedart is not initialized');
      }

      final notes = await fdFirestore
          .collection('notes')
          .where('userId', isEqualTo: userId)
          .where('isDeleted', isEqualTo: false)
          .get();
      for (final doc in notes) {
        final noteMetrics = await _noteStorageMetricsFromDynamic(
          doc.map,
          userId: userId,
        );
        totalBytes += noteMetrics.contentBytes + noteMetrics.attachmentBytes;
        contentBytes += noteMetrics.contentBytes;
        attachmentBytes += noteMetrics.attachmentBytes;
        attachmentCount += noteMetrics.attachmentCount;
        noteCount++;
      }
    } else {
      final notesSnapshot = await _firebaseFirestore
          .collection('notes')
          .where('userId', isEqualTo: userId)
          .where('isDeleted', isEqualTo: false)
          .get();
      for (final doc in notesSnapshot.docs) {
        final noteMetrics = await _noteStorageMetricsFromDynamic(
          doc.data(),
          userId: userId,
        );
        totalBytes += noteMetrics.contentBytes + noteMetrics.attachmentBytes;
        contentBytes += noteMetrics.contentBytes;
        attachmentBytes += noteMetrics.attachmentBytes;
        attachmentCount += noteMetrics.attachmentCount;
        noteCount++;
      }
    }

    return _StorageUsageTotals(
      totalBytes: totalBytes,
      contentBytes: contentBytes,
      attachmentBytes: attachmentBytes,
      noteCount: noteCount,
      attachmentCount: attachmentCount,
    );
  }

  Future<_NoteStorageMetrics> _noteStorageMetricsFromDynamic(
    Map<dynamic, dynamic> data, {
    required String userId,
  }) async {
    final explicitSize = _intFromDynamic(data['size']);
    final content = data['content'] as String? ?? '';
    var noteContentBytes = explicitSize ?? content.length;
    final attachmentMetrics = await _attachmentMetricsFromDynamic(
      data['attachments'],
      userId: userId,
    );

    final pdfPath = data['pdfPath'] as String?;
    if (noteContentBytes <= 0 && pdfPath != null && pdfPath.isNotEmpty) {
      noteContentBytes =
          await _remoteObjectBytes(userId: userId, path: pdfPath);
    }

    return _NoteStorageMetrics(
      contentBytes: noteContentBytes,
      attachmentBytes: attachmentMetrics.bytes,
      attachmentCount: attachmentMetrics.count,
    );
  }

  Future<_AttachmentMetrics> _attachmentMetricsFromDynamic(
    dynamic attachments, {
    required String userId,
  }) async {
    if (attachments is! List) {
      return const _AttachmentMetrics(bytes: 0, count: 0);
    }

    var total = 0;
    var count = 0;
    for (final attachment in attachments) {
      if (attachment is Map<String, dynamic>) {
        final storedSize = _intFromDynamic(attachment['size']) ?? 0;
        total += storedSize > 0
            ? storedSize
            : await _remoteObjectBytes(
                userId: userId,
                path: attachment['path'] as String? ?? '',
              );
        count++;
      } else if (attachment is Map) {
        final storedSize = _intFromDynamic(attachment['size']) ?? 0;
        total += storedSize > 0
            ? storedSize
            : await _remoteObjectBytes(
                userId: userId,
                path: attachment['path'] as String? ?? '',
              );
        count++;
      }
    }
    return _AttachmentMetrics(bytes: total, count: count);
  }

  Future<int> _remoteObjectBytes({
    required String userId,
    required String path,
  }) async {
    if (path.isEmpty || _isLikelyLocalPath(path)) {
      return 0;
    }

    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
        final objectPath = _storageObjectPathFromLocation(
          path,
          userId: userId,
        );
        if (objectPath == null || objectPath.isEmpty) {
          return 0;
        }
        return await _fetchLinuxObjectSize(objectPath);
      }

      if (path.startsWith('http://') ||
          path.startsWith('https://') ||
          path.startsWith('gs://')) {
        final metadata = await _firebaseStorage.refFromURL(path).getMetadata();
        return metadata.size ?? 0;
      }

      final normalizedPath =
          path.startsWith('users/') ? path : _storageObjectPath(userId, path);
      final metadata =
          await _firebaseStorage.ref().child(normalizedPath).getMetadata();
      return metadata.size ?? 0;
    } catch (_) {
      return 0;
    }
  }

  bool _isLikelyLocalPath(String path) {
    return path.startsWith('/') ||
        path.startsWith('file://') ||
        path.contains(':\\');
  }

  String? _storageObjectPathFromLocation(
    String path, {
    required String userId,
  }) {
    return resolveStorageObjectPath(path, userId: userId);
  }

  int? _intFromDynamic(dynamic value, {int? fallback}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  SubscriptionTier _subscriptionTierFromDynamic(
    dynamic value, {
    SubscriptionTier fallback = SubscriptionTier.free,
  }) {
    final tierIndex = _intFromDynamic(value);
    if (tierIndex == null ||
        tierIndex < 0 ||
        tierIndex >= SubscriptionTier.values.length) {
      return fallback;
    }
    return SubscriptionTier.values[tierIndex];
  }

  SubscriptionTier _subscriptionTierFromUserData(
    Map<dynamic, dynamic> data, {
    SubscriptionTier fallback = SubscriptionTier.free,
  }) {
    final planId = data['planId'];
    if (planId is String && planId.isNotEmpty) {
      return subscriptionTierFromPlanId(planId, fallback: fallback);
    }
    return _subscriptionTierFromDynamic(
      data['subscriptionTier'],
      fallback: fallback,
    );
  }

  bool get _shouldUseLinuxStorageRest =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

  bool get _shouldUseFunctionStorageUploads => true;

  String get _storageBucket {
    if (Firebase.apps.isNotEmpty) {
      return Firebase.app().options.storageBucket ??
          DefaultFirebaseOptions.currentPlatform.storageBucket ??
          '';
    }
    return DefaultFirebaseOptions.currentPlatform.storageBucket ?? '';
  }

  String _storageObjectPath(String userId, String path) =>
      'users/$userId/$path';

  Future<_AttachmentMetrics> _auditStorageUsageViaFunction(
    String userId,
  ) async {
    final idToken = await _idToken();
    final auditUri = _linuxFunctionUri('audit_storage_usage');

    final response = await _httpClient.post(
      auditUri,
      headers: {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode({'userId': userId}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractHttpError(response));
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final storageUsedBytes = _intFromDynamic(
          body['storageUsedBytes'],
          fallback: _storageUsedBytes,
        ) ??
        _storageUsedBytes;
    _applyRecordedUsage(storageUsedBytes);

    return _AttachmentMetrics(
      bytes: _intFromDynamic(
            body['storedFileBytes'],
            fallback: storageUsedBytes,
          ) ??
          storageUsedBytes,
      count: _intFromDynamic(body['storedFileCount']) ?? 0,
    );
  }

  Future<_FunctionUploadResult> _uploadDataViaFunction({
    required String userId,
    required String destinationPath,
    required List<int> data,
    String? contentType,
  }) async {
    final idToken = await _idToken();
    final uploadUri = _linuxFunctionUri('upload_storage_object');

    final response = await _httpClient.post(
      uploadUri,
      headers: {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode({
        'userId': userId,
        'destinationPath': destinationPath,
        'contentType': contentType ?? 'application/octet-stream',
        'dataBase64': base64Encode(data),
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractHttpError(response));
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final downloadUrl = body['downloadUrl'] as String?;
    if (downloadUrl == null || downloadUrl.isEmpty) {
      throw Exception('Upload succeeded without a download URL');
    }
    return _FunctionUploadResult(
      downloadUrl: downloadUrl,
      storageUsedBytes: _intFromDynamic(
            body['storageUsedBytes'],
            fallback: _storageUsedBytes,
          ) ??
          _storageUsedBytes,
    );
  }

  Future<int> _fetchLinuxObjectSize(String objectPath) async {
    final idToken = await _linuxIdToken();
    final uri = Uri.https(
      'firebasestorage.googleapis.com',
      '/v0/b/$_storageBucket/o/${Uri.encodeComponent(objectPath)}',
    );
    final response = await _httpClient.get(
      uri,
      headers: {'Authorization': 'Bearer $idToken'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractHttpError(response));
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final sizeValue = body['size'];
    if (sizeValue is int) return sizeValue;
    if (sizeValue is String) return int.tryParse(sizeValue) ?? 0;
    return 0;
  }

  Future<_FunctionDeleteResult> _deleteObjectViaFunction({
    required String userId,
    required String objectPath,
  }) async {
    final idToken = await _idToken();
    final deleteUri = _linuxFunctionUri('delete_storage_object');

    final response = await _httpClient.post(
      deleteUri,
      headers: {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode({
        'userId': userId,
        'objectPath': objectPath,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractHttpError(response));
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return _FunctionDeleteResult(
      storageUsedBytes: _intFromDynamic(
            body['storageUsedBytes'],
            fallback: _storageUsedBytes,
          ) ??
          _storageUsedBytes,
    );
  }

  String _buildDownloadUrl(String objectPath, {String? downloadToken}) {
    return Uri.https(
      'firebasestorage.googleapis.com',
      '/v0/b/$_storageBucket/o/${Uri.encodeComponent(objectPath)}',
      {
        'alt': 'media',
        if (downloadToken != null) 'token': downloadToken,
      },
    ).toString();
  }

  Uri _linuxFunctionUri(String functionName) {
    return Uri.https(
      'us-central1-${DefaultFirebaseOptions.currentPlatform.projectId}.cloudfunctions.net',
      functionName,
    );
  }

  Future<String> _linuxIdToken() async {
    if (!fd.FirebaseAuth.initialized) {
      throw Exception('Firedart auth is not initialized');
    }
    final auth = fd.FirebaseAuth.instance;
    if (!auth.isSignedIn) {
      throw Exception('No signed-in Linux user for storage upload');
    }
    return auth.tokenProvider.idToken;
  }

  Future<String> _idToken() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
      return _linuxIdToken();
    }

    final user = fb_auth.FirebaseAuth.instance.currentUser;
    final idToken = await user?.getIdToken();
    if (idToken == null || idToken.isEmpty) {
      throw Exception('No signed-in Firebase user for storage upload');
    }
    return idToken;
  }

  void _applyRecordedUsage(int storageUsedBytes) {
    _storageUsedBytes = storageUsedBytes;
    _cloudRecordedBytes = storageUsedBytes;
    _hasLoadedStorageInfo = true;
  }

  String _storageUsagePrefsKey(String userId) {
    return '$_storageUsagePrefsPrefix$userId';
  }

  Future<int?> _readCachedStorageUsage(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_storageUsagePrefsKey(userId));
    } catch (_) {
      return null;
    }
  }

  Future<void> _persistCachedStorageUsage(
    String userId,
    int storageUsedBytes,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_storageUsagePrefsKey(userId), storageUsedBytes);
    } catch (_) {
      // Missing this cache write should never interrupt storage operations.
    }
  }

  String _extractHttpError(http.Response response) {
    try {
      final json = jsonDecode(response.body);
      if (json is Map<String, dynamic>) {
        if (json['code'] == 'quota-exceeded') {
          final usedBytes = _intFromDynamic(json['usedBytes']);
          final requestedBytes = _intFromDynamic(json['requestedBytes']);
          final limitBytes = _intFromDynamic(json['limitBytes']);
          if (usedBytes != null &&
              requestedBytes != null &&
              limitBytes != null) {
            return 'Storage quota exceeded '
                '(${_formatBytes(usedBytes)} used, '
                '${_formatBytes(requestedBytes)} requested, '
                '${_formatBytes(limitBytes)} limit)';
          }
          return 'Storage quota exceeded';
        }
        final error = json['error'];
        if (error is Map<String, dynamic>) {
          final message = error['message'];
          if (message is String && message.isNotEmpty) {
            return 'HTTP ${response.statusCode}: $message';
          }
        }
      }
    } catch (_) {
      // Fall back to raw body.
    }
    if (response.body.isNotEmpty) {
      return 'HTTP ${response.statusCode}: ${response.body}';
    }
    return 'HTTP ${response.statusCode}';
  }

  String _describeStorageError(Object error) {
    if (error is FirebaseException) {
      final code = error.code.isEmpty ? 'unknown' : error.code;
      final message = error.message;
      return message == null || message.isEmpty
          ? 'Firebase error ($code)'
          : 'Firebase error ($code): $message';
    }
    return error.toString();
  }

  String _formatBytes(int bytes) {
    if (bytes < 1000) return '$bytes B';
    if (bytes < 1000 * 1000) return '${(bytes / 1000).toStringAsFixed(1)} KB';
    if (bytes < 1000 * 1000 * 1000) {
      return '${(bytes / (1000 * 1000)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1000 * 1000 * 1000)).toStringAsFixed(2)} GB';
  }

  // lazy Firebase Functions instance
  FirebaseFunctions? _functions;

  FirebaseFunctions get _cloudFunctions {
    try {
      _functions ??= FirebaseFunctions.instance;
      return _functions!;
    } catch (e) {
      debugPrint('Firebase Functions not available: $e');
      rethrow;
    }
  }

  /// Verify Gumroad License Key
  Future<bool> verifyLicenseKey(String userId, String key) async {
    _isLoading = true;
    notifyListeners();

    try {
      final result = await _cloudFunctions
          .httpsCallable('verify_gumroad_license')
          .call<Map<String, dynamic>>({
        'license_key': key,
      });

      final data = result.data;
      if (data['success'] == true) {
        // Reload storage info to get updated tier
        await loadStorageInfo(userId);
        _errorMessage = null;
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _errorMessage = data['message'] as String? ?? 'Invalid license key';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = 'Verification failed: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Verify Patreon Subscription
  Future<bool> verifyPatreon(String userId) async {
    _isLoading = true;
    notifyListeners();

    try {
      final result = await _cloudFunctions
          .httpsCallable('check_patreon_subscription')
          .call<Map<String, dynamic>>();

      final data = result.data;
      if (data['success'] == true) {
        await loadStorageInfo(userId);
        _errorMessage = null;
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _errorMessage = data['message'] as String? ?? 'Verification failed';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = 'Patreon check failed: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
}

class _AttachmentMetrics {
  final int bytes;
  final int count;

  const _AttachmentMetrics({
    required this.bytes,
    required this.count,
  });
}

class _UserStorageSnapshot {
  final SubscriptionTier tier;
  final int recordedBytes;

  const _UserStorageSnapshot({
    required this.tier,
    required this.recordedBytes,
  });
}

class _StorageUsageTotals {
  final int totalBytes;
  final int contentBytes;
  final int attachmentBytes;
  final int noteCount;
  final int attachmentCount;

  const _StorageUsageTotals({
    required this.totalBytes,
    required this.contentBytes,
    required this.attachmentBytes,
    required this.noteCount,
    required this.attachmentCount,
  });
}

class _FunctionUploadResult {
  final String downloadUrl;
  final int storageUsedBytes;

  const _FunctionUploadResult({
    required this.downloadUrl,
    required this.storageUsedBytes,
  });
}

class _FunctionDeleteResult {
  final int storageUsedBytes;

  const _FunctionDeleteResult({
    required this.storageUsedBytes,
  });
}

class _NoteStorageMetrics {
  final int contentBytes;
  final int attachmentBytes;
  final int attachmentCount;

  const _NoteStorageMetrics({
    required this.contentBytes,
    required this.attachmentBytes,
    required this.attachmentCount,
  });
}

/// Information about a subscription plan
class SubscriptionInfo {
  final SubscriptionTier tier;
  final String name;
  final String storage;
  final double priceEuros;
  final List<String> features;
  final bool isRecommended;

  const SubscriptionInfo({
    required this.tier,
    required this.name,
    required this.storage,
    required this.priceEuros,
    required this.features,
    this.isRecommended = false,
  });

  String get priceFormatted =>
      priceEuros == 0 ? 'Free' : '€${priceEuros.toStringAsFixed(2)}/month';
}
