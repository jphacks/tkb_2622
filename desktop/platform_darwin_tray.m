//go:build darwin

#import <AppKit/AppKit.h>

#include "platform_darwin_tray.h"

extern void FocusLinkShowWindow(void);
extern void FocusLinkQuit(void);

@interface FocusLinkStatusController : NSObject {
    NSStatusItem *_statusItem;
    NSMenu *_menu;
}

- (void)installStatusItem;
- (void)removeStatusItem;
- (void)statusItemPressed:(id)sender;
- (void)showWindow:(id)sender;
- (void)quitApplication:(id)sender;

@end

static FocusLinkStatusController *focusLinkStatusController;

@implementation FocusLinkStatusController

- (void)installStatusItem {
    if (_statusItem != nil) {
        return;
    }

    _statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
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
    button.toolTip = @"Focus Link（クリックで表示、右クリックでメニュー）";
    button.target = self;
    button.action = @selector(statusItemPressed:);
    [button sendActionOn:NSEventMaskLeftMouseUp | NSEventMaskRightMouseUp];

    _menu = [[NSMenu alloc] initWithTitle:@"Focus Link"];
    NSMenuItem *showItem = [_menu addItemWithTitle:@"表示" action:@selector(showWindow:) keyEquivalent:@""];
    showItem.target = self;
    [_menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *quitItem = [_menu addItemWithTitle:@"終了" action:@selector(quitApplication:) keyEquivalent:@""];
    quitItem.target = self;
}

- (void)removeStatusItem {
    if (_statusItem != nil) {
        [[NSStatusBar systemStatusBar] removeStatusItem:_statusItem];
        _statusItem = nil;
    }
}

- (void)statusItemPressed:(id)sender {
    NSEvent *event = [NSApp currentEvent];
    if (event.type == NSEventTypeRightMouseUp) {
        [NSMenu popUpContextMenu:_menu withEvent:event forView:_statusItem.button];
        return;
    }
    FocusLinkShowWindow();
}

- (void)showWindow:(id)sender {
    FocusLinkShowWindow();
}

- (void)quitApplication:(id)sender {
    FocusLinkQuit();
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
        [focusLinkStatusController performSelectorOnMainThread:@selector(installStatusItem) withObject:nil waitUntilDone:NO];
    }
}
