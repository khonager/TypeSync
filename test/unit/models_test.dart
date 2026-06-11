/// Model Unit Tests
///
/// Tests for data models to ensure correct serialization and behavior.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:typesync/core/models/folder.dart';
import 'package:typesync/core/models/note.dart';
import 'package:typesync/core/services/data_repair_service.dart';
import 'package:typesync/core/models/user.dart';

void main() {
  group('User Model', () {
    test('storage limit returns correct values for each tier', () {
      expect(SubscriptionTier.free.storageLimitBytes, 5 * 1024 * 1024);
      expect(SubscriptionTier.basic.storageLimitBytes, 1 * 1024 * 1024 * 1024);
      expect(
        SubscriptionTier.standard.storageLimitBytes,
        25 * 1024 * 1024 * 1024,
      );
      expect(
        SubscriptionTier.premium.storageLimitBytes,
        100 * 1024 * 1024 * 1024,
      );
    });

    test('price returns correct values for each tier', () {
      expect(SubscriptionTier.free.priceEuros, 0.0);
      expect(SubscriptionTier.basic.priceEuros, 2.99);
      expect(SubscriptionTier.standard.priceEuros, 5.99);
      expect(SubscriptionTier.premium.priceEuros, 11.99);
    });

    test('legacy enum values map to new plan ids', () {
      expect(SubscriptionTier.free.planId, 'free');
      expect(SubscriptionTier.basic.planId, 'TypeSync Lite');
      expect(SubscriptionTier.standard.planId, 'plus');
      expect(SubscriptionTier.premium.planId, 'pro');
      expect(
        subscriptionTierFromPlanId('TypeSync Lite'),
        SubscriptionTier.basic,
      );
      expect(subscriptionTierFromPlanId('light'), SubscriptionTier.basic);
      expect(subscriptionTierFromPlanId('plus'), SubscriptionTier.standard);
      expect(subscriptionTierFromPlanId('pro'), SubscriptionTier.premium);
    });

    test('User.isStorageFull returns correct value', () {
      final userNotFull = User(
        id: 'test',
        email: 'test@test.com',
        createdAt: DateTime.now(),
        storageUsedBytes: 4 * 1024 * 1024,
        subscriptionTier: SubscriptionTier.free,
      );
      expect(userNotFull.isStorageFull, isFalse);

      final userFull = User(
        id: 'test',
        email: 'test@test.com',
        createdAt: DateTime.now(),
        storageUsedBytes: 5 * 1024 * 1024,
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

  group('Folder Model', () {
    test('copyWith can clear nullable fields', () {
      final original = Folder(
        id: 'folder-1',
        name: 'School',
        subtitle: 'Notes',
        parentId: 'parent-1',
        backgroundColor: '#ffffff',
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 1, 1),
        userId: 'user-1',
      );

      final updated = original.copyWith(
        subtitle: null,
        parentId: null,
        backgroundColor: null,
      );

      expect(updated.subtitle, isNull);
      expect(updated.parentId, isNull);
      expect(updated.backgroundColor, isNull);
    });
  });

  group('Data Repair Service', () {
    test('detects and describes legacy folder and note repairs', () {
      final folder = Folder(
        id: 'folder-1',
        name: 'Legacy Folder',
        subtitle: '   ',
        backgroundColor: 'blue',
        icon: '',
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 1, 1),
        userId: 'old-user',
      );

      final note = Note(
        id: 'note-1',
        title: 'Legacy Note',
        content: 'Hello',
        folderId: 'missing-folder',
        backgroundColor: ' ',
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 1, 1),
        userId: 'old-user',
      );

      final service = DataRepairService();
      final plan = service.buildRepairPlanFromItems(
        currentUserId: 'user-1',
        folders: [folder],
        notes: [note],
      );

      expect(plan.folders, hasLength(1));
      expect(plan.notes, hasLength(1));
      expect(
        plan.folders.single.changes,
        containsAll([
          'clear empty subtitle',
          'restore missing folder icon',
          'clear invalid folder color',
          'assign to your account',
        ]),
      );
      expect(
        plan.notes.single.changes,
        containsAll([
          'remove missing folder link',
          'clear invalid note color',
          'assign to your account',
        ]),
      );
      expect(plan.folders.single.repairedFolder?.icon, 'folder');
      expect(plan.folders.single.repairedFolder?.backgroundColor, isNull);
      expect(plan.notes.single.repairedNote?.folderId, isNull);
    });
  });
}
