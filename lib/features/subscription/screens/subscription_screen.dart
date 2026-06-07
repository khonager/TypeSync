/// Subscription Screen
///
/// TypeSync plan management and RevenueCat purchase entry points.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/user.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/billing_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/widgets/desktop_window_frame.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  String? _configuredUserId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.read<AuthService>();
    final billing = context.read<BillingService>();
    final userId = auth.userId;
    if (userId != _configuredUserId) {
      _configuredUserId = userId;
      unawaited(billing.configureForUser(userId));
    }
  }

  Future<void> _refreshEntitlements() async {
    final billing = context.read<BillingService>();
    final storage = context.read<StorageService>();
    final auth = context.read<AuthService>();
    await billing.refreshCustomerInfo();
    final userId = auth.userId;
    if (userId != null) {
      await storage.loadStorageInfo(userId, fallbackUser: auth.currentUser);
    }
  }

  Future<void> _purchase(SubscriptionInfo plan) async {
    final billing = context.read<BillingService>();
    final storage = context.read<StorageService>();
    final auth = context.read<AuthService>();
    final messenger = ScaffoldMessenger.of(context);

    if (!auth.isLoggedIn) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Sign in to choose a cloud plan.')),
      );
      return;
    }

    final result = plan.tier == SubscriptionTier.basic
        ? await billing.presentLitePaywall(userId: auth.userId)
        : await billing.purchasePlan(plan, userId: auth.userId);
    if (!mounted) return;

    switch (result) {
      case BillingActionResult.completed:
        messenger.showSnackBar(
          const SnackBar(content: Text('Purchase confirmed. Syncing plan...')),
        );
        await storage.loadStorageInfo(
          auth.userId!,
          fallbackUser: auth.currentUser,
        );
        break;
      case BillingActionResult.openedExternal:
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Complete checkout in the browser, then refresh.'),
          ),
        );
        break;
      case BillingActionResult.notConfigured:
      case BillingActionResult.unavailable:
      case BillingActionResult.failed:
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              billing.errorMessage ?? 'This purchase option is not ready yet.',
            ),
            backgroundColor: Colors.red,
          ),
        );
        break;
      case BillingActionResult.canceled:
        break;
      case BillingActionResult.alreadySubscribed:
        messenger.showSnackBar(
          const SnackBar(content: Text('Your subscription is already active.')),
        );
        break;
    }
  }

  Future<void> _restorePurchases() async {
    final billing = context.read<BillingService>();
    final auth = context.read<AuthService>();
    final storage = context.read<StorageService>();
    final messenger = ScaffoldMessenger.of(context);

    final result = await billing.restorePurchases(userId: auth.userId);
    if (!mounted) return;

    if (result == BillingActionResult.completed) {
      final userId = auth.userId;
      if (userId != null) {
        await storage.loadStorageInfo(userId, fallbackUser: auth.currentUser);
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('Subscription status refreshed.')),
      );
      return;
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text(billing.errorMessage ?? 'Restore is not available yet.'),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final storageService = context.watch<StorageService>();
    final billingService = context.watch<BillingService>();
    final authService = context.watch<AuthService>();
    final plans = StorageService.subscriptionPlans;

    return Scaffold(
      appBar: AppBar(
        flexibleSpace: desktopWindowDragArea(),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Storage Plans'),
        actions: withDesktopWindowControls([
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: storageService.isLoading || billingService.isLoading
                ? null
                : _refreshEntitlements,
          ),
        ]),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _CurrentPlanCard(
            storage: storageService,
            billing: billingService,
            onManage: billingService.openCustomerPortal,
          ),
          const SizedBox(height: 20),
          if (!billingService.canStartPurchase)
            _SetupNotice(billing: billingService)
          else
            const _PlatformNotice(),
          const SizedBox(height: 20),
          ...plans.map((plan) {
            final isCurrentPlan = plan.tier == storageService.currentTier;
            return _PlanCard(
              plan: plan,
              isCurrentPlan: isCurrentPlan,
              isSignedIn: authService.isLoggedIn,
              isBusy: storageService.isLoading || billingService.isLoading,
              onSelect: plan.tier == SubscriptionTier.free || isCurrentPlan
                  ? null
                  : () => _purchase(plan),
            );
          }),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: billingService.isLoading ? null : _restorePurchases,
            icon: const Icon(Icons.restore),
            label: const Text('Restore Purchases'),
          ),
        ],
      ),
    );
  }
}

class _CurrentPlanCard extends StatelessWidget {
  final StorageService storage;
  final BillingService billing;
  final Future<bool> Function() onManage;

  const _CurrentPlanCard({
    required this.storage,
    required this.billing,
    required this.onManage,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final entitlementTier = billing.entitlementTier;
    final showEntitlementHint = entitlementTier != SubscriptionTier.free &&
        entitlementTier != storage.currentTier;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current Plan',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.cloud, size: 44, color: colorScheme.primary),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        storage.currentTier.displayName,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      Text(
                        storage.usageFormatted,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: !billing.supportsRevenueCatUi &&
                          billing.managementUrl == null &&
                          RevenueCatBillingConfig.customerPortalUrl.isEmpty
                      ? null
                      : onManage,
                  child: const Text('Manage'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: storage.usagePercent.clamp(0, 1),
                backgroundColor: Colors.grey.withValues(alpha: 0.3),
                minHeight: 8,
              ),
            ),
            if (showEntitlementHint) ...[
              const SizedBox(height: 12),
              Text(
                'RevenueCat shows ${entitlementTier.displayName}; Firebase will update after the webhook runs.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.secondary,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SetupNotice extends StatelessWidget {
  final BillingService billing;

  const _SetupNotice({required this.billing});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                billing.errorMessage ??
                    'RevenueCat products are scaffolded. Add the platform keys or web purchase links to enable checkout.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlatformNotice extends StatelessWidget {
  const _PlatformNotice();

  @override
  Widget build(BuildContext context) {
    return Text(
      RevenueCatBillingConfig.supportsRevenueCatSdk
          ? 'TypeSync Lite renews monthly through RevenueCat.'
          : 'TypeSync Lite renews monthly through the external checkout page.',
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}

class _PlanCard extends StatelessWidget {
  final SubscriptionInfo plan;
  final bool isCurrentPlan;
  final bool isSignedIn;
  final bool isBusy;
  final VoidCallback? onSelect;

  const _PlanCard({
    required this.plan,
    required this.isCurrentPlan,
    required this.isSignedIn,
    required this.isBusy,
    this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: isCurrentPlan || plan.isRecommended
            ? BorderSide(
                color:
                    isCurrentPlan ? colorScheme.primary : colorScheme.secondary,
                width: isCurrentPlan ? 2 : 1,
              )
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(plan.name, style: theme.textTheme.titleLarge),
                      if (isCurrentPlan)
                        _Badge(
                          label: 'Current',
                          color: colorScheme.primary,
                          textColor: colorScheme.onPrimary,
                        ),
                      if (plan.isRecommended)
                        _Badge(
                          label: 'Recommended',
                          color: colorScheme.secondaryContainer,
                          textColor: colorScheme.onSecondaryContainer,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      plan.priceFormatted,
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(plan.storage, style: theme.textTheme.bodySmall),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...plan.features.map(
              (feature) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(Icons.check, size: 18, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(child: Text(feature)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: isBusy || !isSignedIn ? null : onSelect,
                child: Text(_buttonLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _buttonLabel {
    if (!isSignedIn) return 'Sign in required';
    if (isCurrentPlan) return 'Current Plan';
    if (plan.tier == SubscriptionTier.free) return 'Included';
    return 'Choose ${plan.name}';
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;

  const _Badge({
    required this.label,
    required this.color,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style:
            Theme.of(context).textTheme.labelSmall?.copyWith(color: textColor),
      ),
    );
  }
}
