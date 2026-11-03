import '../../core/money.dart';

const _ones = [
  '',
  'one',
  'two',
  'three',
  'four',
  'five',
  'six',
  'seven',
  'eight',
  'nine',
  'ten',
  'eleven',
  'twelve',
  'thirteen',
  'fourteen',
  'fifteen',
  'sixteen',
  'seventeen',
  'eighteen',
  'nineteen',
];
const _tens = [
  '',
  '',
  'twenty',
  'thirty',
  'forty',
  'fifty',
  'sixty',
  'seventy',
  'eighty',
  'ninety',
];

String _below100(int n) {
  if (n < 20) return _ones[n];
  final t = _tens[n ~/ 10], o = _ones[n % 10];
  return o.isEmpty ? t : '$t-$o';
}

String _below1000(int n) {
  final h = n ~/ 100, r = n % 100;
  return [if (h > 0) '${_ones[h]} hundred', if (r > 0) _below100(r)].join(' ');
}

/// A whole number in Indian words — crore, lakh, thousand.
/// `1234567` → "twelve lakh thirty-four thousand five hundred sixty-seven".
String indianWords(int n) {
  if (n == 0) return 'zero';
  if (n < 0) return 'minus ${indianWords(-n)}';
  final parts = <String>[];
  final crore = n ~/ 10000000;
  if (crore > 0) parts.add('${indianWords(crore)} crore');
  final lakh = (n ~/ 100000) % 100;
  if (lakh > 0) parts.add('${_below100(lakh)} lakh');
  final thousand = (n ~/ 1000) % 100;
  if (thousand > 0) parts.add('${_below100(thousand)} thousand');
  final rest = n % 1000;
  if (rest > 0) parts.add(_below1000(rest));
  return parts.join(' ');
}

/// "Rupees forty-five thousand and fifty paise only" — the way a cheque or
/// bill says it, so a misplaced zero is caught before saving.
String amountInWords(Money m) {
  final rupees = m.paise.abs() ~/ 100, paise = m.paise.abs() % 100;
  final unit = MoneyFormat.currency.code == 'INR'
      ? 'Rupees'
      : MoneyFormat.currency.code;
  final words = [
    '$unit ${indianWords(rupees)}',
    if (paise > 0) 'and ${_below100(paise)} paise',
  ].join(' ');
  return '${m.isNegative ? 'Minus ' : ''}$words only';
}
