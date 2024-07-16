class BadiDateInterval implements Comparable<BadiDateInterval> {
  final int days;
  final int months;
  final int years;

  const BadiDateInterval({
    this.days = 0,
    this.months = 0,
    this.years = 0,
  });

  static const BadiDateInterval zero =
      BadiDateInterval(days: 0, months: 0, years: 0);

  @override
  int get hashCode => Object.hash(years, months, days);

  @override
  operator ==(Object other) {
    return identical(this, other) ||
        (other is BadiDateInterval &&
            years == other.years &&
            months == other.months &&
            days == other.days);
  }

  @override
  int compareTo(BadiDateInterval other) {
    if (this == other) {
      return 0;
    }
    return [
      years.compareTo(other.years),
      months.compareTo(other.months),
      days.compareTo(other.days),
    ].firstWhere((c) => c != 0);
  }

  BadiDateInterval copyWith({
    int? days,
    int? months,
    int? years,
  }) =>
      BadiDateInterval(
        days: days ?? this.days,
        months: months ?? this.months,
        years: years ?? this.years,
      );

  BadiDateInterval negate() =>
      copyWith(days: -days, months: -months, years: -years);

  @override
  String toString() =>
      'BadiDateInterval(days: $days, months: $months, years: $years)';
}
