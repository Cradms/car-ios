
window.addEventListener('DOMContentLoaded', function() {
    
    const errorMessage = document.getElementById('error-message');
    if (errorMessage && !errorMessage.classList.contains('hidden')) {
        return; 
    }
    
    
    const refToken = document.getElementById('refTokenInput').value;
    
    if (!refToken) {
        showError('缺少认证信息，请重新登录');
        return;
    }
    
    
    fetch('https://incallapi.changan.com.cn/cac/api/v1/oauth2/refresh_token?client_id=2c918082632162010163388048d60158&refresh_token=' + encodeURIComponent(refToken), {
        method: 'GET',
        headers: {
            'Accept': '*/*',
            'Connection': 'Keep-Alive',
            'User-Agent': 'okhttp/4.9.0',
            'response-form': 'json'
        }
    })
    .then(response => response.json())
    .then(tokenData => {
        if (tokenData.access_token) {
            
            document.getElementById('tokenInput').value = tokenData.access_token;
            
            
            return fetch('https://m.iov.changan.com.cn/app2/api/user/cars?type=0&token=' + encodeURIComponent(tokenData.access_token), {
                method: 'GET',
                headers: {
                    'User-Agent': 'okhttp/4.9.0',
                    'Connection': 'Keep-Alive',
                    'vcs-app-id': 'inCall'
                }
            });
        } else {
            throw new Error('Token 获取失败，请重新注册');
        }
    })
    .then(response => response.json())
    .then(carData => {
        if (carData.data && carData.data.length > 0) {
            document.getElementById('carIdInput').value = carData.data[0].carId;
            
            
            document.getElementById('loading-container').classList.add('hidden');
            document.getElementById('user-info-container').classList.remove('hidden');
            document.getElementById('controls-container').classList.remove('hidden');
            
            
            loadVehicleStatus();
        } else {
            throw new Error('未找到车辆信息');
        }
    })
    .catch(error => {
        showError(error.message || '加载失败，请重新登录');
        document.getElementById('loading-container').classList.add('hidden');
    });
});


function showError(message) {
    const errorDiv = document.getElementById('error-message');
    const errorContent = document.getElementById('error-content');
    if (errorDiv && errorContent) {
        
        const isTokenError = message && (
            message.includes('Token') || 
            message.includes('token') || 
            message.includes('重新注册') ||
            message.includes('获取失败')
        );
        
        if (isTokenError) {
            showTokenExpiredModal();
            return;
        }
        
        errorContent.innerHTML = 
            '<div class="flex items-center">' +
            '<i class="fa fa-exclamation-circle mr-2"></i>' +
            '<span>' + message + '</span>' +
            '</div>';
        errorDiv.classList.remove('hidden');
    }
}

function showTokenExpiredModal() {
    var modal = document.getElementById('tokenExpiredModal');
    if (modal) {
        modal.classList.remove('hidden');
        modal.classList.add('flex');
    }
}

function confirmTokenExpired() {
    localStorage.removeItem('phone');
    localStorage.removeItem('ref_token');
    localStorage.removeItem('pin');
    window.location.href = '/';
}


const actionMap = {
    'LockDoor': '闭锁',
    'UnLockDoor': '开锁',
    'OpenEngine': '点火',
    'CloseEngine': '熄火',
    'openair': '打开空调',
    'closeair': '关闭空调',
    'OpenWindow': '开窗',
    'CloseWindow': '关窗',
    'WindowSlit': '留缝',
    'SkyWindowLiftUp': '开天窗',
    'CloseDormer': '关天窗',
    'Whistle': '鸣笛',
    'RemoteSearchCar': '闪灯&鸣笛',
    'FlashLight': '闪灯'
};


// 指令成功后自动刷新车辆状态：2s/8s/15s 三次，覆盖车机执行延迟
window.autoRefreshAfterCmd = function () {
    [2000, 8000, 15000].forEach(function (d) {
        setTimeout(function () {
            if (typeof window.loadVehicleStatus === 'function') window.loadVehicleStatus();
            if (typeof window.loadLocationCard === 'function') window.loadLocationCard(true);
        }, d);
    });
};


/* ===== 指令执行确认（异步任务）=====
   长安 v3/control/execute 返回 success:true 只表示「指令发送成功」，
   车机是否真正执行是异步的（响应里 handleStatus=Initialized 只是初始态），
   且可能因车辆前置条件不满足而失败（如远程点火要求车门上锁、车窗关闭、
   钥匙在车外等）。因此发送后必须轮询车辆真实状态来确认，不能直接报「执行成功」。
   —— 这正是「提示成功但发动机没着」的根因。 */

/* 读取一次车况原始数据（不渲染），用于判断指令是否生效 */
function _readCarData() {
    var carId = document.getElementById('carIdInput').value;
    var token = document.getElementById('tokenInput').value;
    if (!carId || !token) return Promise.resolve(null);
    var url = 'https://m.iov.changan.com.cn/app2/api/car/data?carId=' + carId +
              '&ErrorAutoProjectile=false&toast=false&keys=*&token=' + token + '&isNev=0';
    return fetch(url, {
        method: 'POST',
        headers: {
            'User-Agent': 'okhttp/4.9.0',
            'Accept': 'application/json, text/plain, */*',
            'vcs-app-id': 'inCall',
            'X-Requested-With': 'cn.com.changan.cvim'
        }
    })
    .then(function (r) { return r.json(); })
    .then(function (res) { return (res && res.success) ? (res.data || null) : null; })
    .catch(function () { return null; });
}

/* 判断某条指令在给定车况下是否已生效。返回 true/false；数据不足返回 null */
function _cmdConfirmCheck(action, d) {
    if (!d) return null;
    var is1 = function (v) { return v === 1 || v === '1'; };
    var engOn = function () {
        var spd = +(d.vehicleSpeed !== undefined && d.vehicleSpeed !== null ? d.vehicleSpeed : d.speed) || 0;
        if (spd > 0) return true;
        var fire = d.fireStatus;
        if (fire === 2 || fire === '2') return false;
        var sp = d.engineSpeed;
        if (sp !== undefined && sp !== null && sp !== '') {
            var n = +sp;
            return !isNaN(n) && n > 0 && n < 16383;
        }
        return is1(d.engineStatus);
    };
    var doorLocked = function () {
        /* 车门锁状态：任一门未锁即为未锁；字段缺失返回 null */
        var vals = [d.leftFrontDoorLock, d.rightFrontDoorLock, d.leftRearDoorLock, d.rightRearDoorLock];
        var shown = vals.filter(function (v) { return v !== undefined && v !== null; });
        if (!shown.length) return null;
        /* 锁车后所有锁位应为 1（已锁）；部分车型 0 表示已锁，故以「全部相同」判定不可靠，
           这里只在全部为 1 时视为已锁，全部为 0 时视为已锁（该车型 0=锁），混合态视为未锁 */
        var all1 = shown.every(function (v) { return v === 1; });
        var all0 = shown.every(function (v) { return v === 0; });
        return all1 || all0;
    };
    switch (action) {
        case 'OpenEngine':  return engOn();
        case 'CloseEngine': return !engOn();
        case 'LockDoor':
            if (d.leftFrontDoorStatus !== undefined) {
                /* 该车系用 *DoorStatus=1 表示已解锁 */
                var anyUnlocked = [d.leftFrontDoorStatus, d.rightFrontDoorStatus, d.leftRearDoorStatus, d.rightRearDoorStatus]
                    .some(function (v) { return v === 1 || v === '1'; });
                return !anyUnlocked;
            }
            return doorLocked();
        case 'UnLockDoor':
            if (d.leftFrontDoorStatus !== undefined) {
                return [d.leftFrontDoorStatus, d.rightFrontDoorStatus, d.leftRearDoorStatus, d.rightRearDoorStatus]
                    .some(function (v) { return v === 1 || v === '1'; });
            }
            return null;
        case 'OpenWindow':  return is1(d.diverWindow) || is1(d.leftFrontDoorrWindow) || is1(d.window);
        case 'CloseWindow': return !is1(d.diverWindow) && !is1(d.leftFrontDoorrWindow);
        default: return null;   /* 鸣笛/闪灯/空调等无稳定可读状态，跳过确认 */
    }
}

/* 轮询确认：最多 maxTry 次，间隔 interval ms。resolve(true/false/null) */
function _pollCmdConfirm(action, maxTry, interval) {
    var tries = 0;
    return new Promise(function (resolve) {
        (function tick() {
            tries++;
            _readCarData().then(function (d) {
                var ok = _cmdConfirmCheck(action, d);
                if (ok === true) return resolve(true);
                if (tries >= maxTry) return resolve(ok === null ? null : false);
                setTimeout(tick, interval);
            });
        })();
    });
}

/* ===== 防误触二次确认 =====
   「我的」→「防误触确认」里可按需勾选哪些操作需要确认（localStorage: confirm_ops）。
   勾选后点击对应按钮会先弹「确定要 xx 吗？」，确认才真正下发指令。 */
const CONFIRM_ITEMS = [
    { k: 'UnLockDoor',      n: '开锁' },
    { k: 'LockDoor',        n: '闭锁' },
    { k: 'OpenEngine',      n: '远程点火' },
    { k: 'CloseEngine',     n: '远程熄火' },
    { k: 'openair',         n: '打开空调（经典版）' },
    { k: 'closeair',        n: '关闭空调（经典版）' },
    { k: 'openAir',         n: '打开空调（新版官方）' },
    { k: 'closeAir',        n: '关闭空调（新版官方）' },
    { k: 'OpenWindow',      n: '开窗' },
    { k: 'CloseWindow',     n: '关窗' },
    { k: 'WindowSlit',      n: '车窗留缝' },
    { k: 'SkyWindowLiftUp', n: '开天窗' },
    { k: 'CloseDormer',     n: '关天窗' },
    { k: 'Whistle',         n: '鸣笛' },
    { k: 'RemoteSearchCar', n: '寻车（闪灯&鸣笛）' },
    { k: 'FlashLight',      n: '闪灯' }
];

function confirmGateGet() {
    try { return JSON.parse(localStorage.getItem('confirm_ops') || '{}') || {}; } catch (e) { return {}; }
}
window.confirmGateNeed = function (action) { return !!confirmGateGet()[action]; };

window.confirmGateName = function (action) {
    var hit = CONFIRM_ITEMS.find(function (it) { return it.k === action; });
    if (hit) return hit.n;
    return actionMap[action] || action;
};

/* 弹确认框：确认后执行 cb()，取消则什么都不做 */
var _confirmGateCb = null;
window.askConfirm = function (name, cb) {
    _confirmGateCb = cb || null;
    var t = document.getElementById('confirmGateText');
    if (t) t.textContent = '确定要「' + name + '」吗？';
    var m = document.getElementById('confirmGateModal');
    if (!m) { if (_confirmGateCb) { var f = _confirmGateCb; _confirmGateCb = null; f(); } return; }
    m.classList.remove('hidden');
    m.classList.add('flex');
};
window.confirmGateOk = function () {
    var m = document.getElementById('confirmGateModal');
    if (m) { m.classList.add('hidden'); m.classList.remove('flex'); }
    var cb = _confirmGateCb; _confirmGateCb = null;
    if (cb) cb();
};
window.confirmGateCancel = function () {
    var m = document.getElementById('confirmGateModal');
    if (m) { m.classList.add('hidden'); m.classList.remove('flex'); }
    _confirmGateCb = null;
};

/* 统一入口：需要确认的操作先弹框 */
function performAction(phone, action) {
    if (window.confirmGateNeed(action)) {
        window.askConfirm(window.confirmGateName(action), function () { _performActionGo(phone, action); });
        return;
    }
    _performActionGo(phone, action);
}

/* ===== 闭锁方式选择：点击「闭锁」弹出，普通锁车（仅车门）/ 一键锁车（车门+全部车窗） ===== */
window.openLockSheet = function () {
    var m = document.getElementById('lockSheetModal');
    if (!m) { performAction(PHONE, 'LockDoor'); return; }   /* 弹层缺失时兜底直接锁车 */
    m.classList.remove('hidden');
    m.classList.add('flex');
};
window.closeLockSheet = function () {
    var m = document.getElementById('lockSheetModal');
    if (m) { m.classList.add('hidden'); m.classList.remove('flex'); }
};
/* 普通锁车：与原闭锁行为一致 */
window.doLockNormal = function () {
    closeLockSheet();
    performAction(PHONE, 'LockDoor');
};
/* 一键锁车：先锁车门，间隔约 4.5 秒再下发关窗（给车机留执行时间），
   两次执行共用结果弹窗，第二次覆盖为「关窗」进度 */
window.doLockAll = function () {
    closeLockSheet();
    var run = function () {
        _performActionGo(PHONE, 'LockDoor');
        setTimeout(function () { _performActionGo(PHONE, 'CloseWindow'); }, 4500);
    };
    if (window.confirmGateNeed('LockDoor') || window.confirmGateNeed('CloseWindow')) {
        window.askConfirm('一键锁车（车门+车窗）', run);
    } else {
        run();
    }
};

function _performActionGo(phone, action) {
    const modal = document.getElementById('resultModal');
    const modalMessage = document.getElementById('modalMessage');
    const responseInfo = document.getElementById('responseInfo');
    
    
    modalMessage.innerHTML = '<div class="flex items-center justify-center"><div class="loading-spinner mr-3"></div><span>正在执行 ' + (actionMap[action] || action) + '...</span></div>';
    responseInfo.classList.add('hidden');
    document.getElementById('resultOkBtn').classList.add('hidden');
    modal.classList.remove('hidden');
    modal.classList.add('flex');
    
    const token = document.getElementById('tokenInput').value;
    
    
    fetch('https://m.iov.changan.com.cn/app2/api/control/createPinVerifyCode', {
        method: 'POST',
        headers: {
            'User-Agent': 'okhttp/4.9.0',
            'Connection': 'Keep-Alive',
            'Content-Type': 'application/x-www-form-urlencoded',
            'vcs-app-id': 'inCall',
        },
        body: `token=${token}`
    })
    .then(response => response.json())
    .then(data => {
        const pinVerifyCode = data.data;
        const carId = document.getElementById('carIdInput').value;
        
        
        return fetch(`https://m.iov.changan.com.cn/app2/api/v2/security/key?carId=${carId}&token=${token}`, {
            method: 'GET',
            headers: {
                'User-Agent': 'okhttp/4.9.0',
                'Connection': 'Keep-Alive',
                'vcs-app-id': 'inCall',
            }
        })
        .then(response => response.json())
        .then(keyData => {
            return {
                pinVerifyCode: pinVerifyCode,
                publicKey: keyData.data
            };
        });
    })
    .then(securityData => {
        const pin = document.getElementById('pinInput').value;
        
        const cmdData = {
            "pinVerifyCode": securityData.pinVerifyCode,
            "cmd": action,
            "type": action,
            "pin": pin,
            "wifiPassword": ""
        };
        
        
        return fetch('/encrypt_data', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                phone: phone,
                public_key: securityData.publicKey,
                plaintext: JSON.stringify(cmdData, null, 0)
            })
        })
        .then(response => response.json())
        .then(encryptResult => {
            if (!encryptResult.success) {
                throw new Error(encryptResult.error || '加密失败');
            }
            
            const controlData = new URLSearchParams();
            controlData.append('toast', 'false');
            controlData.append('phoneType', 'a');
            controlData.append('s', encryptResult.encrypted_data);
            controlData.append('phoneId', 'b');
            controlData.append('isNev', '0');
            controlData.append('temperature', '0');
            controlData.append('loading', 'false');
            controlData.append('carId', document.getElementById('carIdInput').value);
            controlData.append('token', token);
            
            
            return fetch('https://m.iov.changan.com.cn/app2/api/v3/control/execute', {
                method: 'POST',
                headers: {
                    'User-Agent': 'okhttp/4.9.0',
                    'Connection': 'Keep-Alive',
                    'Content-Type': 'application/x-www-form-urlencoded',
                    'vcs-app-id': 'inCall',
                },
                body: controlData
            });
        });
    })
    .then(response => response.json())
    .then(data => {
        /* 关键：此处 data.success 只代表「指令发送成功」，车机是否真正执行是异步的，
           必须轮询车辆真实状态确认，否则会出现「提示成功但发动机没着」。 */
        var name = actionMap[action] || action;
        var sentOk = !(data && data.success === false);
        if (!sentOk) {
            modalMessage.textContent = `执行失败：${name}`;
            responseInfo.textContent = (data && data.msg) || '车辆未接受指令，请稍后重试';
            responseInfo.classList.remove('hidden');
            document.getElementById('resultOkBtn').classList.remove('hidden');
            return;
        }
        /* 指令已下发，直接提示发送成功（不再轮询等待车辆执行确认） */
        modalMessage.textContent = `指令已发送：${name}`;
        responseInfo.textContent = (data && data.msg) || '操作已发送，车况将自动刷新';
        responseInfo.classList.remove('hidden');
        document.getElementById('resultOkBtn').classList.remove('hidden');
        if (window.autoRefreshAfterCmd) window.autoRefreshAfterCmd();
    })
    .catch(error => {
        modalMessage.textContent = '执行失败';
        responseInfo.textContent = error.message || '操作执行失败，请重试';
        responseInfo.classList.remove('hidden');
        document.getElementById('resultOkBtn').classList.remove('hidden');
    });
}

/* 指令已发送但未生效时，给出最可能的原因提示 */
function _cmdFailHint(action) {
    var hints = {
        'OpenEngine': '远程点火需满足：车门已上锁、车窗/天窗关闭、智能钥匙不在车内、挡位在 P 挡。请先锁车关窗后再试。若仍无效，请用长安汽车 App 操作一次确认车机是否在线。',
        'CloseEngine': '远程熄火未生效：请确认车辆处于 P 挡且已驻车，稍后重试。',
        'LockDoor': '闭锁未生效：请确认车门、后备箱、引擎盖均已完全关闭。',
        'UnLockDoor': '开锁未生效：请稍后重试，或检查车机网络信号。'
    };
    return hints[action] || '指令已发送但车辆未在预期时间内执行，可能是车辆前置条件不满足或车机信号不佳，请稍后重试。';
}


function loadVehicleStatus() {
    const carId = document.getElementById('carIdInput').value;
    const token = document.getElementById('tokenInput').value;
    
    if (!carId || !token) {
        console.log('缺少车辆ID或Token，无法获取状态');
        return;
    }
    
    const url = `https://m.iov.changan.com.cn/app2/api/car/data?carId=${carId}&ErrorAutoProjectile=false&toast=false&keys=*&token=${token}&isNev=0`;
    
    const headers = {
        'User-Agent': 'okhttp/4.9.0',
        'Accept': 'application/json, text/plain, */*',
        'vcs-app-id': 'inCall',
        'X-Requested-With': 'cn.com.changan.cvim',
        'Sec-Fetch-Site': 'cross-site',
        'Sec-Fetch-Mode': 'cors',
        'Sec-Fetch-Dest': 'empty',
        'Accept-Language': 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7'
    };
    
    fetch(url, {
        method: 'POST',
        headers: headers
    })
    .then(response => response.json())
    .then(result => {
        if (result.success) {
            const data = result.data || {};
            window.__lastCarData = data;   /* 供开空调温度弹窗等读取当前车机设定温度 */

            // 车模叠加特效：车门/车窗异常闪烁红点（原图不做修改）
            // doorFL/doorRL=左前/左后门（侧视可见侧），winFL/winRL=驾驶员窗/左后窗
            window.updateCarFx = function (doorFL, doorRL, winFL, winRL) {
                var fx = document.getElementById('carFx');
                if (!fx) return;
                fx.classList.toggle('fx-door-open-fl', !!doorFL);
                fx.classList.toggle('fx-door-open-rl', !!doorRL);
                fx.classList.toggle('fx-win-down-fl', !!winFL);
                fx.classList.toggle('fx-win-down-rl', !!winRL);
            };

            // 发动机是否运行：以转速为准（运转 >0，≥16383（0x3FFF 起，含 0xFFFF）均为无效哨兵值=熄火，合理转速不会超过 8000）；
            // 仅当车型完全不上报转速时才退回 engineStatus（部分车型该值恒为 1，不可单独采信）
            function _engineRunning(d) {
                /* 判定顺序（多车型实测）：
                   1) 车速 > 0 一定在运行；
                   2) fireStatus === 2 表示熄火/未点火 —— 此时转速是熄火前最后一次怠速的残留值
                      （实测三代逸动 751、三代CS75PLUS 756、UNI-V 721、逸动新蓝鲸 1030），不能当运行中；
                   3) 其余按转速（≥16383 为无效哨兵值）；
                   4) 无转速时用 engineStatus 兜底。 */
                var spd = +(d.vehicleSpeed !== undefined && d.vehicleSpeed !== null ? d.vehicleSpeed : d.speed) || 0;
                if (spd > 0) return true;
                var fire = d.fireStatus;
                if (fire === 2 || fire === '2') return false;
                var sp = d.engineSpeed;
                var hasSp = sp !== undefined && sp !== null && sp !== '';
                if (hasSp) {
                    var n = +sp;
                    return !isNaN(n) && n > 0 && n < 16383;
                }
                var es = d.engineStatus;
                return es === 1 || es === '1';
            }

            /* 车窗是否打开：按车型代码分流（详见 static/js/car_fields.js）
               - 三代 CS75PLUS（confCode SC6479BEH6*，S311-D20T / CS75PLUS-ICA）：
                 车机不上报具体车窗字段（恒 0），真实开闭只认通用 window 字段；
               - 其他车型：具体车窗字段正常上报，优先具体字段、全部缺失才退回 window。
               车主实测反馈：CS75PLUS 车窗实际开着时具体字段仍全 0，曾因此漏报 */

            // 车辆下方状态标注：异常红色小字，全部正常显示绿色"车况正常"
            var tagBox = document.getElementById('carStateTags');
            if (tagBox) {
                var engineOn = _engineRunning(data);
                var anyDoor = [data.leftFrontDoorStatus, data.rightFrontDoorStatus, data.leftRearDoorStatus, data.rightRearDoorStatus, data.trunk, data.hood]
                    .some(function (v) { return v === 1; });
                var anyWin = window.CarFields ? window.CarFields.anyWindowOpen(data) : false;
                // 侧视可见侧的具体门窗（用于车模特效联动；聚合车型位置未知返回 null，不闪红点）
                var doorFL = data.leftFrontDoorStatus === 1 || data.leftFrontDoorStatus === '1';
                var doorRL = data.leftRearDoorStatus === 1 || data.leftRearDoorStatus === '1';
                var winFL = window.CarFields ? window.CarFields.windowOpenAt(data, ['diverWindow', 'driverWindow', 'leftFrontDoorrWindow', 'leftFrontDoorWindow']) : false;
                var winRL = window.CarFields ? window.CarFields.windowOpenAt(data, ['leftRearWindow', 'leftRearDoorrWindow']) : false;
                var tags = [];
                if (engineOn) tags.push(['发动机已启动', '']);
                if (anyDoor) tags.push(['车门已解锁', '']);
                if (anyWin) tags.push(['车窗未关闭', '']);
                if (!tags.length) tags.push(['车况正常', 'ok']);
                tagBox.innerHTML = tags.map(function (t) {
                    return '<span class="car-tag ' + t[1] + '"><i></i>' + t[0] + '</span>';
                }).join('');
            }
            // 联动车模特效（车门/车窗红点）
            if (window.updateCarFx) { try { window.updateCarFx(doorFL, doorRL, winFL, winRL); } catch (e) {} }

            // 3D 真车车模实时联动（控车主页 3D 视图：门窗/后备箱/发动机/灯光）
            window.__lastVehicleData = data;
            if (window.Car3D && window.Car3D.updateFromVehicleData) {
                try {
                    /* 发动机用与状态标签同一套多车型判定（转速/熄火哨兵/车速），
                       避免部分车型 engineStatus 恒为 1 导致车轮常转 */
                    var d3d = Object.assign({}, data);
                    d3d.engineStatus = _engineRunning(data) ? 1 : 0;
                    window.Car3D.updateFromVehicleData(d3d);
                } catch (e) {}
            }

            const carStatus = document.getElementById('carStatus');
            if (carStatus) {
                if (_engineRunning(data)) {
                    carStatus.textContent = '启动';
                    carStatus.className = 'text-lg font-bold text-amber-500';
                } else {
                    carStatus.textContent = '熄火';
                    carStatus.className = 'text-lg font-bold text-gray-400';
                }
            }
            
            
            var fuelLeftover = data.fuelLeftover;
            if (fuelLeftover !== undefined && fuelLeftover !== null) {
                document.getElementById('fuelLevel').textContent = fuelLeftover + ' L';
            }
            
            
            var remainedOilMile = data.remainedOilMile;
            if (remainedOilMile !== undefined && remainedOilMile !== null) {
                document.getElementById('remainMileage').textContent = remainedOilMile + ' km';
            }
            
            
            var totalMileage = data.totalOdometer;
            if (totalMileage !== undefined && totalMileage !== null) {
                document.getElementById('totalMileage').textContent = totalMileage + ' km';
            }
            
            
            var lastTripOil = data.igniteCumulativeOil;
            if (lastTripOil !== undefined && lastTripOil !== null) {
                var lastTripOilEl = document.getElementById('lastTripOil');
                if (lastTripOilEl) lastTripOilEl.textContent = lastTripOil + ' L';
            }
            
            
            var lastTripMileage = data.igniteCumulativeMileage;
            if (lastTripMileage !== undefined && lastTripMileage !== null) {
                var lastTripMileageEl = document.getElementById('lastTripMileage');
                if (lastTripMileageEl) lastTripMileageEl.textContent = lastTripMileage + ' km';
            }

            // 车况卡标题栏徽章：上次行程里程 + 油耗
            var badge = document.getElementById('lastTripBadge');
            if (badge && lastTripOil !== undefined && lastTripOil !== null && parseFloat(lastTripOil) > 0) {
                var badgeTxt = '';
                if (lastTripMileage !== undefined && lastTripMileage !== null && parseFloat(lastTripMileage) > 0) {
                    badgeTxt += '上次里程' + lastTripMileage + '公里 ';
                }
                badgeTxt += '油耗：' + lastTripOil + 'L';
                badge.textContent = badgeTxt;
                badge.classList.remove('hidden');
            }
            
            
            var batteryVoltage = data.batteryVoltage;
            if (batteryVoltage !== undefined && batteryVoltage !== null) {
                var bvEl = document.getElementById('batteryVoltage');
                if (bvEl) bvEl.textContent = batteryVoltage + 'V';

                var batteryBar = document.getElementById('batteryBar');
                if (batteryBar) {
                    var minVoltage = 11;
                    var maxVoltage = 15;
                    var percentage = Math.min(100, Math.max(0, ((batteryVoltage - minVoltage) / (maxVoltage - minVoltage)) * 100));
                    batteryBar.style.width = percentage + '%';
                    if (batteryVoltage < 11.5) {
                        batteryBar.className = 'bg-red-500 h-1 rounded-full transition-all duration-500';
                    } else if (batteryVoltage < 12) {
                        batteryBar.className = 'bg-amber-500 h-1 rounded-full transition-all duration-500';
                    } else {
                        batteryBar.className = 'bg-green-500 h-1 rounded-full transition-all duration-500';
                    }
                }
            }

            // 实时胎压（kPa）：车况卡四角小方块，无效值显示 --，偏离正常范围红色警示
            function _tpValid(v) { return v !== undefined && v !== null && v !== '' && !isNaN(+v) && +v > 0 && +v !== 65535; }
            [['lfTyrePressure', 'tpLF'], ['rfTyrePressure', 'tpRF'], ['lrTyrePressure', 'tpLR'], ['rrTyrePressure', 'tpRR']]
            .forEach(function (pair) {
                var el = document.getElementById(pair[1]);
                if (!el) return;
                if (_tpValid(data[pair[0]])) {
                    var v = +data[pair[0]];
                    el.textContent = v;
                    el.classList.toggle('warn', v > 350 || v < 150);
                } else {
                    el.textContent = '--';
                    el.classList.remove('warn');
                }
            });

            // 温度行：外温 + 空调设定温度（无数据时显示 --）
            (function () {
                var el = document.getElementById('tempLine');
                if (!el) return;
                var et = data.environmentalTemp;   /* 车外环境温度 */
                var vt = data.vehicleTemperature;  /* 车内温度 */
                var at = (data.air && data.air.temperature !== undefined) ? data.air.temperature : data.airConditioningSetTemperature;
                function fmt(v) { return (v !== undefined && v !== null && v !== '' && !isNaN(+v)) ? Math.round(+v) + '°C' : '--°C'; }
                el.textContent = '外' + fmt(et) + ' ｜ 内' + fmt(vt) + ' ｜ 空调' + fmt(at);
            })();
            
            
            var doorWindowStatus = document.getElementById('doorWindowStatus');
            if (doorWindowStatus) {
                var doorValues = [
                    data.leftFrontDoorStatus,
                    data.rightFrontDoorStatus,
                    data.leftRearDoorStatus,
                    data.rightRearDoorStatus,
                    data.trunk,
                    data.hood
                ];
                var windowValues = [
                    data.diverWindow,
                    data.passengerWindow,
                    data.leftRearWindow,
                    data.rightRearWindow
                ];
                var anyDoorOpen = doorValues.some(function(v) { return v === 1; });
                /* 车窗按车型感知判定：三代 CS75PLUS 具体字段不上报，只认通用 window */
                var anyWindowOpen = window.CarFields ? window.CarFields.anyWindowOpen(data)
                    : windowValues.some(function(v) { return v === 1; });
                
                if (anyDoorOpen && anyWindowOpen) {
                    doorWindowStatus.textContent = '开启';
                    doorWindowStatus.className = 'text-xs font-bold text-red-500';
                } else if (anyDoorOpen) {
                    doorWindowStatus.textContent = '开门';
                    doorWindowStatus.className = 'text-xs font-bold text-amber-500';
                } else if (anyWindowOpen) {
                    doorWindowStatus.textContent = '开窗';
                    doorWindowStatus.className = 'text-xs font-bold text-amber-500';
                } else {
                    doorWindowStatus.textContent = '关闭';
                    doorWindowStatus.className = 'text-xs font-bold text-green-500';
                }
            }
            
        } else {
            console.log('获取车辆状态失败:', result.msg);
            /* 车机从未上报车况数据（长安返回"尚无车况信息"等）：
               不是登录/网站问题，给出明确指引而不是让页面一片"未获取" */
            var m = (result.msg || '').toString();
            if (m.indexOf('尚无车况') >= 0 || m.indexOf('无车况') >= 0 || m.indexOf('未定位') >= 0 || m.indexOf('暂无') >= 0) {
                var tagBox2 = document.getElementById('carStateTags');
                if (tagBox2) {
                    var go = function () {
                        var app = window.APP || {};
                        location.href = '/vehicle_status?phone=' + encodeURIComponent(app.phone || '') + '&ref_token=' + encodeURIComponent(app.refToken || '') + '&pin=' + encodeURIComponent(app.pin || '');
                    };
                    var hint = document.createElement('span');
                    hint.className = 'car-tag hint';
                    hint.innerHTML = '<i></i>车辆未上报车况 · 点此查看解决方法';
                    hint.onclick = go;
                    tagBox2.innerHTML = '';
                    tagBox2.appendChild(hint);
                }
                if (!window._noDataToastShown) {
                    window._noDataToastShown = true;
                    window.showToast && window.showToast('账号正常，车辆暂未上报车况数据：请启动车辆一次后再试', 'fail');
                }
            }
        }
    })
    .catch(error => {
        console.log('获取车辆状态出错:', error.message);
    });
}

/* ===== 防误触确认配置页（「我的」→「防误触确认」） ===== */
window.renderConfirmCfg = function () {
    var box = document.getElementById('confirmCfgList');
    if (!box) return;
    var saved = confirmGateGet();
    var onStyle = 'width:44px;height:26px;border-radius:13px;background:#10b981;position:relative;transition:background .15s;flex-shrink:0';
    var offStyle = 'width:44px;height:26px;border-radius:13px;background:#d6d3d1;position:relative;transition:background .15s;flex-shrink:0';
    var knobOn = 'position:absolute;top:2px;left:20px;width:22px;height:22px;border-radius:50%;background:#fff;box-shadow:0 1px 3px rgba(0,0,0,.25);transition:left .15s';
    var knobOff = 'position:absolute;top:2px;left:2px;width:22px;height:22px;border-radius:50%;background:#fff;box-shadow:0 1px 3px rgba(0,0,0,.25);transition:left .15s';
    box.innerHTML = CONFIRM_ITEMS.map(function (it, i) {
        var on = !!saved[it.k];
        return '<div class="flex items-center gap-3 py-3' + (i ? '" style="border-top:1px solid var(--border)' : '') + '">'
            + '<div class="flex-1 min-w-0"><p class="text-[13px] font-semibold" style="color:var(--txt)">' + it.n + '</p></div>'
            + '<button type="button" onclick="toggleConfirmOp(\'' + it.k + '\')" style="' + (on ? onStyle : offStyle) + '">'
            + '<span style="' + (on ? knobOn : knobOff) + '"></span></button>'
            + '</div>';
    }).join('');
};
window.toggleConfirmOp = function (k) {
    var cfg = confirmGateGet();
    if (cfg[k]) delete cfg[k]; else cfg[k] = true;
    try { localStorage.setItem('confirm_ops', JSON.stringify(cfg)); } catch (e) {}
    window.renderConfirmCfg();
    var t = window.confirmGateName(k);
    window.showToast && window.showToast((cfg[k] ? '已开启「' : '已关闭「') + t + '」二次确认', 'ok');
};
window.confirmGateSetAll = function (on) {
    var cfg = {};
    if (on) CONFIRM_ITEMS.forEach(function (it) { cfg[it.k] = true; });
    try { localStorage.setItem('confirm_ops', JSON.stringify(cfg)); } catch (e) {}
    window.renderConfirmCfg();
    window.showToast && window.showToast(on ? '已开启全部操作的二次确认' : '已关闭全部二次确认', 'ok');
};
window.openConfirmCfgPage = function () {
    document.getElementById('confirmCfgPage').classList.remove('hidden');
    window.scrollTo({ top: 0 });
    window.renderConfirmCfg();
};
window.closeConfirmCfgPage = function () { document.getElementById('confirmCfgPage').classList.add('hidden'); };
