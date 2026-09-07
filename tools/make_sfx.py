#!/usr/bin/env python3
"""Synthesise the game's sound effects.

Generated rather than sourced, for three reasons: no licensing to worry about
on something being shared as a public link, files small enough that they cost
nothing in a web build (the whole set is well under a megabyte), and the
ability to tune a sound to the thing it represents instead of settling for the
nearest match in a pack.

The palette is deliberately retro-synth to match the pixel art: square and saw
oscillators, filtered noise, short envelopes, a little detune and pitch sweep.
Nothing here is sampled.

Output: 22.05 kHz mono 16-bit WAV. That rate is plenty for short effects and
halves the size against 44.1.
"""

import os
import struct
import numpy as np

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "game", "assets", "sfx")

rng = np.random.default_rng(1234)  # fixed seed: regenerating gives the same set


# --- building blocks ------------------------------------------------------

def t(dur):
    return np.linspace(0.0, dur, int(SR * dur), endpoint=False)


def sine(freq, dur, phase=0.0):
    return np.sin(2 * np.pi * freq * t(dur) + phase)


def square(freq, dur, duty=0.5):
    ph = (freq * t(dur)) % 1.0
    return np.where(ph < duty, 1.0, -1.0)


def saw(freq, dur):
    return 2.0 * ((freq * t(dur)) % 1.0) - 1.0


def noise(dur):
    return rng.uniform(-1.0, 1.0, int(SR * dur))


def sweep(f0, f1, dur, kind="sine", curve=1.0):
    """Oscillator with the frequency swept f0 -> f1 (curve>1 = fast at first)."""
    n = int(SR * dur)
    k = np.linspace(0.0, 1.0, n, endpoint=False) ** curve
    freqs = f0 + (f1 - f0) * k
    phase = np.cumsum(2 * np.pi * freqs / SR)
    if kind == "sine":
        return np.sin(phase)
    if kind == "square":
        return np.sign(np.sin(phase))
    return 2.0 * ((phase / (2 * np.pi)) % 1.0) - 1.0


def env(sig, attack=0.005, decay=None, sustain=0.0, release=0.05):
    """Simple AD/ADSR shaped to the signal's own length."""
    n = len(sig)
    a = max(1, int(SR * attack))
    r = max(1, int(SR * release))
    d = max(1, int(SR * decay)) if decay is not None else max(1, n - a - r)
    e = np.zeros(n)
    a = min(a, n)
    e[:a] = np.linspace(0.0, 1.0, a)
    end_d = min(a + d, n)
    if end_d > a:
        e[a:end_d] = np.linspace(1.0, sustain if sustain > 0 else 0.0, end_d - a)
    if sustain > 0 and end_d < n:
        rel_start = max(end_d, n - r)
        e[end_d:rel_start] = sustain
        e[rel_start:] = np.linspace(sustain, 0.0, n - rel_start)
    return sig * e


def lowpass(sig, cutoff):
    """One-pole lowpass. Cheap, and enough to take the fizz off noise."""
    a = np.exp(-2.0 * np.pi * cutoff / SR)
    out = np.empty_like(sig)
    acc = 0.0
    for i, s in enumerate(sig):
        acc = (1 - a) * s + a * acc
        out[i] = acc
    return out


def fit(a, b):
    n = max(len(a), len(b))
    return (np.pad(a, (0, n - len(a))), np.pad(b, (0, n - len(b))))


def mix(*sigs):
    n = max(len(s) for s in sigs)
    out = np.zeros(n)
    for s in sigs:
        out[: len(s)] += s
    return out


def norm(sig, peak=0.85):
    m = np.max(np.abs(sig))
    return sig * (peak / m) if m > 0 else sig


def loopable(sig, fade=0.02):
    """Cross-fade the tail into the head so a looping stream has no click."""
    f = int(SR * fade)
    if f * 2 >= len(sig):
        return sig
    head, tail = sig[:f].copy(), sig[-f:].copy()
    ramp = np.linspace(0.0, 1.0, f)
    sig = sig[:-f]
    sig[:f] = head * ramp + tail * (1.0 - ramp)
    return sig


def write(name, sig, peak=0.85):
    sig = norm(np.clip(sig, -1.0, 1.0), peak)
    data = (sig * 32767).astype("<i2").tobytes()
    path = os.path.join(OUT, name + ".wav")
    with open(path, "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", 36 + len(data)) + b"WAVEfmt ")
        f.write(struct.pack("<IHHIIHH", 16, 1, 1, SR, SR * 2, 2, 16))
        f.write(b"data" + struct.pack("<I", len(data)) + data)
    print(f"  {name+'.wav':24s} {len(data)/1024:6.1f} KB  {len(sig)/SR:.2f}s")


# --- the sounds -----------------------------------------------------------

def build():
    os.makedirs(OUT, exist_ok=True)
    print("writing sfx to", os.path.normpath(OUT))

    # Machine gun: a short filtered noise crack over a fast downward blip. Kept
    # very short (70ms) because at a 0.13s fire rate anything longer overlaps
    # into mush.
    write("shoot_mg", mix(
        env(lowpass(noise(0.07), 3800), attack=0.001, release=0.03) * 0.7,
        env(sweep(900, 260, 0.07, "square", 2.0), attack=0.001, release=0.03) * 0.5,
    ), 0.55)

    # Double MG: same idea, two barrels, slightly detuned and a touch longer.
    a = env(sweep(820, 240, 0.085, "square", 2.0), attack=0.001, release=0.04)
    b = env(sweep(760, 210, 0.085, "square", 2.0), attack=0.002, release=0.04)
    write("shoot_double", mix(
        env(lowpass(noise(0.085), 3200), attack=0.001, release=0.04) * 0.6,
        a * 0.45, b * 0.45,
    ), 0.6)

    # Laser: a sustained, slightly unstable beam. Loops.
    dur = 0.5
    body = (saw(220, dur) * 0.35 + sine(440, dur) * 0.3 + sine(661, dur) * 0.15)
    wobble = 1.0 + 0.05 * np.sin(2 * np.pi * 31 * t(dur))
    write("laser_loop", loopable(body * wobble + lowpass(noise(dur), 900) * 0.12), 0.5)

    # Flamethrower: filtered noise with a slow roar under it. Loops.
    dur = 0.6
    roar = lowpass(noise(dur), 700) * 0.9 + lowpass(noise(dur), 180) * 0.5
    breath = 1.0 + 0.25 * np.sin(2 * np.pi * 7.5 * t(dur))
    write("flame_loop", loopable(roar * breath), 0.45)

    # Bullet landing on something. Tiny and bright so it reads over the gun.
    write("hit_enemy", mix(
        env(lowpass(noise(0.05), 6000), attack=0.001, release=0.03) * 0.8,
        env(sine(1400, 0.05), attack=0.001, release=0.03) * 0.3,
    ), 0.45)

    # Explosion: noise burst, a body thump, and a low tail.
    write("explosion", mix(
        env(lowpass(noise(0.45), 2200), attack=0.002, decay=0.35, release=0.1),
        env(sweep(180, 40, 0.4, "sine", 1.6), attack=0.002, release=0.2) * 0.8,
        env(lowpass(noise(0.45), 400), attack=0.02, release=0.3) * 0.5,
    ), 0.8)

    # Boss death: the same shape, longer and lower, with a falling siren.
    write("explosion_big", mix(
        env(lowpass(noise(1.2), 1600), attack=0.003, decay=0.9, release=0.3),
        env(sweep(140, 28, 1.1, "sine", 1.8), attack=0.003, release=0.4) * 0.9,
        env(sweep(700, 90, 1.0, "saw", 2.2), attack=0.05, release=0.4) * 0.35,
    ), 0.9)

    # Taking a hit: a short bitter buzz that falls away.
    write("player_hurt", mix(
        env(sweep(420, 120, 0.25, "square", 1.4), attack=0.002, release=0.15) * 0.7,
        env(lowpass(noise(0.25), 1500), attack=0.002, release=0.15) * 0.4,
    ), 0.6)

    # Jump: a quick rising blip. Short, because it fires constantly.
    write("jump", env(sweep(320, 720, 0.12, "square", 0.7),
                      attack=0.002, release=0.06), 0.4)

    # Pickup: bright three-note arpeggio, unmistakably a good thing.
    pick = np.concatenate([
        env(square(660, 0.06, 0.25), attack=0.002, release=0.03),
        env(square(880, 0.06, 0.25), attack=0.002, release=0.03),
        env(square(1320, 0.12, 0.25), attack=0.002, release=0.08),
    ])
    write("pickup", pick, 0.5)

    # Checkpoint: two clean notes, a fifth apart, with a little shimmer.
    cp = np.concatenate([
        env(mix(sine(587, 0.14), sine(880, 0.14) * 0.5), attack=0.005, release=0.09),
        env(mix(sine(880, 0.3), sine(1320, 0.3) * 0.4), attack=0.005, release=0.22),
    ])
    write("checkpoint", cp, 0.5)

    # Shield up: a rising hum that settles.
    write("shield_up", mix(
        env(sweep(180, 380, 0.3, "sine", 0.6), attack=0.02, release=0.15) * 0.8,
        env(sweep(360, 760, 0.3, "sine", 0.6), attack=0.02, release=0.15) * 0.3,
    ), 0.45)

    # Perfect deflect: a metallic ping. Distinct from everything else, because
    # it is the one thing worth noticing that you did.
    write("deflect", mix(
        env(sine(1760, 0.35), attack=0.001, release=0.3) * 0.7,
        env(sine(2640, 0.3), attack=0.001, release=0.26) * 0.4,
        env(sine(3520, 0.2), attack=0.001, release=0.18) * 0.2,
        env(lowpass(noise(0.06), 7000), attack=0.001, release=0.04) * 0.5,
    ), 0.6)

    # Enemy fire: duller and lower than the player's, so you can tell incoming
    # from outgoing without looking.
    write("enemy_shoot", mix(
        env(sweep(420, 150, 0.11, "saw", 1.8), attack=0.002, release=0.06) * 0.7,
        env(lowpass(noise(0.11), 1800), attack=0.002, release=0.06) * 0.4,
    ), 0.45)

    # Boss charging its beam: a rising whine, the audible half of the telegraph.
    write("boss_charge", mix(
        env(sweep(120, 900, 0.8, "saw", 1.5), attack=0.05, sustain=0.9, release=0.1) * 0.7,
        env(sweep(240, 1800, 0.8, "sine", 1.5), attack=0.05, sustain=0.9, release=0.1) * 0.3,
    ), 0.55)

    # Boss firing its beam. Loops while the sweep is live.
    dur = 0.5
    write("boss_laser_loop", loopable(mix(
        saw(90, dur) * 0.5, saw(181, dur) * 0.3, sine(45, dur) * 0.4,
        lowpass(noise(dur), 1200) * 0.25,
    )), 0.6)

    # Menu: a soft click, not a beep.
    write("menu_click", mix(
        env(lowpass(noise(0.04), 2500), attack=0.001, release=0.025) * 0.6,
        env(sine(520, 0.05), attack=0.001, release=0.035) * 0.5,
    ), 0.4)

    # Enemy destroyed: a short descending confirmation under the explosion.
    write("enemy_down", env(sweep(600, 180, 0.22, "square", 1.5),
                            attack=0.002, release=0.14), 0.4)


if __name__ == "__main__":
    build()
