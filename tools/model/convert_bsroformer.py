"""
تحويل نموذج BS-RoFormer (عزل الصوت البشري، viperx، رخصة MIT) إلى Core ML لرفيقي.

النموذج يأخذ طيف STFT ويُرجع قناعًا مركّبًا؛ التحويل الطيفي (STFT/iSTFT) يتم داخل التطبيق (vDSP)
لأن Core ML لا يدعمه. لذلك نصدّر «القلب» فقط:
    الدخل  spec: [1, 2050, 801, 2]  (1025 تردد × قناتان متداخلتان (f s)، 801 إطار، حقيقي/تخيلي)
    الخرج  mask: [1, 2050, 801, 2]
مطابق لـ BSRoformer.forward في ZFTurbo/Music-Source-Separation-Training (MIT).

الدقة: أوزان fp16. RMSNorm يحسب مجموع المربعات فيتجاوز حد fp16 مع القيم الكبيرة، فيُستبدل
بصيغة مكافئة رياضيًا آمنة (تُقسم القيم على أكبرها أولًا).
"""
import argparse, hashlib, json, os, sys
import numpy as np
import torch
import torch.nn.functional as F
import yaml
from einops import rearrange, pack, unpack

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from models.bs_roformer import bs_roformer as bsr  # noqa: E402

FRAMES = 801  # يُغيَّر بـ --frames


def safe_rmsnorm(self, x):
    m = x.abs().amax(dim=-1, keepdim=True).clamp(min=1e-8)
    y = x / m
    y = y / y.pow(2).sum(dim=-1, keepdim=True).sqrt().clamp(min=1e-12)
    return y * self.scale * self.gamma


def groups_of(dims):
    """النطاقات المتتالية ذات العرض نفسه: [(البداية، العدد، العرض)]"""
    out, i = [], 0
    while i < len(dims):
        j = i
        while j < len(dims) and dims[j] == dims[i]:
            j += 1
        out.append((i, j - i, dims[i]))
        i = j
    return out


class GroupedBandSplit(torch.nn.Module):
    """BandSplit نفسه رياضيًا: ٦٢ عملية صغيرة ← ٧ عمليات مجمّعة (الأسرع على المحرك العصبي وكرت الشاشة)"""
    def __init__(self, bs):
        super().__init__()
        dims = list(bs.dim_inputs)
        self.groups = groups_of(dims)
        self.g = torch.nn.ParameterList()
        self.w = torch.nn.ParameterList()
        self.b = torch.nn.ParameterList()
        for (s0, n, d) in self.groups:
            nets = [bs.to_features[k] for k in range(s0, s0 + n)]
            self.g.append(torch.nn.Parameter(torch.stack([net[0].gamma for net in nets]) * (d ** 0.5)))      # [n, d]
            self.w.append(torch.nn.Parameter(torch.stack([net[1].weight.t() for net in nets])))           # [n, d, e]
            self.b.append(torch.nn.Parameter(torch.stack([net[1].bias for net in nets])))                 # [n, e]

    def forward(self, x):
        outs, off = [], 0
        for k, (s0, n, d) in enumerate(self.groups):
            xg = x[..., off:off + n * d].reshape(x.shape[0], x.shape[1], n, d)
            off += n * d
            m = xg.abs().amax(dim=-1, keepdim=True).clamp(min=1e-8)
            y = xg / m
            y = y / y.pow(2).sum(dim=-1, keepdim=True).sqrt().clamp(min=1e-12)
            y = y * self.g[k]
            outs.append(torch.einsum('btnd,nde->btne', y, self.w[k]) + self.b[k])
        return torch.cat(outs, dim=2)


class GroupedMaskEstimator(torch.nn.Module):
    """MaskEstimator نفسه رياضيًا: MLP لكل نطاق ← دفعات مجمّعة"""
    def __init__(self, me):
        super().__init__()
        dims = list(me.dim_inputs)
        self.groups = groups_of(dims)
        self.w1, self.b1, self.w2, self.b2 = (torch.nn.ParameterList() for _ in range(4))
        for (s0, n, d) in self.groups:
            mlps = [me.to_freqs[k][0] for k in range(s0, s0 + n)]   # Sequential(Linear, Tanh, Linear)
            self.w1.append(torch.nn.Parameter(torch.stack([m[0].weight.t() for m in mlps])))
            self.b1.append(torch.nn.Parameter(torch.stack([m[0].bias for m in mlps])))
            self.w2.append(torch.nn.Parameter(torch.stack([m[2].weight.t() for m in mlps])))
            self.b2.append(torch.nn.Parameter(torch.stack([m[2].bias for m in mlps])))

    def forward(self, x):          # x: [b, t, 62, dim]
        outs = []
        for k, (s0, n, d) in enumerate(self.groups):
            xg = x[:, :, s0:s0 + n]
            h = torch.tanh(torch.einsum('btne,neh->btnh', xg, self.w1[k]) + self.b1[k])
            o = torch.einsum('btnh,nho->btno', h, self.w2[k]) + self.b2[k]      # [b, t, n, 2d]
            o = o[..., :d] * torch.sigmoid(o[..., d:])                         # GLU
            outs.append(o.reshape(o.shape[0], o.shape[1], n * d))
        return torch.cat(outs, dim=-1)


class Core(torch.nn.Module):
    """BSRoformer.forward من بعد STFT حتى القناع"""
    def __init__(self, m, grouped=False):
        super().__init__()
        self.m = m
        self.split = GroupedBandSplit(m.band_split) if grouped else m.band_split
        self.mask = GroupedMaskEstimator(m.mask_estimators[0]) if grouped else m.mask_estimators[0]

    def forward(self, spec):
        m = self.m
        x = rearrange(spec, 'b f t c -> b t (f c)')
        x = self.split(x)
        for block in m.layers:
            time_t, freq_t = block[-2], block[-1]
            x = rearrange(x, 'b t f d -> b f t d')
            x, ps = pack([x], '* t d')
            x = time_t(x)
            x, = unpack(x, ps, '* t d')
            x = rearrange(x, 'b f t d -> b t f d')
            x, ps = pack([x], '* f d')
            x = freq_t(x)
            x, = unpack(x, ps, '* f d')
        x = m.final_norm(x)
        mask = self.mask(x)
        return rearrange(mask, 'b t (f c) -> b f t c', c=2)


def sha256(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''):
            h.update(b)
    return h.hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--config', required=True)
    ap.add_argument('--weights', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--frames', type=int, default=801)
    a = ap.parse_args()
    global FRAMES
    FRAMES = a.frames

    cfg = yaml.load(open(a.config), Loader=yaml.FullLoader)
    mc = dict(cfg['model'])
    for k in ('multi_stft_resolutions_window_sizes', 'freqs_per_bands'):
        mc[k] = tuple(mc[k])
    model = bsr.BSRoformer(**mc)
    if a.weights.endswith('.safetensors'):
        from safetensors.torch import load_file
        sd = load_file(a.weights)
    else:
        sd = torch.load(a.weights, map_location='cpu')
    missing, unexpected = model.load_state_dict(sd, strict=False)
    missing = [k for k in missing if 'rotary' not in k and 'cached' not in k]
    print('missing', missing[:10], 'unexpected', unexpected[:10])
    assert not missing and not unexpected, 'weights do not match the architecture'
    model.eval()

    # مرجع بالدقة الكاملة: النموذج الأصلي على مقطع عشوائي، ثم نفس المقطع عبر القلب + STFT/iSTFT
    torch.manual_seed(0)
    # قطعة أقصر من ٨ ثوانٍ تقلل ذاكرة الانتباه (تتناسب مع مربع الطول) فتعمل على معالج الجوال الرسومي
    n = (FRAMES - 1) * 441
    audio = torch.randn(1, 2, n) * 0.1
    with torch.no_grad():
        ref = model(audio)
        win = torch.hann_window(2048)
        st = torch.stft(audio.reshape(2, n), n_fft=2048, hop_length=441, win_length=2048, window=win, return_complex=True)
        st = torch.view_as_real(st).reshape(1, 2, 1025, FRAMES, 2)
        spec = rearrange(st, 'b s f t c -> b (f s) t c')
        core = Core(model).eval()
        mask = core(spec)
        y = torch.view_as_complex(spec.contiguous()) * torch.view_as_complex(mask.contiguous())
        y = rearrange(y, 'b (f s) t -> (b s) f t', s=2)
        y[:, 0] = 0
        rec = torch.istft(y, n_fft=2048, hop_length=441, win_length=2048, window=win, length=n).reshape(1, 1, 2, n)
        err = (rec - ref).abs().max().item()
        print('core+stft vs model max abs err', err)
        assert err < 1e-3, 'core does not match the original model'

        # RMSNorm الآمن لا يغيّر الناتج
        bsr.RMSNorm.forward = safe_rmsnorm
        mask2 = core(spec)
        print('safe norm max diff', (mask2 - mask).abs().max().item())
        assert (mask2 - mask).abs().max().item() < 1e-3

        # النسخة المجمّعة مطابقة للأصل (الأوزان نفسها، ترتيب حساب مختلف فقط)
        grouped = Core(model, grouped=True).eval()
        mask3 = grouped(spec)
        gdiff = (mask3 - mask2).abs().max().item()
        print('grouped max diff', gdiff, 'mask range', mask2.abs().max().item())
        assert gdiff < 1e-3, 'grouped core differs'
        traced = torch.jit.trace(grouped, spec, check_trace=False)

    import coremltools as ct
    mlm = ct.convert(
        traced,
        inputs=[ct.TensorType(name='spec', shape=(1, 2050, FRAMES, 2), dtype=np.float32)],
        outputs=[ct.TensorType(name='mask', dtype=np.float32)],
        convert_to='mlprogram',
        minimum_deployment_target=ct.target.iOS18,
        compute_precision=ct.precision.FLOAT16,
    )
    mlm.short_description = 'BS-RoFormer vocals (viperx, MIT) — spectrogram mask core for Rafiqi'
    pkg = os.path.join(a.out, 'BSRoformer.mlpackage')
    mlm.save(pkg)
    files = {}
    for root, _, names in os.walk(pkg):
        for nm in names:
            p = os.path.join(root, nm)
            rel = os.path.relpath(p, pkg)
            files[rel] = {'sha256': sha256(p), 'size': os.path.getsize(p)}
    json.dump(files, open(os.path.join(a.out, 'files.json'), 'w'), indent=1, ensure_ascii=False)
    print(json.dumps(files, indent=1))


if __name__ == '__main__':
    main()
