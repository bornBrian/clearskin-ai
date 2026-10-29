/// The first sentence of [text], ending in a full stop. Keeps screens to one
/// line of reading where the full text lives elsewhere.
String firstSentence(String text) {
  final first = text.trim().split(RegExp(r'(?<=[.!?])\s')).first;
  return RegExp(r'[.!?]$').hasMatch(first) ? first : '$first.';
}
