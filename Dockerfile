# Stage 1: build binutils and GCC from source. Nothing from this stage
# leaks into the final image except the compiled toolchain under $PREFIX.
FROM ubuntu:26.04 AS builder

ARG BINUTILS_VERSION=2.46.0
ARG GCC_VERSION=16.1.0
ARG TARGET=x86_64-elf
ARG PREFIX=/opt/cross
# Keep JOBS=1 by default to avoid OOM on small builders; override with --build-arg
ARG JOBS=1

ENV DEBIAN_FRONTEND=noninteractive

# All the usual suspects for a GNU toolchain build. texinfo is needed for
# makeinfo when building GCC docs (even if we don't install them).
RUN apt-get update && apt-get install -y \
    build-essential \
    bison \
    flex \
    gawk \
    texinfo \
    wget \
    xz-utils \
    libgmp-dev \
    libmpfr-dev \
    libmpc-dev \
    libisl-dev \
    && rm -rf /var/lib/apt/lists/* \
    && export PATH="${PREFIX}/bin:${PATH}"

WORKDIR /tmp/src

RUN wget -q https://ftp.gnu.org/gnu/binutils/binutils-${BINUTILS_VERSION}.tar.xz
RUN tar -xf binutils-${BINUTILS_VERSION}.tar.xz
RUN mkdir binutils-build
WORKDIR /tmp/src/binutils-build

# --with-sysroot tells binutils the cross target has no host sysroot,
# which is correct for a bare-metal elf target.
RUN ../binutils-${BINUTILS_VERSION}/configure \
        --target=${TARGET} \
        --prefix=${PREFIX} \
        --with-sysroot \
        --disable-nls \
        --disable-werror

RUN make -j${JOBS}
RUN make install

WORKDIR /tmp/src

RUN wget -q https://ftp.gnu.org/gnu/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.xz
RUN tar -xf gcc-${GCC_VERSION}.tar.xz
RUN mkdir build-gcc
WORKDIR /tmp/src/build-gcc

# Inject a custom tmake fragment so the x86_64-elf target builds libgcc
# multilib variants for -mno-red-zone and -mcmodel=kernel. Both are needed
# for kernel code that can't use the System V ABI red zone.
RUN printf '# Add libgcc multilib variant without red-zone requirement\n\nMULTILIB_OPTIONS += mno-red-zone mcmodel=kernel\nMULTILIB_DIRNAMES += no-red-zone mcmodel=kernel\n' \
    > /tmp/src/gcc-${GCC_VERSION}/gcc/config/i386/t-x86_64-elf

# Wire the fragment into config.gcc so GCC actually picks it up during configure
RUN sed -i '/x86_64-\*-elf\*)/a \\ttmake_file="${tmake_file} i386/t-x86_64-elf"' \
    /tmp/src/gcc-${GCC_VERSION}/gcc/config.gcc

# --without-headers and --disable-hosted-libstdcxx are mandatory for a
# freestanding cross compiler that targets an OS not yet written.
RUN ../gcc-${GCC_VERSION}/configure \
        --target=${TARGET} \
        --prefix=${PREFIX} \
        --disable-nls \
        --enable-languages=c,c++ \
        --without-headers \
        --disable-hosted-libstdcxx

RUN make -j${JOBS} all-gcc

# libgcc fails with -fPIC on a bare-metal target. Let it fail once so the
# Makefiles are generated, then disable PICFLAG before retrying.
RUN make -j${JOBS} all-target-libgcc || true
RUN find /tmp/src/build-gcc/${TARGET} -name "Makefile" | xargs sed -i 's/PICFLAG/DISABLED_PICFLAG/g'
RUN make -j${JOBS} all-target-libgcc

RUN make -j${JOBS} all-target-libstdc++-v3
RUN make install-gcc
RUN make install-target-libgcc
RUN make install-target-libstdc++-v3

# Shave some MB off the final image; --strip-debug keeps enough info for
# linker scripts to work while removing the bulk of debug sections.
RUN find ${PREFIX} -type f -executable | xargs strip --strip-debug 2>/dev/null || true

# Stage 2: lean runtime image, only the compiled toolchain and its runtime deps
FROM ubuntu:26.04 AS final

ARG PREFIX=/opt/cross

COPY --from=builder ${PREFIX} ${PREFIX}

# Runtime shared libraries required by the cross toolchain binaries.
# nasm is included for convenience since most osdev projects need it.
RUN apt-get update && apt-get install -y \
    make \
    nasm \
    libgmp10 \
    libmpfr6 \
    libmpc3 \
    libisl23 \
    && rm -rf /var/lib/apt/lists/*

ENV PATH="${PREFIX}/bin:${PATH}"

WORKDIR /osdev

CMD ["/bin/bash"]
