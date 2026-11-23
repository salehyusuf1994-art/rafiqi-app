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

FRAMES = 801


def safe_rmsnorm(self, x):
    m = x.abs().amax(dim=-1, keepdim=True).clamp(min=1e-8)
    y = x / m
    y = y / y.pow(2).sum(dim=-1, keepdim=True).sqrt().clamp(min=1e-12)
    return y * self.scale * self.gamma


class Core(torch.nn.Module):
    """BSRoformer.forward من بعد STFT حتى القناع"""
    def __init__(self, m):
        super().__init__()
        self.m = m

    def forward(self, spec):
        m = self.m
        x = rearrange(spec, 'b f t c -> b t (f c)')
        x = m.band_split(x)
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
        mask = m.mask_estimators[0](x)
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
    a = ap.parse_args()

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
    n = cfg['audio']['chunk_size']
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

        traced = torch.jit.trace(core, spec, check_trace=False)

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
