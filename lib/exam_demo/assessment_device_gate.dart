import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'assessment_device_access_policy.dart';
import 'demo_exam_models.dart';

class AssessmentDeviceGate extends StatelessWidget {
  const AssessmentDeviceGate({
    super.key,
    required this.assessment,
    required this.child,
    this.deviceClassOverride,
  });

  final DemoAssessment assessment;
  final Widget child;
  final AssessmentDeviceClass? deviceClassOverride;

  @override
  Widget build(BuildContext context) {
    final deviceClass = deviceClassOverride ??
        AssessmentDeviceClassResolver.resolve(
          platform: defaultTargetPlatform,
          shortestSide: MediaQuery.sizeOf(context).shortestSide,
        );
    final decision = AssessmentDeviceAccessPolicy.decisionFor(
      assessmentKind: AssessmentDeviceAccessPolicy.kindFromString(
        assessment.assessmentType,
      ),
      deviceClass: deviceClass,
    );

    if (decision.allowed) return child;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Device check',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.devices_other_outlined,
                      color: Color(0xFFEA580C),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    decision.title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF0F172A),
                        ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    decision.message,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: const Color(0xFF475569),
                          height: 1.45,
                        ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Assessments, practice questions, and assignments remain available on mobile phones.',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w700,
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

class AssessmentDeviceClassResolver {
  const AssessmentDeviceClassResolver._();

  static AssessmentDeviceClass resolve({
    required TargetPlatform platform,
    required double shortestSide,
  }) {
    switch (platform) {
      case TargetPlatform.windows:
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
        return AssessmentDeviceClass.desktop;
      case TargetPlatform.iOS:
        return shortestSide >= 600
            ? AssessmentDeviceClass.ipad
            : AssessmentDeviceClass.mobilePhone;
      case TargetPlatform.android:
        return shortestSide >= 600
            ? AssessmentDeviceClass.tablet
            : AssessmentDeviceClass.mobilePhone;
      case TargetPlatform.fuchsia:
        return AssessmentDeviceClass.unknown;
    }
  }
}
