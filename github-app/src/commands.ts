// SPDX-Licence-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2025-2026 xaoscience

export interface ParsedCommand {
  /** Lower-cased command name, e.g. "combine". */
  name: string;
  /** Tokens after the command name (positionals and flags such as --sign). */
  args: string[];
  /** The original trimmed command line, for echoing back to the user. */
  raw: string;
}

/**
 * Extract every "<prefix> <name> [args…]" line from a comment body.
 * A line must start with the prefix to be considered a command.
 */
export function parseCommands(body: string, prefix: string): ParsedCommand[] {
  const commands: ParsedCommand[] = [];
  for (const line of body.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (trimmed !== prefix && !trimmed.startsWith(`${prefix} `)) {
      continue;
    }
    const rest = trimmed.slice(prefix.length).trim();
    if (!rest) {
      continue;
    }
    const parts = rest.split(/\s+/);
    commands.push({
      name: parts[0].toLowerCase(),
      args: parts.slice(1),
      raw: trimmed,
    });
  }
  return commands;
}

/** Split args into positionals and a set of flags (tokens starting with --). */
export function splitArgs(args: string[]): { positionals: string[]; flags: Set<string> } {
  const positionals: string[] = [];
  const flags = new Set<string>();
  for (const a of args) {
    if (a.startsWith("--")) {
      flags.add(a);
    } else {
      positionals.push(a);
    }
  }
  return { positionals, flags };
}
