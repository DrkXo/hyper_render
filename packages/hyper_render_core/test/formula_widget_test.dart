import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyper_render_core/hyper_render_core.dart';

/// FormulaWidget: the dependency-free LaTeX fallback (Unicode rendering).
void main() {
  Future<String> render(WidgetTester tester, String latex) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: FormulaWidget(formula: latex)),
    ));
    return tester.widget<Text>(find.byType(Text)).data!;
  }

  testWidgets('Greek letters, upper and lower case', (tester) async {
    expect(await render(tester, r'\alpha + \beta = \Omega'), 'α + β = Ω');
    expect(await render(tester, r'\theta \eta \zeta'), 'θ η ζ');
  });

  testWidgets('a command is not eaten by a shorter prefix', (tester) async {
    expect(await render(tester, r'\infty'), '∞');
    expect(await render(tester, r'x \in A'), 'x ∈ A');
    expect(await render(tester, r'\int f'), '∫ f');
    expect(await render(tester, r'a \leq b \neq c'), 'a ≤ b ≠ c');
    expect(await render(tester, r'A \Leftrightarrow B'), 'A ⇔ B');
  });

  testWidgets('fractions, roots, super- and subscripts, braces',
      (tester) async {
    expect(await render(tester, r'\frac{a}{b}'), 'a/b');
    expect(await render(tester, r'\sqrt{x}'), '√(x)');
    expect(await render(tester, r'x^2 + y_1'), 'x² + y₁');
    expect(await render(tester, r'{e}^{n}'), 'eⁿ');
    expect(await render(tester, r'x^{2} + a_{i}'), 'x² + aᵢ');
  });

  testWidgets('customBuilder replaces the fallback', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: FormulaWidget(
        formula: 'E=mc^2',
        customBuilder: (context, f) => Text('custom:$f'),
      ),
    ));
    expect(find.text('custom:E=mc^2'), findsOneWidget);
  });

  testWidgets('explicit style is applied', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: FormulaWidget(formula: 'x', style: TextStyle(fontSize: 31)),
    ));
    expect(tester.widget<Text>(find.byType(Text)).style!.fontSize, 31);
  });

  test('FormulaParser reads Quill Delta formula embeds', () {
    final embed = <String, dynamic>{'formula': r'\pi r^2'};
    expect(embed.isFormula, isTrue);
    expect(embed.formulaString, r'\pi r^2');
    expect(embed.formulaInfo!.formula, r'\pi r^2');
    expect(embed.formulaInfo!.displayMode, isFalse);
    final notFormula = <String, dynamic>{'image': 'a.png'};
    expect(notFormula.isFormula, isFalse);
    expect(notFormula.formulaInfo, isNull);
  });
}
