import 'package:flutter/material.dart';

import '../core/img_data.dart';
import '../core/processing.dart';
import '../ops/neighborhood_ops.dart';

enum OpCategory { pointwise, geometric, neighborhood }

enum FieldKind { text, boolean, choice }

class ParamField {
  final String key;
  final String label;
  final FieldKind kind;
  final String initial;
  final String? hint;
  final List<String> options; // para choice
  const ParamField(this.key, this.label,
      {this.kind = FieldKind.text,
      this.initial = '',
      this.hint,
      this.options = const []});
}

class ParsedParams {
  final Map<String, num> params;
  final String description;
  ParsedParams(this.params, this.description);
}

class OpSpec {
  final String id;
  final String label;
  final OpCategory category;
  final IconData icon;
  final List<ParamField> fields;
  final ParsedParams Function(Map<String, String> v) parse;
  const OpSpec(this.id, this.label, this.category, this.icon,
      {this.fields = const [], required this.parse});
}

// ---------- utilitários de leitura / validação ----------

double _dbl(Map<String, String> v, String key, String name) {
  final s = (v[key] ?? '').trim().replaceAll(',', '.');
  final d = double.tryParse(s);
  if (d == null || !d.isFinite) {
    throw ImgException('Valor inválido para "$name": digite um número.');
  }
  return d;
}

int _int(Map<String, String> v, String key, String name) {
  final s = (v[key] ?? '').trim();
  final i = int.tryParse(s);
  if (i == null) {
    throw ImgException('Valor inválido para "$name": digite um número inteiro.');
  }
  return i;
}

ParsedParams _none() => ParsedParams({}, '—');

const _sepField = ParamField('sep', 'Convolução separável (mais rápida)',
    kind: FieldKind.boolean, initial: '1');

/// Definição de todas as operações do menu.
final List<OpSpec> allOps = [
  // ------------------------- PONTUAIS -------------------------
  OpSpec(Ops.grayscale, 'Escala de cinza', OpCategory.pointwise, Icons.filter_b_and_w,
      parse: (_) => _none()),
  OpSpec(Ops.brightness, 'Ajuste de brilho', OpCategory.pointwise, Icons.brightness_6,
      fields: const [
        ParamField('delta', 'Ajuste de brilho', initial: '+30', hint: 'ex.: +30 ou -40')
      ], parse: (v) {
    final d = _int(v, 'delta', 'Ajuste de brilho');
    if (d < -255 || d > 255) {
      throw ImgException('O ajuste de brilho deve estar entre -255 e +255.');
    }
    return ParsedParams({'delta': d}, 'ajuste = ${d >= 0 ? '+' : ''}$d');
  }),
  OpSpec(Ops.contrast, 'Ajuste de contraste', OpCategory.pointwise, Icons.contrast,
      fields: const [
        ParamField('factor', 'Fator de contraste', initial: '1.5', hint: 'ex.: 1.5')
      ], parse: (v) {
    final f = _dbl(v, 'factor', 'Fator de contraste');
    if (f < 0 || f > 10) throw ImgException('O fator de contraste deve estar entre 0 e 10.');
    return ParsedParams({'factor': f}, 'fator = $f');
  }),
  OpSpec(Ops.negative, 'Negativo', OpCategory.pointwise, Icons.invert_colors,
      parse: (_) => _none()),
  OpSpec(Ops.histogram, 'Exibir histograma', OpCategory.pointwise, Icons.bar_chart,
      parse: (_) => _none()),
  OpSpec(Ops.stretch, 'Alongamento de contraste', OpCategory.pointwise, Icons.open_in_full,
      parse: (_) => _none()),
  OpSpec(Ops.equalize, 'Equalização de histograma', OpCategory.pointwise, Icons.equalizer,
      parse: (_) => _none()),

  // ------------------------ GEOMÉTRICAS ------------------------
  OpSpec(Ops.rotate, 'Rotação', OpCategory.geometric, Icons.rotate_right,
      fields: const [
        ParamField('angle', 'Ângulo de rotação (graus)',
            initial: '45', hint: 'positivo = anti-horário')
      ], parse: (v) {
    final a = _dbl(v, 'angle', 'Ângulo');
    if (a.abs() > 36000) throw ImgException('Ângulo fora do intervalo permitido.');
    return ParsedParams({'angle': a}, 'ângulo = $a°');
  }),
  OpSpec(Ops.translate, 'Translação', OpCategory.geometric, Icons.open_with,
      fields: const [
        ParamField('dx', 'Deslocamento horizontal (px)', initial: '50'),
        ParamField('dy', 'Deslocamento vertical (px)', initial: '-20'),
      ], parse: (v) {
    final dx = _int(v, 'dx', 'Deslocamento horizontal');
    final dy = _int(v, 'dy', 'Deslocamento vertical');
    if (dx.abs() > 20000 || dy.abs() > 20000) {
      throw ImgException('Deslocamento fora do intervalo permitido.');
    }
    return ParsedParams({'dx': dx, 'dy': dy}, 'dx = $dx, dy = $dy');
  }),
  OpSpec(Ops.flip, 'Espelhamento', OpCategory.geometric, Icons.flip, fields: const [
    ParamField('dir', 'Direção',
        kind: FieldKind.choice, options: ['Espelhamento horizontal', 'Espelhamento vertical'])
  ], parse: (v) {
    final horizontal = (v['dir'] ?? '').contains('horizontal');
    return ParsedParams({'dir': horizontal ? 1 : 2}, horizontal ? 'horizontal' : 'vertical');
  }),
  OpSpec(Ops.resize, 'Redimensionamento', OpCategory.geometric, Icons.photo_size_select_large,
      fields: const [
        ParamField('w', 'Nova largura (px)', initial: '400'),
        ParamField('h', 'Nova altura (px)', initial: '300'),
      ], parse: (v) {
    final w = _int(v, 'w', 'Largura');
    final h = _int(v, 'h', 'Altura');
    if (w < 1 || h < 1) throw ImgException('Largura e altura devem ser >= 1.');
    if (w > 8000 || h > 8000) throw ImgException('Dimensão máxima: 8000 px.');
    return ParsedParams({'w': w, 'h': h}, '${w}×$h');
  }),

  // ------------------------ VIZINHANÇA ------------------------
  OpSpec(Ops.mean, 'Filtro da média', OpCategory.neighborhood, Icons.blur_linear,
      fields: const [
        ParamField('k', 'Tamanho do kernel (3, 5, 7...)', initial: '3'),
        _sepField,
      ], parse: (v) {
    final k = _int(v, 'k', 'Tamanho do kernel');
    validateKernelSize(k);
    final sep = v['sep'] == '1';
    return ParsedParams({'k': k, 'sep': sep ? 1 : 0},
        'kernel ${k}×$k${sep ? ' (separável)' : ' (2D)'}, bordas: reflexão');
  }),
  OpSpec(Ops.gaussian, 'Filtro Gaussiano', OpCategory.neighborhood, Icons.blur_on,
      fields: const [
        ParamField('k', 'Tamanho do kernel (ímpar)', initial: '5'),
        ParamField('sigma', 'Sigma (σ)', initial: '1.5'),
        _sepField,
      ], parse: (v) {
    final k = _int(v, 'k', 'Tamanho do kernel');
    validateKernelSize(k);
    final s = _dbl(v, 'sigma', 'Sigma');
    if (s <= 0) throw ImgException('σ deve ser maior que zero.');
    if (s > 100) throw ImgException('σ máximo permitido: 100.');
    final sep = v['sep'] == '1';
    return ParsedParams({'k': k, 'sigma': s, 'sep': sep ? 1 : 0},
        'kernel ${k}×$k, σ = $s${sep ? ' (separável)' : ' (2D)'}, bordas: reflexão');
  }),
  OpSpec(Ops.noise, 'Adicionar ruído', OpCategory.neighborhood, Icons.grain, fields: const [
    ParamField('sigma', 'Desvio padrão do ruído gaussiano', initial: '25')
  ], parse: (v) {
    final s = _dbl(v, 'sigma', 'Desvio padrão');
    if (s <= 0) throw ImgException('O desvio padrão do ruído deve ser > 0.');
    if (s > 255) throw ImgException('Desvio padrão máximo: 255.');
    final seed = DateTime.now().microsecondsSinceEpoch & 0x7fffffff;
    return ParsedParams({'sigma': s, 'seed': seed}, 'ruído gaussiano, σ = $s');
  }),
];

OpSpec specById(String id) => allOps.firstWhere((o) => o.id == id);
