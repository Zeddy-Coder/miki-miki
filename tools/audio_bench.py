#!/usr/bin/env python3
"""Audio bench for Miki Miki's mpv setup: desktop mpv stands in for the app's libmpv.

    python3 tools/audio_bench.py        (needs mpv, ffmpeg and numpy in PATH; files go to tools/.audio_bench/)

With real mpv and the options the app sets (MpvConfig.configureEngine + media_kit) it checks:
  1. a stereo episode after a mono one: with gapless-audio=yes (the old setting) the output keeps the first file's
     mono for the whole session; with weak (now) it reopens in stereo;
  2. 5.1 downmixed to two channels (the phone speakers) keeps left and right apart;
  3. how often the audio output opens over a session: OpenSL ES on Android measured its device latency only then,
     so with gapless-audio=yes a Bluetooth / speaker change kept the old latency until a restart;
  4. ao-reload (what the app runs when the audio route changes) reopens the output, playback goes on, audio-delay stays.
Prints PASS / FAIL lines and writes report.json next to the files; exit code 1 when an expectation fails.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.join(HERE, '.audio_bench')
os.makedirs(WORK, exist_ok=True)
FFMPEG = shutil.which('ffmpeg') or 'ffmpeg'

# The engine options of the app (lib/services/mpv_config.dart + media_kit's own), audio-relevant ones
APP_BASE = [
    '--video-sync=audio', '--framedrop=vo', '--audio-pitch-correction=yes', '--hr-seek=yes', '--hr-seek-framedrop=yes',
    '--keep-open=no', '--audio-display=no', '--vd-lavc-fast=yes',
]


def make(name, audio_filter, layout, rate=48000, seconds=3):
    path = os.path.join(WORK, name)
    if os.path.exists(path):
        return path
    subprocess.run([
        FFMPEG, '-hide_banner', '-loglevel', 'error', '-y',
        '-f', 'lavfi', '-i', f'testsrc2=size=320x240:rate=24:duration={seconds}',
        '-f', 'lavfi', '-i', audio_filter.format(rate=rate, d=seconds),
        '-map', '0:v', '-map', '1:a', '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p',
        '-c:a', 'pcm_s16le', '-shortest', path,
    ], check=True)
    return path


def sine(freq, rate='{rate}', d='{d}'):
    return f'sine=frequency={freq}:sample_rate={rate}:duration={d}'


MONO = make('mono.mkv', 'aevalsrc=0.4*sin(600*2*PI*t):c=mono:s={rate}:d={d}', 'mono')
# 440 Hz only on the left, 1000 Hz only on the right
STEREO = make('stereo.mkv', 'aevalsrc=0.4*sin(440*2*PI*t)|0.4*sin(1000*2*PI*t):c=stereo:s={rate}:d={d}', 'stereo')
# A tone of its own per channel: FL 440, FR 1000, FC 600 (dialogue), LFE 60, BL 300, BR 1500
SURROUND = make(
    'surround.mkv',
    'aevalsrc=0.25*sin(440*2*PI*t)|0.25*sin(1000*2*PI*t)|0.25*sin(600*2*PI*t)|0.25*sin(60*2*PI*t)|'
    '0.25*sin(300*2*PI*t)|0.25*sin(1500*2*PI*t):c=5.1:s={rate}:d={d}',
    '5.1',
)
MONO44 = make('mono44.mkv', 'aevalsrc=0.4*sin(600*2*PI*t):c=mono:s={rate}:d={d}', 'mono', rate=44100)


def mpv(files, *extra, out=None, script=None):
    args = ['mpv', '--no-config', '--really-quiet=no', '--msg-level=all=warn,ao=v,cplayer=v', '--vo=null', *APP_BASE]
    if out:
        args += ['--ao=pcm', f'--ao-pcm-file={out}']
    if script:
        args += [f'--script={script}']
    args += list(extra) + list(files)
    r = subprocess.run(args, capture_output=True, text=True, timeout=120)
    return r.stdout + r.stderr


def ao_inits(log):
    """The audio output (re)openings with their format, e.g. '48000Hz stereo 2ch s16'"""
    return re.findall(r'AO: \[\w+\] (\d+Hz \S+ \d+ch \S+)', log)


def read_wav(path):
    with wave.open(path) as w:
        ch, rate, n = w.getnchannels(), w.getframerate(), w.getnframes()
        data = np.frombuffer(w.readframes(n), dtype=np.int16).astype(np.float64)
    return ch, rate, data.reshape(-1, ch) if ch > 1 else data.reshape(-1, 1)


def level(x, rate, freq):
    """Amplitude of one frequency (Goertzel-like via an FFT bin)"""
    spec = np.abs(np.fft.rfft(x * np.hanning(len(x))))
    bins = np.fft.rfftfreq(len(x), 1 / rate)
    i = np.argmin(np.abs(bins - freq))
    return float(spec[max(i - 2, 0):i + 3].max())


def db(a, b):
    return 20 * np.log10(max(a, 1e-9) / max(b, 1e-9))


results = []


def check(name, ok, detail):
    results.append({'test': name, 'ok': bool(ok), 'detail': detail})
    print(f"{'PASS' if ok else 'FAIL'}  {name}: {detail}")


def stereo_separation(path):
    ch, rate, d = read_wav(path)
    if ch < 2:
        return ch, None
    mid = d[len(d) // 4: len(d) * 3 // 4]
    l, r = mid[:, 0], mid[:, 1]
    # 440 Hz is only in the left channel, 1000 Hz only in the right
    sep_l = db(level(l, rate, 440), level(r, rate, 440))
    sep_r = db(level(r, rate, 1000), level(l, rate, 1000))
    return ch, (sep_l, sep_r)


# 1. Stereo after mono: what the app does now (gapless-audio=yes) and what it should do (weak)
for gapless in ('yes', 'weak'):
    out = os.path.join(WORK, f'mono_then_stereo_{gapless}.wav')
    if os.path.exists(out):
        os.remove(out)
    log = mpv([MONO, STEREO], f'--gapless-audio={gapless}', '--audio-channels=auto-safe', out=out)
    inits = ao_inits(log)
    ch, sep = stereo_separation(out)
    if gapless == 'yes':
        check('gapless-audio=yes: стерео після моно', ch == 1,
              f'вихід відкрито {len(inits)} раз(и) {inits}; у файлі {ch} канал(и) — стерео серія звучить як моно (це вада)')
    else:
        ok = ch == 2 and sep is not None and sep[0] > 40 and sep[1] > 40
        check('gapless-audio=weak: стерео після моно', ok,
              f'вихід відкрито {len(inits)} раз(и) {inits}; каналів {ch}, розділення L/R: '
              f'{sep[0]:.0f} дБ / {sep[1]:.0f} дБ' if sep else f'каналів {ch}')

# 2. 5.1 to two channels (the phone speakers / OpenSL ES: always 2 channels)
out = os.path.join(WORK, 'surround_stereo.wav')
if os.path.exists(out):
    os.remove(out)
log = mpv([SURROUND], '--gapless-audio=weak', '--audio-channels=stereo', out=out)
ch, rate, d = read_wav(out)
mid = d[len(d) // 4: len(d) * 3 // 4]
l, r = mid[:, 0], mid[:, 1]
fl = db(level(l, rate, 440), level(r, rate, 440))
fr = db(level(r, rate, 1000), level(l, rate, 1000))
fc = db(level(l, rate, 600), level(r, rate, 600))
corr = float(np.corrcoef(l, r)[0, 1])
check('5.1 → стерео: ліве й праве не злиті', ch == 2 and fl > 20 and fr > 20 and abs(fc) < 1,
      f'FL у лівому сильніше на {fl:.0f} дБ, FR у правому на {fr:.0f} дБ, центр рівно посередині ({fc:+.1f} дБ), '
      f'кореляція L/R {corr:.2f} (моно було б 1.00)')

# 3. How often the output is opened over a session of different files
for gapless in ('yes', 'weak'):
    log = mpv([STEREO, MONO44, SURROUND, STEREO], f'--gapless-audio={gapless}', '--ao=null', '--audio-channels=auto-safe')
    inits = ao_inits(log)
    if gapless == 'yes':
        check('gapless-audio=yes: вихід звуку відкривається лише раз за сесію', len(inits) == 1,
              f'{len(inits)} відкриття на 4 файли {inits}: затримку пристрою OpenSL ES міряє лише тут, тож зміна маршруту '
              f'(Bluetooth ↔ динамік) лишає стару до перезапуску')
    else:
        check('gapless-audio=weak: вихід перевідкривається, коли змінюється формат', len(inits) >= 3,
              f'{len(inits)} відкриття на 4 файли {inits}')

# 4. ao-reload during playback: the output re-opens, playback continues, audio-delay stays
script = os.path.join(WORK, 'reload.lua')
with open(script, 'w') as f:
    f.write('''
local reloaded = false
mp.set_property_number("audio-delay", 0.25)
mp.add_periodic_timer(0.2, function()
  local t = mp.get_property_number("time-pos") or 0
  if not reloaded and t > 1.0 then
    reloaded = true
    mp.commandv("ao-reload")
    mp.msg.warn("BENCH reload at " .. string.format("%.2f", t))
  end
end)
mp.register_event("end-file", function()
  mp.msg.warn("BENCH end delay=" .. tostring(mp.get_property_number("audio-delay")))
end)
''')
log = mpv([STEREO], '--gapless-audio=weak', '--ao=null', script=script)
inits = ao_inits(log)
delay = re.findall(r'BENCH end delay=([\d.]+)', log)
reload_at = re.findall(r'BENCH reload at ([\d.]+)', log)
ended = 'Exiting... (End of file)' in log or 'BENCH end' in log
check('ao-reload перевідкриває вихід і не збиває затримку звуку',
      len(inits) == 2 and reload_at and ended and delay and abs(float(delay[0]) - 0.25) < 1e-6,
      f'відкриттів {len(inits)} (перезавантаження на {reload_at[0] if reload_at else "—"} с), '
      f'серія дограла: {ended}, audio-delay після: {delay[0] if delay else "—"}')

with open(os.path.join(WORK, 'report.json'), 'w') as f:
    json.dump(results, f, ensure_ascii=False, indent=1)
sys.exit(0 if all(r['ok'] for r in results) else 1)
