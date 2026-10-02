"""Annotations for the SM83 -> 68000 recompilation (GB rom offsets, original ROM)."""

# coverage directories (relative to analysis/) whose traces (access masks, bank contexts,
# indirect targets) are used; all of them are merged
COVDIRS = ['coverage']        # (merged traces, see analysis/merge_coverage.py)

# GB functions replaced by HAL routines (called with jsr, return with rts)
HLE_FUNC = {
    0x3E9F: 'hal_wait_ly91',      # wait LY == $91
    0x3E58: 'hal_wait_hbl',       # wait STAT mode != 0 then mode 0 (menus)
    0x32AE: 'hle_road',           # road renderer lines 73-142 (hal/hle.s)
    0x30BC: 'hle_30bc',           # (DE) = (HL) + (BC) table loop (race, every frame)
    0x30FF: 'hle_30ff',           # (DE) = (HL) - (BC)
    0x8FA00: 'hle_23_7a00',       # 23:7A00: 120-byte copy (menus, every frame)
    0xD61C0: 'hle_35_61c0',       # 35:61C0: BG palettes 1-7, one per line (menus)
    # sound engine API (banks 20 and 21: same engine): music and effects as two instances
    0x80000: 'snd_play', 0x84000: 'snd_play',     # 4000: play music A
    0x80003: 'snd_update', 0x84003: 'snd_update', # 4003: once per frame
    0x80006: 'snd_both6', 0x84006: 'snd_both6',   # 4006: stop
    0x80009: 'snd_both9', 0x84009: 'snd_both9',   # 4009: reset, restart the looping effect
    0x80015: 'snd_fx', 0x84015: 'snd_fx',         # 4015: play sound effect A
    0x80018: 'snd_both18', 0x84018: 'snd_both18', # 4018: sound off
    0xD61E9: 'hle_35_61e9',       # 35:61E9: OBJ palettes 0-6 (menus)
}

# GB loops replaced by native code: rom offset of the loop entry -> (GB address where the
# code continues, HAL routine). Nothing else may jump into the loop body.
HLE_BLOCK = {
    0x183E0: (0x43EE, 'hle_06_43e0'),  # 6:43E0 challenge menu: sky gradient, one colour per line
    0x184C4: (0x44D2, 'hle_06_43e0'),  # 6:44C4 same loop (other half of the frame)
    0x180A8: (0x40B0, 'hle_06_40a8'),  # 6:40A8 wait for the VBlank (STAT mode 1)
    0x18298: (0x42CB, 'hle_06_4298'),  # 6:4298 7 map rows (tiles), one per line
    0x182D2: (0x4313, 'hle_06_42d2'),  # 6:42D2 7 map rows (attributes + 8), one per line
}

# calls/jumps into GB RAM code with a fixed meaning
RAMCALL = {
    0xFF80: 'hal_oam_dma',        # ld a,$c0/$c1 (self-modified) ; ldh ($46),a ; wait
    0xFF82: 'hal_oam_dma_a',      # same, entered with A = source page
}

# rom offset -> forced region kind for pointer instructions ('F','X','V','WX','I','G')
REGION = {}

# IO registers with side effects: read / write handlers (value in d7)
IOR = {0x00: 'io_r_p1', 0x04: 'io_r_div', 0x0F: 'io_r_if', 0x41: 'io_r_stat', 0x44: 'io_r_ly', 0x4D: 'io_r_key1',
       0x55: 'io_r_hdma5', 0x69: 'io_r_bcpd', 0x6B: 'io_r_ocpd', 0x4F: 'io_r_vbk', 0x70: 'io_r_svbk', 0x26: 'io_r_nr52'}
IOW = {0x04: 'io_w_div', 0x0F: 'io_w_if', 0x40: 'io_w_lcdc', 0x41: 'io_w_stat', 0x42: 'io_w_scy', 0x43: 'io_w_scx',
       0x45: 'io_w_lyc', 0x46: 'io_w_dma', 0x4A: 'io_w_wy', 0x4B: 'io_w_wx', 0x4F: 'io_w_vbk',
       0x55: 'io_w_hdma5', 0x68: 'io_w_bcps', 0x69: 'io_w_bcpd', 0x6A: 'io_w_ocps', 0x6B: 'io_w_ocpd',
       0x70: 'io_w_svbk'}
# sound registers: write-only bits read as 1; writes queued for the DSP
for _r in range(0x10, 0x30):
    IOR.setdefault(_r, 'io_r_snd')
# sound registers: logged for the DSP
for _r in range(0x10, 0x40):
    IOW.setdefault(_r, 'io_w_snd')

# HAL routines called before the translation of an instruction (content changes)
PATCH_BEFORE = {
    0x01FB: 'hal_nolicense',      # Infogrames logo scene, before the LCD is switched on
}

ENTRY = [0x0100, 0x0040, 0x0048, 0x0050, 0x0058, 0x0060]




