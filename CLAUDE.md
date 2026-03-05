# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`xapicli` is a bash-based CLI tool that converts OpenAPI 3.0 specs into an interactive command-line interface for making REST API calls, with bash tab-completion support.

## Development Environment Setup

**macOS (Apple Silicon):**
```bash
brew install gnu-getopt
export PATH="/opt/homebrew/opt/gnu-getopt/bin:${PATH}"
```

**Required tools:** `bash`, `jq`, `getopt` (GNU version), `shfmt` (for formatting), `shellcheck` (for linting)

**Formatting:** Uses `shfmt` via the VSCode ShellFormat extension. Set `shellformat.path` in `.vscode/settings.json` to the `shfmt` binary path.

**Note:** The codebase targets bash 3.2 (macOS default). Avoid bash 4.0+ features such as `${var^^}` or `readarray -t`.

## Workflow: Adding an API

```bash
# 1. Install json-refs (used internally by --init)
npm install -g json-refs

# 2. Initialize the API (resolves $refs and generates the API definition in one step)
export XAPICLI_CONF_DIR=${PWD}/.xapicli
xapicli --init examples/petstore-oas3.json
```

## Architecture

The project has two main components:

### `xapicli.sh` (sourced, not executed)
The script is designed to be **sourced** (`source xapicli.sh`), not run directly. This is required for bash completion to register in the current shell.

- **`_xapicli_completion()`** — Bash completion handler registered via `complete -F`. Completes:
  - HTTP methods after `xapicli`
  - Resource paths filtered by the selected method
  - Options (`-q`, `-p`, `-d`, `--summary`, `--help`) after a resource path; only options relevant to the endpoint are shown (e.g. `-q` only appears if the endpoint has query parameters)
  - Query/post parameter names after `-q`/`-p`
  - Enum values after a parameter name (when the parameter has an `enum` constraint)
  - API definition is cached in a global variable to avoid re-reading the file on every keypress
- **`xapicli()`** — Main CLI function. Parses args with GNU `getopt`, loads the API definition, and executes HTTP requests via `curl`. Supports GET, POST, PUT, DELETE.
  - POST/PUT bodies are assembled from `-p` flags or passed raw via `-d`
  - Array parameters: repeat the same `-p` name → `{"tags":["a","b"]}`
  - Dot-notation object parameters: `-p category.id 1` → `{"category":{"id":"1"}}`
  - Path parameters (e.g., `/pet/99`) are matched to templates (e.g., `/pet/{petId}`) via jq regex
  - `-h`/`--help`, `--version`, and `--init` are handled before config loading
- **`_xapicli_init()`** — Handles `--init <spec-file>`. Runs `json-refs resolve` on the spec, applies the embedded jq filter (formerly `install-api.jq`), writes the result to `$XAPICLI_CONF_DIR/apis/`, and updates `xapicli.conf`.

### API definition format (output of `--init`)
A jq filter embedded in `_xapicli_init()` transforms a resolved OpenAPI 3.0 `paths` object into a flat JSON structure used at runtime:
```json
{
  "/pet": [
    {
      "method": "post",
      "query_parameters": [{"name": "status", "type": "string", "required": false, "enum": ["available", "pending", "sold"]}],
      "post_parameters": [
        {"name": "name", "type": "string", "required": true},
        {"name": "photoUrls", "type": "array", "items": {"type": "string"}, "required": true},
        {"name": "category.id", "type": "integer"},
        {"name": "category.name", "type": "string"}
      ]
    }
  ]
}
```
Key transformation rules:
- Only `application/json` request bodies are recognized
- `$refs` are pre-resolved automatically by `--init` via `json-refs`
- `query_parameters`: includes `enum` field for tab completion; object/array type query params are excluded
- `post_parameters`: object-type properties are flattened one level into dot-notation entries (e.g., `category` → `category.id`, `category.name`); array-type properties with scalar items are included with `type: "array"`; arrays of objects and deeper nesting are excluded
- Required parameters are marked with `required: true`
- GET/DELETE endpoints do not have a `post_parameters` field

### Configuration (`.xapicli/xapicli.conf`)
```json
{
  "default": "petstore",
  "petstore": {
    "openapispec": "../examples/petstore-oas3.json",
    "apidef": "petstore-oas3.json",
    "url": "http://localhost:8080/api/v3/"
  }
}
```
The `apidef` field points to the processed file under `.xapicli/apis/`. `XAPICLI_CONF_DIR` env var overrides the default `$HOME/.xapicli` location.

## CLI Usage

```bash
source xapicli.sh

xapicli [options] <method> <resource> [params]
Options:
  -h, --help                Show this help message
  --version                 Show version
  --init <spec-file>        Initialize API from an OpenAPI spec file
  --summary[=<resource>]    Print available endpoints; required params marked *, array params marked []
  --summary-csv             Print endpoints in CSV format
Params:
  -q <name> <value>         Query parameter (repeatable)
  -p <name> <value>         Body parameter (repeatable); builds a JSON object
                              Repeat the same name for array params: -p tags a -p tags b → {"tags":["a","b"]}
                              Use dot notation for object params: -p category.id 1 → {"category":{"id":"1"}}
  -d <json>                 Raw JSON body (overrides -p)
```

## Code Modification Workflow

When modifying source code, follow these steps unless instructed otherwise:

1. Create a GitHub issue for the change (if one does not already exist)
2. Create a new topic branch from `main` and make the fix there
3. Commit the changes to the topic branch
4. Push the topic branch to GitHub
5. Create a Pull Request

Individual instructions take precedence — e.g. "skip the issue", "don't open a PR yet" override the above steps.

## Known Limitations

- `$refs` in OpenAPI specs must be pre-resolved with `json-refs`
- Only `application/json` request bodies are supported
- Array parameters are supported only when items are scalar types; arrays of objects are not supported
- Object parameters are supported one level deep via dot notation; deeper nesting is not supported
- `explode` is not supported
- Authentication headers must be added manually (not supported natively)
