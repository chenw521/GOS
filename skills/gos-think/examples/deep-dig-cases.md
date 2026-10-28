# Deep-dig case records

Read this file before the first decision card of a session. It is the
working contract for what a real dig looks like: three case records, each
showing the dig, the card it produced, and one deepen round that followed.
Every dig starts from two questions — *who consumes this* and *what does
the real data say* — but they are a starting point, never a stopping
point. The three shapes here (a dig that reshapes a card, a card shown
without a dig, a dig that counts the corpus) are patterns to adapt to the
domain at hand, not a quiz to answer.

## Case 1: a dig that reshaped a card before it was shown

**The situation.** A maintenance task set out to harden a stale-lock check
in a command-line tool. Several commands share one lock file; when a
command finds the lock held by what looks like a dead process, it may
break the lock and continue. A first draft of the card carried three
options: keep the current same-process pass, replace the whole lock with
a shared design, or wrap the check in a retry loop.

**The dig.** Before showing the card, the session asked who actually
touches this lock. A search over the source tree counted the call sites:
three write-path commands nest (one command takes the lock, then calls a
second command that takes it again), while five read-only commands take it
once and exit. The nesting only survives because of the same-process pass
— and the pass is also blind to a second window: two tool processes
started in two terminals on the same machine can each believe the lock is
theirs. The premise of "keep the same-process pass, it is harmless
bookkeeping" was wrong: the pass is load-bearing for nesting and useless
against other processes. That option was killed before the card was
shown, and the option list was re-cut around the real consumer — the
second process.

**The card it produced.**

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| shared lock: one writer, many readers (chosen) | readers far outnumber writers (five read-only call sites vs three nesting writers) | nesting callers become plain readers; cross-process safety by design | full rewrite of the lock helper and its tests | the lock helper contract every command relies on when opening the shared state |
| retry loop around the current check | no API change | smallest diff | retries the same broken check faster; still blind to a dead owner | nothing new — the same single-user assumption |
| drop locking, rely on temp files | zero lock code | none worth naming | corrupts shared state on every concurrent write | the recovery tool a later session would have to write |

why-not: retry loop — it makes the failing check fail faster, not less;
drop locking — moves the cost onto an unknown future consumer.

recommendation: shared lock — conditional: the read/write split must
match the counted call sites; re-count before rewriting, and any new
nesting caller joins the readers first.

deepen: any option — ask for another dig round.

**The deepen round.**

new facts: a search of the open issue list found one report of two
tool starts in the same second on a shared machine — the second-process
consumer was real, not theoretical. The recommendation stood, and one
premise was tightened: "many readers" now names the five read-only
commands, not a guess.

## Case 2: a card shown without a dig, and what it cost

**The situation.** A cleanup task had to decide what to do with files
left behind in an archive folder after an aborted move — call them
orphans. The session wrote a card on the spot, from memory, with no dig.
It recommended building a new registration list: every file entering the
archive would be written into a central list, and a nightly check would
compare the list against the folder.

**What actually happened.** The user's first challenge was one question:
who reads the existing warning today? The answer, checked in the source
rather than remembered: when the cleanup scanner meets an unknown file,
it already prints a warning that names the adopt command — and that
warning is what prompted the last two adoptions. The warning was not
toothless; it was the working channel. A second fact surfaced in the same
exchange: the recommended option, stripped of its wording, added exactly
one new error code over the lightest option — a few lines, not a
subsystem. The card had been built on two untested premises, and both
were wrong.

**What the dig should have asked.** Two questions, both cheap: who
consumes the warning line (found by locating where its text is printed),
and what the heavy option adds in real lines. The dig would have taken
minutes and saved a full round of challenge.

**The corrected card.**

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| keep the warning, add a missing-file check (chosen) | the scanner warning is the working adoption channel (the last two adoptions came through it) | zero new surfaces; the check reuses the warning text | someone must read the output | the scanner warning that already moves files toward adoption |
| central registration list | a list forces registration where a warning only suggests | strictest guarantee | one new file to keep in sync; the archive and the list can drift apart | a nightly check that did not exist before |
| monthly manual sweep | a human sees everything | no tooling | adoptions wait up to a month | a maintainer's calendar |

why-not: registration list — solves a problem the warning was already
solving, and adds a second copy of the truth; manual sweep — turns a
machine check into a meeting.

recommendation: warning plus missing-file check — conditional: revisit a
harder mechanism only if files start arriving without passing the
scanner.

deepen: any option — ask for another dig round.

**The deepen round.**

new facts: reading the scanner source turned up a second warning path
with the same text but no adopt hint — half the warnings could not lead
to adoption. One sentence was added to that path; no option changed.

## Case 3: a dig through the corpus — counts before a card

**The situation.** A code-graph tool draws automatic edges between
modules by reading their import lines. For one analysis project — dozens
of small rule modules — the tool drew zero edges, and a card was about to
choose between manual edge entry, surgery on the import pattern, or
giving up on automatic edges for that language.

**The dig.** The session ran the root-cause hunt first. Reading the
import matcher showed its pattern requires a letter or an underscore at
the start of the module path. A count across the project corpus: all 37
rule modules use dotted relative imports, and none uses the plain
sibling form the pattern expects. The numbers closed the case: the
pattern matches zero lines not because the idea is wrong but because the
shape it expects never occurs in this corpus. The card's premise cells
carry those counts, so a reviewer can re-run the count and disagree with
numbers, not with adjectives.

**The card it produced.**

| Option | Premise | Pros | Cons | Activates |
|:--|:--|:--|:--|:--|
| extend the pattern to dotted imports (chosen) | all 37 rule modules import relatively; the current pattern matches zero lines | one pattern change turns zero auto edges into full coverage for the project | relative paths must resolve against the importing file | every future run of the graph tool on rule-style projects |
| manual edge entry | a human knows the graph best | no matcher change | dozens of entries, stale after every rename | a side file nobody re-checks |
| drop auto edges for this language | zero effort | honest output | the tool stops being useful for a whole class of projects | nothing — the feature simply ends |

why-not: manual entry — the counts show the import shape is regular,
which is exactly the case where machines win; drop the feature — the gap
is one pattern, not a design flaw.

recommendation: extend the pattern — conditional: the dotted form
resolves against the importing file's folder, and the count is re-run at
review time as proof.

deepen: any option — ask for another dig round.

**The deepen round.**

new facts: none. The fixed pattern was re-checked against the same
corpus and produced no further surprise — no new facts, and the deepen
port closes here.

---

What the three cases share: the dig always changes the card — a premise
rewritten, an option killed, or numbers put where adjectives were. Every
Activates cell names a consumer that was found, not assumed. And deepen
rounds live or die by their increment: a round that opens with new facts
earns its answer; a round that finds none closes the port honestly.
