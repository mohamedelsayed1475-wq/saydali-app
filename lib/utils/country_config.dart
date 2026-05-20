/// ── إعدادات الدول والعملات ──────────────────────────────────────────
/// يدعم مصر + دول الخليج العربي
class CountryInfo {
  final String code; // EG, SA, AE ...
  final String name; // مصر، السعودية ...
  final String currency; // ج.م، ر.س ...
  final String currencyEn; // EGP, SAR ...
  final String phoneCode; // +20, +966 ...
  final String flag; // 🇪🇬, 🇸🇦 ...

  const CountryInfo({
    required this.code,
    required this.name,
    required this.currency,
    required this.currencyEn,
    required this.phoneCode,
    required this.flag,
  });
}

class CountryConfig {
  static const List<CountryInfo> countries = [
    CountryInfo(
      code: 'EG',
      name: 'مصر',
      currency: 'ج.م',
      currencyEn: 'EGP',
      phoneCode: '+20',
      flag: '🇪🇬',
    ),
    CountryInfo(
      code: 'SA',
      name: 'السعودية',
      currency: 'ر.س',
      currencyEn: 'SAR',
      phoneCode: '+966',
      flag: '🇸🇦',
    ),
    CountryInfo(
      code: 'AE',
      name: 'الإمارات',
      currency: 'د.إ',
      currencyEn: 'AED',
      phoneCode: '+971',
      flag: '🇦🇪',
    ),
    CountryInfo(
      code: 'KW',
      name: 'الكويت',
      currency: 'د.ك',
      currencyEn: 'KWD',
      phoneCode: '+965',
      flag: '🇰🇼',
    ),
    CountryInfo(
      code: 'QA',
      name: 'قطر',
      currency: 'ر.ق',
      currencyEn: 'QAR',
      phoneCode: '+974',
      flag: '🇶🇦',
    ),
    CountryInfo(
      code: 'BH',
      name: 'البحرين',
      currency: 'د.ب',
      currencyEn: 'BHD',
      phoneCode: '+973',
      flag: '🇧🇭',
    ),
    CountryInfo(
      code: 'OM',
      name: 'عمان',
      currency: 'ر.ع',
      currencyEn: 'OMR',
      phoneCode: '+968',
      flag: '🇴🇲',
    ),
    CountryInfo(
      code: 'IQ',
      name: 'العراق',
      currency: 'د.ع',
      currencyEn: 'IQD',
      phoneCode: '+964',
      flag: '🇮🇶',
    ),
    CountryInfo(
      code: 'JO',
      name: 'الأردن',
      currency: 'د.أ',
      currencyEn: 'JOD',
      phoneCode: '+962',
      flag: '🇯🇴',
    ),
    CountryInfo(
      code: 'LY',
      name: 'ليبيا',
      currency: 'د.ل',
      currencyEn: 'LYD',
      phoneCode: '+218',
      flag: '🇱🇾',
    ),
    CountryInfo(
      code: 'SD',
      name: 'السودان',
      currency: 'ج.س',
      currencyEn: 'SDG',
      phoneCode: '+249',
      flag: '🇸🇩',
    ),
    CountryInfo(
      code: 'YE',
      name: 'اليمن',
      currency: 'ر.ي',
      currencyEn: 'YER',
      phoneCode: '+967',
      flag: '🇾🇪',
    ),
    CountryInfo(
      code: 'SY',
      name: 'سوريا',
      currency: 'ل.س',
      currencyEn: 'SYP',
      phoneCode: '+963',
      flag: '🇸🇾',
    ),
    CountryInfo(
      code: 'LB',
      name: 'لبنان',
      currency: 'ل.ل',
      currencyEn: 'LBP',
      phoneCode: '+961',
      flag: '🇱🇧',
    ),
    CountryInfo(
      code: 'PS',
      name: 'فلسطين',
      currency: 'ش.ج',
      currencyEn: 'ILS',
      phoneCode: '+970',
      flag: '🇵🇸',
    ),
    CountryInfo(
      code: 'MA',
      name: 'المغرب',
      currency: 'د.م.',
      currencyEn: 'MAD',
      phoneCode: '+212',
      flag: '🇲🇦',
    ),
    CountryInfo(
      code: 'DZ',
      name: 'الجزائر',
      currency: 'د.ج',
      currencyEn: 'DZD',
      phoneCode: '+213',
      flag: '🇩🇿',
    ),
    CountryInfo(
      code: 'TN',
      name: 'تونس',
      currency: 'د.ت',
      currencyEn: 'TND',
      phoneCode: '+216',
      flag: '🇹🇳',
    ),
    CountryInfo(
      code: 'MR',
      name: 'موريتانيا',
      currency: 'أوقية',
      currencyEn: 'MRU',
      phoneCode: '+222',
      flag: '🇲🇷',
    ),
    CountryInfo(
      code: 'SO',
      name: 'الصومال',
      currency: 'ش.ص',
      currencyEn: 'SOS',
      phoneCode: '+252',
      flag: '🇸🇴',
    ),
    CountryInfo(
      code: 'DJ',
      name: 'جيبوتي',
      currency: 'ف.ج',
      currencyEn: 'DJF',
      phoneCode: '+253',
      flag: '🇩🇯',
    ),
    CountryInfo(
      code: 'KM',
      name: 'جزر القمر',
      currency: 'ف.ج.ق',
      currencyEn: 'KMF',
      phoneCode: '+269',
      flag: '🇰🇲',
    ),
  ];

  /// الدولة الافتراضية (مصر)
  static CountryInfo get defaultCountry => countries.first;

  /// البحث عن دولة بالكود
  static CountryInfo getByCode(String code) {
    return countries.firstWhere(
      (c) => c.code == code,
      orElse: () => defaultCountry,
    );
  }

  /// تنسيق رقم الهاتف مع كود الدولة
  /// مثال: formatPhone('01012345678', 'EG') → '+2001012345678'
  static String formatPhone(String phone, String countryCode) {
    phone = phone.trim().replaceAll(RegExp(r'[\s\-()]'), '');
    if (phone.startsWith('+')) return phone; // رقم دولي بالفعل
    if (phone.startsWith('00')) {
      return '+${phone.substring(2)}'; // 00966... → +966...
    }
    // إزالة الصفر المحلي إن وُجد
    final country = getByCode(countryCode);
    if (phone.startsWith('0')) {
      phone = phone.substring(1);
    }
    return '${country.phoneCode}$phone';
  }
}
