"""Write Finder layout without launching Finder (also works on CI)."""
import sys
from pathlib import Path

from ds_store import DSStore
from mac_alias import Alias


def main():
    volume = Path(sys.argv[1])
    app_name = sys.argv[2]
    background = volume / f"{app_name}.app" / "Contents" / "Resources" / "DMGBackground.tiff"
    options = {
        "viewOptionsVersion": 1,
        "backgroundType": 2,
        "backgroundColorRed": 1.0,
        "backgroundColorGreen": 1.0,
        "backgroundColorBlue": 1.0,
        "backgroundImageAlias": Alias.for_file(str(background)).to_bytes(),
        "gridOffsetX": 0.0,
        "gridOffsetY": 0.0,
        "gridSpacing": 100.0,
        "arrangeBy": "none",
        "showIconPreview": True,
        "showItemInfo": False,
        "labelOnBottom": True,
        "textSize": 14.0,
        "iconSize": 64.0,
    }
    with DSStore.open(str(volume / ".DS_Store"), "w+") as store:
        store["."]["bwsp"] = {
            "ShowStatusBar": False,
            "ShowTabView": False,
            "ShowToolbar": False,
            "ShowPathbar": False,
            "ShowSidebar": False,
            "ContainerShowSidebar": False,
            "WindowBounds": "{{120, 120}, {780, 480}}",
        }
        store["."]["icvp"] = options
        store["."]["vSrn"] = ("long", 1)
        store["."]["vstl"] = ("type", b"icnv")
        # Keep the portrait and its original credits unobscured.
        store[f"{app_name}.app"]["Iloc"] = (88, 155)
        store["Applications"]["Iloc"] = (650, 155)
        store["安装前必看.txt"]["Iloc"] = (88, 295)

    with (volume / ".DS_Store").open("rb") as source:
        assert source.read(8) == b"\x00\x00\x00\x01Bud1"


if __name__ == "__main__":
    main()
