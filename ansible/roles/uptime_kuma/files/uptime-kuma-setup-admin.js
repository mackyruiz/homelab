// Creates the first Uptime Kuma user from KUMA_USERNAME / KUMA_PASSWORD. Kuma
// has no env var or REST endpoint for it; only the socket.io `setup` event.
// Prints "changed" or "unchanged"; exits 3 while Kuma is not accepting connections.
const { io } = require("/app/node_modules/socket.io-client");

const username = process.env.KUMA_USERNAME;
const password = process.env.KUMA_PASSWORD;
if (!username || !password) throw new Error("KUMA_USERNAME and KUMA_PASSWORD must be set");

const notReady = () => {
  console.log("not-ready");
  process.exit(3);
};

const socket = io("http://127.0.0.1:3001", {
  transports: ["websocket"],
  reconnection: false,
  timeout: 10000,
});
setTimeout(notReady, 20000);

socket.on("connect_error", notReady);
socket.on("connect", () => {
  socket.emit("needSetup", (needSetup) => {
    if (!needSetup) {
      console.log("unchanged");
      process.exit(0);
    }
    socket.emit("setup", username, password, (res) => {
      if (res.ok) {
        console.log("changed");
        process.exit(0);
      }
      console.error(res.msg);
      process.exit(1);
    });
  });
});
