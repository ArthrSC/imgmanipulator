import 'dart:typed_data';
import 'package:flutter/foundation.dart';

import '../ops/histogram.dart';
import 'img_data.dart';
import 'processing.dart';

/// Registro de uma operação executada.
class LogEntry {
  final int index;
  final String operation;
  final String params;
  final String source; // "Imagem original" | "Última imagem processada"
  final Duration elapsed;
  final String outputSize;
  final DateTime time;
  LogEntry(this.index, this.operation, this.params, this.source, this.elapsed,
      this.outputSize)
      : time = DateTime.now();
}

/// Estado e fluxo da aplicação: mantém imagem_original e imagem_atual.
class AppController extends ChangeNotifier {
  ImgData? imagemOriginal;
  ImgData? imagemAtual;
  Uint8List? _originalPng;
  Uint8List? _atualPng;
  String? fileName;

  final List<LogEntry> log = [];
  List<String> pipeline = [];

  bool busy = false;
  bool showingOriginal = false;

  bool get hasImage => imagemOriginal != null;

  /// Já existe alguma imagem processada (diferente da original)?
  bool get hasProcessed => pipeline.length > 1;

  Uint8List? get displayedPng => showingOriginal ? _originalPng : _atualPng;
  ImgData? get displayedImage => showingOriginal ? imagemOriginal : imagemAtual;
  Uint8List? get currentPng => _atualPng;

  /// Carrega uma imagem. Retorna mensagem de erro (ou null se OK).
  Future<String?> loadImage(String name, Uint8List bytes) async {
    _setBusy(true);
    final res = await compute(decodeImageBytes, bytes);
    _setBusy(false);
    if (res.error != null) return res.error;
    imagemOriginal = res.image;
    imagemAtual = res.image;
    _originalPng = res.png;
    _atualPng = res.png;
    fileName = name;
    log.clear();
    pipeline = ['Original'];
    showingOriginal = false;
    notifyListeners();
    return null;
  }

  /// "Encerrar": descarta a sessão e volta à tela inicial.
  void reset() {
    imagemOriginal = imagemAtual = null;
    _originalPng = _atualPng = null;
    fileName = null;
    log.clear();
    pipeline = [];
    showingOriginal = false;
    notifyListeners();
  }

  void showOriginal(bool v) {
    showingOriginal = v;
    notifyListeners();
  }

  /// Aplica a operação [op] sobre a imagem original ou sobre a última
  /// imagem processada, registra no log e atualiza a imagem atual.
  Future<String?> apply({
    required String op,
    required String label,
    required String paramsText,
    required Map<String, num> params,
    required bool onOriginal,
  }) async {
    if (!hasImage) return 'Carregue uma imagem antes de aplicar operações.';
    final input = onOriginal ? imagemOriginal! : imagemAtual!;
    _setBusy(true);
    final res = await compute(runProcess, ProcessRequest(op, input, params));
    _setBusy(false);
    if (res.error != null) return res.error;

    imagemAtual = res.image;
    _atualPng = res.png;
    showingOriginal = false;
    if (onOriginal) pipeline = ['Original'];
    pipeline = [...pipeline, label];
    log.add(LogEntry(
      log.length + 1,
      label,
      paramsText,
      onOriginal ? 'Imagem original' : 'Última imagem processada',
      Duration(microseconds: res.elapsedMicros),
      '${res.image!.width}×${res.image!.height}',
    ));
    notifyListeners();
    return null;
  }

  /// Histograma da imagem escolhida (não altera imagem_atual, mas é registrado).
  HistogramData? histogram({required bool onOriginal}) {
    if (!hasImage) return null;
    final src = onOriginal ? imagemOriginal! : imagemAtual!;
    final sw = Stopwatch()..start();
    final h = computeHistogram(src);
    sw.stop();
    log.add(LogEntry(
      log.length + 1,
      'Histograma',
      '—',
      onOriginal ? 'Imagem original' : 'Última imagem processada',
      sw.elapsed,
      '${src.width}×${src.height}',
    ));
    notifyListeners();
    return h;
  }

  void _setBusy(bool v) {
    busy = v;
    notifyListeners();
  }
}
