/// Release metadata used by the in-app update prompt and its cache.
///
/// The release page and APK are deliberately derived from one release record.
/// An invalid or unavailable APK does not erase the release information: the
/// UI can still explain the problem and offer the release page.
class ApplicationUpdateRelease {
  const ApplicationUpdateRelease({
    required this.version,
    required this.notes,
    required this.pageUrl,
    this.asset,
    this.assetError,
  });

  static const assetMissing = 'asset_missing';
  static const assetAmbiguous = 'asset_ambiguous';
  static const assetNotUploaded = 'asset_not_uploaded';
  static const assetInvalidSize = 'asset_invalid_size';
  static const assetInvalidDigest = 'asset_invalid_digest';
  static const assetInvalidUrl = 'asset_invalid_url';
  static const assetInvalidMetadata = 'asset_invalid_metadata';

  static const _assetErrors = {
    assetMissing,
    assetAmbiguous,
    assetNotUploaded,
    assetInvalidSize,
    assetInvalidDigest,
    assetInvalidUrl,
    assetInvalidMetadata,
  };

  final String version;
  final String notes;
  final String pageUrl;
  final ApplicationUpdateAsset? asset;
  final String? assetError;

  /// Builds metadata from the selected GitHub release response object.
  factory ApplicationUpdateRelease.fromReleaseMetadata(
    Map release, {
    required String repository,
  }) {
    final rawTag = release['tag_name'];
    if (rawTag is! String || rawTag.trim().isEmpty) {
      throw const FormatException('release_invalid_metadata');
    }
    final version = _versionFromTag(rawTag);
    final pageUrl = _releasePageUri(repository, rawTag).toString();
    final notes = release['body'] is String ? release['body'] as String : '';
    final rawAssets = release['assets'];
    final matches = <Map>[];
    if (rawAssets is List) {
      for (final rawAsset in rawAssets) {
        if (rawAsset is! Map) continue;
        final name = rawAsset['name'];
        if (_assetVersion(name) == version) matches.add(rawAsset);
      }
    }

    if (matches.isEmpty) {
      return ApplicationUpdateRelease(
        version: version,
        notes: notes,
        pageUrl: pageUrl,
        assetError: assetMissing,
      );
    }
    if (matches.length != 1) {
      return ApplicationUpdateRelease(
        version: version,
        notes: notes,
        pageUrl: pageUrl,
        assetError: assetAmbiguous,
      );
    }

    final candidate = matches.single;
    final name = candidate['name'];
    final rawUrl = candidate['browser_download_url'];
    final size = candidate['size'];
    final digest = candidate['digest'];
    final id = candidate['id'];
    if (candidate['state'] != 'uploaded') {
      return ApplicationUpdateRelease(
        version: version,
        notes: notes,
        pageUrl: pageUrl,
        assetError: assetNotUploaded,
      );
    }
    if (name is! String || size is! int || size <= 0) {
      return ApplicationUpdateRelease(
        version: version,
        notes: notes,
        pageUrl: pageUrl,
        assetError: assetInvalidSize,
      );
    }
    if (digest is! String || !_digestPattern.hasMatch(digest)) {
      return ApplicationUpdateRelease(
        version: version,
        notes: notes,
        pageUrl: pageUrl,
        assetError: assetInvalidDigest,
      );
    }
    if ((id != null && (id is! int || id <= 0)) || rawUrl is! String) {
      return ApplicationUpdateRelease(
        version: version,
        notes: notes,
        pageUrl: pageUrl,
        assetError: assetInvalidMetadata,
      );
    }

    final url = Uri.tryParse(rawUrl);
    final tagSegments = url?.pathSegments;
    if (url == null ||
        !isAllowedUpdateDownloadUri(
          url,
          initial: true,
          repository: repository,
        ) ||
        tagSegments == null ||
        tagSegments.length != 6 ||
        tagSegments[4] != rawTag ||
        tagSegments[5] != name) {
      return ApplicationUpdateRelease(
        version: version,
        notes: notes,
        pageUrl: pageUrl,
        assetError: assetInvalidUrl,
      );
    }

    return ApplicationUpdateRelease(
      version: version,
      notes: notes,
      pageUrl: pageUrl,
      asset: ApplicationUpdateAsset(
        name: name,
        url: url,
        size: size,
        sha256: digest.substring('sha256:'.length).toLowerCase(),
        id: id as int?,
      ),
    );
  }

  factory ApplicationUpdateRelease.fromJson(
    Map<String, Object?> json, {
    String? repository,
  }) {
    final version = json['version'];
    final notes = json['notes'];
    final pageUrl = json['pageUrl'];
    final rawAsset = json['asset'];
    final assetError = json['assetError'];
    if (version is! String ||
        version.isEmpty ||
        notes is! String ||
        pageUrl is! String ||
        (assetError != null &&
            (assetError is! String || !_assetErrors.contains(assetError)))) {
      throw const FormatException('release_invalid_metadata');
    }

    final pageUri = Uri.tryParse(pageUrl);
    final pageRepository = pageUri == null
        ? null
        : _repositoryFromPageUri(pageUri, version);
    if (pageRepository == null ||
        (repository != null &&
            repository.toLowerCase() != pageRepository.toLowerCase())) {
      throw const FormatException('release_invalid_metadata');
    }

    if (rawAsset == null) {
      if (assetError == null) {
        throw const FormatException('release_invalid_metadata');
      }
      return ApplicationUpdateRelease(
        version: version,
        notes: notes,
        pageUrl: pageUrl,
        assetError: assetError as String,
      );
    }
    if (rawAsset is! Map<String, Object?> || assetError != null) {
      throw const FormatException('release_invalid_metadata');
    }
    final asset = ApplicationUpdateAsset.fromJson(
      rawAsset,
      repository: pageRepository,
      version: version,
    );
    return ApplicationUpdateRelease(
      version: version,
      notes: notes,
      pageUrl: pageUrl,
      asset: asset,
    );
  }

  Map<String, Object?> toJson() => {
    'version': version,
    'notes': notes,
    'pageUrl': pageUrl,
    'asset': asset?.toJson(),
    'assetError': assetError,
  };
}

class ApplicationUpdateAsset {
  const ApplicationUpdateAsset({
    required this.name,
    required this.url,
    required this.size,
    required this.sha256,
    this.id,
  });

  final String name;
  final Uri url;
  final int size;
  final String sha256;
  final int? id;

  factory ApplicationUpdateAsset.fromJson(
    Map<String, Object?> json, {
    String? repository,
    String? version,
  }) {
    final name = json['name'];
    final rawUrl = json['url'];
    final size = json['size'];
    final digest = json['sha256'];
    final id = json['id'];
    if (name is! String ||
        rawUrl is! String ||
        size is! int ||
        size <= 0 ||
        digest is! String ||
        !_digestPattern.hasMatch('sha256:$digest') ||
        (id != null && (id is! int || id <= 0))) {
      throw const FormatException(
        ApplicationUpdateRelease.assetInvalidMetadata,
      );
    }
    final assetUrl = Uri.tryParse(rawUrl);
    final segments = assetUrl?.pathSegments;
    if (assetUrl == null ||
        segments == null ||
        segments.length != 6 ||
        segments[2] != 'releases' ||
        segments[3] != 'download' ||
        !isAllowedUpdateDownloadUri(
          assetUrl,
          initial: true,
          repository: repository ?? '${segments[0]}/${segments[1]}',
        )) {
      throw const FormatException(ApplicationUpdateRelease.assetInvalidUrl);
    }
    final inferredRepository = '${segments[0]}/${segments[1]}';
    final inferredVersion = _assetVersion(name);
    final tagVersion = _versionFromTag(segments[4]);
    if (inferredVersion == null ||
        inferredVersion != tagVersion ||
        segments[5] != name ||
        (version != null && inferredVersion != version) ||
        (repository != null &&
            repository.toLowerCase() != inferredRepository.toLowerCase())) {
      throw const FormatException(
        ApplicationUpdateRelease.assetInvalidMetadata,
      );
    }
    return ApplicationUpdateAsset(
      name: name,
      url: assetUrl,
      size: size,
      sha256: digest.toLowerCase(),
      id: id as int?,
    );
  }

  Map<String, Object?> toJson() => {
    'name': name,
    'url': url.toString(),
    'size': size,
    'sha256': sha256,
    'id': id,
  };
}

/// Validates the initial asset URL and every URL reached by a redirect.
///
/// Initial URLs must identify this repository's exact release asset. Redirects
/// may use GitHub's two release-asset hosts; arbitrary githubusercontent.com
/// subdomains are intentionally not admitted.
bool isAllowedUpdateDownloadUri(
  Uri uri, {
  required bool initial,
  required String repository,
}) {
  if (!_validRepository(repository) ||
      uri.scheme.toLowerCase() != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.authority.toLowerCase() != uri.host.toLowerCase() ||
      uri.hasFragment) {
    return false;
  }

  if (initial) {
    if (uri.host.toLowerCase() != 'github.com' || uri.hasQuery) return false;
    final segments = uri.pathSegments;
    if (segments.length != 6 ||
        segments[2] != 'releases' ||
        segments[3] != 'download') {
      return false;
    }
    final configured = repository.split('/');
    if (segments[0] != configured[0] || segments[1] != configured[1]) {
      return false;
    }
    final tag = segments[4];
    final name = segments[5];
    final version = _assetVersion(name);
    if (version == null || _versionFromTag(tag) != version) return false;
    final expectedPath =
        '/${configured[0]}/${configured[1]}/releases/download/$tag/$name';
    return uri.path == expectedPath;
  }

  final host = uri.host.toLowerCase();
  if (host != 'github.com' &&
      host != 'release-assets.githubusercontent.com' &&
      host != 'objects.githubusercontent.com') {
    return false;
  }
  if (host == 'github.com' && uri.hasQuery) return false;
  final segments = uri.pathSegments;
  return segments.isNotEmpty &&
      segments.every(
        (segment) =>
            segment.isNotEmpty &&
            segment != '.' &&
            segment != '..' &&
            !segment.contains('\\'),
      );
}

final _digestPattern = RegExp(r'^sha256:[0-9a-fA-F]{64}$');
final _legacyAssetName = RegExp(
  r'^Leaf-([A-Za-z0-9][A-Za-z0-9.+-]*)-[0-9]+-release-arm64-v8a\.apk$',
);
final _buildAssetName = RegExp(
  r'^VeneraNext-Leaf-([A-Za-z0-9][A-Za-z0-9.+-]*)-android-arm64-v8a\.apk$',
);
final _repositoryPart = RegExp(r'^[A-Za-z0-9_.-]+$');

String? _assetVersion(Object? name) {
  if (name is! String) return null;
  return _legacyAssetName.firstMatch(name)?.group(1) ??
      _buildAssetName.firstMatch(name)?.group(1);
}

String _versionFromTag(String tag) => tag.replaceFirst(RegExp(r'^[vV]'), '');

bool _validRepository(String repository) {
  final parts = repository.split('/');
  return parts.length == 2 &&
      parts.every(
        (part) => _repositoryPart.hasMatch(part) && part != '.' && part != '..',
      );
}

Uri _releasePageUri(String repository, String tag) {
  if (!_validRepository(repository)) {
    throw const FormatException('release_invalid_metadata');
  }
  return Uri(
    scheme: 'https',
    host: 'github.com',
    pathSegments: [...repository.split('/'), 'releases', 'tag', tag],
  );
}

String? _repositoryFromPageUri(Uri uri, String version) {
  if (uri.scheme.toLowerCase() != 'https' ||
      uri.host.toLowerCase() != 'github.com' ||
      uri.userInfo.isNotEmpty ||
      uri.authority.toLowerCase() != 'github.com' ||
      uri.hasQuery ||
      uri.hasFragment) {
    return null;
  }
  final segments = uri.pathSegments;
  if (segments.length != 5 ||
      segments[2] != 'releases' ||
      segments[3] != 'tag' ||
      _versionFromTag(segments[4]) != version) {
    return null;
  }
  final repository = '${segments[0]}/${segments[1]}';
  if (!_validRepository(repository)) return null;
  final expected = _releasePageUri(repository, segments[4]);
  return uri.path == expected.path ? repository : null;
}
