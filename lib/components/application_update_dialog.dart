import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:venera_next/foundation/application_update_download.dart';
import 'package:venera_next/foundation/application_update_release.dart';
import 'package:venera_next/foundation/translations.dart';

/// The application controller owns I/O; this dialog only owns its presentation.
class ApplicationUpdateDialog extends StatefulWidget {
  const ApplicationUpdateDialog({
    required this.download,
    required this.release,
    required this.releasePageUrl,
    required this.onClose,
    this.canAct,
    super.key,
  });

  final ApplicationUpdateDownload download;
  final ApplicationUpdateRelease? release;
  final String? releasePageUrl;
  final VoidCallback onClose;
  final bool Function()? canAct;

  @override
  State<ApplicationUpdateDialog> createState() =>
      _ApplicationUpdateDialogState();
}

class _ApplicationUpdateDialogState extends State<ApplicationUpdateDialog> {
  bool _closing = false;
  String? _actionError;

  Future<void> _close() async {
    if (_closing || !(widget.canAct?.call() ?? true)) return;
    setState(() => _closing = true);
    try {
      final state = widget.download.state;
      if (state != ApplicationUpdateDownloadState.installing &&
          state != ApplicationUpdateDownloadState.blocked) {
        await widget.download.cancelAndClear();
      }
      if (mounted) widget.onClose();
    } catch (_) {
      if (mounted) {
        setState(() => _actionError = 'Update cache could not be cleaned');
      }
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  Future<void> _perform(Future<void> Function() action) async {
    if (_closing || !(widget.canAct?.call() ?? true)) return;
    setState(() => _actionError = null);
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => _actionError = 'Application update failed');
    }
  }

  String _assetError(String code) => switch (code) {
    ApplicationUpdateRelease.assetMissing =>
      'No compatible ARM64 release package is available',
    ApplicationUpdateRelease.assetAmbiguous =>
      'More than one compatible package was found',
    ApplicationUpdateRelease.assetNotUploaded =>
      'The release package is not fully uploaded',
    ApplicationUpdateRelease.assetInvalidSize =>
      'The release package size is invalid',
    ApplicationUpdateRelease.assetInvalidDigest =>
      'The release package has no valid SHA-256 digest',
    ApplicationUpdateRelease.assetInvalidUrl =>
      'The release download address is not trusted',
    _ => 'The release package information is invalid',
  };

  String _size(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.download,
    builder: (context, _) {
      final controller = widget.download;
      final release = controller.candidate ?? widget.release;
      final state = controller.state;
      final blocked = state == ApplicationUpdateDownloadState.blocked;
      final installing = state == ApplicationUpdateDownloadState.installing;
      final downloading = state == ApplicationUpdateDownloadState.downloading;
      final verifying = state == ApplicationUpdateDownloadState.verifying;
      final ready = state == ApplicationUpdateDownloadState.ready;
      final supported = controller.isSupported;
      final error = _actionError ?? controller.error;
      final canDownload =
          !_closing &&
          supported &&
          !controller.busy &&
          !blocked &&
          !ready &&
          release?.asset != null &&
          release?.assetError == null;
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _close();
        },
        child: AlertDialog(
          scrollable: true,
          title: Text(
            (blocked ? 'Installation not confirmed' : 'New version available')
                .tl,
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (release != null) ...[
                  Text('Version @v'.tlParams({'v': release.version})),
                  if (release.asset != null)
                    Text(
                      'Package size: @size'.tlParams({
                        'size': _size(release.asset!.size),
                      }),
                    ),
                  if (release.notes.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(release.notes),
                  ],
                ],
                if (!supported) ...[
                  const SizedBox(height: 12),
                  Text(
                    'In-app updates are unavailable for this build. Open the release page to update manually.'
                        .tl,
                  ),
                ] else if (release?.assetError != null) ...[
                  const SizedBox(height: 12),
                  Text(_assetError(release!.assetError!).tl),
                ],
                if (downloading || verifying) ...[
                  const SizedBox(height: 16),
                  LinearProgressIndicator(value: controller.progress / 100),
                  const SizedBox(height: 8),
                  Text(
                    downloading
                        ? 'Downloading: @percent% (@size)'.tlParams({
                            'percent': '${controller.progress}',
                            'size': _size(controller.received),
                          })
                        : 'Verifying update package'.tl,
                  ),
                ],
                if (ready) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Update package verified. Confirm installation in Android.'
                        .tl,
                  ),
                ],
                if (installing || blocked) ...[
                  const SizedBox(height: 12),
                  Text(
                    (blocked
                            ? 'The previous installation has no confirmed result. The package is kept. Complete the system installation or update manually from the release page.'
                            : 'Complete the permission or installation request in Android. The package will be kept.')
                        .tl,
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    error.tl,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: _closing ? null : _close,
              child: Text(
                (downloading || verifying
                        ? 'Cancel download'
                        : installing || blocked || ready
                        ? 'Close'
                        : 'Update later')
                    .tl,
              ),
            ),
            if (widget.releasePageUrl != null &&
                (!supported ||
                    blocked ||
                    error != null ||
                    release?.assetError != null))
              TextButton(
                onPressed: _closing
                    ? null
                    : () => _perform(() async {
                        if (!await launchUrlString(widget.releasePageUrl!)) {
                          throw StateError('Unable to open release page');
                        }
                      }),
                child: Text('Open release page'.tl),
              ),
            if (canDownload)
              FilledButton(
                onPressed: () => _perform(() => controller.download(release!)),
                child: Text(
                  (state == ApplicationUpdateDownloadState.failed
                          ? 'Retry download'
                          : 'Update now')
                      .tl,
                ),
              ),
            if (ready && supported)
              FilledButton(
                onPressed: _closing ? null : () => _perform(controller.install),
                child: Text('Install update'.tl),
              ),
          ],
        ),
      );
    },
  );
}
