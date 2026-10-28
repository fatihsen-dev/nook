"use strict";

const COPIED_FEEDBACK_MS = 1600;
const REVEAL_STAGGER_MS = 70;
const REVEAL_MAX_DELAY_MS = 280;
const NAV_SCROLL_OFFSET_PX = 8;
const CLOCK_TICK_MS = 1000;

const SWIFT_KEYWORDS = new Set([
  "import", "struct", "class", "enum", "var", "let", "some", "func", "in", "private",
  "return", "guard", "else", "for", "if", "switch", "case", "self", "true", "false", "nil",
]);

// Matches, in order: a line comment, a double-quoted string, an @attribute, a .member access, a number, an identifier, or any other single character.
const SWIFT_TOKEN = /(\/\/[^\n]*)|("(?:[^"\\\n]|\\.)*")|(@\w+)|(\.[a-z_]\w*)|(\b\d+(?:\.\d+)?\b)|(\b[A-Za-z_]\w*\b)|([\s\S])/g;

// Matches a double-quoted JSON string, optionally followed by spaces and a colon when it is an object key, or any other single character.
const JSON_TOKEN = /("(?:[^"\\\n]|\\.)*")(\s*:)?|([\s\S])/g;

const escapeHtml = (text) =>
  text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

const span = (className, text) => `<span class="${className}">${escapeHtml(text)}</span>`;

const classifySwiftToken = (match) => {
  const [token, comment, string, attribute, member, number, identifier] = match;
  if (comment) return span("token-comment", token);
  if (string) return span("token-string", token);
  if (attribute) return span("token-type", token);
  if (member) return span("token-member", token);
  if (number) return span("token-number", token);
  if (identifier && SWIFT_KEYWORDS.has(token)) return span("token-keyword", token);
  if (identifier && /^[A-Z]/.test(token)) return span("token-type", token);
  return escapeHtml(token);
};

const highlightSwift = (source) =>
  Array.from(source.matchAll(SWIFT_TOKEN), classifySwiftToken).join("");

const classifyJsonToken = ([token, string, keySuffix]) => {
  if (string && keySuffix) return span("token-type", string) + escapeHtml(keySuffix);
  if (string) return span("token-string", token);
  return escapeHtml(token);
};

const highlightJson = (source) =>
  Array.from(source.matchAll(JSON_TOKEN), classifyJsonToken).join("");

const highlightCode = () => {
  document.querySelectorAll("code[data-swift]").forEach((block) => {
    block.innerHTML = highlightSwift(block.textContent);
  });
  document.querySelectorAll("code[data-json]").forEach((block) => {
    block.innerHTML = highlightJson(block.textContent);
  });
};

const showCopied = (element) => {
  element.classList.add("is-copied");
  window.setTimeout(() => element.classList.remove("is-copied"), COPIED_FEEDBACK_MS);
};

const copyText = async (text, feedbackElement) => {
  try {
    await navigator.clipboard.writeText(text);
    showCopied(feedbackElement);
  } catch (error) {
    console.error(`Copying "${text.slice(0, 40)}" to the clipboard failed`, error);
  }
};

const setUpCopyButtons = () => {
  document.querySelectorAll("[data-copy-button]").forEach((button) => {
    const source = button.closest("[data-copy-source]");
    const text = source.querySelector("[data-copy-text]").textContent.trim();
    button.addEventListener("click", () => copyText(text, source));
  });
  document.querySelectorAll("[data-copy-code]").forEach((button) => {
    const code = button.closest("figure").querySelector("code");
    const label = button.lastChild;
    button.addEventListener("click", async () => {
      await copyText(code.textContent, button);
      label.textContent = "Copied";
      window.setTimeout(() => { label.textContent = "Copy"; }, COPIED_FEEDBACK_MS);
    });
  });
};

const setUpNavigation = () => {
  const nav = document.querySelector("[data-nav]");
  const menuButton = document.querySelector("[data-menu-button]");
  const updateScrolled = () => nav.classList.toggle("is-scrolled", window.scrollY > NAV_SCROLL_OFFSET_PX);
  const setOpen = (isOpen) => {
    nav.classList.toggle("is-open", isOpen);
    menuButton.setAttribute("aria-expanded", String(isOpen));
    menuButton.setAttribute("aria-label", isOpen ? "Close menu" : "Open menu");
  };
  updateScrolled();
  window.addEventListener("scroll", updateScrolled, { passive: true });
  menuButton.addEventListener("click", () => setOpen(!nav.classList.contains("is-open")));
  document.querySelectorAll("[data-nav-links] a").forEach((link) => {
    link.addEventListener("click", () => setOpen(false));
  });
};

const setUpReveal = () => {
  const elements = document.querySelectorAll(".reveal");
  const observer = new IntersectionObserver((entries) => {
    entries.filter((entry) => entry.isIntersecting).forEach((entry) => {
      entry.target.classList.add("is-visible");
      observer.unobserve(entry.target);
    });
  }, { rootMargin: "0px 0px -8% 0px" });
  elements.forEach((element) => {
    const siblings = Array.from(element.parentElement.children).filter((child) => child.classList.contains("reveal"));
    const delay = Math.min(siblings.indexOf(element) * REVEAL_STAGGER_MS, REVEAL_MAX_DELAY_MS);
    element.style.setProperty("--reveal-delay", `${delay}ms`);
    observer.observe(element);
  });
};

const setUpCardSpotlight = () => {
  document.querySelectorAll(".card").forEach((card) => {
    card.addEventListener("pointermove", (event) => {
      const bounds = card.getBoundingClientRect();
      card.style.setProperty("--spot-x", `${event.clientX - bounds.left}px`);
      card.style.setProperty("--spot-y", `${event.clientY - bounds.top}px`);
    });
  });
};

const selectRecipe = (name) => {
  document.querySelectorAll("[data-recipe]").forEach((tab) => {
    tab.setAttribute("aria-selected", String(tab.dataset.recipe === name));
  });
  document.querySelectorAll("[data-panel]").forEach((panel) => {
    const isActive = panel.dataset.panel === name;
    panel.hidden = !isActive;
    panel.classList.toggle("is-active", isActive);
  });
  document.querySelector("[data-recipe-select]").value = name;
};

const setUpRecipes = () => {
  document.querySelectorAll("[data-recipe]").forEach((tab) => {
    tab.addEventListener("click", () => selectRecipe(tab.dataset.recipe));
  });
  document.querySelector("[data-recipe-select]").addEventListener("change", (event) => selectRecipe(event.target.value));
};

const setUpClock = () => {
  const time = document.querySelector("[data-clock-time]");
  const date = document.querySelector("[data-clock-date]");
  const timeFormat = new Intl.DateTimeFormat(undefined, { hour: "2-digit", minute: "2-digit" });
  const dateFormat = new Intl.DateTimeFormat(undefined, { weekday: "long", day: "numeric", month: "long" });
  const render = () => {
    const now = new Date();
    time.textContent = timeFormat.format(now);
    time.dateTime = now.toISOString();
    date.textContent = dateFormat.format(now);
  };
  render();
  window.setInterval(render, CLOCK_TICK_MS);
};

highlightCode();
setUpCopyButtons();
setUpNavigation();
setUpReveal();
setUpCardSpotlight();
setUpRecipes();
setUpClock();
