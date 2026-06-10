/// Progress event emitted while downloading/installing an APK update.
class ApkProgress {
  final String status; // DOWNLOADING / INSTALLING / and error statuses
  final int percent;   // 0–100, or -1 when unknown
  const ApkProgress({required this.status, required this.percent});

  bool get isError => status.toUpperCase().contains('ERROR');
}
