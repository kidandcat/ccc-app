import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

const _panel = Color(0xFF171C24);
const _line = Color(0xFF2A3340);
const _text = Color(0xFFE8EDF4);
const _muted = Color(0xFF8B97A8);
const _gold = Color(0xFFD4A84B);

/// GitHub-flavored Markdown (tables, lists, code, …) sized to the parent.
/// Wide tables scroll sideways; paragraphs still wrap.
class MdBody extends StatelessWidget {
  const MdBody(this.data, {super.key, this.style});
  final String data;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = (style ?? theme.textTheme.bodyMedium)?.copyWith(
      color: _text,
      height: 1.45,
    );
    return MarkdownBody(
      data: data,
      selectable: true,
      shrinkWrap: true,
      fitContent: false,
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: base,
        a: base?.copyWith(color: _gold),
        em: base?.copyWith(fontStyle: FontStyle.italic),
        strong: base?.copyWith(fontWeight: FontWeight.w700),
        del: base?.copyWith(decoration: TextDecoration.lineThrough),
        listBullet: base,
        listIndent: 22,
        h1: base?.copyWith(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
        h2: base?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
        h3: base?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
        h4: base?.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
        h5: base?.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
        h6: base?.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: _muted,
        ),
        blockquote: base?.copyWith(color: _muted),
        blockquoteDecoration: const BoxDecoration(
          color: _panel,
          border: Border(left: BorderSide(color: _gold, width: 3)),
        ),
        blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        code: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          color: _gold,
          backgroundColor: _panel,
          height: 1.4,
        ),
        codeblockPadding: const EdgeInsets.all(12),
        codeblockDecoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _line),
        ),
        tableHead: base?.copyWith(fontWeight: FontWeight.w700, fontSize: 13),
        tableBody: base?.copyWith(fontSize: 13),
        tableHeadAlign: TextAlign.left,
        tableBorder: TableBorder.all(color: _line, width: 0.6),
        tableColumnWidth: const IntrinsicColumnWidth(),
        tableScrollbarThumbVisibility: true,
        tableCellsPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 7,
        ),
        tableHeadCellsDecoration: const BoxDecoration(color: Color(0xFF1E2530)),
        tablePadding: const EdgeInsets.only(bottom: 8, top: 4),
        horizontalRuleDecoration: const BoxDecoration(
          border: Border(top: BorderSide(color: _line)),
        ),
      ),
    );
  }
}
