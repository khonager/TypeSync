// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

html.MutationObserver? _observer;

void suppressBrowserSpellcheckForFlutterInputs() {
  _markDocument();
  _markEditableElements();

  _observer ??= html.MutationObserver((_, __) {
    _markDocument();
    _markEditableElements();
  });

  final body = html.document.body;
  if (body != null) {
    _observer!.observe(body, childList: true, subtree: true);
  }
}

void _markDocument() {
  for (final element in <html.Element?>[
    html.document.documentElement,
    html.document.body,
  ]) {
    if (element == null) continue;
    _disableSpellcheck(element);
  }
}

void _markEditableElements() {
  final elements = html.document.querySelectorAll(
    'input, textarea, [contenteditable], flt-text-editing-host',
  );

  for (final element in elements) {
    _disableSpellcheck(element);
  }
}

void _disableSpellcheck(html.Element element) {
  element.setAttribute('spellcheck', 'false');
  element.setAttribute('autocomplete', 'off');
  element.setAttribute('autocorrect', 'off');
  element.setAttribute('autocapitalize', 'off');
  element.setAttribute('data-gramm', 'false');
  element.setAttribute('data-gramm_editor', 'false');
  element.setAttribute('data-enable-grammarly', 'false');
  element.setAttribute('data-lt-active', 'false');
}
