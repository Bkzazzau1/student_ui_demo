import 'package:flutter/material.dart';

import '../exam_demo/demo_exam_home.dart';

const Color _brand = Color(0xFF0F4C81);
const Color _brandDark = Color(0xFF0B1220);
const Color _brandDeep = Color(0xFF082F49);
const Color _brandLight = Color(0xFFEFF6FF);
const Color _green = Color(0xFF16A34A);
const Color _amber = Color(0xFFF59E0B);
const Color _purple = Color(0xFF7C3AED);
const Color _surface = Colors.white;
const Color _surfaceSoft = Color(0xFFF8FAFC);
const Color _line = Color(0xFFE2E8F0);
const Color _muted = Color(0xFF64748B);

class StudentLoginView extends StatefulWidget {
  const StudentLoginView({super.key});

  @override
  State<StudentLoginView> createState() => _StudentLoginViewState();
}

class _StudentLoginViewState extends State<StudentLoginView> {
  static const String demoStudentId = 'KSLAS/STD/2026/001';
  static const String demoPassword = 'demo123';

  final _formKey = GlobalKey<FormState>();
  final _studentIdController = TextEditingController(text: demoStudentId);
  final _passwordController = TextEditingController(text: demoPassword);
  bool _rememberMe = true;
  bool _obscurePassword = true;
  bool _signingIn = false;

  @override
  void dispose() {
    _studentIdController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _signingIn = true);
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    setState(() => _signingIn = false);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const DemoExamHome()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEAF1F8),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFEAF1F8), Color(0xFFF8FAFC), Color(0xFFEFF6FF)],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              const Positioned(top: 0, left: 0, right: 0, child: _TopColorBand()),
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 34),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= 940;
                        final loginPanel = _LoginPanel(
                          formKey: _formKey,
                          studentIdController: _studentIdController,
                          passwordController: _passwordController,
                          rememberMe: _rememberMe,
                          obscurePassword: _obscurePassword,
                          signingIn: _signingIn,
                          onRememberChanged: (value) => setState(() => _rememberMe = value),
                          onTogglePassword: () => setState(() => _obscurePassword = !_obscurePassword),
                          onSignIn: _signIn,
                        );

                        if (!wide) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const _BrandPanel(compact: true),
                              const SizedBox(height: 16),
                              loginPanel,
                            ],
                          );
                        }

                        return Container(
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: _surface,
                            border: Border.all(color: const Color(0xFFD6DFEA)),
                            borderRadius: BorderRadius.circular(26),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x1A0F172A),
                                blurRadius: 36,
                                offset: Offset(0, 22),
                              ),
                            ],
                          ),
                          child: IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Expanded(child: _BrandPanel()),
                                Container(width: 1, color: _line),
                                SizedBox(width: 480, child: loginPanel),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopColorBand extends StatelessWidget {
  const _TopColorBand();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 8,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_brand, _green, _amber, _purple],
        ),
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF082F49), Color(0xFF0F4C81), Color(0xFF14532D)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: compact ? 88 : 130,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                border: Border(left: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(compact ? 24 : 46),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const _InstitutionMark(),
                SizedBox(height: compact ? 30 : 54),
                const _OfficialAccessTag(),
                const SizedBox(height: 18),
                Text(
                  'K-SLAS Student Portal',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        height: 1.06,
                        letterSpacing: -0.8,
                      ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'A trusted access point for assessments, coursework, results, and lecturer feedback for Distance Learning students.',
                  style: TextStyle(
                    color: Color(0xFFE2E8F0),
                    fontSize: 17,
                    height: 1.55,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(height: 34),
                  const _AccessSummary(),
                  const SizedBox(height: 28),
                  const _AcademicNotice(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OfficialAccessTag extends StatelessWidget {
  const _OfficialAccessTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        'Official Student Access',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _InstitutionMark extends StatelessWidget {
  const _InstitutionMark();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 72,
          height: 72,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.55), width: 1.5),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1F000000),
                blurRadius: 18,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: const Text(
            'KASU',
            style: TextStyle(
              color: _brand,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.6,
            ),
          ),
        ),
        const SizedBox(width: 16),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Kaduna State University',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                ),
              ),
              SizedBox(height: 5),
              Text(
                'Distance Learning Institute',
                style: TextStyle(
                  color: Color(0xFFCBD5E1),
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AccessSummary extends StatelessWidget {
  const _AccessSummary();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SummaryRow(
            title: 'Assessments',
            subtitle: 'Open available exams, quizzes, and practice activities.',
            color: _amber,
          ),
          SizedBox(height: 14),
          _SummaryRow(
            title: 'Guided exam checks',
            subtitle: 'Follow simple steps before monitored assessments begin.',
            color: _green,
          ),
          SizedBox(height: 14),
          _SummaryRow(
            title: 'Feedback',
            subtitle: 'View lecturer feedback and continue learning after submission.',
            color: Color(0xFF93C5FD),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.title,
    required this.subtitle,
    required this.color,
  });

  final String title;
  final String subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 5,
          height: 46,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Color(0xFFD8E3F0),
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LoginPanel extends StatelessWidget {
  const _LoginPanel({
    required this.formKey,
    required this.studentIdController,
    required this.passwordController,
    required this.rememberMe,
    required this.obscurePassword,
    required this.signingIn,
    required this.onRememberChanged,
    required this.onTogglePassword,
    required this.onSignIn,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController studentIdController;
  final TextEditingController passwordController;
  final bool rememberMe;
  final bool obscurePassword;
  final bool signingIn;
  final ValueChanged<bool> onRememberChanged;
  final VoidCallback onTogglePassword;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _surface,
      padding: const EdgeInsets.symmetric(horizontal: 38, vertical: 42),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            const _LoginHeading(),
            const SizedBox(height: 18),
            const _DemoCredentialsCard(),
            const SizedBox(height: 24),
            TextFormField(
              controller: studentIdController,
              textInputAction: TextInputAction.next,
              decoration: _fieldDecoration(
                label: 'Student ID',
                hint: 'Enter student ID',
                icon: Icons.badge_outlined,
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) return 'Enter your student ID';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: passwordController,
              obscureText: obscurePassword,
              onFieldSubmitted: (_) => onSignIn(),
              decoration: _fieldDecoration(
                label: 'Password',
                hint: 'Enter password',
                icon: Icons.lock_outline,
                suffixIcon: IconButton(
                  tooltip: obscurePassword ? 'Show password' : 'Hide password',
                  onPressed: onTogglePassword,
                  icon: Icon(
                    obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) return 'Enter your password';
                return null;
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 32,
                  height: 32,
                  child: Checkbox(
                    value: rememberMe,
                    activeColor: _brand,
                    onChanged: (value) => onRememberChanged(value ?? false),
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Remember me',
                    style: TextStyle(
                      color: Color(0xFF334155),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please contact the institute support desk.'),
                      ),
                    );
                  },
                  child: const Text('Need help?'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _PrimarySignInButton(signingIn: signingIn, onPressed: onSignIn),
          ],
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: _surfaceSoft,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _brand, width: 1.6),
      ),
    );
  }
}

class _LoginHeading extends StatelessWidget {
  const _LoginHeading();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 58,
          height: 5,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_brand, _green, _amber]),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Student Login',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: _brandDark,
              ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Use your official student access details to continue.',
          style: TextStyle(
            color: _muted,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _PrimarySignInButton extends StatelessWidget {
  const _PrimarySignInButton({required this.signingIn, required this.onPressed});

  final bool signingIn;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: signingIn
            ? const LinearGradient(colors: [Color(0xFF94A3B8), Color(0xFF64748B)])
            : const LinearGradient(colors: [_brand, Color(0xFF1D4ED8), _green]),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x240F4C81),
            blurRadius: 16,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: signingIn ? null : onPressed,
          child: SizedBox(
            height: 56,
            child: Center(
              child: signingIn
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.login_rounded, color: Colors.white, size: 20),
                        SizedBox(width: 9),
                        Text(
                          'Sign In',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DemoCredentialsCard extends StatelessWidget {
  const _DemoCredentialsCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 4,
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [_amber, _green, _brand]),
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.verified_user_outlined, color: _amber, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Demo Credentials',
                      style: TextStyle(
                        color: _brandDark,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                _DemoLoginLine(label: 'Student ID', value: _StudentLoginViewState.demoStudentId),
                SizedBox(height: 7),
                _DemoLoginLine(label: 'Password', value: _StudentLoginViewState.demoPassword),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DemoLoginLine extends StatelessWidget {
  const _DemoLoginLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: const TextStyle(
              color: _muted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: _brandDark,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _AcademicNotice extends StatelessWidget {
  const _AcademicNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Before monitored examinations',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Students will complete identity, camera, microphone, and device checks before the assessment begins.',
            style: TextStyle(
              color: Color(0xFFD8E3F0),
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
