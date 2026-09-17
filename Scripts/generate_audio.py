#!/usr/bin/env python3
"""
Regenerates the bundled audio clips.

Each alert clip = short attention tone + gap + spoken phrase, baked into one WAV so
the app plays exactly one file per alert with no gap between tone and word.

Speech engines:
  say    macOS built-in voice (default on a Mac; best quality, zero installs)
  piper  Piper TTS (used to produce the committed placeholders on Linux)
  none   tones only (spoken part replaced by silence; for debugging)

Usage on the owner's Mac, from the repository root:

    python3 Scripts/generate_audio.py --engine say

Only the Python standard library is used. Output goes to MotoHazardAlert/Resources/Audio/.
"""

import argparse
import math
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import wave

RATE = 44100

# Cues describe what is there. They never instruct the rider.
PHRASES = {
    "gravel_ahead": "Gravel ahead.",
    "cattle_ahead": "Cattle ahead.",
    "accident_ahead": "Accident ahead.",
    "rough_surface_ahead": "Rough surface ahead.",
    "hazard_ahead": "Hazard ahead.",
}

ATTENTION_TONE_HZ = 880.0
ATTENTION_TONE_SECONDS = 0.20
TONE_TO_SPEECH_GAP_SECONDS = 0.06
TAIL_SILENCE_SECONDS = 0.05
MAX_CLIP_SECONDS = 1.5


def tone(freq, seconds, amplitude=0.6, fade=0.01):
    n = int(RATE * seconds)
    fade_n = max(1, int(RATE * fade))
    out = []
    for i in range(n):
        env = 1.0
        if i < fade_n:
            env = i / fade_n
        elif i > n - fade_n:
            env = (n - i) / fade_n
        out.append(amplitude * env * math.sin(2 * math.pi * freq * i / RATE))
    return out


def silence(seconds):
    return [0.0] * int(RATE * seconds)


def write_wav(path, samples):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        frames = bytearray()
        for s in samples:
            v = max(-1.0, min(1.0, s))
            frames += struct.pack("<h", int(v * 32767))
        w.writeframes(bytes(frames))


def read_wav_mono_44100(path):
    """Reads a 16-bit PCM WAV and returns float samples at 44.1 kHz mono (naive resample)."""
    with wave.open(path, "rb") as w:
        ch = w.getnchannels()
        width = w.getsampwidth()
        rate = w.getframerate()
        raw = w.readframes(w.getnframes())
    if width != 2:
        sys.exit(f"{path}: expected 16-bit PCM, got {width * 8}-bit")
    count = len(raw) // 2
    ints = struct.unpack("<%dh" % count, raw)
    mono = []
    for i in range(0, count, ch):
        mono.append(sum(ints[i:i + ch]) / ch / 32768.0)
    if rate == RATE:
        return mono
    out_n = int(len(mono) * RATE / rate)
    return [mono[min(len(mono) - 1, int(i * rate / RATE))] for i in range(out_n)]


def trim_silence(samples, threshold=0.01):
    start = 0
    end = len(samples)
    while start < end and abs(samples[start]) < threshold:
        start += 1
    while end > start and abs(samples[end - 1]) < threshold:
        end -= 1
    return samples[start:end]


def normalise(samples, peak=0.9):
    m = max((abs(s) for s in samples), default=0.0)
    if m == 0:
        return samples
    g = peak / m
    return [s * g for s in samples]


def speak_say(text, out_wav, voice, rate_wpm):
    cmd = ["say", "-o", out_wav, "--file-format=WAVE", "--data-format=LEI16@44100"]
    if voice:
        cmd += ["-v", voice]
    if rate_wpm:
        cmd += ["-r", str(rate_wpm)]
    cmd.append(text)
    subprocess.run(cmd, check=True)


def speak_piper(text, out_wav, model, length_scale):
    piper = shutil.which("piper") or os.path.expanduser("~/.local/bin/piper")
    cmd = [piper, "-m", model, "-f", out_wav, "--length-scale", str(length_scale)]
    subprocess.run(cmd, input=text.encode(), check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--engine", choices=["say", "piper", "none"], default="say" if sys.platform == "darwin" else "piper")
    ap.add_argument("--voice", default="Samantha", help="macOS voice for --engine say")
    ap.add_argument("--rate", type=int, default=190, help="words per minute for --engine say")
    ap.add_argument("--piper-model", default="/tmp/piper/en_US-lessac-medium.onnx")
    ap.add_argument("--piper-length-scale", type=float, default=0.85)
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "..", "MotoHazardAlert", "Resources", "Audio"))
    args = ap.parse_args()

    out_dir = os.path.abspath(args.out)
    os.makedirs(out_dir, exist_ok=True)

    attention = tone(ATTENTION_TONE_HZ, ATTENTION_TONE_SECONDS)
    write_wav(os.path.join(out_dir, "tone_attention.wav"), attention + silence(TAIL_SILENCE_SECONDS))

    # Report confirmation: two rising blips, clearly different from the alert tone.
    confirm = tone(1320.0, 0.07, amplitude=0.7) + silence(0.04) + tone(1760.0, 0.09, amplitude=0.7) + silence(TAIL_SILENCE_SECONDS)
    write_wav(os.path.join(out_dir, "tone_report_confirm.wav"), confirm)

    with tempfile.TemporaryDirectory() as tmp:
        for name, phrase in PHRASES.items():
            speech_path = os.path.join(tmp, name + "_speech.wav")
            if args.engine == "say":
                speak_say(phrase, speech_path, args.voice, args.rate)
                speech = read_wav_mono_44100(speech_path)
            elif args.engine == "piper":
                speak_piper(phrase, speech_path, args.piper_model, args.piper_length_scale)
                speech = read_wav_mono_44100(speech_path)
            else:
                speech = silence(0.8)

            speech = normalise(trim_silence(speech))
            clip = attention + silence(TONE_TO_SPEECH_GAP_SECONDS) + speech + silence(TAIL_SILENCE_SECONDS)
            seconds = len(clip) / RATE
            flag = "" if seconds <= MAX_CLIP_SECONDS else "  <-- OVER 1.5 s, speak faster (--rate / --piper-length-scale)"
            print(f"{name:24s} {seconds:5.2f} s{flag}")
            write_wav(os.path.join(out_dir, name + ".wav"), clip)

    print(f"Written to {out_dir}")


if __name__ == "__main__":
    main()
