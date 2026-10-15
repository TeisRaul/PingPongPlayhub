import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../theme/app_theme.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController cameraController = MobileScannerController();
  bool _isScanned = false;

  Future<void> _enterCodeManually() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('Cod bilet', style: TextStyle(color: AppColors.text)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: AppColors.text),
          decoration: InputDecoration(
            hintText: 'Cod bilet (ex. AV5-T7D)',
            hintStyle: TextStyle(color: AppColors.muted),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Anulează', style: TextStyle(color: AppColors.muted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Continuă'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (code != null && code.trim().isNotEmpty && mounted && !_isScanned) {
      setState(() => _isScanned = true);
      Navigator.pop(context, code.trim());
    }
  }

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        title: Text('Scanează QR Check-in', style: TextStyle(color: AppColors.text)),
        iconTheme: IconThemeData(color: AppColors.text),
        actions: [
          IconButton(
            tooltip: 'Introdu codul manual',
            icon: const Icon(Icons.keyboard),
            onPressed: _enterCodeManually,
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            flex: 4,
            child: MobileScanner(
              controller: cameraController,
              onDetect: (capture) {
                if (_isScanned) return;
                final List<Barcode> barcodes = capture.barcodes;
                if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
                  final String code = barcodes.first.rawValue!;
                  setState(() => _isScanned = true);
                  // Return the scanned value back to the previous screen
                  Navigator.pop(context, code);
                }
              },
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Aliniază codul QR în cadru pentru a scana.',
                    style: TextStyle(color: AppColors.text70, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _enterCodeManually,
                    icon: const Icon(Icons.keyboard),
                    label: const Text('Nu merge camera? Introdu codul biletului'),
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}
