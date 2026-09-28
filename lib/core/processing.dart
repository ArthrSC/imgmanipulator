import 'dart:typed_data';
import 'package:image/image.dart' as img;

import '../ops/geometric_ops.dart';
import '../ops/neighborhood_ops.dart';
import '../ops/point_ops.dart';
import 'img_data.dart';

/// Máximo lado da imagem ao carregar (imagens maiores são reduzidas para
/// manter a aplicação fluida). Use 0 para desativar.
const int kMaxLoadSide = 2000;

/// Identificadores das operações.
abstract class Ops {
  static const grayscale = 'grayscale';
  static const brightness = 'brightness';
  static const contrast = 'contrast';
  static const negative = 'negative';
  static const histogram = 'histogram';
  static const stretch = 'stretch';
  static const equalize = 'equalize';
  static const rotate = 'rotate';
  static const translate = 'translate';
  static const flip = 'flip';
  static const resize = 'resize';
  static const mean = 'mean';
  static const gaussian = 'gaussian';
  static const noise = 'noise';
}

/// Mensagens enviadas ao isolate (só contêm dados simples => "sendable").
class ProcessRequest {
  final String op;
  final ImgData input;
  final Map<String, num> params;
  ProcessRequest(this.op, this.input, this.params);
}

class ProcessResult {
  final ImgData? image;
  final Uint8List? png;
  final int elapsedMicros; // tempo apenas da operação (sem codificar PNG)
  final String? error;
  ProcessResult({this.image, this.png, this.elapsedMicros = 0, this.error});
}

/// Executa uma operação (rodada via compute(), fora da thread da UI).
ProcessResult runProcess(ProcessRequest r) {
  try {
    final sw = Stopwatch()..start();
    final p = r.params;
    final ImgData out;
    switch (r.op) {
      case Ops.grayscale:
        out = toGrayscale(r.input);
      case Ops.brightness:
        out = adjustBrightness(r.input, p['delta']!.toInt());
      case Ops.contrast:
        out = adjustContrast(r.input, p['factor']!.toDouble());
      case Ops.negative:
        out = negative(r.input);
      case Ops.stretch:
        out = contrastStretch(r.input);
      case Ops.equalize:
        out = equalizeHistogram(r.input);
      case Ops.rotate:
        out = rotate(r.input, p['angle']!.toDouble());
      case Ops.translate:
        out = translate(r.input, p['dx']!.toInt(), p['dy']!.toInt());
      case Ops.flip:
        out = flip(r.input, horizontal: p['dir'] == 1);
      case Ops.resize:
        out = resize(r.input, p['w']!.toInt(), p['h']!.toInt());
      case Ops.mean:
        out = meanFilter(r.input, p['k']!.toInt(), separable: p['sep'] == 1);
      case Ops.gaussian:
        out = gaussianFilter(r.input, p['k']!.toInt(), p['sigma']!.toDouble(),
            separable: p['sep'] == 1);
      case Ops.noise:
        out = addGaussianNoise(r.input, p['sigma']!.toDouble(), p['seed']!.toInt());
      default:
        throw ImgException('Operação desconhecida: ${r.op}');
    }
    sw.stop();
    return ProcessResult(
        image: out, png: encodePng(out), elapsedMicros: sw.elapsedMicroseconds);
  } on ImgException catch (e) {
    return ProcessResult(error: e.message);
  } catch (e) {
    return ProcessResult(error: 'Falha ao processar: $e');
  }
}

/// Decodifica JPG/PNG (valida assinatura do arquivo) -> ImgData + PNG de exibição.
ProcessResult decodeImageBytes(Uint8List bytes) {
  try {
    final isPng = bytes.length > 8 &&
        bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47;
    final isJpg = bytes.length > 3 &&
        bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;
    if (!isPng && !isJpg) {
      return ProcessResult(error: 'Formato inválido: use um arquivo JPG ou PNG.');
    }
    var im = img.decodeImage(bytes);
    if (im == null) {
      return ProcessResult(error: 'Não foi possível decodificar a imagem (arquivo corrompido?).');
    }
    im = img.bakeOrientation(im);
    im = im.convert(format: img.Format.uint8, numChannels: 4);
    final raw = Uint8List.fromList(im.getBytes(order: img.ChannelOrder.rgba));
    // Composição sobre fundo branco (remove transparência).
    for (int i = 0; i < raw.length; i += 4) {
      final a = raw[i + 3];
      if (a != 255) {
        for (int c = 0; c < 3; c++) {
          raw[i + c] = clamp255((raw[i + c] * a + 255 * (255 - a)) / 255);
        }
        raw[i + 3] = 255;
      }
    }
    var data = ImgData(im.width, im.height, raw);
    final longest = data.width > data.height ? data.width : data.height;
    if (kMaxLoadSide > 0 && longest > kMaxLoadSide) {
      final f = kMaxLoadSide / longest;
      data = resize(data, (data.width * f).round().clamp(1, kMaxLoadSide).toInt(),
          (data.height * f).round().clamp(1, kMaxLoadSide).toInt());
    }
    return ProcessResult(image: data, png: encodePng(data));
  } catch (e) {
    return ProcessResult(error: 'Erro ao abrir a imagem: $e');
  }
}

Uint8List encodePng(ImgData d) {
  final im = img.Image.fromBytes(
    width: d.width,
    height: d.height,
    bytes: d.rgba.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return Uint8List.fromList(img.encodePng(im, level: 1));
}
