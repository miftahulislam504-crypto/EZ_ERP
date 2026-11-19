import 'package:intl/intl.dart';

class Fmt {
  Fmt._();

  static const _symbols = {
    'BDT': '৳',
    'USD': '\$',
    'EUR': '€',
    'GBP': '£',
    'INR': '₹',
    'AED': 'AED ',
    'SAR': 'SAR ',
  };

  /// Money with lakh/crore digit grouping (1,23,456.00), the convention used in Bangladesh.
  static String money(num? value, {String currency = 'BDT'}) {
    if (value == null) return '--';
    final symbol = _symbols[currency] ?? '$currency ';
    return NumberFormat.currency(locale: 'en_IN', symbol: symbol, decimalDigits: 2).format(value);
  }

  static String compact(num? value) {
    if (value == null) return '--';
    final v = value.abs();
    final sign = value < 0 ? '-' : '';
    if (v >= 10000000) return '$sign${(v / 10000000).toStringAsFixed(2)} Cr';
    if (v >= 100000) return '$sign${(v / 100000).toStringAsFixed(2)} L';
    if (v >= 1000) return '$sign${(v / 1000).toStringAsFixed(1)} K';
    return '$sign${v.toStringAsFixed(0)}';
  }

  static String date(DateTime? d, {String pattern = 'dd MMM yyyy'}) =>
      d == null ? '--' : DateFormat(pattern).format(d.toLocal());

  static String dateTime(DateTime? d) => date(d, pattern: 'dd MMM yyyy, hh:mm a');

  static DateTime? parse(String? iso) => iso == null ? null : DateTime.tryParse(iso);

  static String timeAgo(DateTime? d) {
    if (d == null) return '';
    final diff = DateTime.now().difference(d.toLocal());
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    if (diff.inDays < 7) return '${diff.inDays} d ago';
    return date(d);
  }

  static String initials(String? name) {
    final parts = (name ?? '').trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  /// "head_office" -> "Head office"
  static String humanize(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final s = raw.replaceAll('_', ' ');
    return s.substring(0, 1).toUpperCase() + s.substring(1);
  }
}
