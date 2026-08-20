/// [sound_service.dart]の条件付きエクスポート先（Web向け実装）。
/// 効果音は音声ファイルを使わず、Web Audio API（`AudioContext`）で
/// その場で音を合成する。読み上げはWeb Speech API（`speechSynthesis`）を使う。
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

web.AudioContext? _audioContext;

/// 効果音再生用の`AudioContext`を、初回だけ生成して使い回す
/// （ブラウザによっては生成できる数に上限があるため）。
web.AudioContext _ensureAudioContext() {
  return _audioContext ??= web.AudioContext();
}

/// 単発の音（正弦波などの発振音）を、指定した開始時刻・長さ・音量で鳴らす。
/// 音量は`GainNode`でクリック音（プチッという音）が出ないよう、瞬間的に
/// 立ち上げてから減衰させるエンベロープをかける。
void _scheduleTone(
  web.AudioContext ctx, {
  required double frequency,
  required double startTime,
  required double duration,
  String type = 'sine',
  double peakGain = 0.2,
}) {
  final oscillator = ctx.createOscillator();
  oscillator.type = type;
  oscillator.frequency.setValueAtTime(frequency, startTime);

  final gainNode = ctx.createGain();
  gainNode.gain.setValueAtTime(0.0001, startTime);
  gainNode.gain.exponentialRampToValueAtTime(peakGain, startTime + 0.015);
  gainNode.gain.exponentialRampToValueAtTime(0.0001, startTime + duration);

  oscillator.connect(gainNode);
  gainNode.connect(ctx.destination);
  oscillator.start(startTime);
  oscillator.stop(startTime + duration + 0.02);
}

/// [frequencies]を同時に鳴らす和音版の[_scheduleTone]。
void _scheduleChord(
  web.AudioContext ctx, {
  required List<double> frequencies,
  required double startTime,
  required double duration,
  String type = 'sine',
  double peakGain = 0.15,
}) {
  for (final f in frequencies) {
    _scheduleTone(
      ctx,
      frequency: f,
      startTime: startTime,
      duration: duration,
      type: type,
      peakGain: peakGain,
    );
  }
}

/// 正解時のファンファーレ（合計約4.1秒）。
/// 1) 0.00-0.54s: 上昇する6音の助走フレーズ（ド・レ・ミ・ソ・高ド・高ミ）
/// 2) 0.60-0.76s / 0.84-1.06s: 「タン・ター！」の2発の和音の合いの手
/// 3) 1.14-4.14s: 高いドミソ＋オクターブ上のドの和音を、低音の支え（低いド）と
///    共にゆっくり減衰させながら鳴らし、お祝い感のある余韻を残す
void playCorrectSound() {
  try {
    final ctx = _ensureAudioContext();
    unawaited(ctx.resume().toDart);
    final t0 = ctx.currentTime;

    // 1) 助走フレーズ：C5 D5 E5 G5 C6 E6 を弾むように上昇させる。
    const runNotes = [523.25, 587.33, 659.25, 783.99, 1046.50, 1318.51];
    const runStep = 0.09;
    for (var i = 0; i < runNotes.length; i++) {
      _scheduleTone(
        ctx,
        frequency: runNotes[i],
        startTime: t0 + i * runStep,
        duration: 0.16,
        type: 'triangle',
        peakGain: 0.16,
      );
    }
    final afterRun = t0 + runNotes.length * runStep;

    // 2) 「タン・ター！」：短い和音 → 一段大きい和音の2発。
    final stab1 = afterRun + 0.06;
    _scheduleChord(
      ctx,
      frequencies: const [1046.50, 1318.51, 1567.98], // C6 E6 G6
      startTime: stab1,
      duration: 0.16,
      type: 'triangle',
      peakGain: 0.15,
    );
    final stab2 = stab1 + 0.24;
    _scheduleChord(
      ctx,
      frequencies: const [783.99, 1046.50, 1318.51, 1567.98], // G5 C6 E6 G6
      startTime: stab2,
      duration: 0.22,
      type: 'triangle',
      peakGain: 0.17,
    );

    // 3) 最後の和音：高いドミソ＋オクターブ上のドを、低いドの支えと共に
    //    3秒かけてゆっくり減衰させ、余韻を残す。
    final finaleStart = stab2 + 0.30;
    _scheduleChord(
      ctx,
      frequencies: const [1046.50, 1318.51, 1567.98, 2093.00], // C6 E6 G6 C7
      startTime: finaleStart,
      duration: 3.0,
      type: 'sine',
      peakGain: 0.15,
    );
    _scheduleTone(
      ctx,
      frequency: 261.63, // C4（低音の支え）
      startTime: finaleStart,
      duration: 3.0,
      type: 'sine',
      peakGain: 0.10,
    );
  } catch (_) {
    // 音が出せない環境（AudioContext未対応・ブロック済みなど）でも、
    // アプリの他の動作には影響させない。
  }
}

/// 不正解時のブザー音（約1.9秒）。
/// ノコギリ波2本（150Hz付近とその1オクターブ下）を重ねて厚みを出し、
/// 24Hzの矩形波LFOでゲインを揺らして「ブーー」というザラついた質感を作る。
/// 終盤にかけて音程をわずかに下げ、尻すぼみに減衰させる。
/// 生徒が繰り返し聞くことを想定し、音量・長さは控えめに抑えている。
void playIncorrectSound() {
  try {
    final ctx = _ensureAudioContext();
    unawaited(ctx.resume().toDart);
    final t0 = ctx.currentTime;
    const duration = 1.9;

    final osc1 = ctx.createOscillator();
    osc1.type = 'sawtooth';
    osc1.frequency.setValueAtTime(150, t0);
    osc1.frequency.linearRampToValueAtTime(105, t0 + duration);

    final osc2 = ctx.createOscillator(); // 1オクターブ下を重ねて厚みを出す
    osc2.type = 'sawtooth';
    osc2.frequency.setValueAtTime(75, t0);
    osc2.frequency.linearRampToValueAtTime(52.5, t0 + duration);

    final mainGain = ctx.createGain();
    mainGain.gain.setValueAtTime(0.0001, t0);
    mainGain.gain.exponentialRampToValueAtTime(0.16, t0 + 0.05);
    mainGain.gain.setValueAtTime(0.16, t0 + duration - 0.35);
    mainGain.gain.exponentialRampToValueAtTime(0.0001, t0 + duration);

    // ブザーらしいザラつき（トレモロ）を、LFO（低周波発振器）でゲインを
    // 揺らして作る。LFO自体は聞こえず、mainGainの音量を上下させるだけ。
    final lfo = ctx.createOscillator();
    lfo.type = 'square';
    lfo.frequency.setValueAtTime(24, t0);
    final lfoDepth = ctx.createGain();
    lfoDepth.gain.setValueAtTime(0.06, t0);
    lfo.connect(lfoDepth);
    lfoDepth.connect(mainGain.gain);

    osc1.connect(mainGain);
    osc2.connect(mainGain);
    mainGain.connect(ctx.destination);

    osc1.start(t0);
    osc2.start(t0);
    lfo.start(t0);
    osc1.stop(t0 + duration + 0.05);
    osc2.stop(t0 + duration + 0.05);
    lfo.stop(t0 + duration + 0.05);
  } catch (_) {
    // 音が出せない環境でも、アプリの他の動作には影響させない。
  }
}

/// [text]を英語の音声合成で読み上げる。連続でタップされた場合は、
/// 前の読み上げを打ち切ってから新しい読み上げを開始する。
void speak(String text, {String lang = 'en-US'}) {
  try {
    final synth = web.window.speechSynthesis;
    synth.cancel();
    final utterance = web.SpeechSynthesisUtterance(text);
    utterance.lang = lang;
    synth.speak(utterance);
  } catch (_) {
    // Web Speech API未対応のブラウザでも、アプリの他の動作には影響させない。
  }
}
