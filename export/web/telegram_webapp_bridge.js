/**
 * Telegram WebApp Bridge for Godot
 * 提供 JavaScript 与 Godot 之间的通信接口
 */

(function() {
    'use strict';
    
    // 桥接对象
    window.godotTelegramBridge = {
        // 是否处于 Telegram WebApp 环境
        isTelegram: false,
        
        // Godot 实例引用
        godotInstance: null,
        
        // 初始化
        init: function() {
            this.isTelegram = (window.Telegram && Telegram.WebApp) ? true : false;
            
            if (this.isTelegram) {
                console.log('[TelegramBridge] Telegram WebApp detected');
                this.setupTelegramUI();
            } else {
                console.log('[TelegramBridge] Running in standard browser');
            }
            
            // 尝试获取 Godot 实例
            if (typeof engine !== 'undefined') {
                this.godotInstance = engine;
            }
        },
        
        // 设置 Telegram UI
        setupTelegramUI: function() {
            const tg = Telegram.WebApp;
            
            // 显示返回按钮
            tg.BackButton.show();
            tg.BackButton.onClick(function() {
                window.history.back();
            });
            
            // 设置主按钮（默认隐藏，由 Godot 控制）
            tg.MainButton.hide();
            tg.MainButton.setText('继续');
            
            // 主按钮点击事件
            tg.MainButton.onClick(function() {
                if (window.godotTelegramBridge.onMainButtonClick) {
                    window.godotTelegramBridge.onMainButtonClick();
                }
            });
        },
        
        // ========== Godot 可调用的方法 ==========
        
        // 显示主按钮
        showMainButton: function(text) {
            if (!this.isTelegram) return;
            const tg = Telegram.WebApp;
            if (text) tg.MainButton.setText(text);
            tg.MainButton.show();
        },
        
        // 隐藏主按钮
        hideMainButton: function() {
            if (!this.isTelegram) return;
            Telegram.WebApp.MainButton.hide();
        },
        
        // 设置主按钮加载状态
        setMainButtonLoading: function(loading) {
            if (!this.isTelegram) return;
            if (loading) {
                Telegram.WebApp.MainButton.showProgress();
            } else {
                Telegram.WebApp.MainButton.hideProgress();
            }
        },
        
        // 启用/禁用主按钮
        setMainButtonEnabled: function(enabled) {
            if (!this.isTelegram) return;
            if (enabled) {
                Telegram.WebApp.MainButton.enable();
            } else {
                Telegram.WebApp.MainButton.disable();
            }
        },
        
        // 触发震动反馈
        hapticFeedback: function(type) {
            if (!this.isTelegram) return;
            type = type || 'light';
            
            const tg = Telegram.WebApp;
            if (tg.HapticFeedback) {
                switch(type) {
                    case 'light':
                        tg.HapticFeedback.impactOccurred('light');
                        break;
                    case 'medium':
                        tg.HapticFeedback.impactOccurred('medium');
                        break;
                    case 'heavy':
                        tg.HapticFeedback.impactOccurred('heavy');
                        break;
                    case 'success':
                        tg.HapticFeedback.notificationOccurred('success');
                        break;
                    case 'error':
                        tg.HapticFeedback.notificationOccurred('error');
                        break;
                    case 'warning':
                        tg.HapticFeedback.notificationOccurred('warning');
                        break;
                    case 'selection':
                        tg.HapticFeedback.selectionChanged();
                        break;
                }
            }
        },
        
        // 显示弹窗
        showPopup: function(title, message, buttons) {
            if (!this.isTelegram) {
                alert(message);
                return;
            }
            
            const params = {
                title: title || '提示',
                message: message,
                buttons: buttons || [{type: 'ok'}]
            };
            
            Telegram.WebApp.showPopup(params, function(buttonId) {
                if (window.godotTelegramBridge.onPopupClosed) {
                    window.godotTelegramBridge.onPopupClosed(buttonId);
                }
            });
        },
        
        // 显示确认对话框
        showConfirm: function(message) {
            if (!this.isTelegram) {
                return confirm(message);
            }
            
            Telegram.WebApp.showConfirm(message, function(confirmed) {
                if (window.godotTelegramBridge.onConfirmResult) {
                    window.godotTelegramBridge.onConfirmResult(confirmed);
                }
            });
        },
        
        // 显示警告
        showAlert: function(message) {
            if (!this.isTelegram) {
                alert(message);
                return;
            }
            
            Telegram.WebApp.showAlert(message, function() {
                if (window.godotTelegramBridge.onAlertClosed) {
                    window.godotTelegramBridge.onAlertClosed();
                }
            });
        },
        
        // 设置头部颜色
        setHeaderColor: function(color) {
            if (!this.isTelegram) return;
            Telegram.WebApp.setHeaderColor(color);
        },
        
        // 设置背景颜色
        setBackgroundColor: function(color) {
            if (!this.isTelegram) return;
            Telegram.WebApp.setBackgroundColor(color);
        },
        
        // 打开链接
        openLink: function(url) {
            if (!this.isTelegram) {
                window.open(url, '_blank');
                return;
            }
            Telegram.WebApp.openLink(url);
        },
        
        // 打开 Telegram 链接
        openTelegramLink: function(url) {
            if (!this.isTelegram) {
                window.open(url, '_blank');
                return;
            }
            Telegram.WebApp.openTelegramLink(url);
        },
        
        // 关闭 WebApp
        close: function() {
            if (!this.isTelegram) return;
            Telegram.WebApp.close();
        },
        
        // 获取启动参数
        getInitData: function() {
            if (!this.isTelegram) return '';
            return Telegram.WebApp.initData || '';
        },
        
        // 获取用户信息
        getUserInfo: function() {
            if (!this.isTelegram) return null;
            return Telegram.WebApp.initDataUnsafe?.user || null;
        },
        
        // 获取主题参数
        getThemeParams: function() {
            if (!this.isTelegram) return {};
            return Telegram.WebApp.themeParams || {};
        },
        
        // 获取颜色方案
        getColorScheme: function() {
            if (!this.isTelegram) return 'dark';
            return Telegram.WebApp.colorScheme || 'dark';
        },
        
        // 发送数据到 Bot
        sendData: function(data) {
            if (!this.isTelegram) {
                console.log('[TelegramBridge] SendData:', data);
                return;
            }
            Telegram.WebApp.sendData(data);
        },
        
        // ========== 事件回调（由 Godot 设置） ==========
        
        // 主题变化回调
        onThemeChanged: function(scheme) {
            console.log('[TelegramBridge] Theme changed:', scheme);
            // 通过 Godot 的 JavaScriptBridge 通知 Godot
            if (this.godotInstance && this.godotInstance.sendNotification) {
                this.godotInstance.sendNotification('theme_changed', scheme);
            }
        },
        
        // 视口变化回调
        onViewportChanged: function() {
            console.log('[TelegramBridge] Viewport changed');
            if (this.godotInstance && this.godotInstance.sendNotification) {
                this.godotInstance.sendNotification('viewport_changed');
            }
        },
        
        // 尺寸变化回调
        onResize: function(width, height) {
            if (this.godotInstance && this.godotInstance.sendNotification) {
                this.godotInstance.sendNotification('window_resized', {width: width, height: height});
            }
        },
        
        // 可见性变化回调
        onVisibilityChange: function(visible) {
            console.log('[TelegramBridge] Visibility:', visible);
            if (this.godotInstance && this.godotInstance.sendNotification) {
                this.godotInstance.sendNotification('visibility_changed', visible);
            }
        },
        
        // 主按钮点击回调（由 Godot 设置）
        onMainButtonClick: null,
        
        // 弹窗关闭回调（由 Godot 设置）
        onPopupClosed: null,
        
        // 确认结果回调（由 Godot 设置）
        onConfirmResult: null,
        
        // 警告关闭回调（由 Godot 设置）
        onAlertClosed: null
    };
    
    // 页面加载完成后初始化
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', function() {
            window.godotTelegramBridge.init();
        });
    } else {
        window.godotTelegramBridge.init();
    }
    
})();
