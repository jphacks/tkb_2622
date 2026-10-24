//go:build darwin

#import <AppKit/AppKit.h>
#import "platform_darwin_popover.h"

extern void FocusLinkPopoverAction(char *action, char *name);
extern void FocusLinkOpenPage(char *page);

enum {
    FLPopoverActionStart = 1,
    FLPopoverActionPause,
    FLPopoverActionResume,
    FLPopoverActionFinish,
    FLPopoverActionAbort,
    FLPopoverActionRetry,
    FLPopoverOpenDashboard,
    FLPopoverOpenHistory,
    FLPopoverOpenSettings,
    FLPopoverOpenFeedback,
};

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
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.cell.wraps = YES;
    label.cell.usesSingleLineMode = NO;
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
    NSTextField *_timerLabel;
    NSTextField *_timerHintLabel;
    NSTextField *_balanceLabel;
    NSTextField *_detailLabel;
    NSTextField *_nameField;
    NSButton *_primaryButton;
    NSButton *_secondaryButton;
    NSButton *_abortButton;
    NSButton *_dashboardButton;
    NSButton *_historyButton;
    NSButton *_settingsButton;
    NSButton *_feedbackButton;
    NSDictionary *_lastState;
    BOOL _busy;
}
- (void)buttonPressed:(NSButton *)sender;
@end

@implementation FocusLinkPopoverViewController

- (void)loadView {
    NSVisualEffectView *root = [[[NSVisualEffectView alloc] initWithFrame:NSMakeRect(0, 0, 360, 470)] autorelease];
    root.material = NSVisualEffectMaterialPopover;
    root.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    root.state = NSVisualEffectStateFollowsWindowActiveState;

    NSStackView *stack = FLStack(NSUserInterfaceLayoutOrientationVertical, 12);
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:stack];

    NSStackView *header = FLStack(NSUserInterfaceLayoutOrientationHorizontal, 8);
    NSTextField *brand = FLLabel(@"Focus Link", [NSFont systemFontOfSize:16 weight:NSFontWeightSemibold], NSColor.labelColor);
    _statusLabel = FLLabel(@"作業開始前", [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold], NSColor.secondaryLabelColor);
    [header addArrangedSubview:brand];
    NSView *spacer = [[[NSView alloc] initWithFrame:NSZeroRect] autorelease];
    [spacer setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [header addArrangedSubview:spacer];
    [header addArrangedSubview:_statusLabel];
    [stack addArrangedSubview:header];

    _taskLabel = FLLabel(@"", [NSFont systemFontOfSize:13 weight:NSFontWeightMedium], NSColor.secondaryLabelColor);
    [stack addArrangedSubview:_taskLabel];

    _nameField = [[[NSTextField alloc] initWithFrame:NSZeroRect] autorelease];
    _nameField.placeholderString = @"作業名（任意）";
    _nameField.accessibilityLabel = @"作業名（任意）";
    _nameField.translatesAutoresizingMaskIntoConstraints = NO;
    [_nameField.heightAnchor constraintEqualToConstant:34].active = YES;
    [stack addArrangedSubview:_nameField];

    NSStackView *timerCard = FLStack(NSUserInterfaceLayoutOrientationVertical, 4);
    timerCard.edgeInsets = NSEdgeInsetsMake(12, 14, 12, 14);
    timerCard.wantsLayer = YES;
    timerCard.layer.backgroundColor = [NSColor colorWithSRGBRed:0.95 green:0.94 blue:1.0 alpha:1.0].CGColor;
    timerCard.layer.cornerRadius = 12;
    NSTextField *timerTitle = FLLabel(@"計測時間（一時停止を除く）", [NSFont systemFontOfSize:11], NSColor.secondaryLabelColor);
    _timerLabel = FLLabel(@"0:00:00", [NSFont monospacedDigitSystemFontOfSize:34 weight:NSFontWeightSemibold], NSColor.labelColor);
    _timerHintLabel = FLLabel(@"", [NSFont systemFontOfSize:12], NSColor.secondaryLabelColor);
    [timerCard addArrangedSubview:timerTitle];
    [timerCard addArrangedSubview:_timerLabel];
    [timerCard addArrangedSubview:_timerHintLabel];
    [stack addArrangedSubview:timerCard];

    _balanceLabel = FLLabel(@"", [NSFont systemFontOfSize:12 weight:NSFontWeightMedium], NSColor.secondaryLabelColor);
    [stack addArrangedSubview:_balanceLabel];

    _detailLabel = FLLabel(@"", [NSFont systemFontOfSize:12], NSColor.secondaryLabelColor);
    [stack addArrangedSubview:_detailLabel];

    _primaryButton = [self buttonWithTitle:@"開始" tag:FLPopoverActionStart primary:YES];
    [_primaryButton.heightAnchor constraintEqualToConstant:42].active = YES;
    [stack addArrangedSubview:_primaryButton];

    NSStackView *sessionButtons = FLStack(NSUserInterfaceLayoutOrientationHorizontal, 8);
    _secondaryButton = [self buttonWithTitle:@"終了" tag:FLPopoverActionFinish primary:NO];
    [_secondaryButton.widthAnchor constraintGreaterThanOrEqualToConstant:140].active = YES;
    [sessionButtons addArrangedSubview:_secondaryButton];
    _abortButton = [self buttonWithTitle:@"中止する" tag:FLPopoverActionAbort primary:NO];
    _abortButton.contentTintColor = NSColor.systemRedColor;
    [sessionButtons addArrangedSubview:_abortButton];
    [stack addArrangedSubview:sessionButtons];

    NSBox *separator = [[[NSBox alloc] initWithFrame:NSZeroRect] autorelease];
    separator.boxType = NSBoxSeparator;
    [stack addArrangedSubview:separator];

    NSStackView *footer = FLStack(NSUserInterfaceLayoutOrientationHorizontal, 16);
    _historyButton = [self linkButtonWithTitle:@"これまでの記録" tag:FLPopoverOpenHistory];
    _settingsButton = [self linkButtonWithTitle:@"設定" tag:FLPopoverOpenSettings];
    _feedbackButton = [self linkButtonWithTitle:@"結果" tag:FLPopoverOpenFeedback];
    _dashboardButton = [self linkButtonWithTitle:@"ダッシュボード" tag:FLPopoverOpenDashboard];
    [footer addArrangedSubview:_dashboardButton];
    [footer addArrangedSubview:_historyButton];
    [footer addArrangedSubview:_settingsButton];
    [footer addArrangedSubview:_feedbackButton];
    [stack addArrangedSubview:footer];

    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-20],
        [stack.topAnchor constraintEqualToAnchor:root.topAnchor constant:18],
        [stack.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-16],
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
        button.contentTintColor = NSColor.controlAccentColor;
    }
    return button;
}

- (NSButton *)linkButtonWithTitle:(NSString *)title tag:(NSInteger)tag {
    NSButton *button = [NSButton buttonWithTitle:title target:self action:@selector(buttonPressed:)];
    button.tag = tag;
    button.bezelStyle = NSBezelStyleInline;
    button.controlSize = NSControlSizeSmall;
    button.contentTintColor = NSColor.controlAccentColor;
    return button;
}

- (void)updateWithState:(NSDictionary *)state {
    [_lastState release];
    _lastState = [state copy];
    NSString *status = state[@"status"] ?: @"idle";
    NSString *statusLabel = state[@"statusLabel"] ?: @"作業開始前";
    _statusLabel.stringValue = statusLabel;
    _taskLabel.stringValue = state[@"taskDescription"] ?: @"タスクが設定されていません";
    _timerLabel.stringValue = state[@"elapsed"] ?: @"0:00:00";
    _timerHintLabel.stringValue = state[@"timerHint"] ?: @"";
    _balanceLabel.stringValue = state[@"balance"] ?: @"";
    _detailLabel.stringValue = state[@"detail"] ?: @"";

    BOOL isIdle = [status isEqualToString:@"idle"];
    BOOL isRunning = [status isEqualToString:@"running"];
    BOOL isPaused = [status isEqualToString:@"paused"];
    BOOL isPending = [status isEqualToString:@"pending"];
    BOOL hasTask = [state[@"hasTask"] boolValue];
    _nameField.hidden = !isIdle || !hasTask;
    if (!isIdle) {
        _nameField.stringValue = @"";
    }
    _timerLabel.hidden = isIdle;
    _timerHintLabel.hidden = isIdle || ![state[@"timerHint"] length];
    _balanceLabel.hidden = ![state[@"balance"] length];

    if (isIdle) {
        _primaryButton.title = hasTask ? @"開始" : @"設定を開く";
        _primaryButton.tag = hasTask ? FLPopoverActionStart : FLPopoverOpenSettings;
        _primaryButton.enabled = !_busy && (hasTask ? FLAllowed(state, @"start") : YES);
        _primaryButton.toolTip = FLReason(state, @"start");
        _secondaryButton.hidden = YES;
        _abortButton.hidden = YES;
    } else if (isRunning) {
        _primaryButton.title = @"一時停止";
        _primaryButton.tag = FLPopoverActionPause;
        _primaryButton.enabled = !_busy && FLAllowed(state, @"pause");
        _primaryButton.toolTip = FLReason(state, @"pause");
        _secondaryButton.title = @"終了";
        _secondaryButton.toolTip = FLAllowed(state, @"finish") ? @"" : (FLReason(state, @"finish").length ? FLReason(state, @"finish") : @"終了できません");
        _secondaryButton.tag = FLPopoverActionFinish;
        _secondaryButton.enabled = !_busy && FLAllowed(state, @"finish");
        _secondaryButton.hidden = NO;
        _abortButton.hidden = NO;
        _abortButton.enabled = !_busy && FLAllowed(state, @"abort");
    } else if (isPaused) {
        _primaryButton.title = @"作業を再開する";
        _primaryButton.tag = FLPopoverActionResume;
        _primaryButton.enabled = !_busy && FLAllowed(state, @"resume");
        _primaryButton.toolTip = FLReason(state, @"resume");
        _secondaryButton.title = @"終了する";
        _secondaryButton.toolTip = FLAllowed(state, @"finish") ? @"" : (FLReason(state, @"finish").length ? FLReason(state, @"finish") : @"終了できません");
        _secondaryButton.tag = FLPopoverActionFinish;
        _secondaryButton.enabled = !_busy && FLAllowed(state, @"finish");
        _secondaryButton.hidden = NO;
        _abortButton.hidden = NO;
        _abortButton.enabled = !_busy && FLAllowed(state, @"abort");
    } else if (isPending) {
        _primaryButton.title = FLAllowed(state, @"retry") ? @"記録を同期して結果を表示" : @"同期を待っています";
        _primaryButton.tag = FLPopoverActionRetry;
        _primaryButton.enabled = !_busy && FLAllowed(state, @"retry");
        _primaryButton.toolTip = FLReason(state, @"retry");
        _secondaryButton.hidden = YES;
        _abortButton.hidden = YES;
    } else {
        _primaryButton.title = @"開始";
        _primaryButton.tag = FLPopoverActionStart;
        _primaryButton.enabled = !_busy && FLAllowed(state, @"start");
        _primaryButton.toolTip = FLReason(state, @"start");
        _secondaryButton.hidden = YES;
        _abortButton.hidden = YES;
    }

    if (_busy) {
        _detailLabel.stringValue = @"処理しています…";
    }
    _historyButton.enabled = !_busy;
    _settingsButton.enabled = !_busy;
    _dashboardButton.enabled = !_busy;
    _feedbackButton.enabled = !_busy && [state[@"hasResult"] boolValue];
}

- (void)setBusy:(BOOL)busy {
    _busy = busy;
    if (busy) {
        _detailLabel.stringValue = @"処理しています…";
        _primaryButton.enabled = NO;
        _secondaryButton.enabled = NO;
        _abortButton.enabled = NO;
    } else if (_lastState != nil) {
        [self updateWithState:_lastState];
    }
}

- (void)dealloc {
    [_lastState release];
    [super dealloc];
}

- (void)buttonPressed:(NSButton *)sender {
    if (_busy) {
        return;
    }
    switch (sender.tag) {
        case FLPopoverActionStart:
            FocusLinkPopoverAction("start", (char *)[_nameField.stringValue UTF8String]);
            return;
        case FLPopoverActionPause:
            FocusLinkPopoverAction("pause", "");
            return;
        case FLPopoverActionResume:
            FocusLinkPopoverAction("resume", "");
            return;
        case FLPopoverActionFinish:
            FocusLinkPopoverAction("finish", "");
            return;
        case FLPopoverActionAbort:
            FocusLinkPopoverAction("abort", "");
            return;
        case FLPopoverActionRetry:
            FocusLinkPopoverAction("retry", "");
            return;
        case FLPopoverOpenHistory:
            FocusLinkOpenPage("history");
            return;
        case FLPopoverOpenDashboard:
            FocusLinkOpenPage("session");
            return;
        case FLPopoverOpenSettings:
            FocusLinkOpenPage("settings");
            return;
        case FLPopoverOpenFeedback:
            FocusLinkOpenPage("feedback");
            return;
        default:
            return;
    }
}

@end

static FocusLinkPopoverViewController *focusLinkPopoverViewController;
static NSPopover *focusLinkPopover;

static void FLUpdatePopoverOnMainThread(NSDictionary *state) {
    if (focusLinkPopoverViewController == nil) {
        return;
    }
    if ([NSThread isMainThread]) {
        [focusLinkPopoverViewController updateWithState:state];
        NSString *status = state[@"status"] ?: @"idle";
        CGFloat height = [status isEqualToString:@"idle"] ? 300 : ([status isEqualToString:@"pending"] ? 370 : 470);
        if (focusLinkPopover != nil && focusLinkPopover.contentSize.height != height) {
            focusLinkPopover.contentSize = NSMakeSize(360, height);
        }
        return;
    }
    NSDictionary *retainedState = [state retain];
    dispatch_async(dispatch_get_main_queue(), ^{
        [focusLinkPopoverViewController updateWithState:retainedState];
        NSString *status = retainedState[@"status"] ?: @"idle";
        CGFloat height = [status isEqualToString:@"idle"] ? 300 : ([status isEqualToString:@"pending"] ? 370 : 470);
        if (focusLinkPopover != nil && focusLinkPopover.contentSize.height != height) {
            focusLinkPopover.contentSize = NSMakeSize(360, height);
        }
        [retainedState release];
    });
}

void FocusLinkConfigurePopover(NSPopover *popover) {
    focusLinkPopover = popover;
    focusLinkPopoverViewController = [[FocusLinkPopoverViewController alloc] init];
    popover.contentViewController = focusLinkPopoverViewController;
    popover.behavior = NSPopoverBehaviorTransient;
    popover.animates = YES;
    popover.contentSize = NSMakeSize(360, 470);
}

void FocusLinkUpdatePopover(const char *stateJSON) {
    if (stateJSON == NULL) {
        return;
    }
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
    if (focusLinkPopoverViewController == nil) {
        return;
    }
    BOOL value = busy != 0;
    if ([NSThread isMainThread]) {
        [focusLinkPopoverViewController setBusy:value];
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [focusLinkPopoverViewController setBusy:value];
    });
}
