import 'package:day_dial/agent/activity_log.dart';
import 'package:day_dial/agent/agent_host.dart';
import 'package:day_dial/main.dart';
import 'package:day_dial/screens/agent_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  testWidgets('agent panel golden (stopped, with activity)', (tester) async {
    final host = createAgentHost(
      repository: testRepository(),
      navigatorKey: GlobalKey<NavigatorState>(),
    );
    final at = DateTime(2026, 7, 3, 8, 30);
    host.activity
      ..add(
        ActivityEntry(
          tool: 'add_block',
          summary: 'add_block(name=Gym, start=10:00, end=11:00)',
          outcome: ActivityOutcome.allowed,
          at: at,
        ),
      )
      ..add(
        ActivityEntry(
          tool: 'delete_block',
          summary: 'delete_block(id=lunch)',
          outcome: ActivityOutcome.denied,
          at: at,
        ),
      );

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(
          useMaterial3: true,
        ).copyWith(scaffoldBackgroundColor: const Color(0xFF0A0D18)),
        home: SizedBox(width: 400, height: 760, child: AgentScreen(host: host)),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(AgentScreen),
      matchesGoldenFile('goldens/agent_panel.png'),
    );
  });

  testWidgets('the agent button opens the Agent panel', (tester) async {
    await tester.pumpWidget(DayDialApp(repository: testRepository()));
    await tester.pump();

    await tester.tap(find.byTooltip('Agent'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // route transition

    expect(find.text('Agent'), findsWidgets); // app bar title
    expect(find.text('Server stopped'), findsOneWidget); // idle by default

    await tester.pumpWidget(const SizedBox());
  });
}
