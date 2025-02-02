// Copyright 2017 Google Inc. Use of this source code is governed by an
// MIT-style license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

@TestOn('node')
@Tags(['node'])

import 'dart:convert';
import 'dart:js';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:sass/src/node/utils.dart';

import 'ensure_npm_package.dart';
import 'hybrid.dart';
import 'legacy_node_api/api.dart';
import 'legacy_node_api/intercept_stdout.dart';
import 'legacy_node_api/utils.dart';
import 'utils.dart';

void main() {
  setUpAll(ensureNpmPackage);
  useSandbox();

  late String sassPath;

  setUp(() async {
    sassPath = p.join(sandbox, 'test.scss');
    await writeTextFile(sassPath, 'a {b: c}');
  });

  group("renderSync()", () {
    test("renders a file", () {
      expect(renderSync(RenderOptions(file: sassPath)),
          equalsIgnoringWhitespace('a { b: c; }'));
    });

    test("renders a file from a relative path", () {
      runTestInSandbox();
      expect(renderSync(RenderOptions(file: 'test.scss')),
          equalsIgnoringWhitespace('a { b: c; }'));
    });

    test("renders a file with the indented syntax", () async {
      var indentedPath = p.join(sandbox, 'test.sass');
      await writeTextFile(indentedPath, 'a\n  b: c');
      expect(renderSync(RenderOptions(file: indentedPath)),
          equalsIgnoringWhitespace('a { b: c; }'));
    });

    test("supports relative imports for a file", () async {
      var importerPath = p.join(sandbox, 'importer.scss');
      await writeTextFile(importerPath, '@import "test"');
      expect(renderSync(RenderOptions(file: importerPath)),
          equalsIgnoringWhitespace('a { b: c; }'));
    });

    // Regression test for #284
    test("supports relative imports for a file from a relative path", () async {
      await createDirectory(p.join(sandbox, 'subdir'));

      var importerPath = p.join(sandbox, 'subdir/importer.scss');
      await writeTextFile(importerPath, '@import "../test"');

      runTestInSandbox();
      expect(renderSync(RenderOptions(file: 'subdir/importer.scss')),
          equalsIgnoringWhitespace('a { b: c; }'));
    });

    test("supports absolute path imports", () async {
      expect(
          renderSync(RenderOptions(
              // Node Sass parses imports as paths, not as URLs, so the absolute
              // path should work here.
              data: '@import "${sassPath.replaceAll('\\', '\\\\')}"')),
          equalsIgnoringWhitespace('a { b: c; }'));
    });

    test("supports import-only files", () async {
      await writeTextFile(p.join(sandbox, 'foo.scss'), 'a {b: regular}');
      await writeTextFile(
          p.join(sandbox, 'foo.import.scss'), 'a {b: import-only}');

      runTestInSandbox();
      expect(renderSync(RenderOptions(data: "@import 'foo'")),
          equalsIgnoringWhitespace('a { b: import-only; }'));
    });

    test("supports mixed `@use` and `@import`", () async {
      await writeTextFile(p.join(sandbox, 'foo.scss'), 'a {b: regular}');
      await writeTextFile(
          p.join(sandbox, 'foo.import.scss'), 'a {b: import-only}');

      runTestInSandbox();
      expect(renderSync(RenderOptions(data: "@use 'foo'; @import 'foo';")),
          equalsIgnoringWhitespace('a { b: regular; } a { b: import-only; }'));
    });

    test("renders a string", () {
      expect(renderSync(RenderOptions(data: "a {b: c}")),
          equalsIgnoringWhitespace('a { b: c; }'));
    });

    test("one of data and file must be set", () {
      var error = renderSyncError(RenderOptions());
      expect(error.toString(),
          contains('Either options.data or options.file must be set.'));
    });

    test("supports load paths", () {
      expect(
          renderSync(
              RenderOptions(data: "@import 'test'", includePaths: [sandbox])),
          equalsIgnoringWhitespace('a { b: c; }'));
    });

    test("supports SASS_PATH", () async {
      await createDirectory(p.join(sandbox, 'dir1'));
      await createDirectory(p.join(sandbox, 'dir2'));
      await writeTextFile(p.join(sandbox, 'dir1', 'test1.scss'), 'a {b: c}');
      await writeTextFile(p.join(sandbox, 'dir2', 'test2.scss'), 'x {y: z}');

      withSassPath([p.join(sandbox, 'dir1'), p.join(sandbox, 'dir2')], () {
        expect(renderSync(RenderOptions(data: """
              @import 'test1';
              @import 'test2';
            """)), equalsIgnoringWhitespace('a { b: c; } x { y: z; }'));
      });
    });

    test("load path takes precedence over SASS_PATH", () async {
      await createDirectory(p.join(sandbox, 'dir1'));
      await createDirectory(p.join(sandbox, 'dir2'));
      await writeTextFile(p.join(sandbox, 'dir1', 'test.scss'), 'a {b: c}');
      await writeTextFile(p.join(sandbox, 'dir2', 'test.scss'), 'x {y: z}');

      setEnvironmentVariable("SASS_PATH", p.join(sandbox, 'dir1'));

      try {
        expect(
            renderSync(RenderOptions(
                data: "@import 'test'",
                includePaths: [p.join(sandbox, 'dir2')])),
            equalsIgnoringWhitespace('x { y: z; }'));
      } finally {
        setEnvironmentVariable("SASS_PATH", null);
      }
    });

    // Regression test for #314
    test(
        "a file imported through a relative load path supports relative "
        "imports", () async {
      var subDir = p.join(sandbox, 'sub');
      await createDirectory(subDir);
      await writeTextFile(p.join(subDir, '_test.scss'), '@import "other"');

      await writeTextFile(p.join(subDir, '_other.scss'), 'x {y: z}');

      expect(
          renderSync(RenderOptions(
              data: "@import 'sub/test'", includePaths: [p.relative(sandbox)])),
          equalsIgnoringWhitespace('x { y: z; }'));
    });

    test("can render the indented syntax", () {
      expect(renderSync(RenderOptions(data: "a\n  b: c", indentedSyntax: true)),
          equalsIgnoringWhitespace('a { b: c; }'));
    });

    test("the indented syntax flag takes precedence over the file extension",
        () async {
      var scssPath = p.join(sandbox, 'test.scss');
      await writeTextFile(scssPath, 'a\n  b: c');
      expect(renderSync(RenderOptions(file: scssPath, indentedSyntax: true)),
          equalsIgnoringWhitespace('a { b: c; }'));
    });

    test("supports the expanded output style", () {
      expect(renderSync(RenderOptions(file: sassPath, outputStyle: 'expanded')),
          equals('a {\n  b: c;\n}'));
    });

    test("doesn't support other output styles", () {
      var error =
          renderSyncError(RenderOptions(file: sassPath, outputStyle: 'nested'));
      expect(error.toString(), contains('Unsupported output style "nested".'));
    });

    test("allows tab indentation", () {
      expect(renderSync(RenderOptions(file: sassPath, indentType: 'tab')),
          equals('''
a {
\t\tb: c;
}'''));
    });

    test("allows unknown indentation names", () {
      expect(renderSync(RenderOptions(file: sassPath, indentType: 'asdf')),
          equals('''
a {
  b: c;
}'''));
    });

    group("unicode", () {
      test("adds @charset by default", () async {
        var unicodePath = p.join(sandbox, 'test.scss');
        await writeTextFile(unicodePath, 'p { content: "é"; } ');
        expect(renderSync(RenderOptions(file: unicodePath)),
            equalsIgnoringWhitespace('@charset "UTF-8"; p { content: "é"; } '));
      });

      test("allows charset=false to hide @charset", () async {
        var unicodePath = p.join(sandbox, 'test.scss');
        await writeTextFile(unicodePath, 'p { content: "é"; } ');
        expect(renderSync(RenderOptions(file: unicodePath, charset: false)),
            equalsIgnoringWhitespace('p { content: "é"; } '));
      });
    });

    group("linefeed allows", () {
      test("cr", () {
        expect(renderSync(RenderOptions(file: sassPath, linefeed: 'cr')),
            equals('a {\r  b: c;\r}'));
      });

      test("crlf", () {
        expect(renderSync(RenderOptions(file: sassPath, linefeed: 'crlf')),
            equals('a {\r\n  b: c;\r\n}'));
      });

      test("lfcr", () {
        expect(renderSync(RenderOptions(file: sassPath, linefeed: 'lfcr')),
            equals('a {\n\r  b: c;\n\r}'));
      });

      test("unknown names", () {
        expect(renderSync(RenderOptions(file: sassPath, linefeed: 'asdf')),
            equals('a {\n  b: c;\n}'));
      });
    });

    group("indentWidth allows", () {
      test("a number", () {
        expect(renderSync(RenderOptions(file: sassPath, indentWidth: 10)),
            equals('''
a {
          b: c;
}'''));
      });

      test("a string", () {
        expect(renderSync(RenderOptions(file: sassPath, indentWidth: '1')),
            equals('''
a {
 b: c;
}'''));
      });
    });

    test("emits warnings on stderr", () {
      expect(
          const LineSplitter().bind(interceptStderr()),
          emitsInOrder([
            "WARNING: aw beans",
            "    stdin 1:1  root stylesheet",
          ]));

      expect(renderSync(RenderOptions(data: "@warn 'aw beans'")), isEmpty);
    });

    test("emits debug messages on stderr", () {
      expect(const LineSplitter().bind(interceptStderr()),
          emits("stdin:1 DEBUG: what the heck"));

      expect(
          renderSync(RenderOptions(data: "@debug 'what the heck'")), isEmpty);
    });

    group("with quietDeps", () {
      group("in a relative load from the entrypoint", () {
        test("emits @warn", () async {
          await writeTextFile(p.join(sandbox, "test.scss"), "@use 'other'");
          await writeTextFile(p.join(sandbox, "_other.scss"), "@warn heck");

          expect(const LineSplitter().bind(interceptStderr()),
              emitsThrough(contains("heck")));

          renderSync(RenderOptions(
              file: p.join(sandbox, "test.scss"), quietDeps: true));
        });

        test("emits @debug", () async {
          await writeTextFile(p.join(sandbox, "test.scss"), "@use 'other'");
          await writeTextFile(p.join(sandbox, "_other.scss"), "@debug heck");

          expect(const LineSplitter().bind(interceptStderr()),
              emitsThrough(contains("heck")));

          renderSync(RenderOptions(
              file: p.join(sandbox, "test.scss"), quietDeps: true));
        });

        test("emits parser warnings", () async {
          await writeTextFile(p.join(sandbox, "test.scss"), "@use 'other'");
          await writeTextFile(p.join(sandbox, "_other.scss"), "a {b: c && d}");

          expect(const LineSplitter().bind(interceptStderr()),
              emitsThrough(contains("&&")));

          renderSync(RenderOptions(
              file: p.join(sandbox, "test.scss"), quietDeps: true));
        });

        test("emits runner warnings", () async {
          await writeTextFile(p.join(sandbox, "test.scss"), "@use 'other'");
          await writeTextFile(p.join(sandbox, "_other.scss"), "#{blue} {x: y}");

          expect(const LineSplitter().bind(interceptStderr()),
              emitsThrough(contains("blue")));

          renderSync(RenderOptions(
              file: p.join(sandbox, "test.scss"), quietDeps: true));
        });
      });

      group("in a load path load", () {
        test("emits @warn", () async {
          await writeTextFile(p.join(sandbox, "test.scss"), "@use 'other'");
          await createDirectory(p.join(sandbox, "dir"));
          await writeTextFile(
              p.join(sandbox, "dir", "_other.scss"), "@warn heck");

          expect(const LineSplitter().bind(interceptStderr()),
              emitsThrough(contains("heck")));

          renderSync(RenderOptions(
              file: p.join(sandbox, "test.scss"),
              includePaths: [p.join(sandbox, "dir")],
              quietDeps: true));
        });

        test("emits @debug", () async {
          await writeTextFile(p.join(sandbox, "test.scss"), "@use 'other'");
          await createDirectory(p.join(sandbox, "dir"));
          await writeTextFile(
              p.join(sandbox, "dir", "_other.scss"), "@debug heck");

          expect(const LineSplitter().bind(interceptStderr()),
              emitsThrough(contains("heck")));

          renderSync(RenderOptions(
              file: p.join(sandbox, "test.scss"),
              includePaths: [p.join(sandbox, "dir")],
              quietDeps: true));
        });

        test("doesn't emit parser warnings", () async {
          await writeTextFile(p.join(sandbox, "test.scss"), "@use 'other'");
          await createDirectory(p.join(sandbox, "dir"));
          await writeTextFile(
              p.join(sandbox, "dir", "_other.scss"), "a {b: c && d}");

          // No stderr should be printed at all.
          const LineSplitter()
              .bind(interceptStderr())
              .listen(expectAsync1((_) {}, count: 0));

          renderSync(RenderOptions(
              file: p.join(sandbox, "test.scss"),
              includePaths: [p.join(sandbox, "dir")],
              quietDeps: true));

          // Give stderr a chance to be piped through if it's going to be.
          await pumpEventQueue();
        });

        test("doesn't emit runner warnings", () async {
          await writeTextFile(p.join(sandbox, "test.scss"), "@use 'other'");
          await createDirectory(p.join(sandbox, "dir"));
          await writeTextFile(
              p.join(sandbox, "dir", "_other.scss"), "#{blue} {x: y}");

          // No stderr should be printed at all.
          const LineSplitter()
              .bind(interceptStderr())
              .listen(expectAsync1((_) {}, count: 0));

          renderSync(RenderOptions(
              file: p.join(sandbox, "test.scss"),
              includePaths: [p.join(sandbox, "dir")],
              quietDeps: true));

          // Give stderr a chance to be piped through if it's going to be.
          await pumpEventQueue();
        });
      });
    });

    group("with a bunch of deprecation warnings", () {
      setUp(() async {
        await writeTextFile(p.join(sandbox, "test.scss"), r"""
          $_: call("inspect", null);
          $_: call("rgb", 0, 0, 0);
          $_: call("nth", null, 1);
          $_: call("join", null, null);
          $_: call("if", true, 1, 2);
          $_: call("hsl", 0, 100%, 100%);

          $_: 1/2;
          $_: 1/3;
          $_: 1/4;
          $_: 1/5;
          $_: 1/6;
          $_: 1/7;
        """);
      });

      test("without --verbose, only prints five", () async {
        expect(
            const LineSplitter().bind(interceptStderr()),
            emitsInOrder([
              ...List.filled(5, emitsThrough(contains("call()"))),
              ...List.filled(5, emitsThrough(contains("math.div"))),
              emitsThrough(
                  contains("2 repetitive deprecation warnings omitted."))
            ]));

        renderSync(RenderOptions(file: p.join(sandbox, "test.scss")));
      });

      test("with --verbose, prints all", () async {
        expect(
            const LineSplitter().bind(interceptStderr()),
            emitsInOrder([
              ...List.filled(6, emitsThrough(contains("call()"))),
              ...List.filled(6, emitsThrough(contains("math.div")))
            ]));

        renderSync(
            RenderOptions(file: p.join(sandbox, "test.scss"), verbose: true));
      });
    });

    group("with both data and file", () {
      test("uses the data parameter as the source", () {
        expect(renderSync(RenderOptions(data: "x {y: z}", file: sassPath)),
            equalsIgnoringWhitespace('x { y: z; }'));
      });

      test("doesn't require the file path to exist", () {
        expect(
            renderSync(RenderOptions(
                data: "x {y: z}", file: p.join(sandbox, 'non-existent.scss'))),
            equalsIgnoringWhitespace('x { y: z; }'));
      });

      test("imports relative to the file path", () async {
        await writeTextFile(p.join(sandbox, 'importee.scss'), 'x {y: z}');
        expect(
            renderSync(
                RenderOptions(data: "@import 'importee'", file: sassPath)),
            equalsIgnoringWhitespace('x { y: z; }'));
      });

      test("reports errors from the file path", () {
        var error =
            renderSyncError(RenderOptions(data: "x {y: }", file: sassPath));
        expect(
            error.toString(),
            equals("Error: Expected expression.\n"
                "  ╷\n"
                "1 │ x {y: }\n"
                "  │       ^\n"
                "  ╵\n"
                "  ${prettyPath(sassPath)} 1:7  root stylesheet"));
      });
    });

    group("the result object", () {
      test("includes the filename", () {
        var result = sass.renderSync(RenderOptions(file: sassPath));
        expect(result.stats.entry, equals(sassPath));
      });

      test("includes data without a filename", () {
        var result = sass.renderSync(RenderOptions(data: 'a {b: c}'));
        expect(result.stats.entry, equals('data'));
      });

      test("includes timing information", () {
        var stats = sass.renderSync(RenderOptions(file: sassPath)).stats;
        expect(stats.start, const TypeMatcher<int>());
        expect(stats.end, const TypeMatcher<int>());
        expect(stats.start, lessThanOrEqualTo(stats.end));
        expect(stats.duration, equals(stats.end - stats.start));
      });

      group("has includedFiles which", () {
        test("contains the root path if available", () {
          var result = sass.renderSync(RenderOptions(file: sassPath));
          expect(result.stats.includedFiles, equals([sassPath]));
        });

        test("doesn't contain the root path if it's not available", () {
          var result = sass.renderSync(RenderOptions(data: 'a {b: c}'));
          expect(result.stats.includedFiles, isEmpty);
        });

        test("contains imported paths", () async {
          var importerPath = p.join(sandbox, 'importer.scss');
          await writeTextFile(importerPath, '@import "test"');

          var result = sass.renderSync(RenderOptions(file: importerPath));
          expect(result.stats.includedFiles,
              unorderedEquals([importerPath, sassPath]));
        });

        test("only contains each path once", () async {
          var importerPath = p.join(sandbox, 'importer.scss');
          await writeTextFile(importerPath, '@import "test"; @import "test";');

          var result = sass.renderSync(RenderOptions(file: importerPath));
          expect(result.stats.includedFiles,
              unorderedEquals([importerPath, sassPath]));
        });
      });
    });

    group("the error object", () {
      late RenderError error;
      group("for a parse error in a file", () {
        setUp(() async {
          await writeTextFile(sassPath, "a {b: }");
          error = renderSyncError(RenderOptions(file: sassPath));
        });

        test("is a JS Error", () async {
          expect(isJSError(error), isTrue);
        });

        test("has a useful toString() and message", () async {
          expect(
              error,
              toStringAndMessageEqual("Expected expression.\n"
                  "  ╷\n"
                  "1 │ a {b: }\n"
                  "  │       ^\n"
                  "  ╵\n"
                  "  ${prettyPath(sassPath)} 1:7  root stylesheet"));
        });

        test("sets the line, column, and filename", () {
          expect(error.line, equals(1));
          expect(error.column, equals(7));
          expect(error.file, equals(sassPath));
        });
      });

      group("for a parse error in a string", () {
        setUp(() {
          error = renderSyncError(RenderOptions(data: "a {b: }"));
        });

        test("is a JS Error", () async {
          expect(isJSError(error), isTrue);
        });

        test("has a useful toString() and message", () {
          expect(
              error,
              toStringAndMessageEqual("Expected expression.\n"
                  "  ╷\n"
                  "1 │ a {b: }\n"
                  "  │       ^\n"
                  "  ╵\n"
                  "  stdin 1:7  root stylesheet"));
        });

        test("sets the line, column, and filename", () {
          expect(error.line, equals(1));
          expect(error.column, equals(7));
          expect(error.file, equals("stdin"));
        });
      });

      group("for a runtime error in a file", () {
        setUp(() async {
          await writeTextFile(sassPath, "a {b: 1 % a}");
          error = renderSyncError(RenderOptions(file: sassPath));
        });

        test("has a useful toString() and message", () {
          expect(
              error,
              toStringAndMessageEqual('Undefined operation "1 % a".\n'
                  '  ╷\n'
                  '1 │ a {b: 1 % a}\n'
                  '  │       ^^^^^\n'
                  '  ╵\n'
                  '  ${prettyPath(sassPath)} 1:7  root stylesheet'));
        });

        test("sets the line, column, and filename", () {
          expect(error.line, equals(1));
          expect(error.column, equals(7));
          expect(error.file, equals(sassPath));
        });
      });

      group("for a runtime error in a string", () {
        setUp(() {
          error = renderSyncError(RenderOptions(data: "a {b: 1 % a}"));
        });

        test("has a useful toString() and message", () {
          expect(
              error,
              toStringAndMessageEqual('Undefined operation "1 % a".\n'
                  '  ╷\n'
                  '1 │ a {b: 1 % a}\n'
                  '  │       ^^^^^\n'
                  '  ╵\n'
                  '  stdin 1:7  root stylesheet'));
        });

        test("sets the line, column, and filename", () {
          expect(error.line, equals(1));
          expect(error.column, equals(7));
          expect(error.file, equals("stdin"));
        });
      });
    });

    group("when called with a raw JS collection", () {
      test("for includePaths", () {
        expect(
            renderSyncJS({
              "data": "@import 'test'",
              "includePaths": [sandbox]
            }),
            equalsIgnoringWhitespace('a { b: c; }'));
      });

      // Regression test for #412
      test("for includePaths with an importer", () {
        expect(
            renderSyncJS({
              "data": "@import 'test'",
              "includePaths": [sandbox],
              "importer": allowInterop((void _, void __) => null)
            }),
            equalsIgnoringWhitespace('a { b: c; }'));
      });
    });
  });

  group("render()", () {
    test("renders a file", () async {
      expect(await render(RenderOptions(file: sassPath)),
          equalsIgnoringWhitespace('a { b: c; }'));
    });

    test("throws an error that has a useful toString", () async {
      await writeTextFile(sassPath, 'a {b: }');

      var error = await renderError(RenderOptions(file: sassPath));
      expect(
          error.toString(),
          equals("Error: Expected expression.\n"
              "  ╷\n"
              "1 │ a {b: }\n"
              "  │       ^\n"
              "  ╵\n"
              "  ${prettyPath(sassPath)} 1:7  root stylesheet"));
    });
  });
}
