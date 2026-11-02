## Before you're done

This repo has been created for your Microsoft Ignite 2026 session. Here's how to get it ready.

**Easiest path — use the agent (recommended):**

- Open GitHub Copilot Chat and say `help me initialize repo`. The agent will walk you through getting the README populated.
- When you're ready to publish, say `help me finalize repo`. The agent will clean up unused folders, validate everything, and remove this "Before you're done" section and other extra stuff that attendees don't need to see.
- Curious how it works? Read the [agent workflow](.github/AGENT-WORKFLOW.md).

**Doing it manually?**

Fill in the sections below yourself, then:

- Delete any placeholder folders you don't need (`data/`, `infra/`, etc.)
- Delete this "Before you're done" section
- Delete `.github/agents/`, `.github/tests/`, `.github/copilot-instructions.md`, and `.github/AGENT-WORKFLOW.md` — these are template tooling, not part of your published repo

**Folder conventions:**

- Attendee step-by-step guidance goes in `instructions/`. If you use MkDocs or a docs site instead, put it in `docs/` and link to it from this README.
- Reference material and background reading go in `docs/`.
- You can add a `.devcontainer/` folder if needed.

---

<a name="start-building"></a>

<p align="center">
<img src="img/banner-ignite-26.png" alt="Microsoft Ignite 2026" width="100%"/>
</p>

# [Microsoft Ignite 2026](https://ignite.microsoft.com)

## 🔥 LAB693: Building search for AI apps and agents with Azure SQL Database
### Session description

Build a retrieval foundation for reliable AI experiences with Azure SQL Database
and Microsoft Foundry. In four SQL notebooks, follow 207 synthetic clinical
cases from full-text search through embeddings, vector search, and hybrid
ranking with reciprocal rank fusion (RRF). An optional final exercise extracts
intent from a narrative and routes focused requests to retrieval.

This lab demonstrates retrieval techniques; it does not build an autonomous
agent or provide medical advice, diagnoses, or treatment guidance.

### 🚀 Getting started

#### In a guided session

If you're following along during a live session, use the dedicated lab
environment provided by your host:

1. Open this repository in Visual Studio Code and select the **MSSQL** kernel.
2. Connect to the prepared `Healthcare` database with your assigned Microsoft
   Entra account. Do not connect to `master`, a shared database, or production data.
3. Open [Lab 1: Beyond Keywords](instructions/01-beyond-keywords.ipynb) and run
   the readiness checkpoint. Every required check must say **Yes**.
4. Follow the [attendee guide](instructions/README.md) and complete all four
   notebooks in order, one SQL cell at a time—not **Run All**.

#### On your own

The notebooks require a prepared Azure environment; cloning this repository
alone does not create one.

1. Clone the repository and install Visual Studio Code with the MSSQL extension.
2. Review the [lab setup and prerequisites](instructions/README.md).
3. Prepare a dedicated lab environment using the [host deployment guide](infra/README.md).
4. Start with [Lab 1](instructions/01-beyond-keywords.ipynb), then follow the
   attendee guide and continue through the notebooks:

   - [1. Beyond Keywords](instructions/01-beyond-keywords.ipynb)
   - [2. From Case Notes to Vectors](instructions/02-case-notes-to-vectors.ipynb)
   - [3. Search by Meaning](instructions/03-search-by-meaning.ipynb)
   - [4. From Narrative to Better Results](instructions/04-narrative-to-results.ipynb)

### 🎯 Learning outcomes

By the end of this session, you will be able to:

- Explain how full-text retrieval and semantic vector search can complement
  one another when matching a request to relevant case text.
- Prepare traceable chunks and embeddings, compare exact and approximate
  vector search, and verify when the vector index is used.
- Combine lexical and semantic ranks with RRF and optionally route validated
  intent to retrieval without making intent detection a prerequisite.

### 💻 Technologies used

- **Azure SQL Database and T-SQL:** [full-text search](https://learn.microsoft.com/en-us/sql/relational-databases/search/full-text-search),
  text chunking, vector embeddings, cosine-distance [vector search and indexes](https://learn.microsoft.com/en-us/sql/t-sql/functions/vector-search-transact-sql?view=sql-server-ver17),
  DiskANN, and RRF hybrid ranking.
- **Microsoft Foundry:** [`text-embedding-3-small` embeddings](https://learn.microsoft.com/en-us/azure/foundry/openai/how-to/embeddings) and the optional
  `gpt-5-nano` intent-extraction exercise.
- **Microsoft Entra ID and managed identity:** [authenticate to Azure SQL](https://learn.microsoft.com/en-us/azure/azure-sql/database/authentication-aad-overview?view=azuresql)
  and let the SQL server identity [call external REST endpoints](https://learn.microsoft.com/en-us/sql/relational-databases/system-stored-procedures/sp-invoke-external-rest-endpoint-transact-sql?view=sql-server-ver17)
  without embedding API keys in the lab.
- **Visual Studio Code and the MSSQL extension:** run and inspect
  [SQL notebooks](https://learn.microsoft.com/en-us/sql/tools/visual-studio-code-extensions/mssql/mssql-sql-notebooks?view=sql-server-ver17).

The optional [intent exercise](instructions/04-narrative-to-results.ipynb)
requires additional host setup. Azure resources and model inference can incur
charges. Read the [attendee guide](instructions/README.md) for safety, cost,
readiness, recovery, and cleanup details.

### 📚 Continue your learning

Pick your next step based on your learning style:

| Resource | What you'll get |
|----------|-----------------|
| **[Ignite 2026 Next Steps](https://aka.ms/ignite26-next-steps)** | Additional session repos and materials from Microsoft Ignite 2026 |
| **[Microsoft AI Skills Navigator](https://aka.ms/ignite26-asn)** | Discover AI skills, learning paths, and resources for your next step |
| **[Microsoft Learn](https://aka.ms/ignite26-learn)** | Official documentation and guided learning paths on these topics |
| **[Microsoft Foundry Community](https://aka.ms/MicrosoftFoundryDiscord-Ignite26)** | Connect with other learners and experts in our Discord community |

### 🌟 Microsoft Learn MCP Server

<!-- Remove this section if the Microsoft Learn MCP Server is not relevant to the session. -->

The Microsoft Learn MCP Server gives your AI agent direct access to Microsoft's official documentation — grounded, up-to-date answers about the topics in this session.

**GitHub Copilot CLI** — Install with:

```shell
copilot plugin install microsoftdocs/mcp
```

**VS Code** — One-click install:  
[![Install in VS Code](https://img.shields.io/badge/VS_Code-Install_Microsoft_Learn_MCP-0098FF?style=flat-square&logo=visualstudiocode&logoColor=white)](https://vscode.dev/redirect/mcp/install?name=microsoft-learn&config=%7B%22type%22%3A%22http%22%2C%22url%22%3A%22https%3A%2F%2Flearn.microsoft.com%2Fapi%2Fmcp%22%7D)

For more information, visit the [Learn MCP Server repo](https://aka.ms/learnmcp).

### 👥 Content owners

<table>
<tr>
    <td align="center"><a href="https://github.com/Iqra617">
        <img src="https://github.com/Iqra617.png" width="100px;" alt="Iqra Shaikh"/><br />
        <sub><b>Iqra Shaikh</b></sub></a><br />
            <a href="https://github.com/Iqra617" title="talk">📢</a>
    </td>
    <td align="center"><a href="https://github.com/itsnotaboutthecell">
        <img src="https://github.com/itsnotaboutthecell.png" width="100px;" alt="Alex Powers"/><br />
        <sub><b>Alex Powers</b></sub></a><br />
            <a href="https://github.com/itsnotaboutthecell" title="talk">📢</a>
    </td>
</tr></table>

### ⚖️ Trademarks

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft trademarks or logos is subject to and must follow [Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/legal/intellectualproperty/trademarks/usage/general). Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship.

Any use of third-party trademarks or logos are subject to those third-party's policies.
