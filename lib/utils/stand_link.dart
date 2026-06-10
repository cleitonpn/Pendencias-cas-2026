/// Base URL of the public "stand" web page hosted on Firebase Hosting.
/// The QR code printed on each stand sticker points here.
const String kStandBaseUrl = 'https://montagem-uset.web.app';

/// Builds the deep link encoded in a stand's QR code.
/// Uses the hash strategy so it works on static hosting without rewrites.
String buildStandUrl({required int fairId, required String rowId}) =>
    '$kStandBaseUrl/#/stand?f=$fairId&c=${Uri.encodeComponent(rowId)}';

/// Link opened by the event organizer to create requests for any stand.
/// Requests go to the attendant (consultant) for approval before reaching teams.
String buildOrganizerUrl({required int fairId}) =>
    '$kStandBaseUrl/#/organizadora?f=$fairId';
