import 'package:flutter/material.dart';

import 'crew.dart';
import 'hub.dart';

const _panel = Color(0xFF171C24);
const _line = Color(0xFF2A3340);
const _text = Color(0xFFE8EDF4);
const _muted = Color(0xFF8B97A8);
const _gold = Color(0xFFD4A84B);

/// Live line on a session card: pending question, thinking, last text, engine.
String sessionSubtitle(
  BotInfo bot, {
  QuestionInfo? question,
  String cachedProgress = '',
}) {
  final asking = question ?? bot.question;
  final q = asking?.question.trim() ?? '';
  if (q.isNotEmpty) return q;
  final live = Crew.resolveProgress(
    status: bot.status,
    turnProgress: bot.progress,
    cached: cachedProgress,
  );
  if (live.isNotEmpty) return live;
  final last = bot.lastText?.trim() ?? '';
  if (last.isNotEmpty) return last;
  if (bot.engine.trim().isNotEmpty) return bot.engine;
  return statusCaption(bot.status);
}

/// Waiting / running first, then most recently active.
List<BotInfo> rankWorkers(
  List<BotInfo> workers, {
  bool Function(BotInfo bot)? isAsking,
}) {
  int rank(BotInfo x) {
    if (isAsking?.call(x) == true) return 0;
    final s = statusLabel(x.status);
    if (s == 'waiting') return 0;
    if (s == 'running' || s == 'queued') return 1;
    return 2;
  }

  final out = [...workers];
  out.sort((a, b) {
    final c = rank(a).compareTo(rank(b));
    if (c != 0) return c;
    return (b.last ?? '').compareTo(a.last ?? '');
  });
  return out;
}

String? sessionWhen(String? last, {DateTime? now}) {
  if (last == null || last.isEmpty) return null;
  final t = DateTime.tryParse(last);
  if (t == null) return null;
  final d = (now ?? DateTime.now()).toUtc().difference(t.toUtc());
  if (d.isNegative || d.inSeconds < 45) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays < 14) return '${d.inDays}d ago';
  return null;
}

/// One session, Grok-Bot-cloud-agent style: name, live status, current line.
class SessionCard extends StatelessWidget {
  const SessionCard({
    super.key,
    required this.bot,
    this.line,
    this.asking = false,
    this.onTap,
    this.onLongPress,
    this.trailing,
  });

  final BotInfo bot;
  final String? line;
  final bool asking;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final status = asking ? 'waiting' : bot.status;
    final hot = asking || statusHot(status);
    final subtitle = (line ?? sessionSubtitle(bot)).trim();
    final when = sessionWhen(bot.last);
    final meta = [
      if (bot.engine.trim().isNotEmpty) bot.engine,
      ?when,
    ].join(' · ');
    return Material(
      color: _panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: hot ? _gold.withValues(alpha: asking ? 0.45 : 0.28) : _line,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              _StatusDot(status: status),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bot.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _text,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: hot ? _gold : _muted,
                          fontSize: 13,
                          height: 1.25,
                        ),
                      ),
                    ],
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _muted, fontSize: 11),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              trailing ?? _StatusPill(status),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sticky fleet glance on General — one card, a row per live session.
class SessionStrip extends StatelessWidget {
  const SessionStrip({
    super.key,
    required this.workers,
    required this.onOpen,
    this.questionOf,
    this.progressOf,
    this.onSeeAll,
    this.limit = 4,
  });

  final List<BotInfo> workers;
  final void Function(BotInfo bot) onOpen;
  final QuestionInfo? Function(int botId)? questionOf;
  final String Function(int botId)? progressOf;
  final VoidCallback? onSeeAll;
  final int limit;

  @override
  Widget build(BuildContext context) {
    if (workers.isEmpty) return const SizedBox.shrink();
    final ranked = rankWorkers(
      workers,
      isAsking: (b) {
        final q = questionOf?.call(b.id) ?? b.question;
        return q != null && q.question.trim().isNotEmpty;
      },
    );
    final shown = ranked.take(limit).toList();
    final extra = ranked.length - shown.length;
    final anyHot = shown.any((b) {
      final q = questionOf?.call(b.id) ?? b.question;
      return (q != null && q.question.trim().isNotEmpty) || statusHot(b.status);
    });
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Material(
        color: _panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: anyHot ? _gold.withValues(alpha: 0.28) : _line,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 6, 6),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Sessions',
                      style: TextStyle(
                        color: _text,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (onSeeAll != null)
                    TextButton(
                      onPressed: onSeeAll,
                      style: TextButton.styleFrom(
                        foregroundColor: _muted,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: Text(
                        extra > 0
                            ? (extra == 1 ? '1 more' : '$extra more')
                            : 'See all',
                      ),
                    ),
                ],
              ),
            ),
            for (var i = 0; i < shown.length; i++) ...[
              if (i > 0) const Divider(height: 1, thickness: 1, color: _line),
              _SessionRow(
                bot: shown[i],
                question: questionOf?.call(shown[i].id) ?? shown[i].question,
                cachedProgress: progressOf?.call(shown[i].id) ?? '',
                onTap: () => onOpen(shown[i]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({
    required this.bot,
    required this.onTap,
    this.question,
    this.cachedProgress = '',
  });

  final BotInfo bot;
  final QuestionInfo? question;
  final String cachedProgress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final asking = question != null && question!.question.trim().isNotEmpty;
    final status = asking ? 'waiting' : bot.status;
    final hot = asking || statusHot(status);
    final line = sessionSubtitle(
      bot,
      question: question,
      cachedProgress: cachedProgress,
    );
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
        child: Row(
          children: [
            _StatusDot(status: status),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bot.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _text,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  if (line.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: hot ? _gold : _muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            _StatusPill(status),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.status);
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = statusHot(status) ? _gold : _muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        statusCaption(status),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.02,
        ),
      ),
    );
  }
}

class _StatusDot extends StatefulWidget {
  const _StatusDot({required this.status});
  final String status;

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot>
    with SingleTickerProviderStateMixin {
  AnimationController? _pulse;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _StatusDot old) {
    super.didUpdateWidget(old);
    if (old.status != widget.status) _sync();
  }

  void _sync() {
    final run = statusLabel(widget.status) == 'running';
    if (run && _pulse == null) {
      _pulse = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2200),
      )..repeat();
    } else if (!run && _pulse != null) {
      _pulse!.dispose();
      _pulse = null;
    }
  }

  @override
  void dispose() {
    _pulse?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hot = statusHot(widget.status);
    final color = hot ? _gold : _muted;
    final dot = Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    final pulse = _pulse;
    if (pulse == null) return dot;
    return AnimatedBuilder(
      animation: pulse,
      builder: (ctx, child) {
        final t = pulse.value;
        final glow = 0.25 + 0.55 * (1 - (t * 2 - 1).abs());
        return Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color.withValues(alpha: glow.clamp(0.35, 1)),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.35 * glow),
                blurRadius: 6,
              ),
            ],
          ),
        );
      },
    );
  }
}
