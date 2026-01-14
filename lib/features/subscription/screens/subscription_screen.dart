/// Subscription Screen
///
/// Storage plan management and upgrade options.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/user.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/services/auth_service.dart';

/// Subscription management screen
///
/// Shows available storage plans:
/// - Free: 1GB (included)
/// - Basic: 5GB for €1.99/month
/// - Standard: 50GB for €4.99/month
/// - Premium: 200GB for €9.99/month
class SubscriptionScreen extends StatelessWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final storageService = context.watch<StorageService>();
    final authService = context.watch<AuthService>();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Storage Plans'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Current plan card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current Plan',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.cloud,
                        size: 48,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              storageService.currentTier.displayName,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            Text(
                              storageService.usageFormatted,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Storage bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: storageService.usagePercent,
                      backgroundColor: Colors.grey.withOpacity(0.3),
                      minHeight: 8,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          Text(
            'Available Plans',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),

          // Plan cards
          ...StorageService.subscriptionPlans.map((plan) {
            final isCurrentPlan = plan.tier == storageService.currentTier;

            return _PlanCard(
              plan: plan,
              isCurrentPlan: isCurrentPlan,
              onSelect: isCurrentPlan
                  ? null
                  : () {
                      _showUpgradeDialog(
                        context,
                        plan,
                        authService,
                        storageService,
                      );
                    },
            );
          }),

          const SizedBox(height: 24),

          // Restore purchases
          Center(
            child: TextButton(
              onPressed: () {
                // TODO: Implement restore purchases
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Checking for previous purchases...'),
                  ),
                );
              },
              child: const Text('Restore Purchases'),
            ),
          ),
        ],
      ),
    );
  }

  void _showUpgradeDialog(
    BuildContext context,
    SubscriptionInfo plan,
    AuthService authService,
    StorageService storageService,
  ) {
    // Check if user is in guest mode
    if (authService.isGuestMode) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Login Required'),
          content: const Text(
            'Please log in to upgrade your subscription. Guest mode only supports local storage.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context); // Close subscription screen
                // Navigate to login screen
                // TODO: Add navigation to login screen
              },
              child: const Text('Go to Login'),
            ),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Upgrade to ${plan.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              plan.priceFormatted,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            Text('${plan.storage} cloud storage'),
            const SizedBox(height: 8),
            ...plan.features.map(
              (f) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    const Icon(Icons.check, size: 16, color: Colors.green),
                    const SizedBox(width: 8),
                    Text(f),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);

              // TODO: Integrate with payment provider
              // Only show success message after payment is confirmed
              // For now, this is a placeholder - actual payment integration should
              // only show success after payment confirmation
              final userId = authService.userId;
              if (userId != null) {
                final success =
                    await storageService.upgradeSubscription(userId, plan.tier);

                if (context.mounted && success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Upgraded to ${plan.name}!'),
                    ),
                  );
                } else if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Failed to upgrade subscription. Please try again.',
                      ),
                    ),
                  );
                }
              }
            },
            child: Text('Upgrade for ${plan.priceFormatted}'),
          ),
        ],
      ),
    );
  }
}

/// Individual plan card widget
class _PlanCard extends StatelessWidget {
  final SubscriptionInfo plan;
  final bool isCurrentPlan;
  final VoidCallback? onSelect;

  const _PlanCard({
    required this.plan,
    required this.isCurrentPlan,
    this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isCurrentPlan
            ? BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              )
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Plan info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          plan.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (isCurrentPlan) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Current',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color:
                                        Theme.of(context).colorScheme.onPrimary,
                                  ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      plan.storage,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    ),
                  ],
                ),
              ),
              // Price
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    plan.priceFormatted,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
