import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds the newest link that opened the app (for example the Firebase email-confirmation link),
/// so the sign-in screen or the confirmation dialog can finish by itself instead of asking the
/// person to paste it. The paste field stays as a fallback (iOS, or links that do not open the app).
class EmailLinkInbox extends Notifier<String?> {
  @override
  String? build() {
    StreamSubscription<Uri>? subscription;
    try {
      subscription = AppLinks().uriLinkStream.listen((uri) => state = uri.toString());
    } on Object {
      // Platform without app links: the paste field still works.
    }
    ref.onDispose(() => subscription?.cancel());
    return null;
  }

  /// Forget the link after it was used.
  void clear() => state = null;
}

/// The latest incoming link (null when none).
final emailLinkInboxProvider = NotifierProvider<EmailLinkInbox, String?>(EmailLinkInbox.new);
