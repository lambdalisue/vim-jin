# Draw glyphs from a preset the user chooses and overrides

Status: Accepted

## Context

The statusline of a view packs several parts into a line, told apart only
by color and spacing. Icons tell them
apart at a glance, but the icons that read best come from a Nerd Font,
which only some users have installed; without one, they show as boxes.
Plain Unicode symbols depend less on the font, and some terminals and
fonts handle even those poorly. No single set of glyphs suits every user.

## Decision

Every glyph vim-jin draws has a name, and comes from a preset: one of Nerd
Font icons, one of plain Unicode, one of ASCII alone. A variable chooses
the preset, and a dictionary variable sets any glyph by its name in place
of the preset's. Both are read when the glyphs are drawn.

## Alternatives considered

- Draw no glyphs. Every user gets the plainest look, those with a Nerd
  Font included.
- Detect whether the font has Nerd Font glyphs. Neither editor can tell
  which glyphs the terminal's font draws.
- Offer the presets alone. A user whose font lacks one glyph, or who
  dislikes one, has to give up the whole preset.
- Let the user replace the whole statusline format. It hands over the
  layout too, which the user then has to keep up with as views change.

## Consequences

- One preset is the default, and a user whose font does not suit it has to
  choose another.
- The width of a glyph is the font's and the editor's to say, so every
  layout that holds a glyph measures it by the editor's display width.
- A change to the variables shows on the next draw, with nothing to reload.
