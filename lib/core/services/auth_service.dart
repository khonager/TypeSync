/// Authentication Service
///
/// Handles user authentication via Firebase Auth including
/// login, registration, password reset, and session management.
library;

import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firedart/firedart.dart' as fd;
import 'package:firedart/auth/user_gateway.dart' as fd;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/user.dart';

/// Service for managing user authentication
///
/// Provides methods for sign in, sign up, sign out, and
/// password recovery. Maintains current user state.
class AuthService extends ChangeNotifier {
  // Firebase Auth instance (lazy initialization)
  firebase.FirebaseAuth? _auth;
  FirebaseFirestore? _firestore;

  // Firedart instances for Linux fallback
  fd.FirebaseAuth? _fdAuth;

  // Lazy getters for Firebase instances
  firebase.FirebaseAuth get _firebaseAuth {
    _auth ??= firebase.FirebaseAuth.instance;
    return _auth!;
  }

  FirebaseFirestore get _firebaseFirestore {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
      // On Linux, we should ideally use Firedart for Firestore too,
      // but the app currently uses cloud_firestore FirebaseFirestore type.
      // If Firebase.initializeApp worked, this might work.
      // If it didn't, this will throw.
      return FirebaseFirestore.instance;
    }
    _firestore ??= FirebaseFirestore.instance;
    return _firestore!;
  }

  fd.FirebaseAuth get _firedartAuth {
    try {
      _fdAuth ??= fd.FirebaseAuth.instance;
      return _fdAuth!;
    } catch (e) {
      // If FirebaseAuth.instance throws because it hasn't been initialized,
      // we need to handle it gracefully.
      if (kDebugMode) {
        debugPrint('Firedart FirebaseAuth instance access failed: $e');
      }
      rethrow;
    }
  }

  // Current user data
  User? _currentUser;

  // Guest mode flag
  bool _isGuestMode = false;

  // Sync enabled preference (for logged-in users)
  bool _syncEnabled = true;

  // Workspace mode preference (for logged-in users)
  bool _localOnlyMode = false;

  // Loading state
  bool _isLoading = false;

  // Initialization state (whether we've determined the initial auth state)
  bool _isInitialized = false;

  // Error state
  String? _errorMessage;
  bool _hasError = false;

  // UUID generator for guest IDs
  final Uuid _uuid = const Uuid();

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

  /// Whether local-only workspace mode is enabled.
  bool get localOnlyMode => _localOnlyMode;

  /// Whether cloud sync should actively run.
  bool get effectiveSyncEnabled => _syncEnabled && !_localOnlyMode;

  /// Loading state for async operations
  bool get isLoading => _isLoading;

  /// Whether the initial auth state has been determined
  bool get isInitialized => _isInitialized;

  /// Current error message (null if no error)
  String? get errorMessage => _errorMessage;

  /// Whether there's an active error
  bool get hasError => _hasError;

  /// User ID for local storage (Firebase UID for logged-in users, guest ID for guests)
  String? get userId {
    if (_isGuestMode && _currentUser != null) {
      return _currentUser!.id;
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
      return _firedartAuth.isSignedIn ? _firedartAuth.userId : null;
    }
    return _auth?.currentUser?.uid;
  }

  /// Local storage workspace ID. When local-only mode is enabled for a logged-in
  /// user, this points to an isolated local workspace.
  String? get storageUserId {
    final uid = userId;
    if (uid == null) return null;
    if (isLoggedIn && _localOnlyMode) {
      return 'local_$uid';
    }
    return uid;
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
        // Sync check for signed in state to prevent login screen flash on Android/iOS/Web
        final firebaseUser = _firebaseAuth.currentUser;
        if (firebaseUser != null) {
          _currentUser = User(
            id: firebaseUser.uid,
            email: firebaseUser.email ?? '',
            displayName: firebaseUser.displayName,
            photoUrl: firebaseUser.photoURL,
            createdAt: DateTime.now(),
            lastSignIn: DateTime.now(),
            emailVerified: firebaseUser.emailVerified,
          );

          // Asynchronously fetch complete user data
          _loadUserData(firebaseUser.uid).catchError((_) {
            // Silently handle get user error
          });
        } else if (kIsWeb) {
          // On Web, wait a short moment for Firebase to restore session
          // before assuming the user is logged out.
          Future.delayed(const Duration(milliseconds: 500), () {
            if (!_isInitialized && _firebaseAuth.currentUser == null) {
              _onAuthStateChanged(null);
            }
          });
        }

        _firebaseAuth.authStateChanges().listen(_onAuthStateChanged);
      } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
        // Sync check for signed in state to prevent login screen flash
        bool isSignedIn = false;
        try {
          isSignedIn = _firedartAuth.isSignedIn;
        } catch (e) {
          if (kDebugMode) {
            debugPrint('Firedart check signed in failed: $e');
          }
        }

        if (isSignedIn) {
          _currentUser = User(
            id: _firedartAuth.userId,
            email: '',
            displayName: null,
            createdAt: DateTime.now(),
            lastSignIn: DateTime.now(),
            emailVerified: true,
          );

          // Asynchronously fetch complete user data
          _firedartAuth.getUser().then((fdUser) {
            _onFiredartAuthChanged(fdUser);
          }).catchError((_) {
            // Silently handle get user error
          });
        } else {
          // Mark as initialized if not signed in
          _isInitialized = true;
          notifyListeners();
        }

        // Listen to Firedart auth changes
        try {
          _firedartAuth.signInState.listen((signedIn) async {
            if (signedIn) {
              final fdUser = await _firedartAuth.getUser();
              _onFiredartAuthChanged(fdUser);
            } else {
              _onFiredartAuthChanged(null);
            }
          });
        } catch (e) {
          if (kDebugMode) {
            debugPrint('Firedart listen failed: $e');
          }
          _isInitialized = true;
          notifyListeners();
        }
      } else {
        // Local-only mode or platform not supported
        _isInitialized = true;
        notifyListeners();
      }
    } catch (e) {
      // Firebase not initialized
      _isInitialized = true;
      notifyListeners();
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
      _localOnlyMode = prefs.getBool('local_only_mode') ?? false;
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

  Future<void> _saveLocalOnlyMode(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('local_only_mode', enabled);
      _localOnlyMode = enabled;
      notifyListeners();
    } catch (e) {
      debugPrint('Error saving local-only preference: $e');
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
      // Handle Linux fallback
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
        await _firedartAuth.signIn(email.trim(), password);
        final fdUser = await _firedartAuth.getUser();

        // Load full user data from Firestore using Firedart
        await _loadUserData(fdUser.id);

        _isGuestMode = false;
        _setLoading(false);
        notifyListeners();
        return true;
      }

      // Attempt Firebase sign in
      final credential = await _firebaseAuth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      // Load user data from Firestore
      if (credential.user != null) {
        _isGuestMode = false;
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
      // Firedart errors might come here
      _setError(
        e.toString().contains('INVALID_PASSWORD')
            ? 'Incorrect password.'
            : 'An unexpected error occurred. Please try again.',
      );
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
      // Handle Linux fallback
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
        await _firedartAuth.signUp(email.trim(), password);
        final fdUser = await _firedartAuth.getUser();

        // Create user object for Firestore
        final user = User(
          id: fdUser.id,
          email: email.trim(),
          displayName: displayName,
          createdAt: DateTime.now(),
          lastSignIn: DateTime.now(),
          emailVerified: true, // Firedart fallback
        );

        // Save to Firestore via Firedart
        final fdFirestore = fd.Firestore.instance;
        await fdFirestore
            .collection('users')
            .document(fdUser.id)
            .set(user.toJson());

        _currentUser = user;
        notifyListeners();

        _setLoading(false);
        return true;
      }

      // Create Firebase Auth account
      final credential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      if (credential.user != null) {
        _isGuestMode = false;
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
      _setError('Registration failed. Please try again: $e');
      _setLoading(false);
      return false;
    }
  }

  /// Sign in as guest (local-only mode)
  Future<void> signInAsGuest() async {
    await _startGuestSession();
  }

  /// Continue without sync while keeping the current local workspace.
  Future<void> continueAsGuest({String? workspaceId}) async {
    _setLoading(true);
    _clearError();

    try {
      if (!_isGuestMode) {
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
          _firedartAuth.signOut();
        } else {
          await _firebaseAuth.signOut();
        }
      }

      await _startGuestSession(workspaceId: workspaceId, setLoading: false);
    } catch (e) {
      _setError('Failed to continue in guest mode.');
      _setLoading(false);
    }
  }

  Future<void> _startGuestSession({
    String? workspaceId,
    bool setLoading = true,
  }) async {
    if (setLoading) {
      _setLoading(true);
      _clearError();
    }

    try {
      // Generate a guest user ID
      final guestId = workspaceId ?? 'guest_${_uuid.v4()}';

      // Create a guest user object
      _currentUser = User(
        id: guestId,
        email: 'guest@local',
        displayName: 'Guest',
        createdAt: DateTime.now(),
        lastSignIn: DateTime.now(),
        emailVerified: false,
      );

      _isGuestMode = true;
      _isInitialized = true;
      _setLoading(false);
      notifyListeners();
    } catch (e) {
      _setError('Failed to sign in as guest.');
      _setLoading(false);
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

  /// Toggle isolated local workspace mode for logged-in users.
  Future<void> setLocalOnlyMode(bool enabled) async {
    if (_isGuestMode) {
      return;
    }
    await _saveLocalOnlyMode(enabled);
  }

  /// Sign out the current user
  Future<void> signOut() async {
    _setLoading(true);

    try {
      if (!_isGuestMode) {
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
          _firedartAuth.signOut();
        } else {
          await _firebaseAuth.signOut();
        }
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

  /// Send magic link to email
  Future<bool> sendSignInLinkToEmail(String email) async {
    _setLoading(true);
    _clearError();

    try {
      final actionCodeSettings = firebase.ActionCodeSettings(
        url: 'https://typesync-app.web.app/finishSignUp?email=$email',
        handleCodeInApp: true,
        androidPackageName: 'com.khonager.typesync',
        androidMinimumVersion: '1',
        androidInstallApp: true,
      );

      await _firebaseAuth.sendSignInLinkToEmail(
        email: email.trim(),
        actionCodeSettings: actionCodeSettings,
      );

      _setLoading(false);
      return true;
    } on firebase.FirebaseAuthException catch (e) {
      _setError(_mapFirebaseError(e.code));
      _setLoading(false);
      return false;
    } catch (e) {
      _setError('Failed to send magic link. Please try again.');
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

  /// Reload the authenticated user so email verification and profile data stay fresh.
  Future<bool> refreshCurrentUser() async {
    if (_currentUser == null || _isGuestMode) {
      return false;
    }

    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
        final fdUser = await _firedartAuth.getUser();
        await _onFiredartAuthChanged(fdUser);
        return true;
      }

      final firebaseUser = _firebaseAuth.currentUser;
      if (firebaseUser == null) {
        return false;
      }

      await firebaseUser.reload();
      final reloadedUser = _firebaseAuth.currentUser;
      if (reloadedUser == null) {
        return false;
      }

      await _loadUserData(reloadedUser.uid, firebaseUser: reloadedUser);
      return true;
    } catch (e) {
      _setError('Failed to refresh account details.');
      return false;
    }
  }

  /// Delete the authenticated account and its cloud data.
  Future<bool> deleteAccount() async {
    if (_currentUser == null || _isGuestMode) {
      _setError('No signed-in account to delete.');
      return false;
    }

    _setLoading(true);
    _clearError();

    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
        _setError('Account deletion is not supported on Linux yet.');
        _setLoading(false);
        return false;
      }

      final firebaseUser = _firebaseAuth.currentUser;
      if (firebaseUser == null) {
        _setError('No signed-in account to delete.');
        _setLoading(false);
        return false;
      }

      final uid = firebaseUser.uid;

      await _deleteUserCollection('notes', uid);
      await _deleteUserCollection('folders', uid);
      await _deleteUserCollection('homework', uid);
      await _deleteUserCollection('calendar_events', uid);
      await _deleteUserCollection('timetable_entries', uid);
      await _firebaseFirestore
          .collection('settings')
          .doc(uid)
          .delete()
          .catchError((_) {});
      await _firebaseFirestore
          .collection('users')
          .doc(uid)
          .delete()
          .catchError((_) {});
      await _deleteUserStorageFolder(uid);
      await firebaseUser.delete();

      _currentUser = null;
      _isGuestMode = false;
      _setLoading(false);
      notifyListeners();
      return true;
    } on firebase.FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        _setError('Please sign in again before deleting your account.');
      } else {
        _setError(_mapFirebaseError(e.code));
      }
      _setLoading(false);
      return false;
    } catch (e) {
      _setError('Failed to delete account. Please try again.');
      _setLoading(false);
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
      // Handle Linux fallback
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
        final fdFirestore = fd.Firestore.instance;
        final updates = <String, dynamic>{};
        if (displayName != null) updates['displayName'] = displayName;
        if (photoUrl != null) updates['photoUrl'] = photoUrl;

        await fdFirestore
            .collection('users')
            .document(_currentUser!.id)
            .update(updates);

        // Update local user
        _currentUser = _currentUser!.copyWith(
          displayName: displayName ?? _currentUser!.displayName,
          photoUrl: photoUrl ?? _currentUser!.photoUrl,
        );

        notifyListeners();
        _setLoading(false);
        return true;
      }

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
      _setError('Failed to update profile: $e');
      _setLoading(false);
      return false;
    }
  }

  // ===========================================
  // PRIVATE METHODS
  // ===========================================

  bool _webInitialized = false;

  /// Handle auth state changes
  Future<void> _onAuthStateChanged(firebase.User? firebaseUser) async {
    if (firebaseUser != null) {
      _isGuestMode = false;
      await _loadUserData(firebaseUser.uid);
      _isInitialized = true;
      notifyListeners();
    } else if (firebaseUser == null && !_isGuestMode) {
      if (kIsWeb && !_webInitialized) {
        // Skip the first null event on Web to allow for session restoration delay
        _webInitialized = true;
        return;
      }
      // Only clear user if not in guest mode
      _currentUser = null;
      _isInitialized = true;
      notifyListeners();
    }
  }

  /// Load user data from Firestore
  Future<void> _loadUserData(String uid, {firebase.User? firebaseUser}) async {
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
        final fdFirestore = fd.Firestore.instance;
        final doc = await fdFirestore.collection('users').document(uid).get();

        if (doc.map.isNotEmpty) {
          _currentUser = User.fromJson(doc.map);

          // Update last sign in
          await fdFirestore.collection('users').document(uid).update({
            'lastSignIn': DateTime.now().toIso8601String(),
          });
        } else {
          // Create user document if it doesn't exist
          final fdUser = await _firedartAuth.getUser();
          final user = User(
            id: uid,
            email: fdUser.email!,
            displayName: fdUser.displayName,
            createdAt: DateTime.now(),
            lastSignIn: DateTime.now(),
            emailVerified: true,
          );

          await fdFirestore
              .collection('users')
              .document(uid)
              .set(user.toJson());
          _currentUser = user;
        }
      } else {
        final doc = await _firebaseFirestore.collection('users').doc(uid).get();
        final activeFirebaseUser = firebaseUser ?? _firebaseAuth.currentUser;

        if (doc.exists) {
          final firestoreUser = User.fromJson(doc.data()!);
          final emailVerified =
              activeFirebaseUser?.emailVerified ?? firestoreUser.emailVerified;

          _currentUser = firestoreUser.copyWith(
            email: activeFirebaseUser?.email ?? firestoreUser.email,
            displayName:
                activeFirebaseUser?.displayName ?? firestoreUser.displayName,
            photoUrl: activeFirebaseUser?.photoURL ?? firestoreUser.photoUrl,
            emailVerified: emailVerified,
          );

          // Update last sign in
          await _firebaseFirestore.collection('users').doc(uid).update({
            'lastSignIn': DateTime.now().toIso8601String(),
            'emailVerified': emailVerified,
            'email': activeFirebaseUser?.email ?? firestoreUser.email,
            'displayName':
                activeFirebaseUser?.displayName ?? firestoreUser.displayName,
            'photoUrl': activeFirebaseUser?.photoURL ?? firestoreUser.photoUrl,
          });
        } else {
          // Create user document if it doesn't exist (e.g., after auth migration)
          final firebaseUser = activeFirebaseUser!;
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
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Error loading user data: $e');
    }
  }

  Future<void> _onFiredartAuthChanged(fd.User? fdUser) async {
    if (fdUser != null && !_isGuestMode) {
      _currentUser = User(
        id: fdUser.id,
        email: fdUser.email ?? '',
        displayName: fdUser.displayName,
        createdAt: DateTime.now(),
        lastSignIn: DateTime.now(),
        emailVerified: true,
      );
    } else if (fdUser == null && !_isGuestMode) {
      _currentUser = null;
    }
    _isInitialized = true;
    notifyListeners();
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
      case 'requires-recent-login':
        return 'Please sign in again to continue.';
      default:
        return 'Authentication failed. Please try again.';
    }
  }

  Future<void> _deleteUserCollection(String collectionName, String userId) async {
    while (true) {
      final snapshot = await _firebaseFirestore
          .collection(collectionName)
          .where('userId', isEqualTo: userId)
          .limit(100)
          .get();

      if (snapshot.docs.isEmpty) {
        break;
      }

      final batch = _firebaseFirestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }

  Future<void> _deleteUserStorageFolder(String userId) async {
    final rootRef = FirebaseStorage.instance.ref().child('users/$userId');
    await _deleteStorageFolder(rootRef);
  }

  Future<void> _deleteStorageFolder(Reference ref) async {
    final result = await ref.listAll();

    for (final item in result.items) {
      await item.delete();
    }

    for (final prefix in result.prefixes) {
      await _deleteStorageFolder(prefix);
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
