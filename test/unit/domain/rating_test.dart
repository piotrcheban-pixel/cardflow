import 'package:cardflow/domain/scheduling/fsrs_mapper.dart';
import 'package:cardflow/domain/scheduling/rating.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;

/// Итерация 0, шаг 2 (красная фаза): маппинг оценок Again/Hard/Good/Easy на FSRS.
void main() {
  group('Rating: четыре оценки A7.2', () {
    test('порядок и значения 1..4 совпадают с FSRS', () {
      expect(Rating.values, <Rating>[
        Rating.again,
        Rating.hard,
        Rating.good,
        Rating.easy,
      ]);
      expect(Rating.again.value, 1);
      expect(Rating.hard.value, 2);
      expect(Rating.good.value, 3);
      expect(Rating.easy.value, 4);
    });

    test('fromValue восстанавливает оценку', () {
      for (final rating in Rating.values) {
        expect(Rating.fromValue(rating.value), rating);
      }
      expect(() => Rating.fromValue(0), throwsArgumentError);
      expect(() => Rating.fromValue(5), throwsArgumentError);
    });
  });

  group('FsrsMapper: маппинг оценок на пакет fsrs', () {
    test('каждая оценка маппится 1:1 по значению', () {
      for (final rating in Rating.values) {
        final mapped = FsrsMapper.toFsrs(rating);
        expect(mapped.value, rating.value);
        expect(mapped, fsrs.Rating.fromValue(rating.value));
      }
      expect(FsrsMapper.toFsrs(Rating.again), fsrs.Rating.again);
      expect(FsrsMapper.toFsrs(Rating.hard), fsrs.Rating.hard);
      expect(FsrsMapper.toFsrs(Rating.good), fsrs.Rating.good);
      expect(FsrsMapper.toFsrs(Rating.easy), fsrs.Rating.easy);
    });

    test('обратный маппинг восстанавливает оценку', () {
      for (final rating in Rating.values) {
        expect(FsrsMapper.fromFsrs(FsrsMapper.toFsrs(rating)), rating);
      }
    });

    test('маппинг состояний: new -> learning, остальные 1:1', () {
      expect(FsrsMapper.toFsrsState(CardState.newState), fsrs.State.learning);
      expect(FsrsMapper.toFsrsState(CardState.learning), fsrs.State.learning);
      expect(FsrsMapper.toFsrsState(CardState.review), fsrs.State.review);
      expect(
        FsrsMapper.toFsrsState(CardState.relearning),
        fsrs.State.relearning,
      );
    });

    test('обратный маппинг состояний покрывает все состояния FSRS', () {
      // В fsrs 2.0.1 State.new нет — проверяем и это условие совместимости.
      expect(fsrs.State.values, hasLength(3));
      expect(FsrsMapper.fromFsrsState(fsrs.State.learning), CardState.learning);
      expect(FsrsMapper.fromFsrsState(fsrs.State.review), CardState.review);
      expect(
        FsrsMapper.fromFsrsState(fsrs.State.relearning),
        CardState.relearning,
      );
      for (final state in fsrs.State.values) {
        expect(FsrsMapper.toFsrsState(FsrsMapper.fromFsrsState(state)), state);
      }
    });

    test('проводные имена состояний соответствуют SPEC A5', () {
      expect(CardState.newState.wireName, 'new');
      expect(CardState.learning.wireName, 'learning');
      expect(CardState.review.wireName, 'review');
      expect(CardState.relearning.wireName, 'relearning');
    });
  });
}
