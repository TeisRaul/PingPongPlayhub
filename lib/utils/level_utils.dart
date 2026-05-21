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
}
