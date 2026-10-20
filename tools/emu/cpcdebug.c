// Debugging additions to the headless CPC emulator in ~/repos/CPCTools/cpcemu:
// registers, single steps and run-to-address, for tools/run.py. Built into
// build/libcpcdebug.so by tools/emu/build.sh; the original library is untouched.
#include "cpcheadless.c"

// AF BC DE HL IX IY SP PC AF' BC' DE' HL' IR IM IFF1 RAMCFG
void cpcemu_regs(void* h, uint16_t* o) {
    cpc_t* s = &((emu_t*)h)->cpc;
    z80_t* c = &s->cpu;
    o[0] = c->af; o[1] = c->bc; o[2] = c->de; o[3] = c->hl;
    o[4] = c->ix; o[5] = c->iy; o[6] = c->sp; o[7] = (uint16_t)(c->pc - 1);
    o[8] = c->af2; o[9] = c->bc2; o[10] = c->de2; o[11] = c->hl2;
    o[12] = c->ir; o[13] = c->im; o[14] = c->iff1; o[15] = s->ga.ram_config;
}

static uint64_t dbg_ticks;   // 4 MHz ticks run through step1

static void step1(cpc_t* s) {
    uint64_t pins = s->pins;
    do { pins = _cpc_tick(s, pins); dbg_ticks++; } while (!z80_opdone(&s->cpu));
    s->pins = pins;
}

// run whole instructions until PC == pc (returns 1) or max instructions (0)
int cpcemu_run_to(void* h, uint16_t pc, uint32_t max) {
    cpc_t* s = &((emu_t*)h)->cpc;
    for (uint32_t i = 0; i < max; i++) {
        step1(s);
        if ((uint16_t)(s->cpu.pc - 1) == pc) return 1;
    }
    return 0;
}

// the PCs of the next n instructions
void cpcemu_trace(void* h, uint32_t n, uint16_t* pcs) {
    cpc_t* s = &((emu_t*)h)->cpc;
    for (uint32_t i = 0; i < n; i++) {
        step1(s);
        pcs[i] = (uint16_t)(s->cpu.pc - 1);
    }
}

// 4 MHz ticks spent in cpcemu_run_to/cpcemu_trace so far: timing
uint64_t cpcemu_ticks(void* h) { (void)h; return dbg_ticks; }
