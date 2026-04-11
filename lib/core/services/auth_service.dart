/// Authentication Service
///
/// Handles user authentication via Firebase Auth including
/// login, registration, password reset, and session management.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firedart/firedart.dart' as fd;
import 'package:firedart/auth/user_gateway.dart' as fd;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../firebase_options.dart';
import '../models/user.dart';
import 'diagnostics_service.dart';

/// Service for managing user authentication
///
/// Provides methods for sign in, sign up, sign out, and
/// password recovery. Maintains current user state.
class AuthService extends ChangeNotifier {
  static const String customAuthDomain = 'typesync.khonager.de';
  static const String customAuthBaseUrl = 'https://$customAuthDomain';
  static const String finishSignUpPath = '/finishSignUp';
  static const String loginPath = '/login';
  static const String _pendingEmailLinkEmailKey = 'pending_email_link_email';

  final DiagnosticsService _diagnostics = DiagnosticsService.instance;
  final http.Client _httpClient = http.Client();

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
  String? _guestWorkspaceId;
  String? _pendingGuestImportWorkspaceId;
  String? _pendingEmailLinkEmail;

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
  String? get guestWorkspaceId => _guestWorkspaceId;
  String? get pendingGuestImportWorkspaceId => _pendingGuestImportWorkspaceId;
  String? get pendingEmailLinkEmail => _pendingEmailLinkEmail;

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
      _guestWorkspaceId = prefs.getString('guest_workspace_id');
      _pendingGuestImportWorkspaceId =
          prefs.getString('pending_guest_import_workspace_id');
      _pendingEmailLinkEmail = prefs.getString(_pendingEmailLinkEmailKey);

      _diagnostics.info(
        'AuthService',
        'AUTH_FLOW prefs loaded syncEnabled=$_syncEnabled localOnly=$_localOnlyMode guestWorkspace=$_guestWorkspaceId pendingGuestImport=$_pendingGuestImportWorkspaceId pendingEmailLink=$_pendingEmailLinkEmail isAuthenticated=$isAuthenticated',
      );

      if (!isAuthenticated &&
          _guestWorkspaceId != null &&
          _guestWorkspaceId!.isNotEmpty) {
        _diagnostics.info(
          'AuthService',
          'AUTH_FLOW restoring guest workspace=$_guestWorkspaceId from preferences',
        );
        await _startGuestSession(
          workspaceId: _guestWorkspaceId,
          persistWorkspace: false,
        );
        return;
      }

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
    final previousGuestWorkspaceId = _guestWorkspaceId;
    _diagnostics.info(
      'AuthService',
      'AUTH_FLOW signIn requested email=${email.trim()} guestMode=$_isGuestMode previousGuestWorkspace=$previousGuestWorkspaceId',
    );

    try {
      // Handle Linux fallback
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
        await _firedartAuth.signIn(email.trim(), password);
        final fdUser = await _firedartAuth.getUser();

        // Load full user data from Firestore using Firedart
        _isGuestMode = false;
        await _setPendingGuestImportWorkspace(
          previousGuestWorkspaceId,
          fdUser.id,
        );
        await _loadUserData(fdUser.id);

        _diagnostics.info(
          'AuthService',
          'AUTH_FLOW Linux signIn completed user=${fdUser.id} storageUserId=$storageUserId pendingGuestImport=$_pendingGuestImportWorkspaceId',
        );

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
        await _setPendingGuestImportWorkspace(
          previousGuestWorkspaceId,
          credential.user!.uid,
        );
        await _loadUserData(credential.user!.uid);
        _diagnostics.info(
          'AuthService',
          'AUTH_FLOW signIn completed user=${credential.user!.uid} storageUserId=$storageUserId pendingGuestImport=$_pendingGuestImportWorkspaceId',
        );
      }

      _setLoading(false);
      return true;
    } on firebase.FirebaseAuthException catch (e) {
      // Handle specific Firebase auth errors
      _diagnostics.warning(
        'AuthService',
        'AUTH_FLOW signIn failed code=${e.code} message=${e.message ?? 'unknown'} email=${email.trim()}',
      );
      _setError(_mapFirebaseError(e.code));
      _setLoading(false);
      return false;
    } catch (e) {
      // Firedart errors might come here
      _diagnostics.error(
        'AuthService',
        'AUTH_FLOW signIn unexpected failure email=${email.trim()} error=$e',
      );
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
    final previousGuestWorkspaceId = _guestWorkspaceId;
    _diagnostics.info(
      'AuthService',
      'AUTH_FLOW register requested email=${email.trim()} guestMode=$_isGuestMode previousGuestWorkspace=$previousGuestWorkspaceId',
    );

    try {
      // Handle Linux fallback
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
        await _firedartAuth.signUp(email.trim(), password);
        final fdUser = await _firedartAuth.getUser();
        _isGuestMode = false;
        await _setPendingGuestImportWorkspace(
          previousGuestWorkspaceId,
          fdUser.id,
        );

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

        _diagnostics.info(
          'AuthService',
          'AUTH_FLOW Linux register completed user=${fdUser.id} storageUserId=$storageUserId pendingGuestImport=$_pendingGuestImportWorkspaceId',
        );

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
        await _setPendingGuestImportWorkspace(
          previousGuestWorkspaceId,
          credential.user!.uid,
        );
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

        _diagnostics.info(
          'AuthService',
          'AUTH_FLOW register completed user=${credential.user!.uid} storageUserId=$storageUserId pendingGuestImport=$_pendingGuestImportWorkspaceId',
        );

        // Send email verification
        await resendVerificationEmail();
      }

      _setLoading(false);
      return true;
    } on firebase.FirebaseAuthException catch (e) {
      _diagnostics.warning(
        'AuthService',
        'AUTH_FLOW register failed code=${e.code} message=${e.message ?? 'unknown'} email=${email.trim()}',
      );
      _setError(_mapFirebaseError(e.code));
      _setLoading(false);
      return false;
    } catch (e) {
      _diagnostics.error(
        'AuthService',
        'AUTH_FLOW register unexpected failure email=${email.trim()} error=$e',
      );
      _setError('Registration failed. Please try again: $e');
      _setLoading(false);
      return false;
    }
  }

  /// Sign in as guest (local-only mode)
  Future<void> signInAsGuest() async {
    _diagnostics.info(
      'AuthService',
      'AUTH_FLOW signInAsGuest requested previousGuestWorkspace=$_guestWorkspaceId',
    );
    await _startGuestSession();
  }

  /// Continue without sync while keeping the current local workspace.
  Future<void> continueAsGuest({String? workspaceId}) async {
    _setLoading(true);
    _clearError();
    _diagnostics.info(
      'AuthService',
      'AUTH_FLOW continueAsGuest requested workspaceOverride=$workspaceId currentUserId=$userId storageUserId=$storageUserId guestMode=$_isGuestMode',
    );

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
    bool persistWorkspace = true,
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
      if (persistWorkspace) {
        await _saveGuestWorkspaceId(guestId);
      }
      _diagnostics.info(
        'AuthService',
        'AUTH_FLOW guest session started workspace=$guestId persistWorkspace=$persistWorkspace pendingGuestImport=$_pendingGuestImportWorkspaceId',
      );
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
      _diagnostics.info(
        'AuthService',
        'AUTH_FLOW requesting password reset email',
      );
      await _postEmailFunction(
        'send_password_reset_email_http',
        {
          'email': email.trim(),
          ..._buildEmailActionPayload(
            path: loginPath,
            handleCodeInApp: false,
            queryParameters: const {'mode': 'resetPassword'},
          ),
        },
      );
      _setLoading(false);
      return true;
    } catch (e) {
      _diagnostics.error(
        'AuthService',
        'AUTH_FLOW password reset email failed: $e',
      );
      _setError(_mapEmailFunctionError(e));
      _setLoading(false);
      return false;
    }
  }

  /// Send magic link to email
  Future<bool> sendSignInLinkToEmail(String email) async {
    _setLoading(true);
    _clearError();

    try {
      final normalizedEmail = email.trim();
      await _savePendingEmailLinkEmail(normalizedEmail);
      await _postEmailFunction(
        'send_sign_in_link_email_http',
        {
          'email': normalizedEmail,
          ..._buildEmailActionPayload(
            path: finishSignUpPath,
            handleCodeInApp: true,
            queryParameters: {'email': normalizedEmail},
          ),
        },
      );

      _setLoading(false);
      return true;
    } catch (e) {
      _setError(_mapEmailFunctionError(e));
      _setLoading(false);
      return false;
    }
  }

  /// Resend email verification
  Future<bool> resendVerificationEmail() async {
    _setLoading(true);
    _clearError();

    try {
      final idToken = await _currentIdToken();
      if (idToken == null || idToken.isEmpty) {
        _setError('You need to be signed in to verify your email.');
        _setLoading(false);
        return false;
      }

      _diagnostics.info(
        'AuthService',
        'AUTH_FLOW requesting verification email delivery',
      );

      await _postEmailFunction(
        'send_verification_email_http',
        _buildEmailActionPayload(
          path: loginPath,
          handleCodeInApp: false,
          queryParameters: const {'mode': 'verifyEmail'},
        ),
        idToken: idToken,
      );
      _setLoading(false);
      return true;
    } catch (e) {
      _diagnostics.error(
        'AuthService',
        'AUTH_FLOW verification email delivery failed: $e',
      );
      _setError(_mapEmailFunctionError(e));
      _setLoading(false);
      return false;
    }
  }

  bool isSignInLink(String emailLink) {
    if (!kIsWeb) {
      return false;
    }

    return _firebaseAuth.isSignInWithEmailLink(emailLink);
  }

  Future<bool> completeSignInWithEmailLink({
    required String email,
    String? emailLink,
  }) async {
    _setLoading(true);
    _clearError();

    try {
      final normalizedEmail = email.trim();
      final resolvedEmailLink =
          emailLink ?? (kIsWeb ? Uri.base.toString() : '');

      if (resolvedEmailLink.isEmpty || !isSignInLink(resolvedEmailLink)) {
        _setError('This sign-in link is invalid or has expired.');
        _setLoading(false);
        return false;
      }

      final previousGuestWorkspaceId = _guestWorkspaceId;
      final credential = await _firebaseAuth.signInWithEmailLink(
        email: normalizedEmail,
        emailLink: resolvedEmailLink,
      );

      if (credential.user != null) {
        _isGuestMode = false;
        await _setPendingGuestImportWorkspace(
          previousGuestWorkspaceId,
          credential.user!.uid,
        );
        await _loadUserData(
          credential.user!.uid,
          firebaseUser: credential.user,
        );
      }

      await _clearPendingEmailLinkEmail();
      _setLoading(false);
      return true;
    } on firebase.FirebaseAuthException catch (e) {
      _setError(_mapFirebaseError(e.code));
      _setLoading(false);
      return false;
    } catch (e) {
      _setError('Failed to complete email sign-in. Please try again.');
      _setLoading(false);
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
    _diagnostics.info(
      'AuthService',
      'AUTH_FLOW firebase auth state changed user=${firebaseUser?.uid} guestMode=$_isGuestMode initialized=$_isInitialized',
    );
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
      _diagnostics.info(
        'AuthService',
        'AUTH_FLOW loading user data uid=$uid platform=${defaultTargetPlatform.name}',
      );
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
      _diagnostics.info(
        'AuthService',
        'AUTH_FLOW user data loaded uid=$uid currentUser=${_currentUser?.id} storageUserId=$storageUserId guestMode=$_isGuestMode',
      );
    } catch (e) {
      debugPrint('Error loading user data: $e');
    }
  }

  Future<void> _onFiredartAuthChanged(fd.User? fdUser) async {
    _diagnostics.info(
      'AuthService',
      'AUTH_FLOW firedart auth state changed user=${fdUser?.id} guestMode=$_isGuestMode initialized=$_isInitialized',
    );
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
      case 'invalid-credential':
      case 'invalid-login-credentials':
        return 'Email or password is incorrect.';
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

  Future<void> _deleteUserCollection(
    String collectionName,
    String userId,
  ) async {
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

  firebase.ActionCodeSettings _buildActionCodeSettings({
    required String path,
    required bool handleCodeInApp,
    Map<String, String>? queryParameters,
  }) {
    final uri = Uri.parse(customAuthBaseUrl).replace(
      path: path,
      queryParameters: queryParameters,
    );

    return firebase.ActionCodeSettings(
      url: uri.toString(),
      handleCodeInApp: handleCodeInApp,
      linkDomain: customAuthDomain,
      androidPackageName: 'de.khonager.typesync',
      androidMinimumVersion: '1',
      androidInstallApp: handleCodeInApp,
      iOSBundleId: DefaultFirebaseOptions.ios.iosBundleId,
    );
  }

  Map<String, dynamic> _buildEmailActionPayload({
    required String path,
    required bool handleCodeInApp,
    Map<String, String>? queryParameters,
  }) {
    final settings = _buildActionCodeSettings(
      path: path,
      handleCodeInApp: handleCodeInApp,
      queryParameters: queryParameters,
    );

    return {
      'url': settings.url,
      'handleCodeInApp': settings.handleCodeInApp,
      'linkDomain': customAuthDomain,
      'androidPackageName': settings.androidPackageName,
      'androidMinimumVersion': settings.androidMinimumVersion,
      'androidInstallApp': settings.androidInstallApp,
      'iOSBundleId': settings.iOSBundleId,
    };
  }

  Uri _functionUri(String functionName) {
    return Uri.https(
      'us-central1-${DefaultFirebaseOptions.currentPlatform.projectId}.cloudfunctions.net',
      functionName,
    );
  }

  Future<void> _postEmailFunction(
    String functionName,
    Map<String, dynamic> payload, {
    String? idToken,
  }) async {
    final uri = _functionUri(functionName);
    _diagnostics.info(
      'AuthService',
      'AUTH_FLOW posting email function=$functionName uri=$uri',
    );

    late http.Response response;
    try {
      response = await _httpClient
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              if (idToken != null && idToken.isNotEmpty)
                'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw Exception(
        'The email service took too long to respond. Please try again.',
      );
    } on http.ClientException {
      throw Exception(
        'Unable to reach the email service. Check your internet connection and try again.',
      );
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      _diagnostics.info(
        'AuthService',
        'AUTH_FLOW email function succeeded function=$functionName status=${response.statusCode}',
      );
      return;
    }

    final extractedError = _extractFunctionError(response);
    _diagnostics.warning(
      'AuthService',
      'AUTH_FLOW email function failed function=$functionName status=${response.statusCode} error=$extractedError',
    );
    throw Exception(extractedError);
  }

  String _extractFunctionError(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic>) {
        final error = body['error'];
        if (error is String && error.isNotEmpty) {
          return error;
        }
      }
    } catch (_) {
      // Fall back to the raw body when the response is not JSON.
    }

    if (response.body.isNotEmpty) {
      return response.body;
    }

    return 'HTTP ${response.statusCode}';
  }

  String _mapEmailFunctionError(Object error) {
    final message = error.toString();
    final normalized = message.startsWith('Exception: ')
        ? message.substring('Exception: '.length)
        : message;

    if (normalized.contains('Invalid email address')) {
      return 'Invalid email address.';
    }
    if (normalized.contains('Authenticated user email is required')) {
      return 'You need to be signed in to verify your email.';
    }
    if (normalized.contains('Missing bearer token') ||
        normalized.contains('Invalid auth token')) {
      return 'Your session expired. Please sign in again and try again.';
    }
    if (normalized.contains('Unable to reach the email service')) {
      return 'Unable to reach the email service. Check your internet connection and try again.';
    }
    if (normalized.contains('took too long to respond')) {
      return 'The email service took too long to respond. Please try again.';
    }
    if (normalized.contains('Failed to send sign-in email')) {
      return 'Failed to send magic link. Please try again.';
    }
    if (normalized.contains('Failed to create sign-in email')) {
      return 'Failed to send magic link. Please try again.';
    }
    if (normalized.contains('Failed to send password reset email')) {
      return 'Failed to send reset email. Please try again.';
    }
    if (normalized.contains('Failed to create password reset email')) {
      return 'Failed to send reset email. Please try again.';
    }
    if (normalized.contains('Failed to send verification email')) {
      return 'Failed to send verification email. Please try again.';
    }

    return normalized;
  }

  Future<String?> _currentIdToken() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
      if (!fd.FirebaseAuth.initialized || !_firedartAuth.isSignedIn) {
        return null;
      }
      return _firedartAuth.tokenProvider.idToken;
    }

    return _firebaseAuth.currentUser?.getIdToken();
  }

  Future<void> _savePendingEmailLinkEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingEmailLinkEmailKey, email);
    _pendingEmailLinkEmail = email;
    notifyListeners();
  }

  Future<void> _clearPendingEmailLinkEmail() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingEmailLinkEmailKey);
    _pendingEmailLinkEmail = null;
    notifyListeners();
  }

  Future<void> clearPendingGuestImportWorkspace() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pending_guest_import_workspace_id');
    _pendingGuestImportWorkspaceId = null;
    _diagnostics.info(
      'AuthService',
      'AUTH_FLOW cleared pending guest import workspace',
    );
    notifyListeners();
  }

  Future<void> clearGuestWorkspaceId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('guest_workspace_id');
    _guestWorkspaceId = null;
    _diagnostics.info(
      'AuthService',
      'AUTH_FLOW cleared guest workspace preference',
    );
    notifyListeners();
  }

  Future<void> _saveGuestWorkspaceId(String workspaceId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('guest_workspace_id', workspaceId);
    _guestWorkspaceId = workspaceId;
    _diagnostics.info(
      'AuthService',
      'AUTH_FLOW saved guest workspace workspace=$workspaceId',
    );
  }

  Future<void> _setPendingGuestImportWorkspace(
    String? workspaceId,
    String targetUserId,
  ) async {
    if (workspaceId == null ||
        workspaceId.isEmpty ||
        workspaceId == targetUserId) {
      _diagnostics.info(
        'AuthService',
        'AUTH_FLOW skipped pending guest import workspace=$workspaceId targetUser=$targetUserId',
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pending_guest_import_workspace_id', workspaceId);
    _pendingGuestImportWorkspaceId = workspaceId;
    _diagnostics.info(
      'AuthService',
      'AUTH_FLOW set pending guest import workspace=$workspaceId targetUser=$targetUserId',
    );
  }
}
