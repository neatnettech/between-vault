/* Theme switch. No dependency, no build step, no external request.
   Default is the operating system preference, which is what the design handoff
   asks for. An explicit choice wins and is remembered in this browser only.
   Loaded synchronously in <head> so a stored choice applies before first paint.

   The button is built here rather than repeated in every page: it does nothing
   without JavaScript, so there is no reason for it to sit in the markup.
   The icons the design specifies (promise strip, form errors) stay inline in the
   HTML instead, because those have to render with JavaScript off. */
(function () {
  var KEY = "betweenvault-theme";
  var SVG_NS = "http://www.w3.org/2000/svg";
  var root = document.documentElement;
  var system = window.matchMedia("(prefers-color-scheme: dark)");

  var stored = null;
  try { stored = localStorage.getItem(KEY); } catch (e) { /* private mode */ }
  if (stored === "light" || stored === "dark") {
    root.setAttribute("data-theme", stored);
  }

  var ICONS = {
    moon: [
      ["path", { d: "M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z" }]
    ],
    sun: [
      ["circle", { cx: "12", cy: "12", r: "4" }],
      ["path", { d: "M12 2v2M12 20v2M2 12h2M20 12h2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M19.1 4.9l-1.4 1.4M6.3 17.7l-1.4 1.4" }]
    ]
  };

  function shape(name, attrs) {
    var el = document.createElementNS(SVG_NS, name);
    Object.keys(attrs).forEach(function (key) { el.setAttribute(key, attrs[key]); });
    return el;
  }

  function icon(name) {
    var svg = shape("svg", {
      "class": name,
      width: "18",
      height: "18",
      viewBox: "0 0 24 24",
      fill: "none",
      stroke: "currentColor",
      "stroke-width": "1.8",
      "stroke-linecap": "round",
      "stroke-linejoin": "round",
      "aria-hidden": "true"
    });
    ICONS[name].forEach(function (part) { svg.appendChild(shape(part[0], part[1])); });
    return svg;
  }

  function active() {
    return root.getAttribute("data-theme") || (system.matches ? "dark" : "light");
  }

  document.addEventListener("DOMContentLoaded", function () {
    var nav = document.querySelector("header nav");
    if (!nav) { return; }

    var button = document.createElement("button");
    button.className = "theme-toggle";
    button.type = "button";
    button.appendChild(icon("moon"));
    button.appendChild(icon("sun"));

    function sync() {
      var label = "Switch to " + (active() === "dark" ? "light" : "dark") + " theme";
      button.setAttribute("aria-label", label);
      button.title = label;
    }

    button.addEventListener("click", function () {
      var next = active() === "dark" ? "light" : "dark";
      root.setAttribute("data-theme", next);
      try { localStorage.setItem(KEY, next); } catch (e) { /* private mode */ }
      sync();
    });

    // Keep the primary call to action last in the tab order
    nav.insertBefore(button, nav.querySelector(".nav-cta"));

    // Follow the system for as long as no explicit choice has been made
    system.addEventListener("change", sync);
    sync();
  });
})();
