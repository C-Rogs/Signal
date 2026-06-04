#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Signal/Signal/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
DST="$ROOT/Signal/SignalWatch Watch App/Assets.xcassets/AppIcon.appiconset"

if [[ ! -f "$SRC" ]]; then
  echo "Missing source icon: $SRC"
  exit 1
fi

mkdir -p "$DST"

resize() {
  local name="$1"
  local pixels="$2"
  sips -z "$pixels" "$pixels" "$SRC" --out "$DST/$name" >/dev/null
  echo "wrote $name (${pixels}px)"
}

resize "Icon-24@2x.png" 48
resize "Icon-27.5@2x.png" 55
resize "Icon-29@2x.png" 58
resize "Icon-29@3x.png" 87
resize "Icon-40@2x.png" 80
resize "Icon-44@2x.png" 88
resize "Icon-50@2x.png" 100
resize "Icon-86@2x.png" 172
resize "Icon-98@2x.png" 196
resize "Icon-108@2x.png" 216
resize "Icon-1024.png" 1024

cat > "$DST/Contents.json" <<'EOF'
{
  "images" : [
    {
      "filename" : "Icon-24@2x.png",
      "idiom" : "watch",
      "role" : "notificationCenter",
      "scale" : "2x",
      "size" : "24x24",
      "subtype" : "38mm"
    },
    {
      "filename" : "Icon-27.5@2x.png",
      "idiom" : "watch",
      "role" : "notificationCenter",
      "scale" : "2x",
      "size" : "27.5x27.5",
      "subtype" : "42mm"
    },
    {
      "filename" : "Icon-29@2x.png",
      "idiom" : "watch",
      "role" : "companionSettings",
      "scale" : "2x",
      "size" : "29x29"
    },
    {
      "filename" : "Icon-29@3x.png",
      "idiom" : "watch",
      "role" : "companionSettings",
      "scale" : "3x",
      "size" : "29x29"
    },
    {
      "filename" : "Icon-40@2x.png",
      "idiom" : "watch",
      "role" : "appLauncher",
      "scale" : "2x",
      "size" : "40x40",
      "subtype" : "38mm"
    },
    {
      "filename" : "Icon-44@2x.png",
      "idiom" : "watch",
      "role" : "appLauncher",
      "scale" : "2x",
      "size" : "44x44",
      "subtype" : "40mm"
    },
    {
      "filename" : "Icon-50@2x.png",
      "idiom" : "watch",
      "role" : "appLauncher",
      "scale" : "2x",
      "size" : "50x50",
      "subtype" : "44mm"
    },
    {
      "filename" : "Icon-86@2x.png",
      "idiom" : "watch",
      "role" : "quickLook",
      "scale" : "2x",
      "size" : "86x86",
      "subtype" : "38mm"
    },
    {
      "filename" : "Icon-98@2x.png",
      "idiom" : "watch",
      "role" : "quickLook",
      "scale" : "2x",
      "size" : "98x98",
      "subtype" : "42mm"
    },
    {
      "filename" : "Icon-108@2x.png",
      "idiom" : "watch",
      "role" : "quickLook",
      "scale" : "2x",
      "size" : "108x108",
      "subtype" : "44mm"
    },
    {
      "filename" : "Icon-1024.png",
      "idiom" : "watch-marketing",
      "scale" : "1x",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF

echo "Done. Rebuild watch app in Xcode or: xcodebuild -scheme Signal -destination 'platform=iOS,name=Your iPhone' build"
