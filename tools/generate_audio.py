#!/usr/bin/env python3
"""Synthesises the Chomp Wars sound effects and background music.

Everything is generated from maths, so the game ships no third-party audio.
Standard library only. Run from anywhere:

    python3 tools/generate_audio.py

Writes 16-bit mono WAV files into assets/audio/.
"""

import math
import os
import random
import struct
import wave

RATE = 22050
HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.normpath(os.path.join(HERE, "..", "assets", "audio"))


def midi_hz(note: int) -> float:
    return 440.0 * 2.0 ** ((note - 69) / 12.0)


def write_wav(name: str, samples: list[float]) -> None:
    peak = max(1e-9, max(abs(s) for s in samples))
    scale = 0.8 / peak
    path = os.path.join(OUT_DIR, name)
    with wave.open(path, "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(RATE)
        frames = bytearray()
        for s in samples:
            frames += struct.pack("<h", int(max(-1.0, min(1.0, s * scale)) * 32767))
        wav.writeframes(bytes(frames))
    print(f"wrote {path} ({len(samples) / RATE:.2f} s)")


def loop_track(chords: list[tuple[int, ...]], seg: float, step: float, pad_gain: float,
               arp_gain: float, decay: float, arp_octaves: bool = True) -> list[float]:
    """A loop of chords, each with a sine-windowed pad and a plucked arpeggio.

    Each chord's pad fades in and out with a sine window, so the loop joins smoothly.
    Each chord lasts `seg` seconds and the arpeggio steps every `step` seconds.
    """
    seg_n = int(seg * RATE)
    out = [0.0] * (seg_n * len(chords))
    for ci, chord in enumerate(chords):
        start = ci * seg_n
        for k in range(seg_n):
            t = k / RATE
            window = math.sin(math.pi * k / seg_n)
            pad = sum(math.sin(2 * math.pi * midi_hz(m) * t) for m in chord) / len(chord)
            out[start + k] += pad_gain * window * pad
        step_n = int(step * RATE)
        for j in range(int(seg / step)):
            octave = 12 if arp_octaves and (j // len(chord)) % 2 else 0
            note = chord[j % len(chord)] + octave
            freq = midi_hz(note)
            for k in range(int(step_n * 0.95)):
                idx = start + j * step_n + k
                if idx >= len(out) or j * step_n + k >= seg_n:
                    break
                t = k / RATE
                env = math.exp(-decay * t)
                out[idx] += arp_gain * env * (math.sin(2 * math.pi * freq * t)
                                              + 0.3 * math.sin(2 * math.pi * 2 * freq * t))
    return out


def starlight() -> list[float]:
    """Starlight: a slow, airy 16 s loop (Dm, Bb, F, C) with long pads and a sparse arpeggio."""
    return loop_track([(50, 53, 57), (58, 62, 65), (53, 57, 60), (48, 52, 55)],
                      seg=4.0, step=0.5, pad_gain=0.20, arp_gain=0.07, decay=3.5)


def add_tone(out: list[float], start_s: float, dur: float, freq_of, amp: float,
             vib_depth: float = 0.012, attack: float = 0.25, release: float = 0.6) -> None:
    """Adds one sustained tone with a slow vibrato, a fade-in and a fade-out.

    freq_of(u) gives the frequency at normalised time u (0 to 1) through the note.
    """
    start = int(start_s * RATE)
    n = int(dur * RATE)
    phase = 0.0
    for k in range(n):
        idx = start + k
        if idx >= len(out):
            break
        t = k / RATE
        u = t / dur
        vib = 1.0 + vib_depth * math.sin(2 * math.pi * 5.5 * t)
        phase += 2 * math.pi * freq_of(u) * vib / RATE
        env = min(1.0, t / attack, (dur - t) / release)
        out[idx] += amp * max(env, 0.0) * (math.sin(phase) + 0.2 * math.sin(2 * phase))


def extra_terrestrial() -> list[float]:
    """Extra Terrestrial: a 16 s loop of eerie, detuned pads (Dm, Bb, F, C) with a wavering theremin line."""
    pads = loop_track([(50, 57, 62), (46, 53, 58), (53, 60, 65), (48, 55, 60)],
                      seg=4.0, step=2.0, pad_gain=0.14, arp_gain=0.0, decay=1.0, arp_octaves=False)
    # (start s, length s, MIDI note) for the theremin line. Every note ends before the loop does.
    line = [(0.0, 2.2, 74), (2.6, 1.2, 77), (4.2, 2.4, 72), (7.2, 1.4, 70),
            (8.8, 2.4, 69), (11.6, 1.6, 65), (13.6, 2.2, 67)]
    for start_s, dur, note in line:
        target = midi_hz(note)
        # The pitch glides up into the note over the first few percent of its length.
        add_tone(pads, start_s, dur, lambda u, f=target: f * (1.0 - 0.05 * max(0.0, 1.0 - u * 6.0)),
                 amp=0.13)
    return pads


def hard_rock() -> list[float]:
    """Hard Rock: an 8 s loop at 120 BPM. Distorted, palm-muted power chords, a kick, snare and hi-hat."""
    beat = 0.5
    bar = 4 * beat
    bars = 4
    total = int(bars * bar * RATE)
    out = [0.0] * total
    rng = random.Random(7)

    def put(start_s: float, values) -> None:
        start = int(start_s * RATE)
        for k, value in enumerate(values):
            if start + k >= total:
                break
            out[start + k] += value

    # Power chords (root, fifth, octave), one per bar: E, C, D, B.
    roots = [40, 36, 38, 35]
    for bar_index, root in enumerate(roots):
        for eighth in range(8):
            t0 = bar_index * bar + eighth * beat / 2
            dur = beat / 2 * 0.85
            n = int(dur * RATE)
            chug = []
            for k in range(n):
                t = k / RATE
                # A stack of harmonics approximates a sawtooth, then a hard clip adds the grit.
                wave_sum = 0.0
                for note in (root, root + 7, root + 12):
                    f = midi_hz(note)
                    for h in range(1, 9):
                        wave_sum += math.sin(2 * math.pi * f * h * t) / h
                clipped = math.tanh(3.0 * wave_sum)
                env = min(1.0, t / 0.005) * math.exp(-9.0 * t)
                chug.append(0.16 * env * clipped)
            put(t0, chug)

    # Drums: kick on beats 1 and 3, snare on 2 and 4, eighth-note hi-hat.
    for bar_index in range(bars):
        for b in range(4):
            t = bar_index * bar + b * beat
            if b in (0, 2):
                n = int(0.22 * RATE)
                kick = []
                for k in range(n):
                    tk = k / RATE
                    f = 45.0 + 95.0 * math.exp(-30.0 * tk)
                    kick.append(0.55 * math.exp(-16.0 * tk) * math.sin(2 * math.pi * f * tk))
                put(t, kick)
            if b in (1, 3):
                n = int(0.18 * RATE)
                snare = []
                for k in range(n):
                    tk = k / RATE
                    noise = rng.uniform(-1.0, 1.0)
                    tone = math.sin(2 * math.pi * 190.0 * tk)
                    snare.append(0.32 * math.exp(-24.0 * tk) * (noise + 0.5 * tone))
                put(t, snare)
        for e in range(8):
            t = bar_index * bar + e * beat / 2
            n = int(0.05 * RATE)
            prev = 0.0
            hat = []
            for k in range(n):
                tk = k / RATE
                noise = rng.uniform(-1.0, 1.0)
                hat.append(0.09 * math.exp(-70.0 * tk) * (noise - prev))  # high-passed noise
                prev = noise
            put(t, hat)
    return out


def collect() -> list[float]:
    """Bright two-note chime for collecting an orb."""
    dur = 0.5
    n = int(dur * RATE)
    out = []
    for k in range(n):
        t = k / RATE
        freq = midi_hz(88) if t < 0.12 else midi_hz(93)  # E6 then A6
        env = math.exp(-8.0 * t)
        out.append(env * (math.sin(2 * math.pi * freq * t)
                          + 0.25 * math.sin(2 * math.pi * 2 * freq * t)))
    return out


def jump() -> list[float]:
    """Short upward blip for jumping."""
    dur = 0.22
    n = int(dur * RATE)
    out = []
    phase = 0.0
    for k in range(n):
        t = k / RATE
        freq = 320.0 + 520.0 * (t / dur)
        phase += 2 * math.pi * freq / RATE
        env = math.sin(math.pi * k / n) ** 0.5
        out.append(env * math.sin(phase))
    return out


def laser() -> list[float]:
    """Short zap for firing: a fast downward sweep with a little buzz."""
    dur = 0.28
    n = int(dur * RATE)
    out = []
    phase = 0.0
    for k in range(n):
        t = k / RATE
        freq = 1400.0 * (300.0 / 1400.0) ** (t / dur)  # exponential sweep down
        phase += 2 * math.pi * freq / RATE
        env = math.exp(-7.0 * t)
        out.append(env * (math.sin(phase) + 0.3 * math.copysign(1.0, math.sin(2 * phase))))
    return out


def chomp() -> list[float]:
    """A wet two-bite chomp: the mouth snaps shut, then a second, softer crunch."""
    dur = 0.36
    n = int(dur * RATE)
    rng = random.Random(3)
    out = [0.0] * n
    for bite_start, strength in ((0.0, 1.0), (0.13, 0.6)):
        start = int(bite_start * RATE)
        for k in range(int(0.09 * RATE)):
            idx = start + k
            if idx >= n:
                break
            t = k / RATE
            # A low thump for the jaw plus a burst of filtered noise for the crunch.
            thump = math.sin(2 * math.pi * (180.0 * math.exp(-18.0 * t) + 70.0) * t)
            crunch = rng.uniform(-1.0, 1.0) * math.exp(-45.0 * t)
            out[idx] += strength * math.exp(-22.0 * t) * (0.7 * thump + 0.5 * crunch)
    return out


def explosion() -> list[float]:
    """Explosion: a noise burst that darkens as it fades, over a falling low thump."""
    dur = 0.9
    n = int(dur * RATE)
    rng = random.Random(11)
    out = []
    smooth = 0.0
    phase = 0.0
    for k in range(n):
        t = k / RATE
        noise = rng.uniform(-1.0, 1.0)
        smooth += 0.25 * (noise - smooth)  # low-pass: the tail is duller than the start
        env = math.exp(-4.5 * t)
        freq = 120.0 * math.exp(-3.0 * t) + 35.0
        phase += 2 * math.pi * freq / RATE
        out.append(env * (0.8 * smooth + 0.9 * math.sin(phase)))
    return out


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    write_wav("starlight.wav.bin", starlight())
    write_wav("extra_terrestrial.wav.bin", extra_terrestrial())
    write_wav("hard_rock.wav.bin", hard_rock())
    write_wav("collect.wav.bin", collect())
    write_wav("jump.wav.bin", jump())
    write_wav("laser.wav.bin", laser())
    write_wav("explosion.wav.bin", explosion())
    write_wav("chomp.wav.bin", chomp())


if __name__ == "__main__":
    main()
