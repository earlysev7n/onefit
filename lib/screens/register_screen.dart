import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../widgets/auth_input_decoration.dart';
import '../widgets/social_auth_button.dart';
import '../widgets/or_divider.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String? _emailValidator(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Enter your email address';
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailRegex.hasMatch(v)) return 'Enter a valid email address';
    return null;
  }

  String? _passwordValidator(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Choose a password';
    if (v.length < 6) return 'At least 6 characters';
    return null;
  }

  String? _confirmValidator(String? value) {
    if ((value ?? '').isEmpty) return 'Re-enter your password';
    if (value != _passwordController.text) return 'Passwords do not match';
    return null;
  }

  Future<void> _register() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      await AuthService().register(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      _showError(AuthService.authErrorMessage(e));
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isGoogleLoading = true);
    try {
      await AuthService().signInWithGoogle();
      // Null result = user cancelled the picker; AuthGate handles success.
    } catch (e) {
      _showError(AuthService.authErrorMessage(e));
    }
    if (!mounted) return;
    setState(() => _isGoogleLoading = false);
  }

  void _showLegalDialog(String title) {
    final c = context.colors;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          style: GoogleFonts.spaceGrotesk(
            fontWeight: FontWeight.w700,
            color: c.onBackground,
          ),
        ),
        content: Text(
          'The full $title will be available here soon.',
          style: GoogleFonts.inter(color: c.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final anyLoading = _isLoading || _isGoogleLoading;
    return Scaffold(
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
                            Text(
                              'Create account',
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 32,
                                fontWeight: FontWeight.w700,
                                color: c.onBackground,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Start your fitness journey',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                color: c.muted,
                              ),
                            ),
                            const SizedBox(height: 40),
                            TextFormField(
                              controller: _emailController,
                              style: TextStyle(color: c.onBackground),
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              validator: _emailValidator,
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
                              textInputAction: TextInputAction.next,
                              validator: _passwordValidator,
                              decoration: authInputDecoration(
                                context,
                                label: 'Password',
                                hint: 'At least 6 characters',
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
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _confirmPasswordController,
                              obscureText: _obscureConfirm,
                              style: TextStyle(color: c.onBackground),
                              textInputAction: TextInputAction.done,
                              validator: _confirmValidator,
                              onFieldSubmitted: (_) => _register(),
                              decoration: authInputDecoration(
                                context,
                                label: 'Confirm Password',
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscureConfirm
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                    color: c.muted,
                                  ),
                                  onPressed: () => setState(
                                    () => _obscureConfirm = !_obscureConfirm,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              height: 54,
                              child: ElevatedButton(
                                onPressed: anyLoading ? null : _register,
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
                                        'Create Account',
                                        style: GoogleFonts.spaceGrotesk(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _TermsConsent(onTap: _showLegalDialog),
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
                                    : () => Navigator.pop(context),
                                child: Text(
                                  'Already have an account? Sign in',
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

/// "By creating an account you agree to our Terms / Privacy Policy" line, with
/// the two phrases tappable. Placeholder dialogs until real URLs are provided.
class _TermsConsent extends StatelessWidget {
  const _TermsConsent({required this.onTap});

  final void Function(String title) onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final base = GoogleFonts.inter(fontSize: 12, color: c.muted, height: 1.4);
    final link = base.copyWith(
      color: AppColors.primary,
      fontWeight: FontWeight.w600,
    );

    return Text.rich(
      TextSpan(
        style: base,
        children: [
          const TextSpan(text: 'By creating an account you agree to our '),
          _linkSpan('Terms of Service', link, () => onTap('Terms of Service')),
          const TextSpan(text: ' and '),
          _linkSpan('Privacy Policy', link, () => onTap('Privacy Policy')),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }

  TextSpan _linkSpan(String text, TextStyle style, VoidCallback onTap) {
    return TextSpan(
      text: text,
      style: style,
      recognizer: TapGestureRecognizer()..onTap = onTap,
    );
  }
}
