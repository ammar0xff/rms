import 'dart:convert';

/// Dedicated Arabic text shaper, BiDi reorderer, and ESC/POS encoder.
///
/// Converts raw Arabic strings into correctly shaped ligatures and right-to-left
/// byte sequences suitable for ESC/POS thermal receipt printers.
class ArabicEscPosEncoder {
  ArabicEscPosEncoder._();

  /// Codepage selection command bytes for ESC/POS:
  /// ESC t <n>
  static List<int> codepageSelectBytes(String codepage) {
    switch (codepage.toUpperCase()) {
      case 'CP864':
        return [0x1B, 0x74, 28]; // CP864 (Arabic) table on Epson/Star
      case 'WINDOWS-1256':
      case 'CP1256':
        return [0x1B, 0x74, 72]; // Windows-1256 (Arabic)
      case 'UTF-8':
      default:
        return [0x1B, 0x74, 0]; // Default page
    }
  }

  /// Shapes Arabic characters and handles BiDi reordering so lines print
  /// legibly and right-to-left on thermal printers.
  static List<int> encode(String text, {String codepage = 'UTF-8'}) {
    final shapedAndReordered = formatForPrinter(text);
    return utf8.encode(shapedAndReordered);
  }

  /// Shapes Arabic glyphs and reverses Arabic tokens for LTR thermal print heads.
  static String formatForPrinter(String line) {
    if (line.isEmpty) return line;

    final shaped = shapeArabic(line);
    return reorderBidi(shaped);
  }

  /// Contextual Arabic Glyph Shaping Table
  /// [Isolated, Final, Initial, Medial]
  static const Map<int, List<int>> _shapingTable = {
    // Hamza
    0x0621: [0xFE80, 0xFE80, 0xFE80, 0xFE80],
    // Alef with Madda
    0x0622: [0xFE81, 0xFE82, 0xFE81, 0xFE82],
    // Alef with Hamza Above
    0x0623: [0xFE83, 0xFE84, 0xFE83, 0xFE84],
    // Waw with Hamza
    0x0624: [0xFE85, 0xFE86, 0xFE85, 0xFE86],
    // Alef with Hamza Below
    0x0625: [0xFE87, 0xFE88, 0xFE87, 0xFE88],
    // Yeh with Hamza
    0x0626: [0xFE89, 0xFE8A, 0xFE8B, 0xFE8C],
    // Alef
    0x0627: [0xFE8D, 0xFE8E, 0xFE8D, 0xFE8E],
    // Beh
    0x0628: [0xFE8F, 0xFE90, 0xFE91, 0xFE92],
    // Teh Marbuta
    0x0629: [0xFE93, 0xFE94, 0xFE93, 0xFE94],
    // Teh
    0x062A: [0xFE95, 0xFE96, 0xFE97, 0xFE98],
    // Theh
    0x062B: [0xFE99, 0xFE9A, 0xFE9B, 0xFE9C],
    // Jeem
    0x062C: [0xFE9D, 0xFE9E, 0xFE9F, 0xFEA0],
    // Hah
    0x062D: [0xFEA1, 0xFEA2, 0xFEA3, 0xFEA4],
    // Khah
    0x062E: [0xFEA5, 0xFEA6, 0xFEA7, 0xFEA8],
    // Dal
    0x062F: [0xFEA9, 0xFEAA, 0xFEA9, 0xFEAA],
    // Thal
    0x0630: [0xFEAB, 0xFEAC, 0xFEAB, 0xFEAC],
    // Reh
    0x0631: [0xFEAD, 0xFEAE, 0xFEAD, 0xFEAE],
    // Zain
    0x0632: [0xFEAF, 0xFEB0, 0xFEAF, 0xFEB0],
    // Seen
    0x0633: [0xFEB1, 0xFEB2, 0xFEB3, 0xFEB4],
    // Sheen
    0x0634: [0xFEB5, 0xFEB6, 0xFEB7, 0xFEB8],
    // Sad
    0x0635: [0xFEB9, 0xFEBA, 0xFEBB, 0xFEBC],
    // Dad
    0x0636: [0xFEBD, 0xFEBE, 0xFEBF, 0xFEC0],
    // Tah
    0x0637: [0xFEC1, 0xFEC2, 0xFEC3, 0xFEC4],
    // Zah
    0x0638: [0xFEC5, 0xFEC6, 0xFEC7, 0xFEC8],
    // Ain
    0x0639: [0xFEC9, 0xFECA, 0xFECB, 0xFECC],
    // Ghain
    0x063A: [0xFECD, 0xFECE, 0xFECF, 0xFED0],
    // Tatweel
    0x0640: [0x0640, 0x0640, 0x0640, 0x0640],
    // Feh
    0x0641: [0xFED1, 0xFED2, 0xFED3, 0xFED4],
    // Qaf
    0x0642: [0xFED5, 0xFED6, 0xFED7, 0xFED8],
    // Kaf
    0x0643: [0xFED9, 0xFEDA, 0xFEDB, 0xFEDC],
    // Lam
    0x0644: [0xFEDD, 0xFEDE, 0xFEDF, 0xFEE0],
    // Meem
    0x0645: [0xFEE1, 0xFEE2, 0xFEE3, 0xFEE4],
    // Noon
    0x0646: [0xFEE5, 0xFEE6, 0xFEE7, 0xFEE8],
    // Heh
    0x0647: [0xFEE9, 0xFEEA, 0xFEEB, 0xFEEC],
    // Waw
    0x0648: [0xFEED, 0xFEEE, 0xFEED, 0xFEEE],
    // Alef Maksura
    0x0649: [0xFEEF, 0xFEF0, 0xFEEF, 0xFEF0],
    // Yeh
    0x064A: [0xFEF1, 0xFEF2, 0xFEF3, 0xFEF4],
  };

  /// Non-dual joining letters (connects only backwards / right):
  static const Set<int> _rightJoinOnly = {
    0x0621, // Hamza
    0x0622, // Alef Madda
    0x0623, // Alef Hamza Above
    0x0624, // Waw Hamza
    0x0625, // Alef Hamza Below
    0x0627, // Alef
    0x0629, // Teh Marbuta
    0x062F, // Dal
    0x0630, // Thal
    0x0631, // Reh
    0x0632, // Zain
    0x0648, // Waw
    0x0649, // Alef Maksura
  };

  static bool _isArabic(int code) => code >= 0x0600 && code <= 0x06FF;

  static bool _connectsNext(int code) {
    if (!_isArabic(code)) return false;
    return !_rightJoinOnly.contains(code);
  }

  static bool _connectsPrev(int code) {
    if (!_isArabic(code)) return false;
    if (code == 0x0621) return false; // Hamza never connects
    return true;
  }

  /// Transforms Arabic text into presentation forms (ligatures & connected glyphs).
  static String shapeArabic(String input) {
    final runes = input.runes.toList();
    final shaped = <int>[];

    for (int i = 0; i < runes.length; i++) {
      final current = runes[i];

      // Handle Lam-Alef ligatures
      if (current == 0x0644 && i + 1 < runes.length) {
        final next = runes[i + 1];
        int? lamAlef;
        if (next == 0x0622) lamAlef = 0xFEF5; // Lam-Alef Madda
        if (next == 0x0623) lamAlef = 0xFEF7; // Lam-Alef Hamza Above
        if (next == 0x0625) lamAlef = 0xFEF9; // Lam-Alef Hamza Below
        if (next == 0x0627) lamAlef = 0xFEFB; // Lam-Alef Plain

        if (lamAlef != null) {
          final prevConnects = i > 0 && _connectsNext(runes[i - 1]);
          shaped.add(prevConnects ? lamAlef + 1 : lamAlef);
          i++; // Skip Alef
          continue;
        }
      }

      final forms = _shapingTable[current];
      if (forms == null) {
        shaped.add(current);
        continue;
      }

      final prevConnects = i > 0 && _connectsNext(runes[i - 1]);
      final nextConnects = i + 1 < runes.length && _connectsPrev(runes[i + 1]);

      int formIndex;
      if (!prevConnects && !nextConnects) {
        formIndex = 0; // Isolated
      } else if (prevConnects && !nextConnects) {
        formIndex = 1; // Final
      } else if (!prevConnects && nextConnects) {
        formIndex = 2; // Initial
      } else {
        formIndex = 3; // Medial
      }

      shaped.add(forms[formIndex]);
    }

    return String.fromCharCodes(shaped);
  }

  /// Reverses Arabic text segments while preserving numeric and LTR Latin segments.
  static String reorderBidi(String text) {
    final lines = text.split('\n');
    final formattedLines = <String>[];

    for (final line in lines) {
      if (line.isEmpty) {
        formattedLines.add(line);
        continue;
      }

      // Check if line contains any Arabic characters
      final hasArabic = line.runes.any((r) =>
          (r >= 0x0600 && r <= 0x06FF) || (r >= 0xFB50 && r <= 0xFDFF) || (r >= 0xFE70 && r <= 0xFEFF));

      if (!hasArabic) {
        formattedLines.add(line);
        continue;
      }

      // Split into tokens: words, spaces, punctuation
      final tokens = _tokenize(line);
      final reversedTokens = tokens.reversed.map((token) {
        if (_isArabicToken(token)) {
          return String.fromCharCodes(token.runes.toList().reversed);
        }
        return token;
      }).toList();

      formattedLines.add(reversedTokens.join());
    }

    return formattedLines.join('\n');
  }

  static bool _isArabicToken(String token) {
    return token.runes.any((r) =>
        (r >= 0x0600 && r <= 0x06FF) || (r >= 0xFB50 && r <= 0xFDFF) || (r >= 0xFE70 && r <= 0xFEFF));
  }

  static List<String> _tokenize(String s) {
    final tokens = <String>[];
    final buffer = StringBuffer();
    bool? inArabic;

    for (final rune in s.runes) {
      final isAr = (rune >= 0x0600 && rune <= 0x06FF) ||
          (rune >= 0xFB50 && rune <= 0xFDFF) ||
          (rune >= 0xFE70 && rune <= 0xFEFF);

      if (inArabic == null) {
        inArabic = isAr;
        buffer.writeCharCode(rune);
      } else if (inArabic == isAr) {
        buffer.writeCharCode(rune);
      } else {
        tokens.add(buffer.toString());
        buffer.clear();
        inArabic = isAr;
        buffer.writeCharCode(rune);
      }
    }

    if (buffer.isNotEmpty) {
      tokens.add(buffer.toString());
    }

    return tokens;
  }
}
