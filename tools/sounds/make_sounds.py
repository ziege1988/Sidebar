# Erzeugt Rüdigers Geräusche (selbst synthetisiert, keine Aufnahmen) nach Resources/Sounds/*.wav
#   python3 tools/sounds/make_sounds.py
import pathlib, wave
import numpy as np

SR = 44100
OUT = pathlib.Path(__file__).resolve().parents[2] / 'Resources' / 'Sounds'
OUT.mkdir(parents=True, exist_ok=True)
rng = np.random.default_rng(7)

def t_axis(d): return np.arange(int(SR * d)) / SR

def envelope(n, attack, release):
    e = np.ones(n)
    a, r = int(SR * attack), int(SR * release)
    if a: e[:a] = np.linspace(0, 1, a) ** 1.5
    if r: e[-r:] = np.linspace(1, 0, r) ** 1.5
    return e

def bandpass(x, lo, hi):
    X = np.fft.rfft(x); f = np.fft.rfftfreq(len(x), 1 / SR)
    m = ((f >= lo) & (f <= hi)).astype(float)
    # weiche Flanken
    m = np.convolve(m, np.hanning(41) / np.hanning(41).sum(), mode='same')
    return np.fft.irfft(X * m, len(x))

def formant_gain(freq, formants):
    g = np.zeros_like(freq)
    for fc, bw, amp in formants:
        g += amp * np.exp(-0.5 * ((freq - fc) / bw) ** 2)
    return g + 0.02

def meow(d=0.62, f_start=520, f_peak=780, f_end=430, bright=1.0):
    """Miau: Grundton steigt und fällt, Vokal wandert von „i“ über „a“ zu „u“"""
    t = t_axis(d); n = len(t); u = t / d
    f0 = np.where(u < 0.32, f_start + (f_peak - f_start) * np.sin(u / 0.32 * np.pi / 2),
                  f_peak + (f_end - f_peak) * np.clip((u - 0.32) / 0.68, 0, 1) ** 1.3)
    f0 *= 1 + 0.012 * np.sin(2 * np.pi * 6 * t)            # leichtes Vibrato
    phase = 2 * np.pi * np.cumsum(f0) / SR
    # Formanten über die Zeit (i → a → u)
    F1 = np.interp(u, [0, .35, 1], [380, 900, 420]); F2 = np.interp(u, [0, .35, 1], [2300, 1450, 900])
    sig = np.zeros(n)
    for k in range(1, 14):
        fk = f0 * k
        g = formant_gain(fk, [(F1, 160, 1.0), (F2, 260, 0.6 * bright), (3200, 400, 0.25 * bright)])
        sig += g * np.sin(k * phase) / k ** 0.7
    breath = bandpass(rng.standard_normal(n), 1500, 6000) * 0.05
    sig = (sig + breath) * envelope(n, 0.05, 0.22)
    return sig

def mrrp(d=0.3):
    """kurzes, gerolltes Gurren (Nachrichten, Sprüche)"""
    s = meow(d, 430, 620, 520, bright=0.7)
    t = t_axis(d)
    return s * (0.6 + 0.4 * np.sin(2 * np.pi * 28 * t) ** 2)

def purr(d=2.2):
    t = t_axis(d); n = len(t)
    noise = bandpass(rng.standard_normal(n), 40, 420)
    pulses = 0.5 + 0.5 * np.sin(2 * np.pi * 25 * t) ** 6
    breath = 0.55 + 0.45 * np.sin(2 * np.pi * t / 1.1 - np.pi / 2) ** 2
    hum = 0.35 * np.sin(2 * np.pi * 50 * t + 0.3 * np.sin(2 * np.pi * 25 * t))
    return (noise * pulses * 1.8 + hum * pulses) * breath * envelope(n, 0.25, 0.4)

def hiss(d=0.7):
    t = t_axis(d); n = len(t)
    noise = bandpass(rng.standard_normal(n), 2200, 9000)
    e = envelope(n, 0.02, 0.45) * (1 + 0.15 * np.sin(2 * np.pi * 9 * t))
    return noise * e * 1.4

def chomp(d=1.4):
    t = t_axis(d); n = len(t); s = np.zeros(n)
    for start in [0.0, 0.22, 0.44, 0.66, 0.88]:
        i = int(start * SR); L = int(0.06 * SR)
        burst = bandpass(rng.standard_normal(L), 300, 2200) * envelope(L, 0.003, 0.05)
        s[i:i + L] += burst * (1.0 if start == 0 else 0.6)
    # Schluck: kurzer, fallender Ton
    i = int(1.12 * SR); L = int(0.14 * SR); tt = np.arange(L) / SR
    s[i:i + L] += 0.5 * np.sin(2 * np.pi * np.cumsum(np.linspace(320, 150, L)) / SR) * envelope(L, 0.01, 0.08)
    return s

def alarm(d=2.4):
    """kleines Weckerklingeln, danach ein empörtes Miau"""
    t = t_axis(1.5); n = len(t)
    bell = sum(a * np.sin(2 * np.pi * f * t) for f, a in [(2093, 1.0), (2794, 0.5), (4186, 0.35), (5274, 0.2)])
    trem = (np.sin(2 * np.pi * 16 * t) > 0).astype(float)
    trem = np.convolve(trem, np.ones(60) / 60, mode='same')
    ring = bell * trem * envelope(n, 0.01, 0.25) * 0.35
    m = meow(0.6, 600, 900, 480)
    out = np.zeros(int(SR * d)); out[:n] += ring; out[int(1.6 * SR):int(1.6 * SR) + len(m)] += m
    return out

def save(name, sig, level=0.55):
    sig = sig / (np.max(np.abs(sig)) + 1e-9) * level
    data = (sig * 32767).astype('<i2')
    with wave.open(str(OUT / f'{name}.wav'), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(data.tobytes())

save('meow', meow())
save('meow2', meow(0.5, 600, 850, 520))
save('mrrp', mrrp(), 0.45)
save('purr', purr(), 0.5)
save('hiss', hiss(), 0.4)
save('chomp', chomp(), 0.5)
save('alarm', alarm(), 0.5)
print('ok', sorted(p.name for p in OUT.glob('*.wav')))
