import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image/image.dart' as image;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:zxing2/qrcode.dart' hide BarcodeFormat;

import '../store/bots.dart';
import '../ui/design.dart';
import '../units/virt_bot.dart';
import 'bot_transfer.dart';
import 'manifest.dart';

Future<void> showPluginBotQr(BuildContext context, VirtBot bot) async {
  if (!await _confirm(
    context,
    title: 'Share bot as QR code?',
    message:
        'Do not share this code with anyone. It contains the Telegram bot token, plugin API keys, and saved settings. Anyone who sees it can read those credentials.',
    action: 'Continue',
  )) {
    return;
  }
  if (!context.mounted ||
      !await _confirm(
        context,
        title: 'Reveal the private QR code?',
        message:
            'Scan it only with your own device. Keep it off screen shares, screenshots, and messages.',
        action: 'Show QR code',
      )) {
    return;
  }
  if (!context.mounted) return;
  try {
    final transfer = await context.read<BotsCubit>().exportPluginBot(bot);
    final result = QrValidator.validate(
      data: transfer.toLink(),
      version: QrVersions.auto,
      errorCorrectionLevel: QrErrorCorrectLevel.M,
    );
    final qr = result.qrCode;
    if (qr == null) {
      throw const PluginException(
        'This bot’s configuration is too large for a single QR code.',
      );
    }
    if (!context.mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Private bot QR code')),
          body: SingleChildScrollView(
            child: BContent(
              maxWidth: 528,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  BHeading(
                    title: transfer.name,
                    subtitle:
                        'Requires the exact installed plugin: ${transfer.pluginKey}',
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Anyone who sees this code can read the bot’s credentials.',
                  ),
                  const SizedBox(height: 16),
                  QrImageView.withQr(
                    qr: qr,
                    backgroundColor: Colors.white,
                    padding: const EdgeInsets.all(24),
                    semanticsLabel: 'Private bot QR code',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  } catch (error) {
    if (context.mounted) {
      _notice(context, error, 'The bot QR code could not be generated.');
    }
  }
}

enum _BotImportSource { backup, qr }

Future<void> chooseBotImport(BuildContext context) async {
  final source = await showDialog<_BotImportSource>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Import bots'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, _BotImportSource.backup),
          child: const ListTile(
            leading: Icon(Icons.folder_open_outlined),
            title: Text('Backup file'),
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, _BotImportSource.qr),
          child: const ListTile(
            leading: Icon(Icons.qr_code_scanner),
            title: Text('Scan QR code'),
          ),
        ),
      ],
    ),
  );
  if (source == null || !context.mounted) return;
  switch (source) {
    case _BotImportSource.backup:
      await context.read<BotsCubit>().import();
    case _BotImportSource.qr:
      await _importPluginBotQr(context);
  }
}

Future<void> _importPluginBotQr(BuildContext context) async {
  final bots = context.read<BotsCubit>();
  final link = await Navigator.of(
    context,
  ).push<String>(MaterialPageRoute(builder: (_) => const _BotQrScanner()));
  if (link == null || !context.mounted) return;
  try {
    final transfer = PluginBotTransfer.fromLink(link);
    final plugin = await bots.plugins.reviewBotTransfer(transfer);
    if (!context.mounted) return;
    final confirmed = await _confirm(
      context,
      title: 'Import ${transfer.name}?',
      message:
          '${plugin.name} ${plugin.version} is installed. This device will save the bot’s credentials and settings. The imported bot starts in the stopped state.',
      action: 'Import bot',
    );
    if (!confirmed || !context.mounted) return;
    await bots.importPluginBot(transfer);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Bot imported.')));
    }
  } catch (error) {
    if (context.mounted) {
      _notice(context, error, 'The bot QR code could not be imported.');
    }
  }
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        scrollable: true,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

void _notice(BuildContext context, Object error, String fallback) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(error is PluginException ? error.message : fallback),
    ),
  );
}

class _BotQrScanner extends StatefulWidget {
  const _BotQrScanner();

  @override
  State<_BotQrScanner> createState() => _BotQrScannerState();
}

class _BotQrScannerState extends State<_BotQrScanner> {
  bool _readingImage = false;
  bool _finished = false;
  String? _error;

  bool get _cameraSupported => switch (defaultTargetPlatform) {
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.macOS => true,
    _ => false,
  };

  void _finish(String link) {
    if (_finished || !mounted || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    _finished = true;
    Navigator.pop(context, link);
  }

  void _detected(BarcodeCapture capture) {
    if (_readingImage) return;
    for (final code in capture.barcodes) {
      final link = code.rawValue;
      if (code.format == BarcodeFormat.qrCode && link != null) {
        _finish(link);
        return;
      }
    }
  }

  Future<void> _openImage() async {
    if (_readingImage || _finished) return;
    setState(() {
      _readingImage = true;
      _error = null;
    });
    try {
      final file = await FilePicker.pickFile(
        dialogTitle: 'Open a bot QR image',
        type: FileType.custom,
        allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
      );
      if (file == null || !mounted) return;
      final path = file.path;
      if (path == null) throw const FormatException();
      final imageFile = File(path);
      if (await imageFile.length() > 16 * 1024 * 1024) {
        throw const FormatException();
      }
      final bytes = await imageFile.readAsBytes();
      final link = await compute(decodeBotQrImage, bytes);
      if (link == null) throw const FormatException();
      _finish(link);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No QR code could be read from this image.');
      }
    } finally {
      if (mounted && !_finished) setState(() => _readingImage = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan bot QR code')),
    body: SingleChildScrollView(
      child: BContent(
        maxWidth: 600,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BHeading(
              title: 'Import a plugin bot',
              subtitle: _cameraSupported
                  ? 'Point the camera at the Bottogram QR code, or open a QR image.'
                  : 'Open an image of the Bottogram QR code to scan it on this device.',
            ),
            const SizedBox(height: 20),
            if (_cameraSupported && !_readingImage) ...[
              AspectRatio(
                aspectRatio: 4 / 3,
                child: ClipRRect(
                  borderRadius: BottogramDesign.controlRadius,
                  child: MobileScanner(
                    onDetect: _detected,
                    errorBuilder: (_, _) => const Center(
                      child: Text(
                        'Camera unavailable. You can open a QR image below.',
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (_error != null) ...[
              BNotice(message: _error!, error: true),
              const SizedBox(height: 12),
            ],
            OutlinedButton.icon(
              onPressed: _readingImage ? null : _openImage,
              icon: const Icon(Icons.image_outlined),
              label: Text(
                _readingImage ? 'Reading QR image…' : 'Open QR image',
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

String? decodeBotQrImage(Uint8List bytes) {
  try {
    final decoder = image.findDecoderForData(bytes);
    final info = decoder?.startDecode(bytes);
    if (info == null || info.width * info.height > 16 * 1024 * 1024) {
      return null;
    }
    final pixels = decoder!.decodeFrame(0);
    if (pixels == null) return null;
    final source = RGBLuminanceSource(
      pixels.width,
      pixels.height,
      pixels
          .convert(numChannels: 4)
          .getBytes(order: image.ChannelOrder.abgr)
          .buffer
          .asInt32List(),
    );
    return QRCodeReader().decode(BinaryBitmap(HybridBinarizer(source))).text;
  } catch (_) {
    return null;
  }
}
