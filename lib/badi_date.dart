import 'dart:math';

import 'package:badi_date/badi_date_interval.dart';
import 'package:badi_date/bahai_holyday.dart';
import 'package:badi_date/names.dart';
import 'package:badi_date/years.dart';
import 'package:dart_suncalc/suncalc.dart';

/// A Badi Date
class BadiDate implements Comparable<BadiDate> {
  static const LAST_YEAR_SUPPORTED = 221;
  static const YEAR_ONE_IN_GREGORIAN = 1844;
  static const YEAR_ZERO_IN_GREGORIAN = YEAR_ONE_IN_GREGORIAN - 1;
  final int day;

  /// The month number with Baha = 1, ... Ayyam'i'Ha = 19, and Ala = 20
  int _monthIntern = -1;

  /// The month number with Ayyam'i'Ha = 0 and Baha = 1, ... Ala = 19
  final int month;

  /// The full year of the Badi Calendar with 2020 AC = 177 BE
  final int year;

  /// longitude value of degree coordinates for sunset calculation in the range [-180,180]
  final double? longitude;

  /// latitude value of degree coordinates for sunset calculation in the range [-90,90]
  final double? latitude;

  /// altitude in meters
  final double? altitude;

  /// Badi date
  /// for now only for the years up to LAST_YEAR_SUPPORTED
  /// Dates before the year 172 are calculated according to the Baha'i Calendar
  /// used in western countries.
  /// parameters:
  /// day int in range [1-19]
  /// month int in range [0-19]
  /// year int
  /// longitude and latitude double for sunset calculation
  /// ayyamIHa bool
  /// For Ayyam'i'Ha set month to 0 or leave it empty and set ayyamIHa to true
  BadiDate({
    required this.day,
    required this.month,
    required this.year,
    bool ayyamIHa = false,
    this.latitude,
    this.longitude,
    this.altitude,
  }) {
    if (day < 1 || day > 19) {
      throw ArgumentError.value(day, 'day', 'Day must be in the range [1-19]');
    }
    if (month < 0 || month > 19) {
      throw ArgumentError.value(
          month, 'month', 'Month must be in the range [1-19]');
    }
    if (month != 0 && ayyamIHa) {
      throw ArgumentError.value(
          month, 'month', 'Please set month to 0 or leave it out for AyyamIHa');
    }
    if ((latitude == null) != (longitude == null)) {
      throw ArgumentError(
          'both latitude and longitude should be specified, or neither');
    }
    if ((latitude?.abs() ?? 0) > 90.0) {
      throw ArgumentError('latitude out of range (-90...90)');
    }
    if ((longitude?.abs() ?? 0) > 180.0) {
      throw ArgumentError('longitude out of range (-180...180)');
    }
    if ((altitude ?? 0) < 0) {
      throw ArgumentError('altitude must be greater than zero');
    }
    if (year > LAST_YEAR_SUPPORTED) {
      throw UnsupportedError(
          'Years greater than $LAST_YEAR_SUPPORTED are not supported yet');
    }
    _monthIntern = _monthToMonthIntern(month);
  }

  /// Convenience factory to construct a [BadiDate] from [DateTime.now].
  factory BadiDate.now({
    double? latitude,
    double? longitude,
    double? altitude,
  }) =>
      BadiDate.fromDate(
        DateTime.now(),
        latitude: latitude,
        longitude: longitude,
        altitude: altitude,
      );

  /// The year in the Vahid. A value in the range from [1-19]
  int get yearInVahid {
    return year % 19 == 0 ? 19 : year % 19;
  }

  /// Vahid = 19 years
  int get vahid {
    return ((year - yearInVahid) / 19).floor() + 1;
  }

  /// Kull'i'shay = 19 Vahids = 361 years
  int get kullIShay {
    return (year / 361).floor() + 1;
  }

  String get monthName => monthNames[month]!;
  String get monthNameEnglish => monthNamesEnglish[month]!;

  /// Number of Ayyam'i'ha days the year has
  /// For years < 172: use only for January 1st to before Naw-Ruz
  static int _getNumberAyyamIHaDays(int year) {
    final yearSpecific = yearSpecifics[year];
    if (yearSpecific == null) {
      final gregYear = year + YEAR_ONE_IN_GREGORIAN;
      final isleapyear =
          gregYear % 4 == 0 && gregYear % 100 != 0 || gregYear % 400 == 0;
      return isleapyear ? 5 : 4;
    }
    return yearSpecific.leapday ? 5 : 4;
  }

  static int getDayOfNawRuz(int year) {
    final yearSpecific = yearSpecifics[year];
    if (yearSpecific == null) {
      return 21;
    }
    return yearSpecific.nawRuzOnMarch21 ? 21 : 20;
  }

  /// the day of the year with Naw Ruz = 1
  int get dayOfYear {
    if (_monthIntern == 20) {
      return 342 + _getNumberAyyamIHaDays(year) + day;
    }
    return (_monthIntern - 1) * 19 + day;
  }

  /// Is the date in the period of fast
  bool get isPeriodOfFast {
    return month == 19;
  }

  /// is the date an Ayyam'i'Ha day
  bool get isAyyamIHa {
    return month == 0;
  }

  /// is the date a feast date
  bool get isFeastDay {
    return day == 1 && !isAyyamIHa;
  }

  static DateTime _calculateSunSet(DateTime date,
      {double? longitude, double? latitude, double? altitude}) {
    final fallback = DateTime(date.year, date.month, date.day, 18);
    // return 6pm if no location or if in the poles
    if (latitude == null ||
        longitude == null ||
        latitude > 66.0 ||
        latitude < -66.0 ||
        longitude.abs() > 180.0) {
      return fallback;
    }
    final sunCalcTimes = SunCalc.getTimes(date,
        lat: latitude, lng: longitude, height: altitude ?? 0.0);
    // The sunset of places far west might have the sunset calculated
    // for the day before. In that case we add a day and calculate again.
    if (sunCalcTimes.sunset?.day == date.day - 1) {
      final sunCalcWithAdjustment = SunCalc.getTimes(
          date.add(Duration(days: 1)),
          lat: latitude,
          lng: longitude,
          height: altitude ?? 0.0);
      return sunCalcWithAdjustment.sunset ?? fallback;
    }
    return sunCalcTimes.sunset ?? fallback;
  }

  static DateTime _utcToLocale(DateTime date) {
    if (!date.isUtc) {
      return date;
    }
    final localeDate = DateTime(date.year, date.month, date.day);
    return localeDate
        .add(Duration(hours: date.hour, minutes: date.minute))
        .add(localeDate.timeZoneOffset);
  }

  DateTime get nawRuzDate =>
      DateTime.utc(year + YEAR_ZERO_IN_GREGORIAN, 3, getDayOfNawRuz(year));

  /// Start DateTime
  DateTime get startDateTime {
    final date = nawRuzDate.add(Duration(days: dayOfYear - 2));
    return _utcToLocale(_calculateSunSet(date,
        longitude: longitude, latitude: latitude, altitude: altitude));
  }

  /// End DateTime
  DateTime get endDateTime {
    final date = nawRuzDate.add(Duration(days: dayOfYear - 1));
    return _utcToLocale(_calculateSunSet(date,
        longitude: longitude, latitude: latitude, altitude: altitude));
  }

  DateTime get monthStartDateTime => firstDayOfMonth.startDateTime;

  DateTime get monthEndDateTime => lastDayOfMonth.endDateTime;

  static BadiDate _fromYearAndDayOfYear(
      {required int year,
      required int doy,
      double? longitude,
      double? latitude,
      double? altitude}) {
    if (doy < 1 || doy > 366) {
      throw ArgumentError.value(
          doy, 'doy', 'Day of year must be in the range [1-366]');
    }
    final month = (doy / 19).ceil();
    final day = doy - (month - 1) * 19;
    if (month < 19) {
      return BadiDate(
          day: day,
          month: month,
          year: year,
          longitude: longitude,
          latitude: latitude,
          altitude: altitude);
    } else if (month == 19 && day <= _getNumberAyyamIHaDays(year)) {
      return BadiDate(
          day: day,
          month: 0,
          year: year,
          longitude: longitude,
          latitude: latitude,
          altitude: altitude);
    }
    final alaDay = doy - 342 - _getNumberAyyamIHaDays(year);
    return BadiDate(
        day: alaDay,
        month: 19,
        year: year,
        longitude: longitude,
        latitude: latitude,
        altitude: altitude);
  }

  /// BadiDate from a DateTime object
  /// Optional parameter double longitude, latitude, altitude for the sunset time
  static BadiDate fromDate(DateTime gregorianDate,
      {double? longitude, double? latitude, double? altitude}) {
    // we convert to utc to avoid daylight saving issues
    final dateTime = DateTime.utc(
        gregorianDate.year, gregorianDate.month, gregorianDate.day);
    if (dateTime.isAfter(DateTime.utc(2065, 3, 19))) {
      throw UnsupportedError('Dates after 2064-03-19 are not supported yet.');
    }
    final isAfterSunset = gregorianDate.isAfter(_calculateSunSet(gregorianDate,
        longitude: longitude, latitude: latitude, altitude: altitude));
    final date = isAfterSunset ? dateTime.add(Duration(days: 1)) : dateTime;
    final badiYear = date.year - YEAR_ZERO_IN_GREGORIAN;
    final isBeforeNawRuz =
        date.isBefore(DateTime.utc(date.year, 3, getDayOfNawRuz(badiYear)));
    if (!isBeforeNawRuz) {
      final doy =
          date.difference(DateTime.utc(date.year, 3, getDayOfNawRuz(badiYear)));
      // +1 because naw ruz has a doy of 1 but a difference of 0
      return _fromYearAndDayOfYear(
          year: badiYear,
          doy: doy.inDays + 1,
          longitude: longitude,
          latitude: latitude,
          altitude: altitude);
    }
    final doy = date.difference(
        DateTime.utc(date.year - 1, 3, getDayOfNawRuz(badiYear - 1)));
    return _fromYearAndDayOfYear(
        year: badiYear - 1,
        doy: doy.inDays + 1,
        longitude: longitude,
        latitude: latitude,
        altitude: altitude);
  }

  /// If the BadiDate is a Baha'i Holy day the Holy date else null
  BahaiHolyDayEnum? get holyDay {
    final birthOfBab = yearSpecifics[year]?.birthOfBab;
    return bahaiHolyDays
        .firstWhere(
            (holyDay) =>
                holyDay?.getDayOfTheYear(dayOfYearBirthOfBab: birthOfBab) ==
                dayOfYear,
            orElse: () => null)
        ?.type;
  }

  /// The BadiDate of the previous feast. If `day` > 1, returns the current BadiDate
  /// with the day set to 1.
  BadiDate getPreviousFeast() {
    if (day > 1) {
      return copyWith(day: 1);
    }
    if (month == 1) {
      return copyWith(day: 1, month: 19, year: year - 1);
    }
    return copyWith(day: 1, month: month - 1);
  }

  /// The BadiDate of the next feast
  BadiDate getNextFeast() {
    if (month == 19) {
      return copyWith(day: 1, month: 1, year: year + 1);
    }
    return copyWith(day: 1, month: month + 1);
  }

  /// The BadiDate of the next Holy day
  BadiDate get nextHolyDate {
    final birthOfBab = yearSpecifics[year]?.birthOfBab;
    final doy = bahaiHolyDays
        .firstWhere(
            (holyDay) =>
                (holyDay?.getDayOfTheYear(dayOfYearBirthOfBab: birthOfBab) ??
                    0) >
                dayOfYear,
            orElse: () => null)
        ?.getDayOfTheYear(dayOfYearBirthOfBab: birthOfBab);
    if (doy == null) {
      return _fromYearAndDayOfYear(
          year: year + 1,
          doy: 1,
          longitude: longitude,
          latitude: latitude,
          altitude: altitude);
    }
    return _fromYearAndDayOfYear(
        year: year,
        doy: doy,
        longitude: longitude,
        latitude: latitude,
        altitude: altitude);
  }

  // return the last Ayyam'i'Ha day of that Badi year
  BadiDate get lastAyyamIHaDayOfYear {
    final firstAla = BadiDate(
        day: 1,
        year: year,
        month: 19,
        longitude: longitude,
        latitude: latitude,
        altitude: altitude);
    return BadiDate._fromYearAndDayOfYear(
        year: year,
        doy: firstAla.dayOfYear - 1,
        longitude: longitude,
        latitude: latitude,
        altitude: altitude);
  }

  // equality
  @override
  bool operator ==(Object other) =>
      other is BadiDate &&
      other.year == year &&
      other.dayOfYear == dayOfYear &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.altitude == altitude;

  // hash code
  @override
  int get hashCode =>
      Object.hash(year, dayOfYear, latitude, longitude, altitude);

  @override
  int compareTo(BadiDate other) {
    if (this == other) {
      return 0;
    }
    if (year != other.year) {
      return year.compareTo(other.year);
    }
    return dayOfYear.compareTo(other.dayOfYear);
  }

  operator >(BadiDate other) => compareTo(other) > 0;

  operator >=(BadiDate other) => compareTo(other) >= 0;

  operator <(BadiDate other) => compareTo(other) < 0;

  operator <=(BadiDate other) => compareTo(other) <= 0;

  /// Checks whether `startDateTime` occurs after `other.startDateTime` using [DateTime.isAfter];
  bool isBefore(BadiDate other) => startDateTime.isBefore(other.startDateTime);

  /// Checks whether `startDateTime` occurs before `other.startDateTime` using [DateTime.isBefore];
  bool isAfter(BadiDate other) => startDateTime.isAfter(other.startDateTime);

  BadiDate get firstDayOfMonth => copyWith(day: 1);
  BadiDate get lastDayOfMonth => getNextFeast() - 1;

  int _monthInternToMonth(int monthIntern) => monthIntern == 19
      ? 0
      : monthIntern == 20
          ? 19
          : monthIntern;

  int _monthToMonthIntern(int month) => month == 0
      ? 19
      : month == 19
          ? 20
          : month;

  BadiDate subtract(BadiDateInterval interval,
          {bool includeAyyamIHaInMonths = false}) =>
      add(interval.negate(), includeAyyamIHaInMonths: includeAyyamIHaInMonths);

  /// Returns a copy of `this` with the given number of `years` added.
  /// If `this` is during Ayyám-i-Há, the resulting `day` will be clamped to the number of days
  /// in Ayyám-i-Há for that year.
  ///
  /// If `years` is zero, `this` is returned unchanged.
  BadiDate addYears(int years) {
    if (!years.isFinite) {
      throw ArgumentError('years must be finite');
    }

    if (years == 0) {
      return this;
    }

    BadiDate badiDate = this;
    final newYear = year + years;
    if (badiDate.isAyyamIHa) {
      final ayyamIHaDays = _getNumberAyyamIHaDays(newYear);
      if (badiDate.day > ayyamIHaDays) {
        badiDate = badiDate.copyWith(day: 1, month: 19);
      }
    }
    return badiDate.copyWith(year: newYear);
  }

  /// Returns a copy of `this` with `months` added. Pass a negative
  /// `months` to subtract.
  ///
  /// If `this` is during Ayyám-i-Há, Ayyám-i-Há is always counted as the
  /// current "month", regardless of `includeAyyamIHa`.
  ///
  /// If `includeAyyamIHa` is true:
  ///   - Ayyám-i-Há is counted as a "month" during addition or subtraction;
  ///   - If the resulting BadiDate falls during Ayyám-i-Há, its `day`
  ///     is clamped to the maximum number of Ayyám-i-Há days that year.
  ///
  /// If `includeAyyamIHa` is false, the resulting [BadiDate] can only be
  /// during Ayyám-i-Há if `months` is zero.
  ///
  /// If `months` is zero, `this` is returned unchanged.
  BadiDate addMonths(int months, {bool includeAyyamIHa = false}) {
    if (months == 0) {
      return this;
    }

    if (!months.isFinite) {
      throw ArgumentError('months must be finite');
    }

    final sign = months.sign;
    BadiDate badiDate = this;
    int savedDay = badiDate.day;
    int ayyamIHaDays = _getNumberAyyamIHaDays(badiDate.year);
    while (months != 0) {
      months -= sign;
      int newMonthIntern = badiDate._monthIntern + sign;
      int newYear = badiDate.year;
      int newDay = badiDate.day;
      if (newMonthIntern == 19) {
        if (includeAyyamIHa) {
          newDay = min(newDay, ayyamIHaDays);
        } else {
          newMonthIntern += sign;
        }
      } else {
        newDay = savedDay;
        if (newMonthIntern < 1) {
          newMonthIntern = 20;
          newYear--;
        } else if (newMonthIntern > 20) {
          newMonthIntern = 1;
          newYear++;
        }
      }
      final yearChanged = newYear != badiDate.year;
      badiDate = badiDate.copyWith(
        day: newDay,
        month: _monthInternToMonth(newMonthIntern),
        year: newYear,
      );
      if (yearChanged) {
        ayyamIHaDays = _getNumberAyyamIHaDays(badiDate.year);
      }
    }
    return badiDate;
  }

  /// Returns a copy of `this` with the given number of `days` added.
  /// The number of days in Ayyám-i-Há for the [BadiDate.year] are taken into
  /// account during the calculation.
  ///
  /// If `days` is zero, `this` is returned unchanged.
  BadiDate addDays(int days) {
    if (!days.isFinite) {
      throw ArgumentError('days must be finite');
    }

    if (days == 0) {
      return this;
    }

    BadiDate badiDate = this;
    int ayyamIHaDays = _getNumberAyyamIHaDays(badiDate.year);
    while (days != 0) {
      int newDay = badiDate.day + days.sign;
      int newMonthIntern = badiDate._monthIntern;
      int newYear = badiDate.year;
      if (newDay > 19 || (badiDate.isAyyamIHa && newDay > ayyamIHaDays)) {
        newDay = 1;
        newMonthIntern++;
        if (newMonthIntern > 20) {
          newMonthIntern = 1;
          newYear++;
        }
      } else if (newDay < 1) {
        newDay = 19;
        newMonthIntern--;
        if (newMonthIntern == 19) {
          newDay = ayyamIHaDays;
        } else if (newMonthIntern < 1) {
          newMonthIntern = 20;
          newYear--;
        }
      }
      final yearChanged = newYear != badiDate.year;
      badiDate = badiDate.copyWith(
        day: newDay,
        month: _monthInternToMonth(newMonthIntern),
        year: newYear,
      );
      if (yearChanged) {
        ayyamIHaDays = _getNumberAyyamIHaDays(badiDate.year);
      }
      days -= days.sign;
    }
    return badiDate;
  }

  /// Performs addition or subtraction of the given [BadiDateInterval]
  /// and returns the resulting [BadiDate] as a copy.
  ///
  /// IMPORTANT: The operations occur in the following order:
  /// 1. [BadiDateInterval.years] is added to `this`;
  /// 2. [BadiDateInterval.months] is added to the result from #1;
  /// 3. [BadiDateInterval.days] is added to the result from #2.
  ///
  /// This order matters especially if `includeAyyamIHaInMonths` is true,
  /// because, if the [BadiDate] resulting from #2 falls during Ayyám-i-Há,
  /// its `day` is clamped to the number of Ayyám-i-Há days for that year,
  /// then [BadiDateInterval.days] is added, the result of which may not be intuitive.
  ///
  /// TODO(tgrushka): 2 examples
  ///
  /// If `this` is during Ayyám-i-Há, Ayyám-i-Há is always counted as the
  /// current "month", regardless of `includeAyyamIHaInMonths`.
  ///
  /// TODO(tgrushka): Example
  ///
  /// If `includeAyyamIHaInMonths` is false, a date during Ayyám-i-Há can only
  /// be reached if:
  /// - [BadiDateInterval.days] is not zero, or
  /// - `this` is during Ayyám-i-Há and [BadiDateInterval.years] is not zero.
  ///
  /// TODO(tgrushka): 2 examples
  ///
  /// If `interval` == [BadiDateInterval.zero], `this` is returned unchanged.
  BadiDate add(
    BadiDateInterval interval, {
    bool includeAyyamIHaInMonths = false,
  }) =>
      interval == BadiDateInterval.zero
          ? this
          : addYears(interval.years)
              .addMonths(interval.months,
                  includeAyyamIHa: includeAyyamIHaInMonths)
              .addDays(interval.days);

  /// Returns a copy of `this` with the given number of days or `BadiDateInterval` added.
  BadiDate operator +(Object daysOrInterval) {
    if (daysOrInterval is int) {
      return addDays(daysOrInterval);
    }
    if (daysOrInterval is BadiDateInterval) {
      return add(daysOrInterval.negate());
    }
    throw ArgumentError(
        'argument must be an integer (days) or a BadiDateInterval');
  }

  /// Returns a copy of `this` with the given number of days or `BadiDateInterval` subtracted.
  /// This is the same as `+` with its argument negated.
  BadiDate operator -(Object daysOrInterval) {
    if (daysOrInterval is int) {
      return addDays(-daysOrInterval);
    }
    if (daysOrInterval is BadiDateInterval) {
      return subtract(daysOrInterval);
    }
    throw ArgumentError(
        'argument must be an integer (days) or a BadiDateInterval');
  }

  /// Returns a copy of this [BadiDate] with any supplied arguments modified.
  /// If `latitude`, `longitude`, or `altitude` are passed as null, these will overwrite
  /// the same properties of `this` with null (don't pass them, or use the default of
  /// [double.infinity], to leave unchanged).
  BadiDate copyWith({
    int? day,
    int? month,
    int? year,
    double? latitude = double.infinity,
    double? longitude = double.infinity,
    double? altitude = double.infinity,
  }) =>
      BadiDate(
        day: day ?? this.day,
        month: month ?? this.month,
        year: year ?? this.year,
        latitude: latitude == double.infinity ? this.latitude : latitude,
        longitude: longitude == double.infinity ? this.longitude : longitude,
        altitude: altitude == double.infinity ? this.altitude : altitude,
      );

  @override
  String toString() => [
        'BadiDate(',
        'day: $day, month: $month, year: $year',
        if (latitude != null || longitude != null || altitude != null)
          ', latitude: $latitude, longitude: $longitude, altitude: $altitude',
        ')',
      ].join();
}
