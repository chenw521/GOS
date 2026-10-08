/**
 * GOS plugin for OpenCode.ai
 *
 * Registers GOS skills directory + injects gos-router bootstrap.
 * Works alongside the gos CLI (npm-installed) which provides hard gates.
 *
 * v0.5: updated to reference three-layer architecture and CLI integration.
 */

import path from 'path';
import fs from 'fs';
import os from 'os';
import { fileURLToPath } from 'url';

const pkg = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../../package.json'), 'utf-8'));

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const extractFrontmatter = (content) => {
  const match = content.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/);
  if (!match) return { frontmatter: {}, content };
  const body = match[2];
  const frontmatter = {};
  for (const line of match[1].split('\n')) {
    const colonIdx = line.indexOf(':');
    if (colonIdx > 0) {
      const key = line.slice(0, colonIdx).trim();
      const value = line.slice(colonIdx + 1).trim().replace(/^["']|["']$/g, '');
      frontmatter[key] = value;
    }
  }
  return { frontmatter, content: body };
};

export const GOSPlugin = async ({ client, directory }) => {
  const homeDir = os.homedir();
  const gosSkillsDir = path.resolve(__dirname, '../../skills');

  const getBootstrapContent = () => {
    const skillPath = path.join(gosSkillsDir, 'gos-router', 'SKILL.md');
    if (!fs.existsSync(skillPath)) return null;

    const fullContent = fs.readFileSync(skillPath, 'utf8');
    const { content } = extractFrontmatter(fullContent);

    // gos:core-shortlist begin
    const cliHint = `**GOS CLI (if installed via npm):**
- \`gos\` (no args) = status + what's next (zero-memorization entry)
- \`gos init <level> "<intent>"\` = start task
- \`gos commit <stage>\` = atomic commit + stage advance
- \`gos gate all\` = hard gates (exit 1 on failure — weak-model safe)
- \`gos context <stage>\` = pre-computed context JSON (read_files + decisions + gates)
- \`gos resume\` = print summary for a fresh session
- \`gos instructions <stage>\` = stage-by-step guidance
- \`gos phase <sub>\` = Lv4 phase lifecycle (add | list | claim)
- \`gos decision <sub>\` = record/amend truth-source decisions
- \`gos help [--json]\` = full capability discovery

Full capability: \`gos help [--json]\` — human pages are decorative; --json is the sole legal machine mode.

<HARD-INSTRUCTION>
Before starting ANY development task in this session, run \`gos\` (no
arguments) first. It reports active task state and what to do next.
</HARD-INSTRUCTION>

**Three-Layer Architecture:**
- Lv0-2 (Engineer/Superpowers DNA): build/review/verify
- Lv3 (Designer/OpenSpec DNA): think/plan/ship phase lifecycle
- Lv4 (Chief Designer/GSD DNA): gos-project manages PROJECT/ROADMAP/DECISIONS/REQUIREMENTS

**State:** .gos/state.json (gitignored) — enables cross-session resume.
**Artifacts:** .gos/ (half-committed: project/ + archive/ in git, state.json local).`;
    // gos:core-shortlist end

    return `<GOS_INSTRUCTIONS>
You have GOS (Get Organized System) v${pkg.version} — an adaptive three-layer workflow plugin.

${content}

${cliHint}
</GOS_INSTRUCTIONS>`;
  };

  return {
    config: async (config) => {
      config.skills = config.skills || {};
      config.skills.paths = config.skills.paths || [];
      if (!config.skills.paths.includes(gosSkillsDir)) {
        config.skills.paths.push(gosSkillsDir);
      }
    },

    'experimental.chat.system.transform': async (_input, output) => {
      const bootstrap = getBootstrapContent();
      if (bootstrap) {
        (output.system ||= []).push(bootstrap);
      }
    },
  };
};
