# xapicli — A Command-Line Interface for OpenAPI 3.0 REST APIs

`xapicli` converts an OpenAPI 3.0 specification into an interactive CLI that lets you call REST API endpoints directly from your terminal, with bash tab-completion support.

## Requirements

| Tool | Notes |
|------|-------|
| `bash` 3.2+ | macOS ships with 3.2; works as-is |
| `jq` | JSON processor |
| GNU `getopt` | macOS ships with BSD getopt (incompatible); GNU version is required |
| `node` + `npm` | Required for `json-refs` (used internally by `--init` to resolve `$ref` in OpenAPI specs) |
| Docker | Optional; only needed for the Petstore demo |

---

## Setup

### Step 1 — Install GNU getopt

macOS ships with BSD `getopt`, which does not support long options. Install the GNU version with Homebrew:

```bash
brew install gnu-getopt
```

Then add it to your `PATH`. Add the following line to your shell profile (`~/.zshrc` or `~/.bashrc`) and reload the shell:

```bash
export PATH="/opt/homebrew/opt/gnu-getopt/bin:$PATH"
```

```bash
# Apply immediately in the current session
source ~/.zshrc   # or source ~/.bashrc
```

### Step 2 — Install jq

```bash
brew install jq
```

### Step 3 — Install json-refs

`json-refs` is used internally by `xapicli --init` to resolve `$ref` references in OpenAPI spec files.

```bash
npm install -g json-refs
```

### Step 4 — Clone this repository

```bash
git clone https://github.com/tmonj1/xapicli.git
cd xapicli
```

### Step 5 — Source the script

xapicli must be **sourced** (not executed directly) so that bash tab-completion registers in the current shell:

```bash
source xapicli.sh
```

To make xapicli available in every terminal session, add this line to your `~/.zshrc` or `~/.bashrc`:

```bash
# Add to ~/.zshrc or ~/.bashrc
export XAPICLI_CONF_DIR=/path/to/xapicli/.xapicli
source /path/to/xapicli/xapicli.sh
```

### Step 6 — Set the configuration directory

xapicli looks for its configuration in `~/.xapicli` by default. To use the sample configuration included in this repository, point it to the `.xapicli` directory inside the project:

```bash
export XAPICLI_CONF_DIR=/path/to/xapicli/.xapicli
```

---

## Quick Start: Petstore Demo

This repository includes a Docker Compose file for running the [Swagger Petstore](https://github.com/swagger-api/swagger-petstore) API locally, and a ready-to-use xapicli configuration for it.

### 1. Start the Petstore server

```bash
docker compose -f examples/docker-compose.yml up -d
```

The API will be available at `http://localhost:8080/api/v3/`.

### 2. Source xapicli and set the config directory

```bash
export XAPICLI_CONF_DIR=/path/to/xapicli/.xapicli
source /path/to/xapicli/xapicli.sh
```

### 3. Try some commands

```bash
# Show all available endpoints
xapicli --summary

# GET /store/inventory
xapicli get /store/inventory

# GET with a path parameter
xapicli get /pet/99

# GET /pet/findByStatus (with a query parameter)
xapicli get /pet/findByStatus -q status available

# POST /pet (with body parameters)
xapicli post /pet -p name "My Dog" -p status available -p photoUrls "http://example.com/photo.jpg"

# POST /pet (with raw JSON body)
xapicli post /pet -d '{"name": "My Dog", "status": "available", "photoUrls": ["http://example.com/photo.jpg"]}'

# PUT /pet with an array parameter (repeat -p for the same key)
xapicli put /pet -p id 1 -p name "My Dog" -p photoUrls "http://example.com/a.jpg" -p photoUrls "http://example.com/b.jpg" -p status available

# PUT /pet with an object parameter (dot notation)
xapicli put /pet -p id 1 -p name "My Dog" -p category.id 2 -p category.name "Dogs" -p photoUrls "http://example.com/photo.jpg" -p status available

# DELETE /pet/{petId}
xapicli delete /pet/1
```

### 4. Tab completion

After sourcing the script, tab completion is available:

```
$ xapicli <TAB>
  get  post  put  delete

$ xapicli get <TAB>
  /pet/findByStatus  /pet/{petId}  /store/inventory  ...

$ xapicli get /pet/findByStatus <TAB>
  -q  --summary  --help  -d

$ xapicli get /pet/findByStatus -q <TAB>
  status

$ xapicli get /pet/findByStatus -q status <TAB>
  available  pending  sold
```

---

## Adding Your Own API

### Step 1 — Run `--init`

```bash
xapicli --init your-api-spec.json
```

This single command:
1. Resolves all `$ref` references in the spec using `json-refs`
2. Transforms the spec into xapicli's internal API definition format
3. Saves the result to `$XAPICLI_CONF_DIR/apis/<name>.json`
4. Creates or updates `$XAPICLI_CONF_DIR/xapicli.conf` with the new API entry

The API name is derived from the spec filename (e.g., `your-api-spec.json` → `your-api-spec`).

### Step 2 — Set the base URL

If the spec contains a `servers[0].url` entry, it is used automatically. Otherwise, edit `$XAPICLI_CONF_DIR/xapicli.conf` and set the `url` field:

```json
{
  "default": "your-api-spec",
  "your-api-spec": {
    "openapispec": "your-api-spec.json",
    "apidef": "your-api-spec.json",
    "url": "https://your-api-base-url/"
  }
}
```

---

## Usage Reference

```
xapicli <method> <resource> [options]

Methods:
  get | post | put | delete

Options:
  --init <spec-file>     Initialize API from an OpenAPI spec file
  -H <header: value>     Custom HTTP header (repeatable)
  -q <name> <value>      Query parameter (repeatable)
  -p <name> <value>      Body parameter (repeatable); builds a JSON object
                           - Repeat the same name to build a JSON array:
                             -p tags foo -p tags bar  →  {"tags":["foo","bar"]}
                           - Use dot notation for nested objects:
                             -p category.id 1 -p category.name Dogs  →  {"category":{"id":"1","name":"Dogs"}}
  -d <json>              Raw JSON body (overrides -p)
  --summary[=<resource>] Print available endpoints (optionally filtered by resource)
                           Required params are marked with *, array params with []
  --summary-csv          Print endpoints in CSV format
  --help                 Show usage

Environment variables:
  XAPICLI_CUSTOM_HEADER  Custom HTTP header(s) applied to every request.
                           Use newlines to specify multiple headers:
                           export XAPICLI_CUSTOM_HEADER=$'Authorization: Bearer token\nX-Tenant: acme'
```

### Examples

```bash
# Show all endpoints
xapicli --summary

# Show endpoints for a specific resource
xapicli --summary=/pet

# Show a specific method + resource
xapicli get /pet/findByStatus --summary

# GET with a query parameter
xapicli get /pet/findByStatus -q status available

# GET with a path parameter
xapicli get /pet/99

# POST with body parameters
xapicli post /pet -p name "My Dog" -p status available -p photoUrls "http://example.com/photo.jpg"

# POST with raw JSON body
xapicli post /pet -d '{"id": 1, "name": "My Dog", "status": "available"}'

# PUT with an array parameter (repeat the same key to build a JSON array)
xapicli put /pet -p id 1 -p name "My Dog" -p photoUrls "http://example.com/a.jpg" -p photoUrls "http://example.com/b.jpg" -p status available

# PUT with an object parameter (dot notation for nested fields)
xapicli put /pet -p id 1 -p name "My Dog" -p category.id 2 -p category.name "Dogs" -p photoUrls "http://example.com/photo.jpg" -p status available

# DELETE
xapicli delete /pet/1
```

---

## Limitations

- `$ref` must be pre-resolved with `json-refs` before processing
- Only `application/json` request bodies are recognized
- Array parameters are supported only when items are scalar types (string, integer, etc.); arrays of objects are not supported
- Object parameters are supported one level deep via dot notation; deeper nesting is not supported
- Authentication headers can be passed via `-H "Authorization: Bearer token"` or the `XAPICLI_CUSTOM_HEADER` env var
- `explode` and deeply nested object constraints are not enforced

---

## Development

**Required tools:**

- [`shfmt`](https://github.com/mvdan/sh) — shell script formatter (configured via the VSCode [ShellFormat](https://marketplace.visualstudio.com/items?itemName=foxundermoon.shell-format) extension)
- [`shellcheck`](https://www.shellcheck.net/) — shell script linter

**Install:**

```bash
brew install shfmt shellcheck
```

Set the `shfmt` path in `.vscode/settings.json`:

```json
{
  "shellformat.path": "/opt/homebrew/bin/shfmt"
}
```
