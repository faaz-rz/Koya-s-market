// Downloads explicitly selected source URLs for visual review, never applies them.
import fs from 'node:fs/promises';
import path from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const root = path.resolve(import.meta.dirname, '..');
const run = promisify(execFile);
const file = path.resolve(process.argv[2]);
const selected = process.argv.slice(3);
const candidates = JSON.parse(await fs.readFile(file, 'utf8')).filter((item)=>!selected.length||selected.includes(item.key));
const directory = path.join(root, 'outputs/product_image_review/sourced');
await fs.mkdir(directory, { recursive: true });
for (const item of candidates) {
  if (item.localAssetImagePath) {
    item.assetImagePath=item.localAssetImagePath;
    continue;
  }
  // Use the system HTTP client so the user's configured network routing works.
  // --fail rejects error pages; no cookies or authentication are sent.
  const { stdout: data } = await run('curl', ['--fail', '--silent', '--show-error',
    '--location', '--max-time', '25', '--proto', '=https', '--proto-redir', '=https',
    item.image], { encoding: 'buffer', maxBuffer: 8000001 });
  if (data.length < 200 || data.length > 8000000) throw new Error('Unexpected image size');
  const source = path.join(directory, `${item.key}.source`);
  await fs.writeFile(source, data);
  item.assetImagePath = `outputs/product_image_review/sourced/${item.key}.webp`;
  await run(process.env.CWEBP_PATH || 'cwebp', ['-quiet', '-q', '86', source, '-o', path.join(root, item.assetImagePath)]);
}
const previous=JSON.parse(await fs.readFile(path.join(directory,'candidates.json'),'utf8').catch(()=>'[]'));
const merged=new Map(previous.map((item)=>[item.key,item]));
for (const item of candidates) merged.set(item.key,item);
await fs.writeFile(path.join(directory, 'candidates.json'), JSON.stringify([...merged.values()], null, 2) + '\n');
console.log(`Downloaded ${candidates.length} images for review.`);
