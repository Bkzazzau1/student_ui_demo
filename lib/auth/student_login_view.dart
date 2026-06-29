import 'package:flutter/material.dart';

import '../exam_demo/demo_exam_home.dart';

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
      backgroundColor: const Color(0xFFEFF3F8),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 26),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1160),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 920;
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
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: const Color(0xFFD6DFEA)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x160F172A),
                          blurRadius: 30,
                          offset: Offset(0, 18),
                        ),
                      ],
                    ),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Expanded(child: _BrandPanel()),
                          Container(width: 1, color: const Color(0xFFE2E8F0)),
                          SizedBox(width: 470, child: loginPanel),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
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
      color: const Color(0xFFFBFCFE),
      padding: EdgeInsets.all(compact ? 24 : 44),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const _InstitutionMark(),
          SizedBox(height: compact ? 28 : 52),
          Container(width: 76, height: 4, color: const Color(0xFF0F4C81)),
          const SizedBox(height: 22),
          Text(
            'K-SLAS Student Portal',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: const Color(0xFF0B1220),
                  fontWeight: FontWeight.w900,
                  height: 1.06,
                  letterSpacing: -0.8,
                ),
          ),
          const SizedBox(height: 18),
          const Text(
            'A formal access point for assessments, coursework, results, and lecturer feedback for Distance Learning students.',
            style: TextStyle(
              color: Color(0xFF475569),
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
          width: 68,
          height: 68,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF0F4C81),
            border: Border.all(color: const Color(0xFF0B3A63), width: 1.5),
          ),
          child: const Text(
            'KASU',
            style: TextStyle(
              color: Colors.white,
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
                  color: Color(0xFF0B1220),
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                ),
              ),
              SizedBox(height: 5),
              Text(
                'Distance Learning Institute',
                style: TextStyle(
                  color: Color(0xFF334155),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
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
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SummaryRow(title: 'Assessments', subtitle: 'Open available exams, quizzes, and practice activities.'),
          SizedBox(height: 14),
          _SummaryRow(title: 'Guided exam checks', subtitle: 'Follow simple steps before monitored assessments begin.'),
          SizedBox(height: 14),
          _SummaryRow(title: 'Feedback', subtitle: 'View lecturer feedback and continue learning after submission.'),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(width: 5, height: 44, color: const Color(0xFF0F4C81)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF0B1220),
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Color(0xFF64748B),
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
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 38, vertical: 42),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Student Login',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF0B1220),
                  ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Use your official student access details to continue.',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            const _DemoCredentialsCard(),
            const SizedBox(height: 24),
            TextFormField(
              controller: studentIdController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Student ID',
                hintText: 'Enter student ID',
                prefixIcon: Icon(Icons.badge_outlined),
                border: OutlineInputBorder(),
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
              decoration: InputDecoration(
                labelText: 'Password',
                hintText: 'Enter password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: obscurePassword ? 'Show password' : 'Hide password',
                  onPressed: onTogglePassword,
                  icon: Icon(
                    obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  ),
                ),
                border: const OutlineInputBorder(),
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
            FilledButton(
              onPressed: signingIn ? null : onSignIn,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0F4C81),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(56),
                shape: const RoundedRectangleBorder(),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              child: signingIn
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Sign In'),
            ),
          ],
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFFD6DFEA)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Demo Credentials',
            style: TextStyle(
              color: Color(0xFF0B1220),
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 10),
          _DemoLoginLine(label: 'Student ID', value: _StudentLoginViewState.demoStudentId),
          SizedBox(height: 6),
          _DemoLoginLine(label: 'Password', value: _StudentLoginViewState.demoPassword),
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
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: Color(0xFF0B1220),
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
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Official Student Access',
            style: TextStyle(
              color: Color(0xFF0B1220),
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'For monitored examinations, students will complete the required identity, camera, microphone, and device checks before the assessment begins.',
            style: TextStyle(
              color: Color(0xFF475569),
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
