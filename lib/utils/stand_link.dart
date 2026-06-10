/// Base URL of the public "stand" web page hosted on Firebase Hosting.
/// The QR code printed on each stand sticker points here.
const String kStandBaseUrl = 'https://montagem-uset.web.app';

/// Builds the deep link encoded in a stand's QR code.
/// Uses the hash strategy so it works on static hosting without rewrites.
String buildStandUrl({required int fairId, required String rowId}) =>
    '$kStandBaseUrl/#/stand?f=$fairId&c=${Uri.encodeComponent(rowId)}';

/// Link opened by the event organizer. With no [fairId] it is a single
/// universal link: the organizer identifies herself and the page lists the
/// fairs she is responsible for. Passing [fairId] opens straight into one fair.
/// Requests go to the attendant (consultant) for approval before reaching teams.
String buildOrganizerUrl({int? fairId}) => fairId == null
    ? '$kStandBaseUrl/#/organizadora'
    : '$kStandBaseUrl/#/organizadora?f=$fairId';
