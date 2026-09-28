import 'dart:math';
import 'dart:typed_data';
import '../core/img_data.dart';

/// ---------- TRANSFORMAÇÕES POR VIZINHANÇA ----------
///
/// TRATAMENTO DE BORDAS: REFLEXÃO (reflect-101, sem repetir o pixel da borda).
/// Um índice fora da imagem i < 0 vira -i e i >= n vira 2(n-1) - i.
/// Ex.: para n = 5, a sequência de índices ... 2 1 [0 1 2 3 4] 3 2 ...
/// Vantagem sobre zeros: não escurece as bordas; sobre replicação: não
/// cria faixas constantes.

const int kMaxKernel = 31;

void validateKernelSize(int k) {
  if (k < 3) throw ImgException('Kernel deve ter tamanho >= 3.');
  if (k.isEven) throw ImgException('Kernel deve ter tamanho ímpar (3, 5, 7...).');
  if (k > kMaxKernel) throw ImgException('Kernel máximo permitido: $kMaxKernel.');
}

int reflectIndex(int i, int n) {
  if (n == 1) return 0;
  while (i < 0 || i >= n) {
    if (i < 0) i = -i;
    if (i >= n) i = 2 * (n - 1) - i;
  }
  return i;
}

/// Kernel 1D da média: k pesos iguais a 1/k.
List<double> meanKernel1D(int k) {
  validateKernelSize(k);
  return List<double>.filled(k, 1.0 / k);
}

/// Kernel 1D gaussiano: w(i) = exp(-i² / 2σ²), normalizado (soma = 1).
List<double> gaussianKernel1D(int k, double sigma) {
  validateKernelSize(k);
  if (!sigma.isFinite || sigma <= 0) throw ImgException('σ deve ser > 0.');
  final half = k ~/ 2;
  final w = List<double>.generate(
      k, (i) => exp(-((i - half) * (i - half)) / (2 * sigma * sigma)));
  final s = w.reduce((a, b) => a + b);
  return w.map((v) => v / s).toList();
}

/// Kernel 2D (k x k) a partir do 1D: K(i, j) = a(i) * a(j).
/// Tanto a média quanto a gaussiana são separáveis.
List<double> kernel2DFrom1D(List<double> a) {
  final k = a.length;
  return [for (int i = 0; i < k; i++) for (int j = 0; j < k; j++) a[i] * a[j]];
}

Int32List _indexTable(int n, int k) {
  final half = k ~/ 2;
  final t = Int32List(n * k);
  for (int p = 0; p < n; p++) {
    for (int j = 0; j < k; j++) {
      t[p * k + j] = reflectIndex(p + j - half, n);
    }
  }
  return t;
}

/// CONVOLUÇÃO 2D GENÉRICA (k x k):
///   g(x, y) = Σ_i Σ_j K(i, j) · f(x - i, y - j)
/// O kernel é espelhado (convolução verdadeira; para kernels simétricos
/// coincide com a correlação). Custo: O(W · H · k²).
ImgData convolve2D(ImgData src, List<double> kernel, int k) {
  validateKernelSize(k);
  if (kernel.length != k * k) throw ImgException('Kernel incompatível com o tamanho.');
  final w = src.width, h = src.height, d = src.rgba;
  final xt = _indexTable(w, k), yt = _indexTable(h, k);
  final out = Uint8List(w * h * 4);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      double r = 0, g = 0, b = 0;
      for (int ky = 0; ky < k; ky++) {
        final yy = yt[y * k + ky];
        for (int kx = 0; kx < k; kx++) {
          final xx = xt[x * k + kx];
          final wgt = kernel[(k - 1 - ky) * k + (k - 1 - kx)]; // espelhado
          final idx = (yy * w + xx) * 4;
          r += wgt * d[idx];
          g += wgt * d[idx + 1];
          b += wgt * d[idx + 2];
        }
      }
      final o = (y * w + x) * 4;
      out[o] = clamp255(r);
      out[o + 1] = clamp255(g);
      out[o + 2] = clamp255(b);
      out[o + 3] = 255;
    }
  }
  return ImgData(w, h, out);
}

/// CONVOLUÇÃO SEPARÁVEL: aplica o kernel 1D nas linhas e depois nas colunas.
/// Resultado equivalente ao 2D (K = a·aᵀ) com custo O(W · H · k).
ImgData convolveSeparable(ImgData src, List<double> a) {
  final k = a.length;
  validateKernelSize(k);
  final w = src.width, h = src.height, d = src.rgba;
  final xt = _indexTable(w, k), yt = _indexTable(h, k);
  final tmp = Float32List(w * h * 3);

  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      double r = 0, g = 0, b = 0;
      for (int j = 0; j < k; j++) {
        final idx = (y * w + xt[x * k + j]) * 4;
        final wgt = a[k - 1 - j];
        r += wgt * d[idx];
        g += wgt * d[idx + 1];
        b += wgt * d[idx + 2];
      }
      final t = (y * w + x) * 3;
      tmp[t] = r;
      tmp[t + 1] = g;
      tmp[t + 2] = b;
    }
  }
  final out = Uint8List(w * h * 4);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      double r = 0, g = 0, b = 0;
      for (int j = 0; j < k; j++) {
        final t = (yt[y * k + j] * w + x) * 3;
        final wgt = a[k - 1 - j];
        r += wgt * tmp[t];
        g += wgt * tmp[t + 1];
        b += wgt * tmp[t + 2];
      }
      final o = (y * w + x) * 4;
      out[o] = clamp255(r);
      out[o + 1] = clamp255(g);
      out[o + 2] = clamp255(b);
      out[o + 3] = 255;
    }
  }
  return ImgData(w, h, out);
}

/// Filtro da média k x k (todos os pesos iguais a 1/k²).
ImgData meanFilter(ImgData src, int k, {bool separable = true}) {
  final a = meanKernel1D(k);
  return separable ? convolveSeparable(src, a) : convolve2D(src, kernel2DFrom1D(a), k);
}

/// Filtro Gaussiano k x k com desvio padrão sigma.
ImgData gaussianFilter(ImgData src, int k, double sigma, {bool separable = true}) {
  final a = gaussianKernel1D(k, sigma);
  return separable ? convolveSeparable(src, a) : convolve2D(src, kernel2DFrom1D(a), k);
}

/// Ruído gaussiano aditivo: g = f + N(0, σ²) em cada canal, saturado em [0, 255].
/// Amostras geradas com Box-Muller.
ImgData addGaussianNoise(ImgData src, double sigma, int seed) {
  if (!sigma.isFinite || sigma <= 0) throw ImgException('σ do ruído deve ser > 0.');
  final rng = Random(seed);
  double? spare;
  double gauss() {
    if (spare != null) {
      final s = spare!;
      spare = null;
      return s;
    }
    double u1;
    do {
      u1 = rng.nextDouble();
    } while (u1 <= 1e-12);
    final u2 = rng.nextDouble();
    final mag = sqrt(-2.0 * log(u1));
    spare = mag * sin(2 * pi * u2);
    return mag * cos(2 * pi * u2);
  }

  final out = Uint8List.fromList(src.rgba);
  for (int i = 0; i < out.length; i += 4) {
    out[i] = clamp255(out[i] + sigma * gauss());
    out[i + 1] = clamp255(out[i + 1] + sigma * gauss());
    out[i + 2] = clamp255(out[i + 2] + sigma * gauss());
  }
  return ImgData(src.width, src.height, out);
}
