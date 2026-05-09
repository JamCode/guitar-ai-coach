# iOS Stem Separation Model

This directory contains a locally generated Core ML package for 2-stem vocal/accompaniment separation.

## Files

- `stemseparation.mlpackage`: Core ML `mlProgram` package for iOS 17+.
- `source_onnx/vocals.onnx`: downloaded source ONNX model.
- `source_onnx/accompaniment.onnx`: downloaded source ONNX model.
- `source_onnx/manifest.json`: source repository, revision, file sizes, and SHA-256 checksums.

## Source

- Source model family: Deezer Spleeter 2-stem vocals/accompaniment.
- ONNX distribution: `csukuangfj/sherpa-onnx-spleeter-2stems`
- Hugging Face revision: `7001ba316a615cacddb3f9ef3ec416661a277e26`
- Upstream docs: https://k2-fsa.github.io/sherpa/onnx/source-separation/models.html
- Upstream Spleeter repository: https://github.com/deezer/spleeter

The selected sherpa-onnx model is documented as coming from Deezer Spleeter and supports the 2-stem model. The Deezer Spleeter repository is MIT licensed. The Hugging Face conversion repo itself does not expose a separate license field, so treat the license basis as upstream Spleeter MIT plus the public sherpa-onnx conversion provenance.

## Core ML Model

- Model path: `stemseparation.mlpackage`
- Core ML type: `mlProgram`
- Minimum deployment target used during conversion: iOS 17
- Compute units requested during conversion: `ALL` (Neural Engine / GPU / CPU eligible; actual placement is decided by Core ML at runtime)
- Input name: `x`
- Input dtype: `Float32`
- Input shape: `[2, 1, 512, 1024]`
- Output name: `var_841`
- Output dtype: `Float16`
- Output shape: `[2, 2, 1, 512, 1024]`
- Output stem order:
  - index `0`: vocals mask
  - index `1`: accompaniment mask

## Audio Contract

This model is frequency-domain, not direct waveform-in/waveform-out.

- Decode audio to stereo.
- Resample to `44100 Hz`.
- If source is mono, duplicate to stereo.
- If source has more than 2 channels, keep the first 2 channels.
- Pad waveform with `4096` samples at the end before STFT.
- STFT:
  - `n_fft = 4096`
  - `hop_length = 1024`
  - `window = Hann(4096), periodic = true`
  - `center = false`
  - `onesided = true`
- Build model input from STFT magnitude:
  - Original complex STFT shape is `[2, 2049, frames]`.
  - Permute to `[frames, 2049, 2]`.
  - Keep the first `1024` frequency bins.
  - Pad frames to a multiple of `512`.
  - For one model call, use one split of `512` frames.
  - Final input shape is `[2, 1, 512, 1024]`.
- Postprocess:
  - Read output masks in order `0=vocals`, `1=accompaniment`.
  - Convert output to Float32 if convenient.
  - For each stem, reshape mask back to STFT layout.
  - Pad frequency bins from `1024` back to `2049`.
  - Trim padded frames back to the original STFT frame count.
  - Multiply mask by the original complex STFT.
  - Run inverse STFT with the same FFT, hop, and Hann window.
  - Apply the Spleeter/sherpa scale factor `2 / 3`.

## Download Verification

Downloaded ONNX files were verified by exact byte size and SHA-256:

- `vocals.onnx`
  - size: `39318336`
  - sha256: `bdc16ab6bf6117ddd4842c19e80e40e2be188fc555295064d424616b0224ac97`
- `accompaniment.onnx`
  - size: `39318343`
  - sha256: `671ace17acd3720674a2bc14de32ac6292453dec20d9eb0ba4255d4ad8e3d8c0`

## Conversion Notes

Direct ONNX to Core ML conversion is no longer available in current `coremltools`. The generated package used this path:

1. Download ONNX from Hugging Face.
2. Repair ONNX node topological order for converter compatibility.
3. Convert ONNX graphs to Torch modules with `onnx2torch`.
4. Wrap vocals and accompaniment models into one Torch module.
5. Normalize the two model outputs into masks inside the wrapper with epsilon `1e-6` for Float16-safe silent-frame behavior.
6. Trace with fixed input shape `[2, 1, 512, 1024]`.
7. Convert traced Torch model to Core ML `mlProgram`.

The resulting model loads successfully with `coremltools` and reports the input/output contract above.
CPU-only smoke prediction with a zero tensor also succeeds and returns `var_841` with shape `[2, 2, 1, 512, 1024]`.
