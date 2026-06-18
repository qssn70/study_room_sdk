const members = [
  { name: "Lin", status: "focusing" },
  { name: "Maya", status: "focusing" },
  { name: "Chen", status: "online" },
  { name: "Ari", status: "idle" },
];

const messages = [
  { sender: "Maya", text: "Starting a 25 minute round." },
  { sender: "Chen", text: "I will join after reviewing notes." },
];

const state = {
  remainingSeconds: 25 * 60,
  running: false,
  connected: true,
  focusMinutes: 0,
  sessions: 0,
  intervalId: null,
};

const memberGrid = document.querySelector("#memberGrid");
const onlineCount = document.querySelector("#onlineCount");
const messagesEl = document.querySelector("#messages");
const chatForm = document.querySelector("#chatForm");
const messageInput = document.querySelector("#messageInput");
const timerDisplay = document.querySelector("#timerDisplay");
const timerState = document.querySelector("#timerState");
const focusMinutes = document.querySelector("#focusMinutes");
const sessionCount = document.querySelector("#sessionCount");
const chatCount = document.querySelector("#chatCount");
const connectionStatus = document.querySelector("#connectionStatus");
const startButton = document.querySelector("#startButton");
const pauseButton = document.querySelector("#pauseButton");
const resetButton = document.querySelector("#resetButton");
const toggleConnection = document.querySelector("#toggleConnection");

function renderMembers() {
  memberGrid.innerHTML = "";
  for (const member of members) {
    const card = document.createElement("article");
    card.className = "member-card";
    card.innerHTML = `
      <div class="avatar" aria-hidden="true">${member.name.charAt(0)}</div>
      <div class="member-name" title="${member.name}">${member.name}</div>
      <div class="member-status ${member.status}">${labelStatus(member.status)}</div>
    `;
    memberGrid.append(card);
  }
  onlineCount.textContent = `${members.length} online`;
}

function renderMessages() {
  messagesEl.innerHTML = "";
  for (const message of messages) {
    const row = document.createElement("article");
    row.className = message.sender === "You" ? "message mine" : "message";
    row.innerHTML = `
      <strong>${message.sender}</strong>
      <p>${message.text}</p>
    `;
    messagesEl.append(row);
  }
  messagesEl.scrollTop = messagesEl.scrollHeight;
  chatCount.textContent = String(messages.length);
}

function renderTimer() {
  const minutes = Math.floor(state.remainingSeconds / 60).toString().padStart(2, "0");
  const seconds = (state.remainingSeconds % 60).toString().padStart(2, "0");
  timerDisplay.textContent = `${minutes}:${seconds}`;
  timerState.textContent = state.running ? "Focusing" : "Ready";
  focusMinutes.textContent = String(state.focusMinutes);
  sessionCount.textContent = String(state.sessions);
  startButton.disabled = state.running;
  pauseButton.disabled = !state.running;
}

function renderConnection() {
  connectionStatus.classList.toggle("offline", !state.connected);
  connectionStatus.lastChild.textContent = state.connected ? " Connected" : " Reconnecting";
  toggleConnection.textContent = state.connected ? "Disconnect" : "Reconnect";
}

function labelStatus(status) {
  if (status === "focusing") return "Focusing";
  if (status === "idle") return "Idle";
  return "Online";
}

function startTimer() {
  if (state.running) return;
  state.running = true;
  state.sessions += 1;
  members[0].status = "focusing";
  state.intervalId = window.setInterval(() => {
    state.remainingSeconds -= 1;
    if (state.remainingSeconds % 60 === 0) {
      state.focusMinutes += 1;
    }
    if (state.remainingSeconds <= 0) {
      resetTimer(true);
      messages.push({ sender: "Room", text: "Focus round completed." });
      renderMessages();
    }
    renderTimer();
  }, 1000);
  renderMembers();
  renderTimer();
}

function pauseTimer() {
  state.running = false;
  window.clearInterval(state.intervalId);
  renderTimer();
}

function resetTimer(completed = false) {
  pauseTimer();
  state.remainingSeconds = 25 * 60;
  if (!completed && state.sessions > 0) {
    state.sessions -= 1;
  }
  renderTimer();
}

chatForm.addEventListener("submit", (event) => {
  event.preventDefault();
  const text = messageInput.value.trim();
  if (!text) return;
  messages.push({ sender: "You", text });
  messageInput.value = "";
  renderMessages();
});

startButton.addEventListener("click", startTimer);
pauseButton.addEventListener("click", pauseTimer);
resetButton.addEventListener("click", () => resetTimer(false));
toggleConnection.addEventListener("click", () => {
  state.connected = !state.connected;
  renderConnection();
});

renderMembers();
renderMessages();
renderTimer();
renderConnection();

