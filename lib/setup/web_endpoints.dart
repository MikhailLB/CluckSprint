// Public-facing URLs used outside of the gray flow itself (game menu,
// legal pages, support form). Kept in plain text on purpose — they are
// the same URLs the Play Store listing already points to.

const String cluckSprintSiteUrl = 'https://cllucksprint.com';
const String cluckSprintPrivacyUrl = 'https://cllucksprint.com/privacy-policy.html';
const String cluckSprintSupportUrl = 'https://cllucksprint.com/support.html';

// Helpers in case the menu wants to deep-link with locale or referral.
String buildPrivacyUrl({String? locale}) => locale == null
    ? cluckSprintPrivacyUrl
    : '$cluckSprintPrivacyUrl?lang=$locale';

String buildSupportUrl({String? locale}) => locale == null
    ? cluckSprintSupportUrl
    : '$cluckSprintSupportUrl?lang=$locale';
