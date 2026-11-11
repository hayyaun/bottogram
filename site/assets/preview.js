const commands = {
  start: {
    command: "/start",
    action: "Send HTML widget",
    detail: "Open task board",
    title: "Your task list is ready.",
    reply: "Add a task or view your current list.",
    option: "View tasks",
    next: "tasks",
  },
  tasks: {
    command: "/tasks",
    action: "Send HTML widget",
    detail: "Open task board",
    title: "Your tasks · 1 of 3 done",
    reply: "Review notes · Send draft · Plan tomorrow",
    option: "Add a task",
    next: "add",
  },
  add: {
    command: "/add Check the inbox",
    action: "Run SQLite query",
    detail: "Save the task",
    title: "Task added",
    reply: "Check the inbox",
    option: "View tasks",
    next: "tasks",
  },
};

const events = document.querySelectorAll("[data-command]");
const actionTitle = document.querySelector("#action-title");
const actionDetail = document.querySelector("#action-detail");
const chatCommand = document.querySelector("#chat-command");
const replyTitle = document.querySelector("#reply-title");
const replyDetail = document.querySelector("#reply-detail");
const replyOption = document.querySelector("#reply-option");
let selected = "start";

function showCommand(command) {
  const preview = commands[command];
  selected = command;

  for (const event of events) {
    event.setAttribute("aria-pressed", String(event.dataset.command === command));
  }

  actionTitle.textContent = preview.action;
  actionDetail.textContent = preview.detail;
  chatCommand.textContent = preview.command;
  replyTitle.textContent = preview.title;
  replyDetail.textContent = preview.reply;
  replyOption.textContent = preview.option;
}

for (const event of events) {
  event.addEventListener("click", () => showCommand(event.dataset.command));
}

replyOption.addEventListener("click", () => showCommand(commands[selected].next));
