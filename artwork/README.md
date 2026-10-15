# Weapon Skills Forever logo

Original vector artwork: a gold sword standing before an open book, inside a
gold progress ring, on a rich dark-brown background. It shares its frame,
colors, and sword with the Weapon Sets Forever logo. The design has no font or
external-image dependencies.

- `weapon-skills-forever-logo.svg`: editable, resolution-independent source.
- `weapon-skills-forever-logo.png`: 1024 x 1024 PNG master.
- `weapon-skills-forever-logo-512.png`: 512 x 512 PNG for square project images.

The PNGs are rendered from the SVG with headless Chrome, for example:

```sh
chrome --headless=new --hide-scrollbars --window-size=1024,1024 --force-device-scale-factor=0.5 --screenshot=weapon-skills-forever-logo-512.png weapon-skills-forever-logo.svg
```

Use these files for project pages and distribution branding. Keep this directory
out of the runtime release ZIP; the TOC and box use built-in client icons.

This artwork is covered by the repository's MIT License. Copyright (c) 2026
John Bedworth. Include the applicable license notice with distributed copies.
