import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// DevTools only loads an extension whose `config.yaml` `name` equals the
/// owning package's name (`devtools_extensions validate` rejects anything
/// else). A display-style name like "HyperRender Inspector" silently
/// disabled the whole extension until PR #17.
void main() {
  test('extension config name matches the package name', () {
    String field(String path, String key) =>
        RegExp('^$key:\\s*(\\S+)\\s*\$', multiLine: true)
            .firstMatch(File(path).readAsStringSync())!
            .group(1)!;

    expect(
      field('extension/devtools/config.yaml', 'name'),
      field('pubspec.yaml', 'name'),
    );
  });
}
