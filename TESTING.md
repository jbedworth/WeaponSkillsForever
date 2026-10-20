# Verification and test plan

This document describes how Weapon Skills Forever is verified: the runtime
contract under test, the pinned client-source evidence behind design decisions,
the automated test method, and the in-client checklist.

## Verification approach

1. **Pinned source review.** Client behavior is read from Blizzard's FrameXML
   and generated API documentation at Gethe/wow-ui-source commit
   `943764493e6b16d63ded3ab304150d1f05e58b57` (`1.60.1.70338`; the client
   was tested on build 70450). Source establishes declared APIs, templates, and code paths, not operational behavior.
2. **Automated mock tests.** `tests/run.lua` exercises commands, skill rules,
   saved settings, tracking limits, and the box and setup panel against minimal
   WoW API mocks under Lua 5.1. Python unit tests cover the release helpers.
   Mocks cannot establish layout, textures, or taint.
3. **In-client checks.** The checklist below covers everything mocks cannot.
   Client observations that contradict a mock assumption take precedence; fix
   the mock and add a regression test that encodes the observed behavior.

## Runtime contract

- `Skills.lua` requires `C_SkillInfo.GetNumSkillLines`, `GetSkillLineInfo`, and
  `GetSkillLineInfoByID`. It does not check the client version or build.
- Trackable skills are learned, non-header, top-level lines
  (`parentSkillLineID == 0`) with `maxRank > 1`, outside category 7 (Class
  Skills) and category 10 (Languages, which stay at their cap once known; the
  ID comes from Classic skill data and is confirmed in client through
  `/wsk debug_skills`, which prints each line's `category=`). In client, every profession and secondary skill also appeared as a
  child line with the same name and rank, which duplicated the setup list until
  this filter, the same one Blizzard's Skills panel uses, was added. Defense
  takes its bonus from `UnitDefenseSkill`.
- Status compares the base rank with `maxRank`: `capped` at or above the cap,
  `near` within `NEAR_CAP_RANKS` (5), otherwise `low`. Bonuses never count.
- Secret values: every skill line passes through `ReadSkillLine`, which
  replaces each secret field with the last plain value seen this session
  (by skill ID), or marks the line unknown. `GetNumSkillLines` counts as 0
  while secret, and Defense's `UnitDefenseSkill` bonus keeps its last plain
  value. Unknown lines are never trackable and never pruned; the box keeps
  its rows, and a view whose tracked skills were never seen plain says the
  game hides the values. `/wsk debug_skills` prints `<secret>`.
- `Core.lua` repairs `WeaponSkillsForeverDB` on load: tracked IDs are whole,
  positive, unique, and at most twice `MAX_TRACKED`, because skill types are
  unknown before skill data arrives; `SetTracked` enforces `MAX_TRACKED` (6)
  per type. The saved `view` is `weapons` or `other`. It prunes tracked skills the
  character no longer has on `SKILL_LINES_CHANGED`, but never while the client
  reports zero skill lines.
- At `PLAYER_LOGIN`, core checks that every runtime file is from the same
  version and the skill API exists, prints one banner, then builds the UI by
  calling `WSK.InitializeUI` directly, so startup never depends on event
  handler order.
- `UI.lua` registers a canvas category with Blizzard's Settings API when it
  exists: show and lock checkboxes, reset position, the shared skill selector,
  and disabled Layout and Theme placeholders that store nothing. Without the
  API, WSK runs without the page and `/wsk options` says so.
- With Dyre's Toolkit (`DyresToolkit.RequireContract(1)` at `PLAYER_LOGIN`),
  the box starts with the toolkit's lock, registers with `RegisterMovable`,
  and drags only through `BeginDrag`/`EndDrag`; `/wsk lock`, `/wsk unlock`,
  call the toolkit, which locks every Dyre's AddOn; the settings page and gear
  panel have no lock checkbox (the toolkit's switch replaces it), and the
  reset button and pager move up into its place;
  the settings page is a canvas subcategory of the toolkit's "Dyre's AddOns"
  category. Without the toolkit, or with one lacking contract 1, WSK keeps its
  own drag, lock, and top-level page and prints one install line naming
  CurseForge. The mock suite covers both paths with a mock toolkit.
- Each bar uses a plain color texture created in code; the box uses the
  built-in tooltip background and rounded border, tinted brown at the saved
  background opacity (default 50%)
  and gold.

## Pinned source evidence

- `Blizzard_APIDocumentationGenerated/SkillInfoDocumentation.lua` documents
  `C_SkillInfo` and `SkillLineAttributes`: `skillID`, `name`, `isHeader`,
  `isCollapsed`, `rank`, `tempPoints`, `modifier`, `maxRank`,
  `skillLineCategoryID`, `parentSkillLineID`, and others, plus the synchronous
  `SKILL_LINES_CHANGED` event.
- `Blizzard_UIPanels_Game/Camelot/SkillsFrame.lua` lists skills by index,
  hides category 7, reads Defense's bonus from `UnitDefenseSkill`, and draws
  each bar from 0 to `maxRank` filled to `rank`, with the bonus as green text.
  It declares `SKILL_RANKS_PER_SKILL_LEVEL = 5`, the weapon cap per level.
- `Blizzard_SharedXML/Backdrop.xml` defines `BackdropTemplate`;
  `Backdrop.lua` references `Interface\Tooltips\UI-Tooltip-Background` and
  `Interface\Tooltips\UI-Tooltip-Border`.
- `Blizzard_SharedXML/Shared/Button/CheckButtonTemplates.xml` defines
  `UICheckButtonTemplate`.
- `Blizzard_Settings_Shared/Blizzard_Settings.lua` defines
  `Settings.RegisterCanvasLayoutCategory`, `RegisterCanvasLayoutSubcategory`
  (parent category, frame, name), `RegisterAddOnCategory`, and
  `OpenToCategory`; `Blizzard_ImplementationReadme.lua` documents canvas
  categories and the optional `OnRefresh` frame method.
- `Blizzard_SharedXML/Shared/Slider/MinimalSlider.xml` defines
  `MinimalSliderTemplate`, a horizontal `Slider` with Blizzard's slider art;
  its `OnLoad` applies `obeyStepOnDrag`.
- `Blizzard_Fonts_Shared` defines the fonts used: `GameFontNormal`,
  `GameFontNormalLeft`, `GameFontNormalLarge`, `GameFontHighlight`,
  `GameFontHighlightSmall`, `GameFontHighlightHuge`, and `GameFontDisableSmall`.

### Client observations

- `SKILL_LINES_CHANGED` arrives on skill-ups and on level-ups: tracked bars
  update while playing, and a level-up raises their caps, without opening the
  Character window.
- `INV_Misc_Gear_01` renders on the target client, so the gear button and TOC
  icon need no runtime asset.
- Six tracked rows fit comfortably in the box.
- `INV_Sword_04` and `INV_Misc_Book_09` render as the view toggle, which
  switches the box between weapon and other skills in Skills tab order.
- The setup panel's +/- group headers expand and collapse groups, and the
  Settings page (canvas category, gold-bordered skill list, and
  `MinimalSliderTemplate` opacity sliders) works in client.
- `/wsk debug_skills` on a hunter with Weapon Skills collapsed showed:
  - a collapsed header hides its skills from `GetSkillLineInfo` indexes, but
    `GetSkillLineInfoByID` still finds them, so tracked skills stay in the box;
  - each header's `skillID` equals its skills' `skillLineCategoryID` (Class
    Skills 7, Weapon Skills 6, Armor Proficiencies 8, Secondary Skills 9,
    Languages 10, Professions 11);
  - every profession and secondary skill also has a child line, sometimes
    listed before its parent.

### Open client questions

1. Whether expanding or collapsing groups from WSK leaves any taint that
   affects Blizzard's own UI later in the session (check the taint log).
2. How the bars and box look at different UI scales.

## Automated tests

From the Git Bash repository root:

```sh
.tools/luarocks-3.13.0-win32/win32/lua5.1/bin/lua5.1.exe tests/run.lua
.tools/luarocks-3.13.0-win32/win32/lua5.1/bin/luac5.1.exe -p Commands.lua Skills.lua Core.lua UI.lua tests/run.lua
.tools/python-3.13.7/python.exe -m unittest discover -s tests -p 'test_*.py'
```

Mocks follow the client's quirks learned on Weapon Sets Forever: APIs that
return no value must return no value in mocks, not an explicit nil.

The mock's secret values (`state.secret`, `secretCount`, `secretDefense`)
report their real type through `type()`, as in client, and raise an error on
any compare, arithmetic, concatenation, length, index, or `tostring`. A
boolean test on a secret cannot be made to fail in Lua 5.1, so mocks do not
prove that rule; code checks `IsSecret` before every use instead. Run against
0.1.0-beta, the secret-modifier test fails at `BarText`, as John's
BugGrabber report from the client did.

## In-client checklist

- [ ] Login prints `WSK: Weapon Skills Forever <version> by Dyre` and the ready hint.
- [ ] The box appears with the gold rounded border, half-transparent brown
      background, title, and gear icon; with nothing tracked it shows the hint.
- [ ] The setup panel lists skills grouped as on the Skills tab, with no Class
      Skills, Languages, or single-rank lines, and each skill once.
- [ ] Group headers look like the Skills tab's, with + on collapsed groups and
      − on expanded ones. A collapsed group hides all its skills, tracked or
      not, while the box keeps showing tracked ones.
      Clicking + or − expands or collapses it on the Skills tab too, with no
      Lua error.
- [ ] The sword and book view icons render and toggle the box between weapon
      and other skills, in Skills tab order; the view survives `/reload`.
- [ ] Track six weapon skills; the remaining weapon checkboxes are disabled while
      other skills stay available, and the reverse. Untrack one; the others
      re-enable.
- [ ] Bars: red more than 5 below the cap, yellow within 5, green at the cap;
      the text shows `rank / cap`, with a bonus in green.
- [ ] A skill-up updates its bar without opening the Character window.
- [ ] Drag the box, `/reload`, and confirm the position; lock it and confirm it
      no longer drags; `/wsk reset` restores the default position.
- [ ] Tracked skills and position are kept after relogging, and are separate on
      a second character.
- [ ] Escape and the X button close the setup panel; `/wsk` hides and shows the box.
- [ ] The opacity sliders change the box background and skill rows at once,
      show the value, survive `/reload`, and reset with the panel's Defaults
      button without touching tracked skills.
- [ ] Options > AddOns lists Weapon Skills Forever; `/wsk options` opens it. Its
      show and lock checkboxes, reset button, and skill selector work and stay in
      step with the box and gear panel; Layout and Theme show disabled.
- [ ] No Lua errors or taint warnings in or out of combat.

- [ ] Track Swords (or a skill with a racial bonus) and Defense, and fight:
      BugGrabber shows no `UI.lua` "secret number value" error, and the bars
      keep their values and bonus during and after combat. Skill-ups in combat
      show after combat at the latest.
- [ ] `/wsk debug_skills` in combat prints no Lua error (secret fields print
      as `<secret>`).

### With Dyre's Toolkit

- [ ] Login prints the banner and ready hint, and no install line. The AddOn
      list shows Weapon Skills Forever under Dyre's Toolkit.
- [ ] Options > AddOns > Dyre's AddOns lists Weapon Skills Forever, with no
      second top-level entry; `/wsk options` opens it, and in combat says
      that the settings open out of combat.
- [ ] At login the box is locked and does not drag. `/dyre unlock` unlocks it
      with the frames of every other Dyre's AddOn.
- [ ] Drop the box near another Dyre's frame: it snaps beside it, 20 apart.
      Shift-drag moves the snapped group.
- [ ] With "Snap to the grid" on, a box dropped away from other frames puts
      its center on the nearest grid point; with it off, it stays where
      dropped. The position survives `/reload`.
- [ ] `/wsk lock` and `/wsk unlock` lock and unlock every Dyre's AddOn, with
      one `Dyre:` line and no `WSK:` line.
- [ ] WSK's settings page and the gear panel (`/wsk config`) show no lock
      checkbox; "Reset position" sits right under "Show the skill box", and
      the gear panel has no empty row above its pager.
- [ ] `/wsk reset` still moves the box to its default position.

### Without Dyre's Toolkit

- [ ] With the toolkit disabled, login adds one line naming CurseForge as the
      place to install Dyre's Toolkit; the box drags with `/wsk unlock`, the
      settings page is top-level under Options > AddOns, and it and the gear
      panel show the "Lock the skill box position" checkbox.
