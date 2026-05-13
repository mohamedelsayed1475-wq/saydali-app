import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/groq_service.dart';

// ════════════════════════════════════════════════════════════════════════════
// ▌ شاشة الإعداد - بتظهر أول مرة بس
// ════════════════════════════════════════════════════════════════════════════

class SetupScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const SetupScreen({super.key, required this.onComplete});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  int _step = 0; // 0 = شرح Groq, 1 = إدخال المفتاح, 2 = تم
  final _keyCtrl = TextEditingController();
  bool _loading = false;
  bool _keyVisible = false;
  String? _error;

  @override
  void dispose() {
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _validateAndSave() async {
    final key = _keyCtrl.text.trim();
    if (key.isEmpty) {
      setState(() => _error = 'أدخل المفتاح أولاً');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final valid = await GroqService.instance.validateKey(key);

    if (valid) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('groq_api_key', key);
      await prefs.setBool('setup_complete', true);
      setState(() {
        _step = 2;
        _loading = false;
      });
    } else {
      setState(() {
        _error = '❌ المفتاح غير صحيح، تأكد وحاول تاني';
        _loading = false;
      });
    }
  }

  Future<void> _skipSetup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('setup_complete', true);
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          child: _step == 0
              ? _buildStep0()
              : _step == 1
                  ? _buildStep1()
                  : _buildStep2(),
        ),
      ),
    );
  }

  // ═══ الخطوة 0: شرح إزاي تجيب Groq API ════
  Widget _buildStep0() {
    return SingleChildScrollView(
      key: const ValueKey(0),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),

          // أيقونة حكيم
          Center(
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6C63FF), Color(0xFF4ECDC4)],
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Center(
                child: Text('🤖', style: TextStyle(fontSize: 44)),
              ),
            ),
          ),
          const SizedBox(height: 20),

          const Center(
            child: Text(
              'أهلاً! أنا حكيم 👋',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text(
              'مساعدك الذكي للصيدلية\nمحتاج دقيقتين بس للإعداد',
              style: TextStyle(color: Color(0xFF8B949E), fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 32),

          // بطاقة الشرح
          _InfoCard(
            icon: '⚡',
            title: 'ليه محتاج Groq API؟',
            content: 'Groq هو الذكاء الاصطناعي اللي هيشغل حكيم.\n'
                '• مجاني تماماً\n'
                '• سريع جداً\n'
                '• يدعم العربي بشكل ممتاز\n'
                '• بيشرح الأدوية ويجيب بدائل',
          ),
          const SizedBox(height: 16),

          // خطوات جلب المفتاح
          const Text(
            'خطوات جلب المفتاح (دقيقتين):',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),

          _StepCard(number: '1', text: 'افتح console.groq.com من أي متصفح'),
          const SizedBox(height: 8),
          _StepCard(number: '2', text: 'اعمل حساب مجاني بـ Gmail أو GitHub'),
          const SizedBox(height: 8),
          _StepCard(number: '3', text: 'اضغط على "API Keys" من القائمة الجانبية'),
          const SizedBox(height: 8),
          _StepCard(number: '4', text: 'اضغط "Create API Key" وانسخ المفتاح'),
          const SizedBox(height: 32),

          // أزرار
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => setState(() => _step = 1),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C63FF),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'عملت الحساب، هضيف المفتاح ←',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: _skipSetup,
              child: const Text(
                'تخطي الآن (حكيم هيشتغل بشكل محدود)',
                style: TextStyle(color: Color(0xFF8B949E), fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══ الخطوة 1: إدخال المفتاح ════
  Widget _buildStep1() {
    return SingleChildScrollView(
      key: const ValueKey(1),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),

          // زر رجوع
          IconButton(
            onPressed: () => setState(() => _step = 0),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          const SizedBox(height: 20),

          const Text(
            '🔑 أضف مفتاح Groq API',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'المفتاح بيبدأ بـ gsk_',
            style: TextStyle(color: Color(0xFF8B949E), fontSize: 13),
          ),
          const SizedBox(height: 32),

          // حقل المفتاح
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _error != null
                    ? Colors.redAccent
                    : const Color(0xFF30363D),
              ),
            ),
            child: TextField(
              controller: _keyCtrl,
              obscureText: !_keyVisible,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontFamily: 'monospace',
              ),
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                hintText: 'gsk_xxxxxxxxxxxxxxxxxxxx',
                hintStyle: const TextStyle(color: Color(0xFF8B949E)),
                prefixIcon: const Icon(Icons.key, color: Color(0xFF8B949E)),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _keyVisible = !_keyVisible),
                  icon: Icon(
                    _keyVisible ? Icons.visibility_off : Icons.visibility,
                    color: const Color(0xFF8B949E),
                  ),
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
              ),
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ],

          const SizedBox(height: 24),

          // تنبيه أمان
          _InfoCard(
            icon: '🔒',
            title: 'أمان المفتاح',
            content: 'المفتاح محفوظ على جهازك بس،\nمش بنبعته لأي سيرفر خارجي.',
          ),
          const SizedBox(height: 32),

          // زر التحقق
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _validateAndSave,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C63FF),
                disabledBackgroundColor: const Color(0xFF30363D),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'تحقق وابدأ ✓',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══ الخطوة 2: تم الإعداد ════
  Widget _buildStep2() {
    return Center(
      key: const ValueKey(2),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Center(
                child: Text('✅', style: TextStyle(fontSize: 52)),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'حكيم جاهز!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'تم ربط Groq AI بنجاح\nحكيم دلوقتي يقدر يشرح أدوية،\nيجيب بدائل، ويدير صيدليتك',
              style: TextStyle(color: Color(0xFF8B949E), fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),

            // مميزات مفعّلة
            _FeatureChip(label: '✅ شرح الأدوية'),
            const SizedBox(height: 8),
            _FeatureChip(label: '✅ بدائل بنفس المادة الفعالة'),
            const SizedBox(height: 8),
            _FeatureChip(label: '✅ الأعراض الجانبية من FDA'),
            const SizedBox(height: 8),
            _FeatureChip(label: '✅ إدارة النواقص والديون'),
            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: widget.onComplete,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'ابدأ مع حكيم 🚀',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// ▌ Widgets مساعدة
// ════════════════════════════════════════════════════════════════════════════

class _InfoCard extends StatelessWidget {
  final String icon, title, content;
  const _InfoCard({required this.icon, required this.title, required this.content});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            content,
            style: const TextStyle(
              color: Color(0xFF8B949E),
              fontSize: 13,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  final String number, text;
  const _StepCard({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: const Color(0xFF6C63FF).withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF6C63FF).withValues(alpha: 0.5)),
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                color: Color(0xFF6C63FF),
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: Color(0xFFE6EDF3), fontSize: 14),
          ),
        ),
      ],
    );
  }
}

class _FeatureChip extends StatelessWidget {
  final String label;
  const _FeatureChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.greenAccent,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
