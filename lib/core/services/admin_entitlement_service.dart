/// Secure administration of complimentary TypeSync entitlements.
library;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../models/user.dart';

class AdminEntitlementResult {
  final String email;
  final SubscriptionTier effectiveTier;
  final DateTime? expiresAt;

  const AdminEntitlementResult({
    required this.email,
    required this.effectiveTier,
    this.expiresAt,
  });
}

/// Calls server-side functions which independently verify administrator access.
///
/// This service intentionally has no client-side allow-list. The backend checks
/// a Firebase Auth custom claim or the server-only `ADMIN_EMAILS` secret.
class AdminEntitlementService extends ChangeNotifier {
  bool _isAdmin = false;
  bool _isLoading = false;
  String? _errorMessage;
  String? _checkedUserId;

  bool get isAdmin => _isAdmin;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> refreshAccess(String? userId) async {
    if (userId == _checkedUserId) return;
    _checkedUserId = userId;
    _isAdmin = false;
    _errorMessage = null;
    if (userId == null || userId.isEmpty) {
      notifyListeners();
      return;
    }

    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('get_admin_status')
          .call();
      final data = Map<String, dynamic>.from(result.data as Map);
      _isAdmin = data['isAdmin'] == true;
    } catch (error) {
      // Do not expose privileged controls if the access check is unavailable.
      _isAdmin = false;
      debugPrint('Admin access check failed: $error');
    }
    notifyListeners();
  }

  Future<AdminEntitlementResult> setEntitlement({
    required String email,
    required SubscriptionTier tier,
    int? durationDays,
  }) async {
    _setLoading(true);
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('set_admin_entitlement')
          .call({
        'email': email.trim(),
        'planId': tier.planId,
        if (durationDays != null) 'durationDays': durationDays,
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      final expiresAtValue = data['expiresAt'];
      final expiresAt = expiresAtValue is String
          ? DateTime.tryParse(expiresAtValue)?.toLocal()
          : null;
      _errorMessage = null;
      _setLoading(false);
      return AdminEntitlementResult(
        email: data['email'] as String? ?? email.trim(),
        effectiveTier: subscriptionTierFromPlanId(
          data['effectivePlanId'] as String?,
        ),
        expiresAt: expiresAt,
      );
    } on FirebaseFunctionsException catch (error) {
      _errorMessage = error.message ?? 'Could not update the entitlement.';
      _setLoading(false);
      throw Exception(_errorMessage);
    } catch (error) {
      _errorMessage = 'Could not update the entitlement.';
      _setLoading(false);
      throw Exception(_errorMessage);
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}
