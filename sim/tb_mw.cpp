// Full-system bench: the whole machine from reset behind the MiSTer memory subsystem, the ROM image
// streamed in through the loader, video out. Runs N frames and writes the frames asked for as raw
// RGB (288 x 224, 32-bit little-endian 0x00RRGGBB; tools/rgb2png.py makes a PNG of one), a per-frame
// trace, and the audio as a WAV. The Violent Storm core's bench (sim/tb_vs.cpp there) with this board's
// image layout, inputs and interrupts.
//
//   tb_mw <image.rom> <eeprom.nv> <frames> <out-prefix>
//
// Environment:
//   SNAPFRAMES=a,b,c   frames whose picture is saved as <prefix>.f<N>.rgb (default: the last)
//   SNAPEVERY=n        ... and every n-th frame
//   SCHED=survey|play  scripted inputs (coin, start, buttons), by frame
//   SCHEDLAG=n         apply the SCHED inputs n frames later
//   SCHEDLINE=n        apply the SCHED / KEYS inputs at raster line n after the frame's end, not at the end (261:
//                      where MAME's frame notifier, and so tools/lua/dump_state.lua's SCHEDULE, applies them)
//   BACKDOOR=1         place the image straight into the SDRAM model (the loader's address arithmetic, without
//                      the 16 MB of streaming); the streamed load is the default
//   PATCH=a:hh..,..    patch the image's 68000 program before it is loaded (a simulation shortcut, e.g. past the
//                      power-on RAM / ROM check: see SKIPBOOT)
//   SKIPBOOT=1         sim/run_mw.sh passes tools/skipboot.txt's patch as PATCH
//   TESTAT=n           the test switch pressed from frame n on (the service menu; held from reset it clears the EEPROM)
//   KEYS=f:mask:len,.. player 1's inputs (mask: bit0 left .. 3 down, 4-6 buttons, 7 start) held len frames from frame f
//   AUDIO=1            write <prefix>.wav (48 kHz stereo)
//   TRACE=1            one line a frame in <prefix>.trace
//   TESTSW=1           hold the test switch (IN1 bit 2, low = on)
//   DUMPSTATE=a,b,c    at the end of those frames, write the video chips' registers and RAMs to <prefix>.state_<N>.txt
//   DUMPLINE=n         ... at raster line n after the frame's end instead (261: the instant of MAME's frame update,
//                      where tools/lua/dump_state.lua takes its states, mw_core OBJ_BUILD_LINE)
//   ROMCHK=1           compare every tile / sprite read the renderers complete with the image
#include "Vtb_mw_top.h"
#include "Vtb_mw_top___024root.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
#include <set>
#include <map>
#include <string>
#include <algorithm>

static const int VIS_W = 288, VIS_H = 224;

static Vtb_mw_top *dut;
static unsigned long long cycles = 0;
static inline void tick() { dut->clk = 0; dut->eval(); dut->clk = 1; dut->eval(); cycles++; }

// image layout (byte offsets), mra/*.mra
static const size_t IMG_PROG = 0x000000, IMG_SND = 0x200000, IMG_TILE = 0x240000,
                    IMG_PCM = 0x640000, IMG_SPR = 0xA40000, IMG_SPR5 = 0xE40000, IMG_END = 0xF40000;

static std::set<int> parse_list(const char *e) {
    std::set<int> s; if (!e) return s;
    char *w = strdup(e); for (char *t = strtok(w, ","); t; t = strtok(nullptr, ",")) s.insert(atoi(t));
    free(w); return s;
}

// the video chips' registers and RAMs (a word is 4 hex digits)
static void dump_state(const char *path, int frame) {
    auto &r = *dut->rootp;
    FILE *f = fopen(path, "w"); if (!f) return;
    fprintf(f, "# mystic warriors core state, frame %d\nFRAME %d\n", frame, frame);
    auto words = [&](const char *name, int n, auto get) {
        fprintf(f, "%s", name);
        for (int i = 0; i < n; i++) fprintf(f, " %04x", (unsigned)get(i) & 0xffff);
        fprintf(f, "\n");
    };
    words("K56REGS", 32, [&](int i) { return r.tb_mw_top__DOT__u_core__DOT__k56regs[i]; });
    words("K56REGSB", 4, [&](int i) { return r.tb_mw_top__DOT__u_core__DOT__k56regsb[i]; });
    words("K46REGS", 8, [&](int i) { return r.tb_mw_top__DOT__u_core__DOT__k46regs[i]; });
    words("K47REGS", 8, [&](int i) { return r.tb_mw_top__DOT__u_core__DOT__k47regs[i]; });
    words("K55REGS", 48, [&](int i) { return r.tb_mw_top__DOT__u_core__DOT__k55regs[i]; });
    words("K38REGS", 16, [&](int i) { return r.tb_mw_top__DOT__u_core__DOT__k38regs[i]; });
    words("PALETTE", 4096, [&](int i) {
        unsigned e = i >> 1;
        return (i & 1) ? r.tb_mw_top__DOT__u_core__DOT__u_main__DOT__pal1[e] : r.tb_mw_top__DOT__u_core__DOT__u_main__DOT__pal0[e]; });
    words("SPRITERAM", 2048, [&](int i) { return r.tb_mw_top__DOT__u_core__DOT__u_main__DOT__sram[i]; });
    for (int pg = 0; pg < 16; pg++) {
        char nm[16]; snprintf(nm, sizeof nm, "VRAM %d", pg);
        words(nm, 4096, [&](int i) {
            unsigned a = (pg << 12) | i;
            return ((unsigned)r.tb_mw_top__DOT__u_mem__DOT__u_vram__DOT__ram_hi[a] << 8) | r.tb_mw_top__DOT__u_mem__DOT__u_vram__DOT__ram_lo[a]; });
    }
    fclose(f);
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    if (argc < 5) { fprintf(stderr, "usage: %s <image.rom> <eeprom.nv> <frames> <out-prefix>\n", argv[0]); return 2; }
    int frames = atoi(argv[3]);
    std::string prefix = argv[4];

    std::vector<unsigned char> img;
    { FILE *f = fopen(argv[1], "rb"); if (!f) { fprintf(stderr, "cannot open %s\n", argv[1]); return 1; }
      fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET); img.resize(n);
      if (fread(img.data(), 1, n, f) != (size_t)n) { fprintf(stderr, "short read\n"); return 1; } fclose(f); }
    if (img.size() != IMG_END) fprintf(stderr, "warning: image is %zu bytes, expected %zu\n", img.size(), IMG_END);
    std::vector<unsigned char> nv(128, 0);
    { FILE *f = fopen(argv[2], "rb"); if (f) { if (fread(nv.data(), 1, 128, f) != 128) fprintf(stderr, "short nv\n"); fclose(f); } }

    // PATCH=addr:hexbytes,...: overwrite bytes of the 68000 program (a simulation shortcut, never part of an image)
    if (getenv("PATCH") && *getenv("PATCH")) {
        char *w = strdup(getenv("PATCH"));
        for (char *t = strtok(w, ","); t; t = strtok(nullptr, ",")) {
            char *c = strchr(t, ':'); if (!c) continue; *c = 0;
            unsigned long a = strtoul(t, nullptr, 16); const char *h = c + 1;
            printf("PATCH $%06lx:", a);
            for (; h[0] && h[1]; h += 2, a++) {
                char b[3] = {h[0], h[1], 0};
                if (a < IMG_SND) { img[IMG_PROG + a] = (unsigned char)strtoul(b, nullptr, 16); printf(" %s", b); }
            }
            printf("\n");
        }
        free(w);
    }

    std::set<int> snaps = parse_list(getenv("SNAPFRAMES"));
    std::set<int> dumps = parse_list(getenv("DUMPSTATE"));
    const int dumpline = getenv("DUMPLINE") ? atoi(getenv("DUMPLINE")) : -1;
    int snapevery = getenv("SNAPEVERY") ? atoi(getenv("SNAPEVERY")) : 0;
    // TESTAT=n: the test switch pressed from frame n on (the service menu); KEYS=f:mask:len,...: player 1's bits in
    // mask (bit0 left, 1 right, 2 up, 3 down, 4-6 buttons, 7 start) held for len frames from frame f
    int testat = getenv("TESTAT") ? atoi(getenv("TESTAT")) : -1;
    struct key_t { int f; unsigned m; int len; };
    std::vector<key_t> keys;
    if (getenv("KEYS")) {
        char *w = strdup(getenv("KEYS"));
        for (char *t = strtok(w, ","); t; t = strtok(nullptr, ",")) {
            key_t k{0, 0, 1};
            if (sscanf(t, "%d:%x:%d", &k.f, &k.m, &k.len) >= 2) keys.push_back(k);
        }
        free(w);
    }
    const char *sch = getenv("SCHED");
    bool survey = sch && !strcmp(sch, "survey"), play = sch && !strcmp(sch, "play");
    int schedlag = getenv("SCHEDLAG") ? atoi(getenv("SCHEDLAG")) : 0;
    const int schedline = getenv("SCHEDLINE") ? atoi(getenv("SCHEDLINE")) : -1;
    bool want_audio = getenv("AUDIO") && atoi(getenv("AUDIO"));
    FILE *tr = (getenv("TRACE") && atoi(getenv("TRACE"))) ? fopen((prefix + ".trace").c_str(), "w") : nullptr;
    // PCLOG=n: the 68000's first n opcode fetches (a run of the same few addresses, a loop, is written once)
    long pclog_n = getenv("PCLOG") ? atol(getenv("PCLOG")) : 0;
    FILE *pcl = pclog_n ? fopen((prefix + ".pclog").c_str(), "w") : nullptr;
    unsigned pcl_prev[8] = {0}; int pcl_i = 0; long pcl_rep = 0;

    dut = new Vtb_mw_top;
    // MAME's idle IN1 (496002): bit 7 unused DIP 1, bit 6 two players, bit 5 common coin mechanism, bit 4 stereo,
    // bit 3 0, bit 2 the test switch off (high); bits 1:0 are the EEPROM's, replaced in the core
    const unsigned IN1_IDLE = 0xe4;
    unsigned in1_val = (getenv("TESTSW") && atoi(getenv("TESTSW"))) ? (IN1_IDLE & ~0x04u) : IN1_IDLE;
    dut->reset = 1; dut->dl_hold = 1; dut->dl_start = 0; dut->dl_we = 0; dut->eep_we = 0;
    dut->in_p1_p2 = 0xffff; dut->in_p3_p4 = 0xffff; dut->in0 = 0xff; dut->in1 = in1_val;
    for (int i = 0; i < 16; i++) tick();
    dut->reset = 0;
    // wait for the SDRAM's initialisation and the caches
    long w = 0;
    while (!dut->mem_ready) { tick(); if (++w > 2000000) { fprintf(stderr, "memory never became ready\n"); return 1; } }
    printf("memory ready after %llu clocks; loading %zu bytes\n", cycles, img.size());

    bool backdoor = getenv("BACKDOOR") && atoi(getenv("BACKDOOR"));
    unsigned long long t0 = cycles;
    if (backdoor) {
        // straight into the SDRAM model, in the places the loader (target/mister/mw_mem.sv) puts the words
        auto &sd = dut->rootp->tb_mw_top__DOT__chip__DOT__mem;
        const unsigned SD_TILE = 0x000000, SD_PCM = 0x180000, SD_SPR = 0x380000, SD_PROG = 0x800000, SD_SND = 0x900000;
        for (size_t wa = 0; wa < img.size() / 2; wa++) {
            unsigned v = ((unsigned)img[wa * 2] << 8) | img[wa * 2 + 1];
            size_t b = wa * 2;
            if (b < IMG_SND)       sd[SD_PROG + wa] = v;
            else if (b < IMG_TILE) sd[SD_SND  + (wa - IMG_SND / 2)] = v;
            else if (b < IMG_PCM)  {       // a row's 8-byte group: words 0-2 kept (chunky, chunky, fifth plane + pad)
                size_t rel = wa - IMG_TILE / 2;
                if ((rel & 3) != 3) sd[SD_TILE + (rel >> 2) * 3 + (rel & 3)] = v;
            }
            else if (b < IMG_SPR)  sd[SD_PCM  + (wa - IMG_PCM / 2)] = v;
            else if (b < IMG_SPR5) { size_t rel = wa - IMG_SPR / 2; sd[SD_SPR + (rel >> 2) * 5 + (rel & 3)] = v; }
            else if (b < IMG_END)  { size_t rel = wa - IMG_SPR5 / 2; sd[SD_SPR + rel * 5 + 4] = v; }
        }
        printf("image placed by the backdoor\n");
    } else {
        // the image, a byte at a time as the HPS delivers it, held off while the loader's FIFO is full
        dut->dl_start = 1; tick(); dut->dl_start = 0;
        for (size_t i = 0; i < img.size(); i++) {
            while (dut->dl_wait) tick();
            dut->dl_we = 1; dut->dl_addr = (unsigned)i; dut->dl_data = img[i]; tick();
            dut->dl_we = 0;
            if ((i & 0xfffff) == 0xfffff) { printf("  %zu MB loaded\n", (i + 1) >> 20); fflush(stdout); }
        }
        dut->dl_we = 0;
        for (int i = 0; i < 4000; i++) tick();                         // the loader drains
    }
    for (int i = 0; i < 128; i++) { dut->eep_we = 1; dut->eep_waddr = i; dut->eep_wdata = nv[i]; tick(); }
    dut->eep_we = 0;
    printf("image loaded in %llu clocks\n", cycles - t0);
    dut->dl_hold = 0;

    std::vector<unsigned> fb(VIS_W * VIS_H, 0);
    std::vector<short> audio;
    int frame = 0, x = 0, y = 0;
    bool prev_vblank = true;
    unsigned long long steps = 0, frame_steps = 0;
    unsigned irq2 = 0, irq4 = 0, zsteps = 0, overruns = 0, de_px = 0;
    bool irq2_seen = false, irq4_seen = false, prev_irq2 = false, prev_irq4 = false;
    unsigned vc_last = 0xffff;
    unsigned ovl_events = 0, ovl_n = 0, ovl_line[4] = {0}, ovl_src[4] = {0};   // overrunning lines of the frame (first four)
    unsigned last_pc = 0;
    std::map<unsigned, unsigned> pc_hist;
    // the input words in the core's form (bit set = released): 494000 low byte P1, 496000 the coins
    auto sched = [&](int n, unsigned &p1, unsigned &c) {
        p1 = 0xff; c = 0xff;                 // P1's byte (bit0 left, 1 right, 2 up, 3 down, 4-6 buttons, 7 start); coins
        auto press = [&](unsigned &v, unsigned m, bool on) { if (on) v &= ~m; };
        if (survey) {
            press(c,  0x01, n > 200 && (n % 120) < 8);
            press(p1, 0x80, n > 260 && (n % 90) < 8 && (n % 120) >= 8);
            if (n > 500) {
                press(p1, 0x10, n % 11 < 4);
                press(p1, 0x20, n % 29 < 3);
                press(p1, 0x40, n % 43 < 3);
                press(p1, 0x02, n % 97 < 40);
                press(p1, 0x01, n % 131 > 100);
                press(p1, 0x04, n % 53 < 20);
                press(p1, 0x08, n % 71 > 60);
            }
        } else if (play) {
            press(c,  0x01, n > 200 && (n % 240) < 8);
            press(p1, 0x80, n > 260 && (n % 90) < 8 && (n % 240) >= 8);
            if (n > 500) {
                press(p1, 0x10, n % 7 < 3);
                press(p1, 0x20, n % 61 < 2);
                press(p1, 0x40, n % 83 < 2);
                press(p1, 0x02, n % 160 < 130);
                press(p1, 0x01, (n + 40) % 400 < 12);
                press(p1, 0x04, n % 97 < 18);
                press(p1, 0x08, n % 131 > 112);
            }
        }
    };

    unsigned long long ck0 = cycles;
    bool romchk = getenv("ROMCHK") && atoi(getenv("ROMCHK"));
    unsigned long long chk_n[2] = {0, 0}, chk_bad[2] = {0, 0};
    bool prev_tack = false, prev_sack = false;
    // the scripted inputs for the frame just ended
    auto apply_inputs = [&]() {
        if (survey || play) {
            unsigned p1, c; sched(frame - schedlag, p1, c);
            dut->in_p1_p2 = 0xff00 | p1;
            dut->in0 = c;
        }
        if (!keys.empty()) {
            unsigned p1 = 0xff;
            for (auto &k : keys) if (frame >= k.f && frame < k.f + k.len) p1 &= ~k.m;
            dut->in_p1_p2 = 0xff00 | p1;
        }
    };
    while (frame < frames) {
        tick();
        if (romchk) {
            auto &r = *dut->rootp;
            bool ta = r.tb_mw_top__DOT__chk_tile_ack, sa = r.tb_mw_top__DOT__chk_spr_ack;
            if (ta && !prev_tack) {
                unsigned a = r.tb_mw_top__DOT__chk_tile_addr; unsigned long long q = r.tb_mw_top__DOT__chk_tile_q;
                unsigned long long e = 0; for (int b = 0; b < 5; b++) e = (e << 8) | img[IMG_TILE + (size_t)a * 8 + b];
                chk_n[0]++;
                if (q != e) { if (chk_bad[0] < 6) printf("TILE a=%05x got %010llx want %010llx (frame %d)\n", a, q, e, frame); chk_bad[0]++; }
            }
            if (sa && !prev_sack) {
                unsigned a = r.tb_mw_top__DOT__chk_spr_addr;
                // 80 bits: [79:16] = the row's 8 bytes, [15:0] = the fifth plane's word
                unsigned long long hi = 0; for (int b = 0; b < 8; b++) hi = (hi << 8) | img[IMG_SPR + (size_t)a * 8 + b];
                unsigned lo = ((unsigned)img[IMG_SPR5 + (size_t)a * 2] << 8) | img[IMG_SPR5 + (size_t)a * 2 + 1];
                auto &q = r.tb_mw_top__DOT__chk_spr_q;
                unsigned long long qhi = ((unsigned long long)q[2] << 48) | ((unsigned long long)q[1] << 16) | (q[0] >> 16);
                unsigned qlo = q[0] & 0xffff;
                chk_n[1]++;
                if (qhi != hi || qlo != lo) { if (chk_bad[1] < 6) printf("SPR a=%05x got %016llx/%04x want %016llx/%04x (frame %d)\n", a, qhi, qlo, hi, lo, frame); chk_bad[1]++; }
            }
            prev_tack = ta; prev_sack = sa;
        }
        if (want_audio && dut->snd_valid) { audio.push_back((short)dut->snd_l); audio.push_back((short)dut->snd_r); }
        if (dut->dbg_zstep) zsteps++;
        if (dut->dbg_vcount != vc_last) {
            vc_last = dut->dbg_vcount; if (dut->dbg_overrun) overruns++;
            if (schedline >= 0 && (int)vc_last == schedline && frame > 0) apply_inputs();
            if (dumpline >= 0 && (int)vc_last == dumpline && dumps.count(frame)) {
                char path[512]; snprintf(path, sizeof path, "%s.state_%d.txt", prefix.c_str(), frame);
                dump_state(path, frame);
            }
        }
        if (dut->dbg_overrun_line) {
            ovl_events++;
            if (ovl_n < 4) { ovl_line[ovl_n] = dut->dbg_vcount; ovl_src[ovl_n] = dut->dbg_overrun_src; ovl_n++; }
        }
        if (dut->dbg_step) {
            steps++; frame_steps++;
            if (dut->dbg_busstate == 0) {
                last_pc = dut->dbg_addr; pc_hist[last_pc]++;
                if (pcl && pclog_n > 0) {
                    bool seen = false;
                    for (int k = 0; k < 8; k++) if (pcl_prev[k] == last_pc) seen = true;
                    if (seen) pcl_rep++;
                    else {
                        if (pcl_rep) fprintf(pcl, "  (+%ld in a loop)\n", pcl_rep);
                        pcl_rep = 0;
                        fprintf(pcl, "%06x f%d\n", last_pc, frame); pclog_n--;
                        pcl_prev[pcl_i] = last_pc; pcl_i = (pcl_i + 1) & 7;
                    }
                }
            }
        }
        if (dut->dbg_irq2 && !prev_irq2) irq2_seen = true;
        if (dut->dbg_irq4 && !prev_irq4) irq4_seen = true;
        prev_irq2 = dut->dbg_irq2; prev_irq4 = dut->dbg_irq4;
        if (dut->cen_pix) {
            if (dut->de) {
                if (y >= 0 && y < VIS_H && x < VIS_W) fb[y * VIS_W + x] = dut->rgb;
                x++; de_px++;
            } else if (x) { x = 0; y++; }
            if (dut->vblank && !prev_vblank) {          // the end of a frame
                frame++;
                if (tr) {
                    unsigned hot = 0, hotn = 0;
                    for (auto &kv : pc_hist) if (kv.second > hotn) { hotn = kv.second; hot = kv.first; }
                    fprintf(tr, "frame %d: steps=%llu irq2=%d irq4=%d irqctl=%02x objs=%u overrun=%u unsup=%d de_px=%u pc=%06x hot=%06x(%u) zsteps=%u eep_dirty=%d ovl=%u[%u:%u %u:%u %u:%u %u:%u]\n",
                            frame, frame_steps, irq2_seen, irq4_seen, (unsigned)dut->dbg_irq_ctrl, (unsigned)dut->dbg_objcount, overruns,
                            (int)dut->dbg_unsupported, de_px, last_pc, hot, hotn, zsteps, (int)dut->eep_dirty,
                            ovl_events, ovl_line[0], ovl_src[0], ovl_line[1], ovl_src[1], ovl_line[2], ovl_src[2], ovl_line[3], ovl_src[3]);
                    fflush(tr);
                }
                pc_hist.clear(); zsteps = 0; overruns = 0; frame_steps = 0; de_px = 0;
                ovl_events = 0; ovl_n = 0;
                if (irq2_seen) irq2++;
                if (irq4_seen) irq4++;
                irq2_seen = false; irq4_seen = false;
                if (snaps.count(frame) || (snapevery && frame % snapevery == 0) || (snaps.empty() && !snapevery && frame == frames)) {
                    char path[512]; snprintf(path, sizeof path, "%s.f%d.rgb", prefix.c_str(), frame);
                    FILE *o = fopen(path, "wb"); if (o) { fwrite(fb.data(), 4, fb.size(), o); fclose(o); }
                }
                if (dumpline < 0 && dumps.count(frame)) {
                    char path[512]; snprintf(path, sizeof path, "%s.state_%d.txt", prefix.c_str(), frame);
                    dump_state(path, frame);
                }
                if (frame % 50 == 0) {
                    double mcps = (double)(cycles - ck0) / 1e6;
                    printf("frame %d (%.1f M clocks)\n", frame, mcps); fflush(stdout);
                }
                if (schedline < 0) apply_inputs();
                if (testat >= 0 && frame >= testat) dut->in1 = in1_val & ~0x04u;
                y = 0; x = 0;
            }
            prev_vblank = dut->vblank;
        }
    }
    if (romchk) printf("ROM check: tile reads %llu (%llu wrong), sprite reads %llu (%llu wrong)\n",
                       chk_n[0], chk_bad[0], chk_n[1], chk_bad[1]);
    printf("%d frames, %llu clocks, %llu 68000 steps (%.0f a frame); IRQ2 in %u frames, IRQ4 in %u; unsupported=%d shadow_overlap=%d\n",
           frames, cycles, steps, (double)steps / frames, irq2, irq4, (int)dut->dbg_unsupported, (int)dut->dbg_shadow_overlap);
    if (want_audio) {
        std::string wp = prefix + ".wav";
        FILE *wf = fopen(wp.c_str(), "wb");
        if (wf) {
            unsigned data_bytes = audio.size() * 2, rate = 48000;
            auto u32 = [&](unsigned v) { fputc(v & 255, wf); fputc((v >> 8) & 255, wf); fputc((v >> 16) & 255, wf); fputc((v >> 24) & 255, wf); };
            auto u16 = [&](unsigned v) { fputc(v & 255, wf); fputc((v >> 8) & 255, wf); };
            fwrite("RIFF", 1, 4, wf); u32(36 + data_bytes); fwrite("WAVEfmt ", 1, 8, wf);
            u32(16); u16(1); u16(2); u32(rate); u32(rate * 4); u16(4); u16(16);
            fwrite("data", 1, 4, wf); u32(data_bytes);
            fwrite(audio.data(), 2, audio.size(), wf); fclose(wf);
            printf("audio: %zu stereo samples -> %s\n", audio.size() / 2, wp.c_str());
        }
    }
    if (tr) fclose(tr);
    delete dut;
    return 0;
}
