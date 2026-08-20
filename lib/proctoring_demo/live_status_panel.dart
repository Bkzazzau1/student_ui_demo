import 'package:flutter/material.dart';

class LiveStatusPanel extends StatelessWidget {
  const LiveStatusPanel({super.key, this.onOpenAirBoard});

  final VoidCallback? onOpenAirBoard;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Live exam checks active',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              'Camera, sound, clear face view, and system checks remain required.',
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed:
                  onOpenAirBoard ??
                  () => Navigator.of(context).pushNamed('/air-board'),
              icon: const Icon(Icons.border_color_outlined, size: 18),
              label: const Text('Open rough-work board'),
            ),
            const SizedBox(height: 6),
            const Text(
              'Use the board for calculations and notes inside the exam screen.',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
