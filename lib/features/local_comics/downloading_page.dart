import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:venera_next/components/button.dart';
import 'package:venera_next/components/menu.dart';
import 'package:venera_next/components/pop_up_widget.dart';
import 'package:venera_next/foundation/context.dart';
import 'package:venera_next/foundation/image_provider/cached_image.dart';
import 'package:venera_next/features/local_comics/download_task.dart';
import 'package:venera_next/features/local_comics/local.dart';
import 'package:venera_next/foundation/file_system.dart';
import 'package:venera_next/foundation/translations.dart';
import 'package:venera_next/foundation/widget_utils.dart';

class DownloadingPage extends StatefulWidget {
  const DownloadingPage({super.key});

  @override
  State<DownloadingPage> createState() => _DownloadingPageState();
}

class _DownloadingPageState extends State<DownloadingPage> {
  DownloadTask? activeTask;

  late final LocalManager manager = LocalManager();

  @override
  void initState() {
    super.initState();
    manager.addListener(update);
    _syncActiveTask();
  }

  @override
  void dispose() {
    manager.removeListener(update);
    activeTask?.removeListener(update);
    super.dispose();
  }

  void _syncActiveTask() {
    final current = manager.activeDownloadTask;
    if (!identical(current, activeTask)) {
      activeTask?.removeListener(update);
      activeTask = current;
      activeTask?.addListener(update);
    }
  }

  void update() {
    _syncActiveTask();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final normal = <DownloadTask>[];
    final parked = <DownloadTask>[];
    for (final task in manager.downloadingTasks) {
      (manager.downloadState(task) == DownloadTaskState.normal
              ? normal
              : parked)
          .add(task);
    }
    final items = <Widget>[
      buildTop(),
      if (normal.isNotEmpty) _buildHeader("Downloading / Queued".tl),
      for (final task in normal) _buildTile(task, DownloadTaskState.normal),
      if (parked.isNotEmpty) _buildHeader("Paused / Failed".tl),
      for (final task in parked) _buildTile(task, manager.downloadState(task)),
    ];
    return PopUpWidgetScaffold(
      title: "",
      body: ListView.builder(
        itemCount: items.length,
        itemBuilder: (BuildContext context, int i) => items[i],
      ),
    );
  }

  Widget _buildHeader(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Text(text, style: ts.s14.bold),
  );

  Widget _buildTile(DownloadTask task, DownloadTaskState state) =>
      _DownloadTaskTile(
        key: ValueKey(task),
        task: task,
        state: state,
        manager: manager,
      );

  Widget buildTop() {
    final active = manager.activeDownloadTask;
    final resumePending = manager.isDownloadResumePending;
    final idle = active == null || (active.isPaused && !resumePending);
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: context.colorScheme.outlineVariant,
            width: 0.6,
          ),
        ),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          if (idle)
            Text("Paused".tl, style: ts.s18.bold)
          else
            Text(
              "${bytesToReadableString(active.speed)}/s",
              style: ts.s18.bold,
            ),
          if (active != null)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // Normal tasks can be idle after a system pause or a
                // startup that did not resume them.
                if (idle)
                  OutlinedButton(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.play_arrow, size: 18),
                        const SizedBox(width: 4),
                        Text("Start".tl),
                      ],
                    ),
                    onPressed: () {
                      manager.resumeDownload(active);
                    },
                  ),
                OutlinedButton(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.pause, size: 18),
                      const SizedBox(width: 4),
                      Text("Pause all".tl),
                    ],
                  ),
                  onPressed: () {
                    manager.pauseAllDownloads();
                  },
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _DownloadTaskTile extends StatefulWidget {
  const _DownloadTaskTile({
    required this.task,
    required this.state,
    required this.manager,
    super.key,
  });

  final DownloadTask task;
  final DownloadTaskState state;
  final LocalManager manager;

  @override
  State<_DownloadTaskTile> createState() => _DownloadTaskTileState();
}

class _DownloadTaskTileState extends State<_DownloadTaskTile> {
  late DownloadTask task;

  @override
  void initState() {
    task = widget.task;
    task.addListener(update);
    super.initState();
  }

  @override
  void dispose() {
    task.removeListener(update);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _DownloadTaskTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.task, widget.task)) {
      task.removeListener(update);
      task = widget.task;
      task.addListener(update);
    }
  }

  void update() {
    setState(() {});
  }

  /// A restored failure keeps its saved message, not the task's own.
  String? get _errorMessage => widget.task.isError
      ? widget.task.message
      : widget.manager.downloadErrorMessage(widget.task);

  void _showErrorDetails(String message) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Download error'.tl),
        scrollable: true,
        content: SelectableText(message),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: message)),
            child: Text('Copy'.tl),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Close'.tl),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final errorMessage = _errorMessage;
    final String? status;
    if (errorMessage != null) {
      status = errorMessage;
    } else if (state == DownloadTaskState.error) {
      // Snapshots from older versions keep the state without a message.
      status = "Error".tl;
    } else if (state == DownloadTaskState.paused) {
      status = "Paused".tl;
    } else if (!widget.task.isPaused) {
      status = widget.task.message;
    } else {
      status = null;
    }
    return Container(
      height:
          136 *
          (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(
            1.0,
            double.infinity,
          ),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Row(
        children: [
          Container(
            width: 82,
            height: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: context.colorScheme.primaryContainer,
            ),
            clipBehavior: Clip.antiAlias,
            child: widget.task.cover == null
                ? null
                : Image(
                    image: CachedImageProvider(widget.task.cover!),
                    filterQuality: FilterQuality.medium,
                    fit: BoxFit.cover,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.task.title,
                        style: Theme.of(context).textTheme.bodyMedium,
                        maxLines: 2,
                      ),
                    ),
                    MenuButton(
                      // Entries are rebuilt with every progress update; the
                      // open menu belongs to the task in its current state.
                      identity: (widget.task, state),
                      entries: [
                        if (errorMessage != null)
                          MenuEntry(
                            icon: Icons.error_outline,
                            text: 'Error details'.tl,
                            onClick: () => _showErrorDetails(errorMessage),
                          ),
                        MenuEntry(
                          icon: Icons.close,
                          text: "Cancel".tl,
                          onClick: () {
                            widget.manager.cancelDownload(widget.task);
                          },
                        ),
                        MenuEntry(
                          icon: Icons.vertical_align_top,
                          text: "Move To First".tl,
                          onClick: () {
                            widget.manager.moveToFirst(widget.task);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
                const Spacer(),
                Row(
                  children: [
                    Expanded(
                      child: status == null
                          ? const SizedBox()
                          : Text(status, style: ts.s12, maxLines: 3),
                    ),
                    if (state != DownloadTaskState.normal)
                      TextButton.icon(
                        icon: const Icon(Icons.play_arrow, size: 18),
                        label: Text("Continue".tl),
                        onPressed: () {
                          widget.manager.resumeDownload(widget.task);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(value: widget.task.progress),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
