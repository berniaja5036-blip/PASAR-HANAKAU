import fs from "node:fs";
import path from "node:path";

const manifestPath = path.resolve("manifest.webmanifest");
const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));

if (!manifest.name && !manifest.short_name) throw new Error("Manifest must define name or short_name.");
if (!manifest.start_url || !manifest.scope) throw new Error("Manifest must define start_url and scope.");
if (!["standalone", "fullscreen", "minimal-ui"].includes(manifest.display)) {
  throw new Error("Manifest display must support standalone installation.");
}
if (!Array.isArray(manifest.icons)) throw new Error("Manifest icons must be an array.");

for (const requiredSize of ["192x192", "512x512"]) {
  const icon = manifest.icons.find(item => item.sizes?.split(/\s+/).includes(requiredSize));
  if (!icon) throw new Error(`Manifest is missing required ${requiredSize} icon.`);
  const iconPath = path.resolve(path.dirname(manifestPath), icon.src);
  if (!fs.existsSync(iconPath)) throw new Error(`Missing icon file: ${icon.src}`);
  if (icon.type === "image/png") {
    const bytes = fs.readFileSync(iconPath);
    const signature = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
    if (bytes.length < 24 || !bytes.subarray(0, 8).equals(signature)) {
      throw new Error(`Invalid PNG file: ${icon.src}`);
    }
    const width = bytes.readUInt32BE(16);
    const height = bytes.readUInt32BE(20);
    const expected = Number(requiredSize.split("x")[0]);
    if (width !== expected || height !== expected) {
      throw new Error(`Icon ${icon.src} must be ${requiredSize}; found ${width}x${height}.`);
    }
  }
}

const serviceWorkerPath = path.resolve("sw.js");
if (!fs.existsSync(serviceWorkerPath)) throw new Error("Missing service worker.");
const serviceWorker = fs.readFileSync(serviceWorkerPath, "utf8");
for (const required of ["./icons/icon-192.png", "./icons/icon-512.png"]) {
  if (!serviceWorker.includes(required)) throw new Error(`Service worker does not cache/reference ${required}.`);
}

console.log("PWA manifest, required icons, and service-worker icon references are valid.");
