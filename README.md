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
  replays that log and draws the Game Boy Color picture line by line. The Object Processor
  then shows it scaled ×1.5.
- **Sound** (`hal/dsp.s`): the Game Boy sound chip is emulated on the Jaguar's DSP (Jerry).

### Status

The game boots and all the screens tested so far work: logos, intro, menus, racer and
challenge selection, races with items, results, the Arcade, Endurance, Championship and Time
Trial modes. Testing is mostly done in MAME (headless, scripted) and in BigPEmu.

### Building

Requirements: JagStudio (for `rmac` and `rln`),
Python 3.12, and optionally MAME and PyBoy for the automated tests.

```
python build.py            # recompile the game and build build/wacky.j64
python build.py --norecomp # rebuild only the Jaguar side (HAL, GPU, DSP)
python build.py --hud      # debug build: game fps and drawn fps on screen
```

The build currently expects the disassembly and execution traces (`../analysis`) and the
original ROM in the parent directory. Those are not part of this repository yet.

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
  Jaguar (Tom) rejoue ce journal pour dessiner l'image Game Boy Color ligne par ligne. L'Object
  Processor l'affiche ensuite agrandie ×1,5.
- **Son** (`hal/dsp.s`) : la puce sonore de la Game Boy est émulée sur le DSP de la Jaguar
  (Jerry).

### État

Le jeu démarre et tous les écrans testés jusqu'ici fonctionnent : logos, intro, menus, choix
du pilote et du défi, courses avec objets, résultats, modes Arcade, Endurance, Championnat et
Contre-la-montre. Les tests se font surtout sous MAME (sans affichage, par scripts) et sous
BigPEmu.

### Compilation

Prérequis : JagStudio (pour `rmac` et
`rln`), Python 3.12, et en option MAME et PyBoy pour les tests automatiques.

```
python build.py            # recompile le jeu et produit build/wacky.j64
python build.py --norecomp # ne reconstruit que la partie Jaguar (HAL, GPU, DSP)
python build.py --hud      # version de débogage : images/s du jeu et images affichées à l'écran
```

La compilation attend pour l'instant le désassemblage et les traces d'exécution
(`../analysis`) ainsi que la ROM d'origine dans le dossier parent. Ils ne font pas encore
partie de ce dépôt.

### Mentions légales

**Aucune ROM n'est fournie.** Il faut votre propre copie de *Wacky Races (Europe)
(En,Fr,De,Es,It,Nl)* pour Game Boy Color. Wacky Races et le jeu d'origine appartiennent à
leurs détenteurs respectifs. Ce projet n'a aucun lien avec eux. Le code de ce dépôt est dans
le domaine public (voir [LICENSE](LICENSE)).
