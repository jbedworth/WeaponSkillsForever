# CurseForge listing

Copy-ready text for the CurseForge project form. Keep it aligned with README.md
and the tested client; do not advertise clients or versions that have not been
tested.

## Project fields

| Field | Value |
| --- | --- |
| Name | Weapon Skills Forever |
| Class | Addons |
| Main category | Quests & Leveling. Keep it identical to the TOC `## Category`, which groups the AddOn in the in-game AddOn list when Dyre's Toolkit is missing (with it, `## Group: DyresToolkit` nests WSK under the toolkit). |
| Relations | Dyre's Toolkit (slug `dyres-toolkit`), required dependency. CI uploads set it; add it by hand on any file uploaded through the website. |
| Additional categories | Professions, Warrior, Rogue, Hunter (CurseForge allows up to 4; unrelated ones can send the project back for changes). |
| Author shown | Dyre, set through the CurseForge account's username |
| License | MIT License |
| Source | https://github.com/jbedworth/WeaponSkillsForever |
| Issues | https://github.com/jbedworth/WeaponSkillsForever/issues |

## Summary

Track up to six weapon skills and six professions or other skills with on-screen progress bars that turn green when you hit the cap, for World of Warcraft: Forever.

## Description

Paste this with the description editor in Markdown mode. Pasted into the rich
text editor, the headings, bullets, and bold show as raw, escaped markdown.

Per-file changelogs need no manual text: each CI upload uses the version's
`CHANGELOG.md` section, through `release-notes.md`.

```markdown
**Weapon Skills Forever** keeps the skills you are leveling on screen. Weapon skills and professions are normally tucked away on the Skills tab of the Character window; WSK shows them as bars in a small, movable box, so you know the moment a skill is capped and it is time to switch weapons.

### Features
- A gold-bordered box with a bar for each tracked skill, from 0 to its current cap, filled to your rank.
- Bar colors: **red** more than 5 below the cap, **yellow** within 5, **green** at the cap.
- Track up to six weapon skills and six other skills, such as professions; a sword or book icon on the box switches between them.
- Choose skills from the gear button or `/wsk config`.
- Drag the box anywhere and adjust its opacity; its position and your choices are saved per character.
- Bonuses such as racial weapon bonuses are shown in green but do not count toward the cap, matching the Skills tab.

### Dyre's Toolkit
The CurseForge app installs Dyre's Toolkit with it: one layout mode (`/dyre unlock`) that snaps the box to other Dyre's AddOns' frames and to a grid, a minimap menu, and one settings home for all Dyre's AddOns. WSK still works without it.

### Commands
- `/wsk` (or `/wsk options`) opens the AddOn settings page (Options > AddOns, under Dyre's AddOns with Dyre's Toolkit). `/wsk config` opens the setup panel.
- `/wsk show` and `/wsk hide` show or hide the box. `/wsk help` lists the commands.
- `/weaponskills` works the same as `/wsk`, in case another AddOn uses `/wsk`.
- `/wsk lock`, `/wsk unlock`, and `/wsk reset` control the box position (with Dyre's Toolkit, lock and unlock apply to every Dyre's AddOn).

### Compatibility
Tested on the Forever beta client 1.60.1, build 70450. WSK keeps working on later beta builds; if a client update removes the skill API it needs, it disables itself with one chat message.

WowUp users (2.24.0 or later): install from the repository URL; GitHub releases carry the Forever metadata WowUp needs.

Source, issues, and license (MIT): https://github.com/jbedworth/WeaponSkillsForever
```
