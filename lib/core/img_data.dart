import 'dart:typed_data';

/// Erro de domínio (parâmetro inválido, formato inválido, etc.).
class ImgException implements Exception {
  final String message;
  ImgException(this.message);
  @override
  String toString() => message;
}

/// Imagem como matriz de pixels RGBA (8 bits por canal), linha a linha.
/// índice do pixel (x, y) = (y * width + x) * 4
class ImgData {
  final int width;
  final int height;
  final Uint8List rgba;

  ImgData(this.width, this.height, this.rgba)
      : assert(rgba.length == width * height * 4);

  /// Imagem preenchida com uma cor sólida (alfa = 255).
  factory ImgData.blank(int w, int h, {int r = 0, int g = 0, int b = 0}) {
    final data = Uint8List(w * h * 4);
    for (int i = 0; i < data.length; i += 4) {
      data[i] = r;
      data[i + 1] = g;
      data[i + 2] = b;
      data[i + 3] = 255;
    }
    return ImgData(w, h, data);
  }

  int get pixelCount => width * height;

  ImgData clone() => ImgData(width, height, Uint8List.fromList(rgba));

  /// Verdadeiro se R == G == B em todos os pixels.
  bool get isGrayscale {
    for (int i = 0; i < rgba.length; i += 4) {
      if (rgba[i] != rgba[i + 1] || rgba[i + 1] != rgba[i + 2]) return false;
    }
    return true;
  }
}

/// Limita o valor ao intervalo [0, 255] (imagens de 8 bits) e arredonda.
int clamp255(num v) => v < 0 ? 0 : (v > 255 ? 255 : v.round());

/// Luminância (ITU-R BT.601): Y = 0,299 R + 0,587 G + 0,114 B
int luma(int r, int g, int b) => (0.299 * r + 0.587 * g + 0.114 * b).round();
