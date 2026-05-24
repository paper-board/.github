# paperboard docs style guide

Governs all writing in `paper-board/.github/docs/` and per-service `docs/`. 15 rules.
Violations fail code review.

______________________________________________________________________

01. **Active voice.** "We chose Postgres" not "Postgres was chosen."

02. **Short paragraphs.** 3–5 sentences maximum.

03. **One idea per paragraph.**

04. **No emojis.**

05. **Define terms on first use; link to glossary thereafter.** First mention of "PVC" expands
    to "Persistent Volume Claim (PVC)". Subsequent uses: "PVC".

06. **Code blocks always carry a language hint.** Use ```` ```go ````, ```` ```sql ````, ```` ```yaml ````,
    ```` ```sh ````, ```` ```bash ````, ```` ```proto ````, ```` ```mermaid ````. Never bare triple-backtick.

07. **Headings:** H1 = page title (one per page only). H2 = major sections. H3 = subsections.
    Avoid H4+ unless absolutely required.

08. **Line length:** 100 chars in source Markdown (matches gofmt convention).

09. **Lists:** bulleted for unordered concepts; numbered for sequential steps.

10. **Tables:** ≤ 6 columns. If more, restructure as nested bulleted list.

11. **Cross-references:** relative paths (`../architecture/system-overview.md`); never bare
    URLs to other doc pages.

12. **External links:** only canonical sources (Go docs, K8s docs, RFC, ADR papers). No blog
    posts unless authoritative.

13. **Mermaid diagrams:** always copy the canonical `classDef` block from `diagram-theme.md`
    into every diagram. Do not abbreviate or omit any of the five class definitions.

14. **No marketing language.** "Best", "amazing", "powerful" are rejected. "Designed to do X",
    "implements Y", "solves Z" are accepted.

15. **Acronyms:** spell out on first use within a page. "Persistent Volume Claim (PVC)…
    PVC…"

______________________________________________________________________

## Tone matrix

| Block                                | Tone                                                            |
| ------------------------------------ | --------------------------------------------------------------- |
| Overview, Tutorial, Architecture Why | Linear handbook (narrative, opinionated)                        |
| API Reference                        | CockroachDB / Kubernetes (telegraphic, dense, signatures-first) |
| Operations                           | CockroachDB / Kubernetes (run-this-command-do-this)             |
| ADR mirror                           | ADR formal                                                      |

Examples:

| Block    | Wrong                                          | Right                                                                                                           |
| -------- | ---------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| Overview | "The agents service handles agent CRUD."       | "We split agents into its own service because session state and LLM streaming have different scaling profiles." |
| API Ref  | "When you create an agent you'll need a name." | "`POST /v1/agents`. Body: `{name: string, 1–64 chars}`. Returns `201` with `Agent`."                            |
| Tutorial | "agent CRUD entry point"                       | "First, create an agent. Then send it a message. Watch the SSE stream return tokens."                           |

______________________________________________________________________

## Code example discipline

General snippets (Overview, API Reference, Operations): real-code-extracted with source path
comment for any block > 3 lines.

```go
// from paper-board/agents/internal/handler/agent.go:42-58
func (h *Handler) CreateAgent(w http.ResponseWriter, r *http.Request) {
    // ...
}
```

Source comment syntax by language:

| Language             | Comment prefix |
| -------------------- | -------------- |
| `go`, `proto`        | `// from ...`  |
| `yaml`, `sh`, `bash` | `# from ...`   |
| `sql`                | `-- from ...`  |

Illustrative blocks ≤ 3 lines may omit the source comment.
