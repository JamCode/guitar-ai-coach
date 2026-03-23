"""Merge two ID card images vertically: top = front, bottom = back."""
from pathlib import Path

from PIL import Image

ASSETS = Path(
    r"C:\Users\wanghan\.cursor\projects\d-guitar-ai-coach\assets"
)
FRONT = ASSETS / (
    "c__Users_wanghan_AppData_Roaming_Cursor_User_workspaceStorage_33683eee0055714bcf51aefeabc2b5cd_images______"
    "20260323140918_81_2-22d32ef7-a41d-4adc-845c-b98e0164529b.png"
)
BACK = ASSETS / (
    "c__Users_wanghan_AppData_Roaming_Cursor_User_workspaceStorage_33683eee0055714bcf51aefeabc2b5cd_images______"
    "20260323140921_82_2-266112ca-68e6-45a8-80f7-a587cf1e396e.png"
)
OUT = Path(__file__).resolve().parents[1] / "id-card-merged.png"
DIVIDER_PX = 118  # ~1cm at 300 DPI


def resize_to_width(im: Image.Image, width: int) -> Image.Image:
    h = max(1, int(im.height * width / im.width))
    return im.resize((width, h), Image.Resampling.LANCZOS)


def main() -> None:
    top = Image.open(FRONT).convert("RGB")
    bottom = Image.open(BACK).convert("RGB")
    w = max(top.width, bottom.width)
    top = resize_to_width(top, w)
    bottom = resize_to_width(bottom, w)
    h = top.height + DIVIDER_PX + bottom.height
    merged = Image.new("RGB", (w, h), (255, 255, 255))
    merged.paste(top, (0, 0))
    merged.paste(bottom, (0, top.height + DIVIDER_PX))
    merged.save(OUT, format="PNG", optimize=True)
    print(OUT)


if __name__ == "__main__":
    main()
