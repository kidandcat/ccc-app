import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'crew.dart';
import 'hub.dart';

const _ink = Color(0xFF0E1116);
const _panel = Color(0xFF171C24);
const _line = Color(0xFF2A3340);
const _text = Color(0xFFE8EDF4);
const _muted = Color(0xFF8B97A8);
const _gold = Color(0xFFD4A84B);

/// Persistent ask_owner surface. Same buttons Telegram shows; answering here
/// is the hub `answer` RPC, not a chat message that can scroll away.
class DecisionCard extends StatefulWidget {
  const DecisionCard({
    super.key,
    required this.machine,
    required this.question,
    this.showSession = true,
    this.onOpenSession,
  });

  final Machine machine;
  final QuestionInfo question;
  final bool showSession;
  final VoidCallback? onOpenSession;

  @override
  State<DecisionCard> createState() => _DecisionCardState();
}

class _DecisionCardState extends State<DecisionCard> {
  final _answerCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _answerCtrl.dispose();
    super.dispose();
  }

  Future<void> _answer({int? option, String? text}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await CrewScope.read(context).answerQuestion(
        widget.machine,
        widget.question,
        option: option,
        text: text,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    return Material(
      color: _panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: _gold.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.front_hand_outlined, color: _gold, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.showSession && q.bot.isNotEmpty ? q.bot : 'Decision',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _gold,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (widget.onOpenSession != null)
                  TextButton(
                    onPressed: widget.onOpenSession,
                    child: const Text('Open'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              q.question,
              style: const TextStyle(color: _text, height: 1.35, fontSize: 15),
            ),
            const SizedBox(height: 12),
            if (q.options.isNotEmpty) ...[
              for (var i = 0; i < q.options.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                if (i == 0)
                  FilledButton(
                    onPressed: _busy ? null : () => _answer(option: i),
                    style: FilledButton.styleFrom(
                      backgroundColor: _gold,
                      foregroundColor: _ink,
                      disabledBackgroundColor: _gold.withValues(alpha: 0.4),
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(q.options[i], textAlign: TextAlign.center),
                  )
                else
                  OutlinedButton(
                    onPressed: _busy ? null : () => _answer(option: i),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _text,
                      side: const BorderSide(color: _gold),
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(q.options[i], textAlign: TextAlign.center),
                  ),
              ],
            ] else
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _answerCtrl,
                      enabled: !_busy,
                      minLines: 1,
                      maxLines: 3,
                      textInputAction: TextInputAction.send,
                      decoration: InputDecoration(
                        hintText: 'Your answer',
                        hintStyle: const TextStyle(color: _muted),
                        filled: true,
                        fillColor: _ink,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: _line),
                        ),
                      ),
                      onSubmitted: (v) {
                        if (v.trim().isNotEmpty) _answer(text: v);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    style: IconButton.styleFrom(
                      backgroundColor: _gold,
                      foregroundColor: _ink,
                    ),
                    onPressed: _busy
                        ? null
                        : () => _answer(text: _answerCtrl.text),
                    icon: const Icon(Icons.arrow_upward),
                  ),
                ],
              ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: LinearProgressIndicator(color: _gold, minHeight: 2),
              ),
          ],
        ),
      ),
    );
  }
}

class DecisionBanner extends StatelessWidget {
  const DecisionBanner({
    super.key,
    required this.machine,
    this.questions = const [],
  });
  final Machine? machine;
  final List<QuestionInfo> questions;

  @override
  Widget build(BuildContext context) {
    final crew = CrewScope.of(context);
    final items = machine == null
        ? crew.pendingDecisions
        : questions.map((q) => (machine: machine!, question: q)).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    if (items.length == 1) {
      final it = items.first;
      return DecisionCard(
        machine: it.machine,
        question: it.question,
        onOpenSession: () => _open(context, it.machine, it.question),
      );
    }
    return Material(
      color: _panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: _gold.withValues(alpha: 0.45)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => DecisionsPage(machine: machine),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Row(
            children: [
              const Icon(Icons.front_hand_outlined, color: _gold),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${items.length} decisions waiting',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _text,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, color: _muted),
            ],
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context, Machine m, QuestionInfo q) {
    final crew = CrewScope.read(context);
    final s = crew.sessionFor(m);
    crew.openChat?.call(
      m,
      s,
      BotInfo(
        id: q.botId,
        name: q.bot,
        role: '',
        status: 'waiting',
        engine: '',
      ),
    );
  }
}

class DecisionsPage extends StatelessWidget {
  const DecisionsPage({super.key, this.machine});
  final Machine? machine;

  @override
  Widget build(BuildContext context) {
    final crew = CrewScope.of(context);
    final items = machine == null
        ? crew.pendingDecisions
        : crew
              .questionsOn(machine!.id)
              .map((q) => (machine: machine!, question: q))
              .toList();
    return Scaffold(
      backgroundColor: _ink,
      appBar: AppBar(
        title: Text(
          'Decisions',
          style: GoogleFonts.sourceSerif4(fontWeight: FontWeight.w700),
        ),
      ),
      body: items.isEmpty
          ? const Center(
              child: Text(
                'No pending decisions.',
                style: TextStyle(color: _muted),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (ctx, i) {
                final it = items[i];
                return DecisionCard(
                  machine: it.machine,
                  question: it.question,
                  onOpenSession: () {
                    final s = crew.sessionFor(it.machine);
                    crew.openChat?.call(
                      it.machine,
                      s,
                      BotInfo(
                        id: it.question.botId,
                        name: it.question.bot,
                        role: '',
                        status: 'waiting',
                        engine: '',
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

class StatusMark extends StatelessWidget {
  const StatusMark(this.status, {super.key});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = statusHot(status) ? _gold : _muted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          statusCaption(status),
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
