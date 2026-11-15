/* 复刻运行层：把前端直连的第三方域名改写成本地 mock 后端，保证离线可跑通。
   原站前端是浏览器直连长安 iov / 高德，跨域且需要真实凭证；复刻版改为同源模拟。 */
(function () {
  'use strict';

  var HOST_MAP = [
    ['https://m.iov.changan.com.cn', '/mock/iov/m'],
    ['http://m.iov.changan.com.cn', '/mock/iov/m'],
    ['https://incallapi.changan.com.cn', '/mock/iov/incall'],
    ['https://open.iov.changan.com.cn', '/mock/iov/open'],
    ['https://dualstack-arestapi.amap.com', '/mock/amap'],
    ['https://restapi.amap.com', '/mock/amap'],
    ['https://webapi.amap.com', '/mock/amap']
  ];

  // 真实模式开关：浏览器控制台执行
  //   localStorage.setItem('replica_real_upstream','1')  然后刷新 → 不再改写到本地 mock，
  //   前端会直连长安 iov / 高德真实接口（需要真实账号凭证）
  //   localStorage.removeItem('replica_real_upstream')    → 回到本地模拟
  function realMode() {
    try { return localStorage.getItem('replica_real_upstream') === '1'; } catch (e) { return false; }
  }

  var REAL_MAP = [
    ['https://m.iov.changan.com.cn', '/real/iov/m'],
    ['https://incallapi.changan.com.cn', '/real/iov/incall'],
    ['https://open.iov.changan.com.cn', '/real/iov/open'],
    ['https://dualstack-arestapi.amap.com', '/real/amap'],
    ['https://restapi.amap.com', '/real/amap']
  ];

  function rewrite(u) {
    if (typeof u !== 'string') return null;
    if (realMode()) {
      // 真实模式：改走同源代理 /real/*，由服务端转发到长安官方接口
      for (var j = 0; j < REAL_MAP.length; j++) {
        if (u.indexOf(REAL_MAP[j][0]) === 0) return REAL_MAP[j][1] + u.slice(REAL_MAP[j][0].length);
      }
      return null;
    }
    for (var i = 0; i < HOST_MAP.length; i++) {
      if (u.indexOf(HOST_MAP[i][0]) === 0) {
        return HOST_MAP[i][1] + u.slice(HOST_MAP[i][0].length);
      }
    }
    return null;
  }

  // ---- fetch ----
  if (window.fetch) {
    var _fetch = window.fetch;
    window.fetch = function (input, init) {
      try {
        if (typeof input === 'string') {
          var n = rewrite(input);
          if (n) input = n;
        } else if (input && typeof input === 'object' && input.url) {
          var n2 = rewrite(input.url);
          if (n2) {
            var o = { method: input.method, headers: input.headers, body: input.body,
                      mode: input.mode, credentials: input.credentials, cache: input.cache };
            try { if (init && init.body !== undefined) o.body = init.body; } catch (e) {}
            input = n2;
            init = init || o;
          }
        }
      } catch (e) {}
      return _fetch.call(this, input, init);
    };
  }

  // ---- XMLHttpRequest ----
  var _open = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function (m, u) {
    var n = rewrite(u);
    var args = Array.prototype.slice.call(arguments);
    if (n) args[1] = n;
    return _open.apply(this, args);
  };

  // ---- 真实模式适配（不再显示任何「模拟」标识） ----
  document.addEventListener('DOMContentLoaded', function () {
    if (!realMode()) return;

    // 1) 从地址栏去掉敏感参数（手机号 / ref_token / pin）
    try {
      var qs = location.search || '';
      if (/[?&](ref_token|pin|phone)=/.test(qs)) {
        history.replaceState({}, '', location.pathname);
      }
    } catch (e) {}

    // 2) 车名：优先用真实车辆接口的返回值覆盖硬编码的「逸动PLUS」
    try {
      var cardName = localStorage.getItem('car_name') || '';
      var plate = localStorage.getItem('car_plate') || '';

      var applyName = function () {
        if (!cardName) return;
        var el = document.getElementById('carNameText');
        if (el && el.textContent !== cardName) el.textContent = cardName;
        var sub = document.getElementById('meModelSub');
        if (sub && sub.textContent !== cardName) sub.textContent = cardName;
        var img = document.getElementById('heroCarImg');
        if (img) {
          img.alt = '';
          if (img.complete && img.naturalWidth === 0) img.style.display = 'none';
          img.addEventListener('error', function () { this.style.display = 'none'; });
        }
        var pill = document.getElementById('openTokenStatus');
        if (pill) pill.style.display = 'none';
        document.title = cardName + ' · 远程控车';
      };

      window.__setCarName = function (name, pl) {
        if (!name) return;
        cardName = name;
        plate = pl || plate;
        try { localStorage.setItem('car_name', cardName); localStorage.setItem('car_plate', plate || ''); } catch (e) {}
        applyName();
      };

      // 拦截车辆接口响应，取真实 carName
      if (window.fetch) {
        var _of = window.fetch;
        window.fetch = function () {
          var p = _of.apply(this, arguments);
          try {
            var a = arguments[0];
            var u = typeof a === 'string' ? a : (a && a.url) || '';
            // 车门 / 车窗 / 锁闭状态
            if (u.indexOf('/car/data') >= 0 && u.indexOf('keys=') >= 0) {
              p.then(function (r) { return r.clone().json(); }).then(function (j) {
                var st = (j && j.data) || {};
                if (st.terminalTime) window.__terminalTime = st.terminalTime;
                window.__renderDoors && window.__renderDoors(st);
              }).catch(function () {});
            }

            // 控车结果确认：指令下发后 6 秒重查车况，对比状态变化
            if (u.indexOf('/control/execute') >= 0) {
              p.then(function (r) { return r.clone().json(); }).then(function (j) {
                if (!j || !j.success) return;
                setTimeout(function () {
                  try {
                    var cid = (document.getElementById('carIdInput') || {}).value || '';
                    var tk = (document.getElementById('tokenInput') || {}).value || '';
                    if (!cid || !tk) return;
                    var du = '/real/iov/m/app2/api/car/data?carId=' + encodeURIComponent(cid) +
                      '&ErrorAutoProjectile=false&toast=false&keys=*&isNev=0&token=' + encodeURIComponent(tk);
                    _of(du, { method: 'POST' }).then(function (rr) { return rr.json(); }).then(function (cd) {
                      var st = ((cd && cd.data) || {});
                      var parts = [];
                      if (st.leftFrontDoorLock !== undefined) parts.push(st.leftFrontDoorLock == 1 ? '车门已锁' : '车门未锁');
                      if (st.trunk !== undefined) parts.push(st.trunk == 0 ? '后备箱关闭' : '后备箱开启');
                      if (st.diverWindow !== undefined) parts.push(st.diverWindow == 0 ? '车窗关闭' : '车窗开启');
                      if (!parts.length) return;
                      var info = document.getElementById('responseInfo');
                      if (info) {
                        info.classList.remove('hidden');
                        info.textContent = '状态已同步：' + parts.join(' · ');
                      }
                    }).catch(function () {});
                  } catch (e) {}
                }, 6000);
              }).catch(function () {});
            }

            if (u.indexOf('/user/cars') >= 0) {
              p.then(function (r) { return r.clone().json(); }).then(function (j) {
                var row = (j && j.data && j.data[0]) || (j && j.data) || {};
                if (row && row.carName) {
                  // 按真实车型切换车图配置（seriesCode/车名 → CAR_MODELS 的键）
                  try {
                    var MAP = { 'UNI-V': 'univ', 'UNI-V 智电iDD': 'univ', 'UNI-K': 'univ_k',
                                'CS75PLUS': 'cs75', 'CS75 PLUS': 'cs75', 'CS75': 'cs75_20',
                                '逸动PLUS': 'yidong', '逸动': 'yidong' };
                    var mk = MAP[row.carName] || (String(row.seriesCode || '').toUpperCase() === 'C281' ? 'univ' : '');
                    if (mk && window.CAR_MODELS && window.CAR_MODELS[mk]) {
                      try { localStorage.setItem('car_model', mk); } catch (e) {}
                      var _m = window.CAR_MODELS[mk];
                      var hi = document.getElementById('heroCarImg');
                      if (hi) hi.src = _m.img;
                      var ti = document.getElementById('topCarImg');
                      if (ti) ti.src = _m.topImg;
                      // 非逸动车型没有 3D 模型，隐藏 3D 切换
                      if (mk !== 'yidong' && mk !== 'yidong_white') {
                        var b3 = document.getElementById('cvsSeg3d');
                        if (b3) b3.style.display = 'none';
                      }
                    }
                  } catch (e) {}
                  window.__setCarName(row.carName, row.plateNumber || '');
                }
              }).catch(function () {});
            }
          } catch (e) {}
          return p;
        };
      }

      if (cardName) {
        applyName();
        var n = 0, t = setInterval(function () { applyName(); if (++n > 20) clearInterval(t); }, 500);
      }

      // 白色背景：去掉水墨花纹与花瓣装饰
      try {
        var st = document.createElement('style');
        st.textContent = [
          'html,html.glass{background:#fff!important}',
          'html.glass.myth-qinglong,html.glass.myth-zhuque,html.glass.myth-xuanwu,html.glass.myth-baihu,html.glass.myth-qilin{background:#fff!important}',
          'body{background:#fff!important;background-image:none!important}',
          'body::before,body::after{display:none!important;content:none!important}',
          '.card-snow,.card-snow i,body .card-snow i{display:none!important;background-image:none!important}',
          '.car-stage::before,.car-stage::after{display:none!important;content:none!important}',
          'nav.tabbar::before,nav.tabbar::after{display:none!important;content:none!important}',
          '.myth-card::before,.myth-card::after{opacity:0!important}',
          '#tabItem2{display:none!important}',
          '#ctrlCard .seg{display:none!important}',
          'html{background:#eef1f5!important}',
          'body{max-width:430px!important;margin:0 auto!important;box-shadow:0 0 24px rgba(0,0,0,.07);position:relative}',
          'nav.tabbar{width:100%!important;max-width:430px!important;left:50%!important;right:auto!important;transform:translateX(-50%)!important}',
          '#extraMeta{display:block!important;width:100%!important;flex-basis:100%!important}',
          '#fuelPage::before,#fuelPage::after,#circlePage::before,#circlePage::after,div[id$="Page"]::before{display:none!important;content:none!important}'
        ].join('\n');
        document.head.appendChild(st);

        // 花瓣是动态插入的 <i>，CSS 压不住，直接删
        var killPetals = function () {
          var ns = document.querySelectorAll('.card-snow');
          for (var i = 0; i < ns.length; i++) { if (ns[i].parentNode) ns[i].parentNode.removeChild(ns[i]); }
          var all = document.querySelectorAll('i');
          for (var j = 0; j < all.length; j++) {
            var bi = '';
            try { bi = getComputedStyle(all[j]).backgroundImage || ''; } catch (e) {}
            if (bi.indexOf('petal') >= 0) { all[j].style.display = 'none'; }
          }
        };
        killPetals();
        [300, 900, 1800, 3000, 5000].forEach(function (ms) { setTimeout(killPetals, ms); });
      } catch (e) {}

      // 车辆位置内嵌地图（Leaflet + 高德瓦片）
      (function () {
        var tries = 0;
        function build() {
          var addrEl = document.getElementById('locCardAddress');
          if (!addrEl) { if (++tries < 24) setTimeout(build, 500); return; }
          var card = addrEl.closest('section.card, .myth-card, .card') || addrEl.parentNode;
          if (!document.getElementById('realLocMap')) {
            var box = document.createElement('div');
            box.id = 'realLocMap';
            box.style.cssText = 'height:150px;border-radius:12px;margin-top:10px;overflow:hidden;background:#eef2f7';
            card.appendChild(box);
            // 位置直接显示：只切显示状态，绝不触发详情弹窗
            setInterval(function () {
              var a = document.getElementById('locCardAddress');
              if (!a) return;
              // 已隐藏就只改文案，不点卡片（点卡片会弹窗）
              if ((a.textContent || '').indexOf('隐藏') >= 0) {
                try {
                  if (window.toggleLocCard) window.toggleLocCard();
                } catch (e) {}
              }
              var m = document.getElementById('realLocMap');
              if (m && getComputedStyle(m).display === 'none') {
                m.style.display = 'block';
                try { if (window.__locMap) window.__locMap.invalidateSize(); } catch (e) {}
              }
            }, 600);
          }
          var ph = '';
          try { ph = localStorage.getItem('phone') || ''; } catch (e) {}
          fetch('/api/real/location', { method: 'POST', headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ phone: ph }) }).then(function (r) { return r.json(); }).then(function (j) {
            if (!j || !j.success || j.lat == null || j.lng == null) return;
            var el = document.getElementById('realLocMap');
            if (!el || !window.L) { if (tries < 24) { tries++; setTimeout(build, 800); } return; }
            try {
              if (window.__locMap) { window.__locMap.remove(); window.__locMap = null; }
              var m = L.map(el, { zoomControl: false, attributionControl: false }).setView([j.lat, j.lng], 15);
              L.tileLayer('https://webrd0{s}.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}',
                { subdomains: '1234', maxZoom: 18 }).addTo(m);
              var pin = L.divIcon({
                html: '<div style="width:16px;height:16px;border-radius:50%;background:#4f7cff;border:3px solid #fff;box-shadow:0 2px 8px rgba(79,124,255,.55)"></div>',
                className: '', iconSize: [22, 22], iconAnchor: [11, 11]
              });
              L.marker([j.lat, j.lng], { icon: pin }).addTo(m);
              window.__locMap = m;
            } catch (e) {}
          }).catch(function () {});
        }
        setTimeout(build, 2600);
      })();

      // 去掉位置卡上的「隐藏/显示」眼睛按钮（位置已改为常显）
      (function () {
        var kill = function () {
          var eye = document.getElementById('locEyeIcon');
          if (!eye) return;
          var btn = eye.closest('button') || eye.parentNode;
          if (btn && btn.style.display !== 'none') btn.style.display = 'none';
        };
        kill();
        [400, 1200, 2500].forEach(function (ms) { setTimeout(kill, ms); });
      })();

      // 「更新于」强制使用车辆上报时间，避免被页面用当前时间覆盖
      (function () {
        setInterval(function () {
          var el = document.getElementById('updateTime');
          var tt = window.__terminalTime;
          if (!el || !tt) return;
          var str = String(tt);
          var now = new Date();
          var p = function (n) { return (n < 10 ? '0' : '') + n; };
          var today = now.getFullYear() + '-' + p(now.getMonth() + 1) + '-' + p(now.getDate());
          var disp = str.indexOf(today) === 0 ? str.slice(11, 19) : str.slice(5, 16);
          if (el.textContent !== disp) el.textContent = disp;
        }, 700);
      })();

      // UI 改版：照「长安车控」规范（#F3F6FA 底 / #2F6FB5 主色 / 白卡 #E6EBF1 边 / 16px 圆角 / 纯排版）
      try {
        var ui = document.createElement('style');
        ui.textContent = [
          'html:root{--bg0:#F3F6FA!important;--card:#FFFFFF!important;--card2:#F8FAFC!important;',
          '--border:#E6EBF1!important;--txt:#1A1E24!important;--muted:#7B8592!important;',
          '--faint:#98A2AF!important;--blue:#2F6FB5!important;--green:#2F9E68!important;',
          '--amber:#D98324!important;--red:#D64545!important;--purple:#2F6FB5!important}',
          'body{background:#F3F6FA!important}',
          '.card,section.card,.myth-card{background:#fff!important;border:1px solid #E6EBF1!important;',
          'border-radius:16px!important;box-shadow:none!important}',
          '.card-title{color:#2F6FB5!important;font-weight:600!important}',
          '.seg-btn{background:#fff!important;border:1px solid #2F6FB5!important;color:#2F6FB5!important;border-radius:10px!important}',
          '.seg-btn.active{background:#2F6FB5!important;color:#fff!important}',
          '.btn-primary,button.btn-primary{background:#2F6FB5!important;color:#fff!important;border-radius:10px!important}',
          'nav.tabbar{background:#fff!important;border-top:1px solid #E6EBF1!important}',
          '.tabitem.active{color:#2F6FB5!important}',
          '#extraMeta,#tempLine{color:#7B8592!important}',
          '#lastTripBadge{display:none!important}',
          'section.card{margin-top:10px!important;padding:14px!important}',
          '.card-title{font-size:12px!important;letter-spacing:.2px}',
          '.cbtn-label{font-size:10px!important;margin-top:2px!important}',
          '#quickCard{padding:10px 6px!important}',
          '.fuel-stat-value{font-size:16px!important}'
        ].join('');
        document.head.appendChild(ui);
      } catch (e) {}

      // 空调「新版/官方版」两个按钮已无区别，隐藏并把标题简化
      (function () {
        var fix = function () {
          var seg = document.querySelector('#ctrlCard .seg');
          if (seg) seg.style.display = 'none';
          var t = document.getElementById('acTitle');
          if (t && t.textContent !== '空调控制') t.textContent = '空调控制';
          var pill = document.getElementById('openTokenStatus');
          if (pill) pill.style.display = 'none';
        };
        fix();
        [500, 1500, 3000, 6000].forEach(function (ms) { setTimeout(fix, ms); });
      })();

      // 清掉演示账号遗留的假加油记录（里程明显小于真车总里程）
      (function () {
        var clean = function () {
          var ph = '';
          try { ph = localStorage.getItem('phone') || ''; } catch (e) {}
          if (!ph) return;
          var key = 'fuelRecords_' + ph;
          var recs;
          try { recs = JSON.parse(localStorage.getItem(key) || '[]') || []; } catch (e) { return; }
          if (!recs.length) return;
          // 真车总里程（页面上的「总里程」）
          var odoEl = document.getElementById('totalMileage');
          var realOdo = odoEl ? parseFloat((odoEl.textContent || '').replace(/[^0-9.]/g, '')) : NaN;
          if (!isFinite(realOdo) || realOdo < 1000) return;
          var kept = recs.filter(function (r) {
            var o = parseFloat(r.odo);
            return !isFinite(o) || o > realOdo * 0.5;   // 里程不到真车一半，判为演示数据
          });
          if (kept.length === recs.length) return;
          try { localStorage.setItem(key, JSON.stringify(kept)); } catch (e) {}
          try { if (typeof window.renderFuelHome === 'function') window.renderFuelHome(); } catch (e) {}
        };
        [4000, 8000].forEach(function (ms) { setTimeout(clean, ms); });
      })();

      // 旧加油记录补「加满」标记（否则显示未满/累计中，算不出油耗）
      (function () {
        var fix = function () {
          var ph = '';
          try { ph = localStorage.getItem('phone') || ''; } catch (e) {}
          if (!ph) return;
          var key = 'fuelRecords_' + ph;
          var recs;
          try { recs = JSON.parse(localStorage.getItem(key) || '[]') || []; } catch (e) { return; }
          if (!recs.length) return;
          var changed = false;
          recs.forEach(function (r) {
            if (r && r.full === undefined) { r.full = true; changed = true; }
          });
          if (!changed) return;
          try { localStorage.setItem(key, JSON.stringify(recs)); } catch (e) {}
          try { if (typeof window.renderFuelHome === 'function') window.renderFuelHome(); } catch (e) {}
        };
        fix();
        [3000, 6000].forEach(function (ms) { setTimeout(fix, ms); });
      })();

      // 加油表单：打开时自动带出当日油价
      (function () {
        var wrap = function () {
          if (typeof window.fuelShowForm !== 'function' || window.__fuelPatched) return;
          var orig = window.fuelShowForm;
          window.fuelShowForm = function () {
            var ret = orig.apply(this, arguments);
            setTimeout(function () {
              var p = document.getElementById('fPrice');
              if (!p || p.value) return;
              fetch('/api/oil/price', { method: 'POST', headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ prov: '四川' }) }).then(function (r) { return r.json(); }).then(function (j) {
                if (!j || !j.success || !j.p92) return;
                var el = document.getElementById('fPrice');
                if (!el || el.value) return;
                el.value = j.p92;
                el.dispatchEvent(new Event('input', { bubbles: true }));
                if (window.fuelMachineCalc) window.fuelMachineCalc('price');
                el.title = '当日 ' + (j.prov || '') + ' 92# 油价（' + (j.time || '').slice(0, 10) + '）';
              }).catch(function () {});
            }, 350);
            return ret;
          };
          window.__fuelPatched = true;
        };
        wrap();
        [1500, 4000].forEach(function (ms) { setTimeout(wrap, ms); });
      })();

      // 油费估算兜底：没有加油记录时用「平均油耗 × 油价」算元/公里
      (function () {
        var tick = function () {
          var cost = document.getElementById('fuelCostPerKm');
          if (!cost) return;
          var cur = (cost.textContent || '').trim();
          if (cur !== '--' && cur !== '') return;
          var avgEl = document.getElementById('fuelAvg');
          var avg = avgEl ? parseFloat(avgEl.textContent) : NaN;
          var price = parseFloat(localStorage.getItem('fuelPrice') || '7.86');
          if (!isFinite(avg) || avg <= 0 || !isFinite(price) || price <= 0) return;
          cost.textContent = (avg * price / 100).toFixed(2);
          cost.title = '按油价 ' + price + ' 元/L 估算（可改 localStorage.fuelPrice）';
        };
        setInterval(tick, 1500);
        setTimeout(tick, 3000);
      })();

      // B 类：保养提醒 + 保养历史 + 车辆自检
      (function () {
        var ph = '';
        try { ph = localStorage.getItem('phone') || ''; } catch (e) {}
        var post = function (u) {
          return fetch(u, { method: 'POST', headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ phone: ph }) }).then(function (r) { return r.json(); });
        };
        Promise.all([post('/api/real/maintenance'), post('/api/real/checkitems')])
          .then(function (arr) {
            var mt = arr[0] || {}, ck = arr[1] || {};
            var html = '';

            // 保养
            if ((mt.advices && mt.advices.length) || (mt.history && mt.history.length)) {
              html += '<div style="background:#fff;border:1px solid #E6EBF1;border-radius:16px;padding:14px 16px;margin:10px 14px 0">';
              html += '<div style="font-size:12px;color:#2F6FB5;font-weight:600;margin-bottom:10px">保养</div>';
              (mt.advices || []).slice(0, 4).forEach(function (a) {
                var pct = Number(a.left) || 0;
                var warn = pct < 30;
                html += '<div style="margin-bottom:10px">';
                html += '<div style="display:flex;justify-content:space-between;font-size:12.5px;color:#1A1E24">' +
                        '<span>' + a.name + '</span><span style="color:' + (warn ? '#D64545' : '#2F9E68') + '">剩 ' + pct + '%</span></div>';
                html += '<div style="height:5px;background:#EEF2F7;border-radius:3px;margin-top:5px;overflow:hidden">' +
                        '<div style="height:100%;width:' + pct + '%;background:' + (warn ? '#D64545' : '#2F9E68') + '"></div></div>';
                html += '<div style="font-size:10.5px;color:#98A2AF;margin-top:4px">下次 ' + (a.nextMileage || '-') +
                        ' km / ' + (a.nextDays || '-') + ' 天后</div></div>';
              });
              if (mt.history && mt.history.length) {
                html += '<div style="border-top:1px solid #EEF2F7;margin-top:6px;padding-top:10px">';
                html += '<div style="font-size:11px;color:#98A2AF;margin-bottom:6px">最近保养</div>';
                mt.history.slice(0, 3).forEach(function (h) {
                  html += '<div style="display:flex;justify-content:space-between;font-size:11.5px;color:#2A2F36;padding:4px 0">' +
                          '<span style="flex:1;margin-right:8px">' + (h.items || '-').slice(0, 22) + '</span>' +
                          '<span style="color:#7B8592;white-space:nowrap">' + (h.time || '') + ' · ' + (h.mile || '-') + 'km</span></div>';
                });
                html += '</div>';
              }
              html += '</div>';
            }

            // 自检
            if (ck.success && ck.groups && ck.groups.length) {
              html += '<div style="background:#fff;border:1px solid #E6EBF1;border-radius:16px;padding:14px 16px;margin:10px 14px 0">';
              html += '<div style="font-size:12px;color:#2F6FB5;font-weight:600;margin-bottom:10px">车辆自检</div>';
              html += '<div style="display:grid;grid-template-columns:1fr 1fr;gap:8px">';
              ck.groups.forEach(function (g) {
                html += '<div style="background:#F8FAFC;border-radius:10px;padding:9px 10px">' +
                        '<div style="font-size:12px;color:#1A1E24;font-weight:600">' + g.name + '</div>' +
                        '<div style="font-size:10.5px;color:#7B8592;margin-top:3px">' + g.count + ' 项检查</div></div>';
              });
              html += '</div>';
              html += '<div style="font-size:10.5px;color:#98A2AF;margin-top:9px">共 ' + (ck.total || ck.groups.length) + ' 个系统</div>';
              html += '</div>';
            }

            if (!html) return;
            var box = document.getElementById('bCards');
            if (!box) {
              box = document.createElement('div');
              box.id = 'bCards';
              var doors = document.getElementById('doorsCard');
              var main = document.querySelector('main');
              if (doors && doors.parentNode) doors.parentNode.insertBefore(box, doors.nextSibling);
              else if (main) main.appendChild(box);
              else return;
            }
            box.innerHTML = html;
          }).catch(function () {});
      })();

      // 「我的行程」：该车型不支持行车轨迹（长安返回 code 7），隐藏入口并对报错做友好提示
      (function () {
        var hideTrip = function () {
          var grid = document.getElementById('moreGrid');
          if (!grid) return;
          var items = grid.querySelectorAll('button, .more-item, [onclick]');
          for (var i = 0; i < items.length; i++) {
            var t = (items[i].textContent || '');
            if (t.indexOf('我的行程') >= 0 || /showDrivingHistory/.test(items[i].getAttribute('onclick') || '')) {
              items[i].style.display = 'none';
            }
          }
        };
        hideTrip();
        [600, 1500, 3000].forEach(function (ms) { setTimeout(hideTrip, ms); });

        // 兜底：万一还有边界触发，把原始 JSON 改成中文提示
        var _of = window.fetch;
        window.fetch = function () {
          var p = _of.apply(this, arguments);
          try {
            var a = arguments[0];
            var u = typeof a === 'string' ? a : (a && a.url) || '';
            if (u.indexOf('historyTrackDetail') >= 0 || u.indexOf('drivingHistory') >= 0) {
              p.then(function (r) { return r.clone().json(); }).then(function (j) {
                if (j && j.code === 7) {
                  setTimeout(function () {
                    var m = document.getElementById('resultModal');
                    if (m && !m.classList.contains('hidden')) {
                      var msgEl = document.getElementById('modalMessage');
                      if (msgEl) msgEl.textContent = '该车型不支持行车轨迹';
                      var info = document.getElementById('responseInfo');
                      if (info) { info.textContent = '长安车联网对该车型未开放行程轨迹数据'; info.classList.remove('hidden'); }
                    }
                  }, 300);
                }
              }).catch(function () {});
            }
          } catch (e) {}
          return p;
        };
      })();

      // 位置卡片：点一下只负责"显示位置"，不打开详情弹窗（弹窗只由导航按钮触发）
      (function () {
        var patch = function () {
          if (typeof window.locCardTap !== 'function' || window.__locTapPatched) return;
          window.locCardTap = function () {
            try {
              var a = document.getElementById('locCardAddress');
              var hidden = a && (a.textContent || '').indexOf('隐藏') >= 0;
              if (hidden && typeof window.toggleLocCard === 'function') window.toggleLocCard();
              // 已经是显示状态：什么都不做，不弹窗
            } catch (e) {}
          };
          window.__locTapPatched = true;
        };
        patch();
        [800, 2000, 4000].forEach(function (ms) { setTimeout(patch, ms); });
      })();

      // 功能分类：快捷卡（开锁/闭锁/闪灯/鸣笛）并入控车卡，原卡隐藏
      (function () {
        var ICONS = {
          unlock: '<svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="4" y="11" width="16" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 7.5-2"/></svg>',
          lock: '<svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="4" y="11" width="16" height="10" rx="2"/><path d="M8 11V7a4 4 0 1 1 8 0v4"/></svg>',
          flash: '<svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M9 18h6M10 21h4"/><path d="M12 3a6 6 0 0 0-4 10.5c.8.7 1 1.5 1 2.5h6c0-1 .2-1.8 1-2.5A6 6 0 0 0 12 3Z"/></svg>',
          whistle: '<svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12a5 5 0 0 1 5-5h6l4 5h3v5a4 4 0 0 1-4 4H8a5 5 0 0 1-5-5Z"/><circle cx="10" cy="13" r="2"/></svg>'
        };
        var ROW = [
          ['开锁', 'UnLockDoor', ICONS.unlock],
          ['闭锁', 'LockDoor', ICONS.lock],
          ['闪灯', 'FlashLight', ICONS.flash],
          ['鸣笛', 'Whistle', ICONS.whistle]
        ];

        var build = function () {
          var card = document.getElementById('ctrlCard');
          if (!card || document.getElementById('shimQuickRow')) return;

          // 隐藏原快捷卡（内容已并入控车卡）
          var quick = document.getElementById('quickCard');
          if (quick) quick.style.display = 'none';

          var row = document.createElement('div');
          row.id = 'shimQuickRow';
          row.style.cssText = 'display:grid;grid-template-columns:repeat(4,1fr);gap:8px;margin:4px 0 12px;';
          row.innerHTML = ROW.map(function (it) {
            return '<button type="button" data-cmd="' + it[1] + '" ' +
                   'style="display:flex;flex-direction:column;align-items:center;gap:6px;padding:12px 4px;' +
                   'background:#F5F8FC;border:1px solid #E6EBF1;border-radius:12px;color:#2F6FB5;' +
                   'font-size:10.5px;cursor:pointer;-webkit-tap-highlight-color:transparent">' +
                   it[2] + '<span style="color:#5B6B85">' + it[0] + '</span></button>';
          }).join('');
          row.addEventListener('click', function (e) {
            var b = e.target.closest('button[data-cmd]');
            if (!b) return;
            var ph = '';
            try { ph = localStorage.getItem('phone') || ''; } catch (err) {}
            if (typeof window.performAction === 'function' && ph) {
              window.performAction(ph, b.getAttribute('data-cmd'));
            }
          });

          // 插到标题行后面
          var head = card.querySelector('.card-title');
          var host = head ? head.parentNode : card;
          var anchorEl = host && host.parentNode === card ? host : null;
          if (anchorEl) card.insertBefore(row, anchorEl.nextSibling);
          else card.insertBefore(row, card.firstChild);

          // 分隔标题：车锁/提醒 与 车窗/空调/寻车 分两组
          if (!document.getElementById('shimGroupSep')) {
            var sep = document.createElement('div');
            sep.id = 'shimGroupSep';
            sep.style.cssText = 'display:flex;align-items:center;gap:8px;margin:2px 0 10px;';
            sep.innerHTML = '<span style="font-size:11px;color:#98A2AF;white-space:nowrap">车窗 · 空调 · 寻车</span>' +
                            '<span style="flex:1;height:1px;background:#EEF2F7"></span>';
            if (row.nextSibling) card.insertBefore(sep, row.nextSibling);
            else card.appendChild(sep);
          }
        };

        build();
        [1000, 2500, 5000].forEach(function (ms) { setTimeout(build, ms); });
      })();

      // 一键关窗（门窗卡右上角按钮调用）
      window.__closeAll = function () {
        var phone = '';
        try { phone = localStorage.getItem('phone') || ''; } catch (e) {}
        if (typeof window.performAction !== 'function' || !phone) return;
        window.performAction(phone, 'CloseWindow');
        if (typeof window.showToast === 'function') window.showToast('正在关闭车窗…', 'success');
        setTimeout(function () {
          try { if (typeof window.loadCarData === 'function') window.loadCarData(); } catch (e) {}
        }, 4000);
      };

      // 车门 / 车窗状态：图标网格（图标 + 色点，尽量少文字）
      window.__renderDoors = function (st) {
        try {
          var ICON = {
            door: '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M6 21V9l5-6h7v18"/><path d="M6 21h18"/><rect x="9.5" y="9" width="6" height="5" rx="1"/><circle cx="14" cy="16" r=".9" fill="currentColor" stroke="none"/></svg>',
            trunk: '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M4 16h16V9l-3-3H7L4 9v7Z"/><path d="M3 16h18"/><path d="M8 9h8"/></svg>',
            hood: '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M4 16V9l4-4h8l4 4v7"/><path d="M3 16h18"/><path d="M9 9h6v4H9z"/></svg>',
            win: '<svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><rect x="4" y="4" width="16" height="16" rx="2"/><path d="M12 4v16"/></svg>',
            lock: '<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="4" y="11" width="16" height="10" rx="2"/><path d="M8 11V7a4 4 0 1 1 8 0v4"/></svg>',
            unlock: '<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="4" y="11" width="16" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 7.5-2"/></svg>'
          };
          var doors = [
            ['主驾', st.leftFrontDoor, st.leftFrontDoorLock, 'door'],
            ['副驾', st.rightFrontDoor, st.rightFrontDoorLock, 'door'],
            ['左后', st.leftRearDoor, st.leftRearDoorLock, 'door'],
            ['右后', st.rightRearDoor, st.rightRearDoorLock, 'door'],
            ['后备箱', st.trunk, null, 'trunk'],
            ['引擎盖', st.hood, null, 'hood']
          ];
          var wins = [
            ['主驾', st.leftFrontDoorrWindow], ['副驾', st.rightFrontDoorrWindow],
            ['左后', st.leftRearWindow], ['右后', st.rightRearWindow]
          ];
          var cell = function (name, openVal, lockVal, iconKey) {
            var open = Number(openVal) === 1;
            var locked = lockVal === null ? null : Number(lockVal) === 0;  // 0=已锁
            var main = open ? '#D64545' : '#2F6FB5';
            var bg = open ? '#FEF2F2' : '#F5F8FC';
            var badge = '';
            if (locked !== null) {
              badge = '<span style="color:' + (locked ? '#2F9E68' : '#D98324') + ';display:inline-flex;align-items:center">' +
                      (locked ? ICON.lock : ICON.unlock) + '</span>';
            }
            return '<div style="background:' + bg + ';border-radius:12px;padding:11px 6px;text-align:center;color:' + main + '">' +
                   '<div style="display:flex;justify-content:center">' + ICON[iconKey] + '</div>' +
                   '<div style="font-size:10.5px;color:#7B8592;margin-top:5px;display:flex;align-items:center;justify-content:center;gap:4px">' +
                   name + badge + '</div></div>';
          };
          var winCell = function (name, v) {
            var open = Number(v) === 1;
            return '<div style="display:flex;align-items:center;gap:6px;padding:7px 9px;border-radius:10px;background:' +
                   (open ? '#FEF2F2' : '#F7F9FC') + ';color:' + (open ? '#D64545' : '#9AA6B8') + '">' +
                   ICON.win + '<span style="font-size:10.5px;color:#7B8592">' + name + '</span>' +
                   '<span style="margin-left:auto;font-size:10px;font-weight:600">' + (open ? '开' : '关') + '</span></div>';
          };

          var anyDoorOpen = Number(st.leftFrontDoor) === 1 || Number(st.rightFrontDoor) === 1 ||
                            Number(st.leftRearDoor) === 1 || Number(st.rightRearDoor) === 1;
          var anyWinOpen = Number(st.leftFrontDoorrWindow) === 1 || Number(st.rightFrontDoorrWindow) === 1 ||
                           Number(st.leftRearWindow) === 1 || Number(st.rightRearWindow) === 1;

          // 右上角状态：有开启显示可点的「一键关闭」，全关时显示绿色对勾
          var chip = '';
          if (anyDoorOpen || anyWinOpen) {
            chip = '<button type="button" onclick="window.__closeAll()" ' +
                   'style="display:inline-flex;align-items:center;gap:4px;border:1px solid #2F6FB5;' +
                   'background:#2F6FB5;color:#fff;font-size:11px;font-weight:600;padding:5px 11px;' +
                   'border-radius:99px;cursor:pointer;-webkit-tap-highlight-color:transparent">' +
                   '<svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M4 12h16M4 6h16M4 18h16"/></svg>' +
                   '一键关闭</button>';
          } else {
            chip = '<span style="display:inline-flex;align-items:center;gap:4px;font-size:10.5px;color:#2F9E68">' +
                   '<svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="m5 12 5 5L20 7"/></svg>' +
                   '全部关闭</span>';
          }

          var html = '<div style="background:#fff;border:1px solid #E6EBF1;border-radius:16px;padding:14px;margin:10px 14px 0">' +
            '<div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:10px">' +
            '<span style="font-size:12px;color:#2F6FB5;font-weight:600">门窗</span>' + chip +
            '</div>' +
            '<div style="display:grid;grid-template-columns:repeat(2,1fr);gap:8px">' +
            doors.map(function (d) { return cell(d[0], d[1], d[2], d[3]); }).join('') +
            '</div>' +
            '<div style="display:grid;grid-template-columns:1fr 1fr;gap:6px;margin-top:10px">' +
            wins.map(function (w) { return winCell(w[0] + '窗', w[1]); }).join('') +
            '</div></div>';

          var box = document.getElementById('doorsCard');
          if (!box) {
            box = document.createElement('div');
            box.id = 'doorsCard';
            var main = document.querySelector('main');
            var target = null;
            if (main) {
              var cards = main.querySelectorAll('.myth-card, section.card');
              if (cards.length) target = cards[Math.min(1, cards.length - 1)];
            }
            if (target && target.parentNode) target.parentNode.insertBefore(box, target.nextSibling);
            else if (main) main.appendChild(box);
            else return;
          }
          box.innerHTML = html;
        } catch (e) {}
      };

      // 油耗页：能耗趋势 + 驾驶评分 + 保养提醒
      (function () {
        var ph = '';
        try { ph = localStorage.getItem('phone') || ''; } catch (e) {}
        var post = function (u) {
          return fetch(u, { method: 'POST', headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ phone: ph }) }).then(function (r) { return r.json(); });
        };
        var spark = function (vals, w, h, color) {
          var nums = vals.map(function (v) { return Number(v) || 0; });
          var max = Math.max.apply(null, nums) || 1;
          var pts = nums.map(function (v, i) {
            var x = w * (nums.length > 1 ? i / (nums.length - 1) : 0);
            var y = h - (v / max) * (h - 8) - 4;
            return x.toFixed(1) + ',' + y.toFixed(1);
          }).join(' ');
          return '<svg width="100%" height="' + h + '" viewBox="0 0 ' + w + ' ' + h +
                 '" preserveAspectRatio="none" style="display:block"><polyline fill="none" stroke="' +
                 color + '" stroke-width="2" stroke-linejoin="round" stroke-linecap="round" points="' + pts + '"/></svg>';
        };
        Promise.all([post('/api/real/energy'), post('/api/real/report'), post('/api/real/maintenance')])
          .then(function (arr) {
            var en = arr[0] || {}, rp = arr[1] || {}, mt = arr[2] || {};
            var wrap = document.createElement('div');
            wrap.id = 'realReportCard';
            var html = '';
            html += '<div style="background:#fff;border:1px solid #e6ebf2;border-radius:14px;padding:14px 16px;margin:12px 14px 0;box-shadow:0 2px 10px rgba(15,23,42,.04)">';
            html += '<div style="font-size:12px;color:#7d8aa3;margin-bottom:8px">近 7 天能耗</div>';
            if (en.success && en.fuel && en.fuel.length) {
              html += '<div style="display:flex;align-items:flex-end;gap:10px">';
              html += '<div style="flex:1">' + spark(en.fuel, 240, 46, '#4f7cff') + '</div>';
              html += '<div style="text-align:right"><div style="font-size:19px;font-weight:700;color:#16233a">' +
                      (en.fuelAvg || '-') + '</div><div style="font-size:10px;color:#8fa0b8">L/100km</div></div>';
              html += '</div>';
              html += '<div style="display:flex;justify-content:space-between;font-size:9.5px;color:#a8b4c6;margin-top:4px">';
              (en.dates || []).forEach(function (d) { html += '<span>' + String(d).slice(4, 6) + '/' + String(d).slice(6) + '</span>'; });
              html += '</div>';

              // 今年月度趋势
              if (en.months && en.months.length && en.monthFuel && en.monthFuel.length) {
                var mx = 1;
                en.monthFuel.forEach(function (v) { var n = Number(v) || 0; if (n > mx) mx = n; });
                html += '<div style="margin-top:12px;padding-top:10px;border-top:1px solid #EEF2F7">';
                html += '<div style="font-size:11px;color:#98A2AF;margin-bottom:8px">今年月度油耗（L/100km）</div>';
                html += '<div style="display:flex;align-items:flex-end;gap:5px;height:64px">';
                en.months.forEach(function (m, i) {
                  var v = Number(en.monthFuel[i]) || 0;
                  var h = Math.max(4, Math.round(v / mx * 50));
                  html += '<div style="flex:1;display:flex;flex-direction:column;justify-content:flex-end;align-items:center">' +
                          '<div style="font-size:9px;color:#2F6FB5;margin-bottom:2px">' + (v ? v.toFixed(1) : '-') + '</div>' +
                          '<div style="width:100%;height:' + h + 'px;background:#2F6FB5;border-radius:2px 2px 0 0"></div>' +
                          '<div style="font-size:9px;color:#A6AFBA;margin-top:3px">' + String(m).slice(4) + '月</div></div>';
                });
                html += '</div></div>';
              }
            } else { html += '<div style="font-size:12px;color:#a8b4c6">暂无数据</div>'; }
            html += '</div>';

            if (rp.success && rp.score != null) {
              html += '<div style="background:#fff;border:1px solid #e6ebf2;border-radius:14px;padding:14px 16px;margin:10px 14px 0;box-shadow:0 2px 10px rgba(15,23,42,.04)">';
              html += '<div style="font-size:12px;color:#7d8aa3;margin-bottom:8px">今日驾驶</div>';
              html += '<div style="display:flex;align-items:center;gap:14px">';
              html += '<div style="text-align:center;min-width:64px"><div style="font-size:26px;font-weight:700;color:#12b981;line-height:1">' + rp.score + '</div><div style="font-size:10px;color:#8fa0b8;margin-top:2px">驾驶评分</div></div>';
              html += '<div style="flex:1;font-size:11.5px;color:#5b6b85;line-height:1.9">';
              html += '油耗 ' + (rp.fuel || '-') + ' L/100km ｜ 里程 ' + (rp.mileage || '-') + ' km<br>';
              html += '急加速 ' + (rp.rapidAcc || 0) + ' · 急减速 ' + (rp.rapidDec || 0) + ' · 急转 ' + (rp.sharpTurn || 0);
              html += '</div></div></div>';
            }

            if (mt.success && mt.advices && mt.advices.length) {
              html += '<div style="background:#fff;border:1px solid #e6ebf2;border-radius:14px;padding:14px 16px;margin:10px 14px 0;box-shadow:0 2px 10px rgba(15,23,42,.04)">';
              html += '<div style="font-size:12px;color:#7d8aa3;margin-bottom:8px">保养提醒</div>';
              mt.advices.slice(0, 3).forEach(function (a) {
                var pct = Number(a.left) || 0;
                html += '<div style="margin-bottom:9px">';
                html += '<div style="display:flex;justify-content:space-between;font-size:11.5px;color:#16233a"><span>' + a.name + '</span><span style="color:' + (pct < 30 ? '#ef4444' : '#12b981') + '">剩 ' + pct + '%</span></div>';
                html += '<div style="height:4px;background:#eef1f6;border-radius:2px;margin-top:4px;overflow:hidden"><div style="height:100%;width:' + pct + '%;background:' + (pct < 30 ? '#ef4444' : '#12b981') + '"></div></div>';
                html += '<div style="font-size:10px;color:#8fa0b8;margin-top:3px">下次 ' + (a.nextMileage || '-') + ' km / ' + (a.nextDays || '-') + ' 天后</div>';
                html += '</div>';
              });
              html += '</div>';
            }
            html += '<div style="height:16px"></div>';
            wrap.innerHTML = html;
            var page = document.getElementById('fuelPage');
            if (page) {
              var old = document.getElementById('realReportCard');
              if (old) old.remove();
              var box = page.querySelector('.max-w-lg') || page.firstElementChild;
              if (box) {
                var anchor = box.children && box.children.length > 1 ? box.children[1] : null;
                box.insertBefore(wrap, anchor);
              } else page.appendChild(wrap);
            }
          }).catch(function () {});
      })();

      // 未读消息数：在「消息记录」入口旁加红点
      (function () {
        var ph = '';
        try { ph = localStorage.getItem('phone') || ''; } catch (e) {}
        fetch('/api/real/unread', { method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ phone: ph }) }).then(function (r) { return r.json(); }).then(function (j) {
          if (!j || !j.success || !j.count) return;
          setTimeout(function () {
            var all = document.querySelectorAll('*');
            for (var i = 0; i < all.length; i++) {
              var e = all[i];
              if (e.children.length === 0 && (e.textContent || '').trim() === '消息记录') {
                if (document.getElementById('unreadBadge')) return;
                var b = document.createElement('span');
                b.id = 'unreadBadge';
                b.textContent = j.count > 99 ? '99+' : String(j.count);
                b.style.cssText = 'display:inline-block;margin-left:4px;min-width:16px;padding:0 4px;' +
                  'border-radius:8px;background:#ef4444;color:#fff;font-size:9.5px;line-height:16px;' +
                  'text-align:center;font-weight:600;vertical-align:middle';
                e.parentNode.appendChild(b);
                return;
              }
            }
          }, 1500);
        }).catch(function () {});
      })();

      // 圈子 Tab 已移除：切到索引 2 时回到控车页
      (function () {
        var wrap = function () {
          try {
            if (typeof window.tabGo === 'function' && !window.__tabGoPatched) {
              var orig = window.tabGo;
              window.tabGo = function (n) { return orig.call(this, n === 2 ? 0 : n); };
              window.__tabGoPatched = true;
            }
          } catch (e) {}
        };
        wrap();
        [800, 2000].forEach(function (ms) { setTimeout(wrap, ms); });
      })();

      // 加油记录：服务端有记录时灌入本地并重绘列表
      (function () {
        var tries = 0;
        function go() {
          var list = document.getElementById('fuelList');
          if (!list) { if (++tries < 30) setTimeout(go, 500); return; }
          var ph = '';
          try { ph = localStorage.getItem('phone') || ''; } catch (e) {}
          fetch('/api/fuel/log', { method: 'POST', headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ phone: ph }) }).then(function (r) { return r.json(); }).then(function (j) {
            if (!j || !j.success || !j.records || !j.records.length) return;
            try { localStorage.setItem('fuelRecords_' + ph, JSON.stringify(j.records)); } catch (e) {}
            var empty = document.getElementById('fuelEmpty');
            if (empty) empty.style.display = 'none';
            var cnt = document.getElementById('fuelCount');
            if (cnt) cnt.textContent = j.records.length + ' 条';
            list.innerHTML = j.records.slice().reverse().map(function (r) {
              return '<div class="card px-4 py-3">' +
                '<div style="display:flex;justify-content:space-between;align-items:baseline">' +
                '<span style="font-size:13px;font-weight:600;color:#16233a">' + (r.date || '') + '</span>' +
                '<span style="font-size:13px;font-weight:600;color:#4f7cff">' + (r.liters || '-') + ' L</span></div>' +
                '<div style="display:flex;justify-content:space-between;font-size:11.5px;color:#7d8aa3;margin-top:6px">' +
                '<span>' + (r.odo || '-') + ' km</span><span>' + (r.amount || '-') + ' 元</span>' +
                '<span>' + (r.per100 || '-') + ' L/100km</span></div></div>';
            }).join('');
          }).catch(function () {});
        }
        setTimeout(go, 3000);
      })();

      // 位置卡：原站的 loadLocationCard 定义后没有调用者，这里补上
      (function () {
        var kick = function () {
          try { if (typeof window.loadLocationCard === 'function') window.loadLocationCard(true); } catch (e) {}
        };
        setTimeout(kick, 3000);
        setInterval(kick, 60000);
      })();

      // 车辆详情 / 流量 / 座椅记忆
      (function () {
        var ph = '';
        try { ph = localStorage.getItem('phone') || ''; } catch (e) {}
        var post = function (url) {
          return fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ phone: ph }) }).then(function (r) { return r.json(); });
        };
        Promise.all([post('/api/real/cardetail'), post('/api/real/balance'), post('/api/real/profile')])
          .then(function (arr) {
            var cd = arr[0] || {}, bal = arr[1] || {}, prof = arr[2] || {};
            var parts = [];
            if (cd.success) {
              if (cd.color) parts.push('车色 ' + cd.color);
              if (cd.oilType) parts.push(String(cd.oilType).toUpperCase());
            }
            if (bal.success && bal.items && bal.items.length) {
              var it = bal.items[0];
              parts.push(it.name + ' ' + (it.total == null ? '-' : it.total));
            }
            if (prof.success && prof.count) parts.push('座椅记忆 ' + prof.count + ' 项');
            if (!parts.length) return;
            var old = document.getElementById('extraMeta');
            if (old) old.remove();
            var el = document.createElement('div');
            el.id = 'extraMeta';
            el.style.cssText = 'font-size:10.5px;color:#7d8aa3;margin:8px 14px 0;line-height:1.5;' +
              'text-align:left;max-width:100%;word-break:break-all;clear:both';
            el.textContent = parts.join(' · ');
            // 放到页面顶部（header 下方），独占一行，避免挤车名
            var header = document.querySelector('header');
            if (header && header.parentNode) {
              header.parentNode.insertBefore(el, header.nextSibling);
            } else {
              var host = document.getElementById('carNameText');
              if (host && host.parentNode) host.parentNode.appendChild(el);
            }
          }).catch(function () {});
      })();

      // 真实在线状态（原页面是硬编码「在线」）
      (function () {
        var ph = '';
        try { ph = localStorage.getItem('phone') || ''; } catch (e) {}
        fetch('/api/real/online', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ phone: ph })
        }).then(function (r) { return r.json(); }).then(function (j) {
          if (!j || !j.success) return;
          var chips = document.querySelectorAll('.status-chip');
          for (var i = 0; i < chips.length; i++) {
            var c = chips[i];
            var tx = (c.textContent || '').trim();
            if (tx !== '在线' && tx !== '离线') continue;
            c.innerHTML = '<span class="status-dot" style="background:' +
              (j.online ? 'var(--green)' : '#94a3b8') + '"></span>' + (j.online ? '在线' : '离线');
          }
        }).catch(function () {});
      })();
    } catch (e) {}
  });
})();
