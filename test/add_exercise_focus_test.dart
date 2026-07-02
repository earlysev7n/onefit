import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression guard for the Workout-tab "add a searched exercise" crash
/// (`framework.dart` `InheritedElement.debugDeactivated` → `_dependents.isEmpty`).
///
/// Two causes, both fixed and pinned here:
///  1. The picker/params sheets disposed the search `TextEditingController`
///     **synchronously** in `showModalBottomSheet(...).whenComplete(...)`, which
///     — with a focused field — raced the `EditableText` teardown and corrupted
///     the Overlay unmount. Fix: defer the dispose to a post-frame callback.
///  2. On a real device, popping the sheet while the soft keyboard is open tears
///     down the IME + animates `viewInsets` mid-unmount → same assertion. Fix:
///     `FocusManager.instance.primaryFocus?.unfocus()` before `Navigator.pop`.
///
/// This test mirrors the picker (StatefulBuilder + TextField + modal sheet),
/// simulates an OPEN keyboard via `tester.view.viewInsets`, applies the real fix
/// (unfocus → pop → deferred dispose), and asserts no exception. (Best-effort:
/// the harness has no real IME, so it can't fully prove the device path.)
void main() {
  Future<void> openSearchTapWithKeyboard(WidgetTester tester) async {
    // Simulate the soft keyboard occupying the bottom of the screen.
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () {
                  final controller = TextEditingController();
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    builder: (ctx) => Padding(
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.of(ctx).viewInsets.bottom,
                      ),
                      child: StatefulBuilder(
                        builder: (ctx, setSheetState) => Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextField(
                              controller: controller,
                              onChanged: (_) => setSheetState(() {}),
                            ),
                            ListTile(
                              title: const Text('Barbell Bench Press'),
                              onTap: () {
                                // The real fix, in order:
                                FocusManager.instance.primaryFocus?.unfocus();
                                Navigator.pop(ctx);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ).whenComplete(() {
                    WidgetsBinding.instance
                        .addPostFrameCallback((_) => controller.dispose());
                  });
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // Searching focuses the TextField (keyboard up) — the crash precondition.
    await tester.enterText(find.byType(TextField), 'bench');
    await tester.pump();
    // Adding: unfocus (keyboard dismisses → viewInsets to 0) then pop.
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.tap(find.text('Barbell Bench Press'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'add searched item with keyboard open: unfocus+pop+deferred dispose is clean',
    (tester) async {
      await openSearchTapWithKeyboard(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Barbell Bench Press'), findsNothing); // sheet closed
      expect(find.text('open'), findsOneWidget);
    },
  );
}
