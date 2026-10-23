"""Generate real independent 0.5s CMAF fragments with continuous decode times."""
import hashlib
import json
import pathlib
import struct
import subprocess


def boxes(data):
    offset = 0
    while offset < len(data):
        if offset + 8 > len(data):
            raise ValueError("Truncated ISO BMFF box header")
        size, kind = struct.unpack_from(">I4s", data, offset)
        header = 8
        if size == 1:
            size = struct.unpack_from(">Q", data, offset + 8)[0]
            header = 16
        elif size == 0:
            size = len(data) - offset
        if size < header or offset + size > len(data):
            raise ValueError("Invalid ISO BMFF box size")
        yield kind, data[offset:offset + size], data[offset + header:offset + size]
        offset += size


def prepare(directory, seconds=300):
    directory.mkdir(parents=True, exist_ok=False)
    output = directory / "source.mp4"
    command = [
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-f", "lavfi",
        "-i", "testsrc2=size=256x144:rate=30", "-t", str(seconds), "-an",
        "-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p",
        "-g", "15", "-keyint_min", "15", "-sc_threshold", "0", "-bf", "0",
        "-movflags", "+empty_moov+default_base_moof+frag_keyframe+skip_trailer",
        "-f", "mp4", str(output),
    ]
    subprocess.run(command, check=True, timeout=180)
    data = output.read_bytes()
    initialization = bytearray()
    fragments = []
    current = None
    timestamps = []
    for kind, raw, payload in boxes(data):
        if kind in [b"ftyp", b"moov"]:
            initialization.extend(raw)
        elif kind == b"moof":
            if current is not None:
                raise ValueError("moof without mdat")
            current = raw
            for child_kind, _, child in boxes(payload):
                if child_kind == b"traf":
                    for leaf_kind, _, leaf in boxes(child):
                        if leaf_kind == b"tfdt":
                            timestamps.append(int.from_bytes(leaf[4:12] if leaf[0] == 1 else leaf[4:8], "big"))
        elif kind == b"mdat":
            if current is None:
                raise ValueError("mdat without moof")
            fragments.append(current + raw)
            current = None
    if len(fragments) != seconds * 2 or len(timestamps) != len(fragments):
        raise ValueError("Unexpected fragment count")
    if timestamps != list(range(0, seconds * 15360, 7680)):
        raise ValueError("Discontinuous or unexpected tfdt timestamps")
    (directory / "init.mp4").write_bytes(initialization)
    for index, fragment in enumerate(fragments):
        (directory / f"part-{index}.m4s").write_bytes(fragment)
    for index in range(len(fragments) // 4):
        (directory / f"segment-{index}.m4s").write_bytes(b"".join(fragments[index * 4:index * 4 + 4]))
    stream = json.loads(subprocess.check_output([
        "ffprobe", "-v", "error", "-show_entries", "stream=codec_name,time_base,duration", "-of", "json", str(output)
    ], text=True))
    packet_data = json.loads(subprocess.check_output([
        "ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
        "packet=pts_time,duration_time,flags", "-of", "json", str(output)
    ], text=True))["packets"]
    if len(packet_data) != seconds * 30 or any("K" not in packet_data[index]["flags"] for index in range(0, len(packet_data), 15)):
        raise ValueError("PART start is not an independently decodable keyframe")
    manifest = {
        "generator": command, "ffmpeg": subprocess.check_output(["ffmpeg", "-version"], text=True).splitlines()[0],
        "ffprobe": stream, "parts": len(fragments), "partDuration": 0.5, "partsPerSegment": 4,
        "segmentDuration": 2, "timescale": 15360, "decodeTimestamps": timestamps,
        "packetCount": len(packet_data),
        "sha256": {path.name: hashlib.sha256(path.read_bytes()).hexdigest()
                   for path in sorted(directory.iterdir()) if path.is_file()},
    }
    (directory / "provenance.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", type=pathlib.Path)
    parser.add_argument("--seconds", type=int, default=300)
    args = parser.parse_args()
    print(json.dumps(prepare(args.directory, args.seconds)["ffprobe"]))
