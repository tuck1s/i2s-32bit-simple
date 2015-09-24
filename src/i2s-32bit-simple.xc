/*
 * i2s-32bit-simple.xc
 *
 *  Created on: 22 Sep 2015
 *      Author: steve
 */

#include <stdio.h>
#include <xs1.h>
#include <xclib.h>
#include <stdint.h>

clock cb = XS1_CLKBLK_1;                // Clock Block
in port bclk = XS1_PORT_1H;             // J7 pin 2 = BLCK from WM8804      Bit Clock
in port lrclk = XS1_PORT_1F;            // J7 pin 1 = LRCLK from WM8804     Word Clock
in buffered port:32 din1 = XS1_PORT_1G; // J7 pin 3 = DOUT from WM8804      Ultranet Channels 1 .. 8 data
in buffered port:32 din2 = XS1_PORT_1E; // J7 pin 4 = DOUT_9_16 from WM8804 Ultranet Channels 9 .. 16 data

out port scopetrig = XS1_PORT_1J;       // Debug scope trigger on J7 pin 10

enum i2s_state { search_frame_sync, search_multiframe_sync, in_sync };

#define nsamples 256

/* Input on two i2s streams in parallel
 * - Get LR sync
 * - Get multiframe sync (signalled by LS byte = 0x09)
 * - Process frames, while checking we're still in sync
 * - if data doesn't match, drop back to reacquire LR sync in case of missed or erroneous data
 */
void dual_i2s_in() {
    int lr, t, i;
    uint32_t s1, s2, x1[nsamples], x2[nsamples];

    scopetrig <: 0;

    // LRCLK and all data ports clocked off BCLK
    configure_in_port_no_ready(din1, cb);
    configure_in_port_no_ready(din2, cb);
    configure_in_port_no_ready(lrclk, cb);

    // clock block clocked off external BCLK
    set_clock_src(cb, bclk);
    start_clock(cb);                    // start clock block after configuration

    lrclk :> lr;                        // Read the initial value
    lrclk when pinsneq(lr) :> lr @t;    // Wait for LRCLK edge, and timestamp it

    t+= 31;                             // Just had the LSB of previous word
    din1 @t :> s1; x1[0] = bitrev(s1);
    din2 @t :> s2; x2[0] = bitrev(s2);

    printf("%08x %08x\n", x1[0], x2[0]);
    while(1){

    }
}

int main(void) {
    par {
        dual_i2s_in();
    }
    return 0;
}



