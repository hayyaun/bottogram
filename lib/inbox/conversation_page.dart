import 'dart:async';
import 'dart:io' as io;

import 'package:bottogram/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:bottogram/ui/design.dart';
import 'package:open_filex/open_filex.dart';

import 'diagnostics.dart';
import 'models.dart';
import 'repository.dart';
import 'settings_page.dart';
import 'transformer.dart';

class InboxConversationPage extends StatefulWidget {
  const InboxConversationPage({
    super.key,
    required this.repository,
    required this.user,
    required this.send,
    required this.source,
  });
  final InboxRepository repository;
  final KnownUser user;
  final Future<void> Function(String text) send;
  final AttachmentSource source;
  @override
  State<InboxConversationPage> createState() => _InboxConversationPageState();
}

class _InboxConversationPageState extends State<InboxConversationPage> {
  final _draft = TextEditingController();
  final Set<String> _opening = {};
  StreamSubscription<void>? _subscription;
  List<CachedMessage>? _messages;
  String? _error;
  bool _sending = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _subscription = widget.repository.changes.listen((_) => _refresh());
    _refresh();
  }

  Future<void> _refresh() async {
    final request = ++_request;
    try {
      final messages = await widget.repository.messages(widget.user.id);
      if (mounted && request == _request) setState(() => _messages = messages);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = context.strings.couldNotReadThisConversationTry,
        );
      }
    }
  }

  Future<void> _send() async {
    if (_sending || _draft.text.trim().isEmpty) return;
    final text = _draft.text;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.send(text);
      if (mounted) {
        if (_draft.text == text) _draft.clear();
        await _refresh();
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is InboxException
              ? error.message
              : replyError(error),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _open(CachedMessage message) async {
    if (_opening.contains(message.key)) return;
    final strings = context.strings;
    setState(() => _opening.add(message.key));
    try {
      final file = await widget.repository.openAttachment(
        message,
        widget.source,
      );
      if (!mounted) return;
      if (message.attachment!.isImage) {
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) =>
                _InboxImagePage(file: file, repository: widget.repository),
          ),
        );
      } else {
        final result = await OpenFilex.open(
          file.path,
          type: message.attachment!.mimeType,
        );
        if (result.type != ResultType.done) {
          throw InboxException(strings.noViewerCouldOpenThisAttachment);
        }
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is InboxException
              ? error.message
              : context.strings.couldNotOpenThisAttachmentTry,
        );
      }
    } finally {
      if (mounted) setState(() => _opening.remove(message.key));
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.user.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(
            widget.user.username == null
                ? '${widget.user.id}'
                : '@${widget.user.username}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: context.strings.inboxSettings,
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => InboxSettingsPage(repository: widget.repository),
            ),
          ),
        ),
      ],
    ),
    body: SafeArea(
      child: BContent(
        maxWidth: 960,
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            if (MediaQuery.viewInsetsOf(context).bottom == 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: Text(
                  context.strings.latest20RetainedMessagesClearedOr,
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ),
            if (widget.repository.lastError != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: BNotice(
                  message: InboxStorageProblem.writeFailed.message(context),
                  error: true,
                ),
              ),
            Expanded(
              child: _messages == null
                  ? const Center(child: CircularProgressIndicator())
                  : _messages!.isEmpty
                  ? BEmptyState(
                      icon: Icons.chat_bubble_outline_rounded,
                      title: context.strings.noRetainedMessages,
                      message: context.strings.historyMayHaveBeenClearedOr,
                    )
                  : ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                      itemCount: _messages!.length,
                      itemBuilder: (context, index) {
                        final message =
                            _messages![_messages!.length - 1 - index];
                        final attachment = message.attachment;
                        final ink = message.outgoing
                            ? BColors.of(context).canvas
                            : BColors.of(context).ink;
                        return Align(
                          key: ValueKey(message.key),
                          alignment: message.outgoing
                              ? AlignmentDirectional.centerEnd
                              : AlignmentDirectional.centerStart,
                          child: Container(
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.sizeOf(context).width < 600
                                  ? MediaQuery.sizeOf(context).width * .82
                                  : 520,
                            ),
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: message.outgoing
                                  ? BColors.of(context).ink
                                  : BColors.of(context).surface,
                              border: message.outgoing
                                  ? null
                                  : Border.all(color: BColors.of(context).line),
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(16),
                                topRight: const Radius.circular(16),
                                bottomLeft: Radius.circular(
                                  message.outgoing ? 16 : 4,
                                ),
                                bottomRight: Radius.circular(
                                  message.outgoing ? 4 : 16,
                                ),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  message.outgoing
                                      ? context.strings.bot
                                      : widget.user.name,
                                  style: BottogramDesign.text(
                                    13,
                                    strong: true,
                                    color: message.outgoing
                                        ? BColors.of(context).inverseMuted
                                        : BColors.of(context).muted,
                                  ),
                                ),
                                if (message.text.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    child: SelectableText(
                                      message.text,
                                      style: BottogramDesign.text(
                                        16,
                                        color: ink,
                                      ),
                                    ),
                                  ),
                                if (attachment != null)
                                  TextButton.icon(
                                    style: TextButton.styleFrom(
                                      foregroundColor: ink,
                                      alignment:
                                          AlignmentDirectional.centerStart,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                    ),
                                    onPressed: _opening.contains(message.key)
                                        ? null
                                        : () => _open(message),
                                    icon: _opening.contains(message.key)
                                        ? SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: ink,
                                            ),
                                          )
                                        : Icon(
                                            attachment.isImage
                                                ? Icons.image_outlined
                                                : Icons.attach_file,
                                          ),
                                    label: Text(
                                      '${attachment.name}${attachment.size == null ? '' : ' · ${formatInboxBytes(attachment.size!)}'}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                Text(
                                  '${context.formatDateAndTime(DateTime.fromMillisecondsSinceEpoch(message.date * 1000))}${message.edited ? context.strings.inboxEditedSuffix : ''}',
                                  style: BottogramDesign.text(
                                    13,
                                    color: message.outgoing
                                        ? BColors.of(context).inverseMuted
                                        : BColors.of(context).muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: BNotice(message: _error!, error: true),
              ),
            Container(
              decoration: BoxDecoration(
                color: BColors.of(context).surface,
                border: Border(
                  top: BorderSide(color: BColors.of(context).line),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _draft,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 4096,
                      decoration: InputDecoration(
                        labelText: context.strings.replyAsBot,
                        hintText: context.strings.writeAMessage,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 28),
                    child: IconButton.filled(
                      tooltip: context.strings.sendReply,
                      style: IconButton.styleFrom(
                        backgroundColor: BColors.of(context).ink,
                        foregroundColor: BColors.of(context).canvas,
                      ),
                      onPressed: _sending ? null : _send,
                      icon: _sending
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: BColors.of(context).canvas,
                              ),
                            )
                          : const Icon(Icons.arrow_upward_rounded),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _InboxImagePage extends StatefulWidget {
  const _InboxImagePage({required this.file, required this.repository});
  final io.File file;
  final InboxRepository repository;
  @override
  State<_InboxImagePage> createState() => _InboxImagePageState();
}

class _InboxImagePageState extends State<_InboxImagePage> {
  StreamSubscription<void>? _subscription;
  bool _available = true;
  late final int _generation;
  late final ImageProvider _image;
  @override
  void initState() {
    super.initState();
    _image = ResizeImage(
      FileImage(widget.file),
      width: 1600,
      height: 1600,
      policy: ResizeImagePolicy.fit,
    );
    _generation = widget.repository.generation;
    _subscription = widget.repository.changes.listen((_) async {
      if (widget.repository.generation != _generation ||
          !await widget.file.exists()) {
        await _image.evict();
        if (mounted) setState(() => _available = false);
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _image.evict();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.strings.attachment)),
    body: Center(
      child: !_available
          ? Text(context.strings.thisAttachmentWasRemovedFromThe)
          : InteractiveViewer(
              child: Image(
                image: _image,
                errorBuilder: (_, _, _) =>
                    Text(context.strings.couldNotDisplayThisImage),
              ),
            ),
    ),
  );
}
