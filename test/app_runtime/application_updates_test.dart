import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/app_runtime/application_updates.dart';
import 'package:venera_next/foundation/application_update_service.dart';

void main() {
  test('Android updates default to the Leaf release repository', () async {
    final service = createApplicationUpdates(isAndroid: true);

    expect(service.isEnabled, isTrue);
    expect(
      service.releasePageUrl,
      'https://github.com/typhoonwhale/VeneraNext-Leaf/releases',
    );
    await service.closeAndWait();
  });

  test('Android updates refuse the upstream repository', () async {
    final service = createApplicationUpdates(
      isAndroid: true,
      androidReleaseRepository:
          ApplicationUpdateService.defaultReleaseRepository,
    );

    expect(service.isEnabled, isFalse);
    await service.closeAndWait();
  });

  test(
    'Android updates refuse case variants of the upstream repository',
    () async {
      final service = createApplicationUpdates(
        isAndroid: true,
        androidReleaseRepository: 'cYrIlPeNg/VeNeRa-NeXt',
      );

      expect(service.isEnabled, isFalse);
      await service.closeAndWait();
    },
  );

  test('Android updates use the configured Leaf release repository', () async {
    final service = createApplicationUpdates(
      isAndroid: true,
      androidReleaseRepository: 'typhoonwhale/VeneraNext-Leaf',
    );

    expect(service.isEnabled, isTrue);
    expect(
      service.releasePageUrl,
      'https://github.com/typhoonwhale/VeneraNext-Leaf/releases',
    );
    await service.closeAndWait();
  });

  test('other platforms keep the upstream update repository', () async {
    final service = createApplicationUpdates(
      isAndroid: false,
      androidReleaseRepository: 'typhoonwhale/VeneraNext-Leaf',
    );

    expect(service.isEnabled, isTrue);
    expect(
      service.releasePageUrl,
      'https://github.com/CyrilPeng/venera-next/releases',
    );
    await service.closeAndWait();
  });
}
