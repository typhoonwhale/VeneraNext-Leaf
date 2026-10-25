import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/foundation/application_update_release.dart';

const _repository = 'typhoonwhale/VeneraNext-Leaf';
const _tag = 'v1.2.3';
const _version = '1.2.3';
final _digest = List.filled(64, 'a').join();

void main() {
  test('both supported ARM64 release names produce serializable metadata', () {
    for (final name in [
      'Leaf-1.2.3-2402-release-arm64-v8a.apk',
      'VeneraNext-Leaf-1.2.3-android-arm64-v8a.apk',
    ]) {
      final release = _release([_asset(name)]);
      expect(release.version, _version);
      expect(release.notes, 'Notes for this release');
      expect(release.assetError, isNull);
      expect(release.asset?.name, name);
      expect(release.asset?.size, 1234);
      expect(release.asset?.sha256, _digest);
      expect(release.asset?.id, 52);
      expect(
        release.asset?.url.toString(),
        'https://github.com/$_repository/releases/download/$_tag/$name',
      );

      final decoded = jsonDecode(jsonEncode(release.toJson()));
      final restored = ApplicationUpdateRelease.fromJson(
        decoded as Map<String, Object?>,
        repository: _repository,
      );
      expect(restored.toJson(), release.toJson());
      expect(
        ApplicationUpdateAsset.fromJson(
          release.asset!.toJson(),
          repository: _repository,
          version: _version,
        ).toJson(),
        release.asset!.toJson(),
      );
    }
  });

  test(
    'asset selection reports absence and ambiguity without losing release',
    () {
      final missing = _release([
        _asset('VeneraNext-Leaf-1.2.4-android-arm64-v8a.apk'),
        _asset('VeneraNext-Leaf-1.2.3-android-x86_64.apk'),
      ]);
      expect(missing.version, _version);
      expect(missing.asset, isNull);
      expect(missing.assetError, ApplicationUpdateRelease.assetMissing);

      final ambiguous = _release([
        _asset('Leaf-1.2.3-2402-release-arm64-v8a.apk'),
        _asset('VeneraNext-Leaf-1.2.3-android-arm64-v8a.apk'),
      ]);
      expect(ambiguous.asset, isNull);
      expect(ambiguous.assetError, ApplicationUpdateRelease.assetAmbiguous);

      final restored = ApplicationUpdateRelease.fromJson(
        jsonDecode(jsonEncode(missing.toJson())) as Map<String, Object?>,
        repository: _repository,
      );
      expect(restored.asset, isNull);
      expect(restored.assetError, ApplicationUpdateRelease.assetMissing);
    },
  );

  test('incomplete candidate metadata is rejected with stable error keys', () {
    final uploading = _asset('VeneraNext-Leaf-1.2.3-android-arm64-v8a.apk')
      ..['state'] = 'new';
    expect(
      _release([uploading]).assetError,
      ApplicationUpdateRelease.assetNotUploaded,
    );

    final invalidSize = _asset('VeneraNext-Leaf-1.2.3-android-arm64-v8a.apk')
      ..['size'] = 0;
    expect(
      _release([invalidSize]).assetError,
      ApplicationUpdateRelease.assetInvalidSize,
    );

    final invalidDigest = _asset('VeneraNext-Leaf-1.2.3-android-arm64-v8a.apk')
      ..['digest'] = 'sha256:short';
    expect(
      _release([invalidDigest]).assetError,
      ApplicationUpdateRelease.assetInvalidDigest,
    );

    final invalidUrl = _asset('VeneraNext-Leaf-1.2.3-android-arm64-v8a.apk')
      ..['browser_download_url'] =
          'https://example.com/$_repository/releases/download/$_tag/VeneraNext-Leaf-1.2.3-android-arm64-v8a.apk';
    expect(
      _release([invalidUrl]).assetError,
      ApplicationUpdateRelease.assetInvalidUrl,
    );
  });

  test('initial and redirected URLs stay on the explicit GitHub allowlist', () {
    final name = 'VeneraNext-Leaf-1.2.3-android-arm64-v8a.apk';
    final valid = Uri.parse(
      'https://github.com/$_repository/releases/download/$_tag/$name',
    );
    expect(
      isAllowedUpdateDownloadUri(valid, initial: true, repository: _repository),
      isTrue,
    );

    for (final value in [
      'https://user@github.com/$_repository/releases/download/$_tag/$name',
      'https://github.com:444/$_repository/releases/download/$_tag/$name',
      'https://github.com/$_repository/releases/download/$_tag/$name?mirror=1',
      'https://github.com/another/repository/releases/download/$_tag/$name',
      'https://github.com/$_repository/releases/download/$_tag/%2F$name',
    ]) {
      expect(
        isAllowedUpdateDownloadUri(
          Uri.parse(value),
          initial: true,
          repository: _repository,
        ),
        isFalse,
        reason: value,
      );
    }

    for (final value in [
      // Dart normalizes the standard HTTPS port to the same origin.
      'https://objects.githubusercontent.com:443/objects/asset?token=signed',
      'https://github.com/typhoonwhale/VeneraNext-Leaf/releases/download/v1.2.3/$name',
      'https://release-assets.githubusercontent.com/objects/asset?token=signed',
      'https://objects.githubusercontent.com/objects/asset?token=signed',
    ]) {
      expect(
        isAllowedUpdateDownloadUri(
          Uri.parse(value),
          initial: false,
          repository: _repository,
        ),
        isTrue,
        reason: value,
      );
    }

    for (final value in [
      'http://release-assets.githubusercontent.com/objects/asset',
      'https://foo.githubusercontent.com/objects/asset',
      'https://attacker.example/objects/asset',
      'https://user@objects.githubusercontent.com/objects/asset?token=signed',
      'https://objects.githubusercontent.com:444/objects/asset?token=signed',
      'https://github.com/releases?next=download',
    ]) {
      expect(
        isAllowedUpdateDownloadUri(
          Uri.parse(value),
          initial: false,
          repository: _repository,
        ),
        isFalse,
        reason: value,
      );
    }
  });

  test('JSON cache reconstruction revalidates repository and asset fields', () {
    final release = _release([
      _asset('VeneraNext-Leaf-1.2.3-android-arm64-v8a.apk'),
    ]);
    final json = release.toJson();
    expect(
      () => ApplicationUpdateRelease.fromJson(
        json,
        repository: 'other/repository',
      ),
      throwsFormatException,
    );

    final tampered = Map<String, Object?>.from(json);
    tampered['asset'] = {...release.asset!.toJson(), 'size': 0};
    expect(
      () =>
          ApplicationUpdateRelease.fromJson(tampered, repository: _repository),
      throwsFormatException,
    );
  });
}

ApplicationUpdateRelease _release(List<Map<String, Object?>> assets) =>
    ApplicationUpdateRelease.fromReleaseMetadata({
      'tag_name': _tag,
      'body': 'Notes for this release',
      'assets': assets,
    }, repository: _repository);

Map<String, Object?> _asset(String name) => {
  'id': 52,
  'name': name,
  'state': 'uploaded',
  'size': 1234,
  'digest': 'sha256:$_digest',
  'browser_download_url':
      'https://github.com/$_repository/releases/download/$_tag/$name',
};
