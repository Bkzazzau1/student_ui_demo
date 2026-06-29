import 'package:flutter/material.dart';
import 'package:get_storage/get_storage.dart';

import '../exam_demo/demo_exam_home.dart';

class StudentLoginView extends StatefulWidget {
  const StudentLoginView({super.key});

  @override
  State<StudentLoginView> createState() => _StudentLoginViewState();
}

class _StudentLoginViewState extends State<StudentLoginView> {
  static const Color _brandBlue = Color(0xFF0F4C81);
  static const Color _brandNavy = Color(0xFF0F172A);
  static const String _rememberKey = 'student_login_remember_identity';
  static const String _identityKey = 'student_login_identity';

  final GetStorage _storage = GetStorage();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _identityController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _identityFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();

  bool _rememberIdentity = true;
  bool _passwordVisible = false;
  bool _submitting = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _rememberIdentity = _storage.read<bool>(_rememberKey) ?? true;
    if (_rememberIdentity) {
      _identityController.text = _storage.read<String>(_identityKey) ?? '';
    }
  }

  @override
  void dispose() {
    _identityController.dispose();
    _passwordController.dispose();
    _identityFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid || _submitting) return;

    setState(() {
      _submitting = true;
      _statusMessage = 'Checking your student access...';
    });

    await Future<void>.delayed(const Duration(milliseconds: 650));

    if (!mounted) return;
    final identity = _identityController.text.trim();
    if (_rememberIdentity) {
      await _storage.write(_rememberKey, true);
      await _storage.write(_identityKey, identity);
    } else {
      await _storage.write(_rememberKey, false);
      await _storage.remove(_identityKey);
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const DemoExamHome()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 920;
            return Stack(
              children: [
                const _BackgroundDecoration(),
                Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: wide ? 42 : 18,
                      vertical: wide ? 34 : 18,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1120),
                      child: wide
                          ? Row(
                              children: [
                                const Expanded(child: _WelcomePanel()),
                                const SizedBox(width: 28),
                                Expanded(child: _buildLoginCard(context)),
                              ],
                            )
                          : Column(
                              children: [
                                const _CompactBrandHeader(),
                                const SizedBox(height: 18),
                                _buildLoginCard(context),
                              ],
                            ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildLoginCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A0F172A),
            blurRadius: 34,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Form(
          key: _formKey,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: _brandBlue.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.school_outlined,
                        color: _brandBlue,
                        size: 30,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'K-SLAS Student Portal',
                            style: TextStyle(
                              color: _brandNavy,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Kaduna State University',
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                Text(
                  'Sign in to continue',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: _brandNavy,
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Use your matric number or student email to open your assessment dashboard.',
                  style: TextStyle(color: Color(0xFF64748B), height: 1.45),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _identityController,
                  focusNode: _identityFocus,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.username, AutofillHints.email],
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Matric number or student email',
                    hintText: 'Example: KASU/STU/2026/001',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isEmpty) {
                      return 'Enter your matric number or student email.';
                    }
                    if (text.length < 4) {
                      return 'Enter a valid student identity.';
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _passwordController,
                  focusNode: _passwordFocus,
                  obscureText: !_passwordVisible,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  decoration: InputDecoration(
                    labelText: 'Password',
                    hintText: 'Enter your password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      tooltip: _passwordVisible ? 'Hide password' : 'Show password',
                      onPressed: () => setState(() {
                        _passwordVisible = !_passwordVisible;
                      }),
                      icon: Icon(
                        _passwordVisible
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                  ),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isEmpty) return 'Enter your password.';
                    if (text.length < 3) return 'Password is too short.';
                    return null;
                  },
                  onFieldSubmitted: (_) => _signIn(),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Checkbox(
                      value: _rememberIdentity,
                      onChanged: (value) => setState(() {
                        _rememberIdentity = value ?? true;
                      }),
                    ),
                    const Expanded(
                      child: Text(
                        'Remember this student identity',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Password recovery will be connected to the student support service.',
                            ),
                          ),
                        );
                      },
                      child: const Text('Need help?'),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _submitting ? null : _signIn,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login_rounded),
                  label: Text(
                    _submitting ? 'Opening portal...' : 'Continue to student portal',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                if (_statusMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _statusMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _brandBlue,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                const _SecureModeNotice(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WelcomePanel extends StatelessWidget {
  const _WelcomePanel();

  static const Color _brandBlue = Color(0xFF0F4C81);
  static const Color _brandNavy = Color(0xFF0F172A);

  @override
  Widget build(BuildContext context) {
    return Container(
      minHeight: 640,
      padding: const EdgeInsets.all(34),
      decoration: BoxDecoration(
        color: _brandNavy,
        borderRadius: BorderRadius.circular(32),
        boxShadow: const [
          BoxShadow(
            color: Color(0x240F172A),
            blurRadius: 34,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                ),
                child: const Icon(Icons.auto_stories_outlined, color: Colors.white),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'K-SLAS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      'Smart Learning & Assessment System',
                      style: TextStyle(color: Color(0xFFCBD5E1)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _brandBlue.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            ),
            child: const Text(
              'Student examination access',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'A calm and secure way to enter your online assessments.',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Complete your login, open available assessments, and follow the guided checks before any monitored examination begins.',
            style: TextStyle(
              color: Color(0xFFCBD5E1),
              fontSize: 16,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 28),
          const Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _FeaturePill(icon: Icons.verified_user_outlined, label: 'Identity check'),
              _FeaturePill(icon: Icons.videocam_outlined, label: 'Camera check'),
              _FeaturePill(icon: Icons.mic_none_outlined, label: 'Microphone check'),
              _FeaturePill(icon: Icons.lock_outline, label: 'Secure exam mode'),
            ],
          ),
          const Spacer(),
          const Divider(color: Color(0xFF334155)),
          const SizedBox(height: 14),
          const Row(
            children: [
              Icon(Icons.info_outline, color: Color(0xFF93C5FD)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Your exam records are prepared for authorized review only when required.',
                  style: TextStyle(color: Color(0xFFCBD5E1), height: 1.4),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompactBrandHeader extends StatelessWidget {
  const _CompactBrandHeader();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        CircleAvatar(
          radius: 31,
          backgroundColor: Color(0xFF0F4C81),
          child: Icon(Icons.school_outlined, color: Colors.white, size: 32),
        ),
        SizedBox(height: 12),
        Text(
          'K-SLAS Student Portal',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 28,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'Kaduna State University',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _SecureModeNotice extends StatelessWidget {
  const _SecureModeNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_clock_outlined, color: Color(0xFF0F4C81)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Before a monitored exam starts, the app will guide you through identity, camera, microphone, and device checks.',
              style: TextStyle(color: Color(0xFF475569), height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturePill extends StatelessWidget {
  const _FeaturePill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _BackgroundDecoration extends StatelessWidget {
  const _BackgroundDecoration();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            Positioned(
              top: -120,
              right: -90,
              child: _DecorCircle(
                size: 260,
                color: const Color(0xFF0F4C81).withValues(alpha: 0.12),
              ),
            ),
            Positioned(
              bottom: -130,
              left: -120,
              child: _DecorCircle(
                size: 320,
                color: const Color(0xFF16A34A).withValues(alpha: 0.10),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DecorCircle extends StatelessWidget {
  const _DecorCircle({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}
