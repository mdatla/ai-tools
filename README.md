# AI Tools

A Claude Code plugin marketplace for AI-assisted development workflows. 

## Installation

Add this marketplace to Claude Code:

```
/plugin marketplace add https://github.com/mdatla/ai-tools.git
```

## Available Plugins

### Librarian

Hierarchical memory library system that automatically loads project-specific context when editing files and captures learnings during sessions.

```
/plugin install librarian
/reload-plugins
```

See the [Librarian README](plugins/librarian/README.md) for full documentation.

## Contributing

To add a new plugin:

1. Create a directory under `plugins/` with your plugin name
2. Add `.claude-plugin/plugin.json` with plugin metadata
3. Add skills, hooks, scripts, and agents as needed
4. Register the plugin in `.claude-plugin/marketplace.json`
