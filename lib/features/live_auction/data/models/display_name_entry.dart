/// One entry from `GET /api/v1/users/display-names` — the resolved profile
/// name (and email) for a chat sender. Both fields may be null/absent, so the
/// UI never shows a raw value without falling through [resolveDisplayName].
class DisplayNameEntry {
  const DisplayNameEntry({this.displayName, this.email});

  final String? displayName;
  final String? email;

  factory DisplayNameEntry.fromJson(Map<String, dynamic> json) =>
      DisplayNameEntry(
        displayName: json['displayName'] as String?,
        email: json['email'] as String?,
      );
}

/// Picks the best human-readable label for [userId], in priority order:
///
/// 1. `displayName`
/// 2. local part of `email` (before `@`)
/// 3. full `email`
/// 4. a truncated id
///
/// Never returns a raw full UUID — a missing entry collapses to the short id so
/// the chat always has something compact to render. Mirrors the buyer app, so
/// both sides label the same person identically.
String resolveDisplayName(String userId, Map<String, DisplayNameEntry> names) {
  final fallback = userId.length > 12 ? userId.substring(0, 12) : userId;
  final entry = names[userId];
  if (entry == null) return fallback;

  final dn = entry.displayName?.trim();
  if (dn != null && dn.isNotEmpty) return dn;

  final email = entry.email?.trim();
  if (email != null && email.contains('@')) return email.split('@').first;
  if (email != null && email.isNotEmpty) return email;

  return fallback;
}
