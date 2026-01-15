/// Storage Service
///
/// Manages cloud storage quota and subscription tiers.
/// Handles file uploads to Firebase Storage with size tracking.
library;

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../models/user.dart';

/// Service for managing cloud storage and subscriptions
///
/// Tracks storage usage against subscription limits and handles
/// file upload/download operations to Firebase Storage.
class StorageService extends ChangeNotifier {
  // Lazy Firebase instances
  FirebaseStorage? _storage;
  FirebaseFirestore? _firestore;

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
  Future<void> loadStorageInfo(String userId) async {
    _isLoading = true;
    notifyListeners();

    try {
      final doc =
          await _firebaseFirestore.collection('users').doc(userId).get();

      if (doc.exists) {
        final data = doc.data()!;
        _currentTier =
            SubscriptionTier.values[data['subscriptionTier'] as int? ?? 0];
        _storageUsedBytes = data['storageUsedBytes'] as int? ?? 0;
      }

      _errorMessage = null;
    } catch (e) {
      _errorMessage = 'Failed to load storage info';
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
  }) async {
    final file = File(filePath);
    final fileSize = await file.length();

    // Check if upload would exceed quota
    if (_storageUsedBytes + fileSize > storageLimitBytes) {
      _errorMessage =
          'Storage quota exceeded. Upgrade your plan for more space.';
      notifyListeners();
      return null;
    }

    _isLoading = true;
    notifyListeners();

    try {
      // Upload to Firebase Storage
      final ref =
          _firebaseStorage.ref().child('users/$userId/$destinationPath');
      final uploadTask = ref.putFile(file);

      // Wait for upload to complete
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      // Update storage usage in Firestore
      _storageUsedBytes += fileSize;
      await _firebaseFirestore.collection('users').doc(userId).update({
        'storageUsedBytes': _storageUsedBytes,
      });

      _errorMessage = null;
      _isLoading = false;
      notifyListeners();

      return downloadUrl;
    } catch (e) {
      _errorMessage = 'Failed to upload file';
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
      final ref = _firebaseStorage.ref().child('users/$userId/$filePath');

      // Get file size before deleting
      final metadata = await ref.getMetadata();
      final fileSize = metadata.size ?? 0;

      await ref.delete();

      // Update storage usage
      _storageUsedBytes =
          (_storageUsedBytes - fileSize).clamp(0, storageLimitBytes);
      await _firebaseFirestore.collection('users').doc(userId).update({
        'storageUsedBytes': _storageUsedBytes,
      });

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

      await _firebaseFirestore.collection('users').doc(userId).update({
        'subscriptionTier': newTier.index,
        'subscriptionExpiresAt':
            DateTime.now().add(const Duration(days: 30)).toIso8601String(),
      });

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

  /// Calculate total storage used by recalculating from Firebase Storage
  Future<void> recalculateStorage(String userId) async {
    _isLoading = true;
    notifyListeners();

    try {
      final ref = _firebaseStorage.ref().child('users/$userId');
      final result = await ref.listAll();

      int totalSize = 0;
      for (final item in result.items) {
        final metadata = await item.getMetadata();
        totalSize += metadata.size ?? 0;
      }

      _storageUsedBytes = totalSize;
      await _firebaseFirestore.collection('users').doc(userId).update({
        'storageUsedBytes': totalSize,
      });

      _errorMessage = null;
    } catch (e) {
      _errorMessage = 'Failed to recalculate storage';
    }

    _isLoading = false;
    notifyListeners();
  }

  // ===========================================
  // PRIVATE METHODS
  // ===========================================

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
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
        _errorMessage = data['message'] ?? 'Invalid license key';
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
        _errorMessage = data['message'] ?? 'Verification failed';
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
