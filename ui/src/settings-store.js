"use strict";

const { app } = require("electron");
const fs = require("fs");
const path = require("path");

const DEFAULTS = {
  voice: "M1",
  lang: "auto",
  speed: 1.05,
  steps: 8,
  hotkey: "CommandOrControl+Shift+S",
  hotkeySecondary: "CommandOrControl+Shift+L",
  alwaysOnTop: true,
  captureAuto: false,
  theme: "dark",
  a11yProfile: "standard",
  windowMode: "compact",
  windowBounds: null,
};

let file = null;
let cache = { ...DEFAULTS };

function load() {
  file = path.join(app.getPath("userData"), "settings.json");
  try {
    const data = JSON.parse(fs.readFileSync(file, "utf8"));
    cache = { ...DEFAULTS, ...data };
  } catch {
    cache = { ...DEFAULTS };
  }
  return cache;
}

function save() {
  if (!file) return;
  const tmp = `${file}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(cache, null, 2));
  fs.renameSync(tmp, file);
}

module.exports = {
  load,
  all: () => ({ ...cache }),
  get: (key) => (key in cache ? cache[key] : DEFAULTS[key]),
  set: (key, value) => {
    cache[key] = value;
    save();
  },
  setMany: (patch) => {
    cache = { ...cache, ...patch };
    save();
  },
};
