import 'package:flutter_test/flutter_test.dart';
import 'package:lifeos/core/utils.dart';

void main() {
  test('Arabic normalization matches hamza / taa marbuta variants', () {
    expect(matchesQuery('أهداف السنة', 'اهداف'), isTrue);
    expect(matchesQuery('مكتبة', 'مكتبه'), isTrue);
    expect(matchesQuery('Data Analysis portfolio', 'data port'), isTrue);
    expect(matchesQuery('Data Analysis', 'data gym'), isFalse);
  });

  test('week starts on Saturday', () {
    final wed = DateTime(2026, 11, 25);
    expect(startOfWeek(wed, DateTime.saturday), DateTime(2026, 11, 21));
  });
}
