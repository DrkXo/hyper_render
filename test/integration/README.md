# Integration tests

Tests that exercise several layers together on realistic content. The full
map of test kinds, commands and conventions is in
[`doc/TESTING.md`](../../doc/TESTING.md).

## Files

| Area | Files |
|---|---|
| Real-world content | `real_world_html_test.dart` (news, blog, docs samples from `../fixtures/integration/`) |
| Large documents | `large_document_test.dart`, `cjk_stress_test.dart` |
| Selection | `selection_integration_test.dart` |
| Lifecycle and resources | `lifecycle_stability_test.dart`, `resource_management_test.dart`, `error_recovery_test.dart` |
| Security and accessibility | `security_integration_test.dart`, `advanced_security_test.dart`, `accessibility_test.dart`, `security_accessibility_integration_test.dart` |
| Rendering modes | `dark_mode_hardening_test.dart` |
| Animation | `animation_v150_integration_test.dart`, `animation_v150_performance_test.dart`, `animation_v150_stress_test.dart` |
| Performance | `performance_benchmarks_test.dart`, `performance_regression_test.dart` |

Fixtures: `../fixtures/integration/` (`news_article.html`, `blog_post.html`,
`documentation.html`, `large_document.html`, `complex_table.html`,
`float_layout.html`, `cjk_content.html`).

## Running

```bash
flutter test test/integration/
flutter test test/integration/real_world_html_test.dart
flutter test --coverage test/integration/
```
