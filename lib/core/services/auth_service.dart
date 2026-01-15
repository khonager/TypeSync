/// Authentication Service
///
/// Handles user authentication via Firebase Auth including
/// login, registration, password reset, and session management.
library;

import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user.dart';

/// Service for managing user authentication
///
/// Provides methods for sign in, sign up, sign out, and
/// password recovery. Maintains current user state.
class AuthService extends ChangeNotifier {
  // Firebase Auth instance (lazy initialization)
  firebase.FirebaseAuth? _auth;
  FirebaseFirestore? _firestore;

  // Lazy getters for Firebase instances
  firebase.FirebaseAuth get _firebaseAuth {
    _auth ??= firebase.FirebaseAuth.instance;
    return _auth!;
  }

  FirebaseFirestore get _firebaseFirestore {
    _firestore ??= FirebaseFirestore.instance;
    return _firestore!;
  }

  // Current user data
  User? _currentUser;

  // Guest mode flag
  bool _isGuestMode = false;

  // Sync enabled preference (for logged-in users)
  bool _syncEnabled = true;

  // Loading state
  bool _isLoading = false;

  // Error state
  String? _errorMessage;
  bool _hasError = false;

  // ===========================================
  // GETTERS
  // ===========================================

  /// Current authenticated user (null if not logged in)
  User? get currentUser => _currentUser;

  /// Whether a user is currently authenticated (including guest)
  bool get isAuthenticated => _currentUser != null;

  /// Whether the current user is a guest
  bool get isGuestMode => _isGuestMode;

  /// Whether sync is enabled (only relevant for logged-in users)
  bool get syncEnabled => _syncEnabled;

  /// Loading state for async operations
  bool get isLoading => _isLoading;

  /// Current error message (null if no error)
  String? get errorMessage => _errorMessage;

  /// Whether there's an active error
  bool get hasError => _hasError;

  /// User ID for local storage (Firebase UID for logged-in users, guest ID for guests)
  String? get userId {
    if (_isGuestMode && _currentUser != null) {
      return _currentUser!.id;
    }
    return _auth?.currentUser?.uid;
  }

  /// Whether user is logged in (not guest)
  bool get isLoggedIn => isAuthenticated && !_isGuestMode;

  // ===========================================
  // CONSTRUCTOR
  // ===========================================

  AuthService() {
    _loadPreferences();
    // Only listen to auth state changes if Firebase is initialized
    try {
      if (Firebase.apps.isNotEmpty) {
        _firebaseAuth.authStateChanges().listen(_onAuthStateChanged);
      }
    } catch (e) {
      // Firebase not initialized (e.g., on Linux without proper config)
      // Silently handle - app can run in offline mode
      if (kDebugMode) {
        debugPrint(
          'Firebase Auth not available: ${e.toString().split(':').first}',
        );
      }
    }
  }

  /// Load preferences from SharedPreferences
  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _syncEnabled = prefs.getBool('sync_enabled') ?? true;
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading preferences: $e');
    }
  }

  /// Save sync enabled preference
  Future<void> _saveSyncEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('sync_enabled', enabled);
      _syncEnabled = enabled;
      notifyListeners();
    } catch (e) {
      debugPrint('Error saving sync preference: $e');
    }
  }

  // ===========================================
  // AUTHENTICATION METHODS
  // ===========================================

  /// Sign in with email and password
  ///
  /// Returns true if sign in was successful, false otherwise.
  /// Check [errorMessage] for failure details.
  Future<bool> signIn({
    required String email,
    required String password,
  }) async {
    _setLoading(true);
    _clearError();

    try {
      // Attempt Firebase sign in
      final credential = await _firebaseAuth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      // Load user data from Firestore
      if (credential.user != null) {
        await _loadUserData(credential.user!.uid);
      }

      _setLoading(false);
      return true;
    } on firebase.FirebaseAuthException catch (e) {
      // Handle specific Firebase auth errors
      _setError(_mapFirebaseError(e.code));
      _setLoading(false);
      return false;
    } catch (e) {
      _setError('An unexpected error occurred. Please try again.');
      _setLoading(false);
      return false;
    }
  }

  /// Register a new user with email and password
  ///
  /// Creates both a Firebase Auth account and a Firestore user document.
  Future<bool> register({
    required String email,
    required String password,
    String? displayName,
  }) async {
    _setLoading(true);
    _clearError();

    try {
      // Create Firebase Auth account
      final credential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      if (credential.user != null) {
        // Update display name if provided
        if (displayName != null && displayName.isNotEmpty) {
          await credential.user!.updateDisplayName(displayName);
        }

        // Create user document in Firestore
        final user = User(
          id: credential.user!.uid,
          email: email.trim(),
          displayName: displayName,
          createdAt: DateTime.now(),
          lastSignIn: DateTime.now(),
          emailVerified: credential.user!.emailVerified,
        );

        await _firebaseFirestore
            .collection('users')
            .doc(credential.user!.uid)
            .set(user.toJson());

        _currentUser = user;
        notifyListeners();

        // Send email verification
        await credential.user!.sendEmailVerification();
      }

      _setLoading(false);
      return true;
    } on firebase.FirebaseAuthException catch (e) {
      _setError(_mapFirebaseError(e.code));
      _setLoading(false);
      return false;
    } catch (e) {
      _setError('Registration failed. Please try again.');
      _setLoading(false);
      return false;
    }
  }

  /// Enter guest mode (no user account)
  void enterGuestMode() {
    _isLoading = true;
    notifyListeners();

    _currentUser = null;
    _isGuestMode = true;

    _isLoading = false;
    notifyListeners();
  }

  /// Send sign-in link to email (Passwordless / Magic Link)
  Future<bool> sendSignInLinkToEmail(String email) async {
    _setLoading(true);
    _clearError();

    try {
      final acs = firebase.ActionCodeSettings(
        // URL you want to redirect back to. The domain (www.example.com) for this
        // URL must be whitelisted in the Firebase Console.
        url:
            'https://typesynced.web.app/login?email=$email', // TODO: Configure dynamic link
        handleCodeInApp: true,
        iOSBundleId: 'com.khonager.typesync',
        androidPackageName: 'com.khonager.typesync',
        // androidInstallApp: true,
        // androidMinimumVersion: '12',
      );

      await _firebaseAuth.sendSignInLinkToEmail(
        email: email.trim(),
        actionCodeSettings: acs,
      );

      // Save the email locally so we can use it when the link is opened
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('emailLinkUserEmail', email.trim());

      _setLoading(false);
      return true;
    } on firebase.FirebaseAuthException catch (e) {
      _setError(_mapFirebaseError(e.code));
      _setLoading(false);
      return false;
    } catch (e) {
      _setError('Failed to send sign in link. Please try again.');
      _setLoading(false);
      return false;
    }
  }

  /// Complete sign-in with email link
  Future<bool> signInWithEmailLink(String emailLink) async {
    _setLoading(true);
    _clearError();

    try {
      final prefs = await SharedPreferences.getInstance();
      final String? email = prefs.getString('emailLinkUserEmail');

      // If email is not saved locally, ask user for it (UI should handle this flow)
      if (email == null) {
        _setError('email-not-found-locally'); // Special error code for UI
        _setLoading(false);
        return false;
      }

      if (_firebaseAuth.isSignInWithEmailLink(emailLink)) {
        final credential = await _firebaseAuth.signInWithEmailLink(
          email: email,
          emailLink: emailLink,
        );

        if (credential.user != null) {
          await _loadUserData(credential.user!.uid);
          // Clear saved email
          await prefs.remove('emailLinkUserEmail');
        }
      }

      _setLoading(false);
      return true;
    } on firebase.FirebaseAuthException catch (e) {
      _setError(_mapFirebaseError(e.code));
      _setLoading(false);
      return false;
    } catch (e) {
      _setError('Sign in failed. Please try again.');
      _setLoading(false);
      return false;
    }
  }

  /// Toggle sync enabled/disabled (only for logged-in users)
  Future<void> setSyncEnabled(bool enabled) async {
    if (_isGuestMode) {
      // Guests can't sync anyway
      return;
    }
    await _saveSyncEnabled(enabled);
  }

  /// Sign out the current user
  Future<void> signOut() async {
    _setLoading(true);

    try {
      if (!_isGuestMode) {
        await _firebaseAuth.signOut();
      }
      _currentUser = null;
      _isGuestMode = false;
      notifyListeners();
    } catch (e) {
      _setError('Sign out failed. Please try again.');
    }

    _setLoading(false);
  }

  /// Send password reset email
  Future<bool> resetPassword(String email) async {
    _setLoading(true);
    _clearError();

    try {
      await _firebaseAuth.sendPasswordResetEmail(email: email.trim());
      _setLoading(false);
      return true;
    } on firebase.FirebaseAuthException catch (e) {
      _setError(_mapFirebaseError(e.code));
      _setLoading(false);
      return false;
    } catch (e) {
      _setError('Failed to send reset email. Please try again.');
      _setLoading(false);
      return false;
    }
  }

  /// Resend email verification
  Future<bool> resendVerificationEmail() async {
    try {
      await _firebaseAuth.currentUser?.sendEmailVerification();
      return true;
    } catch (e) {
      _setError('Failed to send verification email.');
      return false;
    }
  }

  /// Update user profile
  Future<bool> updateProfile({
    String? displayName,
    String? photoUrl,
  }) async {
    if (_currentUser == null) return false;

    _setLoading(true);
    _clearError();

    try {
      // Update Firebase Auth profile
      if (displayName != null) {
        await _firebaseAuth.currentUser?.updateDisplayName(displayName);
      }
      if (photoUrl != null) {
        await _firebaseAuth.currentUser?.updatePhotoURL(photoUrl);
      }

      // Update Firestore document
      final updates = <String, dynamic>{};
      if (displayName != null) updates['displayName'] = displayName;
      if (photoUrl != null) updates['photoUrl'] = photoUrl;

      await _firebaseFirestore
          .collection('users')
          .doc(_currentUser!.id)
          .update(updates);

      // Update local user
      _currentUser = _currentUser!.copyWith(
        displayName: displayName ?? _currentUser!.displayName,
        photoUrl: photoUrl ?? _currentUser!.photoUrl,
      );

      notifyListeners();
      _setLoading(false);
      return true;
    } catch (e) {
      _setError('Failed to update profile.');
      _setLoading(false);
      return false;
    }
  }

  // ===========================================
  // PRIVATE METHODS
  // ===========================================

  /// Handle auth state changes
  Future<void> _onAuthStateChanged(firebase.User? firebaseUser) async {
    if (firebaseUser != null && !_isGuestMode) {
      await _loadUserData(firebaseUser.uid);
    } else if (firebaseUser == null && !_isGuestMode) {
      // Only clear user if not in guest mode
      _currentUser = null;
      notifyListeners();
    }
  }

  /// Load user data from Firestore
  Future<void> _loadUserData(String uid) async {
    try {
      final doc = await _firebaseFirestore.collection('users').doc(uid).get();

      if (doc.exists) {
        _currentUser = User.fromJson(doc.data()!);

        // Update last sign in
        await _firebaseFirestore.collection('users').doc(uid).update({
          'lastSignIn': DateTime.now().toIso8601String(),
        });
      } else {
        // Create user document if it doesn't exist (e.g., after auth migration)
        final firebaseUser = _firebaseAuth.currentUser!;
        final user = User(
          id: uid,
          email: firebaseUser.email!,
          displayName: firebaseUser.displayName,
          photoUrl: firebaseUser.photoURL,
          createdAt: DateTime.now(),
          lastSignIn: DateTime.now(),
          emailVerified: firebaseUser.emailVerified,
        );

        await _firebaseFirestore
            .collection('users')
            .doc(uid)
            .set(user.toJson());
        _currentUser = user;
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Error loading user data: $e');
    }
  }

  /// Map Firebase error codes to user-friendly messages
  String _mapFirebaseError(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
        return 'Incorrect password.';
      case 'email-already-in-use':
        return 'An account already exists with this email.';
      case 'weak-password':
        return 'Password is too weak. Use at least 6 characters.';
      case 'invalid-email':
        return 'Invalid email address.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'operation-not-allowed':
        return 'Email/password sign in is not enabled.';
      case 'network-request-failed':
        return 'Network error. Check your connection.';
      default:
        return 'Authentication failed. Please try again.';
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _setError(String message) {
    _errorMessage = message;
    _hasError = true;
    notifyListeners();
  }

  void _clearError() {
    _errorMessage = null;
    _hasError = false;
  }

  /// Clear error state manually
  void clearError() {
    _clearError();
    notifyListeners();
  }
}
