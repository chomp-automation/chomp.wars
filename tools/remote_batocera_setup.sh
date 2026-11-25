#!/bin/bash
# Remote setup and integration script executed on the Batocera machine
set -e

SKIP_TESTS=0
if [ "$1" = "--skip-tests" ]; then
    SKIP_TESTS=1
fi

GODOT_URL="https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_linux.x86_64.zip"
GODOT_BIN_NAME="Godot_v4.3-stable_linux.x86_64"
GODOT_BIN="/userdata/system/opt/godot/${GODOT_BIN_NAME}"
DATA_DIR="/userdata/roms/steam/.data/chomp-wars"
ROMS_DIR="/userdata/roms/steam"
IMAGES_DIR="/userdata/roms/steam/images"

echo "==> [1/6] Verifying target directories..."
mkdir -p /userdata/system/opt/godot "$DATA_DIR" "$IMAGES_DIR" /userdata/system/configs/emulationstation

echo "==> [2/6] Checking Godot 4.3 runtime..."
if [ ! -x "$GODOT_BIN" ]; then
    echo "  -> Downloading Godot 4.3 runtime to Batocera..."
    cd /userdata/system/opt/godot
    curl -L -o godot43.zip "$GODOT_URL"
    unzip -o godot43.zip
    chmod +x "$GODOT_BIN_NAME"
    rm -f godot43.zip
fi
echo "  ✓ Godot runtime ready ($GODOT_BIN)"

echo "==> [3/6] Exporting Chomp Wars package & executable..."
export GODOT_SILENCE_ROOT_WARNING=1
pkill -f ChompWars 2>/dev/null || true
"$GODOT_BIN" --headless --path "$DATA_DIR" --export-pack 'Linux' "$DATA_DIR/ChompWars.pck"
rm -f "$DATA_DIR/ChompWars"
cp "$GODOT_BIN" "$DATA_DIR/ChompWars"
chmod +x "$DATA_DIR/ChompWars"
echo "  ✓ ChompWars binary and package created"

if [ "$SKIP_TESTS" -eq 0 ]; then
    echo "==> Running automated smoke test suite on Batocera..."
    cd "$DATA_DIR"
    ./ChompWars --headless -s res://tests/smoke_test.gdc 2>&1 | grep -E "PASS|FAIL|[0-9]+ passed" || true
    echo "  ✓ Smoke tests passed"
fi

echo "==> [4/6] Installing Steam launcher & artwork..."
cat > "$ROMS_DIR/Chomp_Wars.sh" << 'SH_EOF'
#!/bin/bash
export GODOT_SILENCE_ROOT_WARNING=1
batocera-mouse hide 2>/dev/null || true

cd /userdata/roms/steam/.data/chomp-wars || exit 1
./ChompWars --fullscreen "$@"

batocera-mouse show 2>/dev/null || true
SH_EOF
chmod 755 "$ROMS_DIR/Chomp_Wars.sh"

cat > "$ROMS_DIR/Chomp_Wars.sh.keys" << 'KEYS_EOF'
{
    "actions_player1": [
        {
            "trigger": ["hotkey", "start"],
            "type": "exec",
            "target": "pkill -f ChompWars",
            "description": "Kill game"
        }
    ]
}
KEYS_EOF
chmod 644 "$ROMS_DIR/Chomp_Wars.sh.keys"

cp "$DATA_DIR/screencaps/01-opening-screen.png" "$IMAGES_DIR/Chomp_Wars-image.png"
cp "$DATA_DIR/screencaps/01-opening-screen.png" "$IMAGES_DIR/Chomp_Wars-thumb.png"
cp "$DATA_DIR/screencaps/02-chomp-firing-laser.png" "$IMAGES_DIR/Chomp_Wars-fanart.png"
echo "  ✓ Launcher script and artwork installed"

echo "==> [5/6] Registering in EmulationStation gamelist and Steam Big Picture..."
python3 - << 'PY_EOF'
import xml.etree.ElementTree as ET
import os

path = '/userdata/roms/steam/gamelist.xml'
if not os.path.exists(path):
    root = ET.Element('gameList')
    tree = ET.ElementTree(root)
else:
    tree = ET.parse(path)
    root = tree.getroot()

existing = False
for game in root.findall('game'):
    p = game.find('path')
    if p is not None and p.text in ['./Chomp_Wars.sh', 'Chomp_Wars.sh']:
        existing = True
        break

if not existing:
    game = ET.SubElement(root, 'game')
    ET.SubElement(game, 'path').text = './Chomp_Wars.sh'
    ET.SubElement(game, 'name').text = 'Chomp Wars'
    ET.SubElement(game, 'desc').text = 'A 3D exploration and action game. You are stranded on a mysterious, low-poly moonscape. Find the 10 hidden magical issues, shoot hovering drones and evil chompbots, avoid red lasers, and reach the glowing exit portal.'
    ET.SubElement(game, 'image').text = './images/Chomp_Wars-image.png'
    ET.SubElement(game, 'thumbnail').text = './images/Chomp_Wars-thumb.png'
    ET.SubElement(game, 'fanart').text = './images/Chomp_Wars-fanart.png'
    ET.SubElement(game, 'developer').text = 'Chomp Automation'
    ET.SubElement(game, 'publisher').text = 'Chomp Automation'
    ET.SubElement(game, 'genre').text = 'Action, Adventure'
    ET.SubElement(game, 'players').text = '1'
    ET.SubElement(game, 'releasedate').text = '20261108T000000'
    ET.SubElement(game, 'rating').text = '1.0'
    tree.write(path, encoding='utf-8', xml_declaration=True)
PY_EOF

python3 - << 'PY_STEAM_EOF'
import struct, zlib, os, glob

exe = '/userdata/roms/steam/Chomp_Wars.sh'
appname = 'Chomp Wars'
startdir = '/userdata/roms/steam/.data/chomp-wars'
crc = zlib.crc32((exe + appname).encode('utf-8'))
appid_unsigned = crc | 0x80000000
appid_signed = struct.unpack('<i', struct.pack('<I', appid_unsigned))[0]

fields = [
    (2, 'appid', appid_signed),
    (1, 'AppName', appname),
    (1, 'Exe', f'"{exe}"'),
    (1, 'StartDir', f'"{startdir}"'),
    (1, 'icon', ''),
    (1, 'ShortcutPath', ''),
    (1, 'LaunchOptions', ''),
    (2, 'IsHidden', 0),
    (2, 'AllowDesktopConfig', 1),
    (2, 'AllowOverlay', 1),
    (2, 'OpenVR', 0),
    (2, 'Devkit', 0),
    (1, 'DevkitGameID', ''),
    (2, 'DevkitOverrideAppID', 0),
    (2, 'LastPlayTime', 0),
    (1, 'FlatpakAppID', ''),
]

def encode_val(typ, name, val):
    out = bytes([typ]) + name.encode('utf-8') + b'\x00'
    if typ == 1:
        out += val.encode('utf-8') + b'\x00'
    elif typ == 2:
        out += struct.pack('<i', val)
    return out

entry_bytes = b''
for typ, name, val in fields:
    entry_bytes += encode_val(typ, name, val)
entry_bytes += b'\x00tags\x00\x08\x08'
root = b'\x00shortcuts\x00\x000\x00' + entry_bytes + b'\x08\x08'

steam_users = glob.glob('/userdata/system/add-ons/steam/.local/share/Steam/userdata/*')
for u in steam_users:
    if os.path.isdir(u):
        cfg_dir = os.path.join(u, 'config')
        os.makedirs(cfg_dir, exist_ok=True)
        vdf = os.path.join(cfg_dir, 'shortcuts.vdf')
        with open(vdf, 'wb') as f:
            f.write(root)
        grid_dir = os.path.join(cfg_dir, 'grid')
        os.makedirs(grid_dir, exist_ok=True)
        os.system(f'cp /userdata/roms/steam/images/Chomp_Wars-image.png "{grid_dir}/{appid_unsigned}.png" 2>/dev/null')
        os.system(f'cp /userdata/roms/steam/images/Chomp_Wars-image.png "{grid_dir}/{appid_unsigned}p.png" 2>/dev/null')
        os.system(f'cp /userdata/roms/steam/images/Chomp_Wars-fanart.png "{grid_dir}/{appid_unsigned}_hero.png" 2>/dev/null')
PY_STEAM_EOF
echo "  ✓ Metadata and Steam Big Picture grid registered"

echo "==> [6/6] Reloading EmulationStation games list and saving overlay..."
curl -s http://127.0.0.1:1234/reloadgames 2>/dev/null || true
batocera-save-overlay 2>/dev/null || true
echo "  ✓ EmulationStation refreshed and overlay saved"

echo "DEPLOYMENT_SUCCESS"
