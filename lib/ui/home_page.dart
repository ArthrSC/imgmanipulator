import 'dart:io' show File;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/img_data.dart';
import '../core/processing.dart';
import 'dialogs.dart';
import 'op_specs.dart';

/// Tela principal: controla o menu e o fluxo da aplicação.
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final AppController c = AppController();

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg, style: TextStyle(color: error ? cs.onError : null)),
        backgroundColor: error ? cs.error : null,
      ));
  }

  // ------------------------- carregar / salvar -------------------------

  Future<void> _load() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png'],
        withData: true,
      );
      if (res == null) return;
      final f = res.files.single;
      final ext = f.name.split('.').last.toLowerCase();
      if (!['jpg', 'jpeg', 'png'].contains(ext)) {
        _snack('Formato inválido: selecione um arquivo JPG ou PNG.', error: true);
        return;
      }
      Uint8List? bytes = f.bytes;
      if (bytes == null && f.path != null && !kIsWeb) {
        bytes = await _readFile(f.path!);
      }
      if (bytes == null) {
        _snack('Não foi possível ler o arquivo selecionado.', error: true);
        return;
      }
      await _finishLoad(f.name, bytes);
    } catch (e) {
      _snack('Erro ao carregar: $e', error: true);
    }
  }

  Future<void> _loadByPath() async {
    final path = (await askText(context, 'Abrir por caminho', 'Caminho do arquivo'))?.trim();
    if (path == null || path.isEmpty) return;
    final ext = path.split('.').last.toLowerCase();
    if (!['jpg', 'jpeg', 'png'].contains(ext)) {
      _snack('Formato inválido: use um arquivo .jpg, .jpeg ou .png.', error: true);
      return;
    }
    final bytes = await _readFile(path);
    if (bytes == null) {
      _snack('Arquivo inexistente ou ilegível: $path', error: true);
      return;
    }
    await _finishLoad(path.split(RegExp(r'[\\/]')).last, bytes);
  }

  Future<Uint8List?> _readFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  Future<void> _finishLoad(String name, Uint8List bytes) async {
    final err = await c.loadImage(name, bytes);
    if (err != null) {
      _snack(err, error: true);
    } else {
      _snack('Imagem carregada: $name (${c.imagemOriginal!.width}×${c.imagemOriginal!.height})');
    }
  }

  Future<void> _save() async {
    final png = c.currentPng;
    if (!c.hasImage || png == null) {
      _snack('Carregue uma imagem antes de salvar.', error: true);
      return;
    }
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Salvar imagem atual',
        fileName: 'imgmanipulator_resultado.png',
        type: FileType.custom,
        allowedExtensions: const ['png'],
        bytes: png, // Android / iOS / web gravam a partir dos bytes
      );
      final desktop = !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.windows ||
              defaultTargetPlatform == TargetPlatform.linux ||
              defaultTargetPlatform == TargetPlatform.macOS);
      if (desktop && path != null) {
        final out = path.toLowerCase().endsWith('.png') ? path : '$path.png';
        await File(out).writeAsBytes(png);
        _snack('Imagem salva em $out');
      } else if (path != null || kIsWeb) {
        _snack('Imagem salva.');
      }
    } catch (e) {
      _snack('Não foi possível salvar: $e', error: true);
    }
  }

  // ----------------------------- operações -----------------------------

  Future<void> _runOp(OpSpec spec) async {
    if (!c.hasImage) {
      _snack('Carregue uma imagem antes de aplicar operações.', error: true);
      return;
    }
    // 1) origem: original ou última processada (só pergunta se houver diferença)
    bool onOriginal = true;
    if (c.hasProcessed) {
      final choice = await askSource(context);
      if (choice == null) return;
      onOriginal = choice;
    }
    if (!mounted) return;

    // 2) histograma: apenas exibe
    if (spec.id == Ops.histogram) {
      final h = c.histogram(onOriginal: onOriginal);
      if (h != null) {
        await showHistogramDialog(context, h,
            'Histograma — ${onOriginal ? 'imagem original' : 'última imagem processada'}');
      }
      return;
    }

    // 3) parâmetros (validados no próprio diálogo)
    ParsedParams parsed;
    if (spec.fields.isEmpty) {
      try {
        parsed = spec.parse({});
      } on ImgException catch (e) {
        _snack(e.message, error: true);
        return;
      }
    } else {
      final r = await askParams(context, spec);
      if (r == null) return;
      parsed = r;
    }

    // 4) executa (em isolate), mostra resultado e registra no log
    final err = await c.apply(
      op: spec.id,
      label: spec.label,
      paramsText: parsed.description,
      params: parsed.params,
      onOriginal: onOriginal,
    );
    if (err != null) {
      _snack(err, error: true);
    } else {
      final e = c.log.last;
      _snack('${spec.label} aplicado em ${(e.elapsed.inMicroseconds / 1000).toStringAsFixed(1)} ms');
    }
  }

  // ------------------------------- UI -------------------------------

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('ImgManipulator'),
          actions: [
            IconButton(
                tooltip: 'Carregar imagem',
                icon: const Icon(Icons.folder_open),
                onPressed: c.busy ? null : _load),
            if (!kIsWeb)
              IconButton(
                  tooltip: 'Abrir por caminho',
                  icon: const Icon(Icons.text_fields),
                  onPressed: c.busy ? null : _loadByPath),
          ],
        ),
        body: Stack(children: [
          LayoutBuilder(builder: (context, box) {
            final wide = box.maxWidth >= 850;
            final viewer = _viewer();
            final menu = _menu();
            return wide
                ? Row(children: [
                    SizedBox(width: 340, child: menu),
                    const VerticalDivider(width: 1),
                    Expanded(child: viewer),
                  ])
                : Column(children: [
                    Expanded(flex: 5, child: viewer),
                    const Divider(height: 1),
                    Expanded(flex: 4, child: menu),
                  ]);
          }),
          if (c.busy)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black38,
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _viewer() {
    if (!c.hasImage) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.image_outlined, size: 72),
          const SizedBox(height: 12),
          const Text('Carregue uma imagem (JPG ou PNG) para começar.'),
          const SizedBox(height: 12),
          FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.folder_open),
              label: const Text('Carregar imagem')),
        ]),
      );
    }
    final img = c.displayedImage!;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Original')),
                ButtonSegment(value: false, label: Text('Atual')),
              ],
              selected: {c.showingOriginal},
              onSelectionChanged: (s) => c.showOriginal(s.first),
            ),
            Text('${img.width} × ${img.height} px'),
          ],
        ),
      ),
      Expanded(
        child: InteractiveViewer(
          maxScale: 8,
          child: Center(
            child: Image.memory(c.displayedPng!,
                fit: BoxFit.contain, gaplessPlayback: true),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(8),
        child: Text('Pipeline: ${c.pipeline.join(' → ')}',
            textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis),
      ),
    ]);
  }

  Widget _menu() {
    Widget section(String title, OpCategory cat) {
      final ops = allOps.where((o) => o.category == cat);
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
          child: Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final o in ops)
              FilledButton.tonalIcon(
                onPressed: c.busy ? null : () => _runOp(o),
                icon: Icon(o.icon, size: 18),
                label: Text(o.label),
              ),
          ]),
        ),
      ]);
    }

    return ListView(padding: const EdgeInsets.only(bottom: 16), children: [
      section('TRANSFORMAÇÕES PONTUAIS', OpCategory.pointwise),
      section('TRANSFORMAÇÕES GEOMÉTRICAS', OpCategory.geometric),
      section('TRANSFORMAÇÕES POR VIZINHANÇA', OpCategory.neighborhood),
      const Padding(
        padding: EdgeInsets.fromLTRB(12, 14, 12, 6),
        child: Text('CONTROLE DA APLICAÇÃO',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Wrap(spacing: 6, runSpacing: 6, children: [
          OutlinedButton.icon(
              onPressed: c.hasImage ? () => c.showOriginal(true) : null,
              icon: const Icon(Icons.image, size: 18),
              label: const Text('Mostrar imagem original')),
          OutlinedButton.icon(
              onPressed: c.hasImage ? () => c.showOriginal(false) : null,
              icon: const Icon(Icons.image_search, size: 18),
              label: const Text('Mostrar imagem atual')),
          OutlinedButton.icon(
              onPressed: c.busy ? null : _save,
              icon: const Icon(Icons.save, size: 18),
              label: const Text('Salvar imagem atual')),
          OutlinedButton.icon(
              onPressed: () => showLogDialog(context, c),
              icon: const Icon(Icons.list_alt, size: 18),
              label: const Text('Registro de operações')),
          OutlinedButton.icon(
              onPressed: c.hasImage ? c.reset : null,
              icon: const Icon(Icons.power_settings_new, size: 18),
              label: const Text('Encerrar')),
        ]),
      ),
    ]);
  }
}
