// Lê o que está tocando nesta aba (API Media Session + elemento de áudio/vídeo)
// e executa os comandos que o OpenNotch mandar.
(() => {
  const api = typeof browser !== "undefined" ? browser : chrome;

  // Botões de próxima/anterior de cada site, para quando não há outro jeito de pular faixa.
  const BUTTONS = {
    "music.youtube.com": { next: ".next-button", previous: ".previous-button" },
    "www.youtube.com": { next: ".ytp-next-button", previous: ".ytp-prev-button" },
    "open.spotify.com": {
      next: '[data-testid="control-button-skip-forward"]',
      previous: '[data-testid="control-button-skip-back"]',
    },
    "soundcloud.com": { next: ".skipControl__next", previous: ".skipControl__previous" },
  };

  const media = () => {
    const all = [...document.querySelectorAll("video, audio")];
    return all.find((m) => !m.paused && !m.ended) || all.find((m) => m.currentTime > 0) || all[0] || null;
  };

  const isPlaying = () => {
    const state = navigator.mediaSession && navigator.mediaSession.playbackState;
    if (state === "playing") return true;
    if (state === "paused") return false;
    const m = media();
    return !!m && !m.paused && !m.ended;
  };

  const snapshot = () => {
    const meta = navigator.mediaSession && navigator.mediaSession.metadata;
    const art = meta && meta.artwork && meta.artwork.length ? meta.artwork[meta.artwork.length - 1].src : "";
    return {
      site: location.hostname,
      title: (meta && meta.title) || document.title,
      artist: (meta && meta.artist) || "",
      album: (meta && meta.album) || "",
      artwork: art || "",
      playing: isPlaying(),
    };
  };

  const run = (command) => {
    const buttons = BUTTONS[location.hostname] || {};
    if (command === "playpause") {
      const m = media();
      if (m) m.paused ? m.play() : m.pause();
    } else if (buttons[command]) {
      const button = document.querySelector(buttons[command]);
      if (button) button.click();
    }
  };

  // Volume escolhido no OpenNotch para esta aba (0 a 1). Vale só para a página, não para o sistema.
  const applyVolume = (volume) => {
    for (const m of document.querySelectorAll("video, audio")) {
      if (Math.abs(m.volume - volume) > 0.005) m.volume = volume;
    }
  };

  let wasPlaying = false;
  const tick = () => {
    const state = snapshot();
    // Só fala com o app enquanto toca, e uma última vez ao pausar.
    if (!state.playing && !wasPlaying) return;
    wasPlaying = state.playing;
    try {
      api.runtime.sendMessage(state, (answer) => {
        if (api.runtime.lastError) return;
        if (answer && answer.command) run(answer.command);
        if (answer && typeof answer.volume === "number") applyVolume(Math.min(Math.max(answer.volume, 0), 1));
      });
    } catch (_) {
      // extensão recarregada: esta aba precisa ser recarregada também
    }
  };

  setInterval(tick, 1000);
})();
