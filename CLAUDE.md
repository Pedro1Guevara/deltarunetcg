# Deltarune TCG — Working Context

Single-player fangame of the Deltarune fan TCG by Sylkwyrm, a card game built on the Pokémon TCG ruleset. Godot 4.7.2, GDScript with static typing. The player fights CPU opponents with prebuilt decks, one combat at a time, best of three rounds. No overworld.

This file is the working context for Claude Code. The specification lives in two documents; read them before changing rules, card data or architecture:

- `ProjectObjectives_DeltaruneTCG_v1` — what is being built and why.
- `DesignDocument_DeltaruneTCG_v1` — rules, card schema, example cards, architecture, current build vs design, frozen systems, open items.

If a rule is not in the Design Document, it has not been decided. Ask; do not assume a value.

## Status

The repository was a Pokémon TCG roguelite (WOTC cards). In October 2026 it pivoted to Deltarune TCG, reusing the build. Section 10 of the Design Document lists every difference between the current code and the new rules. The roguelite structure and Spare/Fight are **frozen**: do not implement them.

The first Deltarune prototype is defined after the documents are approved. Do not plan stages beyond the current one.

## Language

Conversation in Spanish. Code, identifiers, comments and documents in English. Responses that are code: only the code unless an explanation is asked for. Avoid heavy use of bullet points in explanations.

## Methodology

- Prototype-driven: each prototype answers one specific design question and is played before the next is planned.
- No infrastructure ahead of a question that needs it.
- Work step by step; confirm each stage before moving on.
- Rule divergences are fixed in code, not only documented.

## Repository layout

Layers are top-level folders (Design Document 8.2). Dependencies point one way: `core/` references nothing; `ai/`, `meta/` and `net/` reference only `core/` and never each other; `game/` may reference all of them. Create a layer folder only when its first file is written.

- `addons/card-framework/`, `example1/`, `freecell/`, `docs/`, `scripts/` — the card-framework fork (chun92/card-framework). **Never modify anything that ships with the fork.** Extend it by subclassing.
- `core/` — rules engine. Pure GDScript, every class extends RefCounted. No scene tree, input, threads or file I/O. `cards/` (card model; `parsers/` turns JSON into CardData), `match/` (MatchEngine and round state), `rules/` (pure checks and calculations), `effects/`, `rng.gd`.
- `ai/` — CPU opponents. `meta/` — story progression (and the frozen roguelite). `net/` — multiplayer, out of scope. None exist yet.
- `game/` — the Godot app. `app/`, `services/` (DataLoader, SaveService), `presentation/` (CardText: words the player reads), `ui/` (reusable widgets such as CardChip), `screens/` (`debug/hotseat/` today).
- `data/` — `cards/cards.json`, `decks/decks.json`, `effects/` (`functions.json`, `card_effects.json`), `legacy/` (WOTC regression fixture).
- `assets/` — images, sounds, fonts and the Godot resources built only from them (Theme, TileSet, SpriteFrames); never scripts or scenes. Card art is `assets/cards/fronts/<card_id>.png`. Board graphics in `board/`, menus and HUD in `ui/`, type icons in `icons/types/`. `legacy/tcgdex/` holds downloaded WOTC art, not committed.
- `tests/` — headless checks extending `tests/support/test_case.gd`: `godot --headless --path . --script res://tests/core/<file>.gd` (legacy suite in `tests/legacy/`).
- `tools/` — scripts run by hand; `legacy/` for the WOTC importer and effect report.
- Move files from the Godot editor's FileSystem dock so `.tscn` paths and `.uid` files follow.

## Engine contracts

- `MatchEngine` is the only object that mutates game state. Ownership flows MatchEngine → PlayerState → CardInPlay → CardData.
- Every decision goes through `legal_actions()` / `apply()`. The engine does not know who answers. Choices can be answered by the player who is not taking the turn (Bump, Hazy Memory), so the seam must say which player answers.
- `Rng` is the only source of shuffles and coin flips.
- Legality never reads a printed cost. Spell TP costs, attack Energy costs and Flee costs are computed as effective costs through one continuous-effects layer, which also filters `legal_actions()`.
- TP is an integer number of quarters, 0 to 4.
- The number of Mercy Cards taken per knockout and the round-start draw advantage are values effects can modify, never constants.

## Card effects

- Effects are compositions of atomic effects declared in JSON, never per-card code and never interpreted from card text.
- Functions are generic and named by mechanic, not by card or attack. Cards with the same mechanic share one function and differ only in arguments.
- One dictionary per card binds each attack, Ability, ACT card or Special Energy to a function and its arguments.
- No default values in effect data: every argument is declared explicitly. Neutral zeros exist only as a runtime safety net.
- Effect definitions do not store card text.
- Energy in effects: distinguish counting Energy cards from counting Energy units.

## Card data

- Cards are written in the Deltarune schema (Design Document 6.2) in `data/cards/cards.json`. TCGdex is no longer a source.
- A dictionary-based translator (Design Document 6.3) converts each card into the engine's Pokémon vocabulary on load: darkner → Pokemon, act → Trainer with `trainer_type` (item → Item, lightner → Supporter, area → Stadium), flee_cost → retreat_cost, abilities → powers. New concepts are translated as far as they share mechanics and kept apart for the rest: a Spell is a Trainer with `trainer_type` Spell and a `tp_cost`; a Deltarune evolution is stage BREAK.
- Transcribe types by type, never by icon: a type can be printed with alternate icons (Order as a balance scale, Electric as a swirl, Fighting with a second axe design). Type names stay as they are (Holy, Chaos…); they have no Pokémon equivalent.
- Weakness and Resistance are stored per card as types only. The translator fills the modifiers (+20 / −20) from the game rule. The type chart is a design standard, not something the engine derives.
- Evolutions work like XY BREAK: they keep the previous card's attacks, Abilities, Weakness, Resistance and Flee cost; their HP replaces the previous HP.

## Naming

Internally the engine stays a Pokémon TCG engine. Do not rename existing classes, functions, variables or action types (`active`, `bench`, `prizes`, `retreat`, `is_basic_pokemon()` stay as they are). New concepts use the Pokémon equivalent when one exists (`supporter`, `stadium`) and their Deltarune name only when there is none (`spell`, `tp`).

Everything the player sees speaks Deltarune: labels, prompts, logs and UI text. Darkner, ACT card (Item, Lightner, Area, Spell), Battle Zone, Field (the bench only, four slots), Mercy Cards, Flee, damage counters (as in the Pokémon TCG), TP. Note the spelling **Lightner**.

Tests that match on label or prompt text must change in the same commit as the text they match.
