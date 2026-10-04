# Knife Arena çok oyunculu sunucusu (Render.com vb. ücretsiz Docker barındırma için).
# Godot'nun resmi Linux sürümünü indirir ve oyunun dışa aktarılmış paketini ekransız (headless)
# sunucu modunda çalıştırır. Port, barındırma servisinin verdiği PORT ortam değişkeninden okunur.
FROM debian:bookworm-slim

RUN apt-get update \
	&& apt-get install -y --no-install-recommends ca-certificates wget unzip libfontconfig1 \
	&& rm -rf /var/lib/apt/lists/*

WORKDIR /app
RUN wget -q https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip \
	&& unzip -q Godot_v4.7.2-stable_linux.x86_64.zip \
	&& mv Godot_v4.7.2-stable_linux.x86_64 godot \
	&& chmod +x godot \
	&& rm Godot_v4.7.2-stable_linux.x86_64.zip

COPY server/knife_arena.pck /app/knife_arena.pck

ENV PORT=9080
EXPOSE 9080
CMD ["./godot", "--headless", "--main-pack", "knife_arena.pck", "--", "--server"]
