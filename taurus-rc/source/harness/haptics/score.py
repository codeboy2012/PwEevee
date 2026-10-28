# Scores build/haptics' events against onsets librosa finds, per Follows choice: precision, recall (of all the
# onsets, and of the stronger half) and F, matched one to one within 50 ms (mir_eval), and taps a second, each
# beside what taps at random times at the same rate would score.
#
#   python score.py <song.wav> <events.csv>
#
# The references: the onsets of the mix's percussive part (librosa's HPSS, what the analyzer was first tuned
# against), and, when demucs' stems lie beside the song as <song>.drums.wav, .bass.wav and .vocals.wav, the
# onsets of the drums, of the low end (drums and bass under 150 Hz, for Bass) and of the vocals.
# Needs numpy, scipy, soundfile, librosa and mir_eval.
import sys, os, numpy as np, soundfile as sf, librosa, mir_eval, scipy.signal as ss

SR, HOP, WINDOW = 22050, 256, 0.05

def mono(path):
    x, sr = sf.read(path, dtype='float32', always_2d=True)
    return librosa.resample(x.mean(1), orig_sr=sr, target_sr=SR)

def onsets(y):
    env = librosa.onset.onset_strength(y=y, sr=SR, hop_length=HOP)
    t = librosa.onset.onset_detect(onset_envelope=env, sr=SR, hop_length=HOP, units='time')
    return t, env[librosa.time_to_frames(t, sr=SR, hop_length=HOP)]

def score(ref, strength, taps, seconds):
    f, p, r = mir_eval.onset.f_measure(ref, taps, window=WINDOW)
    strong = ref[strength > np.median(strength)]
    rs = mir_eval.onset.f_measure(strong, taps, window=WINDOW)[2]
    rng = np.random.default_rng(1)
    chance = np.mean([mir_eval.onset.f_measure(ref, np.sort(rng.uniform(0, seconds, len(taps))), window=WINDOW)[1:] for _ in range(10)], 0)
    return f'{len(taps) / seconds:.2f}/s  P {p:.2f}  R {r:.2f}  R strong {rs:.2f}  F {f:.2f}   (at random: P {chance[0]:.2f} R {chance[1]:.2f})'

song, events = sys.argv[1], sys.argv[2]
rows = [line.strip().split(',') for line in open(events)]
kicks = np.array([float(r[1]) for r in rows if r[0] == 'K'])
snares = np.array([float(r[1]) for r in rows if r[0] == 'S'])
levels = np.array([float(r[2]) for r in rows if r[0] == 'L'])
drums = np.sort(np.concatenate([kicks, snares]))
mix = mono(song)
seconds = len(mix) / SR
refs = {}
_, percussive = librosa.effects.hpss(mix)
refs['the mix, percussive'] = onsets(percussive)
stem = lambda name: song[:-4] + f'.{name}.wav'
if all(os.path.exists(stem(n)) for n in ('drums', 'bass', 'vocals')):
    d, b = mono(stem('drums')), mono(stem('bass'))
    refs['the drums stem'] = onsets(d)
    refs['the low end (drums and bass under 150 Hz)'] = onsets(ss.sosfilt(ss.butter(4, 150, 'low', fs=SR, output='sos'), d + b))
    refs['the vocals stem'] = onsets(mono(stem('vocals')))
print(f'{os.path.basename(song)}: {seconds:.1f} s; the rumble over its start level for {np.mean(levels >= 0.05) * 100:.0f}% of the time, '
      f'its level {levels.mean():.3f} on average')
for name, (ref, strength) in refs.items():
    print(f'  against {name} ({len(ref) / seconds:.2f} onsets a second):')
    print(f'    Everything, Beat (kicks and snares)  {score(ref, strength, drums, seconds)}')
    print(f'    Bass (kicks)                         {score(ref, strength, kicks, seconds)}')
