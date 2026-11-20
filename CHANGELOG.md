# Changelog

Player-facing changes for each Weapon Skills Forever release, newest first. The
release builder copies the section for the TOC version into the GitHub release
notes and the CurseForge changelog, and fails if that section is missing.

## 1.3.1

### Fixes

- On Classic Era and Anniversary clients in a language other than English, the setup panel no longer offers Class Skills and Languages. WSK now finds those groups from your own client: the languages you speak, your spellbook's tab names, and the game's own text for "Languages" and "Professions". English clients work as before.
- On those clients, collapsing the weapon skills group no longer stops tracking its skills: they keep their last values and stay in the weapons view.

## 1.3.0

### Features

- Your WSK settings are now part of your Dyre's Toolkit profile: the tracked skills, the box's place, shown state and view, and both opacities. On the Toolkit's settings page you can copy them from another character, reset them to the defaults, or export and import them; they apply at once, with no reload. The box's lock stays per character, because it follows the Toolkit's lock. This needs Dyre's Toolkit 2.10.0 or newer; with an older Toolkit, or none, nothing changes.

## 1.2.0

### Features

- WSK now also reads skills on clients without Forever's skill API, such as WoW Classic Era and Anniversary: the same bars (rank, cap, bonus, and cap colors), the weapon and other skill views, and up to six of each. There, a skill is known by its name, and the weapon group by its English header name or by its Defense line in any language. This build is for testing on those clients; the CurseForge release is still for WoW: Forever.

### Other changes

- Without the Skills tab's +/- art, the group headers in the setup panel use the classic +/- buttons.

## 1.1.0

### Features

- `/wsk` now opens the settings page, as `/wsk options` does: under Dyre's AddOns when Dyre's Toolkit is installed, otherwise its own page. In combat it opens nothing and says that the settings open out of combat.
- New backup command `/weaponskills`, which works the same as `/wsk`, for when another AddOn also uses `/wsk`.
- `/wsk help` lists every command.
- If another AddOn also uses `/wsk` or `/weaponskills`, WSK says so once at login and names the command to use instead.

### Other changes

- `/wsk` no longer shows or hides the skill box. Use `/wsk show` and `/wsk hide` for that.

## 1.0.0

The first full release for WoW: Forever, no longer marked beta: it was play tested on the Forever beta client 1.60.1, build 70450. CurseForge now offers it as a release, so the app updates it and installs what it needs for every player.

- The CurseForge app installs Dyre's Toolkit with WSK.

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
