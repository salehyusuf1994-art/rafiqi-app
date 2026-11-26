"""التحويل الطيفي في الأداة (numpy) مطابق لـ torch.stft / torch.istft المستخدمين في النموذج الأصلي"""
import sys
import numpy as np
import torch
from einops import rearrange

sys.path.insert(0, __file__.rsplit('tests', 1)[0])
from naqa import dsp  # noqa: E402

rng = np.random.default_rng(3)
l = (rng.standard_normal(dsp.CHUNK) * 0.1).astype(np.float32)
r = (rng.standard_normal(dsp.CHUNK) * 0.1).astype(np.float32)
inp, spec = dsp.model_input(l, r)

win = torch.hann_window(2048)
audio = torch.from_numpy(np.stack([l, r]))
st = torch.stft(audio, n_fft=2048, hop_length=441, win_length=2048, window=win, return_complex=True)
st = torch.view_as_real(st).reshape(1, 2, 1025, dsp.FRAMES, 2)
ref = rearrange(st, 'b s f t c -> b (f s) t c').numpy()
d1 = np.abs(inp - ref).max()
print('stft max diff', d1)

mask = (rng.standard_normal(inp.shape) * 0.5).astype(np.float32)
yl, yr = dsp.apply_mask(spec, mask)
y = torch.view_as_complex(torch.from_numpy(ref).contiguous()) * torch.view_as_complex(torch.from_numpy(mask).contiguous())
y = rearrange(y, 'b (f s) t -> (b s) f t', s=2)
y[:, 0] = 0
rec = torch.istft(y, n_fft=2048, hop_length=441, win_length=2048, window=win, length=dsp.CHUNK).numpy()
d2 = max(np.abs(yl - rec[0]).max(), np.abs(yr - rec[1]).max())
print('istft max diff', d2)
ok = d1 < 1e-3 and d2 < 1e-4
print('NAQA PARITY', 'PASS' if ok else 'FAIL')
sys.exit(0 if ok else 1)
