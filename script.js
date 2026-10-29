/**
 * Panel de administración de servidores dinámicos
 * Consume la API FastAPI del balanceador (GET /servidores, /solicitar, /estadisticas)
 * Los estados Activo/Inactivo vienen del health real de cada nodo.
 */

(() => {
  "use strict";

  const API_BASE =
    new URLSearchParams(window.location.search).get("api") ||
    localStorage.getItem("apiBase") ||
    "http://127.0.0.1:8000";

  const POLL_MS = 5000;

  const els = {
    apiPill: document.getElementById("api-pill"),
    apiLabel: document.getElementById("api-url-label"),
    apiConnLabel: document.getElementById("api-conn-label"),
    kpiSolicitudes: document.getElementById("kpi-solicitudes"),
    kpiServidores: document.getElementById("kpi-servidores"),
    kpiActivos: document.getElementById("kpi-activos"),
    tbody: document.getElementById("tbody-servidores"),
    tablaWrap: document.getElementById("tabla-servidores-wrap"),
    kpiGrid: document.getElementById("kpi-grid"),
    statsBars: document.getElementById("stats-bars"),
    statsTotal: document.getElementById("stats-total"),
    resultado: document.getElementById("resultado-solicitud"),
    resultadoTitulo: document.getElementById("resultado-titulo"),
    resultadoBody: document.getElementById("resultado-body"),
    resultadoIcon: document.getElementById("resultado-icon"),
    log: document.getElementById("log-mensajes"),
    footerClock: document.getElementById("footer-clock"),
    btnActualizar: document.getElementById("btn-actualizar"),
    btnProbar: document.getElementById("btn-probar-conexion"),
    btnSolicitar: document.getElementById("btn-solicitar"),
    btnSolicitarX5: document.getElementById("btn-solicitar-x5"),
    btnStats: document.getElementById("btn-stats"),
    btnLimpiar: document.getElementById("btn-limpiar-log"),
    btnMotion: document.getElementById("btn-toggle-motion"),
    light: document.getElementById("dynamic-light"),
    canvas: document.getElementById("particle-field"),
  };

  const state = {
    reducedMotion:
      localStorage.getItem("reducedMotion") === "true" ||
      window.matchMedia("(prefers-reduced-motion: reduce)").matches,
    busy: false,
    probing: false,
    /** @type {Map<string, string>} nombre → estado real ("Activo"|"Inactivo"|…) */
    servidoresEstado: new Map(),
    /** @type {object|null} último payload de /estadisticas */
    lastStats: null,
    /** @type {'unknown'|'ok'|'fail'|'probing'} */
    connection: "unknown",
    pollTimer: 0,
  };

  /* —— Helpers —— */

  function setLoading(nodes, on) {
    (Array.isArray(nodes) ? nodes : [nodes]).forEach((node) => {
      if (!node) return;
      node.classList.toggle("is-loading", Boolean(on));
    });
  }

  function isActivo(estado) {
    return String(estado || "").toLowerCase() === "activo";
  }

  function setConnection(status, label) {
    state.connection = status;
    if (els.apiPill) els.apiPill.dataset.conn = status;
    if (els.apiConnLabel) {
      els.apiConnLabel.textContent =
        label ||
        ({
          unknown: "sin probar",
          probing: "probando…",
          ok: "conectada",
          fail: "sin conexión",
        }[status] || status);
    }
  }

  function logMessage(text, type = "info") {
    const empty = els.log.querySelector(".log__empty");
    if (empty) empty.remove();

    const item = document.createElement("div");
    item.className = `log__item log__item--${type}`;
    const time = new Date().toLocaleTimeString("es-CO", { hour12: false });
    item.innerHTML = `<span class="log__time">${time}</span><span class="log__text"></span>`;
    item.querySelector(".log__text").textContent = text;
    els.log.prepend(item);

    while (els.log.children.length > 40) {
      els.log.removeChild(els.log.lastChild);
    }
  }

  function clearLog() {
    els.log.innerHTML =
      '<p class="log__empty">Los resultados, errores y avisos de conexión aparecerán aquí.</p>';
  }

  async function apiGet(path) {
    const url = `${API_BASE.replace(/\/$/, "")}${path}`;
    let response;
    try {
      response = await fetch(url, {
        method: "GET",
        headers: { Accept: "application/json" },
        cache: "no-store",
      });
    } catch (err) {
      const error = new Error(
        `La API no responde en ${url}. ¿Está el balanceador en ejecución?`
      );
      error.cause = err;
      error.kind = "network";
      throw error;
    }

    let data = null;
    const text = await response.text();
    try {
      data = text ? JSON.parse(text) : null;
    } catch {
      data = { raw: text };
    }

    if (!response.ok) {
      const detail =
        (data && (data.detail || data.message || data.mensaje)) ||
        `Error HTTP ${response.status}`;
      const error = new Error(String(detail));
      error.status = response.status;
      error.data = data;
      error.kind = "http";
      throw error;
    }
    return data;
  }

  function toneForServer(nombre) {
    const est = state.servidoresEstado.get(nombre);
    if (est === undefined) return "unknown";
    return isActivo(est) ? "ok" : "down";
  }

  function syncServidoresEstado(lista) {
    state.servidoresEstado.clear();
    for (const s of lista) {
      if (s && s.nombre) {
        state.servidoresEstado.set(String(s.nombre), String(s.estado || "Inactivo"));
      }
    }
  }

  /* —— Render —— */

  function renderServidores(payload) {
    const lista = (payload && payload.servidores) || [];
    syncServidoresEstado(lista);

    const activos = lista.filter((s) => isActivo(s.estado)).length;

    els.kpiServidores.textContent = String(
      payload.total_servidores ?? lista.length
    );
    els.kpiActivos.textContent = String(activos);

    if (!lista.length) {
      els.tbody.innerHTML =
        '<tr class="empty-row"><td colspan="4">No hay servidores registrados.</td></tr>';
      return;
    }

    els.tbody.innerHTML = lista
      .map((s) => {
        const activo = isActivo(s.estado);
        const cls = activo ? "status--activo" : "status--inactivo";
        const label = activo ? "Activo" : "Inactivo";
        const raw = String(s.estado || label);
        return `<tr data-estado="${escapeHtml(raw.toLowerCase())}">
          <td>${escapeHtml(s.nombre || "—")}</td>
          <td class="mono">${escapeHtml(String(s.puerto ?? "—"))}</td>
          <td class="url-cell">${escapeHtml(s.url || "—")}</td>
          <td><span class="status ${cls}" title="Estado según GET /health del nodo">${escapeHtml(label)}</span></td>
        </tr>`;
      })
      .join("");
  }

  /**
   * @param {object} payload
   * @param {{ flash?: 'ok'|'err'|null }} [opts]
   */
  function renderEstadisticas(payload, opts = {}) {
    const flash = opts.flash || null;
    const total = Number(payload.total_solicitudes || 0);
    const porServidor =
      payload.Solicitudes_por_servidor ||
      payload.solicitudes_por_servidor ||
      {};

    state.lastStats = payload;
    els.statsTotal.textContent = String(total);
    els.kpiSolicitudes.textContent = String(total);

    const entries = Object.entries(porServidor);
    if (!entries.length) {
      els.statsBars.innerHTML =
        '<p class="empty-hint">Sin estadísticas todavía. Envía una solicitud o prueba la conexión.</p>';
      applyBarsConnClass(flash === "err" ? "fail" : state.connection === "ok" ? "ok" : null);
      return;
    }

    const max = Math.max(...entries.map(([, n]) => Number(n) || 0), 1);
    els.statsBars.innerHTML = entries
      .map(([nombre, count]) => {
        const n = Number(count) || 0;
        const pct = Math.round((n / max) * 100);
        const tone = toneForServer(nombre);
        const flashCls =
          flash === "ok"
            ? "bar-fill--flash-ok"
            : flash === "err"
              ? "bar-fill--flash-err"
              : "";
        const statusLabel =
          tone === "ok" ? "Activo" : tone === "down" ? "Inactivo" : "Sin dato";
        const statusCls =
          tone === "ok" ? "is-ok" : tone === "down" ? "is-down" : "is-unknown";
        return `<div class="bar-row" role="listitem" data-server="${escapeHtml(nombre)}" data-tone="${tone}">
          <div class="bar-row__meta">
            <span>${escapeHtml(nombre)} <span class="bar-row__status ${statusCls}">${statusLabel}</span></span>
            <span>${n}</span>
          </div>
          <div class="bar-track" aria-hidden="true">
            <div class="bar-fill bar-fill--${tone} ${flashCls}" style="width:${pct}%"></div>
          </div>
        </div>`;
      })
      .join("");

    applyBarsConnClass(
      flash === "err" ? "fail" : flash === "ok" || state.connection === "ok" ? "ok" : null
    );

    if (flash && !state.reducedMotion) {
      window.setTimeout(() => {
        els.statsBars.querySelectorAll(".bar-fill--flash-ok, .bar-fill--flash-err").forEach((el) => {
          el.classList.remove("bar-fill--flash-ok", "bar-fill--flash-err");
        });
      }, 950);
    }
  }

  function applyBarsConnClass(kind) {
    els.statsBars.classList.remove("bars--conn-ok", "bars--conn-fail");
    if (kind === "ok") els.statsBars.classList.add("bars--conn-ok");
    if (kind === "fail") els.statsBars.classList.add("bars--conn-fail");
  }

  function mostrarResultado(ok, titulo, fields) {
    els.resultado.hidden = false;
    els.resultado.classList.toggle("is-error", !ok);
    els.resultadoTitulo.textContent = titulo;
    els.resultadoIcon.src = ok
      ? "desing_h/icons/check-circle.png"
      : "desing_h/icons/x-circle.png";
    els.resultadoBody.innerHTML = fields
      .map(
        ([k, v]) =>
          `<dt>${escapeHtml(k)}</dt><dd>${escapeHtml(String(v))}</dd>`
      )
      .join("");
  }

  function escapeHtml(str) {
    return String(str)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  /* —— Acciones API —— */

  async function actualizarServidores({ silent = false } = {}) {
    setLoading([els.tablaWrap, els.kpiGrid], true);
    try {
      const data = await apiGet("/servidores");
      renderServidores(data);
      setConnection("ok", "conectada");

      const activos = (data.servidores || []).filter((s) => isActivo(s.estado)).length;
      const total = data.total_servidores ?? data.servidores?.length ?? 0;

      if (!silent) {
        logMessage(
          `Estados reales: ${activos}/${total} activos (health de cada nodo vía balanceador).`,
          activos === total ? "ok" : activos === 0 ? "error" : "warn"
        );
      }

      if (state.lastStats) {
        renderEstadisticas(state.lastStats);
      }
      return data;
    } catch (err) {
      setConnection("fail", "sin conexión");
      state.servidoresEstado.clear();
      els.kpiActivos.textContent = "—";
      els.tbody.innerHTML = `<tr class="empty-row"><td colspan="4">${escapeHtml(err.message)}</td></tr>`;
      if (state.lastStats) {
        renderEstadisticas(state.lastStats, { flash: "err" });
      } else {
        applyBarsConnClass("fail");
      }
      if (!silent) logMessage(err.message, "error");
      throw err;
    } finally {
      setLoading([els.tablaWrap, els.kpiGrid], false);
    }
  }

  async function consultarEstadisticas({ silent = false, flash = null } = {}) {
    setLoading(els.statsBars, true);
    els.statsBars.classList.add("is-probing");
    try {
      const data = await apiGet("/estadisticas");
      renderEstadisticas(data, { flash });
      if (!silent) {
        logMessage(
          `Estadísticas: ${data.total_solicitudes || 0} solicitudes totales.`,
          "info"
        );
      }
      return data;
    } catch (err) {
      if (!silent) {
        logMessage(`No se pudieron consultar las estadísticas: ${err.message}`, "error");
      }
      els.statsBars.innerHTML = `<p class="empty-hint">${escapeHtml(err.message)}</p>`;
      applyBarsConnClass("fail");
      throw err;
    } finally {
      els.statsBars.classList.remove("is-probing");
      setLoading(els.statsBars, false);
    }
  }

  /** Prueba de conexión real: / → /servidores → /estadisticas */
  async function probarConexion() {
    if (state.probing) return;
    state.probing = true;
    if (els.btnProbar) els.btnProbar.disabled = true;
    setConnection("probing", "probando…");
    setLoading([els.tablaWrap, els.kpiGrid, els.statsBars], true);
    els.statsBars.classList.add("is-probing");
    logMessage(`Probando conexión real con ${API_BASE}…`, "info");

    try {
      const root = await apiGet("/");
      logMessage(
        `Balanceador OK: ${root.Sistema || root.mensaje || "API activa"} (${root.servidores_configurados ?? "?"} nodos).`,
        "ok"
      );

      await actualizarServidores({ silent: true });
      await consultarEstadisticas({ silent: true, flash: "ok" });

      const activos = [...state.servidoresEstado.values()].filter(isActivo).length;
      const total = state.servidoresEstado.size;
      setConnection("ok", `${activos}/${total} activos`);
      logMessage(
        `Prueba de conexión correcta. Barras coloreadas según health real (${activos} activos, ${total - activos} inactivos).`,
        "ok"
      );
    } catch (err) {
      setConnection("fail", "sin conexión");
      applyBarsConnClass("fail");
      if (state.lastStats) {
        renderEstadisticas(state.lastStats, { flash: "err" });
      }
      logMessage(`Prueba de conexión fallida: ${err.message}`, "error");
    } finally {
      els.statsBars.classList.remove("is-probing");
      setLoading([els.tablaWrap, els.kpiGrid, els.statsBars], false);
      state.probing = false;
      if (els.btnProbar) els.btnProbar.disabled = false;
    }
  }

  async function enviarSolicitud() {
    if (state.busy) return;
    state.busy = true;
    els.btnSolicitar.disabled = true;
    els.btnSolicitarX5.disabled = true;
    els.btnSolicitar.classList.add("is-busy");
    els.statsBars.classList.add("is-probing");

    try {
      const data = await apiGet("/solicitar");
      setConnection("ok", "conectada");
      mostrarResultado(true, "Solicitud atendida", [
        ["Servidor", data.servidor ?? "—"],
        ["Puerto", data.puerto ?? "—"],
        ["Contador", data.contador ?? "—"],
        ["Mensaje", data.mensaje ?? "—"],
        ["Resultado", data.resultado ?? "—"],
      ]);
      logMessage(
        `Solicitud atendida por ${data.servidor || "servidor"} (puerto ${data.puerto ?? "?"}).`,
        "ok"
      );
      await actualizarServidores({ silent: true });
      await consultarEstadisticas({ silent: true, flash: "ok" });
    } catch (err) {
      const msg =
        err.status === 503
          ? "No hay servidores disponibles."
          : err.message;
      if (err.kind === "network") setConnection("fail", "sin conexión");
      mostrarResultado(false, "Solicitud no procesada", [
        ["Error", msg],
        ["Código", err.status || "—"],
      ]);
      logMessage(msg, "error");
      try {
        await actualizarServidores({ silent: true });
        await consultarEstadisticas({ silent: true, flash: "err" });
      } catch {
        applyBarsConnClass("fail");
      }
    } finally {
      els.statsBars.classList.remove("is-probing");
      state.busy = false;
      els.btnSolicitar.disabled = false;
      els.btnSolicitarX5.disabled = false;
      els.btnSolicitar.classList.remove("is-busy");
    }
  }

  async function enviarCinco() {
    for (let i = 0; i < 5; i += 1) {
      await enviarSolicitud();
      await new Promise((r) => setTimeout(r, 120));
    }
  }

  /* —— Motion / lighting / particles —— */

  function applyMotionPreference() {
    document.documentElement.setAttribute(
      "data-reduced-motion",
      state.reducedMotion ? "true" : "false"
    );
    els.btnMotion.setAttribute("aria-pressed", String(!state.reducedMotion));
    els.btnMotion.title = state.reducedMotion
      ? "Activar animaciones"
      : "Desactivar animaciones";
    if (state.reducedMotion) {
      ParticleField.stop();
    } else {
      ParticleField.start();
    }
  }

  function toggleMotion() {
    state.reducedMotion = !state.reducedMotion;
    localStorage.setItem("reducedMotion", String(state.reducedMotion));
    applyMotionPreference();
    logMessage(
      state.reducedMotion ? "Animaciones desactivadas." : "Animaciones activadas.",
      "info"
    );
  }

  function bindDynamicLight() {
    const move = (event) => {
      if (state.reducedMotion || !els.light) return;
      const x = (event.clientX / window.innerWidth) * 100;
      const y = (event.clientY / window.innerHeight) * 100;
      document.documentElement.style.setProperty("--light-x", `${x}%`);
      document.documentElement.style.setProperty("--light-y", `${y}%`);
    };
    window.addEventListener("pointermove", move, { passive: true });
  }

  const ParticleField = (() => {
    let raf = 0;
    let particles = [];
    let ctx = null;
    let w = 0;
    let h = 0;
    let running = false;

    function resize() {
      if (!els.canvas) return;
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      w = window.innerWidth;
      h = window.innerHeight;
      els.canvas.width = Math.floor(w * dpr);
      els.canvas.height = Math.floor(h * dpr);
      els.canvas.style.width = `${w}px`;
      els.canvas.style.height = `${h}px`;
      ctx = els.canvas.getContext("2d");
      if (ctx) ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      seed();
    }

    function seed() {
      const density = Math.round((w * h) / 18000);
      const count = Math.max(28, Math.min(90, density));
      particles = Array.from({ length: count }, () => ({
        x: Math.random() * w,
        y: Math.random() * h,
        vx: (Math.random() - 0.5) * 0.35,
        vy: (Math.random() - 0.5) * 0.35,
        r: 1.2 + Math.random() * 2.2,
        phase: Math.random() * Math.PI * 2,
        speed: 0.01 + Math.random() * 0.025,
      }));
    }

    function frame(t) {
      if (!running || !ctx) return;
      ctx.clearRect(0, 0, w, h);
      ctx.globalCompositeOperation = "lighter";

      for (const p of particles) {
        p.vx += (Math.random() - 0.5) * 0.02;
        p.vy += (Math.random() - 0.5) * 0.02;
        p.vx *= 0.985;
        p.vy *= 0.985;
        p.x += p.vx;
        p.y += p.vy;
        if (p.x < -10) p.x = w + 10;
        if (p.x > w + 10) p.x = -10;
        if (p.y < -10) p.y = h + 10;
        if (p.y > h + 10) p.y = -10;

        const n = (Math.sin(t * 0.001 * 60 * p.speed + p.phase) + 1) / 2;
        const radius = p.r + n * 1.8;
        const alpha = 0.12 + n * 0.35;
        const g = ctx.createRadialGradient(p.x, p.y, 0, p.x, p.y, radius * 6);
        g.addColorStop(0, `rgba(45, 212, 191, ${0.18 * n})`);
        g.addColorStop(0.4, `rgba(56, 189, 248, ${0.08 * n})`);
        g.addColorStop(1, "rgba(0,0,0,0)");
        ctx.fillStyle = g;
        ctx.beginPath();
        ctx.arc(p.x, p.y, radius * 6, 0, Math.PI * 2);
        ctx.fill();

        ctx.beginPath();
        ctx.fillStyle = `rgba(180, 255, 235, ${alpha})`;
        ctx.arc(p.x, p.y, radius, 0, Math.PI * 2);
        ctx.fill();
      }

      raf = requestAnimationFrame(frame);
    }

    function start() {
      if (running || !els.canvas) return;
      running = true;
      resize();
      cancelAnimationFrame(raf);
      raf = requestAnimationFrame(frame);
    }

    function stop() {
      running = false;
      cancelAnimationFrame(raf);
      if (ctx) ctx.clearRect(0, 0, w, h);
    }

    window.addEventListener("resize", () => {
      if (running) resize();
    });

    return { start, stop };
  })();

  function tickClock() {
    if (!els.footerClock) return;
    els.footerClock.textContent = new Date().toLocaleString("es-CO", {
      hour12: false,
    });
  }

  function startPolling() {
    stopPolling();
    state.pollTimer = window.setInterval(async () => {
      if (state.busy || state.probing || document.hidden) return;
      try {
        await actualizarServidores({ silent: true });
        await consultarEstadisticas({ silent: true });
      } catch {
        /* ya se refleja en UI */
      }
    }, POLL_MS);
  }

  function stopPolling() {
    if (state.pollTimer) {
      clearInterval(state.pollTimer);
      state.pollTimer = 0;
    }
  }

  /* —— Init —— */

  function bindEvents() {
    els.btnActualizar.addEventListener("click", () =>
      actualizarServidores().catch(() => {})
    );
    if (els.btnProbar) {
      els.btnProbar.addEventListener("click", () => probarConexion());
    }
    els.btnSolicitar.addEventListener("click", () => enviarSolicitud());
    els.btnSolicitarX5.addEventListener("click", () => enviarCinco());
    els.btnStats.addEventListener("click", () =>
      consultarEstadisticas({ flash: "ok" }).catch(() => {})
    );
    els.btnLimpiar.addEventListener("click", clearLog);
    els.btnMotion.addEventListener("click", toggleMotion);
    document.addEventListener("visibilitychange", () => {
      if (!document.hidden) {
        actualizarServidores({ silent: true }).catch(() => {});
      }
    });
  }

  async function boot() {
    if (els.apiLabel) els.apiLabel.textContent = API_BASE;
    setConnection("unknown");
    bindEvents();
    bindDynamicLight();
    applyMotionPreference();
    tickClock();
    setInterval(tickClock, 1000);

    logMessage(`Conectando a la API FastAPI en ${API_BASE}`, "info");
    await probarConexion();
    startPolling();
  }

  document.addEventListener("DOMContentLoaded", boot);
  window.addEventListener("beforeunload", stopPolling);
})();
