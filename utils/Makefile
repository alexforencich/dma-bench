
PREFIX = /usr/local
BINDIR = $(DESTDIR)$(PREFIX)/bin

CC = gcc
CFLAGS = -O3 -Wall -I../modules/dma_bench

BIN = dma-bench-config dma-bench-perf

GENDEPFLAGS = -MD -MP -MF .$(@F).d

ALL_CFLAGS = $(CFLAGS) $(GENDEPFLAGS)

all: $(BIN)

%.o: %.c
	$(CC) $(ALL_CFLAGS) -c -o $@ $<

dma-bench-config: dma_bench_config.o dma_bench.o
	$(CC) $(ALL_CFLAGS) $^ -o $@

dma-bench-perf: dma_bench_perf.o dma_bench.o
	$(CC) $(CFLAGS) $^ -o $@

install:
	install -d $(BINDIR)
	install -m 0755 $(BIN) $(BINDIR)

clean:
	rm -f $(BIN)
	rm -f *.o
	rm -f .*.d

-include $(wildcard .*.d)

.PHONY: all install clean
