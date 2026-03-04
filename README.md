# xapicli — A Command-Line Interface for OpenAPI 3.0 REST APIs

`xapicli` converts an OpenAPI 3.0 specification into an interactive CLI that lets you call REST API endpoints directly from your terminal, with bash tab-completion support.

## Requirements

| Tool | Notes |
|------|-------|
| `bash` 3.2+ | macOS ships with 3.2; works as-is |
| `jq` | JSON processor |
| GNU `getopt` | macOS ships with BSD getopt (incompatible); GNU version is required |
| `node` + `npm` | Required for `json-refs` (resolves `$ref` in OpenAPI specs) |
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

`json-refs` resolves `$ref` references in OpenAPI spec files before xapicli can process them.

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
docker compose up -d
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

# GET /pet/findByStatus (with a query parameter)
xapicli get /pet/findByStatus -q status available

# POST /pet (with body parameters)
xapicli post /pet -p name "My Dog" -p status available

# POST /pet (with raw JSON body)
xapicli post /pet -d '{"name": "My Dog", "status": "available"}'

# DELETE /pet/{petId}
xapicli delete /pet/1
```

### 4. Tab completion

After sourcing the script, tab completion is available:

```
$ xapicli <TAB>                         # → get  post  put  delete
$ xapicli get <TAB>                     # → resources that support GET
$ xapicli get /pet/findByStatus -q <TAB> # → available query parameters
```

---

## Adding Your Own API

### Step 1 — Prepare the OpenAPI spec

xapicli requires all `$ref` references to be resolved first:

```bash
json-refs resolve your-api-spec.json > your-api-spec-resolved.json
```

### Step 2 — Generate the xapicli API definition

```bash
cat your-api-spec-resolved.json | jq -f install-api.jq > .xapicli/apis/your-api.json
```

### Step 3 — Register the API in the config file

Edit `.xapicli/xapicli.conf`:

```json
{
  "default": "your-api",
  "your-api": {
    "openapispec": "../path/to/your-api-spec.json",
    "apidef": "your-api.json",
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
  -q <name> <value>      Query parameter (repeatable)
  -p <name> <value>      Body parameter — builds a JSON object (repeatable)
  -d <json>              Raw JSON body (overrides -p)
  --summary[=<resource>] Print available endpoints (optionally filtered by resource)
  --summary-csv          Print endpoints in CSV format
  --help                 Show usage
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

# GET with multiple query parameters
xapicli get /pet/findByStatus -q status available -q limit 10

# POST with body parameters
xapicli post /pet -p name "My Dog" -p status available

# POST with raw JSON body
xapicli post /pet -d '{"id": 1, "name": "My Dog", "status": "available"}'

# PUT
xapicli put /pet -p id 1 -p name "My Dog" -p status sold

# DELETE
xapicli delete /pet/1
```

---

## Limitations

- `$ref` must be pre-resolved with `json-refs` before processing
- Only `application/json` request bodies are recognized
- Object-type and array-type parameters are silently filtered out
- Authentication headers must be added manually (not supported natively)
- `enum`, `explode`, and nested object constraints are not enforced

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
