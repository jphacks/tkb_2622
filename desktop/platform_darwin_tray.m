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
    NSPopover *_popover;
    id _outsideClickMonitor;
}

- (void)installStatusItem;
- (void)removeStatusItem;
- (void)statusItemPressed:(id)sender;
- (void)showWindow:(id)sender;
- (void)presentPopover;
- (void)closePopover;
- (void)closePopoverForOutsideClick;
- (void)quitApplication:(id)sender;

@end

static FocusLinkStatusController *focusLinkStatusController;

@implementation FocusLinkStatusController

- (void)installStatusItem {
    if (_statusItem != nil) {
        return;
    }

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

    _popover = [[NSPopover alloc] init];
    FocusLinkConfigurePopover(_popover);
    _outsideClickMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:(NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown | NSEventMaskOtherMouseDown) handler:^(NSEvent *event) {
        if (event == nil) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            [focusLinkStatusController closePopoverForOutsideClick];
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
    [_popover close];
    [_popover release];
    _popover = nil;
}

- (void)statusItemPressed:(id)sender {
    NSEvent *event = [NSApp currentEvent];
    if (event.type == NSEventTypeRightMouseUp) {
        [self closePopover];
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
    [self closePopover];
    FocusLinkDispatchOpenPage("session");
}

- (void)presentPopover {
    if (_statusItem == nil || _statusItem.button == nil || _popover == nil) {
        return;
    }
    if (_popover.isShown) {
        [_popover close];
        return;
    }
    [_popover showRelativeToRect:_statusItem.button.bounds ofView:_statusItem.button preferredEdge:NSMinYEdge];
}

- (void)closePopover {
    [_popover close];
}

- (void)closePopoverForOutsideClick {
    if (_popover.isShown) {
        [_popover close];
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
        [focusLinkStatusController performSelectorOnMainThread:@selector(presentPopover) withObject:nil waitUntilDone:NO];
    }
}

void FocusLinkClosePopover(void) {
    @autoreleasepool {
        [focusLinkStatusController performSelectorOnMainThread:@selector(closePopover) withObject:nil waitUntilDone:NO];
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
