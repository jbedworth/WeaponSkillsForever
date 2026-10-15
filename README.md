# Weapon Skills Forever

Track the skills you are leveling, right on your screen, in World of Warcraft:
Forever. Weapon skills and professions are normally hidden on the Skills tab of
the Character window. Weapon Skills Forever shows up to six weapon skills and
six other skills as bars in a small box, so you can see at a glance when a skill is capped and it is time
to switch weapons or move on.

## Purpose

Leveling a weapon skill, or grinding a profession, means opening the Character
window again and again to check progress. WSK keeps those numbers visible while
you play, and colors each bar by how close it is to the cap.

## Compatibility

WSK is tested on the Forever beta, `1.60.1` build `70338`, Interface `16001`,
Lua `5.1`. It does not check the client version or build, because beta builds
change several times a week. It checks at login for the skill API it needs
(`C_SkillInfo`) and disables itself with one message if it is missing.

## Using it

- **The skill box** shows each tracked skill's name and a bar from 0 to the
  skill's current cap, filled to your base rank. The bar text shows
  `rank / cap`, with any bonus in green, for example `297 (+5) / 300`.
  - **Red:** more than 5 ranks below the cap.
  - **Yellow:** within 5 ranks of the cap.
  - **Green:** at the cap.
- **Drag** the box to move it. The position is saved per character.
- **The view toggle** (the sword or book icon beside the gear) switches the box
  between weapon skills and other skills, such as professions. Each view lists
  its skills in the Skills tab's order. Weapon skills are everything in the
  Skills tab's Weapon Skills group, including Defense.
- **The gear button** opens the setup panel. Check up to **six** weapon skills
  and **six** other skills to track. Skills are grouped as on the Skills tab. Skills with a single rank,
  such as armor proficiencies, Class Skills, and Languages are not listed.
  Group headers work like the Skills tab: click **+** to expand a group and
  **−** to collapse it, which changes the Skills tab the same way. As there, a
  collapsed group hides all its skills; tracked skills always stay in the box.
- Bonuses, such as racial weapon bonuses, are shown but do not count toward the
  cap, matching Blizzard's Skills tab: a bar turns green when your base rank can
  rise no further.
- **Options → AddOns → Weapon Skills Forever** (or `/wsk options`) has the same
  controls in the game's settings: show or hide the box, lock it, reset its
  position, choose tracked skills, and set the **opacity** of the box
  background (default 50%) and of the skill rows (default 90%). Layout
  (horizontal) and theme options are shown there as previews and are not yet
  available.

### Commands

| Command | Effect |
| --- | --- |
| `/wsk` | Show or hide the skill box |
| `/wsk config` | Open or close the setup panel |
| `/wsk options` | Open the AddOn settings page |
| `/wsk show`, `/wsk hide` | Show or hide the skill box |
| `/wsk lock`, `/wsk unlock` | Stop or allow dragging the box |
| `/wsk reset` | Move the box back to its default position |
| `/wsk debug_skills` | Print what the client reports about your skill lines |

## Installation

Extract a release ZIP into `Interface/AddOns/`, giving:

```text
WeaponSkillsForever/
    WeaponSkillsForever.toc
    Commands.lua
    Skills.lua
    Core.lua
    UI.lua
    LICENSE
```

The TOC loads Commands, Skills, Core, then UI, and saves settings per character
in `WeaponSkillsForeverDB`. WSK ships no texture files; it uses built-in client
textures only.

## Development

| File | Responsibility |
| --- | --- |
| `Commands.lua` | `/wsk` command parsing and dispatch. |
| `Skills.lua` | Capability checks, trackable-skill rules, and cap status. |
| `Core.lua` | Events, saved settings, tracking limits, login banner, and diagnostics. |
| `UI.lua` | The skill box and the setup panel. |
| `tests/run.lua` | Isolated Lua 5.1 tests with WoW API mocks. |
| `scripts/` | Standard-library Python release builder, provenance verifier, CurseForge uploader, and version lookup. |
| `CHANGELOG.md` | Player-facing changes per release; required by the builder. |
| `TESTING.md` | Verification method, pinned source evidence, and in-client checklist. |
| `docs/RELEASE_PLAN.md` | Packaging, CI, and publication process. |
| `AGENTS.md` | Maintenance rules and agreed project constraints. |

From the Git Bash repository root:

```sh
.tools/luarocks-3.13.0-win32/win32/lua5.1/bin/lua5.1.exe tests/run.lua
.tools/python-3.13.7/python.exe -m unittest discover -s tests -p 'test_*.py'
.tools/python-3.13.7/python.exe scripts/build_release.py --output dist
```

`.tools/` is ignored and holds portable Lua 5.1, Python 3.13.7, and actionlint
for Windows. CI uses native tools on `ubuntu-24.04`.

## License

Code uses the [MIT License](LICENSE). Copyright (c) 2026 John Bedworth.
