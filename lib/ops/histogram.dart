import '../core/img_data.dart';

/// Histogramas de uma imagem (256 níveis).
class HistogramData {
  final List<int> r, g, b, lum;
  final bool grayscale;
  final int pixels;
  HistogramData(this.r, this.g, this.b, this.lum, this.grayscale, this.pixels);

  int get maxCount {
    int m = 1;
    final lists = grayscale ? [lum] : [r, g, b];
    for (final l in lists) {
      for (final v in l) {
        if (v > m) m = v;
      }
    }
    return m;
  }

  double get meanIntensity {
    int s = 0;
    for (int i = 0; i < 256; i++) {
      s += i * lum[i];
    }
    return pixels == 0 ? 0 : s / pixels;
  }
}

/// h(k) = número de pixels com intensidade k.
HistogramData computeHistogram(ImgData src) {
  final r = List<int>.filled(256, 0);
  final g = List<int>.filled(256, 0);
  final b = List<int>.filled(256, 0);
  final l = List<int>.filled(256, 0);
  final d = src.rgba;
  for (int i = 0; i < d.length; i += 4) {
    r[d[i]]++;
    g[d[i + 1]]++;
    b[d[i + 2]]++;
    l[luma(d[i], d[i + 1], d[i + 2])]++;
  }
  return HistogramData(r, g, b, l, src.isGrayscale, src.pixelCount);
}
