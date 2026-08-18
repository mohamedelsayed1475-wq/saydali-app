import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../utils/app_theme.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> with SingleTickerProviderStateMixin {
  late MobileScannerController _controller;
  bool _alreadyScanned = false;
  late AnimationController _animationController;
  late Animation<double> _laserAnimation;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      formats: [
        BarcodeFormat.ean8,
        BarcodeFormat.ean13,
        BarcodeFormat.code128,
        BarcodeFormat.qrCode,
      ],
      detectionSpeed: DetectionSpeed.normal,
    );

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _laserAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'مسح الباركود',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Cairo'),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          
          // تحديد حجم بؤرة المسح (Viewfinder)
          final scanAreaSize = width * 0.7;
          final left = (width - scanAreaSize) / 2;
          final top = (height - scanAreaSize) / 2;

          return Stack(
            children: [
              // قارئ الكاميرا
              MobileScanner(
                controller: _controller,
                onDetect: (capture) {
                  if (_alreadyScanned) return;
                  final List<Barcode> barcodes = capture.barcodes;
                  if (barcodes.isNotEmpty) {
                    final String? code = barcodes.first.rawValue;
                    if (code != null && code.trim().isNotEmpty) {
                      _alreadyScanned = true;
                      debugPrint('🎉 [BARCODE_SCANNER] تم العثور على رمز: $code بنوع: ${barcodes.first.format}');
                      Navigator.pop(context, code.trim());
                    }
                  }
                },
                errorBuilder: (context, error, child) {
                  debugPrint('❌ [BARCODE_SCANNER] خطأ الكاميرا: ${error.errorCode}');
                  return Container(
                    color: Colors.black,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.videocam_off_rounded, color: Colors.red, size: 64),
                            const SizedBox(height: 16),
                            const Text(
                              'فشل فتح الكاميرا ⚠️',
                              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'يرجى التأكد من منح التطبيق صلاحية الوصول للكاميرا من إعدادات الهاتف ثم المحاولة مرة أخرى.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.textMuted, fontSize: 14, fontFamily: 'Cairo'),
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                              onPressed: () => Navigator.pop(context),
                              child: const Text('رجوع', style: TextStyle(fontFamily: 'Cairo')),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              
              // واجهة الطبقة شبه الشفافة والبؤرة المحددة (Overlay)
              CustomPaint(
                painter: ScannerOverlayPainter(),
                size: Size.infinite,
              ),

              // مؤشر خط الليزر المتحرك للرؤية
              AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return Positioned(
                    top: top + (scanAreaSize * _laserAnimation.value),
                    left: left + 16,
                    width: scanAreaSize - 32,
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.8),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),

              // نص توضيحي فوق البؤرة
              Positioned(
                top: top - 50,
                left: 20,
                right: 20,
                child: Center(
                  child: Text(
                    'ضع الباركود أو الـ QR داخل الإطار للمسح تلقائياً',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Cairo',
                      shadows: [
                        Shadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 4, offset: const Offset(0, 1)),
                      ],
                    ),
                  ),
                ),
              ),

              // أزرار التحكم بالكشاف وتبديل الكاميرا بالأسفل
              Positioned(
                bottom: 60,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // زر التحكم بالكشاف (Flashlight)
                    ValueListenableBuilder<MobileScannerState>(
                      valueListenable: _controller,
                      builder: (context, state, child) {
                        final isTorchOn = state.torchState == TorchState.on;
                        return InkWell(
                          onTap: () => _controller.toggleTorch(),
                          borderRadius: BorderRadius.circular(50),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isTorchOn 
                                  ? AppColors.primary.withValues(alpha: 0.25)
                                  : Colors.black.withValues(alpha: 0.6),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isTorchOn ? AppColors.primary : Colors.white30,
                                width: 1.5,
                              ),
                            ),
                            child: Icon(
                              isTorchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                              color: isTorchOn ? AppColors.primary : Colors.white,
                              size: 26,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 32),
                    // زر تبديل الكاميرا (أمامية/خلفية)
                    ValueListenableBuilder<MobileScannerState>(
                      valueListenable: _controller,
                      builder: (context, state, child) {
                        return InkWell(
                          onTap: () => _controller.switchCamera(),
                          borderRadius: BorderRadius.circular(50),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white30,
                                width: 1.5,
                              ),
                            ),
                            child: const Icon(
                              Icons.flip_camera_ios_rounded,
                              color: Colors.white,
                              size: 26,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// دهان مخصص لرسم حدود وخلفية بؤرة المسح (Scanner Viewfinder Overlay)
class ScannerOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    
    // حجم وتحديد البؤرة الوسطى للمسح
    final scanAreaSize = width * 0.7;
    final left = (width - scanAreaSize) / 2;
    final top = (height - scanAreaSize) / 2;
    final rect = Rect.fromLTWH(left, top, scanAreaSize, scanAreaSize);

    // 1. رسم خلفية داكنة نصف شفافة مع تفريغ المربع الأوسط
    final backgroundPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.65)
      ..style = PaintingStyle.fill;

    final backgroundPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, width, height))
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(16)));
    
    // استخدام odd-even rule لحذف المربع الأوسط من الخلفية الملونة
    backgroundPath.fillType = PathFillType.evenOdd;
    canvas.drawPath(backgroundPath, backgroundPaint);

    // 2. رسم زوايا حدود مضيئة بلون التطبيق الأساسي لتحديد البؤرة
    final borderPaint = Paint()
      ..color = const Color(0xFF00C896) // AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    final borderLength = scanAreaSize * 0.12;
    const radius = 16.0;

    // الزاوية اليسرى العليا
    canvas.drawArc(Rect.fromLTWH(left, top, radius * 2, radius * 2), 3.1415, 1.5707, false, borderPaint);
    canvas.drawLine(Offset(left + radius, top), Offset(left + radius + borderLength, top), borderPaint);
    canvas.drawLine(Offset(left, top + radius), Offset(left, top + radius + borderLength), borderPaint);

    // الزاوية اليمنى العليا
    canvas.drawArc(Rect.fromLTWH(left + scanAreaSize - radius * 2, top, radius * 2, radius * 2), 4.7123, 1.5707, false, borderPaint);
    canvas.drawLine(Offset(left + scanAreaSize - radius, top), Offset(left + scanAreaSize - radius - borderLength, top), borderPaint);
    canvas.drawLine(Offset(left + scanAreaSize, top + radius), Offset(left + scanAreaSize, top + radius + borderLength), borderPaint);

    // الزاوية اليسرى السفلى
    canvas.drawArc(Rect.fromLTWH(left, top + scanAreaSize - radius * 2, radius * 2, radius * 2), 1.5707, 1.5707, false, borderPaint);
    canvas.drawLine(Offset(left + radius, top + scanAreaSize), Offset(left + radius + borderLength, top + scanAreaSize), borderPaint);
    canvas.drawLine(Offset(left, top + scanAreaSize - radius), Offset(left, top + scanAreaSize - radius - borderLength), borderPaint);

    // الزاوية اليمنى السفلى
    canvas.drawArc(Rect.fromLTWH(left + scanAreaSize - radius * 2, top + scanAreaSize - radius * 2, radius * 2, radius * 2), 0.0, 1.5707, false, borderPaint);
    canvas.drawLine(Offset(left + scanAreaSize - radius, top + scanAreaSize), Offset(left + scanAreaSize - radius - borderLength, top + scanAreaSize), borderPaint);
    canvas.drawLine(Offset(left + scanAreaSize, top + scanAreaSize - radius), Offset(left + scanAreaSize, top + scanAreaSize - radius - borderLength), borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
