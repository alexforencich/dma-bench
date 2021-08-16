
# object files to build
obj-m += dma_bench.o
dma_bench-objs += dma_bench_main.o dma_bench_stats.o

all:
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) modules

clean:
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) clean

