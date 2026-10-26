import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/app_runtime/application_updates.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/app_data_operations.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/update_check_schedule.dart';
import 'package:venera_next/foundation/startup_update_check.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  App.dataPath = Directory.systemTemp.path;
  late Directory directory;
  late String oldPath;
  late Map<String, dynamic> oldData;
  late DateTime now;
  late UpdateCheckSchedule schedule;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('update-schedule-');
    oldPath = App.dataPath;
    oldData = Map.of(appdata.implicitData);
    App.dataPath = directory.path;
    appdata.implicitData.clear();
    now = DateTime(2026, 10, 26);
    schedule = createUpdateCheckSchedule(now: () => now);
  });
  tearDown(() {
    appdata.implicitData
      ..clear()
      ..addAll(oldData);
    App.dataPath = oldPath;
    directory.deleteSync(recursive: true);
  });

  test(
    'legacy source timestamp never suppresses first application check',
    () async {
      appdata.implicitData[UpdateCheckSchedule.sourceKey] =
          now.millisecondsSinceEpoch;
      expect(await schedule.reserveSourceCheck(), isFalse);
      expect(await schedule.reserveApplicationCheck(), isTrue);
      expect(await schedule.reserveApplicationCheck(), isFalse);
      now = now.add(const Duration(hours: 24));
      expect(await schedule.reserveApplicationCheck(), isTrue);
    },
  );

  test(
    'manual admission persists independently and survives a fresh schedule',
    () async {
      await schedule.reserveSourceCheck();
      final sourceTime = appdata.implicitData[UpdateCheckSchedule.sourceKey];
      now = now.add(const Duration(hours: 2));
      await schedule.recordManualCheck();
      final saved =
          jsonDecode(
                File('${directory.path}/implicitData.json').readAsStringSync(),
              )
              as Map;
      expect(
        saved[UpdateCheckSchedule.applicationKey],
        now.millisecondsSinceEpoch,
      );
      expect(saved[UpdateCheckSchedule.sourceKey], sourceTime);
      // The check may subsequently fail: admission time remains on disk.
      appdata.implicitData
        ..clear()
        ..addAll(Map<String, dynamic>.from(saved));
      final restarted = createUpdateCheckSchedule(now: () => now);
      expect(await restarted.reserveApplicationCheck(), isFalse);
      now = now.add(const Duration(hours: 23));
      expect(await restarted.reserveApplicationCheck(), isFalse);
      await restarted.recordManualCheck(); // Manual retry is never throttled.
      now = now.add(const Duration(hours: 24));
      expect(await restarted.reserveApplicationCheck(), isTrue);
    },
  );

  test(
    'queued older auto and manual admissions cannot overwrite a newer timestamp',
    () async {
      final permit = Completer<void>();
      final held = AppDataOperations.instance.run(() => permit.future);
      final automatic = schedule.reserveApplicationCheck();
      now = now.add(const Duration(hours: 1));
      final manual = schedule.recordManualCheck();
      final latest = now.millisecondsSinceEpoch;
      now = now.subtract(const Duration(hours: 2));
      final olderManual = schedule.recordManualCheck();
      permit.complete();
      await Future.wait([held, automatic, manual, olderManual]);
      final saved =
          jsonDecode(
                File('${directory.path}/implicitData.json').readAsStringSync(),
              )
              as Map;
      expect(saved[UpdateCheckSchedule.applicationKey], latest);
    },
  );
  test(
    'disabled startup consumes only source time; enabling checks application immediately',
    () async {
      var applications = 0;
      StartupUpdateCheck startup(bool enabled) => StartupUpdateCheck(
        reserveSourceCheck: schedule.reserveSourceCheck,
        reserveApplicationCheck: schedule.reserveApplicationCheck,
        checkSources: () async {},
        checkApplication: (_) async {
          applications++;
        },
        applicationCheckEnabled: () => enabled,
      );
      await startup(false).start();
      final saved =
          jsonDecode(
                File('${directory.path}/implicitData.json').readAsStringSync(),
              )
              as Map;
      expect(saved.containsKey(UpdateCheckSchedule.applicationKey), isFalse);
      await startup(true).start();
      expect(applications, 1);
      await startup(true).start();
      expect(applications, 1);
    },
  );
}
