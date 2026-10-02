# Wacky-Races-Jaguar

[![AI-assisted: Claude Code](https://img.shields.io/badge/AI--assisted-Claude%20Code-D97757?logo=claude&logoColor=white)](https://claude.com/claude-code)
[![License: Unlicense](https://img.shields.io/badge/license-Unlicense-blue.svg)](LICENSE)
[![Platform: Atari Jaguar](https://img.shields.io/badge/platform-Atari%20Jaguar-red.svg)](#)

**English** · [Français](#français)

A port of the Game Boy Color game **Wacky Races** (Infogrames, 2000) to the **Atari Jaguar**,
made with **[Claude Code](https://claude.com/claude-code)**, Anthropic's AI coding assistant.
The code in this repository (recompiler, hardware abstraction layer, GPU renderer, DSP sound
engine, test tools) was written by Claude Code, directed and play-tested by a human.

The whole game runs from the original Game Boy Color ROM.

### How it works

- **Static recompiler** (`recomp68.py`): translates the game's SM83 (Game Boy CPU) code to
  Motorola 68000 assembly ahead of time. Game Boy registers live in 68000 registers, and the
  Game Boy flags are tracked so that they are only saved when they are actually used.
- **Hardware abstraction layer** (`hal/hal.s`, `hal/hle.s`): emulates the Game Boy hardware the
  game relies on (memory banking, LCD timing, interrupts, DMA, joypad). The hottest raster
  effects (sky gradients, the race HUD, the road) are rewritten natively in 68000 code.
- **GPU renderer** (`hal/gpu.s`): the 68000 logs every video change, and the Jaguar's GPU (Tom)
  replays that log and draws the Game Boy Color picture line by line, straight into the
  framebuffer. Tom also does the preparation work: tile data converted (and mirrored) when it
  changes, tilemaps decoded, palettes turned into pixel-pair tables, tile data streamed from the
  ROM. Three framebuffers: Tom never draws into the one on screen. The Object Processor then
  shows the picture over the whole height of the screen, in high resolution.
- **Sound** (`hal/dsp.s`): the Game Boy sound chip is emulated on the Jaguar's DSP (Jerry),
  twice: the game's sound engine runs once for the music and once for the sound effects, each
  with its own four channels, mixed together. A sound effect no longer cuts a music channel.

### Status

The game boots and all the screens tested so far work: logos, intro, menus, racer and
challenge selection, races with items, results, the Arcade, Endurance, Championship and Time
Trial modes. The game runs at full speed and full frame rate (60 frames per second on an NTSC
machine) on all the screens measured: intro, menus, racer and challenge selection, races.
Testing is mostly done in MAME (headless, scripted, with picture-by-picture regression checks)
and in BigPEmu. On a PAL machine the game runs at 50 frames per second (one Game Boy frame per
VBlank: the game itself runs about 17% slower than on the Game Boy).

### Controls and display

Jaguar **B** or **C** = Game Boy A, **A** = Game Boy B, **Option** = Select, **Pause** = Start.

The picture fills the whole height of the screen, in the Jaguar's high-resolution mode
(pixels two clocks wide: about 704 pixels per line in NTSC, 690 in PAL; NTSC ×1.63 = 234
lines, PAL ×1.94 = 279 lines, all 144 lines of the Game Boy picture visible). Keypad **\***
switches between the original 10:9 picture and a picture stretched to the full width. Keypad
**#** switches between the whole height (overscan) and the safe area of a CRT TV.

### Building

Requirements:
- Python 3 (no extra package needed for the build),
- JagStudio, for `rmac`, `rln`, `include/JAGUAR.INC` and `include/Univ.bin`: set `JAGSTUDIO` to
  its `buildfiles` directory (default `D:\source_codes\jagstudio\buildfiles`),
- the original ROM, *Wacky Races (Europe) (En,Fr,De,Es,It,Nl).gbc* (SHA-1
  `dba18064c886cebe4c4be80f941622f377adab98`), in this directory or its parent (or `WACKY_GBROM`).

```
python build.py            # analyse + recompile the game, build build/wacky.j64
python build.py --norecomp # rebuild only the Jaguar side (HAL, GPU, DSP)
python build.py --analyze  # analyse the GB ROM again (analysis/gbre.py)
python build.py --hud      # debug build: game fps and drawn fps on screen
python build.py --sync     # test build for test/sync.ps1 (every frame drawn, deterministic)
```

The ROM is copied to `../output` (or `WACKY_OUTPUT`) as `Wacky Races (Jaguar).j64`
(`--hud`: `Wacky Races (Jaguar) [debug HUD].j64`; the test builds stay in `build/`). `analysis/` holds the tools that
disassemble the GB ROM (`gbre.py`, seeded with the merged execution traces of
`analysis/coverage` and the table entries of `extra_entries.txt`: addresses only, no game data).
The automated tests in `test/` also need MAME (`../tools/mame`) and PyBoy.

### Legal

**No ROM is included.** You need your own copy of *Wacky Races (Europe) (En,Fr,De,Es,It,Nl)*
for the Game Boy Color. Wacky Races and the original game belong to their respective owners.
This project is not affiliated with them. The code in this repository is public domain (see
[LICENSE](LICENSE)).

---

## Français

**[English](#wacky-races-jaguar)** · Français

Un portage du jeu Game Boy Color **Wacky Races** (Infogrames, 2000) sur **Atari Jaguar**,
réalisé avec **[Claude Code](https://claude.com/claude-code)**, l'assistant de programmation
IA d'Anthropic. Le code de ce dépôt (recompilateur, couche d'abstraction matérielle, moteur de
rendu GPU, moteur sonore DSP, outils de test) a été écrit par Claude Code, dirigé et testé
manette en main par un humain.

Le jeu complet tourne à partir de la ROM Game Boy Color d'origine.

### Fonctionnement

- **Recompilateur statique** (`recomp68.py`) : traduit à l'avance le code SM83 (le processeur
  de la Game Boy) du jeu en assembleur Motorola 68000. Les registres de la Game Boy sont dans
  des registres du 68000, et les indicateurs (flags) de la Game Boy ne sont sauvegardés que
  lorsqu'ils servent vraiment.
- **Couche d'abstraction matérielle** (`hal/hal.s`, `hal/hle.s`) : émule le matériel Game Boy
  dont le jeu a besoin (banques mémoire, timing de l'écran, interruptions, DMA, manette). Les
  effets d'affichage les plus coûteux (dégradés du ciel, HUD de course, route) sont réécrits
  directement en 68000.
- **Rendu GPU** (`hal/gpu.s`) : le 68000 enregistre chaque changement vidéo, et le GPU de la
  Jaguar (Tom) rejoue ce journal pour dessiner l'image Game Boy Color ligne par ligne,
  directement dans l'écran. Tom fait aussi le travail de préparation : conversion (et version
  miroir) des tuiles quand elles changent, décodage des tilemaps, palettes transformées en
  tables de paires de pixels, tuiles lues directement dans la ROM. Trois images en mémoire :
  Tom ne dessine jamais dans celle qui est à l'écran. L'Object Processor affiche ensuite
  l'image sur toute la hauteur de l'écran, en haute résolution.
- **Son** (`hal/dsp.s`) : la puce sonore de la Game Boy est émulée sur le DSP de la Jaguar
  (Jerry), en double : le moteur sonore du jeu tourne une fois pour la musique et une fois pour
  les effets, chacun avec ses quatre voies, mixées ensemble. Un effet sonore ne coupe plus une
  voie de la musique.

### État

Le jeu démarre et tous les écrans testés jusqu'ici fonctionnent : logos, intro, menus, choix
du pilote et du défi, courses avec objets, résultats, modes Arcade, Endurance, Championnat et
Contre-la-montre. Le jeu tourne à pleine vitesse et à pleine cadence (60 images par seconde
sur une machine NTSC) sur tous les écrans mesurés : intro, menus, choix du pilote et du défi,
courses. Les tests se font surtout sous MAME (sans affichage, par scripts, avec comparaison
des images une à une) et sous BigPEmu. Sur une machine PAL, le jeu tourne à 50 images par
seconde (une image Game Boy par VBlank : le jeu lui-même va environ 17 % moins vite que sur la
Game Boy).

### Commandes et affichage

Jaguar **B** ou **C** = A de la Game Boy, **A** = B, **Option** = Select, **Pause** = Start.

L'image occupe toute la hauteur de l'écran, dans le mode haute résolution de la Jaguar
(pixels de deux cycles : environ 704 pixels par ligne en NTSC, 690 en PAL ; NTSC ×1,63 =
234 lignes, PAL ×1,94 = 279 lignes, les 144 lignes de l'image Game Boy restent visibles). La
touche **\*** du pavé numérique bascule entre l'image d'origine en 10:9 et une image étirée
sur toute la largeur. La touche **#** bascule entre toute la hauteur (overscan) et la zone
sûre d'un téléviseur cathodique.

### Compilation

Prérequis :
- Python 3 (aucun module supplémentaire pour la compilation),
- JagStudio, pour `rmac`, `rln`, `include/JAGUAR.INC` et `include/Univ.bin` : la variable
  `JAGSTUDIO` donne son dossier `buildfiles` (par défaut `D:\source_codes\jagstudio\buildfiles`),
- la ROM d'origine, *Wacky Races (Europe) (En,Fr,De,Es,It,Nl).gbc* (SHA-1
  `dba18064c886cebe4c4be80f941622f377adab98`), dans ce dossier ou le dossier parent (ou
  `WACKY_GBROM`).

```
python build.py            # analyse + recompile le jeu et produit build/wacky.j64
python build.py --norecomp # ne reconstruit que la partie Jaguar (HAL, GPU, DSP)
python build.py --analyze  # refait l'analyse de la ROM Game Boy (analysis/gbre.py)
python build.py --hud      # version de débogage : images/s du jeu et images affichées à l'écran
python build.py --sync     # version de test pour test/sync.ps1 (tout dessiné, déterministe)
```

La ROM est copiée dans `../output` (ou `WACKY_OUTPUT`) sous le nom `Wacky Races (Jaguar).j64`
(`--hud` : `Wacky Races (Jaguar) [debug HUD].j64` ; les versions de test restent dans `build/`). `analysis/` contient les outils qui
désassemblent la ROM Game Boy (`gbre.py`, guidé par les traces d'exécution fusionnées de
`analysis/coverage` et les entrées de tables de `extra_entries.txt` : uniquement des adresses,
aucune donnée du jeu). Les tests automatiques de `test/` demandent en plus MAME
(`../tools/mame`) et PyBoy.

### Mentions légales

**Aucune ROM n'est fournie.** Il faut votre propre copie de *Wacky Races (Europe)
(En,Fr,De,Es,It,Nl)* pour Game Boy Color. Wacky Races et le jeu d'origine appartiennent à
leurs détenteurs respectifs. Ce projet n'a aucun lien avec eux. Le code de ce dépôt est dans
le domaine public (voir [LICENSE](LICENSE)).
