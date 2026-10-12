// Ponte entre as abas de música e o app OpenNotch, que escuta só neste computador.
// As abas não falam direto com o app: mandam o estado para cá e recebem de volta
// o comando pendente (tocar/pausar, próxima, anterior), se houver.
const ENDPOINT = "http://127.0.0.1:38917/state";
const api = typeof browser !== "undefined" ? browser : chrome;

api.runtime.onMessage.addListener((state, sender, reply) => {
  fetch(ENDPOINT, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(state),
  })
    .then((response) => response.json())
    .then((answer) => reply(answer))
    .catch(() => reply({ command: null })); // app fechado: não faz nada
  return true; // a resposta chega depois
});
