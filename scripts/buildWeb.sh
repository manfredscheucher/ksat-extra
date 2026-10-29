#!/usr/bin/env bash
# Build the static website: the ksat playground at the site root and the XOR demo under xor-demo/
# (both Kotlin/JS production bundles). The playground links to xor-demo/; the demo page gets a link
# back to the playground (added here, after the demo's script, which replaces the page body).
# Output: build/pages/
#
#   ./scripts/buildWeb.sh
set -euo pipefail
cd "$(dirname "$0")/.."
[ -x ./gradlew ] || { echo "Error: ./gradlew not found, run from inside the ksat-extra checkout." >&2; exit 1; }

PLAYGROUND=playground/build/dist/js/productionExecutable
DEMO=demo/build/dist/js/productionExecutable
SITE=build/pages

./gradlew :playground:jsBrowserDistribution :demo:jsBrowserDistribution
for f in "$PLAYGROUND/index.html" "$PLAYGROUND/playground-worker.js" "$DEMO/index.html"; do
    [ -f "$f" ] || { echo "Error: build finished but $f is missing." >&2; exit 1; }
done

rm -rf "$SITE"
mkdir -p "$SITE/xor-demo"
cp -R "$PLAYGROUND"/. "$SITE"/
cp -R "$DEMO"/. "$SITE/xor-demo"/

BACK_LINK='<p><a href="../">ksat playground</a> (paste a CNF and solve it)</p>'
sed -i.bak "s|</body>|    $BACK_LINK\\
</body>|" "$SITE/xor-demo/index.html"
rm "$SITE/xor-demo/index.html.bak"
grep -q 'href="../"' "$SITE/xor-demo/index.html" \
    || { echo "Error: could not add the playground link to $SITE/xor-demo/index.html (no </body>?)." >&2; exit 1; }

echo "Website built: $SITE/ (playground at /, XOR demo at /xor-demo/)"
