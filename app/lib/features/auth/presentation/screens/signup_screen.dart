import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/validators.dart';
import '../providers/auth_provider.dart';

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _handleSignUp() async {
    if (!_formKey.currentState!.validate()) return;

    ref.read(authNotifierProvider.notifier).clearError();

    final outcome = await ref.read(authNotifierProvider.notifier).signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          name: _nameController.text.trim(),
          phone: _phoneController.text.trim(),
        );

    if (mounted) {
      if (outcome == SignUpOutcome.authenticated) {
        context.go(RouteNames.dashboard);
      } else if (outcome == SignUpOutcome.needsEmailConfirmation) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Registration successful! Please check your email to confirm your account.'),
            backgroundColor: AppColors.success,
            duration: Duration(seconds: 5),
          ),
        );
        context.go(RouteNames.login);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final size = MediaQuery.sizeOf(context);

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.primary, AppColors.background],
            stops: [0.0, 0.35],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              children: [
                // Header
                SizedBox(height: size.height * 0.03),
                FadeTransition(
                  opacity: _fadeAnim,
                  child: Column(
                    children: [
                      // Back button row
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.screenPadding,
                        ),
                        child: Row(
                          children: [
                            GestureDetector(
                              onTap: () => context.go(RouteNames.login),
                              child: Container(
                                padding: const EdgeInsets.all(AppSpacing.sm),
                                decoration: BoxDecoration(
                                  color: AppColors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(
                                    AppSpacing.radiusSm,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.arrow_back,
                                  color: AppColors.white,
                                  size: 22,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Welcome',
                        style: AppTypography.h2.copyWith(
                          color: AppColors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        AppConstants.appName,
                        style: AppTypography.h4.copyWith(
                          color: AppColors.white.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: size.height * 0.03),

                // Form card
                SlideTransition(
                  position: _slideAnim,
                  child: FadeTransition(
                    opacity: _fadeAnim,
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.screenPadding,
                      ),
                      padding: const EdgeInsets.all(AppSpacing.xxl),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusXl,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.black.withValues(alpha: 0.08),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Create Account',
                              style: AppTypography.h4,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: AppSpacing.xxl),

                            // Avatar placeholder
                            Center(
                              child: Stack(
                                children: [
                                  CircleAvatar(
                                    radius: 40,
                                    backgroundColor: AppColors.surfaceVariant,
                                    child: const Icon(
                                      Icons.person,
                                      size: 40,
                                      color: AppColors.textTertiary,
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: Container(
                                      padding: const EdgeInsets.all(
                                        AppSpacing.xs,
                                      ),
                                      decoration: const BoxDecoration(
                                        color: AppColors.primary,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.camera_alt,
                                        size: 16,
                                        color: AppColors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            Center(
                              child: Text(
                                'Upload',
                                style: AppTypography.caption.copyWith(
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.lg),

                            // Error message
                            if (authState.errorMessage != null) ...[
                              Container(
                                padding: const EdgeInsets.all(AppSpacing.md),
                                decoration: BoxDecoration(
                                  color: AppColors.error.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(
                                    AppSpacing.radiusSm,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.error_outline,
                                      color: AppColors.error,
                                      size: 20,
                                    ),
                                    const SizedBox(width: AppSpacing.sm),
                                    Expanded(
                                      child: Text(
                                        authState.errorMessage!,
                                        style: AppTypography.bodySmall.copyWith(
                                          color: AppColors.error,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: AppSpacing.lg),
                            ],

                            // Name
                            TextFormField(
                              controller: _nameController,
                              textInputAction: TextInputAction.next,
                              validator: Validators.name,
                              decoration: const InputDecoration(
                                hintText: 'Name',
                                prefixIcon: Icon(Icons.person_outlined),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),

                            // Email
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              validator: Validators.email,
                              decoration: const InputDecoration(
                                hintText: 'Email',
                                prefixIcon: Icon(Icons.email_outlined),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),

                            // Phone
                            TextFormField(
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              textInputAction: TextInputAction.next,
                              validator: Validators.phone,
                              decoration: const InputDecoration(
                                hintText: 'Phone',
                                prefixIcon: Icon(Icons.phone_outlined),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),

                            // Password
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              textInputAction: TextInputAction.next,
                              validator: Validators.password,
                              decoration: InputDecoration(
                                hintText: 'Password',
                                prefixIcon: const Icon(Icons.lock_outlined),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                  ),
                                  onPressed: () => setState(
                                    () => _obscurePassword = !_obscurePassword,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),

                            // Confirm Password
                            TextFormField(
                              controller: _confirmPasswordController,
                              obscureText: _obscureConfirm,
                              textInputAction: TextInputAction.done,
                              validator: (v) => Validators.confirmPassword(
                                v,
                                _passwordController.text,
                              ),
                              onFieldSubmitted: (_) => _handleSignUp(),
                              decoration: InputDecoration(
                                hintText: 'Confirm Password',
                                prefixIcon: const Icon(
                                  Icons.lock_outline_rounded,
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscureConfirm
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                  ),
                                  onPressed: () => setState(
                                    () => _obscureConfirm = !_obscureConfirm,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xxl),

                            // Sign Up button
                            SizedBox(
                              height: 52,
                              child: ElevatedButton(
                                onPressed: authState.isLoading
                                    ? null
                                    : _handleSignUp,
                                child: authState.isLoading
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          color: AppColors.white,
                                          strokeWidth: 2.5,
                                        ),
                                      )
                                    : const Text('Sign Up'),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.lg),

                            // Login link
                            Center(
                              child: TextButton(
                                onPressed: () => context.go(RouteNames.login),
                                child: RichText(
                                  text: TextSpan(
                                    text: 'Already have an account? ',
                                    style: AppTypography.bodySmall,
                                    children: [
                                      TextSpan(
                                        text: 'Login',
                                        style: AppTypography.labelMedium
                                            .copyWith(color: AppColors.primary),
                                      ),
                                    ],
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
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
