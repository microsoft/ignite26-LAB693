const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const directory = __dirname;
const root = path.resolve(directory, '..');
const sqlInput = name => fs.readFileSync(path.join(directory, 'sql', name), 'utf8');
const psLiteral = value => "'" + value.replaceAll("'", "''") + "'";

function generate(t, includeChat = true) {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'sqlai-package-'));
  t.after(() => fs.rmSync(temp, { recursive: true, force: true }));
  const output = path.join(temp, 'prepare.sql');
  const result = spawnSync('pwsh', [
    '-NoProfile', '-File', path.join(directory, 'Initialize-Lab.ps1'),
    '-Server', 'sqlai-test-cu.database.windows.net',
    '-FoundryEndpoint', 'https://foundry-test-cu.services.ai.azure.com/',
    '-OutputPath', output, '-GenerateOnly',
    ...(includeChat ? ['-IncludeChat'] : []),
  ], { encoding: 'utf8' });
  assert.equal(result.status, 0, result.stdout + result.stderr);
  return fs.readFileSync(output, 'utf8');
}

test('SQL preparation uses local schema, seed, identity, readiness, and optional helper inputs', t => {
  const sql = generate(t);
  const schema = sqlInput('01-schema.sql');
  for (const table of ['dbo.Cases', 'dbo.ComplaintEmbeddings', 'dbo.SymptomEmbeddings'])
    assert.match(schema, new RegExp(`CREATE TABLE ${table.replaceAll('.', '\\.')}`));
  assert(sql.includes(schema));
  const seed = sqlInput('02-seed-cases.sql');
  assert.equal([...seed.matchAll(/^\s*\(\s*\d+\s*,/gm)].length, 207);
  assert(sql.includes(seed.replaceAll('dbo.Cases', '#ExpectedCases')));
  const modelAccess = sqlInput('03-model-access.sql')
    .replaceAll('__FOUNDRY_ENDPOINT__', 'https://foundry-test-cu.services.ai.azure.com');
  assert(sql.includes(modelAccess));
  assert(sql.includes(sqlInput('05-entry-readiness.sql')));
  assert(sql.includes(sqlInput('04-chat-helper.sql')));
  assert.match(sql, /IF NOT EXISTS \(SELECT 1 FROM dbo\.Cases\)/);
  assert.match(sql, /EXCEPT SELECT \* FROM #ExpectedCases/);
  assert.match(sql, /EXCEPT SELECT \* FROM dbo\.Cases/);
  assert.doesNotMatch(sql, /DELETE FROM dbo\./);
  assert.doesNotMatch(sql, /YOUR-FOUNDRY|CREATE EXTERNAL MODEL|CREATE FULLTEXT|CREATE VECTOR INDEX/);
  assert.match(sql, /BEGIN TRANSACTION/);
  assert.match(sql, /COMMIT TRANSACTION/);
  assert.match(sql, /Prepared Foundry credential/);
  assert.doesNotMatch(sql, /notebooks[/\\]retrieval|labs-rewrite-sqlai/i);
});

test('optional chat setup is omitted without the switch', t => {
  assert.doesNotMatch(generate(t, false), /CREATE OR ALTER PROCEDURE dbo\.AI_GENERATE_RESPONSE/);
});

test('invalid endpoint fails before producing SQL', t => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'sqlai-package-'));
  t.after(() => fs.rmSync(temp, { recursive: true, force: true }));
  const output = path.join(temp, 'prepare.sql');
  const result = spawnSync('pwsh', ['-NoProfile', '-File',
    path.join(directory, 'Initialize-Lab.ps1'), '-Server', 'sqlai-test-cu.database.windows.net',
    '-FoundryEndpoint', "https://unrelated.example/'unsafe", '-OutputPath', output, '-GenerateOnly'],
  { encoding: 'utf8' });
  assert.notEqual(result.status, 0);
  assert.equal(fs.existsSync(output), false);
});

test('ARM artifact preserves identities, models, cost configuration and desktop-only firewall', () => {
  const template = JSON.parse(fs.readFileSync(path.join(directory, 'main.json'), 'utf8'));
  const resources = template.resources;
  assert(!resources.some(r => /virtualMachines|deploymentScripts/.test(r.type)));
  const server = resources.find(r => r.type === 'Microsoft.Sql/servers');
  assert.equal(server.identity.type, 'SystemAssigned');
  assert.equal(server.properties.administrators.azureADOnlyAuthentication, true);
  assert.equal(server.properties.administratorLoginPassword, undefined);
  const database = resources.find(r => r.type.endsWith('/databases'));
  assert.equal(database.properties.useFreeLimit, false);
  assert.equal(database.sku.name, 'GP_S_Gen5_2');
  const firewall = resources.find(r => r.type.endsWith('/firewallRules'));
  assert.equal(firewall.properties.startIpAddress, '[parameters(\'desktopStartIpAddress\')]');
  assert.equal(firewall.properties.endIpAddress, '[parameters(\'desktopEndIpAddress\')]');
  const project = resources.find(r => r.type === 'Microsoft.CognitiveServices/accounts/projects');
  assert.equal(project.identity?.type, 'SystemAssigned', 'Foundry projects are rejected without their own managed identity');
  const role = resources.find(r => r.type === 'Microsoft.Authorization/roleAssignments');
  assert.equal(role.properties.principalType, 'ServicePrincipal');
  assert.match(template.variables.openAiUserRoleId, /5e0bd9bd-7b93-4f28-af87-19fc36ad61bd/);
  const deployments = resources.filter(r => r.type.endsWith('/deployments'));
  assert.deepEqual(deployments.map(r => r.properties.model.name).sort(), ['gpt-5-nano', 'text-embedding-3-small']);
  assert.equal(deployments.find(r => r.properties.model.name === 'gpt-5-nano').condition, '[parameters(\'includeChat\')]');
});

test('preparation resolves the real endpoint from deployment metadata and stops on CLI failures', t => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'sqlai-metadata-'));
  t.after(() => fs.rmSync(temp, { recursive: true, force: true }));
  const output = path.join(temp, 'prepare.sql');
  const script = path.join(temp, 'metadata.ps1');
  const deployment = { properties: { provisioningState: 'Succeeded', outputs: {
    foundryAccountName: { value: 'foundry-actual-cu' },
    sqlServerFqdn: { value: 'sqlai-test-cu.database.windows.net' },
    databaseName: { value: 'Healthcare' }, includeChat: { value: true },
  } } };
  const account = { properties: { endpoint: 'https://other-endpoint.cognitiveservices.azure.com/',
    endpoints: { 'AI Foundry API': 'https://foundry-actual-cu.services.ai.azure.com/' } } };
  for (const cliExit of [0, 9]) {
    fs.writeFileSync(script, `
function az {
  param([Parameter(ValueFromRemainingArguments)] [string[]] $Arguments)
  $global:LASTEXITCODE = ${cliExit}
  if ($Arguments[0] -eq 'deployment') { ${psLiteral(JSON.stringify(deployment))} }
  else { ${psLiteral(JSON.stringify(account))} }
}
& ${psLiteral(path.join(directory, 'Prepare-Lab.ps1'))} -ResourceGroup test -DeploymentName test -GenerateOnly -OutputPath ${psLiteral(output)}
`);
    const result = spawnSync('pwsh', ['-NoProfile', '-File', script], { encoding: 'utf8' });
    if (cliExit === 0) {
      assert.equal(result.status, 0, result.stdout + result.stderr);
      const sql = fs.readFileSync(output, 'utf8');
      assert.match(sql, /DECLARE @Endpoint NVARCHAR\(4000\) = N'https:\/\/foundry-actual-cu\.services\.ai\.azure\.com';/);
      assert.match(sql, /CREATE OR ALTER PROCEDURE dbo\.AI_GENERATE_RESPONSE/);
      fs.unlinkSync(output);
    } else {
      assert.notEqual(result.status, 0);
      assert.match(result.stderr, /Azure CLI failed/);
      assert.equal(fs.existsSync(output), false);
    }
  }
});

test('SQL execution uses Entra auth, propagates sqlcmd failure, and removes temporary SQL', t => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'sqlai-execution-'));
  t.after(() => fs.rmSync(temp, { recursive: true, force: true }));
  const script = path.join(temp, 'execution.ps1');
  const captured = path.join(temp, 'arguments.json');
  fs.writeFileSync(script, `
$ErrorActionPreference = 'Stop'
function az { $global:LASTEXITCODE = 0 }
function sqlcmd {
  $Arguments = @($args)
  if ($Arguments[0] -eq '--help') {
    $global:LASTEXITCODE = 0
    'Usage: sqlcmd [flags] | sqlcmd [command]'
  } elseif ($Arguments[0] -eq '-?') {
    $global:LASTEXITCODE = 0
    '--authentication-method'
  } else {
    $Arguments | ConvertTo-Json | Set-Content -LiteralPath ${psLiteral(captured)}
    $global:LASTEXITCODE = 7
  }
}
& ${psLiteral(path.join(directory, 'Initialize-Lab.ps1'))} -Server sqlai-test-cu.database.windows.net -FoundryEndpoint https://foundry-test-cu.services.ai.azure.com
`);
  const result = spawnSync('pwsh', ['-NoProfile', '-File', script], { encoding: 'utf8' });
  assert.notEqual(result.status, 0, result.stdout + result.stderr);
  assert.match(result.stderr, /SQL initialization failed/);
  const args = JSON.parse(fs.readFileSync(captured, 'utf8'));
  assert.equal(args[args.indexOf('--authentication-method') + 1], 'ActiveDirectoryAzCli');
  assert(args.includes('-b'));
  assert(args.includes('-x'));
  assert.equal(fs.existsSync(args[args.indexOf('-i') + 1]), false);
});

test('desktop verification requires MSSQL but not Runme for the notebook-only attendee track', t => {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'sqlai-desktop-'));
  t.after(() => fs.rmSync(temp, { recursive: true, force: true }));
  const script = path.join(temp, 'desktop.ps1');
  for (const hasMssql of [true, false]) {
    fs.writeFileSync(script, `
$ErrorActionPreference = 'Stop'
function az { $global:LASTEXITCODE = 0; '2.90.0' }
function sqlcmd {
  $global:LASTEXITCODE = 0
  if ($args[0] -eq '--help') { 'Usage: sqlcmd [flags] | sqlcmd [command]' }
  elseif ($args[0] -eq '-?') { '--authentication-method ActiveDirectoryAzCli' }
  else { 'Version: v1.10.0' }
}
function code {
  $global:LASTEXITCODE = 0
  ${hasMssql ? "'ms-mssql.mssql'" : ''}
}
function winget { throw 'Verification must not install anything.' }
& ${psLiteral(path.join(directory, 'SetUp-Desktop.ps1'))}
`);
    const result = spawnSync('pwsh', ['-NoProfile', '-File', script], { encoding: 'utf8' });
    if (hasMssql) {
      assert.equal(result.status, 0, result.stdout + result.stderr);
      assert.match(result.stdout, /Desktop tools and MSSQL extension verified/);
    } else {
      assert.notEqual(result.status, 0);
      assert.match(result.stderr, /Missing VS Code extension: ms-mssql\.mssql/);
    }
  }
});
