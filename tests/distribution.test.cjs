const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const instructions = path.join(root, 'instructions');
const names = [
  '01-beyond-keywords.ipynb',
  '02-case-notes-to-vectors.ipynb',
  '03-search-by-meaning.ipynb',
  '04-narrative-to-results.ipynb',
];
const files = [
  'README.md',
  'instructions/README.md',
  'infra/README.md',
];

function localTargets(markdown, sourceFile) {
  const directory = path.dirname(path.join(root, sourceFile));
  return [...markdown.matchAll(/\[[^\]]+\]\(([^)]+)\)/g)]
    .map(match => match[1])
    .filter(target => !/^(?:https?:|mailto:)/i.test(target))
    .map(target => ({
      path: path.resolve(directory, decodeURIComponent(target.split('#')[0])),
      anchor: target.split('#')[1],
    }));
}

function anchorsFor(file) {
  const text = fs.readFileSync(file, 'utf8');
  const anchors = new Set([...text.matchAll(/<a\s+(?:name|id)=["']([^"']+)["']/gi)]
    .map(match => match[1]));
  for (const match of text.matchAll(/^#{1,6}\s+(.+?)\s*#*\s*$/gm)) {
    const slug = match[1].toLowerCase()
      .replace(/<[^>]*>/g, '')
      .replace(/[^\p{L}\p{N}\s-]/gu, '')
      .trim()
      .replace(/\s+/g, '-')
      .replace(/-+/g, '-');
    anchors.add(slug);
  }
  return anchors;
}

test('the official session page links directly to the attendee entry point and every lab', () => {
  const readme = fs.readFileSync(path.join(root, 'README.md'), 'utf8');
  assert.match(readme, /img\/banner-ignite-26\.png/);
  assert.match(readme, /instructions\/README\.md/);
  for (const name of names)
    assert.match(readme, new RegExp(`instructions/${name.replaceAll('.', '\\.')}`));
  const outcomesStart = readme.indexOf('### 🎯 Learning outcomes');
  assert.notEqual(outcomesStart, -1, 'learning outcomes section');
  const outcomesEnd = readme.indexOf('\n### ', outcomesStart + 1);
  const outcomes = readme.slice(outcomesStart, outcomesEnd === -1 ? undefined : outcomesEnd);
  assert.equal([...outcomes.matchAll(/^- /gm)].length, 3);
  assert.doesNotMatch(readme, /Add your session description|Outcome [123]|Technology [123]/);
});

test('official documentation links resolve within the flat distribution', () => {
  for (const name of files) {
    const text = fs.readFileSync(path.join(root, name), 'utf8');
    for (const target of localTargets(text, name)) {
      assert(fs.existsSync(target.path), `${name}: missing local target ${target.path}`);
      if (target.anchor)
        assert(anchorsFor(target.path).has(target.anchor), `${name}: missing anchor ${target.anchor}`);
    }
  }
  assert(fs.existsSync(path.join(root, 'img', 'banner-ignite-26.png')));
});

test('the attendee package is flat and independent of the source retrieval directory', () => {
  assert.deepEqual(fs.readdirSync(instructions).sort(), ['00-setup.ipynb', ...names, 'README.md'].sort());
  for (const name of names) {
    const notebook = JSON.parse(fs.readFileSync(path.join(instructions, name), 'utf8'));
    const text = notebook.cells.filter(cell => cell.cell_type === 'markdown')
      .map(cell => cell.source.join('')).join('\n');
    assert.doesNotMatch(text, /notebooks[/\\]retrieval|deployment[/\\]|labs-rewrite-sqlai/i, name);
    assert.doesNotMatch(text, /!\[[^\]]*\]\(images\//, name);
    assert.match(text, /!\[[^\]]+\]\(\.\.\/img\/[^)]+\.png\)/, name);
  }
});

test('the content owners section names a real owner without template placeholders', () => {
  const readme = fs.readFileSync(path.join(root, 'README.md'), 'utf8');
  const section = readme.split('### 👥 Content owners')[1].split('### ⚖️ Trademarks')[0];
  for (const placeholder of ['INSERT NAME HERE', 'yourGitHubHandle', 'TODO']) {
    assert.ok(!section.includes(placeholder), `content owners still contains ${placeholder}`);
  }
  assert.match(section, /https:\/\/github\.com\/itsnotaboutthecell\.png/);
  assert.match(section, /<b>Alex Powers<\/b>/);
});
