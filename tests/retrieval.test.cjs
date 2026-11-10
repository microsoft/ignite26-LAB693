const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const instructions = path.join(root, 'instructions');
const images = path.join(root, 'img');
const names = [
  '01-beyond-keywords.ipynb',
  '02-case-notes-to-vectors.ipynb',
  '03-search-by-meaning.ipynb',
  '04-narrative-to-results.ipynb',
];
const diagrams = ['retrieval-overview', 'model-access', 'chunk-and-embed',
  'exact-and-approximate', 'rank-fusion', 'intent-routing'];
const read = name => JSON.parse(fs.readFileSync(path.join(instructions, name), 'utf8'));
const sql = notebook => notebook.cells.filter(cell => cell.cell_type === 'code')
  .map(cell => cell.source.join('')).join('\n');

test('attendee guide, setup, and four ordered notebooks live directly in instructions', () => {
  assert.deepEqual(fs.readdirSync(instructions).sort(), [
    '00-setup.ipynb',
    '01-beyond-keywords.ipynb',
    '02-case-notes-to-vectors.ipynb',
    '03-search-by-meaning.ipynb',
    '04-narrative-to-results.ipynb',
    'README.md',
  ]);
  assert.deepEqual(fs.readdirSync(images).filter(name => fs.statSync(path.join(images, name)).isDirectory()), []);
});

test('the four notebooks retain MSSQL teaching cells without saved outputs', () => {
  for (const name of names) {
    const notebook = read(name);
    assert.equal(notebook.metadata.kernelspec.name, 'sql-notebook', name);
    for (const [index, cell] of notebook.cells.entries()) {
      if (cell.cell_type !== 'code') continue;
      const before = notebook.cells[index - 1];
      const after = notebook.cells[index + 1];
      assert.equal(before?.cell_type, 'markdown', `${name}:${index} explanation`);
      assert.equal(after?.cell_type, 'markdown', `${name}:${index} expected result`);
      assert.match(after.source.join(''), /^### Expected (?:Output|result)/, `${name}:${index}`);
      assert.deepEqual(cell.outputs, [], `${name}:${index} outputs`);
      assert.equal(cell.execution_count, null, `${name}:${index} execution count`);
    }
  }
});

test('full-text retrieval precedes chunks and hybrid retrieval works without intent detection', () => {
  const fullText = sql(read(names[0]));
  assert.match(fullText, /FREETEXTTABLE\(dbo\.Cases,/);
  assert.doesNotMatch(fullText, /dbo\.RetrievalChunks/);
  const final = read(names[3]);
  const hybrid = final.cells.find(cell => cell.cell_type === 'code'
    && cell.source.join('').startsWith('CREATE OR ALTER PROCEDURE dbo.RetrievalSearch')).source.join('');
  assert.match(hybrid, /CREATE OR ALTER PROCEDURE dbo\.RetrievalSearch/);
  assert.match(hybrid, /ROW_NUMBER\(\) OVER/);
  assert.match(hybrid, /1E0 \/ \(60 \+/);
  assert.doesNotMatch(hybrid, /RewriteQuery|AI_GENERATE_RESPONSE|sp_invoke_external_rest_endpoint/);
  const bonus = sql(final);
  assert.match(bonus, /EXEC dbo\.AI_GENERATE_RESPONSE/);
  assert.match(bonus, /ISJSON/);
  assert.match(bonus, /OPENJSON/);
  assert.match(bonus, /EXEC dbo\.RetrievalSearch/);
  assert.doesNotMatch(final.cells.filter(cell => cell.cell_type === 'code')[0].source.join(''),
    /AI_GENERATE_RESPONSE|gpt-5/);
});

test('embedding reruns preserve completed work and vector search proves the indexed path', () => {
  const preparation = read(names[1]);
  const chunk = preparation.cells.find(cell => cell.cell_type === 'code'
    && cell.source.join('').startsWith('INSERT INTO dbo.RetrievalChunks')).source.join('');
  assert.match(chunk, /AI_GENERATE_CHUNKS/);
  assert.match(chunk, /NOT EXISTS/);
  assert.doesNotMatch(chunk, /\b(?:TRUNCATE|DELETE)\b/);
  const embed = sql(preparation);
  assert.match(embed, /WHERE Embedding IS NULL/);
  assert.match(embed, /AI_GENERATE_EMBEDDINGS/);
  assert.doesNotMatch(embed, /SET Embedding = NULL/);
  const vector = sql(read(names[2]));
  assert.match(vector, /VECTOR_DISTANCE\('cosine'/);
  assert.match(vector, /CREATE VECTOR INDEX/);
  assert.match(vector, /WITH APPROXIMATE/);
  assert.match(vector, /VECTOR_SEARCH\(/);
  assert.match(vector, /SET STATISTICS XML ON/);
  assert.match(vector, /SET STATISTICS XML OFF/);
});

test('notebook navigation, documentation, and local image links resolve', () => {
  for (const name of [...names, 'README.md']) {
    const text = name.endsWith('.ipynb')
      ? read(name).cells.filter(cell => cell.cell_type === 'markdown').map(cell => cell.source.join('')).join('\n')
      : fs.readFileSync(path.join(instructions, name), 'utf8');
    for (const match of text.matchAll(/\[[^\]]+\]\(([^)]+)\)/g)) {
      if (/^https?:/.test(match[1])) continue;
      const target = match[1].split('#')[0];
      assert(fs.existsSync(path.resolve(instructions, target)), `${name}: missing link ${match[1]}`);
    }
    for (const match of text.matchAll(/!\[[^\]]*\]\(([^)]+)\)/g)) {
      assert(fs.existsSync(path.resolve(instructions, match[1])), `${name}: missing image ${match[1]}`);
    }
  }
});

test('each notebook retains contextual Learn links and extension-free local diagrams', () => {
  const concepts = [
    ['query-with-full-text-search', 'create-external-model', 'create-database-scoped-credential'],
    ['ai-generate-chunks', 'ai-generate-embeddings', 'vector-data-type'],
    ['vector-distance', 'create-vector-index', 'vector-search'],
    ['hybrid-search-ranking', 'sp-invoke-external-rest-endpoint', 'openjson'],
  ];
  for (const [index, name] of names.entries()) {
    const notebook = read(name);
    const text = notebook.cells.filter(cell => cell.cell_type === 'markdown').map(cell => cell.source.join('')).join('\n');
    for (const concept of concepts[index])
      assert.match(text, new RegExp(`\\]\\(https://learn\\.microsoft\\.com/[^\\s)]*${concept}[^\\s)]*\\)`), name);
    assert.doesNotMatch(text, /```mermaid|https?:\/\/[^\s)]*\.(?:png|svg)/i, name);
    const localImages = [...text.matchAll(/!\[([^\]]+)\]\((\.\.\/img\/[^)]+\.png)\)/g)];
    assert(localImages.length >= 1, `${name}: missing local concept diagram`);
    for (const [, alt] of localImages)
      assert(alt.length >= 40, `${name}: image needs a meaningful text alternative`);
    assert(notebook.cells.some(cell => cell.cell_type === 'markdown'
      && /Learn more/.test(cell.source.join('')) && /## Step [1-9]/.test(cell.source.join(''))),
    `${name}: references must appear with exercises`);
  }
});

test('six diagrams have editable SVGs and high-resolution PNGs in the flat image folder', () => {
  for (const name of diagrams) {
    const source = fs.readFileSync(path.join(images, `${name}.svg`), 'utf8');
    assert.match(source, /<title[^>]*>[^<]+<\/title>/, name);
    assert.match(source, /<desc[^>]*>[^<]+<\/desc>/, name);
    assert.doesNotMatch(source, /<script\b|<foreignObject\b|@import|url\(["']?https?:|(?:href|src)\s*=\s*["']https?:/i, name);
    const dimensions = source.match(/viewBox="0 0 (\d+) (\d+)"/);
    assert(dimensions, `${name}: explicit SVG viewBox`);
    const png = fs.readFileSync(path.join(images, `${name}.png`));
    assert.equal(png.subarray(0, 8).toString('hex'), '89504e470d0a1a0a', `${name}: valid PNG`);
    assert.equal(png.toString('ascii', 12, 16), 'IHDR', name);
    assert.equal(png.readUInt32BE(16), Number(dimensions[1]) * 2, `${name}: high-resolution width`);
    assert.equal(png.readUInt32BE(20), Number(dimensions[2]) * 2, `${name}: high-resolution height`);
  }
  for (const name of ['lexical-search.png', 'hybrid-search.png'])
    assert(fs.existsSync(path.join(images, name)), `missing shared image ${name}`);
});
