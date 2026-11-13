
window.addEventListener('DOMContentLoaded', function() {
    
    initToggleFunctionality();
    
    
    const errorMessage = document.getElementById('error-message');
    if (errorMessage && !errorMessage.classList.contains('hidden')) {
        return; 
    }
    
    
    const refToken = document.getElementById('refTokenInput').value;
    
    if (!refToken) {
        showError('缺少认证信息，请重新登录');
        return;
    }
    
    /* 直接刷新 token */
    var _chain = fetch('https://incallapi.changan.com.cn/cac/api/v1/oauth2/refresh_token?client_id=2c918082632162010163388048d60158&refresh_token=' + encodeURIComponent(refToken), {
        method: 'GET',
        headers: {
            'Accept': '*/*',
            'Connection': 'Keep-Alive',
            'User-Agent': 'okhttp/4.9.0',
            'response-form': 'json'
        }
    });
    
    _chain
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
            
            
            getVehicleStatus();
        } else {
            throw new Error('未找到车辆信息');
        }
    })
    .catch(error => {
        if (error && error.__expBlocked) return;   // 体验守卫已提示，不重复报错
        showError(error.message || '加载失败，请重新登录');
        document.getElementById('loading-container').classList.add('hidden');
    });
});


/* 长安接口返回"车况为空"类提示时展示引导卡；命中返回 true */
function showNoDataGuide(msg) {
    var box = document.getElementById('nodata-guide');
    var msgEl = document.getElementById('nodata-msg');
    var text = (msg || '').toString();
    var isEmpty = text.indexOf('尚无车况') >= 0 || text.indexOf('未定位') >= 0 ||
                  text.indexOf('无车况') >= 0 || text.indexOf('暂无') >= 0;
    if (!box || !isEmpty) return false;
    if (msgEl) msgEl.textContent = '「' + text + '」';
    box.classList.remove('hidden');
    var err = document.getElementById('error-message');
    if (err) err.classList.add('hidden');
    var vs = document.getElementById('vehicleStatus');
    if (vs) vs.classList.add('hidden');
    return true;
}


function showError(message) {
    const errorDiv = document.getElementById('error-message');
    const errorText = document.getElementById('error-text');
    const loadingContainer = document.getElementById('loading-container');
    
    
    if (loadingContainer) {
        loadingContainer.classList.add('hidden');
    }
    var guide = document.getElementById('nodata-guide');
    if (guide) guide.classList.add('hidden');
    
    
    const isTokenError = message && (
        message.includes('Token') || 
        message.includes('token') || 
        message.includes('重新注册') ||
        message.includes('获取失败')
    );
    
    if (isTokenError) {
        var modal = document.getElementById('tokenExpiredModal');
        if (modal) {
            modal.classList.remove('hidden');
            modal.classList.add('flex');
        }
        return;
    }
    
    if (errorDiv && errorText) {
        errorText.textContent = message;
        errorDiv.classList.remove('hidden');
    }
}


function getVehicleStatus() {
    const loadingContainer = document.getElementById('loading-container');
    const vehicleStatus = document.getElementById('vehicleStatus');
    
    
    loadingContainer.classList.remove('hidden');
    vehicleStatus.classList.add('hidden');
    var guide = document.getElementById('nodata-guide');
    if (guide) guide.classList.add('hidden');
    
    const carId = document.getElementById('carIdInput').value;
    const token = document.getElementById('tokenInput').value;
    
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
        loadingContainer.classList.add('hidden');
        
        if (result.success) {
            const data = result.data || {};
            
            
            (function(){var _tt=(data&&(data.terminalTime||data.serverTime))||'';var _el=document.getElementById('updateTime');if(_el){_el.textContent='更新时间: '+(_tt?String(_tt).slice(5,16):'--');}})();
            var sigEl = document.getElementById('signaIntensity');
            if (sigEl) {
                setNumText('signaIntensity', data.signaIntensity, '%');
            }
            
            
            setNumText('fuelLeftover', data.fuelLeftover, ' L');
            setNumText('remainedOilMile', data.remainedOilMile, ' km');
            setNumText('igniteCumulativeOil', data.igniteCumulativeOil, ' L');
            setNumText('igniteCumulativeMileage', data.igniteCumulativeMileage, ' km');
            setNumText('modalBatteryVoltage', data.batteryVoltage, ' V');
            setText('engineCoolantStatus', data.engineCoolantStatus === 0 ? '正常' : '异常');
            setText('lowOilPressureFlag', data.lowOilPressureFlag === 0 ? '正常' : '异常');
            
            setText('engineStatus2', data.engineStatus == 0 ? '熄火' : '启动');
            setText('vehicleStabilityControlSystemStatus', data.vehicleStabilityControlSystemStatus === 0 ? '正常' : '异常');
            setText('transmissionSystemStatus', data.transmissionSystemStatus === 0 ? '正常' : '异常');
            setText('isValidGps', data.isValidGps === 0 ? '无效' : '有效');
            setText('absStatus', data.absStatus === 0 ? '正常' : '异常');
            setText('airbagSystemStatus', data.airbagSystemStatus === 0 ? '正常' : '异常');
            
            
            function updateStatusItem(elementId, statusValue, isNormalCondition = true) {
                const statusElement = document.getElementById(elementId);
                if (!statusElement) return;

                let isNormal = false;

                if (elementId === 'engineStatus2') {
                    /* 熄火/启动均为正常展示 */
                    isNormal = true;
                } else if (elementId === 'isValidGps') {
                    isNormal = statusValue !== 0;
                } else {
                    isNormal = statusValue === 0;
                }

                statusElement.classList.remove('st-ok', 'st-warn', 'v-na');
                statusElement.classList.add(isNormal ? 'st-ok' : 'st-warn');
            }
            
            
            updateStatusItem('engineStatus2', data.engineStatus, false); 
            updateStatusItem('engineCoolantStatus', data.engineCoolantStatus);
            updateStatusItem('lowOilPressureFlag', data.lowOilPressureFlag);
            updateStatusItem('vehicleStabilityControlSystemStatus', data.vehicleStabilityControlSystemStatus);
            updateStatusItem('transmissionSystemStatus', data.transmissionSystemStatus);
            updateStatusItem('isValidGps', data.isValidGps, false); 
            updateStatusItem('absStatus', data.absStatus);
            updateStatusItem('airbagSystemStatus', data.airbagSystemStatus);
            
            
            const finalStatusBadge = document.getElementById('finalStatusBadge');
            if (finalStatusBadge) {
                const isCoolantNormal = data.engineCoolantStatus === 0;
                const isOilPressureNormal = data.lowOilPressureFlag === 0;
                const isFinalStatusNormal = isCoolantNormal && isOilPressureNormal;
                
                
                finalStatusBadge.classList.remove('status-online', 'status-offline');
                
                
                if (isFinalStatusNormal) {
                    finalStatusBadge.classList.add('status-online');
                    finalStatusBadge.innerHTML = '<i class="fa fa-circle mr-1" style="font-size: 5px;"></i>正常';
                } else {
                    finalStatusBadge.classList.add('status-offline');
                    finalStatusBadge.innerHTML = '<i class="fa fa-circle mr-1" style="font-size: 5px;"></i>异常';
                }
            }
            
            
            setNumText('totalOdometer', data.totalOdometer, ' km');
            setNumText('environmentalTemp', data.environmentalTemp, ' °C');
            setText('keyLowPower', data.keyLowPower == 0 ? '正常' : '低电量');
            setNumText('vehicleTemperature', data.vehicleTemperature, ' °C');
            setNumText('engineWaterTemp', data.engineWaterTemp, ' °C');
            setText('ignitionTime', data.ignitionTime);
            
            
            setNumText('airConditioningSetTemperature', data.air ? data.air.temperature : data.airConditioningSetTemperature, ' °C');
            setText('airRecycleStatus', data.airRecycleStatus == 1 ? '内循环' : '外循环');
            
            
            setNumText('lfTyrePressure', data.lfTyrePressure, ' kPa');
            setNumText('rfTyrePressure', data.rfTyrePressure, ' kPa');
            setNumText('lrTyrePressure', data.lrTyrePressure, ' kPa');
            setNumText('rrTyrePressure', data.rrTyrePressure, ' kPa');
            
            
            setStatusText('leftFrontDoorStatus', data.leftFrontDoorStatus);
            setStatusText('rightFrontDoorStatus', data.rightFrontDoorStatus);
            setStatusText('leftRearDoorStatus', data.leftRearDoorStatus);
            setStatusText('rightRearDoorStatus', data.rightRearDoorStatus);
            setStatusText('trunk', data.trunk);
            setStatusText('hood', data.hood);
            
            
            /* 车窗按车型代码分流（详见 car_fields.js）：
               三代 CS75PLUS（confCode SC6479BEH6*）车机不上报具体车窗、通用 window 恒为 '1'，
               两个字段都不反映真实状态——显示 -- 而非编造状态并附注说明；
               其他车型具体字段正常，逐窗显示。 */
            var winUnreported = !!(window.CarFields && window.CarFields.isWindowUnreportedModel(data));
            var winNote = document.getElementById('windowAggNote');
            if (winUnreported) {
                ['diverWindow', 'passengerWindow', 'leftRearWindow', 'rightRearWindow'].forEach(function (k) {
                    var el = document.getElementById(k);
                    if (el) { el.textContent = '--'; el.classList.remove('st-open', 'st-close'); el.classList.add('v-na'); }
                });
                if (winNote) winNote.classList.remove('hidden');
            } else {
                if (winNote) winNote.classList.add('hidden');
                setStatusText('diverWindow', data.diverWindow);
                setStatusText('passengerWindow', data.passengerWindow);
                setStatusText('leftRearWindow', data.leftRearWindow);
                setStatusText('rightRearWindow', data.rightRearWindow);
            }
            
            
            setStatusText('lowBeam', data.lowBeam);
            setStatusText('highBeam', data.highBeam);
            setStatusText('positionLight', data.positionLight);
            setStatusText('frontFoglamp', data.frontFoglamp);
            setStatusText('rearFoglamp', data.rearFoglamp);
            
            vehicleStatus.classList.remove('hidden');
        } else {
            /* 车机从未上报数据（长安返回"尚无车况信息"/"车辆未定位"等）：
               不是本站故障，显示引导卡教用户自查，而不是抛红色报错 */
            if (showNoDataGuide(result.msg)) return;
            showError('请求失败: ' + (result.msg || '未知错误'));
        }
    })
    .catch(error => {
        loadingContainer.classList.add('hidden');
        showError('请求出错: ' + error.message);
    });
}


function setText(id, value) {
    const element = document.getElementById(id);
    if (element) {
        if (value !== undefined && value !== null && value !== '--') {
            element.textContent = value;
            element.classList.remove('v-na');
        } else {
            element.textContent = '--';
            element.classList.add('v-na');
        }
    }
}


/* 数值字段：缺失 / 非数字时显示 --，避免 "undefined °C" 之类泄漏到界面 */
function setNumText(id, value, suffix) {
    if (value === undefined || value === null || value === '' || isNaN(+value)) {
        setText(id, null);
    } else {
        setText(id, (+value) + suffix);
    }
}


function setStatusText(id, value) {
    const element = document.getElementById(id);
    if (element) {
        element.classList.remove('st-open', 'st-close', 'v-na');
        if (value === 1 || value === '1') {
            element.textContent = '开启';
            element.classList.add('st-open');
        } else {
            element.textContent = '关闭';
            element.classList.add('st-close');
        }
    }
}


function initToggleFunctionality() {
    const toggleButtons = document.querySelectorAll('.toggle-btn');
    
    toggleButtons.forEach(button => {
        button.addEventListener('click', function() {
            const targetId = this.getAttribute('data-target');
            const targetElement = document.getElementById(targetId);
            const toggleText = this.querySelector('.toggle-text');
            const toggleIcon = this.querySelector('.toggle-icon');
            
            if (targetElement) {
                if (targetElement.classList.contains('max-h-48')) {
                    
                    targetElement.classList.remove('max-h-48');
                    targetElement.classList.add('max-h-full');
                    toggleText.textContent = '收起';
                    toggleIcon.classList.add('rotate-180');
                } else {
                    
                    targetElement.classList.remove('max-h-full');
                    targetElement.classList.add('max-h-48');
                    toggleText.textContent = '展开';
                    toggleIcon.classList.remove('rotate-180');
                }
            }
        });
    });
}