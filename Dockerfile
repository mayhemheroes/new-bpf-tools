FROM --platform=linux/amd64 ubuntu:20.04 as builder

RUN apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential

ADD . /repo
WORKDIR /repo/compiler
RUN ./build-amd64.sh
RUN ./compile-run-amd64.sh test/amd64/arith.c

RUN mkdir -p /deps
RUN ldd /repo/compiler/a.out | tr -s '[:blank:]' '\n' | grep '^/' | xargs -I % sh -c 'cp % /deps;'

FROM ubuntu:20.04 as package

COPY --from=builder /deps /deps
COPY --from=builder /repo/compiler/a.out /repo/compiler/a.out
ENV LD_LIBRARY_PATH=/deps
