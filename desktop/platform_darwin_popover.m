//go:build darwin

#import <AppKit/AppKit.h>
#import "platform_darwin_popover.h"
#import "platform_darwin_tray.h"

enum {
    FLPopoverActionStart = 1,
    FLPopoverActionPause,
    FLPopoverActionResume,
    FLPopoverActionFinish,
    FLPopoverActionAbort,
    FLPopoverActionRetry,
    FLPopoverToggleName,
    FLPopoverOpenDashboard,
    FLPopoverOpenHistory,
    FLPopoverOpenSettings,
    FLPopoverOpenFeedback,
};

static NSPopover *focusLinkPopover;

static NSStackView *FLStack(NSUserInterfaceLayoutOrientation orientation, CGFloat spacing) {
    NSStackView *stack = [[[NSStackView alloc] init] autorelease];
    stack.orientation = orientation;
    stack.alignment = orientation == NSUserInterfaceLayoutOrientationVertical ? NSLayoutAttributeLeading : NSLayoutAttributeCenterY;
    stack.distribution = NSStackViewDistributionFill;
    stack.spacing = spacing;
    stack.detachesHiddenViews = YES;
    return stack;
}

static NSTextField *FLLabel(NSString *value, NSFont *font, NSColor *color) {
    NSTextField *label = [NSTextField labelWithString:value ?: @""];
    label.font = font;
    label.textColor = color;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.cell.usesSingleLineMode = YES;
    label.cell.wraps = NO;
    return label;
}

static NSDictionary *FLCapability(NSDictionary *state, NSString *action) {
    id value = state[action];
    return [value isKindOfClass:[NSDictionary class]] ? value : @{};
}

static BOOL FLAllowed(NSDictionary *state, NSString *action) {
    return [FLCapability(state, action)[@"allowed"] boolValue];
}

static NSString *FLReason(NSDictionary *state, NSString *action) {
    return FLCapability(state, action)[@"reason"] ?: @"";
}

@interface FocusLinkPopoverViewController () {
    NSTextField *_statusLabel;
    NSTextField *_taskLabel;
    NSTextField *_taskHintLabel;
    NSTextField *_timerLabel;
    NSTextField *_timerHintLabel;
    NSTextField *_balanceLabel;
    NSTextField *_detailLabel;
    NSTextField *_nameField;
    NSButton *_nameToggleButton;
    NSButton *_primaryButton;
    NSButton *_secondaryButton;
    NSButton *_abortButton;
    NSButton *_dashboardButton;
    NSButton *_historyButton;
    NSButton *_settingsButton;
    NSButton *_feedbackButton;
    NSStackView *_timerCard;
    NSStackView *_sessionButtons;
    NSDictionary *_lastState;
    BOOL _busy;
    BOOL _nameEntryExpanded;
}
- (void)buttonPressed:(NSButton *)sender;
- (CGFloat)preferredHeightForState:(NSDictionary *)state;
@end

@implementation FocusLinkPopoverViewController

- (void)loadView {
    NSView *root = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 360, 250)] autorelease];
    NSStackView *stack = FLStack(NSUserInterfaceLayoutOrientationVertical, 10);
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:stack];

    NSStackView *header = FLStack(NSUserInterfaceLayoutOrientationHorizontal, 8);
    NSTextField *brand = FLLabel(@"Focus Link", [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold], NSColor.labelColor);
    _statusLabel = FLLabel(@"作業開始前", [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold], NSColor.secondaryLabelColor);
    [header addArrangedSubview:brand];
    NSView *spacer = [[[NSView alloc] initWithFrame:NSZeroRect] autorelease];
    [spacer setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [header addArrangedSubview:spacer];
    [header addArrangedSubview:_statusLabel];
    [stack addArrangedSubview:header];

    _taskLabel = FLLabel(@"", [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold], NSColor.labelColor);
    [stack addArrangedSubview:_taskLabel];
    _taskHintLabel = FLLabel(@"", [NSFont systemFontOfSize:12], NSColor.secondaryLabelColor);
    [stack addArrangedSubview:_taskHintLabel];

    _nameToggleButton = [self linkButtonWithTitle:@"作業名を追加" tag:FLPopoverToggleName];
    [stack addArrangedSubview:_nameToggleButton];
    _nameField = [[[NSTextField alloc] initWithFrame:NSZeroRect] autorelease];
    _nameField.placeholderString = @"作業名（任意）";
    _nameField.accessibilityLabel = @"作業名（任意）";
    _nameField.font = [NSFont systemFontOfSize:13];
    _nameField.translatesAutoresizingMaskIntoConstraints = NO;
    _nameField.hidden = YES;
    [_nameField.heightAnchor constraintEqualToConstant:32].active = YES;
    [stack addArrangedSubview:_nameField];

    _timerCard = FLStack(NSUserInterfaceLayoutOrientationVertical, 3);
    NSTextField *timerTitle = FLLabel(@"作業時間", [NSFont systemFontOfSize:11], NSColor.secondaryLabelColor);
    _timerLabel = FLLabel(@"0:00:00", [NSFont monospacedDigitSystemFontOfSize:32 weight:NSFontWeightSemibold], NSColor.labelColor);
    _timerHintLabel = FLLabel(@"", [NSFont systemFontOfSize:12], NSColor.secondaryLabelColor);
    [_timerCard addArrangedSubview:timerTitle];
    [_timerCard addArrangedSubview:_timerLabel];
    [_timerCard addArrangedSubview:_timerHintLabel];
    [stack addArrangedSubview:_timerCard];

    _balanceLabel = FLLabel(@"", [NSFont systemFontOfSize:12 weight:NSFontWeightMedium], NSColor.labelColor);
    [stack addArrangedSubview:_balanceLabel];
    _detailLabel = FLLabel(@"", [NSFont systemFontOfSize:12], NSColor.secondaryLabelColor);
    [stack addArrangedSubview:_detailLabel];

    _primaryButton = [self buttonWithTitle:@"開始" tag:FLPopoverActionStart primary:YES];
    [_primaryButton.heightAnchor constraintEqualToConstant:40].active = YES;
    [_primaryButton.widthAnchor constraintEqualToConstant:324].active = YES;
    [stack addArrangedSubview:_primaryButton];

    _sessionButtons = FLStack(NSUserInterfaceLayoutOrientationHorizontal, 8);
    _secondaryButton = [self buttonWithTitle:@"終了" tag:FLPopoverActionFinish primary:NO];
    [_secondaryButton.widthAnchor constraintGreaterThanOrEqualToConstant:100].active = YES;
    [_sessionButtons addArrangedSubview:_secondaryButton];
    _abortButton = [self linkButtonWithTitle:@"中止する" tag:FLPopoverActionAbort];
    _abortButton.contentTintColor = NSColor.systemRedColor;
    [_sessionButtons addArrangedSubview:_abortButton];
    [stack addArrangedSubview:_sessionButtons];

    NSBox *separator = [[[NSBox alloc] initWithFrame:NSZeroRect] autorelease];
    separator.boxType = NSBoxSeparator;
    [stack addArrangedSubview:separator];

    NSStackView *footer = FLStack(NSUserInterfaceLayoutOrientationHorizontal, 10);
    _dashboardButton = [self linkButtonWithTitle:@"ダッシュボード" tag:FLPopoverOpenDashboard];
    _historyButton = [self linkButtonWithTitle:@"記録" tag:FLPopoverOpenHistory];
    _settingsButton = [self linkButtonWithTitle:@"設定" tag:FLPopoverOpenSettings];
    _feedbackButton = [self linkButtonWithTitle:@"結果" tag:FLPopoverOpenFeedback];
    [footer addArrangedSubview:_dashboardButton];
    [footer addArrangedSubview:_historyButton];
    [footer addArrangedSubview:_settingsButton];
    [footer addArrangedSubview:_feedbackButton];
    [stack addArrangedSubview:footer];

    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:18],
        [stack.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-18],
        [stack.topAnchor constraintEqualToAnchor:root.topAnchor constant:14],
        [stack.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-12],
    ]];
    self.view = root;
}

- (NSButton *)buttonWithTitle:(NSString *)title tag:(NSInteger)tag primary:(BOOL)primary {
    NSButton *button = [NSButton buttonWithTitle:title target:self action:@selector(buttonPressed:)];
    button.tag = tag;
    button.bezelStyle = NSBezelStyleRounded;
    button.controlSize = primary ? NSControlSizeLarge : NSControlSizeRegular;
    button.font = [NSFont systemFontOfSize:13 weight:primary ? NSFontWeightSemibold : NSFontWeightMedium];
    if (primary) {
        button.bezelColor = NSColor.controlAccentColor;
        button.contentTintColor = NSColor.whiteColor;
    }
    return button;
}

- (NSButton *)linkButtonWithTitle:(NSString *)title tag:(NSInteger)tag {
    NSButton *button = [NSButton buttonWithTitle:title target:self action:@selector(buttonPressed:)];
    button.tag = tag;
    button.bezelStyle = NSBezelStyleShadowlessSquare;
    button.bordered = NO;
    button.controlSize = NSControlSizeSmall;
    button.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    button.contentTintColor = NSColor.secondaryLabelColor;
    return button;
}

- (CGFloat)preferredHeightForState:(NSDictionary *)state {
    NSString *status = state[@"status"] ?: @"idle";
    if ([status isEqualToString:@"idle"]) {
        CGFloat height = [state[@"detail"] length] ? 250 : 224;
        if (_nameEntryExpanded) height += 42;
        if ([state[@"balance"] length]) height += 22;
        return height;
    }
    if ([status isEqualToString:@"pending"]) return 340;
    return 400;
}

- (void)updateWithState:(NSDictionary *)state {
    NSDictionary *nextState = [state copy];
    [_lastState release];
    _lastState = nextState;

    NSString *status = state[@"status"] ?: @"idle";
    NSString *detail = state[@"detail"] ?: @"";
    BOOL isIdle = [status isEqualToString:@"idle"];
    BOOL isRunning = [status isEqualToString:@"running"];
    BOOL isPaused = [status isEqualToString:@"paused"];
    BOOL isPending = [status isEqualToString:@"pending"];
    BOOL hasTask = [state[@"hasTask"] boolValue];
    BOOL canRetry = FLAllowed(state, @"retry");

    _statusLabel.stringValue = state[@"statusLabel"] ?: @"作業開始前";
    _statusLabel.textColor = isRunning ? NSColor.systemGreenColor : (isPaused || isPending ? NSColor.systemOrangeColor : NSColor.secondaryLabelColor);
    _taskLabel.stringValue = state[@"taskDescription"] ?: @"タスクがありません";
    _taskLabel.toolTip = _taskLabel.stringValue;
    _taskHintLabel.stringValue = state[@"taskHint"] ?: @"";
    _taskHintLabel.hidden = _taskHintLabel.stringValue.length == 0;
    _timerLabel.stringValue = state[@"elapsed"] ?: @"0:00:00";
    _timerHintLabel.stringValue = state[@"timerHint"] ?: @"";
    _timerHintLabel.hidden = _timerHintLabel.stringValue.length == 0;
    _balanceLabel.stringValue = state[@"balance"] ?: @"";
    _balanceLabel.hidden = _balanceLabel.stringValue.length == 0;
    _detailLabel.stringValue = detail;
    _detailLabel.toolTip = detail;
    _detailLabel.hidden = detail.length == 0;

    if (!isIdle) {
        _nameEntryExpanded = NO;
        _nameField.stringValue = @"";
    }
    _nameToggleButton.hidden = !isIdle || !hasTask;
    _nameToggleButton.title = _nameEntryExpanded ? @"作業名を閉じる" : @"作業名を追加";
    _nameField.hidden = !isIdle || !hasTask || !_nameEntryExpanded;
    _timerCard.hidden = isIdle;
    _sessionButtons.hidden = !(isRunning || isPaused);

    if (isIdle) {
        _primaryButton.hidden = NO;
        _primaryButton.title = hasTask ? @"作業を開始" : @"設定を開く";
        _primaryButton.tag = hasTask ? FLPopoverActionStart : FLPopoverOpenSettings;
        _primaryButton.enabled = !_busy && (hasTask ? FLAllowed(state, @"start") : YES);
        _primaryButton.toolTip = hasTask ? FLReason(state, @"start") : @"";
    } else if (isRunning) {
        _primaryButton.hidden = NO;
        _primaryButton.title = @"一時停止";
        _primaryButton.tag = FLPopoverActionPause;
        _primaryButton.enabled = !_busy && FLAllowed(state, @"pause");
        _primaryButton.toolTip = FLReason(state, @"pause");
        _secondaryButton.title = @"終了";
        _secondaryButton.toolTip = FLAllowed(state, @"finish") ? @"" : FLReason(state, @"finish");
        _secondaryButton.tag = FLPopoverActionFinish;
        _secondaryButton.enabled = !_busy && FLAllowed(state, @"finish");
        _abortButton.enabled = !_busy && FLAllowed(state, @"abort");
    } else if (isPaused) {
        _primaryButton.hidden = NO;
        _primaryButton.title = @"作業を再開";
        _primaryButton.tag = FLPopoverActionResume;
        _primaryButton.enabled = !_busy && FLAllowed(state, @"resume");
        _primaryButton.toolTip = FLReason(state, @"resume");
        _secondaryButton.title = @"終了";
        _secondaryButton.toolTip = FLAllowed(state, @"finish") ? @"" : FLReason(state, @"finish");
        _secondaryButton.tag = FLPopoverActionFinish;
        _secondaryButton.enabled = !_busy && FLAllowed(state, @"finish");
        _abortButton.enabled = !_busy && FLAllowed(state, @"abort");
    } else if (isPending) {
        _primaryButton.hidden = !canRetry;
        _primaryButton.title = @"記録を再試行";
        _primaryButton.tag = FLPopoverActionRetry;
        _primaryButton.enabled = !_busy && canRetry;
        _primaryButton.toolTip = FLReason(state, @"retry");
    }

    _dashboardButton.enabled = !_busy;
    _historyButton.enabled = !_busy;
    _settingsButton.enabled = !_busy;
    _feedbackButton.enabled = !_busy && [state[@"hasResult"] boolValue];
    _feedbackButton.hidden = ![state[@"hasResult"] boolValue];
}

- (void)setBusy:(BOOL)busy {
    _busy = busy;
    if (busy) {
        _detailLabel.stringValue = @"処理しています…";
        _detailLabel.hidden = NO;
        _primaryButton.enabled = NO;
        _secondaryButton.enabled = NO;
        _abortButton.enabled = NO;
        _dashboardButton.enabled = NO;
        _historyButton.enabled = NO;
        _settingsButton.enabled = NO;
        _feedbackButton.enabled = NO;
    } else if (_lastState != nil) {
        [self updateWithState:_lastState];
    }
}

- (void)dealloc {
    [_lastState release];
    [super dealloc];
}

- (void)buttonPressed:(NSButton *)sender {
    if (_busy) return;

    switch (sender.tag) {
        case FLPopoverToggleName:
            _nameEntryExpanded = !_nameEntryExpanded;
            _nameToggleButton.title = _nameEntryExpanded ? @"作業名を閉じる" : @"作業名を追加";
            _nameField.hidden = !_nameEntryExpanded;
            if (_nameEntryExpanded) {
                [[self.view window] makeFirstResponder:_nameField];
            }
            if (focusLinkPopover != nil) {
                focusLinkPopover.contentSize = NSMakeSize(360, [self preferredHeightForState:_lastState ?: @{}]);
            }
            return;
        case FLPopoverActionStart:
            FocusLinkDispatchPopoverAction("start", [_nameField.stringValue UTF8String]);
            return;
        case FLPopoverActionPause:
            FocusLinkDispatchPopoverAction("pause", "");
            return;
        case FLPopoverActionResume:
            FocusLinkDispatchPopoverAction("resume", "");
            return;
        case FLPopoverActionFinish:
            FocusLinkDispatchPopoverAction("finish", "");
            return;
        case FLPopoverActionAbort:
            FocusLinkDispatchPopoverAction("abort", "");
            return;
        case FLPopoverActionRetry:
            FocusLinkDispatchPopoverAction("retry", "");
            return;
        case FLPopoverOpenDashboard:
            FocusLinkDispatchOpenPage("session");
            return;
        case FLPopoverOpenHistory:
            FocusLinkDispatchOpenPage("history");
            return;
        case FLPopoverOpenSettings:
            FocusLinkDispatchOpenPage("settings");
            return;
        case FLPopoverOpenFeedback:
            FocusLinkDispatchOpenPage("feedback");
            return;
        default:
            return;
    }
}

@end

static FocusLinkPopoverViewController *focusLinkPopoverViewController;

static void FLUpdatePopoverOnMainThread(NSDictionary *state) {
    if (state == nil || focusLinkPopoverViewController == nil) return;

    // Go の Cgo コールバック中に AppKit のビューを同期更新すると、イベント処理へ再入する。
    NSDictionary *retainedState = [state copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        FocusLinkPopoverViewController *viewController = focusLinkPopoverViewController;
        NSPopover *popover = focusLinkPopover;
        if (viewController != nil) {
            [viewController updateWithState:retainedState];
            CGFloat height = [viewController preferredHeightForState:retainedState];
            if (popover != nil && popover.contentSize.height != height) {
                popover.contentSize = NSMakeSize(360, height);
            }
        }
        [retainedState release];
    });
}

void FocusLinkConfigurePopover(NSPopover *popover) {
    focusLinkPopover = popover;
    focusLinkPopoverViewController = [[FocusLinkPopoverViewController alloc] init];
    popover.contentViewController = focusLinkPopoverViewController;
    // アプリを前面化せずにメニューバーのパネルを見やすく保つ。
    if (@available(macOS 10.14, *)) {
        popover.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    }
    popover.behavior = NSPopoverBehaviorTransient;
    popover.animates = YES;
    popover.contentSize = NSMakeSize(360, 250);
}

void FocusLinkUpdatePopover(const char *stateJSON) {
    if (stateJSON == NULL) return;
    @autoreleasepool {
        NSString *json = [NSString stringWithUTF8String:stateJSON];
        NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
        NSError *error = nil;
        id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        if (error == nil && [parsed isKindOfClass:[NSDictionary class]]) {
            FLUpdatePopoverOnMainThread(parsed);
        }
    }
}

void FocusLinkSetPopoverBusy(int busy) {
    BOOL value = busy != 0;
    dispatch_async(dispatch_get_main_queue(), ^{
        FocusLinkPopoverViewController *viewController = focusLinkPopoverViewController;
        [viewController setBusy:value];
    });
}
