/// Authentication Service
/// 
/// Handles user authentication via Firebase Auth including
/// login, registration, password reset, and session management.

import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase;
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user.dart';

/// Service for managing user authentication
/// 
/// Provides methods for sign in, sign up, sign out, and
/// password recovery. Maintains current user state.
class AuthService extends ChangeNotifier {
  // Firebase Auth instance
  final firebase.FirebaseAuth _auth = firebase.FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Current user data
  User? _currentUser;
  
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
  
  /// Whether a user is currently authenticated
  bool get isAuthenticated => _currentUser != null;
  
  /// Loading state for async operations
  bool get isLoading => _isLoading;
  
  /// Current error message (null if no error)
  String? get errorMessage => _errorMessage;
  
  /// Whether there's an active error
  bool get hasError => _hasError;
  
  /// Firebase user ID (for sync operations)
  String? get userId => _auth.currentUser?.uid;

  // ===========================================
  // CONSTRUCTOR
  // ===========================================
  
  AuthService() {
    // Listen to auth state changes
    _auth.authStateChanges().listen(_onAuthStateChanged);
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
      final credential = await _auth.signInWithEmailAndPassword(
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
      final credential = await _auth.createUserWithEmailAndPassword(
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
        
        await _firestore
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

  /// Sign out the current user
  Future<void> signOut() async {
    _setLoading(true);
    
    try {
      await _auth.signOut();
      _currentUser = null;
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
      await _auth.sendPasswordResetEmail(email: email.trim());
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
      await _auth.currentUser?.sendEmailVerification();
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
        await _auth.currentUser?.updateDisplayName(displayName);
      }
      if (photoUrl != null) {
        await _auth.currentUser?.updatePhotoURL(photoUrl);
      }
      
      // Update Firestore document
      final updates = <String, dynamic>{};
      if (displayName != null) updates['displayName'] = displayName;
      if (photoUrl != null) updates['photoUrl'] = photoUrl;
      
      await _firestore
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
    if (firebaseUser != null) {
      await _loadUserData(firebaseUser.uid);
    } else {
      _currentUser = null;
      notifyListeners();
    }
  }

  /// Load user data from Firestore
  Future<void> _loadUserData(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      
      if (doc.exists) {
        _currentUser = User.fromJson(doc.data()!);
        
        // Update last sign in
        await _firestore.collection('users').doc(uid).update({
          'lastSignIn': DateTime.now().toIso8601String(),
        });
      } else {
        // Create user document if it doesn't exist (e.g., after auth migration)
        final firebaseUser = _auth.currentUser!;
        final user = User(
          id: uid,
          email: firebaseUser.email!,
          displayName: firebaseUser.displayName,
          photoUrl: firebaseUser.photoURL,
          createdAt: DateTime.now(),
          lastSignIn: DateTime.now(),
          emailVerified: firebaseUser.emailVerified,
        );
        
        await _firestore.collection('users').doc(uid).set(user.toJson());
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

