/// Billing service
///
/// Owns RevenueCat configuration, purchase actions, and entitlement mapping.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:purchases_flutter/purchases_flutter.dart' as purchases;
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart' as rc_ui;
import 'package:url_launcher/url_launcher.dart';

import '../models/user.dart';
import 'storage_service.dart';

class RevenueCatBillingConfig {
  static const defaultPublicApiKey = 'test_fewInKsVqvMRCAmhNYUTFYLqxFT';
  static const androidApiKey =
      String.fromEnvironment('REVENUECAT_ANDROID_API_KEY');
  static const appleApiKey = String.fromEnvironment('REVENUECAT_APPLE_API_KEY');
  static const webApiKey = String.fromEnvironment(
    'REVENUECAT_WEB_API_KEY',
    defaultValue: defaultPublicApiKey,
  );

  static const typeSyncLiteWebPurchaseUrl =
      String.fromEnvironment('REVENUECAT_TYPESYNC_LITE_WEB_PURCHASE_URL');
  static const customerPortalUrl =
      String.fromEnvironment('REVENUECAT_CUSTOMER_PORTAL_URL');

  static const liteEntitlementId = 'TypeSync Lite';
  static const monthlyProductId = 'monthly';
  static const defaultOfferingId = 'default';

  static const entitlementIds = [liteEntitlementId];

  static const productIdsByPlanId = {
    liteEntitlementId: monthlyProductId,
  };

  static bool get supportsRevenueCatSdk =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  static bool get supportsRevenueCatUi =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static String get platformApiKey {
    if (kIsWeb) return webApiKey;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return androidApiKey.isEmpty ? defaultPublicApiKey : androidApiKey;
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return appleApiKey.isEmpty ? defaultPublicApiKey : appleApiKey;
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        return '';
    }
  }

  static String webPurchaseUrlFor(SubscriptionTier tier) {
    switch (tier) {
      case SubscriptionTier.basic:
        return typeSyncLiteWebPurchaseUrl;
      case SubscriptionTier.standard:
      case SubscriptionTier.premium:
      case SubscriptionTier.free:
        return '';
    }
  }
}

class RevenueCatRuntimeBillingConfig {
  final String typeSyncLiteWebPurchaseUrl;
  final String customerPortalUrl;

  const RevenueCatRuntimeBillingConfig({
    this.typeSyncLiteWebPurchaseUrl = '',
    this.customerPortalUrl = '',
  });

  factory RevenueCatRuntimeBillingConfig.fromJson(Map<String, dynamic> json) {
    String stringValue(String key) {
      final value = json[key];
      return value is String ? value.trim() : '';
    }

    return RevenueCatRuntimeBillingConfig(
      typeSyncLiteWebPurchaseUrl:
          stringValue('typeSyncLiteWebPurchaseUrl').isNotEmpty
              ? stringValue('typeSyncLiteWebPurchaseUrl')
              : stringValue('revenueCatTypeSyncLiteWebPurchaseUrl'),
      customerPortalUrl: stringValue('customerPortalUrl').isNotEmpty
          ? stringValue('customerPortalUrl')
          : stringValue('revenueCatCustomerPortalUrl'),
    );
  }
}

enum BillingActionResult {
  completed,
  openedExternal,
  notConfigured,
  unavailable,
  canceled,
  alreadySubscribed,
  failed,
}

class BillingService extends ChangeNotifier {
  bool _isLoading = false;
  bool _isConfigured = false;
  String? _configuredUserId;
  String? _errorMessage;
  String? _managementUrl;
  SubscriptionTier _entitlementTier = SubscriptionTier.free;
  Map<String, purchases.Package> _packagesByProductId = {};
  purchases.Offering? _currentOffering;
  bool _runtimeConfigLoaded = false;
  RevenueCatRuntimeBillingConfig _runtimeConfig =
      const RevenueCatRuntimeBillingConfig();

  bool get isLoading => _isLoading;
  bool get isConfigured => _isConfigured;
  String? get errorMessage => _errorMessage;
  String? get managementUrl => _managementUrl;
  SubscriptionTier get entitlementTier => _entitlementTier;
  bool get supportsRevenueCatSdk =>
      RevenueCatBillingConfig.supportsRevenueCatSdk;
  bool get supportsRevenueCatUi => RevenueCatBillingConfig.supportsRevenueCatUi;

  bool get hasWebPurchaseLinks =>
      _configuredWebPurchaseUrlFor(SubscriptionTier.basic).isNotEmpty;

  bool get canStartPurchase =>
      supportsRevenueCatSdk ? _isConfigured : hasWebPurchaseLinks;

  Future<void> configureForUser(String? userId) async {
    await _loadRuntimeConfig();

    if (userId == null || userId.isEmpty) {
      _configuredUserId = null;
      _isConfigured = false;
      _entitlementTier = SubscriptionTier.free;
      return;
    }

    if (_configuredUserId == userId &&
        (_isConfigured || !supportsRevenueCatSdk)) {
      return;
    }

    _configuredUserId = userId;
    _errorMessage = null;

    if (!supportsRevenueCatSdk) {
      _isConfigured = false;
      notifyListeners();
      return;
    }

    final apiKey = RevenueCatBillingConfig.platformApiKey;
    if (apiKey.isEmpty) {
      _isConfigured = false;
      _errorMessage = 'RevenueCat is not configured for this platform yet.';
      notifyListeners();
      return;
    }

    try {
      final alreadyConfigured = await purchases.Purchases.isConfigured;
      if (!alreadyConfigured) {
        await purchases.Purchases.configure(
          purchases.PurchasesConfiguration(apiKey)..appUserID = userId,
        );
        purchases.Purchases.addCustomerInfoUpdateListener(_applyCustomerInfo);
      } else {
        await purchases.Purchases.logIn(userId);
      }
      _isConfigured = true;
      await refreshCustomerInfo();
      await _loadOfferings();
    } catch (e) {
      _isConfigured = false;
      _errorMessage = 'RevenueCat setup failed: $e';
      notifyListeners();
    }
  }

  Future<BillingActionResult> purchasePlan(
    SubscriptionInfo plan, {
    required String? userId,
  }) async {
    if (plan.tier == SubscriptionTier.free) {
      return BillingActionResult.unavailable;
    }

    await configureForUser(userId);

    if (!supportsRevenueCatSdk) {
      final url = _configuredWebPurchaseUrlFor(plan.tier, userId: userId);
      if (url.isEmpty) {
        _errorMessage = 'RevenueCat web purchase link is not configured yet.';
        notifyListeners();
        return BillingActionResult.notConfigured;
      }
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        _errorMessage = 'Could not open the purchase page.';
        notifyListeners();
        return BillingActionResult.failed;
      }
      return BillingActionResult.openedExternal;
    }

    if (!_isConfigured) {
      _errorMessage = 'RevenueCat is not configured for this platform yet.';
      notifyListeners();
      return BillingActionResult.notConfigured;
    }

    final productId = plan.tier.revenueCatProductId;
    final package = productId == null ? null : _packagesByProductId[productId];
    if (package == null) {
      _errorMessage =
          'RevenueCat product $productId is not available in the current offering.';
      notifyListeners();
      return BillingActionResult.unavailable;
    }

    _setLoading(true);
    try {
      final result = await purchases.Purchases.purchase(
        purchases.PurchaseParams.package(package),
      );
      _applyCustomerInfo(result.customerInfo);
      _setLoading(false);
      return BillingActionResult.completed;
    } catch (e) {
      _errorMessage = 'Purchase failed: $e';
      _setLoading(false);
      return BillingActionResult.failed;
    }
  }

  Future<BillingActionResult> presentLitePaywall({
    required String? userId,
  }) async {
    await configureForUser(userId);

    if (!supportsRevenueCatUi) {
      final litePlan = StorageService.subscriptionPlans.firstWhere(
        (plan) => plan.tier == SubscriptionTier.basic,
      );
      return purchasePlan(litePlan, userId: userId);
    }

    if (!_isConfigured) {
      _errorMessage = 'RevenueCat is not configured for this platform yet.';
      notifyListeners();
      return BillingActionResult.notConfigured;
    }

    _setLoading(true);
    try {
      final result = await rc_ui.RevenueCatUI.presentPaywallIfNeeded(
        RevenueCatBillingConfig.liteEntitlementId,
        offering: _currentOffering,
        displayCloseButton: true,
        presentationConfiguration:
            rc_ui.PaywallPresentationConfiguration.defaultConfiguration,
      );
      if (result == rc_ui.PaywallResult.purchased ||
          result == rc_ui.PaywallResult.restored) {
        await refreshCustomerInfo();
        _setLoading(false);
        return BillingActionResult.completed;
      }
      if (result == rc_ui.PaywallResult.notPresented) {
        _setLoading(false);
        return BillingActionResult.alreadySubscribed;
      }
      if (result == rc_ui.PaywallResult.cancelled) {
        _setLoading(false);
        return BillingActionResult.canceled;
      }
      _errorMessage = 'RevenueCat could not present the paywall.';
      _setLoading(false);
      return BillingActionResult.failed;
    } catch (e) {
      _errorMessage = 'Paywall failed: $e';
      _setLoading(false);
      return BillingActionResult.failed;
    }
  }

  Future<BillingActionResult> restorePurchases({
    required String? userId,
  }) async {
    await configureForUser(userId);

    if (!supportsRevenueCatSdk) {
      await refreshCustomerInfo();
      return BillingActionResult.completed;
    }

    if (!_isConfigured) {
      _errorMessage = 'RevenueCat is not configured for this platform yet.';
      notifyListeners();
      return BillingActionResult.notConfigured;
    }

    _setLoading(true);
    try {
      final customerInfo = await purchases.Purchases.restorePurchases();
      _applyCustomerInfo(customerInfo);
      _setLoading(false);
      return BillingActionResult.completed;
    } catch (e) {
      _errorMessage = 'Restore failed: $e';
      _setLoading(false);
      return BillingActionResult.failed;
    }
  }

  Future<void> refreshCustomerInfo() async {
    if (!supportsRevenueCatSdk || !_isConfigured) return;

    try {
      await purchases.Purchases.invalidateCustomerInfoCache();
      _applyCustomerInfo(await purchases.Purchases.getCustomerInfo());
    } catch (e) {
      _errorMessage = 'Could not refresh subscription status: $e';
      notifyListeners();
    }
  }

  Future<bool> openCustomerPortal() async {
    if (supportsRevenueCatUi && _isConfigured) {
      try {
        await rc_ui.RevenueCatUI.presentCustomerCenter(
          onRestoreCompleted: (customerInfo) =>
              _applyCustomerInfo(customerInfo),
        );
        return true;
      } catch (e) {
        _errorMessage = 'Customer Center failed: $e';
        notifyListeners();
        return false;
      }
    }

    final url = _managementUrl ??
        _runtimeConfig.customerPortalUrl.ifEmpty(
          RevenueCatBillingConfig.customerPortalUrl,
        );
    if (url.isEmpty) {
      _errorMessage = 'Customer portal is not configured yet.';
      notifyListeners();
      return false;
    }
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!opened) {
      _errorMessage = 'Could not open subscription management.';
      notifyListeners();
    }
    return opened;
  }

  Future<void> _loadRuntimeConfig() async {
    if (_runtimeConfigLoaded) return;
    _runtimeConfigLoaded = true;

    if (!kIsWeb) return;

    try {
      final uri = Uri.base.resolve(
        'billing_config.json?v=${DateTime.now().millisecondsSinceEpoch}',
      );
      final response = await http.get(uri);
      if (response.statusCode != 200 || response.body.trim().isEmpty) {
        notifyListeners();
        return;
      }

      final json = jsonDecode(response.body);
      if (json is Map<String, dynamic>) {
        _runtimeConfig = RevenueCatRuntimeBillingConfig.fromJson(json);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Billing runtime config load failed: $e');
    }
  }

  String _configuredWebPurchaseUrlFor(SubscriptionTier tier, {String? userId}) {
    switch (tier) {
      case SubscriptionTier.basic:
        final baseUrl = _runtimeConfig.typeSyncLiteWebPurchaseUrl.ifEmpty(
          RevenueCatBillingConfig.typeSyncLiteWebPurchaseUrl,
        );
        if (baseUrl.isEmpty || userId == null || userId.isEmpty) {
          return baseUrl;
        }
        return _appendAppUserIdToPurchaseUrl(baseUrl, userId);
      case SubscriptionTier.standard:
      case SubscriptionTier.premium:
      case SubscriptionTier.free:
        return '';
    }
  }

  String _appendAppUserIdToPurchaseUrl(String baseUrl, String userId) {
    final uri = Uri.parse(baseUrl);
    final pathSegments = [
      ...uri.pathSegments.where((segment) => segment.isNotEmpty),
      userId,
    ];
    return uri.replace(pathSegments: pathSegments).toString();
  }

  static SubscriptionTier tierFromActiveEntitlements(
    Iterable<String> entitlementIds,
  ) {
    final ids = entitlementIds.toSet();
    if (ids.contains('pro')) return SubscriptionTier.premium;
    if (ids.contains('plus')) return SubscriptionTier.standard;
    if (ids.contains(RevenueCatBillingConfig.liteEntitlementId) ||
        ids.contains('light')) {
      return SubscriptionTier.basic;
    }
    return SubscriptionTier.free;
  }

  Future<void> _loadOfferings() async {
    if (!_isConfigured) return;
    try {
      final offerings = await purchases.Purchases.getOfferings();
      _currentOffering =
          offerings.getOffering(RevenueCatBillingConfig.defaultOfferingId) ??
              offerings.current;
      final offering = _currentOffering;
      final packages = offerings.current?.availablePackages ?? [];
      _packagesByProductId = {
        for (final package in packages)
          package.storeProduct.identifier: package,
        for (final package in packages) package.identifier: package,
        if (offering != null)
          for (final package in offering.availablePackages)
            package.storeProduct.identifier: package,
        if (offering != null)
          for (final package in offering.availablePackages)
            package.identifier: package,
      };
      notifyListeners();
    } catch (e) {
      _packagesByProductId = {};
      _errorMessage = 'Could not load RevenueCat offerings: $e';
      notifyListeners();
    }
  }

  void _applyCustomerInfo(purchases.CustomerInfo customerInfo) {
    _entitlementTier = tierFromActiveEntitlements(
      customerInfo.entitlements.active.keys,
    );
    _managementUrl = customerInfo.managementURL;
    _errorMessage = null;
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}

extension _StringFallback on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
