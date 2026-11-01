import { readFile, writeFile } from 'node:fs/promises';
const sections = [
  ['Stageshow (MIT)', 'vendor/stageshow/LICENSE'],
  ['React (MIT)', 'node_modules/react/LICENSE'],
  ['React DOM (MIT)', 'node_modules/react-dom/LICENSE'],
  ['Lucide (ISC)', 'node_modules/lucide-react/LICENSE'],
];
const text = await Promise.all(sections.map(async ([title, path]) => `${title}\n${'='.repeat(title.length)}\n${await readFile(new URL(path, import.meta.url), 'utf8')}`));
await writeFile(new URL('../docs/assets/demo/LICENSES.txt', import.meta.url), text.join('\n\n'));
