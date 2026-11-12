import 'dart:io';

import 'package:bottogram/l10n/strings.dart';
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
    title: context.strings.shareBotAsQRCode,
    message: context.strings.doNotShareThisCodeWith,
    action: context.strings.continueLabel,
  )) {
    return;
  }
  if (!context.mounted ||
      !await _confirm(
        context,
        title: context.strings.revealThePrivateQRCode,
        message: context.strings.scanItOnlyWithYourOwn,
        action: context.strings.showQRCode,
      )) {
    return;
  }
  if (!context.mounted) return;
  final strings = context.strings;
  try {
    final transfer = await context.read<BotsCubit>().exportPluginBot(bot);
    final result = QrValidator.validate(
      data: transfer.toLink(),
      version: QrVersions.auto,
      errorCorrectionLevel: QrErrorCorrectLevel.M,
    );
    final qr = result.qrCode;
    if (qr == null) {
      throw PluginException(strings.thisBotSConfigurationIsToo);
    }
    if (!context.mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: Text(context.strings.privateBotQRCode)),
          body: SingleChildScrollView(
            child: BContent(
              maxWidth: 528,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  BHeading(
                    title: transfer.name,
                    subtitle: context.strings.qrRequiredPlugin(
                      context.leftToRightText(transfer.pluginKey),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(context.strings.anyoneWhoSeesThisCodeCan),
                  const SizedBox(height: 16),
                  QrImageView.withQr(
                    qr: qr,
                    backgroundColor: Colors.white,
                    padding: const EdgeInsets.all(24),
                    semanticsLabel: context.strings.privateBotQRCode,
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
      _notice(context, error, context.strings.theBotQRCodeCouldNot);
    }
  }
}

enum _BotImportSource { backup, qr }

Future<void> chooseBotImport(BuildContext context) async {
  final source = await showDialog<_BotImportSource>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(context.strings.importBots),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, _BotImportSource.backup),
          child: ListTile(
            leading: Icon(Icons.folder_open_outlined),
            title: Text(context.strings.backupFile),
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, _BotImportSource.qr),
          child: ListTile(
            leading: Icon(Icons.qr_code_scanner),
            title: Text(context.strings.scanQRCode),
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
      title: context.strings.importBotConfirmation(transfer.name),
      message: context.strings.importInstalledPluginNotice(
        plugin.name,
        plugin.version,
      ),
      action: context.strings.importBot,
    );
    if (!confirmed || !context.mounted) return;
    await bots.importPluginBot(transfer);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.strings.botImported)));
    }
  } catch (error) {
    if (context.mounted) {
      _notice(context, error, context.strings.theBotQRCodeCouldNot2);
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
            child: Text(context.strings.cancel),
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
        dialogTitle: context.strings.openABotQRImage,
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
        setState(() => _error = context.strings.noQRCodeCouldBeRead);
      }
    } finally {
      if (mounted && !_finished) setState(() => _readingImage = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.strings.scanBotQRCode)),
    body: SingleChildScrollView(
      child: BContent(
        maxWidth: 600,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BHeading(
              title: context.strings.importAPluginBot,
              subtitle: _cameraSupported
                  ? context.strings.pointTheCameraAtTheBottogram
                  : context.strings.openAnImageOfTheBottogram,
            ),
            const SizedBox(height: 20),
            if (_cameraSupported && !_readingImage) ...[
              AspectRatio(
                aspectRatio: 4 / 3,
                child: ClipRRect(
                  borderRadius: BottogramDesign.controlRadius,
                  child: MobileScanner(
                    onDetect: _detected,
                    errorBuilder: (_, _) => Center(
                      child: Text(context.strings.cameraUnavailableYouCanOpenA),
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
                _readingImage
                    ? context.strings.readingQRImage
                    : context.strings.openQRImage,
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
