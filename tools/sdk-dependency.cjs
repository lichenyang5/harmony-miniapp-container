const fs = require('node:fs');
const path = require('node:path');
const mode = process.argv[2];
if (!['source', 'packaged'].includes(mode)) throw new Error('Expected source or packaged');
const root = path.resolve(__dirname, '..');
const file = path.join(root, 'entry/oh-package.json5');
// This project owns a strict JSON package manifest, also valid as JSON5.
const manifest = JSON.parse(fs.readFileSync(file, 'utf8'));
manifest.dependencies.mpsdk = mode === 'source' ? 'file:../mpsdk' : 'file:../libs/mpsdk.har';
fs.writeFileSync(file, JSON.stringify(manifest, null, 2) + '\n');
