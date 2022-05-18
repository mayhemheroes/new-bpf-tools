FROM --platform=linux/amd64 ubuntu:20.04

RUN apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential

ADD . /repo
WORKDIR /repo/compiler
RUN ./build-amd64.sh
RUN ./compile-run-amd64.sh test/amd64/arith.c
