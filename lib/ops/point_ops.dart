import 'dart:typed_data';
import '../core/img_data.dart';

/// ---------- TRANSFORMAÇÕES PONTUAIS ----------
/// Cada pixel é alterado usando apenas o seu próprio valor.

/// Escala de cinza: I = 0,299 R + 0,587 G + 0,114 B  (R = G = B = I)
ImgData toGrayscale(ImgData src) {
  final out = Uint8List.fromList(src.rgba);
  for (int i = 0; i < out.length; i += 4) {
    final y = luma(out[i], out[i + 1], out[i + 2]);
    out[i] = out[i + 1] = out[i + 2] = y;
  }
  return ImgData(src.width, src.height, out);
}

/// Brilho: g = f + delta, saturado em [0, 255].
ImgData adjustBrightness(ImgData src, int delta) {
  final lut = List<int>.generate(256, (v) => clamp255(v + delta));
  return _applyLut(src, lut);
}

/// Contraste: g = fator * (f - 128) + 128, saturado em [0, 255].
/// fator > 1 aumenta o contraste; 0 < fator < 1 reduz.
ImgData adjustContrast(ImgData src, double factor) {
  final lut = List<int>.generate(256, (v) => clamp255(factor * (v - 128) + 128));
  return _applyLut(src, lut);
}

/// Negativo: g = 255 - f
ImgData negative(ImgData src) {
  final lut = List<int>.generate(256, (v) => 255 - v);
  return _applyLut(src, lut);
}

/// Alongamento de contraste (normalização linear):
///   g = (f - fmin) / (fmax - fmin) * 255
/// fmin/fmax são o menor/maior valor encontrado em todos os canais
/// (usar o mesmo par para R, G e B preserva a tonalidade das cores).
ImgData contrastStretch(ImgData src) {
  int fmin = 255, fmax = 0;
  final d = src.rgba;
  for (int i = 0; i < d.length; i += 4) {
    for (int c = 0; c < 3; c++) {
      final v = d[i + c];
      if (v < fmin) fmin = v;
      if (v > fmax) fmax = v;
    }
  }
  if (fmax == fmin) {
    throw ImgException(
        'Imagem com intensidade constante: não há faixa para alongar.');
  }
  final lut = List<int>.generate(
      256, (v) => clamp255((v - fmin) / (fmax - fmin) * 255));
  return _applyLut(src, lut);
}

/// Equalização de histograma.
///   cdf(k) = soma de h(0..k);  T(k) = round((cdf(k) - cdfmin) / (N - cdfmin) * 255)
/// A equalização é feita sobre a LUMINÂNCIA Y. Para manter a crominância
/// (Cb, Cr) inalterada, soma-se (Y' - Y) aos três canais RGB. Em imagens
/// cinza (R = G = B = Y) isso equivale a equalizar as intensidades diretamente.
ImgData equalizeHistogram(ImgData src) {
  final n = src.pixelCount;
  final d = src.rgba;
  final hist = List<int>.filled(256, 0);
  final ys = Uint8List(n);
  for (int p = 0; p < n; p++) {
    final y = luma(d[p * 4], d[p * 4 + 1], d[p * 4 + 2]);
    ys[p] = y;
    hist[y]++;
  }
  final cdf = List<int>.filled(256, 0);
  int acc = 0;
  for (int k = 0; k < 256; k++) {
    acc += hist[k];
    cdf[k] = acc;
  }
  int cdfMin = 0;
  for (int k = 0; k < 256; k++) {
    if (hist[k] > 0) {
      cdfMin = cdf[k];
      break;
    }
  }
  final denom = n - cdfMin;
  if (denom <= 0) {
    throw ImgException('Imagem com intensidade constante: equalização inválida.');
  }
  final lut = List<int>.generate(
      256, (k) => clamp255((cdf[k] - cdfMin) / denom * 255));

  final out = Uint8List.fromList(d);
  for (int p = 0; p < n; p++) {
    final diff = lut[ys[p]] - ys[p];
    final i = p * 4;
    out[i] = clamp255(out[i] + diff);
    out[i + 1] = clamp255(out[i + 1] + diff);
    out[i + 2] = clamp255(out[i + 2] + diff);
  }
  return ImgData(src.width, src.height, out);
}

ImgData _applyLut(ImgData src, List<int> lut) {
  final out = Uint8List.fromList(src.rgba);
  for (int i = 0; i < out.length; i += 4) {
    out[i] = lut[out[i]];
    out[i + 1] = lut[out[i + 1]];
    out[i + 2] = lut[out[i + 2]];
  }
  return ImgData(src.width, src.height, out);
}
