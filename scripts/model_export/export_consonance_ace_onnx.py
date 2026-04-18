#!/usr/bin/env python3
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import onnx
import torch


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export consonance-ACE checkpoint to ONNX")
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--frames", type=int, default=862, help="Dummy input frame count for export")
    return parser.parse_args()


class ExportWrapper(torch.nn.Module):
    def __init__(self, model: torch.nn.Module) -> None:
        super().__init__()
        self.model = model

    def forward(self, x: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
        outputs = self.model(x)
        return outputs["root"], outputs["bass"], outputs["onehot"]


def main() -> None:
    args = parse_args()
    repo_root = args.repo_root.resolve()
    sys.path.insert(0, str(repo_root))

    import gin  # noqa: WPS433
    from ACE.models.conformer_decomposed import ConformerDecomposedModel  # noqa: WPS433

    gin.parse_config_file(str(repo_root / "ACE/models/conformer_decomposed.gin"), skip_unknown=True)

    model = ConformerDecomposedModel.load_from_checkpoint(
        str(args.checkpoint.resolve()),
        vocabularies={"root": 13, "bass": 13, "onehot": 12},
        loss="consonance_decomposed",
        vocab_path=str(repo_root / "ACE/chords_vocab.joblib"),
        strict=False,
        map_location="cpu",
    )
    model.eval()

    wrapper = ExportWrapper(model)
    dummy = torch.randn(1, 1, 144, args.frames, dtype=torch.float32)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    torch.onnx.export(
        wrapper,
        dummy,
        str(args.output),
        export_params=True,
        opset_version=17,
        do_constant_folding=True,
        input_names=["features"],
        output_names=["root_logits", "bass_logits", "chord_logits"],
        dynamic_axes={
            "features": {0: "batch", 3: "frames"},
            "root_logits": {0: "batch", 1: "frames"},
            "bass_logits": {0: "batch", 1: "frames"},
            "chord_logits": {0: "batch", 1: "frames"},
        },
    )

    exported = onnx.load(str(args.output))
    onnx.checker.check_model(exported)
    print(f"Exported ONNX model to {args.output}")


if __name__ == "__main__":
    main()
