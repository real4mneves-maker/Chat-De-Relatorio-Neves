import 'package:flutter_test/flutter_test.dart';
import 'package:chat_de_relatorio_neves/main.dart';

void main() {
  test('Identifica transporte sem acrescentar informacoes', () {
    final report = localReport('transporte de paciente sem intercorrências');
    expect(report, contains('TRANSPORTE DE PACIENTE'));
    expect(report, contains('sem intercorrências'));
  });

  test('Identifica higienizacao de equipamentos', () {
    final report = localReport('Todas as cadeiras de banho foram higienizadas');
    expect(report, contains('HIGIENIZAÇÃO DE EQUIPAMENTOS'));
  });
}
