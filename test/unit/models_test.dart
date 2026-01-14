/// Model Unit Tests
///
/// Tests for data models to ensure correct serialization and behavior.

import 'package:flutter_test/flutter_test.dart';
import 'package:typesync/core/models/user.dart';

void main() {
  group('User Model', () {
    test('storage limit returns correct values for each tier', () {
      expect(SubscriptionTier.free.storageLimitBytes, 1 * 1024 * 1024 * 1024);
      expect(SubscriptionTier.basic.storageLimitBytes, 5 * 1024 * 1024 * 1024);
      expect(
          SubscriptionTier.standard.storageLimitBytes, 50 * 1024 * 1024 * 1024);
      expect(
          SubscriptionTier.premium.storageLimitBytes, 200 * 1024 * 1024 * 1024);
    });

    test('price returns correct values for each tier', () {
      expect(SubscriptionTier.free.priceEuros, 0.0);
      expect(SubscriptionTier.basic.priceEuros, 1.99);
      expect(SubscriptionTier.standard.priceEuros, 4.99);
      expect(SubscriptionTier.premium.priceEuros, 9.99);
    });

    test('User.isStorageFull returns correct value', () {
      final userNotFull = User(
        id: 'test',
        email: 'test@test.com',
        createdAt: DateTime.now(),
        storageUsedBytes: 500 * 1024 * 1024, // 500 MB
        subscriptionTier: SubscriptionTier.free,
      );
      expect(userNotFull.isStorageFull, isFalse);

      final userFull = User(
        id: 'test',
        email: 'test@test.com',
        createdAt: DateTime.now(),
        storageUsedBytes: 1024 * 1024 * 1024, // 1 GB (full for free tier)
        subscriptionTier: SubscriptionTier.free,
      );
      expect(userFull.isStorageFull, isTrue);
    });

    test('User.toJson and fromJson round trip', () {
      final original = User(
        id: 'test-id',
        email: 'test@example.com',
        displayName: 'Test User',
        subscriptionTier: SubscriptionTier.basic,
        storageUsedBytes: 1000000,
        createdAt: DateTime(2024, 1, 15),
        emailVerified: true,
      );

      final json = original.toJson();
      final restored = User.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.email, original.email);
      expect(restored.displayName, original.displayName);
      expect(restored.subscriptionTier, original.subscriptionTier);
      expect(restored.storageUsedBytes, original.storageUsedBytes);
      expect(restored.emailVerified, original.emailVerified);
    });
  });
}

