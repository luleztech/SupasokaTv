package com.ayubu.supasoka.player

/** JS bridges for quality / audio on PHP gateway pages (Shaka / hls.js). */
object GatewayPlaybackJs {

    /**
     * Soft host reCAPTCHA bypass for **hidden** extractors only.
     * Stubs `grecaptcha` so background extract can pull encryptedMpd without UI.
     * Never use this in the visible WebView — it hides the checkbox and leaves
     * users stuck on "verify you are not a robot".
     */
    fun silentRecaptchaBypassScript(): String = """
        (function(){
          if (window.__supasokaSilentCaptcha) {
            try { window.__supasokaHideCaptchaNodes && window.__supasokaHideCaptchaNodes(); } catch (e) {}
            return true;
          }
          window.__supasokaSilentCaptcha = true;
          var TOKEN = 'supasoka';
          function makeStub(){
            return {
              ready: function(cb){ try{ if (typeof cb === 'function') cb(); }catch(e){} },
              execute: function(){ return Promise.resolve(TOKEN); },
              getResponse: function(){ return TOKEN; },
              render: function(){ return 0; },
              reset: function(){},
              __supasokaSilent: true
            };
          }
          function stubApi(api){
            if (!api || typeof api !== 'object') return makeStub();
            if (api.__supasokaSilent) return api;
            try {
              api.execute = function(){ return Promise.resolve(TOKEN); };
              api.getResponse = function(){ return TOKEN; };
              api.ready = function(cb){ try{ if (typeof cb === 'function') cb(); }catch(e){} };
              if (typeof api.render !== 'function') api.render = function(){ return 0; };
              api.__supasokaSilent = true;
            } catch (e) {}
            return api;
          }
          try {
            var current = window.grecaptcha;
            Object.defineProperty(window, 'grecaptcha', {
              configurable: true,
              enumerable: true,
              get: function(){ return current || (current = makeStub()); },
              set: function(v){ current = stubApi(v); }
            });
            current = stubApi(current || makeStub());
          } catch (e) {
            try { window.grecaptcha = makeStub(); } catch (e2) {}
          }
          function hideCaptchaNodes(){
            try {
              var nodes = document.querySelectorAll(
                '.g-recaptcha,iframe[src*="recaptcha"],#recaptchadiv,.lsrecaptcha,[class*="g-recaptcha"],[id*="recaptcha"],.rc-anchor,[title*="reCAPTCHA"]'
              );
              for (var i = 0; i < nodes.length; i++) {
                try {
                  nodes[i].style.setProperty('display','none','important');
                  nodes[i].style.setProperty('visibility','hidden','important');
                  nodes[i].style.setProperty('pointer-events','none','important');
                  nodes[i].style.setProperty('opacity','0','important');
                  nodes[i].style.setProperty('height','0','important');
                  nodes[i].setAttribute('aria-hidden','true');
                } catch (e) {}
              }
            } catch (e) {}
          }
          window.__supasokaHideCaptchaNodes = hideCaptchaNodes;
          try {
            if (!document.getElementById('supasoka-hide-captcha')) {
              var s = document.createElement('style');
              s.id = 'supasoka-hide-captcha';
              s.textContent = [
                '.g-recaptcha,iframe[src*="recaptcha"],#recaptchadiv,.lsrecaptcha,[class*="g-recaptcha"],[id*="recaptcha"],.rc-anchor,[title*="reCAPTCHA"]{',
                'display:none!important;visibility:hidden!important;pointer-events:none!important;',
                'height:0!important;width:0!important;overflow:hidden!important;opacity:0!important}',
              ].join('');
              (document.documentElement || document.head || document.body).appendChild(s);
            }
            hideCaptchaNodes();
            if (!window.__supasokaCaptchaObserver && document.documentElement) {
              window.__supasokaCaptchaObserver = new MutationObserver(function(){ hideCaptchaNodes(); });
              window.__supasokaCaptchaObserver.observe(document.documentElement, { childList: true, subtree: true });
            }
          } catch (e) {}
          try {
            if (window.grecaptcha && typeof window.grecaptcha.execute === 'function') {
              var p = window.grecaptcha.execute();
              if (p && typeof p.then === 'function') p.then(function(){}).catch(function(){});
            }
          } catch (e) {}
          true;
        })();
    """.trimIndent()

    /**
     * Visible WebView unlock helper. Many PHP gateways call `grecaptcha.execute()`
     * even for `size=normal` checkboxes — that throws and never unlocks the player.
     * Patch execute to wait for a real [grecaptcha.getResponse] after the user ticks.
     * Never stubs or hides the widget.
     */
    fun checkboxRecaptchaUnlockScript(): String = """
        (function(){
          if (window.__supasokaSilentCaptcha) return false;
          if (window.__supasokaCaptchaFix) return true;
          window.__supasokaCaptchaFix = true;
          function readToken(){
            var token = '';
            try {
              if (window.grecaptcha && typeof grecaptcha.getResponse === 'function') {
                token = grecaptcha.getResponse() || '';
                if (!token) {
                  for (var i = 0; i < 8; i++) {
                    try { token = grecaptcha.getResponse(i) || ''; if (token) break; } catch (e) {}
                  }
                }
              }
            } catch (e) {}
            return token || '';
          }
          function patch(){
            try {
              if (!window.grecaptcha || typeof grecaptcha.execute !== 'function') return false;
              if (grecaptcha.__supasokaPatched) return true;
              var orig = grecaptcha.execute.bind(grecaptcha);
              grecaptcha.execute = function(siteKey, opts){
                try {
                  var el = document.querySelector('.g-recaptcha');
                  var size = (el && el.getAttribute('data-size')) || '';
                  if (size === 'invisible') return orig(siteKey, opts);
                  var existing = readToken();
                  if (existing) return Promise.resolve(existing);
                  return new Promise(function(resolve, reject){
                    var n = 0;
                    var t = setInterval(function(){
                      n++;
                      var token = readToken();
                      if (token) { clearInterval(t); resolve(token); }
                      else if (n > 360) { clearInterval(t); reject(new Error('captcha_timeout')); }
                    }, 500);
                  });
                } catch (e) {
                  return orig(siteKey, opts);
                }
              };
              grecaptcha.__supasokaPatched = true;
              return true;
            } catch (e) { return false; }
          }
          if (!patch()) {
            var iv = setInterval(function(){ if (patch()) clearInterval(iv); }, 400);
            setTimeout(function(){ clearInterval(iv); }, 45000);
          }
          true;
        })();
    """.trimIndent()

    /** Undo accidental captcha CSS hides so the checkbox is visible and tappable. */
    fun revealCaptchaScript(): String = """
        (function(){
          try {
            var hide = document.getElementById('supasoka-hide-captcha')
              || document.getElementById('__supasoka_hide_captcha');
            if (hide && hide.parentNode) hide.parentNode.removeChild(hide);
            try {
              if (window.__supasokaCaptchaObserver) {
                window.__supasokaCaptchaObserver.disconnect();
                window.__supasokaCaptchaObserver = null;
              }
            } catch (e) {}
            window.__supasokaHideCaptchaNodes = function(){};
            var nodes = document.querySelectorAll(
              '.g-recaptcha,iframe[src*="recaptcha"],#recaptchadiv,.lsrecaptcha,' +
              '[class*="g-recaptcha"],[id*="recaptcha"],.rc-anchor,[title*="reCAPTCHA"]'
            );
            for (var i = 0; i < nodes.length; i++) {
              try {
                nodes[i].style.removeProperty('display');
                nodes[i].style.removeProperty('visibility');
                nodes[i].style.removeProperty('pointer-events');
                nodes[i].style.removeProperty('opacity');
                nodes[i].style.removeProperty('height');
                nodes[i].style.removeProperty('width');
                nodes[i].style.removeProperty('overflow');
                nodes[i].removeAttribute('aria-hidden');
              } catch (e) {}
            }
          } catch (e) {}
          true;
        })();
    """.trimIndent()

    /**
     * Returns "playing" | "captcha" | "ok".
     * "captcha" only when a visible challenge blocks playback.
     */
    fun pageCaptchaStateScript(): String = """
        (function(){
          try {
            var v = document.querySelector('video');
            var playing = !!(v && !v.paused && !v.ended && v.readyState >= 2 &&
              (v.currentTime > 0.05 || v.readyState >= 3));
            if (playing) return 'playing';
            var token = '';
            try {
              if (window.grecaptcha && typeof grecaptcha.getResponse === 'function') {
                token = grecaptcha.getResponse() || '';
                if (!token) {
                  for (var i = 0; i < 8; i++) {
                    try { token = grecaptcha.getResponse(i) || ''; if (token) break; } catch (e) {}
                  }
                }
              }
            } catch (e) {}
            if (token && v && v.readyState >= 2) return 'ok';
            var text = ((document.body && (document.body.innerText || document.body.textContent)) || '').toLowerCase();
            var widget = document.querySelector(
              '.g-recaptcha,iframe[src*="recaptcha/anchor"],iframe[src*="recaptcha/bframe"],' +
              'iframe[src*="recaptcha.net"],#recaptchadiv,.lsrecaptcha,.rc-anchor'
            );
            var textBlock = text.indexOf('not a robot') !== -1
              || text.indexOf('verify you are') !== -1
              || text.indexOf("i'm not a robot") !== -1
              || text.indexOf('bot verification') !== -1;
            if (widget || textBlock) {
              if (v && v.readyState >= 2 && !v.paused) return 'ok';
              return 'captcha';
            }
            return 'ok';
          } catch (e) { return 'ok'; }
        })();
    """.trimIndent()

    /**
     * Capture Shaka / hls.js instances at construction time (leotena-style).
     * Gateway pages keep `new shaka.Player()` in a local var — retrospective
     * scanning of window globals always reports players:0.
     * Must run at document-start (and be re-armed on each navigation).
     */
    fun playerCaptureHookScript(): String = """
        (function(){
          if (!window.__supasokaShakas) window.__supasokaShakas = [];
          if (!window.__supasokaHls) window.__supasokaHls = [];
          function pushUnique(arr, inst) {
            if (!inst || !arr) return;
            for (var i = 0; i < arr.length; i++) { if (arr[i] === inst) return; }
            arr.push(inst);
          }
          function hookShaka() {
            if (!window.shaka || !window.shaka.Player || window.shaka.Player.__supasokaHooked) {
              return !!(window.shaka && window.shaka.Player && window.shaka.Player.__supasokaHooked);
            }
            try {
              var Orig = window.shaka.Player;
              var Wrapped = class extends Orig {
                constructor() {
                  super(...arguments);
                  window.__supasokaShaka = this;
                  pushUnique(window.__supasokaShakas, this);
                }
              };
              Object.keys(Orig).forEach(function(k) {
                try { Wrapped[k] = Orig[k]; } catch (e) {}
              });
              if (Orig.isBrowserSupported) {
                Wrapped.isBrowserSupported = function() { return Orig.isBrowserSupported(); };
              }
              Wrapped.__supasokaHooked = true;
              window.shaka.Player = Wrapped;
              return true;
            } catch (e1) {
              try {
                var old = window.shaka.Player;
                window.shaka.Player = function(mediaElement) {
                  var inst = (arguments.length > 0) ? new old(mediaElement) : new old();
                  window.__supasokaShaka = inst;
                  pushUnique(window.__supasokaShakas, inst);
                  return inst;
                };
                window.shaka.Player.prototype = old.prototype;
                if (old.isBrowserSupported) {
                  window.shaka.Player.isBrowserSupported = old.isBrowserSupported.bind(old);
                }
                window.shaka.Player.__supasokaHooked = true;
                return true;
              } catch (e2) { return false; }
            }
          }
          function hookHls() {
            var OrigH = window.Hls;
            if (!OrigH || typeof OrigH !== 'function' || OrigH.__supasokaHooked) {
              return !!(OrigH && OrigH.__supasokaHooked);
            }
            try {
              function WrappedHls(config) {
                var inst = (arguments.length > 0) ? new OrigH(config) : new OrigH();
                window.__supasokaHlsInst = inst;
                pushUnique(window.__supasokaHls, inst);
                return inst;
              }
              WrappedHls.prototype = OrigH.prototype;
              Object.keys(OrigH).forEach(function(k) {
                try { WrappedHls[k] = OrigH[k]; } catch (e) {}
              });
              if (typeof OrigH.isSupported === 'function') {
                WrappedHls.isSupported = function() { return OrigH.isSupported(); };
              }
              WrappedHls.__supasokaHooked = true;
              window.Hls = WrappedHls;
              return true;
            } catch (e) { return false; }
          }
          function tryHooks() {
            var a = hookShaka();
            var b = hookHls();
            return a || b;
          }
          tryHooks();
          if (!window.__supasokaPlayerHookTimer) {
            var tries = 0;
            window.__supasokaPlayerHookTimer = setInterval(function() {
              if (tryHooks() || ++tries > 100) {
                try { clearInterval(window.__supasokaPlayerHookTimer); } catch (e) {}
                window.__supasokaPlayerHookTimer = null;
              }
            }, 100);
          }
          true;
        })();
    """.trimIndent()

    /**
     * Force Widevine L3 / software robustness so HDCP-restricted video keys
     * (Shaka error 4012 RESTRICTIONS_CANNOT_BE_MET) can still decode on L3 devices.
     *
     * IMPORTANT: do NOT set player restrictions.maxHeight here — that sets
     * hasAppRestrictions=true and can block all variants (audio-only).
     */
    fun widevineL3FallbackScript(): String = """
        (function(){
          if (window.__supasokaDrmL3Installed) return true;
          window.__supasokaDrmL3Installed = true;
          function softDrmConfig() {
            return {
              drm: {
                advanced: {
                  'com.widevine.alpha': {
                    videoRobustness: 'SW_SECURE_CRYPTO',
                    audioRobustness: 'SW_SECURE_CRYPTO',
                    persistentStateRequired: false,
                    distinctiveIdentifierRequired: false
                  }
                }
              }
            };
          }
          function applyDrm(pl) {
            if (!pl || typeof pl.configure !== 'function') return false;
            try {
              // Clear any prior app restrictions that caused hasAppRestrictions=true.
              pl.configure({
                restrictions: {
                  minHeight: 0, maxHeight: Infinity,
                  minWidth: 0, maxWidth: Infinity,
                  minBandwidth: 0, maxBandwidth: Infinity
                }
              });
              pl.configure(softDrmConfig());
              return true;
            } catch (e) { return false; }
          }
          function patchConfigure(pl) {
            if (!pl || pl.__supasokaCfgPatched || typeof pl.configure !== 'function') return;
            var orig = pl.configure.bind(pl);
            pl.configure = function(config) {
              try {
                if (config && config.drm && config.drm.advanced &&
                    config.drm.advanced['com.widevine.alpha']) {
                  var adv = config.drm.advanced['com.widevine.alpha'];
                  adv.videoRobustness = 'SW_SECURE_CRYPTO';
                  adv.audioRobustness = 'SW_SECURE_CRYPTO';
                  adv.persistentStateRequired = false;
                  adv.distinctiveIdentifierRequired = false;
                }
                // Never keep a restrictive maxHeight from our earlier mistaken inject.
                if (config && config.restrictions && config.restrictions.maxHeight === 540) {
                  config.restrictions.maxHeight = Infinity;
                }
              } catch (e0) {}
              return orig(config);
            };
            pl.__supasokaCfgPatched = true;
          }
          function applyAll() {
            var list = window.__supasokaShakas || [];
            if (window.__supasokaShaka) list = list.concat([window.__supasokaShaka]);
            var ok = false;
            for (var i = 0; i < list.length; i++) {
              patchConfigure(list[i]);
              if (applyDrm(list[i])) ok = true;
            }
            try {
              if (window.player) { patchConfigure(window.player); if (applyDrm(window.player)) ok = true; }
              if (window.shakaPlayer) { patchConfigure(window.shakaPlayer); if (applyDrm(window.shakaPlayer)) ok = true; }
            } catch (e2) {}
            return ok;
          }
          applyAll();
          if (!window.__supasokaDrmL3Timer) {
            var tries = 0;
            window.__supasokaDrmL3Timer = setInterval(function() {
              if (applyAll() || ++tries > 60) {
                try { clearInterval(window.__supasokaDrmL3Timer); } catch (e) {}
                window.__supasokaDrmL3Timer = null;
              }
            }, 200);
          }
          window.__supasokaHandleDrm4012 = function() {
            applyAll();
            try {
              // Prefer lowest video variant without locking ABR forever at a dead height.
              var list = window.__supasokaShakas || [];
              if (window.__supasokaShaka) list = list.concat([window.__supasokaShaka]);
              for (var i = 0; i < list.length; i++) {
                var pl = list[i];
                if (!pl || typeof pl.getVariantTracks !== 'function') continue;
                var tracks = (pl.getVariantTracks() || []).filter(function(t) {
                  return t && (!t.type || t.type === 'variant') && t.height > 0;
                }).sort(function(a, b) { return (a.height || 0) - (b.height || 0); });
                if (tracks.length && typeof pl.selectVariantTrack === 'function') {
                  try { pl.selectVariantTrack(tracks[0], /* clearBuffer */ true); }
                  catch (eSel) { try { pl.selectVariantTrack(tracks[0], false); } catch (e2) {} }
                }
              }
            } catch (e3) {}
            return true;
          };
          true;
        })();
    """.trimIndent()

    /**
     * Read runtime configData / decrypted globals from the gateway page.
     * These pages store encrypted fields on an object, not as quoted HTML literals.
     */
    fun gatewayConfigDataExtractScript(): String = """
        (function(){
          function b64ToBytes(b64) {
            try {
              var bin = atob(String(b64 || '').replace(/\s+/g, ''));
              var out = new Uint8Array(bin.length);
              for (var i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
              return out;
            } catch (e) { return null; }
          }
          function xorDecrypt(enc, key) {
            if (!enc || !key) return '';
            var raw = b64ToBytes(enc);
            if (!raw || !raw.length) return '';
            var out = '';
            for (var i = 0; i < raw.length; i++) {
              out += String.fromCharCode(raw[i] ^ key.charCodeAt(i % key.length));
            }
            return out.replace(/^\s+|\s+$/g, '');
          }
          function pick(obj, names) {
            if (!obj) return '';
            for (var i = 0; i < names.length; i++) {
              var v = obj[names[i]];
              if (v != null && String(v).length) return String(v);
            }
            return '';
          }
          try {
            var cd = window.configData || window.__configData || window.playerConfig || null;
            var key = cd ? pick(cd, ['keyPart','xorKey','decryptKey','key']) : '';
            var encStream = cd ? pick(cd, [
              'encryptedPayload','encryptedMpd','encryptedStream','encryptedUrl',
              'encryptedHls','encryptedDash','encryptedManifest','payload','mpd'
            ]) : '';
            var encLic = cd ? pick(cd, [
              'licenseUrl','encryptedLicense','encryptedLicence','encryptedDrm',
              'encryptedWidevine','encryptedLicenseUrl','licUrl'
            ]) : '';
            var encTok = cd ? pick(cd, [
              'authToken','encryptedToken','encryptedAuth','encryptedAuthToken','token'
            ]) : '';
            var encKeys = cd ? pick(cd, ['keys','encryptedClearKey','encryptedClearKeys','clearKeys']) : '';
            var stream = '';
            var license = '';
            var token = '';
            var clearKey = '';
            if (key) {
              if (encStream) stream = xorDecrypt(encStream, key);
              if (encLic) license = xorDecrypt(encLic, key);
              if (encTok) token = xorDecrypt(encTok, key);
              if (encKeys) clearKey = xorDecrypt(encKeys, key);
            }
            // Prefer already-decrypted globals after page scripts run.
            if (!stream) {
              stream = pick(window, [
                'mpdUrl','manifestUrl','streamUrl','dashUrl','hlsUrl','playbackUrl'
              ]);
            }
            if (!license) {
              license = pick(window, ['licenseUrl','widevineLicense','drmLicense']);
              try {
                if (!license && window.player && window.player.getConfiguration) {
                  var cfg = window.player.getConfiguration();
                  if (cfg && cfg.drm && cfg.drm.servers && cfg.drm.servers['com.widevine.alpha']) {
                    license = String(cfg.drm.servers['com.widevine.alpha']);
                  }
                }
              } catch (e1) {}
            }
            if (!token) token = pick(window, ['authToken','token']);
            if ((!stream || stream.indexOf('http') !== 0) && !license) return '';
            return JSON.stringify({
              stream: stream || '',
              license: license || '',
              token: token || '',
              clearKey: clearKey || '',
              hasConfig: !!cd,
              keyLen: key ? key.length : 0
            });
          } catch (e) { return ''; }
        })();
    """.trimIndent()

    /** Keep forcing play on gateway pages until a video element is actually running. */
    fun forceAutoplayScript(): String = """
        (function(){
          function muteExtras(doc){
            try{
              var vids=doc.querySelectorAll('video');
              if(!vids||vids.length<=1)return;
              var primary=null,best=-1;
              for(var i=0;i<vids.length;i++){
                var v=vids[i];
                var score=(v.clientWidth||0)*(v.clientHeight||0);
                if(!v.paused&&!v.ended)score+=1e9;
                if(score>best){best=score;primary=v;}
              }
              for(var j=0;j<vids.length;j++){
                if(vids[j]===primary){try{vids[j].muted=false;}catch(e){}}
                else{try{vids[j].muted=true;vids[j].pause();}catch(e){}}
              }
            }catch(e){}
          }
          function playIn(doc){
            muteExtras(doc);
            try{
              var v=doc.querySelector('video');
              if(v){
                try{ v.muted=false; v.playsInline=true; v.setAttribute('playsinline',''); }catch(e){}
                if(v.paused && !v.ended){
                  var p=v.play();
                  if(p&&p.catch)p.catch(function(){});
                }
                return !!(v.readyState>=2 && !v.paused);
              }
            }catch(e){}
            return false;
          }
          var ok = playIn(document);
          try{
            var ifr=document.querySelectorAll('iframe');
            for(var i=0;i<ifr.length;i++){
              try{ if(ifr[i].contentDocument) ok = playIn(ifr[i].contentDocument) || ok; }catch(e){}
            }
          }catch(e){}
          return ok ? 'playing' : 'wait';
        })();
    """.trimIndent()

    fun eaMaxOkoaQualityApiScript(): String {
        return """
            (function() {
              if (window.__eaMaxOkoaQualityInstalled) return true;
              window.__eaMaxOkoaQualityInstalled = true;
              function parseTarget(mode) {
                if (!mode || mode === 'auto') return 0;
                var n = parseInt(mode, 10);
                return (isFinite(n) && n > 0) ? n : 0;
              }
              function pickLevel(levels, maxH) {
                if (!levels || !levels.length) return -1;
                if (maxH <= 0) return -1;
                var best = -1, bestHeight = 0, bestBw = -1;
                for (var i = 0; i < levels.length; i++) {
                  var L = levels[i];
                  var h = L.height || (L.resolution && L.resolution.height) || 0;
                  var bw = L.bitrate || L.bandwidth || 0;
                  if (h > 0 && h <= maxH && (h > bestHeight || (h === bestHeight && bw > bestBw))) {
                    best = i; bestHeight = h; bestBw = bw;
                  }
                }
                if (best >= 0) return best;
                var minI = 0, minH = (levels[0].height || 99999);
                for (var j = 1; j < levels.length; j++) {
                  var hj = levels[j].height || 99999;
                  if (hj < minH) { minH = hj; minI = j; }
                }
                return minI;
              }
              function widthForHeight(h) {
                if (h >= 1080) return 1920;
                if (h >= 720) return 1280;
                if (h >= 480) return 854;
                if (h >= 360) return 640;
                if (h >= 240) return 426;
                return 0;
              }
              function matchLang(trackLang, preferred) {
                var t = String(trackLang || '').toLowerCase();
                if (!t || !preferred) return true;
                if (preferred === 'en') {
                  return t === 'en' || t.indexOf('en-') === 0 || t === 'eng';
                }
                if (preferred === 'sw') {
                  return t === 'sw' || t.indexOf('sw-') === 0 || t === 'swa' ||
                    t.indexOf('swahili') >= 0 || t.indexOf('kiswahili') >= 0;
                }
                return t === preferred || t.indexOf(preferred + '-') === 0;
              }
              function collectShakaPlayers() {
                var out = [];
                var seen = [];
                function add(p) {
                  if (!p || typeof p.getVariantTracks !== 'function' ||
                      typeof p.selectVariantTrack !== 'function') return;
                  for (var s = 0; s < seen.length; s++) { if (seen[s] === p) return; }
                  seen.push(p);
                  out.push(p);
                }
                // Prefer constructor-captured instances (document-start hook).
                try {
                  var captured = window.__supasokaShakas || [];
                  for (var c = 0; c < captured.length; c++) add(captured[c]);
                  if (window.__supasokaShaka) add(window.__supasokaShaka);
                } catch (capErr) {}
                function scanDoc(doc) {
                  if (!doc) return;
                  try {
                    var win = doc.defaultView;
                    if (win) {
                      try {
                        var cap2 = win.__supasokaShakas || [];
                        for (var c2 = 0; c2 < cap2.length; c2++) add(cap2[c2]);
                        if (win.__supasokaShaka) add(win.__supasokaShaka);
                      } catch (eCap) {}
                      [win.shakaPlayer, win.player, win.shaka_player, win.splayer, win.tvPlayer].forEach(add);
                    }
                  } catch (e0) {}
                  try {
                    var vids = doc.querySelectorAll('video');
                    for (var i = 0; i < vids.length; i++) {
                      var v = vids[i];
                      try {
                        if (v['ui'] && v['ui'].getControls &&
                            typeof v['ui'].getControls === 'function') {
                          var controls = v['ui'].getControls();
                          if (controls && typeof controls.getPlayer === 'function') {
                            add(controls.getPlayer());
                          }
                        }
                      } catch (uiErr) {}
                      try {
                        var container = v.closest('.shaka-video-container') || v.parentElement;
                        if (container && container['ui'] &&
                            typeof container['ui'].getPlayer === 'function') {
                          add(container['ui'].getPlayer());
                        }
                      } catch (cErr) {}
                      // Some embeds stash the player on the media element.
                      try {
                        if (v.player) add(v.player);
                        if (v.shakaPlayer) add(v.shakaPlayer);
                        if (v.__shakaPlayer) add(v.__shakaPlayer);
                      } catch (vErr) {}
                    }
                  } catch (e1) {}
                  try {
                    var iframes = doc.querySelectorAll('iframe');
                    for (var j = 0; j < iframes.length; j++) {
                      try {
                        var idoc = iframes[j].contentDocument ||
                          (iframes[j].contentWindow && iframes[j].contentWindow.document);
                        if (idoc) scanDoc(idoc);
                      } catch (e2) {}
                    }
                  } catch (e3) {}
                }
                scanDoc(document);
                try {
                  for (var k in window) {
                    if (k === 'parent' || k === 'top' || k === 'frameElement') continue;
                    try {
                      var o = window[k];
                      if (o && typeof o === 'object' &&
                          typeof o.getVariantTracks === 'function' &&
                          typeof o.selectVariantTrack === 'function') add(o);
                    } catch (xe) {}
                  }
                } catch (e4) {}
                return out;
              }
              function variantTracksFor(pl) {
                return (pl.getVariantTracks() || []).filter(function(tr) {
                  return !tr.type || tr.type === 'variant';
                });
              }
              function pickBestVariant(tracks, maxH, prefLang) {
                var sorted = tracks.slice().sort(function(a, b) {
                  return (a.height || 0) - (b.height || 0);
                });
                var langBest = null, anyBest = null;
                for (var i = 0; i < sorted.length; i++) {
                  var tr = sorted[i];
                  var h = tr.height || 0;
                  if (h <= 0 || h > maxH) continue;
                  anyBest = tr;
                  if (!prefLang || matchLang(tr.language, prefLang)) langBest = tr;
                }
                return langBest || anyBest;
              }
              function allManifestHeights() {
                var seen = {}, out = [];
                collectShakaPlayers().forEach(function(pl) {
                  variantTracksFor(pl).forEach(function(tr) {
                    var h = tr.height || 0;
                    if (h > 0 && !seen[h]) { seen[h] = true; out.push(h); }
                  });
                });
                return out.sort(function(a, b) { return a - b; });
              }
              function targetHeightFor(maxH) {
                var pref = window.__eaMaxPreferredAudioLang || '';
                var best = 0;
                collectShakaPlayers().forEach(function(pl) {
                  var tr = pickBestVariant(variantTracksFor(pl), maxH, pref);
                  if (tr && tr.height > best) best = tr.height;
                });
                return best;
              }
              function qualityMet(maxH, activeH) {
                if (maxH <= 0) return true;
                if (activeH <= 0) return false;
                var target = targetHeightFor(maxH);
                if (target <= 0) {
                  var allH = allManifestHeights();
                  if (!allH.length) return false;
                  target = allH[allH.length - 1] < maxH ? allH[allH.length - 1] : maxH;
                }
                if (window.__eaMaxUserQualityLocked) {
                  return activeH >= target - 48 && activeH <= maxH + 48;
                }
                return activeH >= target - 48;
              }
              function tryHls(maxH) {
                var found = false;
                var switched = false;
                var tryOne = function(hls) {
                  if (!hls || !hls.levels || !hls.levels.length) return;
                  found = true;
                  if (maxH <= 0) {
                    if (hls.currentLevel !== -1) {
                      hls.currentLevel = -1;
                      switched = true;
                    } else {
                      switched = true;
                    }
                    try { hls.loadLevel = -1; } catch (eLoad) {}
                    try { hls.nextLevel = -1; } catch (eNext) {}
                    if (typeof hls.autoLevelEnabled !== 'undefined') hls.autoLevelEnabled = true;
                    return;
                  }
                  if (typeof hls.autoLevelEnabled !== 'undefined') hls.autoLevelEnabled = false;
                  var idx = pickLevel(hls.levels, maxH);
                  if (idx < 0) return;
                  if (hls.currentLevel === idx) {
                    switched = true;
                    return;
                  }
                  try { hls.nextLevel = idx; } catch (eN) {}
                  try { hls.loadLevel = idx; } catch (eL) {}
                  hls.currentLevel = idx;
                  switched = true;
                };
                try {
                  var captured = window.__supasokaHls || [];
                  for (var c = 0; c < captured.length; c++) tryOne(captured[c]);
                  if (window.__supasokaHlsInst) tryOne(window.__supasokaHlsInst);
                } catch (eCap) {}
                try { if (window.hls) tryOne(window.hls); } catch (e0) {}
                function scan(doc) {
                  if (!doc) return;
                  try {
                    var win = doc.defaultView;
                    if (win) {
                      try {
                        var cap2 = win.__supasokaHls || [];
                        for (var c2 = 0; c2 < cap2.length; c2++) tryOne(cap2[c2]);
                        if (win.__supasokaHlsInst) tryOne(win.__supasokaHlsInst);
                      } catch (eC) {}
                      if (win.hls) tryOne(win.hls);
                    }
                  } catch (eW) {}
                  try {
                    var vids = doc.querySelectorAll('video');
                    for (var i = 0; i < vids.length; i++) {
                      var v = vids[i];
                      if (v.hls) tryOne(v.hls);
                      if (v._hls) tryOne(v._hls);
                    }
                  } catch (e1) {}
                  try {
                    var iframes = doc.querySelectorAll('iframe');
                    for (var j = 0; j < iframes.length; j++) {
                      try {
                        var idoc = iframes[j].contentDocument ||
                          (iframes[j].contentWindow && iframes[j].contentWindow.document);
                        if (idoc) scan(idoc);
                      } catch (e2) {}
                    }
                  } catch (e3) {}
                }
                scan(document);
                return found && switched;
              }
              function tryShaka(maxH) {
                var candidates = collectShakaPlayers();
                if (!candidates.length) return false;
                var prefLang = window.__eaMaxPreferredAudioLang || '';
                var userLocked = !!window.__eaMaxUserQualityLocked;
                var applied = false;
                for (var i = 0; i < candidates.length; i++) {
                  var pl = candidates[i];
                  try {
                    if (maxH <= 0) {
                      pl.__eaMaxOkoaMaxH = 0;
                      pl.__eaMaxOkoaPinnedId = null;
                      pl.configure({
                        abr: { enabled: true },
                        restrictions: {
                          minHeight: 0, maxHeight: Infinity,
                          minWidth: 0, maxWidth: Infinity,
                          minBandwidth: 0, maxBandwidth: Infinity
                        }
                      });
                      applied = true;
                      continue;
                    }
                    var tracks = variantTracksFor(pl);
                    var best = pickBestVariant(tracks, maxH, prefLang);
                    // If nothing fits under maxH (common: DRM stream is 540p but startup asks 360),
                    // do NOT set restrictions.maxHeight — that triggers Shaka 4012 hasAppRestrictions
                    // and kills video while audio keeps playing.
                    if (!best) {
                      var sorted = tracks.slice().filter(function(tr) {
                        return (tr.height || 0) > 0;
                      }).sort(function(a, b) {
                        return (a.height || 0) - (b.height || 0);
                      });
                      if (!sorted.length) {
                        // Tracks not ready / DRM not unlocked yet — clear restrictions and wait.
                        pl.configure({
                          abr: { enabled: true },
                          restrictions: {
                            minHeight: 0, maxHeight: Infinity,
                            minWidth: 0, maxWidth: Infinity,
                            minBandwidth: 0, maxBandwidth: Infinity
                          }
                        });
                        continue;
                      }
                      best = sorted[0];
                      pl.configure({
                        abr: { enabled: false },
                        restrictions: {
                          minHeight: 0, maxHeight: Infinity,
                          minWidth: 0, maxWidth: Infinity,
                          maxBandwidth: Infinity
                        }
                      });
                    } else {
                      var maxW = widthForHeight(maxH);
                      pl.__eaMaxOkoaMaxH = maxH;
                      pl.configure({
                        abr: { enabled: false },
                        restrictions: {
                          minHeight: 0, maxHeight: Math.max(maxH, best.height || maxH),
                          minWidth: 0, maxWidth: maxW || Infinity,
                          maxBandwidth: Infinity
                        }
                      });
                    }
                    var already =
                      !!best.active ||
                      (pl.__eaMaxOkoaPinnedId != null && pl.__eaMaxOkoaPinnedId === best.id);
                    if (already) {
                      applied = true;
                    } else {
                      pl.selectVariantTrack(best, userLocked);
                      pl.__eaMaxOkoaPinnedId = best.id;
                      applied = true;
                    }
                    if (prefLang && typeof pl.selectAudioLanguage === 'function') {
                      var needAudio = true;
                      try {
                        if (best.language && matchLang(best.language, prefLang)) needAudio = false;
                      } catch (eLang) {}
                      if (needAudio) {
                        var langs = pl.getAudioLanguages() || [];
                        for (var j = 0; j < langs.length; j++) {
                          if (matchLang(langs[j], prefLang)) {
                            try { pl.selectAudioLanguage(langs[j], '', true); }
                            catch (eSel) { try { pl.selectAudioLanguage(langs[j]); } catch (e2) {} }
                            break;
                          }
                        }
                      }
                    }
                  } catch (e3) {}
                }
                return applied;
              }
              function activeVideoHeight() {
                try {
                  var tracks = [];
                  collectShakaPlayers().forEach(function(pl) {
                    variantTracksFor(pl).forEach(function(tr) {
                      if (tr.active && tr.height > 0) tracks.push(tr.height);
                    });
                  });
                  return tracks.length ? Math.max.apply(null, tracks) : 0;
                } catch (e) { return 0; }
              }
              function availableHeights(maxH) {
                var heights = [];
                collectShakaPlayers().forEach(function(pl) {
                  variantTracksFor(pl).forEach(function(tr) {
                    var h = tr.height || 0;
                    if (h > 0 && h <= maxH) heights.push(h);
                  });
                });
                return heights.sort(function(a, b) { return a - b; });
              }
              function applyOkoaQuality(mode) {
                var maxH = parseTarget(String(mode));
                if (window.__eaMaxPlaybackLocked &&
                    !window.__eaMaxUserQualityLocked &&
                    !window.__eaMaxOkoaUserInitiated &&
                    maxH !== 360) {
                  return false;
                }
                var hlsOk = tryHls(maxH);
                var shakaOk = tryShaka(maxH);
                var activeH = activeVideoHeight();
                var targetH = targetHeightFor(maxH);
                var manifestHeights = allManifestHeights();
                // Selection accepted counts as applied — do not wait for activeH or keep re-selecting.
                var applied = qualityMet(maxH, activeH) || hlsOk || shakaOk;
                try {
                  if (typeof ShakaPlayerBridge !== 'undefined' &&
                      ShakaPlayerBridge.onQualityProbe) {
                    ShakaPlayerBridge.onQualityProbe(JSON.stringify({
                      wanted: String(mode),
                      maxH: maxH,
                      targetH: targetH,
                      activeH: activeH,
                      heights: availableHeights(maxH || 9999),
                      manifestHeights: manifestHeights,
                      applied: applied,
                      userLocked: !!window.__eaMaxUserQualityLocked,
                      players: collectShakaPlayers().length,
                      captured: (window.__supasokaShakas || []).length,
                      hlsCaptured: (window.__supasokaHls || []).length,
                      hasShaka: !!(window.shaka && window.shaka.Player),
                      hasHls: typeof window.Hls === 'function',
                      videos: (document.querySelectorAll('video') || []).length
                    }));
                  }
                } catch (e) {}
                return applied;
              }
              window.__eaMaxOkoaApplyStartup360 = function() {
                if (window.__eaMaxUserQualityLocked || window.__eaMaxOkoaUserInitiated) return true;
                if (window.__eaMaxOkoaLastApplied === '360') return true;
                if (window.__eaMaxStartup360Active) return false;
                window.__eaMaxStartup360Active = true;
                var tries = 0;
                function attempt() {
                  if (window.__eaMaxOkoaUserInitiated) {
                    window.__eaMaxStartup360Active = false;
                    return;
                  }
                  if (applyOkoaQuality('360')) {
                    window.__eaMaxOkoaLastApplied = '360';
                    window.__eaMaxStartup360Active = false;
                    return;
                  }
                  if (++tries < 8) {
                    setTimeout(attempt, 700);
                  } else {
                    window.__eaMaxStartup360Active = false;
                  }
                }
                attempt();
                return true;
              };
              window.__eaMaxOkoaSetQuality = function(mode, userInitiated) {
                userInitiated = !!userInitiated;
                if (!userInitiated) {
                  if (window.__eaMaxUserQualityLocked) return true;
                  window.__eaMaxOkoaLastMode = String(mode);
                  return window.__eaMaxOkoaApplyStartup360();
                }
                window.__eaMaxUserQualityLocked = true;
                window.__eaMaxOkoaUserInitiated = true;
                var modeStr = String(mode);
                window.__eaMaxOkoaLastMode = modeStr;
                if (window.__eaMaxOkoaRetryId) {
                  try { clearInterval(window.__eaMaxOkoaRetryId); } catch (e) {}
                  window.__eaMaxOkoaRetryId = null;
                }
                if (applyOkoaQuality(modeStr)) {
                  window.__eaMaxOkoaLastApplied = modeStr;
                  return true;
                }
                // Players may not be ready yet — short, light retry only.
                var tries = 0;
                window.__eaMaxOkoaRetryId = setInterval(function() {
                  if (applyOkoaQuality(window.__eaMaxOkoaLastMode)) {
                    window.__eaMaxOkoaLastApplied = window.__eaMaxOkoaLastMode;
                    clearInterval(window.__eaMaxOkoaRetryId);
                    window.__eaMaxOkoaRetryId = null;
                  } else if (++tries >= 8) {
                    clearInterval(window.__eaMaxOkoaRetryId);
                    window.__eaMaxOkoaRetryId = null;
                  }
                }, 700);
                return true;
              };
              true;
            })();
        """.trimIndent()
    }

    fun eaMaxAudioLanguageApiScript(): String {
        return """
            (function(){
              if (window.__eaMaxAudioLangInstalled) return true;
              window.__eaMaxAudioLangInstalled = true;
              function normalizeLang(raw) {
                var r = String(raw || 'sw').toLowerCase();
                if (r.indexOf('en') === 0 || r === 'english' || r === 'eng') return 'en';
                return 'sw';
              }
              function matchLang(trackLang, preferred) {
                var t = String(trackLang || '').toLowerCase();
                if (!t) return false;
                if (preferred === 'en') {
                  return t === 'en' || t.indexOf('en-') === 0 || t === 'eng' || t === 'english';
                }
                if (preferred === 'sw') {
                  return t === 'sw' || t.indexOf('sw-') === 0 || t === 'swa' ||
                    t.indexOf('swahili') >= 0 || t.indexOf('kiswahili') >= 0 || t === 'ki';
                }
                return t === preferred || t.indexOf(preferred + '-') === 0;
              }
              function collectShakaPlayers() {
                var out = [], seen = [];
                function add(p) {
                  if (!p) return;
                  var canAudio = typeof p.selectAudioLanguage === 'function' ||
                    typeof p.getVariantTracks === 'function';
                  if (!canAudio) return;
                  for (var s = 0; s < seen.length; s++) { if (seen[s] === p) return; }
                  seen.push(p); out.push(p);
                }
                try {
                  var captured = window.__supasokaShakas || [];
                  for (var c = 0; c < captured.length; c++) add(captured[c]);
                  if (window.__supasokaShaka) add(window.__supasokaShaka);
                } catch (capErr) {}
                function scanDoc(doc) {
                  if (!doc) return;
                  try {
                    var win = doc.defaultView;
                    if (win) {
                      try {
                        var cap2 = win.__supasokaShakas || [];
                        for (var c2 = 0; c2 < cap2.length; c2++) add(cap2[c2]);
                        if (win.__supasokaShaka) add(win.__supasokaShaka);
                      } catch (eCap) {}
                      [win.shakaPlayer, win.player, win.shaka_player, win.splayer, win.tvPlayer].forEach(add);
                    }
                  } catch (e0) {}
                  try {
                    var vids = doc.querySelectorAll('video');
                    for (var i = 0; i < vids.length; i++) {
                      var v = vids[i];
                      try {
                        if (v['ui'] && v['ui'].getControls &&
                            typeof v['ui'].getControls === 'function') {
                          var controls = v['ui'].getControls();
                          if (controls && typeof controls.getPlayer === 'function') {
                            add(controls.getPlayer());
                          }
                        }
                      } catch (e2) {}
                      try {
                        var container = v.closest('.shaka-video-container') || v.parentElement;
                        if (container && container['ui'] &&
                            typeof container['ui'].getPlayer === 'function') {
                          add(container['ui'].getPlayer());
                        }
                      } catch (e3) {}
                      try {
                        if (v.player) add(v.player);
                        if (v.shakaPlayer) add(v.shakaPlayer);
                        if (v.__shakaPlayer) add(v.__shakaPlayer);
                      } catch (vErr) {}
                    }
                  } catch (e4) {}
                  try {
                    var iframes = doc.querySelectorAll('iframe');
                    for (var j = 0; j < iframes.length; j++) {
                      try {
                        var idoc = iframes[j].contentDocument ||
                          (iframes[j].contentWindow && iframes[j].contentWindow.document);
                        if (idoc) scanDoc(idoc);
                      } catch (e5) {}
                    }
                  } catch (e6) {}
                }
                scanDoc(document);
                try {
                  for (var k in window) {
                    if (k === 'parent' || k === 'top' || k === 'frameElement') continue;
                    try {
                      var o = window[k];
                      if (o && typeof o === 'object' &&
                          (typeof o.selectAudioLanguage === 'function' ||
                           typeof o.getVariantTracks === 'function')) add(o);
                    } catch (xe) {}
                  }
                } catch (e7) {}
                return out;
              }
              function muteSecondaryVideos() {
                try {
                  var vids = document.querySelectorAll('video');
                  if (!vids || vids.length <= 1) return;
                  var primary = null, best = -1;
                  for (var i = 0; i < vids.length; i++) {
                    var v = vids[i];
                    var score = (v.clientWidth || 0) * (v.clientHeight || 0);
                    if (!v.paused && !v.ended) score += 1000000000;
                    if (score > best) { best = score; primary = v; }
                  }
                  for (var j = 0; j < vids.length; j++) {
                    var vv = vids[j];
                    if (vv === primary) {
                      try { vv.muted = false; } catch (e0) {}
                    } else {
                      try { vv.muted = true; vv.pause(); } catch (e1) {}
                    }
                  }
                } catch (e) {}
              }
              function activeHlsAudioLang() {
                var found = '';
                function fromHls(hls) {
                  if (!hls || !hls.audioTracks || !hls.audioTracks.length) return;
                  var idx = hls.audioTrack;
                  if (idx == null || idx < 0) return;
                  var tr = hls.audioTracks[idx];
                  if (!tr) return;
                  found = normalizeLang(tr.lang || tr.name || tr.label || '');
                }
                function scan(doc) {
                  if (!doc || found) return;
                  try { if (doc.defaultView && doc.defaultView.hls) fromHls(doc.defaultView.hls); } catch (e0) {}
                  try {
                    var vids = doc.querySelectorAll('video');
                    for (var i = 0; i < vids.length; i++) {
                      if (vids[i].hls) fromHls(vids[i].hls);
                      if (vids[i]._hls) fromHls(vids[i]._hls);
                    }
                  } catch (e1) {}
                }
                scan(document);
                return found;
              }
              function activeAudioLang() {
                var hlsLang = activeHlsAudioLang();
                if (hlsLang) return hlsLang;
                var players = collectShakaPlayers();
                for (var i = 0; i < players.length; i++) {
                  var pl = players[i];
                  try {
                    if (typeof pl.getVariantTracks === 'function') {
                      var tracks = pl.getVariantTracks() || [];
                      for (var t = 0; t < tracks.length; t++) {
                        var tr = tracks[t];
                        if (tr.active && tr.language) return normalizeLang(tr.language);
                      }
                    }
                    // Demuxed DASH often has empty variant.language — trust configured preference
                    // after a successful selectAudioLanguage.
                    if (window.__eaMaxAudioLangApplied) {
                      return normalizeLang(window.__eaMaxAudioLangApplied);
                    }
                    if (typeof pl.getConfiguration === 'function') {
                      var cfg = pl.getConfiguration();
                      if (cfg && cfg.preferredAudioLanguage) {
                        return normalizeLang(cfg.preferredAudioLanguage);
                      }
                    }
                  } catch (e) {}
                }
                return window.__eaMaxAudioLangApplied
                  ? normalizeLang(window.__eaMaxAudioLangApplied)
                  : '';
              }
              function labelMatches(text, label) {
                if (label.length <= 3) {
                  var re = new RegExp('(^|[^a-z])' + label + '([^a-z]|$)');
                  return re.test(text);
                }
                return text.indexOf(label) >= 0;
              }
              function tryShaka(lang) {
                var players = collectShakaPlayers(), applied = false;
                // One primary player only — applying to every wrapper causes double audio.
                var list = players.length ? [players[0]] : [];
                for (var i = 0; i < list.length; i++) {
                  var pl = list[i];
                  try {
                    try {
                      pl.configure({ preferredAudioLanguage: lang });
                    } catch (eCfg) {}
                    if (typeof pl.getAudioLanguages === 'function') {
                      var langs = pl.getAudioLanguages() || [];
                      for (var j = 0; j < langs.length; j++) {
                        if (matchLang(langs[j], lang)) {
                          try { pl.selectAudioLanguage(langs[j], '', true); }
                          catch (eSel) { try { pl.selectAudioLanguage(langs[j]); } catch (e2) {} }
                          applied = true;
                          break;
                        }
                      }
                    }
                    if (!applied && typeof pl.getVariantTracks === 'function') {
                      var tracks = pl.getVariantTracks(), best = null, bestBw = 0;
                      for (var t = 0; t < tracks.length; t++) {
                        var tr = tracks[t];
                        if (matchLang(tr.language, lang) || matchLang(tr.label, lang)) {
                          var bw = tr.bandwidth || 0;
                          if (!best || bw > bestBw) { best = tr; bestBw = bw; }
                        }
                      }
                      if (best && typeof pl.selectVariantTrack === 'function') {
                        // clearBuffer on language switch avoids overlapping audio.
                        try { pl.selectVariantTrack(best, true); }
                        catch (eVar) { pl.selectVariantTrack(best, false); }
                        applied = true;
                      }
                    }
                  } catch (e1) {}
                }
                return applied;
              }
              function tryHls(lang) {
                var found = false;
                function tryOne(hls) {
                  if (!hls || !hls.audioTracks || !hls.audioTracks.length) return;
                  for (var i = 0; i < hls.audioTracks.length; i++) {
                    var tr = hls.audioTracks[i];
                    if (matchLang(tr.lang, lang) || matchLang(tr.name, lang) ||
                        matchLang(tr.label, lang)) {
                      hls.audioTrack = i;
                      found = true;
                      return;
                    }
                  }
                }
                function scanDoc(doc) {
                  if (!doc) return;
                  try { if (doc.defaultView && doc.defaultView.hls) tryOne(doc.defaultView.hls); } catch (e0) {}
                  try {
                    var vids = doc.querySelectorAll('video');
                    for (var i = 0; i < vids.length; i++) {
                      var v = vids[i];
                      if (v.hls) tryOne(v.hls);
                      if (v._hls) tryOne(v._hls);
                    }
                  } catch (e1) {}
                  try {
                    var iframes = doc.querySelectorAll('iframe');
                    for (var j = 0; j < iframes.length; j++) {
                      try {
                        var idoc = iframes[j].contentDocument ||
                          (iframes[j].contentWindow && iframes[j].contentWindow.document);
                        if (idoc) scanDoc(idoc);
                      } catch (e2) {}
                    }
                  } catch (e3) {}
                }
                scanDoc(document);
                return found;
              }
              function tryGatewayUiButtons(lang) {
                var labels = lang === 'en'
                  ? ['english', 'eng', 'english audio']
                  : ['swahili', 'kiswahili', 'swahili audio'];
                function scanDoc(doc) {
                  if (!doc) return false;
                  var nodes = doc.querySelectorAll('button,a,span,div,li,option');
                  for (var i = 0; i < nodes.length; i++) {
                    var t = String(nodes[i].textContent || nodes[i].value || '').toLowerCase();
                    for (var j = 0; j < labels.length; j++) {
                      if (labelMatches(t, labels[j])) {
                        try { nodes[i].click(); return true; } catch (e) {}
                      }
                    }
                  }
                  var iframes = doc.querySelectorAll('iframe');
                  for (var k = 0; k < iframes.length; k++) {
                    try {
                      var idoc = iframes[k].contentDocument ||
                        (iframes[k].contentWindow && iframes[k].contentWindow.document);
                      if (idoc && scanDoc(idoc)) return true;
                    } catch (e2) {}
                  }
                  return false;
                }
                return scanDoc(document);
              }
              function collectAudioProbe() {
                var probe = {players:0, shakaLangs:[], hlsLangs:[], variantLangs:[]};
                var players = collectShakaPlayers();
                probe.players = players.length;
                for (var i = 0; i < players.length; i++) {
                  var pl = players[i];
                  try {
                    if (typeof pl.getAudioLanguages === 'function') {
                      var langs = pl.getAudioLanguages() || [];
                      for (var j = 0; j < langs.length; j++) probe.shakaLangs.push(String(langs[j]));
                    }
                    if (typeof pl.getVariantTracks === 'function') {
                      var tracks = pl.getVariantTracks() || [];
                      for (var t = 0; t < tracks.length; t++) {
                        if (tracks[t].language) probe.variantLangs.push(String(tracks[t].language));
                      }
                    }
                  } catch (e) {}
                }
                function scanHls(doc) {
                  if (!doc) return;
                  try {
                    var hlsList = [];
                    if (doc.defaultView && doc.defaultView.hls) hlsList.push(doc.defaultView.hls);
                    var vids = doc.querySelectorAll('video');
                    for (var i = 0; i < vids.length; i++) {
                      if (vids[i].hls) hlsList.push(vids[i].hls);
                      if (vids[i]._hls) hlsList.push(vids[i]._hls);
                    }
                    for (var h = 0; h < hlsList.length; h++) {
                      var hls = hlsList[h];
                      if (!hls || !hls.audioTracks) continue;
                      for (var a = 0; a < hls.audioTracks.length; a++) {
                        var tr = hls.audioTracks[a];
                        probe.hlsLangs.push(String(tr.lang || tr.name || tr.label || a));
                      }
                    }
                  } catch (e) {}
                }
                scanHls(document);
                return probe;
              }
              function reportAudioProbe(wanted, applied) {
                try {
                  var probe = collectAudioProbe();
                  probe.wanted = wanted;
                  probe.applied = !!applied;
                  if (typeof ShakaPlayerBridge !== 'undefined' &&
                      ShakaPlayerBridge.onAudioLanguageProbe) {
                    ShakaPlayerBridge.onAudioLanguageProbe(JSON.stringify(probe));
                  }
                } catch (e) {}
              }
              function applyAudioLanguage(raw) {
                var lang = normalizeLang(raw);
                window.__eaMaxPreferredAudioLang = lang;
                // Never click UI language buttons after API select — that spawns a second
                // audio path (repeated / overlapping voices).
                var apiOk = tryShaka(lang) || tryHls(lang);
                var uiOk = false;
                if (!apiOk) {
                  uiOk = tryGatewayUiButtons(lang);
                }
                muteSecondaryVideos();
                if (apiOk || uiOk) {
                  window.__eaMaxAudioLangApplied = lang;
                }
                var active = activeAudioLang();
                var applied = apiOk || uiOk || matchLang(active, lang) ||
                  (window.__eaMaxAudioLangApplied && matchLang(window.__eaMaxAudioLangApplied, lang));
                reportAudioProbe(lang, applied);
                return !!applied;
              }
              window.__eaMaxSetAudioLanguage = function(lang) {
                if (applyAudioLanguage(lang)) return true;
                if (window.__eaMaxAudioLangRetryId) {
                  try { clearInterval(window.__eaMaxAudioLangRetryId); } catch (e) {}
                }
                var tries = 0;
                window.__eaMaxAudioLangRetryId = setInterval(function() {
                  if (applyAudioLanguage(window.__eaMaxPreferredAudioLang || lang)) {
                    clearInterval(window.__eaMaxAudioLangRetryId);
                    window.__eaMaxAudioLangRetryId = null;
                  } else if (++tries >= 8) {
                    clearInterval(window.__eaMaxAudioLangRetryId);
                    window.__eaMaxAudioLangRetryId = null;
                  }
                }, 800);
                return true;
              };
              if (!window.__eaMaxAudioGuardId) {
                window.__eaMaxAudioGuardId = setInterval(function() {
                  var lang = window.__eaMaxPreferredAudioLang;
                  if (!lang) return;
                  muteSecondaryVideos();
                  if (window.__eaMaxAudioLangApplied &&
                      matchLang(window.__eaMaxAudioLangApplied, lang)) return;
                  var active = activeAudioLang();
                  if (active && matchLang(active, lang)) {
                    window.__eaMaxAudioLangApplied = lang;
                    return;
                  }
                  if (active && !matchLang(active, lang)) {
                    tryShaka(lang);
                    tryHls(lang);
                    muteSecondaryVideos();
                  }
                }, 4000);
              }
              if (window.__eaMaxPreferredAudioLang) {
                try { window.__eaMaxSetAudioLanguage(window.__eaMaxPreferredAudioLang); } catch (e2) {}
              }
              true;
            })();
        """.trimIndent()
    }

}
