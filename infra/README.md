# Host deployment and preparation

This package prepares the Azure resources and Windows desktop required by the
[four-notebook attendee track](../instructions/README.md). The skilling
provider supplies the VM, its build or first-login hooks, and a dedicated
resource group for each lab instance. This repository does not provision the VM
or implement provider-specific login automation.

## Package contents

- `main.bicep` and `main.json`: authoritative Bicep source and provider-loadable
  resource-group ARM template. Commit both together when changing infrastructure.
- `main.parameters.json`: example deployment parameters. Replace every
  `REPLACE-WITH-...` value before use.
- `SetUp-Desktop.ps1`: installs missing tools and the MSSQL extension only when
  explicitly invoked with `-Install`; otherwise it verifies them.
- `Prepare-Lab.ps1`: reads successful deployment outputs and the actual Foundry
  endpoint, then starts database initialization.
- `Initialize-Lab.ps1`: safely creates the starting schema and data using local
  SQL files in `sql/`.
- `Validate-Package.ps1` and `packaging.test.cjs`: local checks that do not
  create Azure resources or connect to SQL.

**ARM deployment success alone does not prepare a participant VM.** The host
must also arrange desktop setup and authenticated SQL initialization.

## 1. Configure and deploy Azure resources

The provider supplies:

| Parameter | Value |
|---|---|
| `administratorObjectId` | Participant Entra user object ID, or dedicated lab administrator group object ID |
| `administratorName` | That user's UPN or group's display name |
| `administratorType` | `User` (default) or `Group` |
| `desktopStartIpAddress`, `desktopEndIpAddress` | Actual public IPv4 egress range of the supplied desktop; identical for one IP |
| `labId` | Optional unique lowercase letters, numbers, and hyphens; defaults to a hash of the dedicated resource group ID |
| `location` | Defaults to `centralus`; check SQL feature availability and model quota before changing |
| `includeChat` | Defaults to `true`; deploys the optional intent-extraction model |

The template creates an Entra-only SQL server with a system-assigned identity,
the paid `Healthcare` General Purpose serverless database (Gen5, maximum 2
vCores, minimum 0.5 vCores, 60-minute auto-pause, 32 GB, local backup
redundancy), and a SQL firewall rule restricted to the supplied desktop egress
range. It does not use the full workshop's internet-wide firewall rule.

It also creates a Foundry `AIServices` S0 account, a `healthcare` project, and
`text-embedding-3-small` version `1`. When `includeChat` is enabled, it also
deploys `gpt-5-nano` version `2025-08-07`. Deployment names are fixed because
SQL references them. The SQL server identity receives **Cognitive Services
OpenAI User** at the Foundry account scope, and Foundry local-key authentication
is disabled.

Both model deployments default to `DataZoneStandard`, capacity 100 each.
Capacity units are model-specific; confirm quota and expected participant
concurrency before deployment. `GlobalStandard` is an explicit parameter choice
with a different processing boundary, not a silent fallback. Verify model
versions after rehearsal before changing parameters.

Register `Microsoft.Sql` and `Microsoft.CognitiveServices` in the subscription.
The deploying identity needs resource-creation permissions and
`Microsoft.Authorization/roleAssignments/write` at the relevant scope. The
participant database administrator is elevated for these exercises, not a
production application identity.

The provider can load `main.json` directly. To deploy with Azure CLI, prepare
the parameter file first:

```powershell
az login
az account set --subscription '<lab-subscription-id>'
az deployment group validate --resource-group '<dedicated-lab-resource-group>' --template-file infra\main.json --parameters '@infra\main.parameters.json'
az deployment group create --resource-group '<dedicated-lab-resource-group>' --name sqlai-lab --template-file infra\main.json --parameters '@infra\main.parameters.json'
```

The endpoint is resolved from Azure metadata. Never construct it from resource
names.

## 2. Prepare the supplied Windows desktop

Place the **whole repository**, including `infra/sql`, on the desktop. Install
PowerShell 7.2 or later and Windows Package Manager first. Run setup as the
same desktop profile participants will use; per-user VS Code extensions
installed in a different account are not sufficient.

```powershell
pwsh -NoProfile -File infra\SetUp-Desktop.ps1 -Install
pwsh -NoProfile -File infra\SetUp-Desktop.ps1
```

Setup verifies Azure CLI, VS Code, Go sqlcmd, and the MSSQL extension. If an
older ODBC `sqlcmd` shadows Go sqlcmd, the script fails with PATH instructions
instead of claiming compatibility. Installation may require provider-approved
elevation. No participant sign-in is baked into the image.

Open the repository root in VS Code and select the **MSSQL** notebook kernel.
The participant track uses SQL notebooks; Python, Jupyter, SSMS, and Runme are
not required. Permit desktop access to Azure sign-in and management, SQL,
Foundry, and extension download endpoints. Permit SQL outbound model access to
the public Foundry endpoint.

## 3. Initialize the participant starting state

Sign into Azure CLI as the configured SQL Entra administrator (or a member of
the configured administrator group), select the correct subscription, then run:

```powershell
pwsh -NoProfile -File infra\Prepare-Lab.ps1 -ResourceGroup '<dedicated-lab-resource-group>' -DeploymentName sqlai-lab
```

This operator preparation script reads successful deployment outputs and the
actual resource-level Foundry endpoint, then:

1. Creates the original `dbo.Cases`, `dbo.ComplaintEmbeddings`, and
   `dbo.SymptomEmbeddings` schema.
2. Loads and verifies the exact 207 synthetic cases from
   `infra/sql/02-seed-cases.sql`.
3. Creates the database master key and managed-identity credential using the
   actual endpoint.
4. Installs only `dbo.AI_GENERATE_RESPONSE` when chat is enabled.
5. Runs the Lab 1 readiness checkpoint without billed inference.

The SQL inputs in `infra/sql/` are extracted from the original notebook setup
cells so the official repository is self-contained. Preparation uses one
transaction and `sqlcmd -b`; failures terminate and uncommitted changes roll
back when the connection closes. Matching seeded data is preserved on a
pre-exercise rerun. Different existing case data, populated original embedding
tables, or participant retrieval objects cause an explicit refusal; there is
no reset or reseed switch.

Preparation does **not** create the external embedding model association, the
full-text index, retrieval chunks, embeddings, vector index, or retrieval
procedure; those are participant exercises. The optional chat helper does not
make a model call during preparation and cannot be executed until participants
register the external model. The SQL administrator identity has the DDL and
external REST permissions required by the exercises.

For offline inspection, use `Prepare-Lab.ps1` with `-GenerateOnly` and
`-OutputPath '<local-file.sql>'` to resolve Azure metadata without executing
SQL, or use `Initialize-Lab.ps1` with `-Server`, `-FoundryEndpoint`,
`-IncludeChat`, `-GenerateOnly`, and `-OutputPath` for offline SQL generation.

Before capturing a prepared VM image, sign out and remove build-account
authentication material using the provider's image-sanitization process. Never
capture Azure CLI token caches, VS Code sign-in state, or secrets.

## 4. Acceptance and teardown

In a **separate rehearsal instance**, run all four notebooks through the actual
MSSQL extension. Verify chunk coverage, complete embeddings, real model
inference, and the preview DiskANN indexed path with **Vector Index Seek** in
the actual execution plan. Infrastructure deployment and static checks do not
prove these capabilities. Measure embedding completion at expected class
concurrency, then prepare a clean instance for participants.

Use the provider's dedicated-resource-group lifecycle for hosted labs. If you
created the dedicated resource group yourself, delete only that group, wait for
deletion, and verify its absence. Foundry soft-deleted accounts may block reuse
of a name; inspect the exact retired account before restoring or irreversibly
purging it. Never purge unrelated resources. SQL storage and model usage are
billable.

## Validation

Use Node.js, PowerShell 7, Azure CLI with Bicep **0.48.1**, and the existing
ScriptDom 180.18.1 prerequisite described in the
[attendee SQL validation script](../tests/check-sql-syntax.ps1).

```powershell
az bicep build --file infra\main.bicep --outfile infra\main.json
pwsh -NoProfile -File infra\Validate-Package.ps1
node --test tests\retrieval.test.cjs tests\distribution.test.cjs
pwsh -NoProfile -File tests\check-sql-syntax.ps1
```

The package validator checks PowerShell syntax, package contracts, generated
SQL syntax, and parity between Bicep and ARM. These offline checks do not create
Azure resources, connect to SQL, call models, or replace VM and live feature
rehearsal.
