FROM --platform=linux/amd64 debian:bookworm
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates wget xz-utils git patch rsync file procps \
        gcc g++ make gawk bison flex texinfo python3 dejagnu expect \
        libgmp-dev libmpfr-dev libmpc-dev libisl-dev libzstd-dev zlib1g-dev \
        qemu-user \
    && rm -rf /var/lib/apt/lists/*
COPY run.sh qemu-wrap.sh /harness/
RUN chmod +x /harness/run.sh /harness/qemu-wrap.sh
VOLUME /work
WORKDIR /work
ENTRYPOINT ["/harness/run.sh"]
CMD ["all"]
