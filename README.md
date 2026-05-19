# x86_64-elf cross-compiler toolchain

<div align="center">

[![Docker Build & Push Multiarch](https://github.com/titanzero/gcc-x86_64-elf/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/titanzero/gcc-x86_64-elf/actions/workflows/docker-publish.yml)

</div>

Docker image with a freestanding `x86_64-elf` GCC toolchain for OS development. Includes binutils, GCC (C/C++) with libgcc multilib variants for `-mno-red-zone`/`-mcmodel=kernel`, and NASM.

## Pull from GHCR

```sh
docker pull ghcr.io/titanzero/gcc-x86_64-elf:latest
docker tag ghcr.io/titanzero/gcc-x86_64-elf:latest x86_64-elf-cross
```

Specific versions are tagged as `gcc-16.1.0-binutils-2.46.0`:

```sh
docker pull ghcr.io/titanzero/gcc-x86_64-elf:gcc-16.1.0-binutils-2.46.0
```

## Build

```sh
docker build -t x86_64-elf-cross .
```

```sh
docker build --build-arg JOBS=8 -t x86_64-elf-cross .
```

```sh
docker build \
  --build-arg BINUTILS_VERSION=2.46.0 \
  --build-arg GCC_VERSION=16.1.0 \
  -t x86_64-elf-cross .
```

## Usage

Tools are on `PATH` as `x86_64-elf-gcc`, `x86_64-elf-g++`, `x86_64-elf-ld`, `nasm`, etc.

```sh
docker run --rm -it -v $(pwd):/osdev x86_64-elf-cross
```

## Daemon + Makefile

Keep one container running and use `docker exec` to avoid per-invocation startup cost:

```sh
docker run -d --name cross \
  -v $(pwd):/osdev \
  -w /osdev \
  --entrypoint sleep \
  x86_64-elf-cross infinity
```

```makefile
CONTAINER := cross
CROSS     := docker exec $(CONTAINER)

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

.PHONY: cross-start cross-stop

cross-start:
	docker run -d --name $(CONTAINER) \
	  -v $(PWD):/osdev -w /osdev \
	  --entrypoint sleep \
	  x86_64-elf-cross infinity

cross-stop:
	docker rm -f $(CONTAINER)
```

## Installed tools

| Tool     | Version        |
|----------|----------------|
| binutils | 2.46.0         |
| GCC      | 16.1.0         |
| NASM     | system package |
