//go:build darwin

#import <AppKit/AppKit.h>
#include <stdlib.h>
#include <string.h>

#include "platform_darwin_tray.h"
#include "platform_darwin_popover.h"

extern void FocusLinkShowPopover(void);
extern void FocusLinkPopoverAction(char *action, char *name);
extern void FocusLinkOpenPage(char *page);
extern void FocusLinkQuit(void);

@interface FocusLinkStatusController : NSObject {
    NSStatusItem *_statusItem;
    NSMenu *_menu;
    NSPanel *_statusPanel;
    id _outsideClickMonitor;
}

- (void)installStatusItem;
- (void)removeStatusItem;
- (void)statusItemPressed:(id)sender;
- (void)showWindow:(id)sender;
- (void)presentStatusPanel;
- (void)closeStatusPanel;
- (void)closeStatusPanelForOutsideClick;
- (void)quitApplication:(id)sender;

@end

@interface FLStatusPanel : NSPanel
@end

@implementation FLStatusPanel

- (BOOL)canBecomeKeyWindow {
    return YES;
}

- (BOOL)canBecomeMainWindow {
    return NO;
}

- (void)cancelOperation:(id)sender {
    [self orderOut:sender];
}

@end

static FocusLinkStatusController *focusLinkStatusController;

@implementation FocusLinkStatusController

- (void)installStatusItem {
    if (_statusItem != nil) {
        return;
    }

    // 通常のDockアプリではなく、メニューバー常駐アプリとして起動する。
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    _statusItem = [[[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength] retain];
    if (_statusItem == nil) {
        return;
    }

    NSStatusBarButton *button = _statusItem.button;
    NSImage *image = nil;
    if (@available(macOS 11.0, *)) {
        image = [NSImage imageWithSystemSymbolName:@"timer" accessibilityDescription:@"Focus Link"];
    }
    if (image != nil) {
        image.template = YES;
        button.image = image;
    } else {
        button.title = @"FL";
    }
    button.toolTip = @"Focus Link（クリックで作業を開始・操作）";
    button.target = self;
    button.action = @selector(statusItemPressed:);
    [button sendActionOn:NSEventMaskLeftMouseUp | NSEventMaskRightMouseUp];

    _menu = [[NSMenu alloc] initWithTitle:@"Focus Link"];
    NSMenuItem *showItem = [_menu addItemWithTitle:@"ダッシュボードを開く" action:@selector(showWindow:) keyEquivalent:@""];
    showItem.target = self;
    [_menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *quitItem = [_menu addItemWithTitle:@"終了" action:@selector(quitApplication:) keyEquivalent:@""];
    quitItem.target = self;

    _statusPanel = [[FLStatusPanel alloc] initWithContentRect:NSMakeRect(0, 0, 320, 220)
                                                    styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                                      backing:NSBackingStoreBuffered
                                                        defer:NO];
    FocusLinkConfigureStatusPanel(_statusPanel);
    _outsideClickMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:(NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown | NSEventMaskOtherMouseDown) handler:^(NSEvent *event) {
        if (event == nil) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            [focusLinkStatusController closeStatusPanelForOutsideClick];
        });
    }];
}

- (void)removeStatusItem {
    if (_outsideClickMonitor != nil) {
        [NSEvent removeMonitor:_outsideClickMonitor];
        _outsideClickMonitor = nil;
    }
    if (_statusItem != nil) {
        [[NSStatusBar systemStatusBar] removeStatusItem:_statusItem];
        [_statusItem release];
        _statusItem = nil;
    }
    [_statusPanel orderOut:nil];
    [_statusPanel release];
    _statusPanel = nil;
}

- (void)statusItemPressed:(id)sender {
    NSEvent *event = [NSApp currentEvent];
    if (event.type == NSEventTypeRightMouseUp) {
        [self closeStatusPanel];
        [NSMenu popUpContextMenu:_menu withEvent:event forView:_statusItem.button];
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        @autoreleasepool {
            FocusLinkShowPopover();
        }
    });
}

- (void)showWindow:(id)sender {
    [self closeStatusPanel];
    FocusLinkDispatchOpenPage("session");
}

- (void)presentStatusPanel {
    if (_statusItem == nil || _statusItem.button == nil || _statusPanel == nil) {
        return;
    }
    if (_statusPanel.isVisible) {
        [_statusPanel orderOut:nil];
        return;
    }

    NSStatusBarButton *button = _statusItem.button;
    NSScreen *screen = button.window.screen ?: NSScreen.mainScreen;
    if (screen == nil) {
        return;
    }

    NSRect buttonRect = [button convertRect:button.bounds toView:nil];
    buttonRect = [button.window convertRectToScreen:buttonRect];
    NSRect visibleFrame = screen.visibleFrame;
    NSSize panelSize = _statusPanel.frame.size;
    CGFloat minX = NSMinX(visibleFrame) + 8;
    CGFloat maxX = NSMaxX(visibleFrame) - panelSize.width - 8;
    if (maxX < minX) maxX = minX;
    CGFloat originX = MIN(MAX(NSMidX(buttonRect) - panelSize.width / 2, minX), maxX);
    CGFloat originY = NSMaxY(visibleFrame) - panelSize.height - 4;
    [_statusPanel setFrameOrigin:NSMakePoint(originX, originY)];
    [_statusPanel makeKeyAndOrderFront:nil];
}

- (void)closeStatusPanel {
    [_statusPanel orderOut:nil];
}

- (void)closeStatusPanelForOutsideClick {
    if (_statusPanel.isVisible) {
        [_statusPanel orderOut:nil];
    }
}

- (void)quitApplication:(id)sender {
    FocusLinkDispatchQuit();
}

- (void)dealloc {
    [self removeStatusItem];
    [_menu release];
    [super dealloc];
}

@end

void FocusLinkInstallStatusItem(void) {
    @autoreleasepool {
        if (focusLinkStatusController == nil) {
            focusLinkStatusController = [[FocusLinkStatusController alloc] init];
        }
        [focusLinkStatusController performSelectorOnMainThread:@selector(installStatusItem) withObject:nil waitUntilDone:YES];
    }
}

void FocusLinkPresentPopover(void) {
    @autoreleasepool {
        [focusLinkStatusController performSelectorOnMainThread:@selector(presentStatusPanel) withObject:nil waitUntilDone:NO];
    }
}

void FocusLinkClosePopover(void) {
    @autoreleasepool {
        [focusLinkStatusController performSelectorOnMainThread:@selector(closeStatusPanel) withObject:nil waitUntilDone:NO];
    }
}

void FocusLinkDispatchPopoverAction(const char *action, const char *name) {
    if (action == NULL || name == NULL) return;
    char *actionCopy = strdup(action);
    char *nameCopy = strdup(name);
    if (actionCopy == NULL || nameCopy == NULL) {
        free(actionCopy);
        free(nameCopy);
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        @autoreleasepool {
            FocusLinkPopoverAction(actionCopy, nameCopy);
        }
        free(actionCopy);
        free(nameCopy);
    });
}

void FocusLinkDispatchOpenPage(const char *page) {
    if (page == NULL) return;
    char *pageCopy = strdup(page);
    if (pageCopy == NULL) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        @autoreleasepool {
            FocusLinkOpenPage(pageCopy);
        }
        free(pageCopy);
    });
}

void FocusLinkDispatchQuit(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        @autoreleasepool {
            FocusLinkQuit();
        }
    });
}
