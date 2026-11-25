"""Assemble the Glacier OS "Live Demo" trailer from footage recorded on the real OS.

Inputs (build/, not committed):
  raw/demo.mp4            in-guest recording (wf-recorder, 1600x900@30) of the live session
  raw/boot/, raw/login/   QEMU screendump frames (PPM, ~6 fps): live GRUB menu, desktop appearing
  raw/firstboot/, raw/firstlogin/   same for the installed system's first boot
  cards/*.png             title cards + captions (cards/make-cards.sh)
Output: build/glacier-live-demo.mp4 (1600x900, 30 fps, H.264 + AAC)

usage: python build.py            (needs ffmpeg/ffprobe on PATH)
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
B = os.path.join(HERE, "build")
RAW, CARDS, SEG = os.path.join(B, "raw"), os.path.join(B, "cards"), os.path.join(B, "seg")
W, H, FPS, XF = 1600, 900, 30, 0.45            # size, frame rate, crossfade seconds
os.makedirs(SEG, exist_ok=True)

ENC = ["-c:v", "libx264", "-preset", "medium", "-crf", "17", "-pix_fmt", "yuv420p", "-r", str(FPS)]


def ff(*args):
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", *args], check=True)


def dur(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
                         check=True, capture_output=True, text=True).stdout
    return float(out)


NORM = f"scale={W}:{H}:flags=lanczos,setsar=1,fps={FPS},format=yuv420p"


def caption_filter(caption, length):
    """overlay a caption PNG (input #1) fading in after 0.5 s and out before the end"""
    if not caption:
        return f"[0:v]{NORM}[v]"
    out_at = max(0.8, length - 0.9)
    return (f"[0:v]{NORM}[base];[1:v]format=rgba,fade=in:st=0.5:d=0.4:alpha=1,"
            f"fade=out:st={out_at:.2f}:d=0.4:alpha=1[cap];[base][cap]overlay=0:0:shortest=1[v]")


def caption_input(caption):
    return ["-loop", "1", "-i", os.path.join(CARDS, caption + ".png")] if caption else []


def seg_video(name, start, end, speed=1.0, caption=None):
    """a slice of the in-guest recording, optionally sped up"""
    out = os.path.join(SEG, name + ".mp4")
    length = (end - start) / speed
    graph = caption_filter(caption, length).replace("[0:v]", f"[0:v]setpts=(PTS-STARTPTS)/{speed},", 1)
    ff("-ss", f"{start}", "-t", f"{end - start}", "-i", os.path.join(RAW, "demo.mp4"), *caption_input(caption),
       "-filter_complex", graph, "-map", "[v]", "-t", f"{length:.3f}", *ENC, out)
    return out


def seg_frames(name, folder, first, last, fps_in, speed=1.0, caption=None):
    """a run of QEMU screendump frames (captured at ~fps_in) played back at speed"""
    out = os.path.join(SEG, name + ".mp4")
    n = last - first + 1
    length = n / fps_in / speed
    ff("-framerate", f"{fps_in * speed}", "-start_number", str(first), "-i", os.path.join(RAW, folder, "f%05d.ppm"),
       *caption_input(caption), "-filter_complex", caption_filter(caption, length), "-map", "[v]",
       "-frames:v", str(int(length * FPS)), *ENC, out)
    return out


def seg_card(name, seconds):
    out = os.path.join(SEG, name + ".mp4")
    ff("-loop", "1", "-t", str(seconds), "-i", os.path.join(CARDS, name + ".png"),
       "-vf", f"{NORM},zoompan=z='1+0.0006*on':d=1:s={W}x{H}:fps={FPS}", *ENC, out)
    return out


def boot_fps(folder):
    lines = open(os.path.join(RAW, folder, "times.txt")).read().split()
    n = len(lines) // 2
    return (n - 1) / float(lines[-1])


print("cutting segments…", flush=True)
segs = [
    seg_card("intro", 3.6),
    seg_frames("grub", "boot", 8, 40, boot_fps("boot"), 1.0, "c-boot"),
    seg_frames("appear", "login", 6, 40, boot_fps("login"), 1.5, "c-desktop"),
    seg_video("dock", 3.0, 9.8, 1.0, "c-desktop"),
    seg_video("launcher", 15.8, 23.8, 1.3, "c-launcher"),
    seg_video("packages", 26.0, 35.6, 1.3, "c-launcher"),
    seg_video("floe", 37.5, 90.0, 4.0, "c-floe"),
    seg_video("cc", 92.8, 103.0, 1.25, "c-cc"),
    seg_video("inst-pages", 529.0, 541.0, 2.0, "c-installer"),
    seg_video("inst-account", 541.0, 577.0, 4.0, "c-installer"),
    seg_video("inst-region", 577.0, 592.0, 3.0, "c-installer"),
    seg_video("inst-review", 592.0, 599.0, 1.0, "c-installer"),
    seg_video("inst-progress", 208.0, 476.0, 40.0, "c-installer"),
    seg_video("inst-done", 476.0, 480.0, 1.0, "c-installer"),
    seg_frames("grub-installed", "firstboot", 0, 17, boot_fps("firstboot"), 1.0, "c-grub"),
    seg_frames("firstlogin", "firstlogin", 18, 80, boot_fps("firstlogin"), 2.0, "c-firstboot"),
    seg_card("outro", 4.5),
]

print("joining with crossfades…", flush=True)
lengths = [dur(s) for s in segs]
inputs, graph, prev, offset = [], [], "[0:v]", 0.0
for s in segs:
    inputs += ["-i", s]
for i in range(1, len(segs)):
    offset += lengths[i - 1] - XF
    tag = f"[x{i}]" if i < len(segs) - 1 else "[vout]"
    graph.append(f"{prev}[{i}:v]xfade=transition=fade:duration={XF}:offset={offset:.3f}{tag}")
    prev = tag
total = sum(lengths) - XF * (len(segs) - 1)
video = os.path.join(B, "video.mp4")
ff(*inputs, "-filter_complex", ";".join(graph) + ";[vout]fade=in:st=0:d=0.6,fade=out:st=" + f"{total - 1.0:.2f}:d=1.0[v]",
   "-map", "[v]", *ENC, video)

print("scoring…", flush=True)
# a soft ambient pad generated from scratch: Amaj9 → F#m9 → Dmaj9 → E6/9, 8 s each, slow swells
chords = [[110.0, 164.81, 220.0, 277.18, 329.63, 493.88],
          [92.5, 138.59, 185.0, 220.0, 277.18, 415.3],
          [73.42, 110.0, 146.83, 220.0, 277.18, 329.63],
          [82.41, 123.47, 164.81, 207.65, 277.18, 369.99]]


def chord_expr(notes):
    return "+".join(f"sin(2*PI*{f}*t)*{0.16 / (1 + j * 0.35):.3f}" for j, f in enumerate(notes))


sel = "+".join(f"(between(mod(t,32),{8 * i},{8 * i + 8})*({chord_expr(c)}))" for i, c in enumerate(chords))
swell = "(0.55+0.45*sin(2*PI*mod(t,8)/16))"
music = os.path.join(B, "music.m4a")
ff("-f", "lavfi", "-i", f"aevalsrc='({sel})*{swell}':s=48000:d={total:.2f}",
   "-af", f"lowpass=f=2400,aecho=0.8:0.7:420|780:0.35|0.22,volume=0.9,afade=in:d=2.5,afade=out:st={total - 3:.2f}:d=3",
   "-c:a", "aac", "-b:a", "192k", music)

final = os.path.join(B, "glacier-live-demo.mp4")
ff("-i", video, "-i", music, "-map", "0:v", "-map", "1:a", "-c:v", "copy", "-c:a", "copy", "-shortest",
   "-movflags", "+faststart", final)
print(f"done: {final}  ({total:.1f} s)")
