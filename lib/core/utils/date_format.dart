class DateUtils {
  static String formatTimestamp(int unixTimestamp) {
    if (unixTimestamp <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(unixTimestamp * 1000);
    final year = dt.year;
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    final now = DateTime.now();
    if (year == now.year) return '$month-$day $hour:$minute';
    return '$year-$month-$day $hour:$minute';
  }
}
