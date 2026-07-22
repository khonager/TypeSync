library;

import 'package:flutter_test/flutter_test.dart';
import 'package:typesync/core/models/user.dart';
import 'package:typesync/core/services/billing_service.dart';
import 'package:typesync/core/services/storage_service.dart';

void main() {
  group('BillingService', () {
    test('maps active RevenueCat entitlements to the highest TypeSync plan',
        () {
      expect(
        BillingService.tierFromActiveEntitlements(const []),
        SubscriptionTier.free,
      );
      expect(
        BillingService.tierFromActiveEntitlements(const ['TypeSync Lite']),
        SubscriptionTier.basic,
      );
      expect(
        BillingService.tierFromActiveEntitlements(const ['light']),
        SubscriptionTier.basic,
      );
      expect(
        BillingService.tierFromActiveEntitlements(
          const ['TypeSync Lite', 'plus'],
        ),
        SubscriptionTier.standard,
      );
      expect(
        BillingService.tierFromActiveEntitlements(
          const ['TypeSync Lite', 'pro'],
        ),
        SubscriptionTier.premium,
      );
    });

    test('subscription plan list exposes monthly launch prices and storage',
        () {
      final paidPlans = StorageService.subscriptionPlans
          .where((plan) => plan.tier != SubscriptionTier.free)
          .toList();

      expect(
        paidPlans.map((plan) => plan.tier.planId),
        ['TypeSync Lite', 'plus', 'pro'],
      );
      expect(
        paidPlans.map((plan) => plan.priceEuros),
        [2.99, 5.99, 11.99],
      );
      expect(
        paidPlans.map((plan) => plan.tier.revenueCatProductId),
        ['monthly', 'typesync_plus_monthly', 'typesync_pro_monthly'],
      );
      expect(
          paidPlans.map((plan) => plan.name), ['TypeSync Lite', 'Plus', 'Pro']);
    });
  });
}
