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
in buffered port:32 dinA = XS1_PORT_1G; // J7 pin 3 = DOUT from WM8804      Ultranet Channels 1 .. 8 data
in buffered port:32 dinB = XS1_PORT_1E; // J7 pin 4 = DOUT_9_16 from WM8804 Ultranet Channels 9 .. 16 data

out port scopetrig = XS1_PORT_1J;       // Debug scope trigger on J7 pin 10

enum i2s_state { search_lr_sync, search_multiframe_sync, check_second_multiframe_sync, in_sync };

#define FRAME_SIZE 0x180

/* Input on two i2s streams A and B in parallel
 * - Get LR sync
 * - Get multiframe sync (signalled by LS byte = 0x09)
 * - Process frames, while checking we're still in sync
 * - if data doesn't match, drop back to reacquire LR sync in case of missed or erroneous data
 */
void dual_i2s_in(streaming chanend c) {
    enum i2s_state st;
    int t, lr;
    uint32_t s1A, s2A, s1B, s2B;
    uint32_t frame_ctr_err = 0;
    const uint8_t lsb_mid = 0x01;                   // LSB values seen on Ultranet interface
    const uint8_t lsb_mframe = 0x09;

    // LRCLK and all data ports clocked off BCLK
    configure_in_port(dinA, cb);
    configure_in_port(dinB, cb);
    configure_in_port(lrclk, cb);

    // clock block clocked off external BCLK
    set_clock_src(cb, bclk);
    start_clock(cb);                                // start clock block after configuration
    st = search_lr_sync;

    while(1){
        switch(st) {
            case search_lr_sync:
                lrclk :> lr;                        // Read the initial value
                lrclk when pinsneq(lr) :> lr @t;    // Wait for LRCLK edge, and timestamp it

                t+= 31;                             // Just had the LSB of previous word
                dinB @t :> s1B; s1B = bitrev(s1B);  // todo: why does this only work when in order B then A?
                dinA @t :> s1A; s1A = bitrev(s1A);

                // Change state only if we're strictly in mid-frame on both channels
                if( (s1A & 0xff) == lsb_mid ) {
                    st = search_multiframe_sync;
                    t = FRAME_SIZE;                 // limit acquisition time
                }
                break;

            case search_multiframe_sync:
                // Look for samples, on both channels, that match multiframe sync pattern
                // pre-req: t must be set to max acquisition time
                dinA :> s1A; s1A = bitrev(s1A);
                dinB :> s1B; s1B = bitrev(s1B);
                if((s1A & 0xff) == lsb_mframe && (s1B & 0xff) == lsb_mframe) {
                    st = check_second_multiframe_sync;
                }
                else {
                    if(--t <=0) {
                        printf("FC! %08x %08x\n",s1A, s1B);            //fixme: Wiggle LEDS if many errors
                        frame_ctr_err++;
                        st = search_lr_sync;        // Waited too long - start again from scratch
                    }
                }
                break;

            case check_second_multiframe_sync:
                dinA :> s2A; s2A = bitrev(s2A);
                dinB :> s2B; s2B = bitrev(s2B);
                if((s2A & 0xff) == lsb_mframe && (s2B & 0xff) == lsb_mframe) {
                    // Stream out the valid samples from the start of this multiframe
                    c<: s1A;
                    c<: s1B;
                    c<: s2A;
                    c<: s2B;
                    st = in_sync;
                }
                else {
                    frame_ctr_err++;         // Valid mframe then non-mframe is an error
                    printf("FR! %08x %08x %08x %08x\n",s1A, s1B, s2A, s2B);            //fixme: Wiggle LEDS if many errors
                    st = search_lr_sync;     // Mismatch - go back to initial state and re-acquire sync
                }
                break;

            case in_sync:
                // Process the remaining complete frame of data
                for(t=2; t<FRAME_SIZE; t++) {
                    dinA :> s1A; s1A = bitrev(s1A);
                    dinB :> s1B; s1B = bitrev(s1B);
                    c<: s1A;
                    c<: s1B;
                }
                // Check the next frame is starting with multiframe sync in the expected place
                t = 1;                      // Strict - only got 1 chance to get it
                st = search_multiframe_sync;
                break;
        }
    }
}


#define NSAMPLES (0x2000)
// Display up to n incoming samples, then wait a bit
void display_task(streaming chanend c) {
    unsigned v[NSAMPLES], i;

    printf("Starting ..");
    //dump a block of samples
    for(i=0; i<NSAMPLES; i++) {
        c:> v[i];        // Receive an integer from the channel
    }
    for(i=0; i<NSAMPLES; i++) {
        if(i % 8 == 0) {
            printf("\n%04x: ",i);
        }
        printf("%08x ", v[i]);
    }
    printf("\nDone\n");
    while(1) {
        delay_milliseconds(10);
    }
}

int main(void) {
    streaming chan c;

    par {
        dual_i2s_in(c);
        display_task(c);
    }
    return 0;
}



