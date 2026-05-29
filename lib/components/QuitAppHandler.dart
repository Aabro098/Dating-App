import 'package:flutter/material.dart';
import 'QuitAppDialog.dart';

/// Wrapper widget to handle back button press globally
/// Wrap your screen's Scaffold with this widget to show quit dialog on back press
class QuitAppHandler extends StatelessWidget {
  final Widget child;
  final bool shouldShowDialog;

  const QuitAppHandler({
    Key? key,
    required this.child,
    this.shouldShowDialog = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (!shouldShowDialog) {
      return child;
    }

    return WillPopScope(
      onWillPop: () async {
        final shouldQuit = await QuitAppDialog.show(context);
        return shouldQuit;
      },
      child: child,
    );
  }
}
