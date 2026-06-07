/// User Model
library;

///
/// Represents a TypeSync user with profile information,
/// subscription status, and storage quota.

import 'package:equatable/equatable.dart';

/// Subscription tier enum
///
/// Defines the available storage plans:
/// - free: small cloud quota for trial use
/// - basic: TypeSync Lite plan
/// - standard: Plus plan
/// - premium: Pro plan
///
/// The enum order is intentionally preserved for legacy Firestore documents.
enum SubscriptionTier {
  free,
  basic,
  standard,
  premium,
}

/// Extension to get storage limits and prices for each tier
extension SubscriptionTierExtension on SubscriptionTier {
  /// Storage limit in bytes
  int get storageLimitBytes {
    switch (this) {
      case SubscriptionTier.free:
        return 5 * 1024 * 1024; // 5 MB
      case SubscriptionTier.basic:
        return 1 * 1024 * 1024 * 1024; // 1 GB
      case SubscriptionTier.standard:
        return 25 * 1024 * 1024 * 1024; // 25 GB
      case SubscriptionTier.premium:
        return 100 * 1024 * 1024 * 1024; // 100 GB
    }
  }

  /// Storage limit formatted as string
  String get storageLimitFormatted {
    switch (this) {
      case SubscriptionTier.free:
        return '5 MB';
      case SubscriptionTier.basic:
        return '1 GB';
      case SubscriptionTier.standard:
        return '25 GB';
      case SubscriptionTier.premium:
        return '100 GB';
    }
  }

  /// Monthly price in euros
  double get priceEuros {
    switch (this) {
      case SubscriptionTier.free:
        return 0.0;
      case SubscriptionTier.basic:
        return 2.99;
      case SubscriptionTier.standard:
        return 5.99;
      case SubscriptionTier.premium:
        return 11.99;
    }
  }

  /// Display name for the tier
  String get displayName {
    switch (this) {
      case SubscriptionTier.free:
        return 'Free';
      case SubscriptionTier.basic:
        return 'TypeSync Lite';
      case SubscriptionTier.standard:
        return 'Plus';
      case SubscriptionTier.premium:
        return 'Pro';
    }
  }

  /// Stable plan id used by RevenueCat and backend entitlement documents.
  String get planId {
    switch (this) {
      case SubscriptionTier.free:
        return 'free';
      case SubscriptionTier.basic:
        return 'TypeSync Lite';
      case SubscriptionTier.standard:
        return 'plus';
      case SubscriptionTier.premium:
        return 'pro';
    }
  }

  /// RevenueCat entitlement id for paid plans.
  String? get revenueCatEntitlementId =>
      this == SubscriptionTier.free ? null : planId;

  /// RevenueCat monthly product id for paid plans.
  String? get revenueCatProductId {
    switch (this) {
      case SubscriptionTier.free:
        return null;
      case SubscriptionTier.basic:
        return 'monthly';
      case SubscriptionTier.standard:
        return 'typesync_plus_monthly';
      case SubscriptionTier.premium:
        return 'typesync_pro_monthly';
    }
  }
}

/// Looks up a subscription tier from a stable plan id.
SubscriptionTier subscriptionTierFromPlanId(
  String? planId, {
  SubscriptionTier fallback = SubscriptionTier.free,
}) {
  switch (planId) {
    case 'free':
      return SubscriptionTier.free;
    case 'TypeSync Lite':
    case 'light':
      return SubscriptionTier.basic;
    case 'plus':
      return SubscriptionTier.standard;
    case 'pro':
      return SubscriptionTier.premium;
    default:
      return fallback;
  }
}

/// User model with profile and subscription info
class User extends Equatable {
  /// Firebase user ID
  final String id;

  /// User email address
  final String email;

  /// Display name
  final String? displayName;

  /// Profile picture URL
  final String? photoUrl;

  /// Current subscription tier
  final SubscriptionTier subscriptionTier;

  /// Current storage used in bytes
  final int storageUsedBytes;

  /// Account creation date
  final DateTime createdAt;

  /// Last sign in date
  final DateTime? lastSignIn;

  /// Whether email is verified
  final bool emailVerified;

  /// Subscription expiry date (null for free tier)
  final DateTime? subscriptionExpiresAt;

  const User({
    required this.id,
    required this.email,
    required this.createdAt,
    this.displayName,
    this.photoUrl,
    this.subscriptionTier = SubscriptionTier.free,
    this.storageUsedBytes = 0,
    this.lastSignIn,
    this.emailVerified = false,
    this.subscriptionExpiresAt,
  });

  /// Checks if user has exceeded their storage limit
  bool get isStorageFull =>
      storageUsedBytes >= subscriptionTier.storageLimitBytes;

  /// Gets remaining storage in bytes
  int get storageRemainingBytes =>
      subscriptionTier.storageLimitBytes - storageUsedBytes;

  /// Gets storage usage percentage (0.0 to 1.0)
  double get storageUsagePercent =>
      storageUsedBytes / subscriptionTier.storageLimitBytes;

  /// Formats storage used as human-readable string
  String get storageUsedFormatted => _formatBytes(storageUsedBytes);

  /// Formats storage remaining as human-readable string
  String get storageRemainingFormatted => _formatBytes(storageRemainingBytes);

  /// Helper to format bytes as human-readable
  static String _formatBytes(int bytes) {
    if (bytes < 1000) return '$bytes B';
    if (bytes < 1000 * 1000) return '${(bytes / 1000).toStringAsFixed(1)} KB';
    if (bytes < 1000 * 1000 * 1000) {
      return '${(bytes / (1000 * 1000)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1000 * 1000 * 1000)).toStringAsFixed(2)} GB';
  }

  /// Creates a copy with updated fields
  User copyWith({
    String? id,
    String? email,
    String? displayName,
    String? photoUrl,
    SubscriptionTier? subscriptionTier,
    int? storageUsedBytes,
    DateTime? createdAt,
    DateTime? lastSignIn,
    bool? emailVerified,
    DateTime? subscriptionExpiresAt,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      subscriptionTier: subscriptionTier ?? this.subscriptionTier,
      storageUsedBytes: storageUsedBytes ?? this.storageUsedBytes,
      createdAt: createdAt ?? this.createdAt,
      lastSignIn: lastSignIn ?? this.lastSignIn,
      emailVerified: emailVerified ?? this.emailVerified,
      subscriptionExpiresAt:
          subscriptionExpiresAt ?? this.subscriptionExpiresAt,
    );
  }

  /// Converts to JSON for Firebase
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'subscriptionTier': subscriptionTier.index,
      'planId': subscriptionTier.planId,
      'storageUsedBytes': storageUsedBytes,
      'createdAt': createdAt.toIso8601String(),
      'lastSignIn': lastSignIn?.toIso8601String(),
      'emailVerified': emailVerified,
      'subscriptionExpiresAt': subscriptionExpiresAt?.toIso8601String(),
    };
  }

  /// Creates from JSON (Firebase)
  factory User.fromJson(Map<String, dynamic> json) {
    final tierIndex = json['subscriptionTier'] as int?;
    final legacyTier = tierIndex == null ||
            tierIndex < 0 ||
            tierIndex >= SubscriptionTier.values.length
        ? SubscriptionTier.free
        : SubscriptionTier.values[tierIndex];

    return User(
      id: json['id'] as String,
      email: json['email'] as String,
      displayName: json['displayName'] as String?,
      photoUrl: json['photoUrl'] as String?,
      subscriptionTier: subscriptionTierFromPlanId(
        json['planId'] as String?,
        fallback: legacyTier,
      ),
      storageUsedBytes: json['storageUsedBytes'] as int? ?? 0,
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastSignIn: json['lastSignIn'] != null
          ? DateTime.parse(json['lastSignIn'] as String)
          : null,
      emailVerified: json['emailVerified'] as bool? ?? false,
      subscriptionExpiresAt: json['subscriptionExpiresAt'] != null
          ? DateTime.parse(json['subscriptionExpiresAt'] as String)
          : null,
    );
  }

  @override
  List<Object?> get props => [
        id,
        email,
        displayName,
        photoUrl,
        subscriptionTier,
        storageUsedBytes,
        createdAt,
        lastSignIn,
        emailVerified,
        subscriptionExpiresAt,
      ];
}
