class LevelUtils {
  static const int pointsPerLevel = 250;
  static const List<String> tiers = ['Iron', 'Bronze', 'Silver', 'Gold', 'Platinum'];
  static const List<String> subLevels = ['I', 'II', 'III', 'IV'];

  /// Calculează detaliile nivelului curent pe baza punctajului (rating/xp)
  static Map<String, dynamic> getLevelDetails(int rating) {
    if (rating < 0) rating = 0;

    int levelIndex = rating ~/ pointsPerLevel;

    if (levelIndex >= tiers.length * subLevels.length) {
      return {
        'levelName': 'Diamond',
        'progress': 1.0,
        'currentPointsInLevel': pointsPerLevel,
        'pointsToNextLevel': 0,
        'winPoints': 40,
        'losePoints': 40,
      };
    }

    int tierIndex = levelIndex ~/ subLevels.length;
    int subLevelIndex = levelIndex % subLevels.length;
    String levelName = '${tiers[tierIndex]} ${subLevels[subLevelIndex]}';
    int currentPointsInLevel = rating % pointsPerLevel;
    double progress = currentPointsInLevel / pointsPerLevel;

    int winPoints = 25;
    int losePoints = 0;

    if (levelIndex == 0) {
      winPoints = 25; losePoints = 0;
    } else if (levelIndex == 1 || levelIndex == 2) {
      winPoints = 25; losePoints = 5;
    } else if (levelIndex == 3 || levelIndex == 4 || levelIndex == 5) {
      winPoints = 25; losePoints = 10;
    } else if (levelIndex == 6 || levelIndex == 7) {
      winPoints = 25; losePoints = 15;
    } else if (levelIndex >= 8 && levelIndex <= 11) {
      winPoints = 25; losePoints = 25;
    } else if (levelIndex >= 12 && levelIndex <= 15) {
      winPoints = 30; losePoints = 25;
    } else if (levelIndex == 16 || levelIndex == 17) {
      winPoints = 30; losePoints = 25;
    } else if (levelIndex == 18 || levelIndex == 19) {
      winPoints = 30; losePoints = 30;
    }

    return {
      'levelName': levelName,
      'progress': progress,
      'currentPointsInLevel': currentPointsInLevel,
      'pointsToNextLevel': pointsPerLevel - currentPointsInLevel,
      'winPoints': winPoints,
      'losePoints': losePoints,
    };
  }

  /// Calculează punctele câștigate, cu bonus dacă învingătorul avea rating mai mic
  static int calculateMatchPoints(int winnerRating, int loserRating) {
    if (winnerRating < 0) winnerRating = 0;
    if (loserRating < 0) loserRating = 0;

    int winnerLevelIndex = winnerRating ~/ pointsPerLevel;
    int loserLevelIndex = loserRating ~/ pointsPerLevel;
    int winPoints = LevelUtils.getLevelDetails(winnerRating)['winPoints'] as int;

    if (loserLevelIndex > winnerLevelIndex) {
      int difference = loserLevelIndex - winnerLevelIndex;
      winPoints += difference * 5;
    }

    return winPoints;
  }

  /// Extrage tariful orar dinamic pe baza textului introdus de administrator și a orei selectate.
  ///
  /// Suportă formate:
  ///   "30 RON/oră înainte de 17:00, 40 RON/oră după 17:00"  ← format standard cu virgulă
  ///   "30 de lei inainte de 17 si dupa 17 40"               ← format cu "si"
  ///   "inainte de 17 30, dupa 17 40"                         ← ordine inversă
  ///   "30 lei pana la 17, 40 lei de la 17"                   ← format cu pana la/de la
  ///   "50 RON/oră"                                            ← tarif fix
  ///
  /// Algoritm: textul este împărțit în segmente (virgulă / punct-virgulă / "si"),
  /// fiecare segment conținând fie o clauză "înainte-de", fie o clauză "după".
  /// Procesarea independentă pe segmente elimină capturarea greșită a cifrelor
  /// din altă clauză (bug-ul care producea 0 lei sau prețuri eronate).
  static double getHourlyPrice(String priceText, int hour) {
    if (priceText.isEmpty) return 20.0;

    // Normalizare
    final text = priceText
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll('–', '-')
        .replaceAll('—', '-')
        .trim();

    // ── Funcții helper locale ────────────────────────────────────────────────

    // Primul număr întreg/zecimal dintr-un string (caută \b...\b)
    double? firstNum(String s) {
      final m = RegExp(r'\b(\d+(?:[.,]\d+)?)\b').firstMatch(s);
      if (m == null) return null;
      return double.tryParse(m.group(1)!.replaceAll(',', '.'));
    }

    // Regex pentru ora: 1-2 cifre, opțional urmat de ":MM"
    // Nu trebuie să înceapă după ':', '/' sau altă cifră (evităm ":00")
    final hourRe = RegExp(r'(?<![:/\d])(\d{1,2})(?::\d{2})?(?!\d)');

    // Returnează ora din string-ul dat (prima potrivire)
    int? firstHour(String s) {
      final m = hourRe.firstMatch(s);
      return m == null ? null : int.tryParse(m.group(1)!);
    }

    // ── Extragere preț și oră din segment cu keyword ───────────────────────
    // Returnează {price, hour} dintr-un segment de tip:
    //   Format A (preț înaintea keyword-ului): "30 ron/oră KEYWORD 17:00"
    //   Format B (preț după keyword și oră):   "KEYWORD 17:00 30 lei" / "KEYWORD 17 30"
    _PriceHour? extractPriceHour(String seg, RegExpMatch kwMatch) {
      final beforeKw = seg.substring(0, kwMatch.start).trim();
      final afterKw  = seg.substring(kwMatch.end).trim();

      // Format A: prețul e înaintea keyword-ului
      final priceA = firstNum(beforeKw);
      if (priceA != null) {
        final h = firstHour(afterKw);
        if (h != null) return _PriceHour(priceA, h);
      }

      // Format B: prețul e DUPĂ oră (ordine inversă):
      //   "KEYWORD 17 30 lei"  sau  "KEYWORD ora 17:00 30 lei"
      final hourM = hourRe.firstMatch(afterKw);
      if (hourM != null) {
        final h = int.tryParse(hourM.group(1)!);
        // prețul se află după oră
        final afterHourStr = afterKw.substring(hourM.end).trim();
        final priceB = firstNum(afterHourStr);
        if (h != null && priceB != null) return _PriceHour(priceB, h);
      }

      return null;
    }

    // ── Cuvinte-cheie ────────────────────────────────────────────────────────
    // "înainte de" acceptă și "inainte de" (fără diacritic î/Î)
    final befRe = RegExp(
      r'(?:(?:î|i)nainte\s+de|p[aă]n[aă]\s+la|before(?!\s*de))',
    );
    // "după" acceptă "dupa" fără diacritic; "de la" este alt cuvânt-cheie after
    final aftRe = RegExp(r'(?:dup[aă]|de\s+la|after)');

    // ── Împărțire în segmente ────────────────────────────────────────────────
    final segments = text
        .split(RegExp(r'[,;]|\b(?:si|și)\b'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    double? beforePrice;
    int?    beforeHourLimit;
    double? afterPrice;
    int?    afterHourLimit;

    for (final seg in segments) {
      final befM = befRe.firstMatch(seg);
      final aftM = aftRe.firstMatch(seg);

      if (befM != null && aftM == null) {
        // Segment cu condiție "înainte de"
        final ph = extractPriceHour(seg, befM);
        if (ph != null) {
          beforePrice = ph.price;
          beforeHourLimit = ph.hour;
        }
      } else if (aftM != null && befM == null) {
        // Segment cu condiție "după"
        final ph = extractPriceHour(seg, aftM);
        if (ph != null) {
          afterPrice = ph.price;
          afterHourLimit = ph.hour;
        }
      }
      // Segmentele fără keyword sunt tratate ca tarif fix mai jos
    }

    // ── Aplicare reguli ──────────────────────────────────────────────────────

    if (beforePrice != null && beforeHourLimit != null &&
        afterPrice != null && afterHourLimit != null) {
      return hour < beforeHourLimit ? beforePrice : afterPrice;
    }
    if (beforePrice != null && beforeHourLimit != null) {
      return beforePrice;
    }
    if (afterPrice != null && afterHourLimit != null) {
      return afterPrice;
    }

    // Tarif fix simplu: "50 RON/oră", "30 lei" etc.
    final flat = firstNum(text);
    if (flat != null && flat > 0) return flat;

    return 20.0;
  }

  /// Calculează costul total al rezervării pe baza intervalului de ore [startHour, endHour)
  static double calculateTotalBookingPrice(String priceText, num startHour, num endHour) {
    if (startHour >= endHour) return 0.0;
    double total = 0.0;
    num current = startHour;
    while (current < endHour) {
      total += getHourlyPrice(priceText, current.floor()) * 0.5;
      current += 0.5;
    }
    return total;
  }

  /// Calculează costul total al rezervării folosind prețurile structurate ale sălii
  static double calculateVenueBookingPrice({
    required Map<String, dynamic> venueData,
    required num startHour,
    required num endHour,
  }) {
    if (startHour >= endHour) return 0.0;

    final String priceType = venueData['priceType'] ?? 'flat';
    final double flatHalf = (venueData['flatPriceHalf'] as num?)?.toDouble() ?? 15.0;

    final int limitHour = (venueData['dynamicHourLimit'] as num?)?.toInt() ?? 17;
    final double dynHalfBefore = (venueData['dynamicPriceHalfBefore'] as num?)?.toDouble() ?? 15.0;
    final double dynHalfAfter = (venueData['dynamicPriceHalfAfter'] as num?)?.toDouble() ?? 20.0;

    double total = 0.0;
    num current = startHour;

    while (current < endHour) {
      if (priceType == 'dynamic') {
        if (current < limitHour) {
          total += dynHalfBefore;
        } else {
          total += dynHalfAfter;
        }
      } else {
        total += flatHalf;
      }
      current += 0.5;
    }

    return total;
  }
}

/// Structură internă: prețul și ora dintr-un segment de tarif
class _PriceHour {
  final double price;
  final int hour;
  const _PriceHour(this.price, this.hour);
}
