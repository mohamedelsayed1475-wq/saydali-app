class FuzzySearch {
  static String normalize(String s) {
    return s
        .toLowerCase()
        .replaceAll(RegExp(r'[\u064B-\u065F]'), '') // Remove tashkeel
        .replaceAll(RegExp(r'[أإآ]'), 'ا')
        .replaceAll(RegExp(r'[ة]'), 'ه')
        .replaceAll(RegExp(r'[ى]'), 'ي')
        .replaceAll(RegExp(r'\s+'), '');
  }

  static int levenshtein(String s, String t) {
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;

    List<int> prev = List.generate(t.length + 1, (i) => i);
    List<int> curr = List.filled(t.length + 1, 0);

    for (int i = 1; i <= s.length; i++) {
      curr[0] = i;
      for (int j = 1; j <= t.length; j++) {
        final cost = s[i - 1] == t[j - 1] ? 0 : 1;
        curr[j] = [curr[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost]
            .reduce((a, b) => a < b ? a : b);
      }
      final temp = prev;
      prev = curr;
      curr = temp;
    }
    return prev[t.length];
  }

  static bool match(String query, String text) {
    if (query.isEmpty) return true;
    if (text.isEmpty) return false;

    final q = normalize(query);
    final t = normalize(text);

    if (t.contains(q)) return true;

    // Subsequence matching
    int i = 0;
    for (int j = 0; j < t.length && i < q.length; j++) {
      if (t[j] == q[i]) i++;
    }
    if (i == q.length) return true;

    // Levenshtein distance
    if (q.length >= 3 && t.length >= 3) {
      final maxDist = (q.length / 3).ceil();
      if (levenshtein(q, t.length > q.length + 3 ? t.substring(0, q.length + 3) : t) <= maxDist) {
        return true;
      }
      for (int k = 0; k <= t.length - q.length; k++) {
        if (levenshtein(q, t.substring(k, k + q.length)) <= maxDist) {
          return true;
        }
      }
    }
    return false;
  }
}
