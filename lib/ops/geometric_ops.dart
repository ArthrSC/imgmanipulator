import 'dart:math';
import 'dart:typed_data';
import '../core/img_data.dart';

/// ---------- TRANSFORMAÇÕES GEOMÉTRICAS ----------
/// Usam mapeamento INVERSO: para cada pixel do destino calcula-se de onde
/// ele vem na origem (sem buracos) e interpola-se bilinearmente.

const int kMaxSide = 10000;
const int kMaxPixels = 40 * 1000 * 1000;

void _checkSize(int w, int h) {
  if (w < 1 || h < 1) throw ImgException('Dimensões devem ser >= 1.');
  if (w > kMaxSide || h > kMaxSide || w * h > kMaxPixels) {
    throw ImgException('Dimensões resultantes grandes demais ($w x $h).');
  }
}

/// Interpolação bilinear em (xs, ys) com coordenadas já limitadas à imagem.
void _bilinear(ImgData s, double xs, double ys, Uint8List out, int o) {
  final w = s.width, h = s.height, d = s.rgba;
  final x0 = xs.floor(), y0 = ys.floor();
  final x1 = min(x0 + 1, w - 1), y1 = min(y0 + 1, h - 1);
  final fx = xs - x0, fy = ys - y0;
  final i00 = (y0 * w + x0) * 4, i10 = (y0 * w + x1) * 4;
  final i01 = (y1 * w + x0) * 4, i11 = (y1 * w + x1) * 4;
  for (int c = 0; c < 3; c++) {
    final top = d[i00 + c] * (1 - fx) + d[i10 + c] * fx;
    final bot = d[i01 + c] * (1 - fx) + d[i11 + c] * fx;
    out[o + c] = clamp255(top * (1 - fy) + bot * fy);
  }
  out[o + 3] = 255;
}

/// Rotação de [degrees] graus (positivo = anti-horário) em torno do centro.
/// A tela de saída é ampliada para caber toda a imagem:
///   W' = |W cosθ| + |H senθ|,  H' = |W senθ| + |H cosθ|
/// As regiões novas ficam pretas.
ImgData rotate(ImgData src, double degrees) {
  if (!degrees.isFinite) throw ImgException('Ângulo inválido.');
  final a = degrees * pi / 180.0;
  final cosA = cos(a), sinA = sin(a);
  final nw = max(1, (src.width * cosA.abs() + src.height * sinA.abs() - 1e-6).ceil());
  final nh = max(1, (src.width * sinA.abs() + src.height * cosA.abs() - 1e-6).ceil());
  _checkSize(nw, nh);

  final out = Uint8List(nw * nh * 4);
  final cxs = (src.width - 1) / 2, cys = (src.height - 1) / 2;
  final cxd = (nw - 1) / 2, cyd = (nh - 1) / 2;
  for (int y = 0; y < nh; y++) {
    for (int x = 0; x < nw; x++) {
      final dx = x - cxd, dy = y - cyd;
      // rotação inversa (y aponta para baixo)
      double xs = dx * cosA - dy * sinA + cxs;
      double ys = dx * sinA + dy * cosA + cys;
      final o = (y * nw + x) * 4;
      if (xs < -0.5 || xs > src.width - 0.5 || ys < -0.5 || ys > src.height - 0.5) {
        out[o + 3] = 255; // fora da imagem original: preto
        continue;
      }
      xs = xs.clamp(0.0, src.width - 1.0).toDouble();
      ys = ys.clamp(0.0, src.height - 1.0).toDouble();
      _bilinear(src, xs, ys, out, o);
    }
  }
  return ImgData(nw, nh, out);
}

/// Translação: x' = x + dx, y' = y + dy (dy positivo = para baixo).
/// A tela mantém o tamanho original; o que sai é descartado e o que
/// entra é preto.
ImgData translate(ImgData src, int dx, int dy) {
  final w = src.width, h = src.height;
  final out = Uint8List(w * h * 4);
  for (int i = 3; i < out.length; i += 4) {
    out[i] = 255;
  }
  for (int y = 0; y < h; y++) {
    final sy = y - dy;
    if (sy < 0 || sy >= h) continue;
    for (int x = 0; x < w; x++) {
      final sx = x - dx;
      if (sx < 0 || sx >= w) continue;
      final o = (y * w + x) * 4, i = (sy * w + sx) * 4;
      out[o] = src.rgba[i];
      out[o + 1] = src.rgba[i + 1];
      out[o + 2] = src.rgba[i + 2];
    }
  }
  return ImgData(w, h, out);
}

/// Espelhamento horizontal (esquerda <-> direita) ou vertical (cima <-> baixo).
ImgData flip(ImgData src, {required bool horizontal}) {
  final w = src.width, h = src.height;
  final out = Uint8List(w * h * 4);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final sx = horizontal ? w - 1 - x : x;
      final sy = horizontal ? y : h - 1 - y;
      final o = (y * w + x) * 4, i = (sy * w + sx) * 4;
      out[o] = src.rgba[i];
      out[o + 1] = src.rgba[i + 1];
      out[o + 2] = src.rgba[i + 2];
      out[o + 3] = 255;
    }
  }
  return ImgData(w, h, out);
}

/// Redimensionamento com interpolação bilinear.
ImgData resize(ImgData src, int newW, int newH) {
  _checkSize(newW, newH);
  final out = Uint8List(newW * newH * 4);
  final sx = src.width / newW, sy = src.height / newH;
  for (int y = 0; y < newH; y++) {
    final ys = ((y + 0.5) * sy - 0.5).clamp(0.0, src.height - 1.0).toDouble();
    for (int x = 0; x < newW; x++) {
      final xs = ((x + 0.5) * sx - 0.5).clamp(0.0, src.width - 1.0).toDouble();
      _bilinear(src, xs, ys, out, (y * newW + x) * 4);
    }
  }
  return ImgData(newW, newH, out);
}
