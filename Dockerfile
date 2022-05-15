# Build Stage
FROM --platform=linux/amd64 ubuntu:20.04 as builder

## Install build dependencies.
RUN apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y vim less man wget tar git gzip unzip make cmake software-properties-common curl

ADD . /repo
WORKDIR /repo/compiler
RUN ./build-amd64.sh
RUN ./compile-run-amd64.sh test/amd64/arith.c
