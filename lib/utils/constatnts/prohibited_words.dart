List<String> getProhibitedMatches(String text) {
  final lowerText = text.toLowerCase();
  final matches = <String>{};

  final prohibitedSymbols = ['@gmail.com', '+91', '.com', 'no.', '@'];

  for (final symbol in prohibitedSymbols) {
    if (lowerText.contains(symbol.toLowerCase())) {
      matches.add(symbol);
    }
  }

  final prohibitedWords = [
    'instagram',
    'insta',
    'phone',
    'call',
    'facebook',
    'contact',
    'whatsapp',
    'fb',
    'snapchat',
    'whasapp',
    'hangouts',
    'telegram',
    'mobile',
    'number',
    'gmail',
  ];

  for (final word in prohibitedWords) {
    final regex = RegExp(
      r'\b' + RegExp.escape(word) + r'\b',
      caseSensitive: false,
    );

    if (regex.hasMatch(text)) {
      if (word == 'gmail' && matches.contains('@gmail.com')) {
        continue;
      }

      matches.add(word);
    }
  }

  return matches.toList();
}
