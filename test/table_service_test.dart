import 'package:flutter_test/flutter_test.dart';
import 'package:pingpong_playhub/services/table_service.dart';

void main() {
  group('TableService.buildOptions - mese numerotate', () {
    test('stările: curentă, ocupată, liberă', () {
      final o = TableService.buildOptions(
        tableType: 'indoor',
        customTables: const [],
        sequentialCount: 3,
        currentId: 1,
        occupiedBy: {2: 'ana 19:00-20:00'},
        trainingBlocked: const {},
      );
      expect(o.map((e) => e.id), [1, 2, 3]);
      expect(o[0].state, TableState.current);
      expect(o[1].state, TableState.occupied);
      expect(o[1].detail, 'ana 19:00-20:00');
      expect(o[2].state, TableState.free);
    });

    test('fără mese', () {
      expect(
        TableService.buildOptions(
          tableType: 'indoor',
          customTables: const [],
          sequentialCount: 0,
          currentId: null,
          occupiedBy: const {},
          trainingBlocked: const {},
        ),
        isEmpty,
      );
    });
  });

  group('TableService.buildOptions - plan personalizat', () {
    final tables = [
      {'tableId': 10, 'name': 'Masa A', 'type': 'indoor'},
      {'tableId': 11, 'name': 'Masa B', 'type': 'training'},
      {'tableId': 12, 'name': 'Terasă', 'type': 'outdoor'},
    ];

    test('indoor arată indoor + antrenament, nu outdoor', () {
      final o = TableService.buildOptions(
        tableType: 'indoor',
        customTables: tables,
        sequentialCount: 0,
        currentId: 10,
        occupiedBy: const {},
        trainingBlocked: {11},
      );
      expect(o.map((e) => e.id), [10, 11]);
      expect(o[1].state, TableState.training);
    });

    test('outdoor arată doar mesele outdoor', () {
      final o = TableService.buildOptions(
        tableType: 'outdoor',
        customTables: tables,
        sequentialCount: 0,
        currentId: null,
        occupiedBy: const {},
        trainingBlocked: const {},
      );
      expect(o.map((e) => e.name), ['Terasă']);
    });

    test('masa curentă are prioritate față de ocupată', () {
      final o = TableService.buildOptions(
        tableType: 'indoor',
        customTables: tables,
        sequentialCount: 0,
        currentId: 10,
        occupiedBy: {10: 'x'},
        trainingBlocked: const {},
      );
      expect(o.first.state, TableState.current);
    });
  });
}
