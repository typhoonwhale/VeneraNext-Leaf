import 'package:venera_next/features/comic_source/comic_source_api.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/application_preferences.dart';
import 'package:venera_next/foundation/global_preference_store.dart';
import 'package:venera_next/foundation/application_update_service.dart';
import 'package:venera_next/foundation/application_update_download.dart';
import 'package:venera_next/foundation/startup_update_check.dart';
import 'package:venera_next/foundation/update_check_schedule.dart';
import 'package:venera_next/network/app_dio.dart';
import 'package:venera_next/network/request_scope.dart';

ApplicationUpdateService createApplicationUpdates({
  bool? isAndroid,
  String androidReleaseRepository = const String.fromEnvironment(
    'LEAF_ANDROID_RELEASE_REPOSITORY',
    defaultValue: ApplicationUpdateService.androidDefaultReleaseRepository,
  ),
}) {
  final useAndroidChannel = isAndroid ?? App.isAndroid;
  final configuredRepository = androidReleaseRepository.trim();
  final upstreamRepository = ApplicationUpdateService.defaultReleaseRepository
      .toLowerCase();
  final String? releaseRepository;
  if (!useAndroidChannel) {
    releaseRepository = ApplicationUpdateService.defaultReleaseRepository;
  } else if (configuredRepository.isEmpty ||
      configuredRepository.toLowerCase() == upstreamRepository) {
    // Keep forked Android packages on their own release page.
    releaseRepository = null;
  } else {
    releaseRepository = configuredRepository;
  }

  return ApplicationUpdateService(
    // Public release metadata needs network preferences, not application cookies
    // or an interactive Cloudflare interceptor.
    createClient: () => Dio()..httpClientAdapter = RHttpAdapter(),
    currentVersion: () => App.version,
    releaseRepository: releaseRepository,
  );
}

/// Created only after bootstrap has established the private cache path.
ApplicationUpdateDownload? createApplicationUpdateDownload(
  ApplicationUpdateService service, {
  bool? isAndroid,
  String? cacheRoot,
}) {
  if (!(isAndroid ?? App.isAndroid) || !service.isEnabled) return null;
  return ApplicationUpdateDownload(
    cacheRoot: cacheRoot ?? App.cachePath,
    repository: service.releaseRepository!,
    dioFactory: () => Dio()..httpClientAdapter = RHttpAdapter(),
  );
}

UpdateCheckSchedule createUpdateCheckSchedule({DateTime Function()? now}) =>
    UpdateCheckSchedule(
      read: () => appdata.implicitData,
      update: (change) => appdata.updateImplicit(change),
      now: now,
    );

StartupUpdateCheck createStartupUpdateCheck({
  required SourceUpdateService sources,
  required Future<void> Function(RequestScope) checkApplication,
  UpdateCheckSchedule? schedule,
}) {
  final timing = schedule ?? createUpdateCheckSchedule();
  return StartupUpdateCheck(
    reserveSourceCheck: timing.reserveSourceCheck,
    reserveApplicationCheck: timing.reserveApplicationCheck,
    checkSources: () async {
      await sources.checkUpdates();
    },
    applicationCheckEnabled: () => GlobalPreferenceStore(
      appdata.settings,
    ).read(AppPreferences.checkUpdateOnStart),
    checkApplication: checkApplication,
  );
}
