import 'package:flutter/material.dart';

import '../core/app_controller.dart';
import '../core/img_data.dart';
import '../ops/histogram.dart';
import 'op_specs.dart';

/// Pergunta em qual imagem a próxima operação será aplicada.
/// Retorna true = original, false = última processada, null = cancelado.
Future<bool?> askSource(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Aplicar a próxima operação em:'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('1 - Imagem original'),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('2 - Última imagem processada'),
        ),
      ],
    ),
  );
}

/// Diálogo genérico de parâmetros. A validação (parse) roda antes de fechar;
/// em caso de erro a mensagem aparece no próprio diálogo.
Future<ParsedParams?> askParams(BuildContext context, OpSpec spec) {
  return showDialog<ParsedParams>(
    context: context,
    builder: (ctx) => _ParamDialog(spec: spec),
  );
}

class _ParamDialog extends StatefulWidget {
  final OpSpec spec;
  const _ParamDialog({required this.spec});
  @override
  State<_ParamDialog> createState() => _ParamDialogState();
}

class _ParamDialogState extends State<_ParamDialog> {
  late final Map<String, TextEditingController> _ctrls;
  late final Map<String, String> _values; // boolean / choice
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrls = {};
    _values = {};
    for (final f in widget.spec.fields) {
      switch (f.kind) {
        case FieldKind.text:
          _ctrls[f.key] = TextEditingController(text: f.initial);
        case FieldKind.boolean:
          _values[f.key] = f.initial.isEmpty ? '0' : f.initial;
        case FieldKind.choice:
          _values[f.key] = f.options.first;
      }
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final v = <String, String>{
      for (final e in _ctrls.entries) e.key: e.value.text,
      ..._values,
    };
    try {
      final parsed = widget.spec.parse(v);
      Navigator.pop(context, parsed);
    } on ImgException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.spec.label),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final f in widget.spec.fields) ...[
              if (f.kind == FieldKind.text)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: TextField(
                    controller: _ctrls[f.key],
                    decoration: InputDecoration(
                        labelText: f.label,
                        hintText: f.hint,
                        border: const OutlineInputBorder()),
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true, signed: true),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
              if (f.kind == FieldKind.boolean)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(f.label),
                  value: _values[f.key] == '1',
                  onChanged: (b) => setState(() => _values[f.key] = b ? '1' : '0'),
                ),
              if (f.kind == FieldKind.choice)
                Column(
                  children: [
                    for (int i = 0; i < f.options.length; i++)
                      // ignore: deprecated_member_use
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        title: Text('${i + 1} - ${f.options[i]}'),
                        value: f.options[i],
                        groupValue: _values[f.key],
                        onChanged: (s) => setState(() => _values[f.key] = s!),
                      ),
                  ],
                ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _submit, child: const Text('Aplicar')),
      ],
    );
  }
}

/// Diálogo com um único campo de texto (usado para "abrir por caminho").
Future<String?> askText(BuildContext context, String title, String label) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        onSubmitted: (s) => Navigator.pop(ctx, s),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Abrir')),
      ],
    ),
  );
}

/// Mostra o histograma (gráfico de barras).
Future<void> showHistogramDialog(
    BuildContext context, HistogramData h, String title) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 2,
              child: Container(
                color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                child: CustomPaint(painter: _HistPainter(h)),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [Text('0'), Text('intensidade'), Text('255')],
            ),
            const SizedBox(height: 8),
            Text(h.grayscale
                ? 'Imagem em escala de cinza — histograma das intensidades.'
                : 'Imagem colorida — canais R (vermelho), G (verde) e B (azul).'),
            Text('Pixels: ${h.pixels}   |   Intensidade média: ${h.meanIntensity.toStringAsFixed(1)}'),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar'))],
    ),
  );
}

class _HistPainter extends CustomPainter {
  final HistogramData h;
  _HistPainter(this.h);

  @override
  void paint(Canvas canvas, Size size) {
    final maxV = h.maxCount.toDouble();
    void draw(List<int> data, Color color) {
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      final bw = size.width / 256;
      for (int i = 0; i < 256; i++) {
        final bh = data[i] / maxV * size.height;
        canvas.drawRect(
            Rect.fromLTWH(i * bw, size.height - bh, bw + 0.5, bh), paint);
      }
    }

    if (h.grayscale) {
      draw(h.lum, Colors.grey.shade700);
    } else {
      draw(h.r, Colors.red.withAlpha(115));
      draw(h.g, Colors.green.withAlpha(115));
      draw(h.b, Colors.blue.withAlpha(115));
    }
  }

  @override
  bool shouldRepaint(covariant _HistPainter old) => old.h != h;
}

/// Registro das operações executadas.
Future<void> showLogDialog(BuildContext context, AppController c) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Registro de operações'),
      content: SizedBox(
        width: 560,
        height: 420,
        child: c.log.isEmpty
            ? const Center(child: Text('Nenhuma operação executada ainda.'))
            : ListView.separated(
                itemCount: c.log.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final e = c.log[i];
                  final ms = (e.elapsed.inMicroseconds / 1000).toStringAsFixed(1);
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(radius: 14, child: Text('${e.index}')),
                    title: Text('${e.operation}  —  ${e.params}'),
                    subtitle: Text(
                        'Origem: ${e.source} • Saída: ${e.outputSize} • Tempo: $ms ms'),
                  );
                },
              ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar'))],
    ),
  );
}
