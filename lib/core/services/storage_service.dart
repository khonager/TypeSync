/// Storage Service
///
/// Manages cloud storage quota and subscription tiers.
/// Handles file uploads to Firebase Storage with size tracking.
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firedart/firedart.dart' as fd;
import 'package:http/http.dart' as http;

import '../models/user.dart';
import '../../firebase_options.dart';
import 'diagnostics_service.dart';

/// Service for managing cloud storage and subscriptions
///
/// Tracks storage usage against subscription limits and handles
/// file upload/download operations to Firebase Storage.
class StorageService extends ChangeNotifier {
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
  bool _isLoading = false;
  String? _errorMessage;

  // ===========================================
  // GETTERS
  // ===========================================

  SubscriptionTier get currentTier => _currentTier;
  int get storageUsedBytes => _storageUsedBytes;
  int get storageLimitBytes => _currentTier.storageLimitBytes;
  double get usagePercent => _storageUsedBytes / storageLimitBytes;
  int get storageRemainingBytes => storageLimitBytes - _storageUsedBytes;
  bool get isStorageFull => _storageUsedBytes >= storageLimitBytes;
  bool get isLoading => _isLoading;
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
          storage: '1 GB',
          priceEuros: 0,
          features: ['Basic sync', '1 GB storage', 'All core features'],
        ),
        const SubscriptionInfo(
          tier: SubscriptionTier.basic,
          name: 'Basic',
          storage: '5 GB',
          priceEuros: 1.99,
          features: ['Everything in Free', '5 GB storage', 'Priority sync'],
        ),
        const SubscriptionInfo(
          tier: SubscriptionTier.standard,
          name: 'Standard',
          storage: '50 GB',
          priceEuros: 4.99,
          features: [
            'Everything in Basic',
            '50 GB storage',
            'Advanced features',
          ],
        ),
        const SubscriptionInfo(
          tier: SubscriptionTier.premium,
          name: 'Premium',
          storage: '200 GB',
          priceEuros: 9.99,
          features: [
            'Everything in Standard',
            '200 GB storage',
            'Priority support',
          ],
        ),
      ];

  // ===========================================
  // PUBLIC METHODS
  // ===========================================

  /// Load storage info for a user
  ///
  /// Calculates actual storage usage from cloud-synced documents.
  Future<void> loadStorageInfo(String userId) async {
    _isLoading = true;
    notifyListeners();

    try {
      int totalBytes = 0;
      var recordedBytes = 0;

      // Load subscription tier and calculate storage from cloud
      if (defaultTargetPlatform == TargetPlatform.linux && !kIsWeb) {
        final fdFirestore = _firedartFirestore;
        if (fdFirestore != null) {
          // 1. Get user document for subscription tier
          final userDoc =
              await fdFirestore.collection('users').document(userId).get();
          if (userDoc.map.isNotEmpty) {
            _currentTier = SubscriptionTier
                .values[userDoc.map['subscriptionTier'] as int? ?? 0];
            recordedBytes = userDoc.map['storageUsedBytes'] as int? ?? 0;
          }

          // 2. Sum up sizes of all notes from Firedart
          final notes = await fdFirestore.collection('notes').get();
          for (final doc in notes) {
            if (doc.map['userId'] == userId && doc.map['isDeleted'] == false) {
              final explicitSize = doc.map['size'] as int?;
              final content = doc.map['content'] as String? ?? '';
              totalBytes += explicitSize ?? content.length;
              totalBytes += _attachmentBytesFromDynamic(doc.map['attachments']);
            }
          }
        }
      } else {
        // 1. Get user document for subscription tier
        final userDoc =
            await _firebaseFirestore.collection('users').doc(userId).get();
        if (userDoc.exists) {
          final data = userDoc.data()!;
          _currentTier =
              SubscriptionTier.values[data['subscriptionTier'] as int? ?? 0];
          recordedBytes = data['storageUsedBytes'] as int? ?? 0;
        }

        // 2. Sum up sizes of all notes from Firestore
        final notesSnapshot = await _firebaseFirestore
            .collection('notes')
            .where('userId', isEqualTo: userId)
            .where('isDeleted', isEqualTo: false)
            .get();
        for (final doc in notesSnapshot.docs) {
          final data = doc.data();
          final explicitSize = data['size'] as int?;
          final content = data['content'] as String? ?? '';
          totalBytes += explicitSize ?? content.length;
          totalBytes += _attachmentBytesFromDynamic(data['attachments']);
        }
      }

      _storageUsedBytes = totalBytes > recordedBytes
          ? totalBytes
          : recordedBytes;
      _errorMessage = null;
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

    // Check if upload would exceed quota
    if (_storageUsedBytes + fileSize > storageLimitBytes) {
      _errorMessage =
          'Storage quota exceeded. Upgrade your plan for more space.';
      _diagnostics.warning(
        'StorageService',
        'Upload blocked by quota for users/$userId/$destinationPath '
            '(${_formatBytes(fileSize)} requested, $usageFormatted used)',
      );
      notifyListeners();
      return null;
    }

    _isLoading = true;
    notifyListeners();

    try {
      if (_shouldUseLinuxStorageRest) {
        final downloadUrl = await _uploadDataLinux(
          userId: userId,
          destinationPath: destinationPath,
          data: await file.readAsBytes(),
          contentType: contentType,
        );
        await _incrementStorageUsage(userId, fileSize);
        _errorMessage = null;
        _isLoading = false;
        _diagnostics.info(
          'StorageService',
          'Uploaded users/$userId/$destinationPath (${_formatBytes(fileSize)})',
        );
        notifyListeners();
        return downloadUrl;
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

    if (_storageUsedBytes + fileSize > storageLimitBytes) {
      _errorMessage =
          'Storage quota exceeded. Upgrade your plan for more space.';
      _diagnostics.warning(
        'StorageService',
        'Byte upload blocked by quota for users/$userId/$destinationPath '
            '(${_formatBytes(fileSize)} requested, $usageFormatted used)',
      );
      notifyListeners();
      return null;
    }

    _isLoading = true;
    notifyListeners();

    try {
      if (_shouldUseLinuxStorageRest) {
        final downloadUrl = await _uploadDataLinux(
          userId: userId,
          destinationPath: destinationPath,
          data: data,
          contentType: contentType,
        );
        await _incrementStorageUsage(userId, fileSize);
        _errorMessage = null;
        _isLoading = false;
        _diagnostics.info(
          'StorageService',
          'Uploaded users/$userId/$destinationPath (${_formatBytes(fileSize)})',
        );
        notifyListeners();
        return downloadUrl;
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
      if (_shouldUseLinuxStorageRest) {
        final fileSize = await _fetchLinuxObjectSize(
          _storageObjectPath(userId, filePath),
        );
        await _deleteLinuxObject(_storageObjectPath(userId, filePath));
        _storageUsedBytes =
            (_storageUsedBytes - fileSize).clamp(0, storageLimitBytes);
        await _writeStorageUsage(userId);
        notifyListeners();
        return true;
      }

      final ref = _firebaseStorage.ref().child('users/$userId/$filePath');

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
  /// Note: In production, this would integrate with a payment provider
  /// like Stripe or Google Play Billing.
  Future<bool> upgradeSubscription(
    String userId,
    SubscriptionTier newTier,
  ) async {
    _isLoading = true;
    notifyListeners();

    try {
      // TODO: Integrate with payment provider
      // For now, just update the tier in Firestore

      if (defaultTargetPlatform == TargetPlatform.linux && !kIsWeb) {
        final fdFirestore = _firedartFirestore;
        if (fdFirestore != null) {
          await fdFirestore.collection('users').document(userId).update({
            'subscriptionTier': newTier.index,
            'subscriptionExpiresAt':
                DateTime.now().add(const Duration(days: 30)).toIso8601String(),
          });
        }
      } else {
        await _firebaseFirestore.collection('users').doc(userId).update({
          'subscriptionTier': newTier.index,
          'subscriptionExpiresAt':
              DateTime.now().add(const Duration(days: 30)).toIso8601String(),
        });
      }

      _currentTier = newTier;
      _errorMessage = null;
      _isLoading = false;
      notifyListeners();

      return true;
    } catch (e) {
      _errorMessage = 'Failed to upgrade subscription';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Calculate total storage used by recalculating from Firestore note sizes
  Future<void> recalculateStorage(String userId) async {
    _isLoading = true;
    notifyListeners();

    try {
      int totalBytes = 0;

      if (defaultTargetPlatform == TargetPlatform.linux && !kIsWeb) {
        final fdFirestore = _firedartFirestore;
        if (fdFirestore != null) {
          final notes = await fdFirestore.collection('notes').get();
          for (final doc in notes) {
            if (doc.map['userId'] == userId && doc.map['isDeleted'] == false) {
              final explicitSize = doc.map['size'] as int?;
              final content = doc.map['content'] as String? ?? '';
              totalBytes += explicitSize ?? content.length;
              totalBytes += _attachmentBytesFromDynamic(doc.map['attachments']);
            }
          }

          await fdFirestore.collection('users').document(userId).update({
            'storageUsedBytes': totalBytes,
          });
        }
      } else {
        final notesSnapshot = await _firebaseFirestore
            .collection('notes')
            .where('userId', isEqualTo: userId)
            .where('isDeleted', isEqualTo: false)
            .get();
        for (final doc in notesSnapshot.docs) {
          final data = doc.data();
          final explicitSize = data['size'] as int?;
          final content = data['content'] as String? ?? '';
          totalBytes += explicitSize ?? content.length;
          totalBytes += _attachmentBytesFromDynamic(data['attachments']);
        }

        await _firebaseFirestore.collection('users').doc(userId).update({
          'storageUsedBytes': totalBytes,
        });
      }

      _storageUsedBytes = totalBytes;
      _errorMessage = null;
    } catch (e) {
      _errorMessage = 'Failed to recalculate storage: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  // ===========================================
  // PRIVATE METHODS
  // ===========================================

  int _attachmentBytesFromDynamic(dynamic attachments) {
    if (attachments is! List) return 0;

    var total = 0;
    for (final attachment in attachments) {
      if (attachment is Map<String, dynamic>) {
        total += attachment['size'] as int? ?? 0;
      } else if (attachment is Map) {
        final size = attachment['size'];
        if (size is int) {
          total += size;
        }
      }
    }
    return total;
  }

  bool get _shouldUseLinuxStorageRest =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

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

  Future<String> _uploadDataLinux({
    required String userId,
    required String destinationPath,
    required List<int> data,
    String? contentType,
  }) async {
    final idToken = await _linuxIdToken();
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
    return downloadUrl;
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

  Future<void> _deleteLinuxObject(String objectPath) async {
    final idToken = await _linuxIdToken();
    final uri = Uri.https(
      'firebasestorage.googleapis.com',
      '/v0/b/$_storageBucket/o/${Uri.encodeComponent(objectPath)}',
    );
    final response = await _httpClient.delete(
      uri,
      headers: {'Authorization': 'Bearer $idToken'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractHttpError(response));
    }
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

  Future<void> _incrementStorageUsage(String userId, int fileSize) async {
    _storageUsedBytes += fileSize;
    await _writeStorageUsage(userId);
  }

  Future<void> _writeStorageUsage(String userId) async {
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
  }

  String _extractHttpError(http.Response response) {
    try {
      final json = jsonDecode(response.body);
      if (json is Map<String, dynamic>) {
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

/// Information about a subscription plan
class SubscriptionInfo {
  final SubscriptionTier tier;
  final String name;
  final String storage;
  final double priceEuros;
  final List<String> features;

  const SubscriptionInfo({
    required this.tier,
    required this.name,
    required this.storage,
    required this.priceEuros,
    required this.features,
  });

  String get priceFormatted =>
      priceEuros == 0 ? 'Free' : '€${priceEuros.toStringAsFixed(2)}/month';
}
