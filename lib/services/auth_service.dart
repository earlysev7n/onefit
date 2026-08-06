import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<UserCredential?> signIn(String email, String password) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<UserCredential?> register(String email, String password) async {
    try {
      return await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } catch (e) {
      rethrow;
    }
  }

  /// Google sign-in via Firebase. Returns null if the user cancels the flow.
  ///
  /// Requires the Firebase project to have the Google provider enabled and the
  /// app's SHA-1 fingerprint registered (see README/setup notes); without that
  /// native config this throws a FirebaseAuthException at runtime.
  Future<UserCredential?> signInWithGoogle() async {
    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) return null; // user dismissed the picker

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    return await _auth.signInWithCredential(credential);
  }

  /// Sends a password-reset email. Firebase handles delivery; no backend needed.
  Future<void> sendPasswordReset(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  Future<void> signOut() async {
    await GoogleSignIn().signOut();
    await _auth.signOut();
  }

  User? get currentUser => _auth.currentUser;

  Future<void> changePassword(String currentPassword, String newPassword) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) throw Exception('Not signed in');
    final cred = EmailAuthProvider.credential(
      email: user.email!,
      password: currentPassword,
    );
    await user.reauthenticateWithCredential(cred);
    await user.updatePassword(newPassword);
  }

  /// Maps auth errors to plain, user-facing sentences. Falls back to a generic
  /// message so raw Firebase exception text never reaches the UI.
  static String authErrorMessage(Object e) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'invalid-credential':
        case 'wrong-password':
        case 'user-not-found':
          return 'Incorrect email or password.';
        case 'invalid-email':
          return 'That email address doesn\'t look right.';
        case 'user-disabled':
          return 'This account has been disabled.';
        case 'email-already-in-use':
          return 'An account with this email already exists.';
        case 'weak-password':
          return 'Please choose a stronger password (at least 6 characters).';
        case 'operation-not-allowed':
          return 'This sign-in method isn\'t enabled yet.';
        case 'network-request-failed':
          return 'No internet connection. Check your network and try again.';
        case 'too-many-requests':
          return 'Too many attempts. Please wait a moment and try again.';
        case 'account-exists-with-different-credential':
          return 'This email is already linked to a different sign-in method.';
        default:
          return 'Something went wrong. Please try again.';
      }
    }
    return 'Something went wrong. Please try again.';
  }
}
