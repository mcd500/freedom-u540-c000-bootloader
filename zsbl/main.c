/* Copyright (c) 2018 SiFive, Inc */
/* SPDX-License-Identifier: Apache-2.0 */
/* SPDX-License-Identifier: GPL-2.0-or-later */
/* See the file LICENSE for further information */

#include <sifive/barrier.h>
#include <sifive/platform.h>
#include <sifive/smp.h>
#include <uart/uart.h>
#include <ux00boot/ux00boot.h>
#include <gpt/gpt.h>
#include "encoding.h"


static Barrier barrier;
extern const gpt_guid gpt_guid_sifive_fsbl;

#ifndef TL_CLK
#define CORE_CLK_KHZ 33000
#else
#define CORE_CLK_KHZ TL_CLK / 1000
#endif


void handle_trap(void)
{
  ux00boot_fail((long) read_csr(mcause), 1);
}


void init_uart(unsigned int peripheral_input_khz)
{
  unsigned long long uart_target_hz = 115200ULL;
  UART0_REG(UART_REG_DIV) = uart_min_clk_divisor(peripheral_input_khz * 1000ULL, uart_target_hz);
}

/* no-op */
int puts(const char* str){
#if BOARD == VC707
	uart_puts((void *) UART0_CTRL_ADDR, str);
	uart_puts((void *) UART0_CTRL_ADDR, "\r\n");
#endif
	return 1;
}

int main()
{
  puts("MAIN: START");
  if (read_csr(mhartid) == NONSMP_HART) {
    unsigned int peripheral_input_khz;
#if BOARD != VC707
    if (UX00PRCI_REG(UX00PRCI_CLKMUXSTATUSREG) & CLKMUX_STATUS_TLCLKSEL) {
      peripheral_input_khz = CORE_CLK_KHZ; // perpheral_clk = tlclk
    } else {
      peripheral_input_khz = (CORE_CLK_KHZ / 2);
    }
#else
    peripheral_input_khz = CORE_CLK_KHZ; // perpheral_clk = tlclk
#endif
    init_uart(peripheral_input_khz);
    puts("MAIN: LOAD: GPT");
    ux00boot_load_gpt_partition((void*) BOATLOADER_ADDR, &gpt_guid_sifive_fsbl, peripheral_input_khz);
    puts("MAIN: LOAD: GPT: AFTER");
  }

  Barrier_Wait(&barrier, NUM_CORES);

  return 0;
}
