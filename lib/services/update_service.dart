import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// Information about an available app update.
class UpdateInfo {
  final String versionName; // e.g. "1.0.2" (shown to the user)
  final int buildNumber;    // e.g. 3 (used to compare)
  final String apkUrl;      // direct download URL of the new APK
  final String notes;       // release notes

  UpdateInfo({
    required this.versionName,
    required this.buildNumber,
    required this.apkUrl,
    required this.notes,
  });
}

/// Checks GitHub Releases for a newer APK than the one currently installed.
///
/// The CI publishes each build as a GitHub Release tagged `v<buildNumber>`
/// with the APK attached. The app compares that build number with its own
/// (from the embedded version) and offers the update when it is higher.
class UpdateService {
  static const _releasesApi =
      'https://api.github.com/repos/cleitonpn/Pendencias-cas-2026/releases/latest';

  static Future<UpdateInfo?> checkForUpdate() async {
    // Updates only make sense for the installed Android app — web auto-updates,
    // and desktop is not distributed this way.
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;

    try {
      final info = await PackageInfo.fromPlatform();
      final localBuild = int.tryParse(info.buildNumber) ?? 0;

      final resp = await http.get(
        Uri.parse(_releasesApi),
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final tag = (data['tag_name'] as String?) ?? '';
      final remoteBuild =
          int.tryParse(tag.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      if (remoteBuild <= localBuild) return null;

      // Find the .apk asset.
      String apkUrl = '';
      for (final a in (data['assets'] as List? ?? [])) {
        final name = (a['name'] as String?) ?? '';
        if (name.toLowerCase().endsWith('.apk')) {
          apkUrl = (a['browser_download_url'] as String?) ?? '';
          break;
        }
      }
      if (apkUrl.isEmpty) return null;

      final name = (data['name'] as String?)?.trim();
      return UpdateInfo(
        versionName: (name == null || name.isEmpty) ? tag : name,
        buildNumber: remoteBuild,
        apkUrl: apkUrl,
        notes: (data['body'] as String?)?.trim() ?? '',
      );
    } catch (_) {
      // Offline or API error — silently skip; we try again next launch.
      return null;
    }
  }
}
