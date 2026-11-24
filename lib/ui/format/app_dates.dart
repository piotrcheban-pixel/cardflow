/// Единый формат дат интерфейса (аудит 2.0, P3-13).
///
/// До аудита в одном продукте соседствовали «16 нояб. 2026 г.» (колоды,
/// `MaterialLocalizations.formatShortDate`), «21.11.2026» (провайдеры) и
/// «фев/апр» (календарь). Теперь одна короткая форма `дд.мм.гггг` для дат и
/// относительные подписи «Сегодня»/«Вчера» там, где важна свежесть.
///
/// Модуль без Flutter: его можно использовать в тестах и в доменных проверках.
library;

/// Склонения слова «день» не нужны: подписи короткие и без числа.
const String _today = 'Сегодня';
const String _yesterday = 'Вчера';

/// Короткая дата `дд.мм.гггг` в локальном времени.
String formatShortDate(DateTime value) {
  final DateTime local = value.toLocal();
  final String day = local.day.toString().padLeft(2, '0');
  final String month = local.month.toString().padLeft(2, '0');
  return '$day.$month.${local.year}';
}

/// Дата с относительной подписью для «сегодня/вчера».
///
/// [now] инжектируется в тестах; по умолчанию — текущее локальное время.
String formatRelativeDate(DateTime value, {DateTime? now}) {
  final DateTime local = value.toLocal();
  final DateTime reference = (now ?? DateTime.now()).toLocal();
  final int days = _dayDifference(reference, local);
  if (days == 0) return _today;
  if (days == 1) return _yesterday;
  return formatShortDate(local);
}

/// Дата и время `дд.мм.гггг чч:мм` (подтверждения, проверки подключения).
String formatDateTime(DateTime value) {
  final DateTime local = value.toLocal();
  final String hour = local.hour.toString().padLeft(2, '0');
  final String minute = local.minute.toString().padLeft(2, '0');
  return '${formatShortDate(local)} $hour:$minute';
}

/// Разница в календарных днях между [now] и [value] (обе даты локальные).
int _dayDifference(DateTime now, DateTime value) {
  final DateTime a = DateTime(now.year, now.month, now.day);
  final DateTime b = DateTime(value.year, value.month, value.day);
  return a.difference(b).inDays;
}
