class LevelUtils {
  static const int pointsPerLevel = 250;
  static const List<String> tiers = ['Iron', 'Bronze', 'Silver', 'Gold', 'Platinum'];
  static const List<String> subLevels = ['I', 'II', 'III', 'IV'];

  /// Calculează detaliile nivelului curent pe baza punctajului (rating/xp)
  static Map<String, dynamic> getLevelDetails(int rating) {
    if (rating < 0) rating = 0;
    
    int levelIndex = rating ~/ pointsPerLevel;
    
    // Verificăm dacă a atins Diamond (Nivelul maxim)
    if (levelIndex >= tiers.length * subLevels.length) {
      return {
        'levelName': 'Diamond',
        'progress': 1.0, // Nivel maxim, progres plin
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
    
    // Determinare puncte de victorie / înfrângere
    int winPoints = 25;
    int losePoints = 0;
    
    if (levelIndex == 0) { // Iron I
      winPoints = 25; losePoints = 0;
    } else if (levelIndex == 1 || levelIndex == 2) { // Iron II, III
      winPoints = 25; losePoints = 5;
    } else if (levelIndex == 3 || levelIndex == 4 || levelIndex == 5) { // Iron IV, Bronze I, II
      winPoints = 25; losePoints = 10;
    } else if (levelIndex == 6 || levelIndex == 7) { // Bronze III, IV
      winPoints = 25; losePoints = 15;
    } else if (levelIndex >= 8 && levelIndex <= 11) { // Silver I-IV
      winPoints = 25; losePoints = 25;
    } else if (levelIndex >= 12 && levelIndex <= 15) { // Gold I-IV
      winPoints = 30; losePoints = 25;
    } else if (levelIndex == 16 || levelIndex == 17) { // Platinum I, II
      winPoints = 30; losePoints = 25;
    } else if (levelIndex == 18 || levelIndex == 19) { // Platinum III, IV
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

  /// Calculează punctele câștigate, cu bonus dacă învingătorul avea rating mai mic (categorie inferioară)
  static int calculateMatchPoints(int winnerRating, int loserRating) {
    if (winnerRating < 0) winnerRating = 0;
    if (loserRating < 0) loserRating = 0;

    int winnerLevelIndex = winnerRating ~/ pointsPerLevel;
    int loserLevelIndex = loserRating ~/ pointsPerLevel;

    int winPoints = LevelUtils.getLevelDetails(winnerRating)['winPoints'] as int;

    // Bonus progresiv: Dacă învingătorul are un nivel mai mic decât învinsul, primește bonus.
    if (loserLevelIndex > winnerLevelIndex) {
      int difference = loserLevelIndex - winnerLevelIndex;
      // Oferim un bonus de 5 puncte pentru fiecare sub-nivel diferență
      int bonus = difference * 5; 
      winPoints += bonus;
    }
    
    return winPoints;
  }

  /// Extrage tariful orar dinamic pe baza textului introdus de administrator și a orei selectate
  static double getHourlyPrice(String priceText, int hour) {
    if (priceText.isEmpty) return 20.0; // fallback default price
    
    // Standardizează textul: litere mici și înlocuirea spațiilor multiple
    final text = priceText.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    
    // 1. Definim regexurile pentru condițiile "înainte de / până la" (Before)
    // Scenariul A: [preț] înainte de [oră] (ex: "30 de lei inainte de 17")
    final beforeRegExp = RegExp(
      r'(\d+(?:\.\d+)?)\s*(?:de\s*)?(?:ron|lei|/or[aă]|/h)?\s*(?:înainte de|inainte de|până la|pana la|before|<)\s*(?:ora\s*)?(\d{1,2})(?::\d{2})?',
    );
    // Scenariul B (revers): înainte de [oră] [preț] (ex: "inainte de 17 30", "inainte de 17: 30 de lei")
    final beforeRegExpRev = RegExp(
      r'(?:înainte de|inainte de|până la|pana la|before|<)\s*(?:ora\s*)?(\d{1,2})(?::\d{2})?\s*(?:de\s*)?(?:ron|lei|/or[aă]|/h|:|valoare|costa|este)?\s*(\d+(?:\.\d+)?)',
    );

    // 2. Definim regexurile pentru condițiile "după / de la" (After)
    // Scenariul A: [preț] după [oră] (ex: "40 de lei dupa 17")
    final afterRegExp = RegExp(
      r'(\d+(?:\.\d+)?)\s*(?:de\s*)?(?:ron|lei|/or[aă]|/h)?\s*(?:după|dupa|de la|after|>)\s*(?:ora\s*)?(\d{1,2})(?::\d{2})?',
    );
    // Scenariul B (revers): după [oră] [preț] (ex: "dupa 17 40", "dupa ora 17 este 40 de lei")
    final afterRegExpRev = RegExp(
      r'(?:după|dupa|de la|after|>)\s*(?:ora\s*)?(\d{1,2})(?::\d{2})?\s*(?:de\s*)?(?:ron|lei|/or[aă]|/h|:|valoare|costa|este)?\s*(\d+(?:\.\d+)?)',
    );

    double? beforePrice;
    int? beforeHourLimit;
    
    // Găsim o regulă "Before" în text
    final beforeMatch = beforeRegExp.firstMatch(text);
    if (beforeMatch != null) {
      beforePrice = double.tryParse(beforeMatch.group(1) ?? '');
      beforeHourLimit = int.tryParse(beforeMatch.group(2) ?? '');
    } else {
      final beforeMatchRev = beforeRegExpRev.firstMatch(text);
      if (beforeMatchRev != null) {
        beforeHourLimit = int.tryParse(beforeMatchRev.group(1) ?? '');
        beforePrice = double.tryParse(beforeMatchRev.group(2) ?? '');
      }
    }

    double? afterPrice;
    int? afterHourLimit;
    
    // Găsim o regulă "After" în text
    final afterMatch = afterRegExp.firstMatch(text);
    if (afterMatch != null) {
      afterPrice = double.tryParse(afterMatch.group(1) ?? '');
      afterHourLimit = int.tryParse(afterMatch.group(2) ?? '');
    } else {
      final afterMatchRev = afterRegExpRev.firstMatch(text);
      if (afterMatchRev != null) {
        afterHourLimit = int.tryParse(afterMatchRev.group(1) ?? '');
        afterPrice = double.tryParse(afterMatchRev.group(2) ?? '');
      }
    }

    // Dacă ambele condiții limită au fost găsite
    if (beforePrice != null && beforeHourLimit != null && afterPrice != null && afterHourLimit != null) {
      if (hour < beforeHourLimit) {
        return beforePrice;
      } else {
        return afterPrice;
      }
    }
    
    // Dacă doar condiția "înainte de" este specificată
    if (beforePrice != null && beforeHourLimit != null) {
      if (hour < beforeHourLimit) {
        return beforePrice;
      }
    }

    // Dacă doar condiția "după" este specificată
    if (afterPrice != null && afterHourLimit != null) {
      if (hour >= afterHourLimit) {
        return afterPrice;
      }
    }

    // Fallback la valori specifice deduse individual
    if (beforePrice != null) return beforePrice;
    if (afterPrice != null) return afterPrice;

    // Fallback: extragere primul număr valid din șir
    final numberRegExp = RegExp(r'\d+(?:\.\d+)?');
    final fallbackMatch = numberRegExp.firstMatch(text);
    if (fallbackMatch != null) {
      return double.tryParse(fallbackMatch.group(0) ?? '') ?? 20.0;
    }

    return 20.0;
  }

  /// Calculează costul total al rezervării pe baza intervalului de ore [startHour, endHour)
  static double calculateTotalBookingPrice(String priceText, int startHour, int endHour) {
    double total = 0.0;
    for (int h = startHour; h < endHour; h++) {
      total += getHourlyPrice(priceText, h);
    }
    return total;
  }
}
