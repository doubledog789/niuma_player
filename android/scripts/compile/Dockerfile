FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV NDK_HOME=/opt/ndk
ENV ANDROID_NDK=/opt/ndk
ENV PATH=/opt/ndk:${PATH}

RUN apt-get update && apt-get install -y --no-install-recommends \
      openjdk-17-jdk curl git unzip build-essential python3 yasm cmake pkg-config ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# NDK r26b (26.1.10909125) — matches VERSIONS.lock
RUN curl -fsSL -o /tmp/ndk.zip https://dl.google.com/android/repository/android-ndk-r26b-linux.zip \
    && unzip -q /tmp/ndk.zip -d /opt \
    && mv /opt/android-ndk-r26b /opt/ndk \
    && rm /tmp/ndk.zip

WORKDIR /workspace
CMD ["/bin/bash"]
