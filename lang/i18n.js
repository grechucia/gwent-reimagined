/*
 * Gwint — silnik tłumaczeń (zmiana języka w locie, bez przeładowania strony i bez przerywania partii).
 *
 * Pliki językowe: lang/<kod>.js, każdy rejestruje się w window.GWENT_LANGS[<kod>] i ma tę samą strukturę
 * co lang/en.js (karty, umiejętności, frakcje, interfejs, akapity stron, wzorce). Logika gry dalej
 * operuje na angielskich nazwach z cards.js / abilities.js — tłumaczony jest wyłącznie tekst na ekranie,
 * okna alert/confirm/prompt i tytuł strony.
 *
 * API:  setLanguage("pl" | "en" | ...)   getLanguage()   GWENT_I18N.t("angielski tekst")
 */
(function () {
    "use strict";
    var LANGS = window.GWENT_LANGS || (window.GWENT_LANGS = {});
    var INLINE = { B: 1, I: 1, EM: 1, STRONG: 1, BR: 1, A: 1, SPAN: 1, CODE: 1, SMALL: 1, U: 1, SUP: 1, SUB: 1, FONT: 1 };
    var SKIP = { SCRIPT: 1, STYLE: 1, NOSCRIPT: 1, TEXTAREA: 1, SELECT: 1, svg: 1, CANVAS: 1, AUDIO: 1, VIDEO: 1 };
    var ATTRS = ["title", "placeholder", "alt", "aria-label"];

    var current = "en";
    var textMap = new Map();      // znormalizowany tekst EN -> tekst docelowy
    var blockMap = new Map();     // znormalizowany textContent akapitu EN -> HTML docelowy
    var patterns = [];            // [RegExp, szablon]

    var origText = new WeakMap(), written = new WeakMap();
    var origHTML = new WeakMap(), blockEls = new Set();
    var origAttr = new WeakMap();
    var observer = null, origTitle = null;

    function norm(s) { return String(s).replace(/\s+/g, " ").trim(); }
    function textOf(html) { var d = document.createElement("div"); d.innerHTML = html; return norm(d.textContent); }

    // ---- budowanie słowników z dwóch równoległych plików (en + docelowy) ----
    function pair(en, tg) {
        if (typeof en !== "string" || typeof tg !== "string") return;
        var k = norm(en);
        if (k && !textMap.has(k)) textMap.set(k, norm(tg));
    }
    function pairObj(en, tg) {
        if (!en || !tg) return;
        for (var id in en) {
            if (!(id in tg)) continue;
            var a = en[id], b = tg[id];
            if (typeof a === "string") pair(a, b);
            else if (a && typeof a === "object") for (var f in a) pair(a[f], b[f]);
        }
    }
    function build(code) {
        textMap = new Map(); blockMap = new Map(); patterns = [];
        var en = LANGS.en, tg = LANGS[code];
        if (!en || !tg || code === "en") return;
        pairObj(en.cards, tg.cards);
        pairObj(en.abilities, tg.abilities);
        pairObj(en.factions, tg.factions);
        if (tg.ui) for (var k in tg.ui) pair(k, tg.ui[k]);
        if (en.blocks && tg.blocks) for (var b in en.blocks) {
            if (tg.blocks[b]) blockMap.set(textOf(en.blocks[b]), tg.blocks[b]);
        }
        (tg.patterns || []).forEach(function (p) {
            try { patterns.push([new RegExp(p[0]), p[1]]); } catch (e) { console.warn("i18n: zły wzorzec", p[0]); }
        });
    }

    // ---- tłumaczenie pojedynczego tekstu ----
    function lookup(k) {
        if (textMap.has(k)) return textMap.get(k);
        var m = /^(.*?)(\s*[:.!?]\s*)$/.exec(k);            // "Leader Ability:" -> "Umiejętność dowódcy:"
        if (m && m[1] && textMap.has(m[1])) return textMap.get(m[1]) + m[2].trim();
        for (var i = 0; i < patterns.length; i++) {
            var r = patterns[i][0].exec(k);
            // {1} = grupa bez zmian, {t1} = grupa przetłumaczona, {l1} = lista "A / B" przetłumaczona element po elemencie
            if (r) return patterns[i][1].replace(/\{([tl]?)(\d)\}/g, function (_, t, n) {
                var g = r[+n] || "";
                if (t === "l") return g.split(" / ").map(function (x) { return lookup(norm(x)) || x; }).join(" / ");
                return t ? (lookup(norm(g)) || g) : g;
            });
        }
        return null;
    }
    function t(s) {
        if (current === "en" || s == null) return s;
        var k = norm(s);
        if (!k) return s;
        var r = lookup(k);
        if (r == null) return s;
        var lead = /^\s*/.exec(s)[0], trail = /\s*$/.exec(s)[0];
        return lead + r + trail;
    }
    function tMultiline(s) {
        if (current === "en" || typeof s !== "string") return s;
        var whole = t(s);
        if (whole !== s) return whole;
        return s.split("\n").map(t).join("\n");
    }

    // ---- dopasowanie napisów: tłumaczenie dłuższe niż oryginał nie może wylewać się z przycisku/pola ----
    var fitState = new WeakMap();     // element -> { fs: oryginalny inline font-size, ws, ta, w, h }
    var fitRO = null, fitPending = new Set(), fitRaf = 0, fitEls = new Set();
    function fitWatch(el) {
        if (!el || el.nodeType !== 1 || SKIP[el.tagName]) return;
        if (!window.ResizeObserver) return;
        if (!fitRO) fitRO = new ResizeObserver(function (entries) {
            entries.forEach(function (e) { fitPending.add(e.target); });
            scheduleFit();
        });
        if (!fitState.has(el)) {
            fitState.set(el, { fs: el.style.fontSize, ws: el.style.whiteSpace, ta: el.style.textAlign, w: -1, h: -1, done: false });
            fitRO.observe(el); fitEls.add(el);
        }
        fitPending.add(el); scheduleFit();
    }
    function scheduleFit() { if (!fitRaf) fitRaf = setTimeout(runFit, 16); }
    function refitAll() { fitEls.forEach(function (el) { if (el.isConnected) { var s = fitState.get(el); if (s) s.done = false; fitPending.add(el); } else fitEls.delete(el); }); scheduleFit(); }
    function overflows(el) { return el.scrollWidth > el.clientWidth + 1 || el.scrollHeight > el.clientHeight + 1; }
    function runFit() {
        fitRaf = 0;
        var els = Array.from(fitPending); fitPending.clear();
        for (var i = 0; i < els.length; i++) fitOne(els[i]);
        if (fitRO) fitRO.takeRecords && fitRO.takeRecords();
    }
    function fitOne(el) {
        var st = fitState.get(el);
        if (!st || !el.isConnected) return;
        var w = el.clientWidth, h = el.clientHeight;
        if (!w || !h) return;                                   // ukryty — dopasujemy, gdy się pokaże
        if (st.done && st.w === w && st.h === h && st.lang === current) return;
        // powrót do stylu oryginalnego
        el.style.fontSize = st.fs; el.style.whiteSpace = st.ws; el.style.textAlign = st.ta;
        st.done = true; st.w = w; st.h = h; st.lang = current;
        if (current === "en" || !overflows(el)) return;
        var txt = norm(el.textContent);
        if (txt.split(" ").length <= 4) el.style.whiteSpace = "nowrap";    // krótkie etykiety w jednej linii
        el.style.textAlign = "center";
        if (!overflows(el)) return;
        var base = parseFloat(getComputedStyle(el).fontSize) || 16, lo = base * 0.45, hi = base;
        for (var k = 0; k < 7; k++) {                          // wyszukiwanie binarne rozmiaru czcionki
            var mid = (lo + hi) / 2;
            el.style.fontSize = mid + "px";
            if (overflows(el)) hi = mid; else lo = mid;
        }
        el.style.fontSize = lo + "px";
        st.w = el.clientWidth; st.h = el.clientHeight;
    }
    function fitText(node) {
        var p = node.parentElement;
        // dopasowujemy najbliższy element o stałym rozmiarze (przycisk, pole); pomijamy inline (b, i, span)
        while (p && /^(B|I|EM|STRONG|U|SMALL|SPAN|A|FONT)$/.test(p.tagName) && getComputedStyle(p).display === "inline") p = p.parentElement;
        if (p && p !== document.body && (p.textContent || "").length < 120) fitWatch(p);
    }

    // ---- DOM ----
    function isInlineOnly(el) {
        var all = el.getElementsByTagName("*");
        for (var i = 0; i < all.length; i++) if (!INLINE[all[i].tagName]) return false;
        return true;
    }
    function doText(node) {
        var orig = origText.has(node) ? origText.get(node) : node.data;
        if (!origText.has(node)) {
            if (!/[A-Za-z]/.test(orig)) return;
            origText.set(node, orig);
        }
        var out = t(orig);
        if (node.data !== out) node.data = out;
        written.set(node, out);
        if (out !== orig || fitState.has(node.parentElement)) fitText(node);
    }
    function doAttrs(el) {
        var store = origAttr.get(el);
        for (var i = 0; i < ATTRS.length; i++) {
            var a = ATTRS[i];
            if (!el.hasAttribute(a) && !(store && a in store)) continue;
            if (!store) { store = {}; origAttr.set(el, store); }
            if (!(a in store)) store[a] = el.getAttribute(a);
            var v = t(store[a]);
            if (el.getAttribute(a) !== v) el.setAttribute(a, v);
        }
        if (el.tagName === "INPUT" && /^(button|submit|reset)$/i.test(el.type)) {
            if (!store) { store = {}; origAttr.set(el, store); }
            if (!("value" in store)) store.value = el.value;
            el.value = t(store.value);
        }
    }
    function doEl(el) {
        if (el.nodeType === 3) { doText(el); return; }
        if (el.nodeType !== 1 || SKIP[el.tagName]) return;
        if (el.hasAttribute && el.hasAttribute("data-no-i18n")) return;
        // cały akapit (zachowuje pogrubienia/odstępy w tłumaczeniu)
        if (blockMap.size && el.firstChild && !blockEls.has(el)) {
            var txt = el.textContent;
            if (txt.length < 6000) {
                var tr = blockMap.get(norm(txt));
                if (tr && isInlineOnly(el)) {
                    origHTML.set(el, el.innerHTML); blockEls.add(el);
                    el.innerHTML = tr; doAttrs(el); return;
                }
            }
        }
        doAttrs(el);
        for (var c = el.firstChild; c; c = c.nextSibling) doEl(c);
    }
    function refreshAll() {
        if (!document.body) return;
        // akapity podmienione wcześniej: przywróć oryginał, potem przetłumacz od nowa
        blockEls.forEach(function (el) {
            if (el.isConnected) el.innerHTML = origHTML.get(el);
            origHTML.delete(el);
        });
        blockEls.clear();
        doEl(document.body);
        if (origTitle == null) origTitle = document.title;
        document.title = t(origTitle);
        document.documentElement.lang = current;
        if (observer) observer.takeRecords();
    }

    var stats = { calls: 0, records: 0, ms: 0, maxMs: 0 };
    function onMutations(list) {
        var t0 = performance.now();
        onMutationsInner(list);
        var dt = performance.now() - t0;
        stats.calls++; stats.records += list.length; stats.ms += dt; if (dt > stats.maxMs) stats.maxMs = dt;
    }
    function onMutationsInner(list) {
        for (var i = 0; i < list.length; i++) {
            var m = list[i], n = m.target;
            if (m.type === "characterData") {
                if (n.data !== written.get(n)) { origText.delete(n); doText(n); }
            } else if (m.type === "attributes") {
                var st = origAttr.get(n);
                if (st && m.attributeName in st) {
                    var cur = n.getAttribute(m.attributeName);
                    if (cur !== t(st[m.attributeName])) { st[m.attributeName] = cur; doAttrs(n); }
                } else if (n.nodeType === 1) doAttrs(n);
            } else {
                // nowe węzły dodane przez grę: ich obecna treść jest oryginałem
                if (blockEls.has(n)) { blockEls.delete(n); origHTML.delete(n); }
                for (var j = 0; j < m.addedNodes.length; j++) {
                    var a = m.addedNodes[j];
                    if (a.nodeType === 3) { origText.delete(a); doText(a); }
                    else if (a.nodeType === 1) doEl(a);
                }
            }
        }
        if (observer) observer.takeRecords();
    }

    // teksty wstawiane przez CSS (content: "...", np. powiadomienia na planszy)
    function applyCss() {
        var st = document.getElementById("gwint-i18n-css");
        var css = (current !== "en" && LANGS[current] && LANGS[current].css) || {};
        var rules = Object.keys(css).map(function (sel) {
            return sel + "{content:\"" + String(css[sel]).replace(/"/g, '\\"') + "\" !important}";
        }).join("\n");
        if (!st) {
            if (!rules) return;
            st = document.createElement("style"); st.id = "gwint-i18n-css";
            (document.head || document.documentElement).appendChild(st);
        }
        st.textContent = rules;
    }

    function setLanguage(code) {
        if (!LANGS[code]) code = "en";
        current = code;
        try { localStorage.setItem("gwent_lang", code); } catch (e) {}
        build(code);
        applyCss();
        refreshAll();
        refitAll();
        try { window.dispatchEvent(new CustomEvent("languagechange-gwent", { detail: code })); } catch (e) {}
    }

    // okna systemowe (alert/confirm/prompt) — tłumaczone przed pokazaniem
    ["alert", "confirm", "prompt"].forEach(function (fn) {
        var orig = window[fn];
        if (!orig) return;
        window[fn] = function (msg) {
            var args = Array.prototype.slice.call(arguments);
            args[0] = tMultiline(msg);
            return orig.apply(window, args);
        };
    });

    function start() {
        var code = window.RN_LANG;
        if (!code) { try { code = localStorage.getItem("gwent_lang"); } catch (e) {} }
        if (!code) code = /^pl/i.test(navigator.language || "") ? "pl" : "en";
        current = LANGS[code] ? code : "en";
        build(current);
        applyCss();
        if (current !== "en") refreshAll();
        if (document.fonts && document.fonts.ready) document.fonts.ready.then(refitAll);
        window.addEventListener("load", refitAll);
        observer = new MutationObserver(onMutations);
        observer.observe(document.documentElement, { childList: true, subtree: true, characterData: true, attributes: true, attributeFilter: ATTRS.concat(["value"]) });
    }

    window.setLanguage = setLanguage;
    window.getLanguage = function () { return current; };
    window.GWENT_I18N = {
        t: t, setLanguage: setLanguage, stats: stats, refit: function () { refitAll(); },
        // pomoc przy tłumaczeniu: lista nieprzetłumaczonych tekstów widocznych na stronie
        missing: function () {
            var out = new Set(), w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
            for (var n; (n = w.nextNode());) {
                var p = n.parentNode; if (!p || SKIP[p.tagName]) continue;
                var inBlock = false;
                for (var q = p; q && !inBlock; q = q.parentNode) inBlock = blockEls.has(q);
                if (inBlock) continue;
                var s = norm(n.data); if (/[A-Za-z]{2}/.test(s) && t(s) === s && (origText.get(n) || n.data) === n.data) out.add(s);
            }
            return Array.from(out);
        },
        // pomoc przy tłumaczeniu: akapity strony (tekst + HTML) do pliku językowego
        blocks: function () {
            var res = [], seen = new Set();
            (function walk(el) {
                if (el.nodeType !== 1 || SKIP[el.tagName]) return;
                var txt = norm(el.textContent);
                if (txt && /[A-Za-z]{2}/.test(txt) && isInlineOnly(el) && !seen.has(txt)) {
                    seen.add(txt); res.push(norm(el.innerHTML)); return;
                }
                for (var c = el.firstElementChild; c; c = c.nextElementSibling) walk(c);
            })(document.body);
            return res;
        }
    };

    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start);
    else start();
})();
