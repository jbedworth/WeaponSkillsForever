# Changelog

Player-facing changes for each Weapon Skills Forever release, newest first. The
release builder copies the section for the TOC version into the GitHub release
notes and the CurseForge changelog, and fails if that section is missing.

## 0.1.1-beta

- Fixed a Lua error ("attempt to compare field 'modifier' (a secret number value)") when the game hides skill values, for example in combat. The box keeps the last values it saw, and never stops tracking a skill because its values are hidden.

- Works with Dyre's Toolkit: the skill box unlocks with every Dyre's AddOn (`/dyre unlock`), snaps to their frames and to the grid, and its settings sit under "Dyre's AddOns". With the toolkit, `/wsk lock` and `/wsk unlock` lock or unlock every Dyre's AddOn. Without the toolkit it works as before, and says once where to get it.
- With Dyre's Toolkit, the settings page and the setup panel no longer show their own lock checkbox: the toolkit's "Unlock frames" switch, `/dyre unlock`, and the minimap button do it for all Dyre's AddOns. Without the toolkit, the checkbox stays.

## 0.1.0-beta

- First public beta for WoW: Forever.
- A movable on-screen box shows up to six weapon skills or six other skills, switched with an icon toggle, each with a bar from 0 to the current cap: red more than 5 below the cap, yellow within 5, green at the cap.
- Choose tracked skills, weapon skills or professions, from the gear button, `/wsk config`, or the AddOn settings page (`/wsk options`).
- Group headers expand and collapse like the Skills tab's.
- Adjustable opacity for the box background and the skill rows, on the AddOn settings page.
- Settings and the box position are saved per character.
