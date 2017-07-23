import 'dart:io';
import 'package:analyzer/dart/ast/standard_ast_factory.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/src/dart/ast/token.dart';
import 'package:analyzer/analyzer.dart';
import 'package:tuple/tuple.dart';
import '../analyze_a_file/analyze_a_file.dart';

final File exampleFile =
    new File.fromUri(Platform.script.resolve('example.dart'));

main() async {
  // Let's analyze our `example.dart` file.
  var compilationUnit = await analyzeFile(exampleFile);

  var libraryName = compilationUnit.element.library.name;
  var originalText = await exampleFile.readAsString();
  print('Original source of library $libraryName:\n');
  print(originalText);

  // Traverse the compilation unit with our visitor class.
  var visitor = new ExampleVisitor();
  compilationUnit.accept(visitor);

  // Replace nodes with new ones...
  for (var pair in visitor.statementsToReplace) {
    // Let's manually create a 'print("Analyzed.")' statement.
    // We must use the astFactory, exported by `package:analyzer`.

    // Create an identifier. Text: `print`
    var $print = astFactory
        .simpleIdentifier(new StringToken(TokenType.IDENTIFIER, 'print', 0));

    // And a string literal. Text: `'Analyzed.'`
    var $stringLiteral = astFactory.simpleStringLiteral(
        new StringToken(TokenType.STRING, "'Analyzed.'", 0), 'Analyzed.');

    // Parenthesis tokens.
    var $lparen = new StringToken(TokenType.OPEN_PAREN, '(', 0);
    var $rparen = new StringToken(TokenType.CLOSE_PAREN, ')', 0);

    // Put it all together
    var $methodInvocation = astFactory.functionExpressionInvocation($print,
        null, astFactory.argumentList($lparen, [$stringLiteral], $rparen));

    // Now, make a `NodeReplacer` to swap out the expression for the `print` invocation.
    var replacer = new NodeReplacer(pair.item2, $methodInvocation);

    // Don't forget to run it.
    pair.item1.accept(replacer);
  }

  var newText = compilationUnit.toSource();

  print('Transformed source:\n');
  print(newText);
}

/// A visitor that can be used to replace every expression statement in any function it finds.
class ExampleVisitor extends GeneralizingAstVisitor {
  /// Collect a list of nodes we want to replace.
  final List<Tuple2<Statement, ExpressionStatement>> statementsToReplace = [];

  @override
  visitBlockFunctionBody(BlockFunctionBody node) {
    for (var statement in node.block.statements) {
      if (statement is ExpressionStatement) {
        statementsToReplace.add(new Tuple2(statement, statement.expression));
      }
    }
  }
}
