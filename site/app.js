(function () {
  var cfg = window.DEBAGR_CONFIG || {};

  document.querySelectorAll("[data-config-text]").forEach(function (el) {
    var key = el.getAttribute("data-config-text");
    if (cfg[key]) {
      el.textContent = cfg[key];
    }
  });

  document.querySelectorAll("[data-config-href]").forEach(function (el) {
    var key = el.getAttribute("data-config-href");
    if (cfg[key]) {
      if (key === "supportEmail") {
        el.setAttribute("href", "mailto:" + cfg[key]);
      } else {
        el.setAttribute("href", cfg[key]);
      }
    }
  });

  document.querySelectorAll(".code-block").forEach(function (block) {
    var pre = block.querySelector("pre");
    if (!pre) return;
    var btn = document.createElement("button");
    btn.className = "copy-btn";
    btn.type = "button";
    btn.textContent = "Copy";
    btn.addEventListener("click", function () {
      var text = pre.innerText || pre.textContent || "";
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(function () {
          btn.textContent = "Copied";
          setTimeout(function () {
            btn.textContent = "Copy";
          }, 1500);
        });
      }
    });
    block.appendChild(btn);
  });

  document.querySelectorAll("[data-tab-group]").forEach(function (group) {
    var buttons = group.querySelectorAll(".tab-btn");
    var panels = group.querySelectorAll(".tab-panel");
    buttons.forEach(function (btn) {
      btn.addEventListener("click", function () {
        var target = btn.getAttribute("data-tab");
        buttons.forEach(function (b) {
          b.classList.toggle("active", b === btn);
        });
        panels.forEach(function (p) {
          p.classList.toggle("active", p.getAttribute("data-panel") === target);
        });
      });
    });
  });
})();
