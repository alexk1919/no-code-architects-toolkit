# Dockerfile

# 1. Base image
FROM python:3.9-slim

# 2. Install system dependencies, build tools, and libraries
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates wget tar xz-utils fonts-liberation fontconfig \
    build-essential yasm cmake meson ninja-build nasm \
    libssl-dev libvpx-dev libx264-dev libx265-dev libnuma-dev \
    libmp3lame-dev libopus-dev libvorbis-dev libtheora-dev \
    libspeex-dev libfreetype6-dev libfontconfig1-dev libgnutls28-dev \
    libaom-dev libdav1d-dev librav1e-dev libsvtav1-dev libzimg-dev \
    libwebp-dev git pkg-config autoconf automake libtool \
    libfribidi-dev libharfbuzz-dev python3-pip \
 && rm -rf /var/lib/apt/lists/*

# 3. Install SRT from source
RUN git clone https://github.com/Haivision/srt.git \
 && cd srt && mkdir build && cd build \
 && cmake .. && make -j$(nproc) && make install \
 && cd ../.. && rm -rf srt

# 4. Install SVT-AV1 from source
RUN git clone https://gitlab.com/AOMediaCodec/SVT-AV1.git \
 && cd SVT-AV1 && git checkout v0.9.0 && mkdir -p Build && cd Build \
 && cmake .. && make -j$(nproc) && make install \
 && cd ../.. && rm -rf SVT-AV1

# 5. Install libvmaf from source
RUN git clone https://github.com/Netflix/vmaf.git \
 && cd vmaf/libvmaf && meson build --buildtype release \
 && ninja -C build && ninja -C build install \
 && cd ../.. && rm -rf vmaf && ldconfig

# 6. Install fdk-aac from source
RUN git clone https://github.com/mstorsjo/fdk-aac.git \
 && cd fdk-aac && autoreconf -fiv && ./configure \
 && make -j$(nproc) && make install \
 && cd .. && rm -rf fdk-aac

# 7. Install libunibreak
RUN git clone https://github.com/adah1972/libunibreak.git \
 && cd libunibreak && ./autogen.sh && ./configure \
 && make -j$(nproc) && make install \
 && ldconfig && cd .. && rm -rf libunibreak

# 8. Build & install libass with unicode wrapping
RUN git clone https://github.com/libass/libass.git \
 && cd libass && autoreconf -i \
 && ./configure --enable-libunibreak \
 && make -j$(nproc) && make install \
 && cd .. && rm -rf libass

# 9. Build & install FFmpeg
RUN git clone https://git.ffmpeg.org/ffmpeg.git ffmpeg \
 && cd ffmpeg && git checkout n7.0.2 \
 && PKG_CONFIG_PATH="/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/local/lib/pkgconfig" \
    CFLAGS="-I/usr/include/freetype2" \
    LDFLAGS="-L/usr/lib/x86_64-linux-gnu" \
    ./configure --prefix=/usr/local \
      --enable-gpl --enable-pthreads --enable-neon \
      --enable-libaom --enable-libdav1d --enable-librav1e \
      --enable-libsvtav1 --enable-libvmaf --enable-libzimg \
      --enable-libx264 --enable-libx265 --enable-libvpx \
      --enable-libwebp --enable-libmp3lame --enable-libopus \
      --enable-libvorbis --enable-libtheora --enable-libspeex \
      --enable-libass --enable-libfreetype --enable-libharfbuzz \
      --enable-fontconfig --enable-libsrt --enable-filter=drawtext \
 && make -j$(nproc) && make install \
 && cd .. && rm -rf ffmpeg && ldconfig

# 10. Ensure custom fonts and cache
COPY ./fonts /usr/share/fonts/custom
RUN fc-cache -f -v

# 11. Set up Whisper cache and workdir
ENV WHISPER_CACHE_DIR="/app/whisper_cache"
WORKDIR /app
RUN mkdir -p ${WHISPER_CACHE_DIR}

# 12. Install Python dependencies
COPY requirements.txt .
RUN pip3 install --no-cache-dir --upgrade pip \
 && pip3 install --no-cache-dir -r requirements.txt \
 && pip3 install --no-cache-dir openai-whisper jsonschema

# 13. Create non-root user
RUN useradd -m appuser && chown appuser:appuser /app
USER appuser

# 14. (Optional) Preload Whisper model
RUN python3 -c "import whisper; whisper.load_model('base')"

# 15. Copy application code
COPY --chown=appuser:appuser . .

# 16. Make sure fonts dir exists at runtime
RUN mkdir -p /usr/share/fonts/custom

# 17. Expose the port Coolify healthchecks (3000)
EXPOSE 3000

# 18. Entrypoint script binding to $PORT (default 3000)
RUN printf '#!/usr/bin/env bash\n\
gunicorn \\
  --bind 0.0.0.0:${PORT:-3000} \\
  --workers ${GUNICORN_WORKERS:-4} \\
  --timeout ${GUNICORN_TIMEOUT:-30} \\
  app:app\n' > /app/run_gunicorn.sh \
 && chmod +x /app/run_gunicorn.sh

CMD ["/app/run_gunicorn.sh"]
