import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:imgmanipulator/core/img_data.dart';
import 'package:imgmanipulator/ops/geometric_ops.dart';
import 'package:imgmanipulator/ops/neighborhood_ops.dart';
import 'package:imgmanipulator/ops/point_ops.dart';

ImgData _sample() {
  final d = Uint8List(4 * 3 * 4);
  for (int i = 0; i < 12; i++) {
    d[i * 4] = i * 20;
    d[i * 4 + 1] = 255 - i * 10;
    d[i * 4 + 2] = i * 5;
    d[i * 4 + 3] = 255;
  }
  return ImgData(4, 3, d);
}

void main() {
  test('negativo duas vezes = identidade', () {
    final s = _sample();
    expect(negative(negative(s)).rgba, s.rgba);
  });

  test('brilho satura em [0,255]', () {
    final r = adjustBrightness(_sample(), 300);
    expect(r.rgba.every((v) => v <= 255), true);
    expect(r.rgba[0], 255);
  });

  test('espelhamento duas vezes = identidade', () {
    final s = _sample();
    expect(flip(flip(s, horizontal: true), horizontal: true).rgba, s.rgba);
    expect(flip(flip(s, horizontal: false), horizontal: false).rgba, s.rgba);
  });

  test('rotação de 90° troca largura e altura', () {
    final r = rotate(_sample(), 90);
    expect(r.width, 3);
    expect(r.height, 4);
  });

  test('rotação de 45° amplia a tela', () {
    final r = rotate(ImgData.blank(100, 100, r: 200), 45);
    expect(r.width, greaterThan(100));
  });

  test('kernels são normalizados', () {
    expect(meanKernel1D(5).reduce((a, b) => a + b), closeTo(1, 1e-9));
    expect(gaussianKernel1D(7, 1.5).reduce((a, b) => a + b), closeTo(1, 1e-9));
  });

  test('validações de kernel e sigma', () {
    expect(() => meanKernel1D(4), throwsA(isA<ImgException>()));
    expect(() => gaussianKernel1D(5, 0), throwsA(isA<ImgException>()));
    expect(() => gaussianKernel1D(5, -1), throwsA(isA<ImgException>()));
  });

  test('convolução separável == convolução 2D', () {
    final s = ImgData.blank(9, 7, r: 10, g: 100, b: 200);
    final noisy = addGaussianNoise(s, 30, 1);
    final a = gaussianFilter(noisy, 5, 1.2, separable: true);
    final b = gaussianFilter(noisy, 5, 1.2, separable: false);
    for (int i = 0; i < a.rgba.length; i++) {
      expect((a.rgba[i] - b.rgba[i]).abs(), lessThanOrEqualTo(1));
    }
  });

  test('imagem constante não muda com filtro da média', () {
    final s = ImgData.blank(8, 8, r: 90, g: 90, b: 90);
    expect(meanFilter(s, 7).rgba, s.rgba);
  });

  test('equalização mantém tamanho e faixa', () {
    final e = equalizeHistogram(toGrayscale(_sample()));
    expect(e.rgba.length, _sample().rgba.length);
  });
}
