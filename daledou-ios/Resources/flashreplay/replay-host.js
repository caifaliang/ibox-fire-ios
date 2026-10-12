(function () {
  'use strict';
  // Ruffle uses this document's DPR for both its backing canvas and pointer coordinates.
  // Cache the capped ratio so its per-frame reads do not force another layout.
  var nativeRatio = Object.getOwnPropertyDescriptor(window, 'devicePixelRatio');
  var standardScale = window.__daledouNativeReplay === true ? 1 : 1.5;
  var initialRatio = window.devicePixelRatio || 1, replayRatio = initialRatio, renderScale = standardScale, quality = 'standard';
  var qualityScales = { standard: standardScale, medium: 2, mediumHigh: 2.5, high: 3, ultraHigh: 4.5 };
  function updatePixelRatio() {
    var ratio = nativeRatio && nativeRatio.get ? nativeRatio.get.call(window) : initialRatio;
    var width = document.getElementById('canvas').clientWidth;
    replayRatio = Math.min(ratio || 1, renderScale, (640 * renderScale / 1.5) / Math.max(1, width));
  }
  updatePixelRatio();
  Object.defineProperty(window, 'devicePixelRatio', { configurable: true, get: function () { return replayRatio; } });
  window.addEventListener('resize', updatePixelRatio);

  var main, toolbar, payload, replayId, ready = false, sent = false, generation = 0;
  var sound = false, failed = false, desiredPaused = false, playbackSpeed = 1, playbackState = 'hostReady';
  var active = false, loaded = false, mainUrl = null, toolbarUrl = null, sessionToken = '';
  var sampleFrame = null, sampleStarted = null, frameCount = 0, slowWindows = 0, measuredFps = null;
  var connectionName = 'daledou_replay_' + Math.random().toString(36).slice(2);
  function canSampleFrames() {
    return main && playbackState === 'playing' && !desiredPaused && !document.hidden;
  }
  function resetFrameSampler() {
    if (sampleFrame !== null) window.cancelAnimationFrame(sampleFrame);
    sampleFrame = null; sampleStarted = null; frameCount = 0; slowWindows = 0; measuredFps = null;
    if (canSampleFrames()) sampleFrame = window.requestAnimationFrame(sampleFrames);
  }
  function sampleFrames(now) {
    sampleFrame = null;
    if (!canSampleFrames()) { resetFrameSampler(); return; }
    if (sampleStarted === null) sampleStarted = now;
    else {
      frameCount++;
      var elapsed = now - sampleStarted;
      if (elapsed >= 2000) {
        // RAF measures rendering-thread pressure, independently of the movie timeline.
        measuredFps = frameCount * 1000 / elapsed;
        slowWindows = measuredFps < 18 ? slowWindows + 1 : 0;
        if (quality === 'standard' && slowWindows >= 3) {
          if (renderScale > 1) { renderScale -= 0.25; updatePixelRatio(); }
          slowWindows = 0;
        }
        sampleStarted = now; frameCount = 0;
      }
    }
    sampleFrame = window.requestAnimationFrame(sampleFrames);
  }
  document.addEventListener('visibilitychange', function () {
    resetFrameSampler();
    if (document.hidden || !desiredPaused || !main) return;
    var expected = generation;
    // Ruffle restores its pre-background playing state in a later listener.
    setTimeout(function () {
      if (expected !== generation || !desiredPaused || !main) return;
      main.ruffle().suspend();
      if (toolbar) toolbar.ruffle().suspend();
    }, 0);
  });
  function notifyIOS(type, payload, status) {
    try {
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.ruffleEvent) {
        window.webkit.messageHandlers.ruffleEvent.postMessage({ type: type, payload: payload || {} });
      }
    } catch (_) {}
    try {
      if (status && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.ruffleStatus) {
        window.webkit.messageHandlers.ruffleStatus.postMessage(String(status));
      }
    } catch (_) {}
  }
  function state(name, message) {
    if (failed && name !== 'error') return;
    var changed = playbackState !== name;
    playbackState = name;
    if (changed) resetFrameSampler();
    if (window.FlashReplay) window.FlashReplay.onState(name, message || '', sessionToken);
    notifyIOS('state', { name: name, message: message || '' }, message || name);
  }
  function fail(message) {
    if (failed) return;
    failed = true;
    dispose();
    state('error', message || '动画播放器遇到兼容问题，已停止加载');
  }
  window.addEventListener('error', function (event) {
    if (/RuntimeError|unreachable|memory|WebAssembly/i.test(event.message || '') ||
        (event.error && event.error.name === 'RuntimeError')) fail();
  });
  window.addEventListener('unhandledrejection', function () { fail(); });
  function call(name) {
    if (!main) return;
    var args = Array.prototype.slice.call(arguments, 1);
    return main.ruffle().callExternalInterface.apply(main.ruffle(), [name].concat(args));
  }
  function dispatch() {
    if (!active || !main || !ready || !payload || sent || desiredPaused) return;
    sent = true;
    var expected = generation;
    // ExternalInterface calls must unwind before invoking Flash again.
    setTimeout(function () {
      if (expected !== generation || !main) return;
      if (desiredPaused) { sent = false; return; }
      try {
        state('preparing', '正在准备战斗动画');
        call('setFightReplayData', payload, replayId);
        if (!desiredPaused) {
          main.ruffle().resume();
          if (toolbar) toolbar.ruffle().resume();
        }
      } catch (_) {
        fail('动画启动失败，请重试');
      }
    }, 0);
  }
  window.FightReady = function () {
    ready = true;
    notifyIOS('fight_ready', {}, 'FightReady');
    dispatch();
  };
  window.FightComplete = function () { if (active) state('complete', '播放结束'); };
  window.getCookie = function (name) {
    // Use the binary URLLoader path: all requests go through the native interceptor.
    if (name === 'chrometag') return '0';
    if (name === 'voice') return '0';
    return null;
  };
  // Keep the movie's audio engine enabled; the app controls output volume.
  window.getVoice = function () { return 0; };
  window.setCookie = function () {};
  window.isqzone = function () { return '16'; };
  window.pgvSendClick = window.pgvSendPV = window.game_fcm = function () {};
  window.swfhand_Obj = {
    weaponpanel: function () { return connectionName; },
    weaponshow: function () { document.getElementById('weapons').style.display = 'block'; },
    weaponhide: function () { document.getElementById('weapons').style.display = 'none'; },
    CloseFlash: function () { if (active) state('playing', ''); },
    // The original initCompleteScreen invokes this before displaying the result.
    OpenFlash: window.FightComplete,
  };
  window.HF = { tower: window.FightComplete };
  window.getSwfInstance = function (name) { return name === 'weapon1' ? toolbar : main; };
  window.flashreload = function () { fail('动画资源加载失败，请重试'); };

  function createMovie(id, container, url) {
    var player = window.RufflePlayer.newest().createPlayer();
    player.setAttribute('id', id);
    player.setAttribute('name', id);
    player.style.width = '100%';
    player.style.height = '100%';
    document.getElementById(container).appendChild(player);
    // The bundled runtime exposes its own play overlay inside an open shadow root.
    // Keep it usable and synchronize its direct engine resume with our controls.
    var playButton = player.shadowRoot && player.shadowRoot.getElementById('play-button');
    if (playButton) playButton.addEventListener('click', function () {
      if (!active || (player !== main && player !== toolbar)) return;
      window.DaledouReplay.resume();
      if (window.FlashReplay && window.FlashReplay.onUserResume) window.FlashReplay.onUserResume(sessionToken);
    });
    var origin = location.origin;
    var isLocalIOS = origin.indexOf('127.0.0.1') >= 0;
    var rufflePublic = origin + (window.__daledouNativeReplay === true ? '/__daledou_pc__/'
      : (isLocalIOS ? '/flashreplay/ruffle/' : '/assets/flashreplay/ruffle/'));
    var options = {
      url: url,
      parameters: { a: 'replay' },
      // 饭店：movie URL 经 rewrite 后仍用 CDN 作 base。iOS 若 base=127.0.0.1/remote/…，
      // `//fightimg…/loadingSWC` 会解析错并 POST 死循环（138-fd4 日志）。
      base: 'https://fightimg.pet.qq.com/swf/gres/main/',
      autoplay: desiredPaused ? 'off' : 'on', unmuteOverlay: 'hidden', allowScriptAccess: true,
      publicPath: rufflePublic,
      // iOS 本机 http://127.0.0.1：upgradeToHttps 会把请求改成 https://127.0.0.1 → 失败
      upgradeToHttps: !isLocalIOS, splashScreen: false, contextMenu: 'off',
      showSwfDownload: false, openUrlMode: 'deny', logLevel: 'warn',
      // 饭店对照：wgpu-webgl。iOS 无 WebView intercept，不能直连 fightimg（CORS，见 fd8）。
      preferredRenderer: 'wgpu-webgl', quality: 'low',
      frameRate: 30,
      deviceFontRenderer: 'canvas',
      maxExecutionDuration: 60,
      backgroundColor: '#181412', letterbox: 'on', scale: 'showAll',
      // iOS：fightimg/fight → 同源 /remote/（剥前缀 + CWS→FWS）。Android 用 intercept，无需 rewrite。
      urlRewriteRules: window.__daledouNativeReplay === true ? [] : [
        [/^https?:\/\/(fightimg\.pet\.qq\.com|fight\.pet\.qq\.com|imgcache\.qq\.com|qzonestyle\.gtimg\.cn)(\/.*)$/, origin + '/remote/$1$2'],
      ],
    };
    player.ruffle().playbackRate = playbackSpeed;
    return { player: player, load: function () { return player.ruffle().load(options); } };
  }
  function dispose() {
    generation++;
    ready = false; sent = false; payload = null; active = false; loaded = false;
    replayId = null; mainUrl = toolbarUrl = null;
    if (main) main.remove();
    if (toolbar) toolbar.remove();
    main = toolbar = null;
    resetFrameSampler();
  }
  window.DaledouReplay = {
    getState: function () { return { state: playbackState, replayId: replayId, paused: desiredPaused, playbackSpeed: playbackSpeed, quality: quality, renderScale: replayRatio,
      fps: measuredFps === null ? null : Math.round(measuredFps * 10) / 10 }; },
    start: async function (options) {
      var reusable = main && ready && loaded && !failed && mainUrl === options.mainUrl && toolbarUrl === (options.toolbarUrl || null);
      if (reusable) { generation++; sent = false; payload = null; }
      else dispose();
      quality = Object.prototype.hasOwnProperty.call(qualityScales, options.quality) ? options.quality : 'standard';
      renderScale = qualityScales[quality]; updatePixelRatio();
      failed = false;
      active = true;
      sessionToken = options.sessionToken || '';
      desiredPaused = !!options.paused;
      var expected = generation;
      try {
        var parsed = JSON.parse(options.replayJson);
        if (String(parsed.result) !== '0' || typeof parsed.string !== 'string' || !parsed.string) {
          throw new Error('Invalid replay');
        }
        payload = parsed;
        replayId = options.replayId;
        if (reusable) {
          state('preparing', '正在准备战斗动画');
          main.ruffle().volume = sound ? 1 : 0;
          main.ruffle().playbackRate = playbackSpeed;
          // Replace the scene before the first resumed frame can show/play the old one.
          main.ruffle().suspend();
          if (toolbar) {
            toolbar.ruffle().volume = sound ? 1 : 0;
            toolbar.ruffle().playbackRate = playbackSpeed;
            toolbar.ruffle().suspend();
          }
          dispatch();
          return;
        }
        state('loading', '正在加载动画资源，首次加载需要一些时间');
        mainUrl = options.mainUrl; toolbarUrl = options.toolbarUrl || null;
        var movie = createMovie('PetFunFight', 'stage', options.mainUrl);
        main = movie.player;
        if (options.toolbarUrl) {
          var panel = createMovie('weapon1', 'weapons', options.toolbarUrl);
          toolbar = panel.player;
          panel.load().then(function () {
            if (expected !== generation) return;
            panel.player.ruffle().playbackRate = playbackSpeed;
            panel.player.ruffle().volume = sound ? 1 : 0;
            if (desiredPaused) panel.player.ruffle().suspend();
            else panel.player.ruffle().resume();
          }).catch(function () { /* Optional weapon details do not stop the battle. */ });
        }
        await movie.load();
        if (expected !== generation) return;
        loaded = true;
        movie.player.ruffle().playbackRate = playbackSpeed;
        movie.player.ruffle().volume = sound ? 1 : 0;
        if (desiredPaused) movie.player.ruffle().suspend();
        else movie.player.ruffle().resume();
        if (expected === generation) dispatch();
      } catch (_) {
        if (expected === generation) fail('动画播放器加载失败，请重试');
      }
    },
    park: function () {
      if (!main || !ready || !loaded || failed || !/^(playing|complete)$/.test(playbackState)) { dispose(); return false; }
      generation++; active = false; sent = false; payload = null; replayId = null; sessionToken = '';
      desiredPaused = true; playbackState = 'parked'; resetFrameSampler();
      main.ruffle().volume = 0; main.ruffle().suspend();
      if (toolbar) { toolbar.ruffle().volume = 0; toolbar.ruffle().suspend(); }
      return true;
    },
    replay: function () { sent = false; resetFrameSampler(); dispatch(); },
    pause: function () { desiredPaused = true; resetFrameSampler(); if (main) main.ruffle().suspend(); if (toolbar) toolbar.ruffle().suspend(); },
    resume: function () { if (!active) return; desiredPaused = false; resetFrameSampler(); if (main) main.ruffle().resume(); if (toolbar) toolbar.ruffle().resume(); dispatch(); },
    setSound: function (enabled) {
      sound = !!enabled;
      if (main) main.ruffle().volume = sound ? 1 : 0;
      if (toolbar) toolbar.ruffle().volume = sound ? 1 : 0;
    },
    setSpeed: function (rate) {
      if (typeof rate !== 'number' || !Number.isInteger(rate) || rate < 1 || rate > 4) return false;
      playbackSpeed = rate;
      if (main) main.ruffle().playbackRate = rate;
      if (toolbar) toolbar.ruffle().playbackRate = rate;
      return true;
    },
    // Change backing resolution in place. The SWF owns Stage.quality and may override
    // the initial Ruffle setting, so a load-only quality flag cannot implement this.
    setQuality: function (value) {
      if (!Object.prototype.hasOwnProperty.call(qualityScales, value)) return false;
      if (quality === value) return true;
      quality = value;
      renderScale = qualityScales[quality];
      updatePixelRatio(); resetFrameSampler();
      return true;
    },
    dispose: dispose,
    abort: fail,
  };
  /** iOS 原生入口：必须同步返回 bool。返回 Promise 会触发 WK「结果类型不受支持」→ 原生重试 → dispose 死循环（138-fd3）。 */
  var officialStartOnce = false;
  window.__startOfficialReplayB64 = function (b64, replayId) {
    if (officialStartOnce) return true;
    try {
      var bin = atob(String(b64 || ''));
      var bytes = new Uint8Array(bin.length);
      for (var i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
      var act = new TextDecoder('utf-8').decode(bytes);
      var replayJson = JSON.stringify({
        result: '0', msg: '', string: act, sn: '1', replayType: '0'
      });
      officialStartOnce = true;
      notifyIOS('boot', { swf: 'v10.19', via: 'flashreplay' }, 'flashreplay start');
      // fire-and-forget：不要 return Promise，否则 WK 报错并反复 restart
      // iOS：主 SWF 必须同源（fd8 直连 CDN → CORS Failed to fetch）。子资源靠 urlRewrite→/remote/。
      var iosLocal = location.origin.indexOf('127.0.0.1') >= 0;
      var mainSwf = iosLocal
        ? (location.origin + '/ruffle_fight/PetFunFight-v10.19.swf')
        : 'https://fightimg.pet.qq.com/swf/gres/main/PetFunFight-v10.19.swf';
      Promise.resolve().then(function () {
        return window.DaledouReplay.start({
          mainUrl: mainSwf,
          replayId: String(replayId || 'app_replay'),
          replayJson: replayJson,
          quality: 'standard',
          paused: false,
          sound: true,
          speed: 1
        });
      }).catch(function (e) {
        officialStartOnce = false;
        notifyIOS('boot_fail', { err: String(e) }, 'start fail: ' + e);
      });
      return true;
    } catch (e) {
      officialStartOnce = false;
      notifyIOS('boot_fail', { err: String(e) }, 'start fail: ' + e);
      return false;
    }
  };
  state('hostReady', '');
})();
