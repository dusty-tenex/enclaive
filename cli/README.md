# enclaive CLI

Command-line tool for managing enclaive environments.

## Install

```bash
# Global install
npm install -g enclaive

# Or run directly
npx enclaive
```

## Commands

| Command | Description |
|---------|-------------|
| `init [dir]` | Initialize a new sandbox project |
| `up` | Start sandbox containers (with health check) |
| `down [--clean]` | Stop containers (--clean removes volumes) |
| `shell` | Open bash shell in sandbox |
| `run <cmd...>` | Run a command in the sandbox |
| `status` | Show container and guard status |
| `logs [-f] [-m mode] [-n lines]` | View/tail audit logs |
| `doctor` | Run diagnostic checks |

## Usage

```bash
# Initialize a project
enclaive init my-project

# Start the sandbox
enclaive up

# Check everything is working
enclaive doctor

# View recent blocks
enclaive logs -n 10

# Follow logs in real-time
enclaive logs -f

# Filter by guard mode
enclaive logs -m memory

# Open a shell
enclaive shell

# Run a one-off command
enclaive run ls -la

# Stop everything
enclaive down
```

## Output Style

All output uses plain text labels: [OK], [FAIL], [WARN], [INFO]. No emojis.

## Development

```bash
cd cli
npm install
npm test
```
