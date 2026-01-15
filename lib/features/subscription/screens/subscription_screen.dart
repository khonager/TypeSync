/// Subscription Screen
///
/// Storage plan management and upgrade options.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/user.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/services/auth_service.dart';

import 'package:url_launcher/url_launcher.dart';

/// Subscription management screen
///
/// Shows available storage plans:
/// - Free: 1GB (included)
/// - Basic: 5GB for €1.99/month
/// - Standard: 50GB for €4.99/month
/// - Premium: 200GB for €9.99/month
class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  final _licenseController = TextEditingController();
  bool _isVerifying = false;

  @override
  void dispose() {
    _licenseController.dispose();
    super.dispose();
  }

  Future<void> _verifyLicense(
    StorageService storage,
    AuthService auth,
  ) async {
    if (_licenseController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a license key')),
      );
      return;
    }

    final userId = auth.userId;
    if (userId == null) return;

    setState(() => _isVerifying = true);

    final success = await storage.verifyLicenseKey(
      userId,
      _licenseController.text.trim(),
    );

    setState(() => _isVerifying = false);

    if (!mounted) return;

    if (success) {
      _licenseController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('License verified! Premium unlocked.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(storage.errorMessage ?? 'Verification failed'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _verifyPatreon(
    StorageService storage,
    AuthService auth,
  ) async {
    final userId = auth.userId;
    if (userId == null) return;

    setState(() => _isVerifying = true);

    final success = await storage.verifyPatreon(userId);

    setState(() => _isVerifying = false);

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Patreon verified! Premium unlocked.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(storage.errorMessage ?? 'Verification failed'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

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
                      backgroundColor: Colors.grey.withValues(alpha: 0.3),
                      minHeight: 8,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Unlock Section
          Text(
            'Unlock Premium',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Have a Gumroad License?',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _licenseController,
                    decoration: const InputDecoration(
                      labelText: 'License Key',
                      hintText: 'XXXXXXXX-XXXXXXXX-XXXXXXXX-XXXXXXXX',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _isVerifying || storageService.isLoading
                          ? null
                          : () => _verifyLicense(
                                storageService,
                                authService,
                              ),
                      child: _isVerifying
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Redeem License'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: () {
                        const url = 'https://khonager.gumroad.com/l/ixufbj';
                        launchUrl(
                          Uri.parse(url),
                          mode: LaunchMode.externalApplication,
                        );
                      },
                      child: const Text('Buy License on Gumroad'),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.favorite, color: Colors.red),
                      const SizedBox(width: 8),
                      Text(
                        'Patreon Supporter?',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Link your Patreon account to unlock premium features if you are an active supporter.',
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _isVerifying || storageService.isLoading
                          ? null
                          : () => _verifyPatreon(
                                storageService,
                                authService,
                              ),
                      child: const Text('Verify Patreon Subscription'),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          Text(
            'Plan Details',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),

          // Plan cards (Read-only / info)
          ...StorageService.subscriptionPlans.map((plan) {
            final isCurrentPlan = plan.tier == storageService.currentTier;

            return _PlanCard(
              plan: plan,
              isCurrentPlan: isCurrentPlan,
              onSelect:
                  null, // Disable selection, buying is done via Key/Patreon
            );
          }),
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
