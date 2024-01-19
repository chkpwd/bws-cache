FROM node:20.11 as builder

# renovate: datasource=github-releases depName=bitwarden/sdk
# TODO: pin to release tag when new release published on bitwarden/sdk; depends on aef6a21
# ARG BWS_SDK_VERSION=0.4.0
ARG BWS_SDK_BRANCH=main
# renovate: datasource=github-releases depName=rust-lang/rust
ARG RUST_VERSION=1.75.0

ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH

# Install Rust
RUN dpkgArch="$(dpkg --print-architecture)" &&\
    case "${dpkgArch##*-}" in \
        amd64) rustArch='x86_64-unknown-linux-gnu' ;; \
        armhf) rustArch='armv7-unknown-linux-gnueabihf' ;; \
        arm64) rustArch='aarch64-unknown-linux-gnu' ;; \
        *) echo >&2 "unsupported architecture: ${dpkgArch}"; exit 1 ;; \
    esac &&\
    url="https://static.rust-lang.org/rustup/dist/${rustArch}/rustup-init" &&\
    wget "$url" &&\
    chmod +x rustup-init &&\
    ./rustup-init -y --no-modify-path --profile minimal --default-host ${rustArch} &&\
    rm rustup-init &&\
    chmod -R a+w $RUSTUP_HOME $CARGO_HOME &&\
    rustup --version &&\
    cargo --version &&\
    rustc --version

# Clone BWS SDK
RUN git clone https://github.com/bitwarden/sdk.git &&\
    cd sdk &&\
    [ -n "${BWS_SDK_VERSION}" ] && git checkout bws-v${BWS_SDK_VERSION} || git checkout ${BWS_SDK_BRANCH}

WORKDIR /sdk

# Compile Rust package
RUN cargo build --package bitwarden-py --release

# Generate schemas
RUN npm ci &&\
    npm run schemas

COPY build-reqs.txt .

# Compile Python bindings
RUN apt update &&\
    apt install -y python3-pip &&\
    rm /usr/lib/python3.*/EXTERNALLY-MANAGED || true &&\
    pip install -r build-reqs.txt &&\
    cd languages/python &&\
    python3 setup.py develop &&\
    mv bitwarden_py.*.so bitwarden_py.so &&\
    rm -rf /var/lib/apt/lists/*

FROM python:3.12-slim-bookworm

ENV ORG_ID=
ENV SECRET_TTL=
ENV DEBUG=false

WORKDIR /app

COPY server/reqs.txt .

RUN pip install --no-cache-dir -r reqs.txt &&\
    mkdir bitwarden_sdk

COPY server/ .

COPY --from=builder /sdk/languages/python/bitwarden_py.so .
COPY --from=builder /sdk/languages/python/bitwarden_sdk bitwarden_sdk

EXPOSE 5000

ENTRYPOINT [ "python", "server.py" ]