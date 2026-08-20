import '../models/video_task.dart';

class SubtitleService {
  /// Splits [script] into subtitle entries whose total duration sums to
  /// [totalDurationSec]. Timing is estimated proportionally by character count.
  List<SubtitleEntry> buildEntries(String script, double totalDurationSec) {
    final sentences = _splitSentences(script);
    if (sentences.isEmpty) return [];

    final totalChars = sentences.fold<int>(0, (s, e) => s + e.length);
    if (totalChars == 0) return [];

    final entries = <SubtitleEntry>[];
    double cursor = 0.0;

    for (final sentence in sentences) {
      final fraction = sentence.length / totalChars;
      final dur = totalDurationSec * fraction;

      entries.add(SubtitleEntry(
        start: Duration(milliseconds: (cursor * 1000).round()),
        end: Duration(milliseconds: ((cursor + dur) * 1000).round()),
        text: sentence.trim(),
      ));

      cursor += dur;
    }

    return entries;
  }

  /// Serialises subtitle entries to SRT format.
  String toSrt(List<SubtitleEntry> entries) {
    final buf = StringBuffer();
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      buf.writeln(i + 1);
      buf.writeln('${_fmt(e.start)} --> ${_fmt(e.end)}');
      buf.writeln(e.text);
      buf.writeln();
    }
    return buf.toString();
  }

  String _fmt(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    final ms = (d.inMilliseconds % 1000).toString().padLeft(3, '0');
    return '$h:$m:$s,$ms';
  }

  List<String> _splitSentences(String text) {
    // Split on sentence-ending punctuation, keep short lines together.
    final raw = text
        .split(RegExp(r'(?<=[.!?])\s+'))
        .where((s) => s.trim().isNotEmpty)
        .toList();

    // Merge very short fragments (< 20 chars) with the next sentence.
    final merged = <String>[];
    for (var i = 0; i < raw.length; i++) {
      if (i < raw.length - 1 && raw[i].trim().length < 20) {
        merged.add('${raw[i].trim()} ${raw[i + 1].trim()}');
        i++;
      } else {
        merged.add(raw[i].trim());
      }
    }
    return merged;
  }
}
