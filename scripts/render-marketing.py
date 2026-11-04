#!/usr/bin/env python3
"""Build shareable cards and two silent, captioned promo cuts from native UI captures.

Requires Pillow and ffmpeg. Run capture-marketing.py first. No stock footage or music.
"""
import json
import math
from pathlib import Path
import shutil
import subprocess
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "Marketing"
BG = "#F4F3EE"
INK = "#18201E"
MUTED = "#67716D"
BLUE = "#245BE8"
FONT = "/System/Library/Fonts/Supplemental/Arial.ttf"
BOLD = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
FPS = 24
DURATION = 24


def font(size, bold=False):
    return ImageFont.truetype(BOLD if bold else FONT, size)


def text(draw, position, copy, size, fill=INK, bold=False, spacing=10):
    draw.multiline_text(position, copy, font=font(size, bold), fill=fill, spacing=spacing)


def pill(draw, xy, copy, size=19):
    x, y = xy
    width = draw.textlength(copy, font=font(size, True)) + 34
    draw.rounded_rectangle((x, y, x + width, y + size + 24), radius=22, fill="#E3E9F8")
    text(draw, (x + 17, y + 10), copy, size, BLUE, True)


def brand(image, xy=(72, 48), size=46):
    icon = Image.open(OUT / "AppIcon.png").convert("RGBA").resize((size, size), Image.Resampling.LANCZOS)
    image.paste(icon, xy, icon)
    text(ImageDraw.Draw(image), (xy[0] + size + 13, xy[1] + 7), "Debagr", int(size * .64), bold=True)


def screenshot(image, name, box):
    x, y, w, h = box
    shot = Image.open(OUT / "screenshots" / f"{name}.png").convert("RGB")
    shot.thumbnail((w, h - 34), Image.Resampling.LANCZOS)
    sw, sh = shot.size
    x += (w - sw) // 2
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((x - 1, y, x + sw + 1, y + sh + 35), radius=15, fill="#D7DCD8")
    draw.rounded_rectangle((x, y, x + sw, y + sh + 34), radius=14, fill="#FFFFFF")
    draw.rectangle((x, y + 20, x + sw, y + 34), fill="#FFFFFF")
    for i, color in enumerate(("#EF7369", "#EDC45E", "#78BF87")):
        draw.ellipse((x + 14 + i * 18, y + 12, x + 23 + i * 18, y + 21), fill=color)
    text(draw, (x + sw // 2 - 55, y + 8), "Debagr Settings", 14, MUTED)
    image.paste(shot, (x, y + 34))


def footer(image, portrait=False):
    w, h = image.size
    d = ImageDraw.Draw(image)
    margin = 64 if portrait else 72
    d.line((margin, h - 92, w - margin, h - 92), fill="#D7DCD8", width=1)
    text(d, (margin, h - 69), "TECHNICAL PREVIEW  /  NATIVE UI WITH SAMPLE DATA", 16, MUTED, True)
    text(d, (margin, h - 43), "Wi-Fi + VPN required. Cellular-only is unsupported.", 17, MUTED)


def frame(scene, portrait=False):
    w, h = (1080, 1920) if portrait else (1920, 1080)
    image = Image.new("RGB", (w, h), BG)
    d = ImageDraw.Draw(image)
    margin = 64 if portrait else 72
    brand(image, (margin, 55), 52)
    pill(d, (w - (315 if portrait else 330), 60), "MACOS TECHNICAL PREVIEW", 16)
    title_size = 73 if portrait else 84
    top = 185 if portrait else 190
    titles = ["Your Mac stays home.\nYour next build\ncomes with you.",
              "Pair once.\nTake your\nnext build along.",
              "From prompt\nto pocket.",
              "Built for your\nnext build."]
    if not portrait:
        titles = ["Your Mac\nstays home.", "Pair once.\nGo remote.",
                  "From prompt\nto pocket.", "Your next build.\nWhere you are."]
    text(d, (margin, top), titles[scene], title_size, bold=True, spacing=6)
    if portrait:
        copy_y = [500, 500, 420, 420][scene]
        body = ["Ask your coding agent to deploy through\nyour paired Mac on another Wi-Fi network.",
                "Connect a paired iPhone through a private VPN.\nKeep its Mac running with Xcode and Debagr.",
                "Claude Code, Codex, or your terminal.\nCheck readiness. Install. Confirm launch.",
                "Native macOS app. Structured JSON CLI.\nOne managed remote device."][scene]
        text(d, (margin, copy_y), body, 31, MUTED, spacing=11)
        shot_name = "agent-tools-light" if scene in (2, 3) else "device-setup-light"
        screenshot(image, shot_name, (48, 690 if scene < 2 else 610, 984, 925))
        if scene == 3:
            pill(d, (margin, 1620), "HELP FUND THE NEXT MILESTONE", 25)
            text(d, (margin, 1690), "Follow development · Support testing", 29, BLUE, True)
    else:
        body = ["Your paired Mac runs the build.\nYour device comes with you.",
                "Your device. Another Wi-Fi network.\nConnected through your private VPN.",
                "Claude Code, Codex, or your terminal.\nCheck readiness. Install. Confirm launch.",
                "Native macOS app. JSON CLI.\nHelp fund compatibility and hardware testing."][scene]
        text(d, (margin, 445), body, 31, MUTED, spacing=12)
        pill(d, (margin, 585), ["REMOTE IPHONE DEPLOYMENT", "PAIR ONCE OVER USB", "AGENT PLUGINS INCLUDED", "FOLLOW · TEST · SPONSOR"][scene], 19)
        text(d, (margin, 687), "One paired Mac. One managed remote device.", 22, MUTED)
        screenshot(image, "agent-tools-light" if scene in (2, 3) else "device-setup-light",
                   (845, 163, 1000, 790))
    footer(image, portrait)
    # Keep copy inside the export's safe area, including social captions.
    assert w >= 1080 and h >= 630
    return image


def export_video(portrait=False):
    name = "debagr-promo-vertical" if portrait else "debagr-promo-landscape"
    size = (1080, 1920) if portrait else (1920, 1080)
    scenes = [frame(i, portrait) for i in range(4)]
    scenes[0].save(OUT / "video" / f"{name}-poster.jpg", quality=92)
    process = subprocess.Popen([
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-f", "rawvideo",
        "-pix_fmt", "rgb24", "-s", f"{size[0]}x{size[1]}", "-r", str(FPS), "-i", "-",
        "-an", "-c:v", "libx264", "-preset", "fast", "-crf", "20", "-pix_fmt", "yuv420p",
        "-movflags", "+faststart", "-metadata", "title=Debagr — From prompt to pocket",
        str(OUT / "video" / f"{name}.mp4")], stdin=subprocess.PIPE)
    try:
        for n in range(FPS * DURATION):
            t = n / FPS
            scene = min(3, int(t // 6))
            local = t % 6
            # A short crossfade between readable, full-resolution scenes.
            if scene and local < .45:
                alpha = (1 - math.cos(math.pi * local / .45)) / 2
                image = Image.blend(scenes[scene - 1], scenes[scene], alpha)
            else:
                image = scenes[scene].copy()
            d = ImageDraw.Draw(image)
            margin = 64 if portrait else 72
            available = size[0] - 2 * margin
            d.rounded_rectangle((margin, size[1] - 14, margin + int(available * (n + 1) / (FPS * DURATION)), size[1] - 9), radius=2, fill=BLUE)
            process.stdin.write(image.tobytes())
    finally:
        process.stdin.close()
    assert process.wait() == 0, "Video encoding failed"
    details = json.loads(subprocess.check_output([
        "ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json",
        str(OUT / "video" / f"{name}.mp4")]))
    video = details["streams"][0]
    assert (video["width"], video["height"]) == size
    assert abs(float(details["format"]["duration"]) - DURATION) < .1
    assert video["codec_name"] == "h264" and video["pix_fmt"] == "yuv420p"
    print(f"Verified {name}.mp4: {size[0]}x{size[1]}, {DURATION}s, H.264", flush=True)


def social_card(size, title, subtitle, destination):
    image = Image.new("RGB", size, BG)
    d = ImageDraw.Draw(image)
    brand(image, (64, 45), 56)
    text(d, (64, 165), title, 67 if size[0] == 1200 else 76, bold=True, spacing=4)
    text(d, (66, size[1] - 115), subtitle, 23, MUTED)
    d.rounded_rectangle((size[0] - 245, 175, size[0] - 60, 360), radius=42, fill="#E3E9F8")
    icon = Image.open(OUT / "AppIcon.png").convert("RGBA").resize((160, 160), Image.Resampling.LANCZOS)
    image.paste(icon, (size[0] - 233, 187), icon)
    image.save(destination, optimize=True)


def main():
    for path in ("video", "social", "sponsorship"):
        (OUT / path).mkdir(exist_ok=True)
    social_card((1200, 630), "Your Mac stays home.\nYour next build\ncomes with you.",
                "macOS technical preview · Paired Mac + Wi-Fi + private VPN", OUT / "social/launch-card.png")
    social_card((1200, 630), "Help the next\nbuild travel\nfurther.",
                "Support compatibility work, documentation, and hardware testing.", OUT / "sponsorship/cover.png")
    for portrait in (False, True):
        export_video(portrait)
    captions = """WEBVTT

00:00.000 --> 00:06.000
Your Mac stays home. Your next build comes with you.
Deploy through your paired Mac on another Wi-Fi network.

00:06.000 --> 00:12.000
Pair once over USB. Connect both devices through a private VPN.
Keep your Mac running with Xcode and Debagr.

00:12.000 --> 00:18.000
Claude Code, Codex, or your terminal.
Check readiness. Install. Confirm launch.

00:18.000 --> 00:24.000
Debagr technical preview. Follow development and support testing.
Wi-Fi required. Cellular-only is unsupported. UI uses sample data.
"""
    (OUT / "video/debagr-promo.vtt").write_text(captions)
    srt = []
    for index, block in enumerate(captions.strip().split("\n\n")[1:], start=1):
        timing, copy = block.split("\n", 1)
        timing = " --> ".join("00:" + value.replace(".", ",") for value in timing.split(" --> "))
        srt.append(f"{index}\n{timing}\n{copy}")
    (OUT / "video/debagr-promo.srt").write_text("\n\n".join(srt) + "\n")
    for name, expected in (("social/launch-card.png", (1200, 630)), ("sponsorship/cover.png", (1200, 630))):
        assert Image.open(OUT / name).size == expected
    for source, destination in (
        ("screenshots/device-setup-light.png", "device-setup-light.png"),
        ("screenshots/agent-tools-light.png", "agent-tools-light.png"),
        ("social/launch-card.png", "launch-card.png"),
        ("video/debagr-promo-landscape.mp4", "debagr-promo.mp4"),
        ("video/debagr-promo-landscape-poster.jpg", "promo-poster.jpg"),
        ("video/debagr-promo.vtt", "debagr-promo.vtt"),
    ):
        shutil.copy2(OUT / source, OUT / "site/assets" / destination)


if __name__ == "__main__":
    main()
