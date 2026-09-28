import 'package:flutter_test/flutter_test.dart';
import 'package:imgmanipulator/main.dart';

void main() {
  testWidgets('app inicia na tela de carregamento', (tester) async {
    await tester.pumpWidget(const ImgManipulatorApp());
    expect(find.text('ImgManipulator'), findsOneWidget);
    expect(find.text('Carregar imagem'), findsWidgets);
  });
}
