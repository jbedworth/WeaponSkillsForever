# Agent Guidelines

## Project purpose and scope

Weapon Skills Forever (WSK) is a small World of Warcraft: Forever AddOn. It
shows learned skills chosen by the user, up to `MAX_TRACKED` (6) of each type
(weapon skills, and other skills such as professions), as bars in a
movable on-screen box, so the user can see when a skill is capped. Skills are
normally visible only on the Skills tab of the Character window.

- The box: rounded gold border, brown background (default 50% opacity), the title
  `Weapon Skills Forever`, a gear button that opens the setup panel, and one row
  per tracked skill: the name, then a bar from 0 to the skill's `maxRank`,
  filled to its base `rank`, with the value centered on the bar.
- Opacity is configurable per character (author-approved) on the settings page
  with `MinimalSliderTemplate` sliders in steps of 5%: `backgroundAlpha` (box
  background, default 0.5, range 0-1) and `contentAlpha` (skill names, bars,
  and the empty hint, default 0.9, range 0.2-1 so rows never vanish). The title
  and header icons stay at full opacity. Saved values are rounded and clamped
  on load. The Settings panel's Defaults button resets opacities only.
- Bar color, author-approved: red when the rank is more than 5 below the cap,
  yellow within 5 but not capped, green at the cap. Compare the base rank with
  `maxRank`; bonuses (`modifier`) are shown in green text but never count,
  matching Blizzard's Skills tab.
- The setup panel lists learned skills with checkboxes, grouped by their Skills
  tab headers, and allows 0 to `MAX_TRACKED` selections. Ranked skills only:
  hide headers, Class Skills (category 7), Languages (category 10, always at
  their cap once known; author-approved), lines with `maxRank <= 1`, and child
  lines (`parentSkillLineID ~= 0`), which the client reports with the same name
  and rank as their parent.
- Keep `MAX_TRACKED` a single constant (6), applied to each type separately;
  the author may change it later.
- Skill type (author-approved): weapons are skills in the Weapon Skills
  category (6), which includes Defense and Unarmed; everything else trackable
  is "other". An icon toggle left of the gear (`INV_Sword_04` for weapons,
  `INV_Misc_Book_09` for other skills, both 20 px like the gear, 10 px apart) switches which
  type the box shows; the
  view is saved per character. The box lists each view in Skills tab order; a
  skill under a collapsed header takes its header's place and keeps its
  position in the group, remembered for the session from the last time the
  group was expanded; only a group never seen expanded falls back to name order.
  The setup panel always lists every group and shows both counts.
- An AddOn settings page (author-approved) is registered as a canvas category
  with Blizzard's Settings API (`Settings.RegisterCanvasLayoutCategory`,
  `RegisterAddOnCategory`, `OpenToCategory`; `/wsk options`): show and lock
  checkboxes, reset position, the same skill selector as the gear panel inside
  a thin rounded gold border (tooltip edge, edgeSize 8, about 2 px), and
  Layout (vertical/horizontal) and Theme sections shown disabled as placeholders.
  Do not persist layout or theme values until those features are agreed and
  built. If the Settings API is missing, WSK still works without the page.
- The box is draggable, with a lock; its position, the tracked skill IDs, and
  shown/locked state are saved per character in `WeaponSkillsForeverDB`
  (`SavedVariablesPerCharacter`).

### With Dyre's Toolkit (built; author-approved, 2026-10-19)

Dyre's Toolkit (`DyresToolkit`, its own repository, owned by the coordinating
session; do not edit it here) gives Dyre's AddOns one layout mode, snapping
across AddOns and to the grid, a minimap menu, and one settings home.

- TOC: `## OptionalDeps: DyresToolkit` (never `## Dependencies`, so WSK loads
  without it) and `## Group: DyresToolkit`. CurseForge uploads list
  `dyres-toolkit` as a required dependency, so the app installs it.
- At `PLAYER_LOGIN`, Core takes `DyresToolkit.RequireContract(1)` as
  `WSK.toolkit`, sets `db.locked` from `IsLocked()` (the toolkit starts
  locked), builds the UI, then calls `RegisterAddOn` (addon, title,
  `setLocked = WSK.ApplyLocked`, `openSettings = WSK.OpenSettings`).
- The box registers with `RegisterMovable` (the save function stores the
  toolkit's `{point = "CENTER", relativePoint = "BOTTOMLEFT", x, y}` in
  `db.position`) and drags only through `BeginDrag`/`EndDrag`: the toolkit
  checks the lock and combat, snaps, and saves.
- `/wsk lock` and `/wsk unlock` go through the toolkit, which locks every
  Dyre's AddOn and says one `Dyre:` line; `ApplyLocked` is quiet. The
  settings page and gear panel have no lock checkbox (author: redundant with
  the toolkit's "Unlock frames" switch); "Reset position" and the gear
  panel's pager move up into its place. Without the toolkit, both lock
  checkboxes stay: they are the only lock there.
- The settings page is `Settings.RegisterCanvasLayoutSubcategory` under the
  toolkit's `SettingsCategory()`, opened with `toolkit.OpenSettings` (never in
  combat).
- Otherwise (no toolkit or a contract it lacks): WSK's own drag, lock, chat
  lines, and top-level page, as before, plus one login line naming CurseForge
  as the place to install the toolkit.

Keep this narrow feature set. Do not add automatic weapon switching, skill-up
alerts, account-wide profiles, or other features without agreement.

## Project structure

- Runtime files: WeaponSkillsForever.toc, Commands.lua, Skills.lua, Core.lua,
  UI.lua, loaded in that order. Commands parses `/wsk`; Skills owns the skill
  API boundary, trackable-skill rules, and cap status; Core owns events, saved
  settings, tracking limits, the login banner, diagnostics, and joining Dyre's
  Toolkit; UI owns the box, setup panel, and settings page.
- tests/run.lua holds the Lua 5.1 mock suite. tests/test_*.py cover the release
  helpers in scripts/. .github/workflows/ holds CI, opt-in publishing, and the
  approval gate check.
- README.md is the user-facing overview, TESTING.md the verification method and
  in-client checklist, docs/RELEASE_PLAN.md the release process,
  docs/CURSEFORGE_LISTING.md the CurseForge form text, and CHANGELOG.md the
  per-release change list. artwork/ holds the logo (SVG source and PNGs) for
  project pages; it is never packaged.
- Documentation describes purpose, design, rules, and methodology. Do not add
  dated status reports or test-result logs to the docs; CHANGELOG.md is the
  release record.
- The project uses the MIT License. The public author name is `Dyre` (TOC
  `## Author`, login banner, listings); LICENSE keeps the legal name, John
  Bedworth, and the release builder requires that exact notice.
- The TOC has `## Group: DyresToolkit`, so WSK nests under Dyre's Toolkit in
  the in-game AddOn list, as every Dyre's AddOn does. Its
  `## Category: Quests & Leveling` groups it only when the toolkit is missing;
  keep that identical to the CurseForge main category (author-selected),
  because the list groups by exact text. CurseForge additional categories:
  Professions, Warrior, Rogue, Hunter.
- WSK ships no texture files. Use built-in client textures and code-created
  color textures only; add no runtime assets without agreement.
- Git origin: git@github.com:jbedworth/WeaponSkillsForever.git. Inspect Git
  state before acting and preserve user work. Text is LF under .gitattributes.

## Client and API verification

- Target: Forever beta 1.60.1, build 70450, Interface 16001, Lua 5.1. Pin source
  review to Gethe/wow-ui-source commit
  `943764493e6b16d63ded3ab304150d1f05e58b57` (the 70338 source; the client
  was tested on 70450). Treat target-client documentation and FrameXML as
  authoritative; Retail and Classic examples are references only.
- Do not gate the runtime on client version, build, or Interface. Gate only on
  the required `C_SkillInfo` functions.
- Track skills by `skillID` (`GetSkillLineInfoByID`), never by list index, which
  shifts when headers collapse. In client, a header collapsed on the Skills tab
  hides its skills from `GetSkillLineInfo` indexes, while lookup by ID still
  works; a header's `skillID` equals its skills' `skillLineCategoryID`. As on
  the Skills tab (author-approved), a collapsed group shows only its header,
  even if some of its skills are tracked; tracked skills stay in the box.
  Group headers mirror the Skills tab (author-approved): the whole row is a
  button with the `common-button-list-collapseExpand` background and 30% ADD
  highlight, and a `common-button-list-plus`/`-minus` state icon on the right.
  Clicking expands or collapses that header, the same action as clicking it on
  the Skills tab. WSK never expands or collapses headers on its own.
- Defense (skill 95) reads its bonus from `UnitDefenseSkill("player")`.
- The target client has Midnight's secret values: a skill line's fields (seen
  in client: `modifier`, from `SKILL_LINES_CHANGED`) and `UnitDefenseSkill`
  can be secret, and `type()` still says "number". Never compare, do
  arithmetic on, concatenate, index by, or print a value that may be secret:
  read lines only through Skills' `ReadSkillLine`/`GetSkill` (a plain copy
  with each secret field replaced by its last known value for the session),
  check `WSK.IsSecret` first, and print with `WSK.Describe`. A secret value
  never makes a skill count as unlearned (`WSK.IsUnlearned`), so nothing is
  pruned; a tracked skill never seen plain stays tracked, and the box says
  the game hides its values.
- WoW APIs can return no values rather than nil; store results in locals before
  passing them to `tostring`, and make mocks return no values in those cases.
  The client may not show Lua error popups, so diagnostics report errors in chat.
- Prefer `/wsk debug_*` commands over long `/run` scripts, which exceed the
  chat input limit.

## Clean coding

- Lua 5.1 syntax and libraries only. Four-space indentation. Prefer local
  variables and functions; share state through the AddOn namespace. Expose
  globals only when WoW requires them (slash commands, saved variables, and the
  named tracker, gear-panel, and settings frames), prefixed `WeaponSkillsForever`
  or `WSK`. Only the gear panel is in `UISpecialFrames` (Escape closes it).
- Centralize meaningful constants; avoid unexplained magic numbers.
- Comment sparingly: non-obvious intent, API constraints, or tradeoffs.
- Event-driven work only: update on `SKILL_LINES_CHANGED`; no polling or idle
  `OnUpdate` handlers.

## Safety and error reporting

- Validate commands and inputs before changing settings. Treat bad commands,
  the tracking limit, and unlearned skills as expected failures with concise
  feedback prefixed `WSK:`.
- Never swallow errors with blanket `pcall` handlers or replace the error handler.
- On an unsupported client or a mixed install, disable the AddOn and report the
  reason once at login.
- Repair saved settings on load so a damaged or older table cannot break the
  UI. Prune tracked skills the character no longer has, but never while the
  client reports zero skill lines.
- UI startup is driven by core at `PLAYER_LOGIN` calling `WSK.InitializeUI`;
  never rely on event handler order between files.

## Testing and documentation

- Run `.tools/luarocks-3.13.0-win32/win32/lua5.1/bin/lua5.1.exe tests/run.lua`
  and the bundled `luac5.1.exe -p` for syntax. Run
  `.tools/python-3.13.7/python.exe -m unittest discover -s tests -p 'test_*.py'`
  and actionlint on workflow changes. Report actual results; never invent them.
- Add focused tests alongside behavior changes. Mocks cannot prove layout,
  textures, or taint; UI changes need in-client checks from TESTING.md.
- Keep README usage and compatibility claims aligned with the implementation.

## Releases and collaboration

- Read docs/RELEASE_PLAN.md before packaging or changing release automation.
- Do not create commits, tags, uploads, or releases unless asked.
- Every release needs a `## <version>` section in CHANGELOG.md with player-facing
  changes; the builder puts it at the top of release-notes.md (GitHub release
  notes and CurseForge changelog) and fails without it.
- Package only WeaponSkillsForever.toc, Commands.lua, Skills.lua, Core.lua,
  UI.lua, and LICENSE under the top-level `WeaponSkillsForever/` folder, named
  `WeaponSkillsForever-<version>-forever.zip`, with the builder's BigWigs-format
  `release.json` (flavor `forever`) attached for WowUp.
- Publishing requires repository variables `ENABLE_GITHUB_RELEASES='true'` and,
  for CurseForge, `ENABLE_CURSEFORGE_UPLOADS='true'`, plus
  `CURSEFORGE_PROJECT_ID`, `CURSEFORGE_GAME_VERSION_ID`, and the `release`
  environment secret `CF_API_TOKEN`. Both publish jobs use the author-created
  environment `release` with a required reviewer; the workflow's environment
  name must match it exactly. Verify the gate with `gate-check.yml` before
  enabling publishing. Store tokens only in GitHub secrets.
- Action pins are full commit SHAs; review any pin change against the GitHub API.
- Commit messages, when requested: imperative, capitalized subject, at most
  about 50 characters, no ending punctuation; short wrapped body when useful.
