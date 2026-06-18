import 'package:flutter/material.dart';

class LiveStatusPanel extends StatelessWidget {
  const LiveStatusPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return const Card(
      elevation: 0,
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Live exam checks active',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            SizedBox(height: 8),
            Text('Camera, sound, face view, and system checks remain required.'),
          ],
        ),
      ),
    );
  }
}
