# x86_64-elf cross-compiler toolchain

<div align="center">

[![Docker Build & Push Multiarch](https://github.com/titanzero/gcc-x86_64-elf/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/titanzero/gcc-x86_64-elf/actions/workflows/docker-publish.yml)

</div>

A containerised x86_64-elf toolchain so the host machine stays clean.

Docker image with a freestanding `x86_64-elf` GCC toolchain, intended for OS development. Includes binutils, GCC (C/C++), libgcc multilib variants for `-mno-red-zone`/`-mcmodel=kernel`, and NASM.

## Build

```sh
docker build -t x86_64-elf-cross .
```

By default the build is single-threaded (`JOBS=1`) to be safe on memory-constrained machines. If you have cores to spare:

```sh
docker build --build-arg JOBS=8 -t x86_64-elf-cross .
```

You can also pin specific versions:

```sh
docker build \
  --build-arg BINUTILS_VERSION=2.46.0 \
  --build-arg GCC_VERSION=16.1.0 \
  -t x86_64-elf-cross .
```

The build takes a while - GCC from source is not fast. Grab a coffee.

## Usage

Mount your project into `/osdev` and drop into a shell:

```sh
docker run --rm -it -v $(pwd):/osdev x86_64-elf-cross
```

The cross tools are on `PATH` as `x86_64-elf-gcc`, `x86_64-elf-g++`, `x86_64-elf-ld`, etc.

```sh
x86_64-elf-gcc -ffreestanding -nostdlib -o kernel.elf kernel.c
```

For kernel code that needs to avoid the red zone (interrupt handlers, etc.):

```sh
x86_64-elf-gcc -mno-red-zone -mcmodel=kernel -ffreestanding -nostdlib -o kernel.elf kernel.c
```

## Using it from a Makefile (daemon approach)

Instead of spawning a new container per compilation unit, keep one container running in the background and talk to it via `docker exec`. Startup cost drops to zero after the first `make`.

**Start the daemon** (once, e.g. at the beginning of a work session):

```sh
docker run -d --name cross \
  -v $(pwd):/osdev \
  -w /osdev \
  --entrypoint sleep \
  x86_64-elf-cross infinity
```

`sleep infinity` keeps the container alive without doing anything. The project directory is mounted at `/osdev`.

**Makefile:**

```makefile
CONTAINER := cross

# docker exec reuses the running container — no startup overhead per file
CROSS := docker exec $(CONTAINER)

CC  := $(CROSS) x86_64-elf-gcc
CXX := $(CROSS) x86_64-elf-g++
LD  := $(CROSS) x86_64-elf-ld
AS  := $(CROSS) nasm

CFLAGS := -ffreestanding -nostdlib -mno-red-zone -mcmodel=kernel -O2 -Wall

OBJS := kernel.o boot.o

kernel.elf: $(OBJS)
	$(LD) -T linker.ld -o $@ $^

kernel.o: kernel.c
	$(CC) $(CFLAGS) -c -o $@ $<

boot.o: boot.asm
	$(AS) -f elf64 -o $@ $<

clean:
	rm -f $(OBJS) kernel.elf

# Convenience targets to manage the daemon from make
.PHONY: cross-start cross-stop

cross-start:
	docker run -d --name $(CONTAINER) \
	  -v $(PWD):/osdev -w /osdev \
	  --entrypoint sleep \
	  x86_64-elf-cross infinity

cross-stop:
	docker rm -f $(CONTAINER)
```

`make cross-start` brings the daemon up, `make cross-stop` kills it. In between, `make` works as if the tools were installed locally.

## Installed tools

| Tool | Version |
|------|---------|
| binutils | 2.46.0 |
| GCC | 16.1.0 |
| NASM | system package |

## Notes

- The image is a two-stage build: the builder compiles everything from source, the final image only ships the toolchain and its runtime shared libraries.
- `libstdc++` is built in freestanding mode (`--disable-hosted-libstdcxx`). Don't expect `<iostream>` to work — it won't.
- The toolchain has no sysroot, so `-nostdlib` or `-ffreestanding` is essentially always required.
