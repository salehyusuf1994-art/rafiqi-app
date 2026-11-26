"""
نموذج BS-RoFormer (عزل الصوت البشري، viperx، رخصة MIT) بصيغة ONNX بالدقة الكاملة (fp32)
لأداة «نقاء» على الكمبيوتر.

نفس «القلب» المصدَّر للجوال (STFT/iSTFT خارج النموذج)، ونفس الأوزان، لكن بدقة fp32 بدل fp16:
    الدخل  spec: [1, 2050, 801, 2]  (1025 تردد × قناتان متداخلتان (f s)، 801 إطار، حقيقي/تخيلي)
    الخرج  mask: [1, 2050, 801, 2]

يتحقق قبل النشر:
  ١) القلب + STFT/iSTFT يطابق النموذج الأصلي
  ٢) النسخة المجمّعة تطابق الأصل
  ٣) ملف ONNX على onnxruntime يطابق النموذج الأصلي من البداية للنهاية
"""
import argparse, json, os, sys, time
import numpy as np
import torch
import yaml
from einops import rearrange

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from convert_bsroformer import Core, bsr, sha256  # noqa: E402

NAME = 'bsroformer-vocals-fp32.onnx'


def load(config, weights):
    cfg = yaml.load(open(config), Loader=yaml.FullLoader)
    mc = dict(cfg['model'])
    for k in ('multi_stft_resolutions_window_sizes', 'freqs_per_bands'):
        mc[k] = tuple(mc[k])
    model = bsr.BSRoformer(**mc)
    if weights.endswith('.safetensors'):
        from safetensors.torch import load_file
        sd = load_file(weights)
    else:
        sd = torch.load(weights, map_location='cpu')
    missing, unexpected = model.load_state_dict(sd, strict=False)
    missing = [k for k in missing if 'rotary' not in k and 'cached' not in k]
    assert not missing and not unexpected, f'weights do not match: {missing[:5]} {unexpected[:5]}'
    return model.eval()


def stft_spec(audio, n, frames):
    win = torch.hann_window(2048)
    st = torch.stft(audio.reshape(2, n), n_fft=2048, hop_length=441, win_length=2048, window=win, return_complex=True)
    st = torch.view_as_real(st).reshape(1, 2, 1025, frames, 2)
    return rearrange(st, 'b s f t c -> b (f s) t c'), win


def apply_mask(spec, mask, win, n):
    y = torch.view_as_complex(spec.contiguous()) * torch.view_as_complex(mask.contiguous())
    y = rearrange(y, 'b (f s) t -> (b s) f t', s=2)
    y[:, 0] = 0
    return torch.istft(y, n_fft=2048, hop_length=441, win_length=2048, window=win, length=n).reshape(1, 1, 2, n)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--config', required=True)
    ap.add_argument('--weights', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--frames', type=int, default=801)
    a = ap.parse_args()
    frames = a.frames
    os.makedirs(a.out, exist_ok=True)

    model = load(a.config, a.weights)
    torch.manual_seed(0)
    n = (frames - 1) * 441
    audio = torch.randn(1, 2, n) * 0.1
    with torch.no_grad():
        ref = model(audio)
        spec, win = stft_spec(audio, n, frames)
        core = Core(model).eval()
        mask = core(spec)
        err = (apply_mask(spec, mask, win, n) - ref).abs().max().item()
        print('core+stft vs model max abs err', err)
        assert err < 1e-3, 'core does not match the original model'
        grouped = Core(model, grouped=True).eval()
        mask_g = grouped(spec)
        gdiff = (mask_g - mask).abs().max().item()
        print('grouped max diff', gdiff, 'mask range', mask.abs().max().item())
        assert gdiff < 1e-3, 'grouped core differs'

        out = os.path.join(a.out, NAME)
        torch.onnx.export(grouped, (spec,), out, input_names=['spec'], output_names=['mask'],
                          opset_version=17, do_constant_folding=True)
    print('onnx size MB', os.path.getsize(out) / 1e6)

    import onnx
    onnx.checker.check_model(out)
    import onnxruntime as ort
    so = ort.SessionOptions()
    so.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
    s = ort.InferenceSession(out, so, providers=['CPUExecutionProvider'])
    x = spec.numpy().astype(np.float32)
    s.run(['mask'], {'spec': x})
    t = time.time()
    mo = s.run(['mask'], {'spec': x})[0]
    print('onnxruntime cpu seconds per 8 s chunk', round(time.time() - t, 2))
    d = float(np.abs(mo - mask_g.numpy()).max())
    print('onnx vs torch mask max diff', d)
    assert d < 1e-3, 'onnx mask differs'
    with torch.no_grad():
        e2e = (apply_mask(spec, torch.from_numpy(mo), win, n) - ref).abs().max().item()
    print('onnx end-to-end vs original model max abs err', e2e)
    assert e2e < 1e-3, 'onnx output differs from the original model'

    files = {NAME: {'sha256': sha256(out), 'size': os.path.getsize(out)}}
    json.dump(files, open(os.path.join(a.out, 'files.json'), 'w'), indent=1)
    print(json.dumps(files, indent=1))


if __name__ == '__main__':
    main()
