/* 车型感知的车况字段解析（主页 user_info 与车辆状态页 vehicle_status 共用）
 *
 * 缘起：CS75PLUS 车主反馈「自从改了三代逸动，车窗状态就不准了」。
 * 追查历史（/workspace/_backup_before_rewrite/site_before_rewrite.bundle 中的 0e4ced8）：
 *   那次「修复主页车窗漏报」把车窗判定从 4 个具体字段
 *   （diverWindow / passengerWindow / leftRearWindow / rightRearWindow）
 *   扩成了「具体字段 + 通用 window」全查，从此 CS75PLUS 才开始误报「车窗未关」。
 *
 * 实测（2026-10-13 全量 43 台车 + 连续采样）：
 *   - 三代 CS75PLUS（confCode SC6479BEH6*；S311-D20T / CS75PLUS-ICA）：
 *     具体车窗字段恒为 0（不上报），通用 window 恒为 '1'（固定值，与真实开闭无关——
 *     连续采样车门、车窗全关时仍恒为 '1'）。两个字段都不反映真实状态，
 *     因此沿用 v1.41 之前的口径：按具体字段判定（恒 0 → 不误报），绝不采信 window；
 *   - 其他车型（逸动 C211*、C281、C589、S202 等 37 台）：具体车窗字段正常上报，
 *     且与通用 window 一致（开窗双 1、关窗双 0），具体字段优先、缺失才退回 window。
 *
 * 结论：window 是 CS75PLUS 误报的源头，仅作其他车型的兜底，聚合车型一律不读。
 */
(function (global) {
    'use strict';

    /* 具体车窗字段（各代车型命名不统一：diverWindow / leftFrontDoorrWindow / driverWindow ...） */
    var WIN_SPECIFIC_KEYS = ['diverWindow', 'driverWindow', 'leftFrontDoorrWindow', 'leftFrontDoorWindow',
                             'passengerWindow', 'leftRearWindow', 'rightRearWindow',
                             'leftRearDoorrWindow', 'rightRearDoorrWindow'];

    function _is1(v) { return v === 1 || v === '1'; }

    /* 三代 CS75PLUS：车机不上报具体车窗、window 恒为 '1' 不可用。
       判定依据 confCode 前缀 SC6479BEH6 + seriesCode 双保险 */
    function isWindowUnreportedModel(d) {
        if (!d) return false;
        var conf = d.carConfCode || d.confCode || '';
        if (/^SC6479BEH6/.test(conf)) return true;
        var s = d.seriesCode || '';
        return s === 'S311-D20T' || s === 'CS75PLUS-ICA';
    }

    /* 车窗是否打开（任一车窗未关即为真）——车型感知 */
    function anyWindowOpen(d) {
        if (!d) return false;
        if (isWindowUnreportedModel(d)) {
            /* 该车型具体字段与 window 均不可信：按具体字段判定（全 0 → 视为已关），不误报 */
            return WIN_SPECIFIC_KEYS.some(function (k) { return _is1(d[k]); });
        }
        var hasSpecific = WIN_SPECIFIC_KEYS.some(function (k) { return d[k] !== undefined && d[k] !== null; });
        if (hasSpecific) {
            return WIN_SPECIFIC_KEYS.some(function (k) { return _is1(d[k]); });
        }
        /* 车型完全不上报具体字段时，退回通用 window 避免漏报 */
        return _is1(d.window);
    }

    /* 指定具体车窗是否开启（车辆状态页逐窗显示、主页车模红点联动用）。
       三代 CS75PLUS 车窗不上报，返回 null 表示"数据不可用"（页面显示 --） */
    function windowOpenAt(d, keys) {
        if (!d) return false;
        if (isWindowUnreportedModel(d)) return null;
        return (keys || []).some(function (k) { return _is1(d[k]); });
    }

    global.CarFields = {
        WIN_SPECIFIC_KEYS: WIN_SPECIFIC_KEYS,
        isWindowUnreportedModel: isWindowUnreportedModel,
        anyWindowOpen: anyWindowOpen,
        windowOpenAt: windowOpenAt
    };
})(window);
