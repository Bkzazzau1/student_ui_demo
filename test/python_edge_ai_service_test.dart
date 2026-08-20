import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:students_ui_demo/proctoring_demo/python_edge_ai_service.dart';

void main() {
  group('PythonEdgeAiProtocol', () {
    test('builds a versioned request', () {
      final request =
          jsonDecode(
                PythonEdgeAiProtocol.requestLine(
                  requestId: '7',
                  type: 'health',
                ),
              )
              as Map<String, dynamic>;
      expect(request['protocol_version'], '1.0');
      expect(request['request_id'], '7');
      expect(request['type'], 'health');
    });

    test('parses an explainable review decision', () {
      final response = PythonEdgeAiProtocol.parseResponse(
        jsonEncode({
          'protocol_version': '1.0',
          'request_id': '8',
          'ok': true,
          'result': {
            'risk_score': 52,
            'risk_level': 'high',
            'disposition': 'human_review',
            'reasons': ['corroborating signals'],
            'proposed_actions': ['capture_review_snapshot'],
            'requires_human_review': true,
          },
        }),
      );
      final decision = EdgeAiReviewDecision.fromJson(
        Map<String, Object?>.from(response['result'] as Map),
      );
      expect(decision.riskScore, 52);
      expect(decision.requiresHumanReview, isTrue);
      expect(decision.proposedActions, ['capture_review_snapshot']);
    });

    test('rejects protocol mismatches', () {
      expect(
        () => PythonEdgeAiProtocol.parseResponse(
          '{"protocol_version":"2.0","request_id":"1","ok":true}',
        ),
        throwsFormatException,
      );
    });
  });
}
