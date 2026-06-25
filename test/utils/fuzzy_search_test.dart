import 'package:flutter_test/flutter_test.dart';
import 'package:saydali_pro/utils/fuzzy_search.dart';

void main() {
  group('FuzzySearch.match', () {
    test('empty query returns true', () {
      expect(FuzzySearch.match('', 'Panadol'), true);
    });

    test('empty text returns false', () {
      expect(FuzzySearch.match('pan', ''), false);
    });

    test('exact match returns true', () {
      expect(FuzzySearch.match('panadol', 'Panadol'), true);
    });

    test('partial match returns true', () {
      expect(FuzzySearch.match('pana', 'Panadol'), true);
    });

    test('Arabic tashkeel normalization', () {
      expect(FuzzySearch.match('مكمل', 'مُكَمِّل'), true);
    });

    test('Arabic alef normalization', () {
      expect(FuzzySearch.match('ادوية', 'أدوية'), true);
    });

    test('Arabic ta marbuta normalization', () {
      expect(FuzzySearch.match('فاحه', 'فاحه'), true);
    });

    test('no match returns false', () {
      expect(FuzzySearch.match('xyz', 'Panadol'), false);
    });

    test('subsequence match', () {
      expect(FuzzySearch.match('pnld', 'Panadol'), true);
    });
  });

  group('FuzzySearch.getScore', () {
    test('exact match returns 1000', () {
      expect(FuzzySearch.getScore('panadol', 'Panadol'), 1000);
    });

    test('starts with returns 900', () {
      expect(FuzzySearch.getScore('pana', 'Panadol'), 900);
    });

    test('contains returns high score', () {
      final score = FuzzySearch.getScore('adol', 'Panadol');
      expect(score, greaterThan(0));
    });

    test('no match returns 0', () {
      expect(FuzzySearch.getScore('xyz', 'Panadol'), 0);
    });

    test('empty query returns 0', () {
      expect(FuzzySearch.getScore('', 'Panadol'), 0);
    });

    test('empty text returns 0', () {
      expect(FuzzySearch.getScore('pan', ''), 0);
    });
  });
}
