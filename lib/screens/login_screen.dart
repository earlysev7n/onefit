import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'register_screen.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../widgets/auth_input_decoration.dart';
import '../widgets/social_auth_button.dart';
import '../widgets/or_divider.dart';

/// Shared email format check used by the login form and the reset dialog.
String? validateEmail(String? value) {
  final v = (value ?? '').trim();
  if (v.isEmpty) return 'Enter your email address';
  final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  if (!emailRegex.hasMatch(v)) return 'Enter a valid email address';
  return null;
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _signIn() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      await AuthService().signIn(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );
      // AuthGate handles navigation on success.
    } catch (e) {
      _showSnack(AuthService.authErrorMessage(e));
    }
    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isGoogleLoading = true);
    try {
      await AuthService().signInWithGoogle();
      // Null result = user cancelled the picker; AuthGate handles success.
    } catch (e) {
      _showSnack(AuthService.authErrorMessage(e));
    }
    if (!mounted) return;
    setState(() => _isGoogleLoading = false);
  }

  Future<void> _openResetDialog() async {
    final sent = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _ResetPasswordDialog(initialEmail: _emailController.text.trim()),
    );
    if (sent == true) {
      _showSnack(
        "If an account exists for that email, you'll get a reset link. "
        'Check your inbox and spam.',
      );
    }
  }

  String? _passwordValidator(String? value) {
    if ((value ?? '').isEmpty) return 'Enter your password';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final anyLoading = _isLoading || _isGoogleLoading;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 32,
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Center(
                              child: Image.asset('assets/images/logo2.png'),
                            ),
                            const SizedBox(height: 28),
                            Text(
                              'Welcome back',
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 32,
                                fontWeight: FontWeight.w700,
                                color: c.onBackground,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Sign in to continue',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                color: c.muted,
                              ),
                            ),
                            const SizedBox(height: 32),
                            TextFormField(
                              controller: _emailController,
                              style: TextStyle(color: c.onBackground),
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              validator: validateEmail,
                              decoration: authInputDecoration(
                                context,
                                label: 'Email',
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              style: TextStyle(color: c.onBackground),
                              textInputAction: TextInputAction.done,
                              validator: _passwordValidator,
                              onFieldSubmitted: (_) => _signIn(),
                              decoration: authInputDecoration(
                                context,
                                label: 'Password',
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                    color: c.muted,
                                  ),
                                  onPressed: () => setState(
                                    () => _obscurePassword = !_obscurePassword,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: anyLoading ? null : _openResetDialog,
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(
                                  'Forgot password?',
                                  style: GoogleFonts.inter(
                                    color: AppColors.primary,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              height: 54,
                              child: ElevatedButton(
                                onPressed: anyLoading ? null : _signIn,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: c.onPrimary,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: _isLoading
                                    ? CircularProgressIndicator(
                                        color: c.onPrimary,
                                      )
                                    : Text(
                                        'Sign In',
                                        style: GoogleFonts.spaceGrotesk(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            const OrDivider(),
                            const SizedBox(height: 20),
                            GoogleSignInButton(
                              onPressed: anyLoading ? null : _signInWithGoogle,
                              isLoading: _isGoogleLoading,
                            ),
                            const SizedBox(height: 8),
                            Center(
                              child: TextButton(
                                onPressed: anyLoading
                                    ? null
                                    : () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const RegisterScreen(),
                                        ),
                                      ),
                                child: Text(
                                  'Don\'t have an account? Sign up',
                                  style: GoogleFonts.inter(
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Password-reset dialog. Owns its controller/form key and disposes them in
/// [dispose] (avoids the manual-dispose-after-showDialog race that crashed with
/// `_dependents.isEmpty`). Pops `true` when a reset has been requested,
/// or `null`/`false` on cancel.
class _ResetPasswordDialog extends StatefulWidget {
  const _ResetPasswordDialog({required this.initialEmail});

  final String initialEmail;

  @override
  State<_ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<_ResetPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialEmail,
  );
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await AuthService().sendPasswordReset(_controller.text.trim());
      if (!mounted) return;
      Navigator.pop(context, true);
    } on FirebaseAuthException catch (e) {
      // Neutral by design: never reveal whether the email is registered
      // (enumeration protection). A missing account is reported the same as a
      // successful send; only genuine failures (network, rate-limit) surface.
      if (e.code == 'user-not-found') {
        if (!mounted) return;
        Navigator.pop(context, true);
        return;
      }
      setState(() {
        _sending = false;
        _error = AuthService.authErrorMessage(e);
      });
    } catch (e) {
      setState(() {
        _sending = false;
        _error = AuthService.authErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AlertDialog(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        'Reset password',
        style: GoogleFonts.spaceGrotesk(
          fontWeight: FontWeight.w700,
          color: c.onBackground,
        ),
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter your email and we\'ll send you a link to reset your password.',
              style: GoogleFonts.inter(fontSize: 14, color: c.muted),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _controller,
              style: TextStyle(color: c.onBackground),
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              validator: validateEmail,
              onFieldSubmitted: (_) => _sending ? null : _send(),
              decoration: authInputDecoration(context, label: 'Email'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppColors.overTarget,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.pop(context, false),
          child: Text('Cancel', style: TextStyle(color: c.muted)),
        ),
        ElevatedButton(
          onPressed: _sending ? null : _send,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: c.onPrimary,
          ),
          child: _sending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Send link'),
        ),
      ],
    );
  }
}
